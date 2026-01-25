# MacViber Architecture Documentation

## Overview

MacViber는 **MVVM + Clean Architecture** 패턴을 따르는 macOS 터미널 관리 앱입니다.  
크로스 플랫폼 지원을 위해 핵심 로직을 **Rust FFI**로 분리하고 있습니다.

---

## Directory Structure

```
MacViber/
├── Backend/                          # 비즈니스 로직 (플랫폼 독립적)
│   ├── Core/                         # 핵심 기능 구현
│   │   ├── Terminal/                 # 터미널 프로세스 관리
│   │   │   ├── TerminalController.swift
│   │   │   └── TerminalConfiguration.swift
│   │   ├── Parser/                   # 출력 분석 및 알림 감지
│   │   │   ├── ClaudeNotificationDetector.swift
│   │   │   └── CustomPatternMatcher.swift
│   │   └── Logger.swift
│   ├── Domain/                       # 도메인 모델 및 서비스
│   │   ├── Models/                   # 데이터 모델
│   │   │   ├── TerminalSession.swift
│   │   │   ├── SplitNode.swift
│   │   │   ├── ClaudeNotification.swift
│   │   │   └── ...
│   │   └── Services/                 # 비즈니스 서비스
│   │       ├── SessionManager.swift
│   │       ├── ThemeManager.swift
│   │       └── ...
│   └── FFI/                          # Rust FFI 래퍼
│       └── RustCore.swift
├── UI/                               # SwiftUI 프레젠테이션 레이어
│   ├── App/
│   │   └── MacViberApp.swift         # 앱 엔트리 포인트
│   └── Presentation/
│       ├── ViewModels/               # MVVM ViewModel
│       │   ├── MainViewModel.swift
│       │   ├── TerminalListViewModel.swift
│       │   └── ...
│       └── Views/                    # SwiftUI Views
│           ├── MainView.swift
│           ├── Terminal/
│           ├── Sidebar/
│           └── ...
└── Resources/

core/                                 # Rust 백엔드 (크로스 플랫폼)
├── src/
│   ├── lib.rs                        # Core 구조체
│   ├── ffi.rs                        # C ABI FFI 레이어
│   ├── models/
│   ├── services/
│   └── terminal/
└── include/
    └── macviber_core.h               # 자동 생성 C 헤더
```

---

## Backend Layer

### SessionManager (`Backend/Domain/Services/SessionManager.swift`)

**역할**: 터미널 세션의 생명주기와 상태를 중앙에서 관리

**구조**:
```swift
class SessionManager: ObservableObject {
    @Published private(set) var sessions: [TerminalSession] = []
    @Published private(set) var activeNotifications: [ClaudeNotification] = []
    @Published var selectedSessionId: UUID?
    @Published var splitViewState: SplitViewState = SplitViewState()
    
    private var controllers: [UUID: TerminalController] = [:]
    private let rustCore = RustCore.shared
}
```

**핵심 함수**:

| 함수 | 동작 |
|------|------|
| `createSession(name:workingDirectory:)` | 새 세션 생성 → TerminalController 생성 → Combine 구독 연결 → RustCore 동기화 |
| `closeSession(_:)` | 구독 해제 → 컨트롤러 종료 → 세션/알림 제거 → Split 상태 정리 → RustCore 동기화 |
| `renameSession(_:newName:)` | 세션 이름 변경 + RustCore 동기화 |
| `setSessionAlias(_:alias:)` | 세션 별칭 설정 + RustCore 동기화 |
| `toggleSessionLock(_:)` | 잠금 상태 토글 + RustCore 동기화 |
| `handleNotification(_:)` | 알림 필터링 → 자동 핀 적용 → 시스템 알림 전송 → 세션 상태 업데이트 |
| `splitPane(_:direction:newSessionId:currentSize:)` | SplitNode 트리 분할 |
| `minimizePane(_:)` | Pane을 사이드바로 최소화 |

**상태 흐름**:
```
createSession() → TerminalController 생성
                ↓
         Combine 구독 설정
                ↓
    controller.notificationPublisher → handleNotification()
    controller.$isRunning → updateSessionStatus()
```

---

### TerminalController (`Backend/Core/Terminal/TerminalController.swift`)

**역할**: 개별 터미널 프로세스 관리 및 SwiftTerm 뷰 생성

**구조**:
```swift
class TerminalController: ObservableObject {
    let sessionId: UUID
    @Published var isRunning: Bool = false
    @Published var terminalView: CustomTerminalView?
    
    let notificationPublisher = PassthroughSubject<ClaudeNotification, Never>()
    let outputPublisher = PassthroughSubject<String, Never>()
    
    private let notificationDetector = ClaudeNotificationDetector()
}
```

**핵심 함수**:

| 함수 | 동작 |
|------|------|
| `createTerminalView(workingDirectory:)` | CustomTerminalView 생성 → 테마 적용 → 셸 프로세스 시작 → 출력 콜백 등록 |
| `handleOutput(_:)` | 출력 스트림 → 알림 감지기 전달 → 알림 발견 시 publisher로 전송 |
| `sendInput(_:)` | 터미널에 텍스트 입력 전송 |
| `resize(cols:rows:)` | 터미널 크기 변경 |
| `terminate()` | 프로세스 종료 및 리소스 정리 |
| `requestFocus()` | 터미널 뷰에 키보드 포커스 요청 |

**출력 처리 흐름**:
```
Shell Process → CustomTerminalView.dataReceived()
                         ↓
              outputBuffer에 누적 (debounce)
                         ↓
              onOutput 콜백 호출
                         ↓
              handleOutput() → ClaudeNotificationDetector.detect()
                         ↓
              알림 발견 시 → notificationPublisher.send()
```

---

### ClaudeNotificationDetector (`Backend/Core/Parser/ClaudeNotificationDetector.swift`)

**역할**: 터미널 출력에서 Claude Code 알림 패턴 감지

**구조**:
```swift
class ClaudeNotificationDetector {
    // 정적 캐시: 앱 시작 시 한 번만 컴파일
    private static let cachedPatterns: [CachedPattern]
    private static let claudePromptRegexes: [NSRegularExpression]
    private static let slashCommandRegexes: [NSRegularExpression]
    private static let ansiStripRegex: NSRegularExpression?
    
    // 인스턴스 상태
    private var outputBuffer: String = ""
    private var lastDetectionTime: Date?
    private var lastMatchedKey: String?
}
```

**핵심 함수**:

| 함수 | 동작 |
|------|------|
| `detect(in:sessionId:)` | ANSI 제거 → 패턴 매칭 → 중복 방지 → ClaudeNotification 반환 |
| `stripANSI(_:)` | ANSI 이스케이프 시퀀스 제거 |
| `isSlashCommandMenu(_:)` | 슬래시 커맨드 메뉴 감지 (오탐 방지) |
| `looksLikePermissionRequest(_:)` | 권한 요청 추가 검증 |
| `isClaudePromptWaiting(_:)` | Claude 프롬프트 대기 상태 감지 |

**감지 패턴 종류**:
- **Question**: `?`, `(y/n)`, `[Y/n]`, `Press Enter to continue`
- **PermissionRequest**: `Allow...?`, `approve/deny`, `Proceed?`
- **Completion**: `✓...completed`, `Done.`, `Successfully`
- **Error**: `Error:`, `Failed:`, `✗`, `FAILED`
- **Custom**: 사용자 정의 패턴 (CustomPatternMatcher)

---

### CustomPatternMatcher (`Backend/Core/Parser/CustomPatternMatcher.swift`)

**역할**: 사용자 정의 패턴 매칭 (regex 캐싱)

**구조**:
```swift
final class CustomPatternMatcher {
    private var regexCache: [UUID: NSRegularExpression] = [:]
    private var cachePatternHashes: [UUID: Int] = [:]
}
```

**핵심 함수**:

| 함수 | 동작 |
|------|------|
| `match(in:)` | 활성화된 패턴 순회 → 첫 번째 매칭 반환 |
| `matchesWithCache(pattern:text:)` | 키워드/정규식 모드에 따라 매칭 |
| `getCachedRegex(for:)` | 캐시된 regex 반환 (없으면 컴파일 후 캐시) |
| `invalidateCache()` | 패턴 변경 시 캐시 초기화 |

---

### TerminalSession (`Backend/Domain/Models/TerminalSession.swift`)

**역할**: 터미널 세션 메타데이터 모델

**구조**:
```swift
struct TerminalSession: Identifiable, Equatable, Hashable {
    let id: UUID
    var name: String
    var alias: String?
    var workingDirectory: URL
    var status: SessionStatus        // idle, running, waitingForInput, terminated
    var hasUnreadNotification: Bool
    var isLocked: Bool
    var lastActivity: Date
    let createdAt: Date
    
    var displayName: String {
        alias ?? name
    }
}
```

---

### RustCore (`Backend/FFI/RustCore.swift`)

**역할**: Rust 백엔드와의 FFI 인터페이스

**구조**:
```swift
public final class RustCore {
    public static let shared = RustCore()
    private var handle: OpaquePointer?
    
    // 세션 관리
    func createSession(workingDirectory:) -> UUID?
    func closeSession(_:) -> Bool
    func renameSession(_:newName:) -> Bool
    func setSessionAlias(_:alias:) -> Bool
    func toggleSessionLock(_:) -> Bool
    func setSessionStatus(_:status:) -> Bool
}
```

**dylib 로딩 우선순위**:
1. `Contents/Frameworks/libmacviber_core.dylib` (앱 번들 내부)
2. `Contents/Resources/libmacviber_core.dylib`
3. `core/target/release/libmacviber_core.dylib` (개발 모드)

---

## Frontend Layer

### MacViberApp (`UI/App/MacViberApp.swift`)

**역할**: SwiftUI 앱 엔트리 포인트 및 메뉴/단축키 정의

**구조**:
```swift
@main
struct MacViberApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var sessionManager = SessionManager.shared
    @StateObject private var themeManager = ThemeManager.shared
    
    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(sessionManager)
        }
        .commands { ... }
    }
}
```

**단축키 매핑**:
| 단축키 | 동작 | NotificationCenter 이벤트 |
|--------|------|---------------------------|
| `⌘T` | 새 터미널 | `.newTerminalRequested` |
| `⌘W` | 터미널 닫기 | `.closeTerminalRequested` |
| `⌘D` | 수평 분할 | `.splitHorizontalRequested` |
| `⇧⌘D` | 수직 분할 | `.splitVerticalRequested` |
| `⇧⌘W` | 패널 닫기 | `.closePaneRequested` |
| `⌥⌘]` | 다음 패널 | `.focusNextPaneRequested` |
| `⌥⌘[` | 이전 패널 | `.focusPreviousPaneRequested` |

---

### MainViewModel (`UI/Presentation/ViewModels/MainViewModel.swift`)

**역할**: MainView의 상태 관리 및 SessionManager 브릿지

**구조**:
```swift
class MainViewModel: ObservableObject {
    @Published var showNotificationGrid: Bool = false
    @Published var showRightSidebar: Bool = false
    @Published var focusedPaneId: UUID?
    @Published private(set) var selectedSessionId: UUID?
    
    private let sessionManager: SessionManager
    private var cancellables = Set<AnyCancellable>()
}
```

**핵심 함수**:

| 함수 | 동작 |
|------|------|
| `addNewTerminal()` | NSOpenPanel로 디렉토리 선택 → 세션 생성 |
| `addNewTerminalAtHome()` | 홈 디렉토리에 새 터미널 생성 |
| `handleTerminalSelection(_:)` | 사이드바에서 터미널 선택 시 처리 (분할뷰면 스왑/교체) |
| `enterSplitView()` | 현재 세션을 분할 뷰 모드로 전환 |
| `exitSplitView()` | 분할 뷰 종료 → 단일 뷰로 복귀 |
| `splitPane(_:direction:currentSize:)` | 패널 분할 (미사용 세션 재활용 또는 신규 생성) |
| `minimizePane(_:)` | 패널을 사이드바로 최소화 |
| `focusNextPane()` / `focusPreviousPane()` | 패널 간 포커스 이동 |

**이벤트 구독 흐름**:
```
NotificationCenter (.newTerminalRequested 등)
         ↓
MainViewModel.setupNotificationObservers()
         ↓
SessionManager 메서드 호출
         ↓
SessionManager.$sessions, $splitViewState 변경
         ↓
MainViewModel Combine 구독으로 UI 갱신
```

---

### MainView (`UI/Presentation/Views/MainView.swift`)

**역할**: 메인 레이아웃 구성

**구조**:
```swift
struct MainView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @StateObject private var viewModel = MainViewModel()
    
    var body: some View {
        NavigationSplitView {
            TerminalListView(...)      // 좌측 사이드바
        } detail: {
            HStack {
                detailContent           // 중앙 메인 영역
                if viewModel.showRightSidebar {
                    RightSidebarView()  // 우측 Notes 사이드바
                }
            }
        }
    }
}
```

**detailContent 조건부 렌더링**:
```swift
@ViewBuilder
private var detailContent: some View {
    if viewModel.showNotificationGrid && viewModel.hasActiveNotifications {
        NotificationGridView(...)
    } else if let rootNode = viewModel.splitViewRoot {
        SplitTerminalView(node: rootNode, ...)
    } else if let session = viewModel.selectedSession {
        TerminalContainerView(session: session, ...)
    } else {
        EmptyStateView(...)
    }
}
```

---

### TerminalView (`UI/Presentation/Views/Terminal/TerminalView.swift`)

**역할**: SwiftTerm NSView를 SwiftUI로 래핑

**구조**:
```swift
struct TerminalView: NSViewRepresentable {
    let controller: TerminalController
    let workingDirectory: URL
    let isFocused: Bool
    
    func makeNSView(context: Context) -> TerminalContainerNSView
    func updateNSView(_ nsView: TerminalContainerNSView, context: Context)
}
```

**핵심 동작**:

| 함수 | 동작 |
|------|------|
| `makeNSView` | TerminalController의 CustomTerminalView를 컨테이너에 삽입 + Auto Layout 설정 |
| `updateNSView` | 테마 색상 적용 + isFocused 상태에 따라 firstResponder 설정 |

**포커스 처리**:
```swift
class TerminalContainerNSView: NSView {
    var isFocused: Bool = false
    
    override func becomeFirstResponder() -> Bool {
        if isFocused, let terminalView = terminalView {
            window?.makeFirstResponder(terminalView)
        }
        return true
    }
}
```

---

### SplitTerminalView (`UI/Presentation/Views/Terminal/SplitTerminalView.swift`)

**역할**: SplitNode 트리를 재귀적으로 렌더링

**구조**:
```swift
struct SplitTerminalView: View {
    let node: SplitNode
    @Binding var focusedPaneId: UUID?
    let onSplitPane: (UUID, SplitDirection, CGSize) -> Void
    let onMinimizePane: (UUID) -> Void
}
```

**렌더링 로직**:
```swift
@ViewBuilder
private func renderNode(_ node: SplitNode) -> some View {
    switch node {
    case .terminal(let paneId, let sessionId, _):
        TerminalPaneView(...)
        
    case .split(_, let direction, let first, let second, let ratio):
        SplitContainerView(...)
    }
}
```

**SplitContainerView**:
- GeometryReader로 사용 가능 크기 계산
- ratio에 따라 first/second 영역 분배
- 드래그 제스처로 ratio 실시간 조절
- 수평/수직 방향 지원

---

## Data Flow Summary

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           User Interaction                               │
│  (Keyboard Shortcut / Menu / Mouse Click)                               │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         NotificationCenter                               │
│  (.newTerminalRequested, .splitHorizontalRequested, etc.)               │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                           MainViewModel                                  │
│  - setupNotificationObservers() 에서 이벤트 수신                          │
│  - SessionManager 메서드 호출                                            │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                          SessionManager                                  │
│  - 세션/컨트롤러 생성 및 관리                                             │
│  - Split 상태 관리                                                       │
│  - RustCore와 동기화                                                     │
└─────────────────────────────────────────────────────────────────────────┘
                          │                    │
                          ▼                    ▼
┌──────────────────────────────┐  ┌──────────────────────────────────────┐
│     TerminalController       │  │              RustCore                 │
│  - SwiftTerm 프로세스 관리    │  │  - Rust FFI 세션 메타데이터 동기화     │
│  - 출력 스트림 처리           │  │  - 크로스 플랫폼 지원 준비             │
└──────────────────────────────┘  └──────────────────────────────────────┘
              │
              ▼
┌──────────────────────────────┐
│  ClaudeNotificationDetector  │
│  - 패턴 매칭                  │
│  - 알림 생성                  │
└──────────────────────────────┘
              │
              ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                    SessionManager.$activeNotifications                   │
│                    SessionManager.$sessions                              │
│                    SessionManager.$splitViewState                        │
│  (Combine @Published)                                                    │
└──────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                           MainViewModel                                  │
│  - Combine 구독으로 상태 변경 감지                                        │
│  - objectWillChange.send()로 UI 갱신 트리거                              │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                      SwiftUI View Hierarchy                              │
│  MainView → SplitTerminalView → TerminalPaneView → TerminalView         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Key Design Patterns

### 1. Singleton + Dependency Injection
- `SessionManager.shared`, `ThemeManager.shared` 등 싱글톤 사용
- ViewModel 초기화 시 의존성 주입 가능 (`init(sessionManager:)`)

### 2. MVVM
- **Model**: TerminalSession, ClaudeNotification, SplitNode
- **ViewModel**: MainViewModel, TerminalListViewModel
- **View**: MainView, TerminalView, SplitTerminalView

### 3. Combine Reactive Binding
- `@Published` 프로퍼티로 상태 변경 자동 전파
- ViewModel에서 SessionManager 상태 구독
- debounce로 과도한 UI 갱신 방지

### 4. NotificationCenter Event Bus
- 메뉴/단축키 이벤트를 중앙 이벤트 버스로 전달
- ViewModel에서 구독하여 처리

### 5. Recursive Tree Rendering
- SplitNode 트리 구조를 재귀적으로 SwiftUI 뷰로 변환
- `.terminal` → TerminalPaneView
- `.split` → SplitContainerView (재귀 호출)

### 6. FFI Bridge Pattern
- RustCore가 Swift와 Rust 사이의 브릿지 역할
- dlopen/dlsym으로 동적 라이브러리 로딩
- 세션 상태를 양쪽에 동기화

---

## File Dependencies

```
MacViberApp.swift
    └── MainView.swift
            ├── TerminalListView.swift
            ├── NotificationGridView.swift
            ├── SplitTerminalView.swift
            │       └── TerminalPaneView.swift
            │               └── TerminalView.swift
            │                       └── TerminalController.swift
            │                               └── CustomTerminalView (SwiftTerm)
            │                               └── ClaudeNotificationDetector.swift
            │                                       └── CustomPatternMatcher.swift
            └── RightSidebarView.swift

SessionManager.swift (중앙 상태 관리)
    ├── TerminalController.swift (N개)
    ├── RustCore.swift (FFI 동기화)
    └── Combine Publishers → MainViewModel.swift
```
