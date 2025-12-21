# MacViber 개발 가이드

Claude Code를 사용하여 MacViber을 처음부터 다시 만들 때 참고할 가이드입니다.

---

## 1단계: 프로젝트 초기 설정

```
macOS SwiftUI 앱 "MacViber"을 만들어줘.
- Swift Package Manager 사용
- SwiftTerm 라이브러리 의존성 추가 (https://github.com/migueldeicaza/SwiftTerm)
- swift-markdown-ui 라이브러리 의존성 추가 (v2.4.0+, Notes 기능용)
- 최소 macOS 14.0 (Sonoma) 타겟
- 앱 번들 생성용 build-app.sh 스크립트 포함
```

### 예상 디렉토리 구조

```
MacViber/
├── Package.swift
├── Scripts/
│   ├── build-app.sh
│   ├── install-app.sh
│   ├── setup.sh
│   └── create-dmg.sh
├── LocalPackages/
│   └── SwiftTerm/              # 로컬 SwiftTerm 패키지
└── MacViber/
    ├── App/
    │   └── MacViberApp.swift
    ├── Core/
    │   ├── Logger.swift
    │   ├── Terminal/
    │   │   ├── TerminalController.swift
    │   │   └── TerminalConfiguration.swift
    │   └── Parser/
    │       ├── ClaudeNotificationDetector.swift
    │       └── CustomPatternMatcher.swift
    ├── Domain/
    │   ├── Models/
    │   │   ├── TerminalSession.swift
    │   │   ├── TerminalTheme.swift
    │   │   ├── SplitNode.swift
    │   │   ├── ClaudeNotification.swift
    │   │   ├── CustomPattern.swift
    │   │   ├── Note.swift
    │   │   ├── NotificationPreferences.swift
    │   │   └── CustomColorSettings.swift
    │   └── Services/
    │       ├── SessionManager.swift
    │       ├── ThemeManager.swift
    │       ├── FavoritesManager.swift
    │       ├── NoteManager.swift
    │       ├── NotificationPreferencesManager.swift
    │       └── SyntaxHighlightingInstaller.swift
    ├── Presentation/
    │   ├── ViewModels/
    │   │   ├── MainViewModel.swift
    │   │   ├── TerminalListViewModel.swift
    │   │   ├── NotificationGridViewModel.swift
    │   │   ├── NotificationSettingsViewModel.swift
    │   │   └── NoteViewModel.swift
    │   └── Views/
    │       ├── MainView.swift
    │       ├── Components/
    │       │   └── ResizableSidebar.swift
    │       ├── Terminal/
    │       │   ├── TerminalView.swift
    │       │   ├── TerminalPaneView.swift
    │       │   └── SplitTerminalView.swift
    │       ├── Sidebar/
    │       │   ├── TerminalListView.swift
    │       │   └── FavoritesView.swift
    │       ├── Notification/
    │       │   ├── NotificationGridView.swift
    │       │   └── NotificationCardView.swift
    │       ├── Settings/
    │       │   ├── ThemePickerView.swift
    │       │   ├── ColorSettingsView.swift
    │       │   ├── NotificationSettingsView.swift
    │       │   └── CustomPatternEditorView.swift
    │       └── Note/
    │           ├── MarkdownEditorView.swift
    │           ├── MarkdownPreviewView.swift
    │           └── RightSidebarView.swift
    └── Resources/
        └── Info.plist
```

---

## 2단계: 핵심 데이터 모델

```
다음 모델들을 만들어줘:

1. TerminalSession
   - id: UUID
   - name: String
   - workingDirectory: URL
   - status: SessionStatus (idle, running, waitingForInput, terminated)
   - alias: String? (사용자 지정 별칭)
   - isLocked: Bool (잠금 상태)
   - hasUnreadNotification: Bool
   - lastActivity: Date
   - displayName: 계산 속성 (alias ?? name)

2. SessionStatus enum
   - idle (회색)
   - running (초록)
   - waitingForInput (주황)
   - terminated (빨강)

3. SplitNode (재귀적 트리 구조)
   - terminal(id: UUID, sessionId: UUID)
   - split(id: UUID, direction: SplitDirection, first: SplitNode, second: SplitNode, ratio: Double)
   - sessionId(for paneId:) 메서드로 특정 pane의 세션 조회

4. SplitViewState
   - rootNode: SplitNode?
   - focusedPaneId: UUID?
   - isActive, paneCount, canSplit (최대 4개), allPaneIds 계산 속성
   - nextPaneId, previousPaneId 메서드로 pane 순환
```

---

## 3단계: TerminalController (핵심)

```
SwiftTerm의 LocalProcessTerminalView를 래핑하는 TerminalController 클래스:

- sessionId: UUID
- @Published isRunning: Bool = false
- @Published terminalView: CustomTerminalView?
- notificationPublisher: PassthroughSubject<ClaudeNotification, Never>

createTerminalView(workingDirectory: URL) 메서드:
- 이미 생성된 view가 있으면 재사용
- zsh 셸 프로세스 시작
- 환경변수: TERM=xterm-256color, PWD=workingDirectory
- 시작 후 0.1초 뒤 cd 명령으로 디렉토리 이동
- processDelegate에서 종료 감지 시 isRunning = false 설정
```

### 핵심 코드 패턴

```swift
class CustomTerminalView: LocalProcessTerminalView {
    var onOutput: ((String) -> Void)?

    // 수동 Selection 추적 (SwiftTerm의 selection 시스템 우회)
    private var cachedSelection: String?
    private var mouseMonitor: Any?
    private var selectionStart: CGPoint?
    private var selectionEnd: CGPoint?
    private var isDragging = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupMouseMonitor()
    }

    deinit {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func setupMouseMonitor() {
        mouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            self?.handleMouseEvent(event)
            return event
        }
    }

    // 마우스 이벤트로 selection 범위 추적 → extractTextFromPoints에서 텍스트 추출
    // copy() 시 cachedSelection 사용

    override func copy(_ sender: Any) {
        if let cached = cachedSelection, !cached.isEmpty {
            let clipboard = NSPasteboard.general
            clipboard.clearContents()
            clipboard.setString(cached, forType: .string)
            return
        }
        super.copy(sender)
    }

    override func dataReceived(slice: ArraySlice<UInt8>) {
        super.dataReceived(slice: slice)
        if let output = String(bytes: slice, encoding: .utf8) {
            onOutput?(output)
        }
    }
}
```

> ⚠️ **주의**: SwiftTerm의 내장 selection 시스템은 `keyDown`에서 `selection.active = false`로 초기화되어 `cmd+c` 복사 시 동작하지 않음. 수동 마우스 추적이 필수.

---

## 4단계: SessionManager (싱글톤)

```
SessionManager 싱글톤 클래스:

@Published sessions: [TerminalSession]
@Published selectedSessionId: UUID?
@Published splitViewState: SplitViewState
private controllers: [UUID: TerminalController]

핵심 메서드:
1. createSession(name:, workingDirectory:) → TerminalSession
2. controller(for:), session(for:)
3. closeSession, renameSession, duplicateSession
4. setSessionAlias, toggleSessionLock

Split View 관리:
- setSplitViewRoot(_ node:)
- setFocusedPane(_ paneId:)
- splitPane(paneId, direction, newSessionId)
- removePaneFromSplit(paneId)
- updatePaneSession(paneId, newSessionId)
- findPaneIdForSession(sessionId) → UUID?
- swapPaneSessions(paneId1, paneId2)
```

### ⚠️ 중요: isRunning 구독 시 dropFirst() 필수

```swift
// createSession 내부
controller.$isRunning
    .dropFirst()  // 초기 false 값 무시 - 이게 없으면 즉시 terminated 됨!
    .receive(on: DispatchQueue.main)
    .sink { [weak self] isRunning in
        self?.updateSessionStatus(session.id, isRunning: isRunning)
    }
    .store(in: &cancellables)
```

---

## 5단계: MainViewModel

```
MainViewModel (ObservableObject):

@Published selectedSessionId: UUID?
@Published focusedPaneId: UUID?
@Published showNotificationGrid: Bool
@Published columnVisibility: NavigationSplitViewVisibility

터미널 생성 메서드:
- addNewTerminal() - NSOpenPanel로 폴더 선택
- addNewTerminal(at: URL) - 특정 경로에 생성
- addNewTerminalAtHome() - 홈 디렉토리에 생성

handleTerminalSelection(sessionId):
- Split view에서 다른 pane이 해당 세션을 이미 표시 중이면 SWAP
- 아니면 단순 교체
```

### ⚠️ 핵심 설계 원칙 1: focusedPaneId는 항상 SessionManager 통해 설정

```swift
// ❌ 잘못된 방법 - 구독자에 의해 덮어씌워짐
focusedPaneId = paneId

// ✅ 올바른 방법
sessionManager.setFocusedPane(paneId)
```

### ⚠️ 핵심 설계 원칙 2: NSOpenPanel 사용 전 상태 캡처

```swift
func addNewTerminal() {
    // 모달 열기 전에 상태 캡처 (모달 중 SwiftUI 상태가 변경될 수 있음)
    let wasInSplitView = isSplitViewActive
    let capturedPaneId = focusedPaneId

    let panel = NSOpenPanel()
    // ... panel 설정 ...

    if panel.runModal() == .OK, let url = panel.url {
        let session = sessionManager.createSession(...)

        // 캡처된 상태 사용
        if wasInSplitView, let paneId = capturedPaneId {
            sessionManager.updatePaneSession(paneId, newSessionId: session.id)
        } else {
            sessionManager.selectedSessionId = session.id
        }
    }
}
```

### ⚠️ 핵심 설계 원칙 3: SWAP 로직

```swift
func handleTerminalSelection(_ sessionId: UUID) {
    if isSplitViewActive, let paneId = focusedPaneId {
        // 다른 pane이 이미 이 세션을 표시 중인지 확인
        if let existingPaneId = sessionManager.findPaneIdForSession(sessionId),
           existingPaneId != paneId {
            // SWAP: 두 pane의 세션 교환
            sessionManager.swapPaneSessions(paneId, existingPaneId)
        } else {
            // 단순 교체
            sessionManager.updatePaneSession(paneId, newSessionId: sessionId)
        }
    } else {
        navigateToSession(sessionId)
    }
}
```

---

## 6단계: View 계층 구조

```
MainView:
- NavigationSplitView
  - Sidebar: TerminalListView
  - Detail: detailContent (조건부)
    - NotificationGridView (알림 있을 때)
    - SplitTerminalView (split view 모드)
    - TerminalContainerView (단일 뷰 모드)
    - EmptyStateView (세션 없을 때)
```

### ⚠️ 중요: .id() modifier 필수

```swift
// TerminalContainerView 사용 시
TerminalContainerView(session: session, viewModel: viewModel)
    .id(session.id)  // SwiftUI가 NSViewRepresentable을 재사용하므로 강제 재생성 필요

// TerminalPaneView 내부의 TerminalView
TerminalView(controller: controller, workingDirectory: session.workingDirectory)
    .id(sessionId)  // 세션 변경 시 뷰 재생성
```

### TerminalView (NSViewRepresentable)

```swift
struct TerminalView: NSViewRepresentable {
    let controller: TerminalController
    let workingDirectory: URL

    func makeNSView(context: Context) -> NSView {
        let containerView = NSView()
        let terminalView = controller.createTerminalView(workingDirectory: workingDirectory)
        // constraint 설정...
        return containerView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // 필요시 업데이트
    }
}
```

---

## 7단계: 사이드바 구성

```
TerminalListView:
- List with selection binding
- FavoritesView 섹션
- Terminals 섹션

TerminalListItemView:
- 상태 인디케이터 (색상 원)
- displayName (alias 또는 name)
- 경로 표시
- 호버 시 잠금/닫기 버튼

컨텍스트 메뉴:
- Set Alias / Remove Alias
- Rename
- Duplicate
- Lock/Unlock
- Close (잠금 시 비활성화)
```

### Selection Binding 핵심

```swift
List(selection: Binding(
    get: { viewModel.selectedSessionId },
    set: { newValue in
        if let sessionId = newValue {
            onSelectSession?(sessionId)  // MainViewModel.handleTerminalSelection 연결
        }
        viewModel.selectedSessionId = newValue
    }
)) {
    // ...
}
```

---

## 8단계: 즐겨찾기 시스템

```
FavoritesManager (싱글톤):
- @Published favorites: [FavoriteFolder]
- UserDefaults에 저장
- add, remove, reorder 메서드

FavoriteFolder:
- id: UUID
- url: URL
- name: String (url.lastPathComponent)

FavoritesView:
- 즐겨찾기 목록 표시
- 클릭 시 onOpenTerminal(url) 콜백
- 드래그로 재정렬
- 컨텍스트 메뉴로 삭제
```

---

## 9단계: 알림 시스템 (Claude Code 연동)

```
ClaudeNotificationDetector:
- 터미널 출력에서 Claude Code 알림 패턴 감지
- "waiting for input", "question" 등 키워드

ClaudeNotification:
- id, sessionId, type, message, timestamp, isRead

NotificationGridView:
- 활성 알림 그리드 표시
- 응답 입력 기능
- 해당 세션으로 이동 버튼
```

---

## 10단계: 키보드 단축키

```swift
.commands {
    CommandGroup(replacing: .newItem) {
        Button("New Terminal") { /* Cmd+T */ }
    }
    CommandGroup {
        Button("Close Terminal") { /* Cmd+W */ }
        Divider()
        Button("Split Horizontal") { /* Cmd+D */ }
        Button("Split Vertical") { /* Cmd+Shift+D */ }
        Divider()
        Button("Next Pane") { /* Cmd+] */ }
        Button("Previous Pane") { /* Cmd+[ */ }
    }
}
```

NotificationCenter를 통해 ViewModel에 전달:
```swift
extension Notification.Name {
    static let newTerminalRequested = Notification.Name("newTerminalRequested")
    static let splitHorizontalRequested = Notification.Name("splitHorizontalRequested")
    // ...
}
```

---

## 회피해야 할 함정들 (Lessons Learned)

### 1. NSViewRepresentable 재사용 문제

**증상**: 터미널 세션을 변경해도 화면이 바뀌지 않음

**원인**: SwiftUI가 NSViewRepresentable을 재사용하여 updateNSView만 호출

**해결**:
```swift
TerminalContainerView(session: session)
    .id(session.id)  // 세션 변경 시 뷰 강제 재생성
```

### 2. @Published 초기값 구독 문제

**증상**: 새 터미널이 즉시 terminated(빨간불) 상태로 표시

**원인**: `@Published isRunning = false` 초기값이 구독자에게 즉시 전달됨

**해결**:
```swift
controller.$isRunning
    .dropFirst()  // 초기값 무시
    .sink { ... }
```

### 3. 상태 동기화 문제

**증상**: Split view 진입 후 focusedPaneId가 nil

**원인**: 로컬에서 설정한 값이 SessionManager 구독자에 의해 덮어씌워짐

**해결**: 항상 SessionManager 메서드를 통해 설정
```swift
// ❌ focusedPaneId = paneId
// ✅ sessionManager.setFocusedPane(paneId)
```

### 4. NSOpenPanel 모달 중 상태 변경

**증상**: + 버튼으로 터미널 생성 시 split view에 표시 안됨

**원인**: 모달이 열려있는 동안 SwiftUI 상태가 변경될 수 있음

**해결**: 모달 열기 전 필요한 상태 캡처
```swift
let wasInSplitView = isSplitViewActive
let capturedPaneId = focusedPaneId
// 이후 모달 열기...
```

### 5. Split view에서 같은 세션 중복 참조

**증상**: Pane A, B가 있을 때 A에서 B의 세션 선택 시 B가 빈 화면

**원인**: 두 pane이 같은 세션을 참조하게 됨

**해결**: SWAP 로직 구현
```swift
if let existingPaneId = findPaneIdForSession(sessionId) {
    swapPaneSessions(currentPaneId, existingPaneId)
}
```

### 6. SwiftTerm 텍스트 복사(cmd+c) 안됨

**증상**: 터미널에서 마우스로 텍스트 선택 후 `cmd+c`로 복사가 안됨

**원인**: SwiftTerm의 `keyDown()` 첫 줄에서 `selection.active = false` 실행
```swift
// SwiftTerm/MacTerminalView.swift
public override func keyDown(with event: NSEvent) {
    selection.active = false  // 모든 키 입력에서 selection 초기화!
    // ...
}
```
`cmd+c` → `keyDown` 실행 → selection 비활성화 → `copy()` 호출 시 selection이 없음

**해결**: NSEvent 모니터로 마우스 이벤트를 독립적으로 추적하여 수동 selection 구현
```swift
// 1. NSEvent.addLocalMonitorForEvents로 마우스 이벤트 캡처
// 2. 화면 좌표 → 터미널 좌표 변환 (macOS 좌표계 반전 + yDisp 스크롤 오프셋)
// 3. terminal.getText()로 버퍼에서 직접 텍스트 추출
// 4. cachedSelection에 저장 후 copy()에서 사용
```

**좌표 변환 핵심**:
```swift
// 화면 row (0 = 맨 위)
let screenRow = Int((bounds.height - point.y) / cellHeight)

// 버퍼 row (스크롤 고려)
let bufferRow = screenRow + terminal.buffer.yDisp
```

> 상세 내용: `docs/copy-selection-fix.md` 참조

---

## 빌드 스크립트 (build-app.sh)

```bash
#!/bin/bash

APP_NAME="MacViber"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# 실행 중인 앱 종료
if pgrep -x "$APP_NAME" > /dev/null 2>&1; then
    pkill -x "$APP_NAME" || true
    sleep 1
fi

# 캐시 정리
rm -rf "$PROJECT_DIR/.build"
rm -rf "$PROJECT_DIR/build"

# 빌드
swift build -c release

# 앱 번들 생성
mkdir -p "$PROJECT_DIR/build/$APP_NAME.app/Contents/MacOS"
mkdir -p "$PROJECT_DIR/build/$APP_NAME.app/Contents/Resources"

cp "$PROJECT_DIR/.build/release/$APP_NAME" "$PROJECT_DIR/build/$APP_NAME.app/Contents/MacOS/"
# Info.plist, 아이콘 등 복사...

# 실행
open "$PROJECT_DIR/build/$APP_NAME.app"
```

---

## 요약: 개발 순서

1. **프로젝트 설정** - Package.swift, 기본 구조
2. **모델** - TerminalSession, SplitNode, SplitViewState
3. **TerminalController** - SwiftTerm 래핑
4. **SessionManager** - 세션/컨트롤러 관리, Split view 상태
5. **MainViewModel** - UI 상태 관리, 비즈니스 로직
6. **MainView** - NavigationSplitView 구조
7. **TerminalView** - NSViewRepresentable
8. **SplitTerminalView** - 재귀적 분할 뷰
9. **사이드바** - TerminalListView, FavoritesView
10. **키보드 단축키** - Commands
11. **알림 시스템** - Claude Code 연동

각 단계에서 위의 "회피해야 할 함정들"을 참고하여 미리 대비하면 시행착오를 줄일 수 있습니다.

---

## 11단계: Notes 사이드바

```
오른쪽 사이드바에 Markdown 노트 기능 추가:

NoteManager (싱글톤):
- @Published note: Note
- 파일 저장 위치: ~/Library/Application Support/MacViber/note.md
- load(), save() 메서드

NoteViewModel:
- @Published selectedTab: Tab (.edit, .preview)
- @Published content: String
- saveNote() 메서드 (수동 저장)

RightSidebarView:
- Header: "Notes" + Edit/Preview Picker
- Content: MarkdownEditorView / MarkdownPreviewView
- Footer: Save 버튼 + 저장 성공 메시지
```

### 핵심 코드 패턴

```swift
// RightSidebarView - 저장 버튼과 피드백
@State private var showSavedMessage = false

Button(action: {
    viewModel.saveNote()
    withAnimation { showSavedMessage = true }
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
        withAnimation { showSavedMessage = false }
    }
}) {
    HStack(spacing: 4) {
        Image(systemName: "square.and.arrow.down")
        Text("Save")
    }
}
.buttonStyle(.borderedProminent)
```

> ⚠️ **주의**: 자동 저장은 CPU 사용량 문제를 일으킬 수 있음. 수동 저장 권장.

---

## 12단계: CPU 최적화 패턴

### 1. 정규식 캐싱 (필수)

```swift
// ❌ 잘못된 방법 - 매번 컴파일
func detect(in text: String) {
    for pattern in patterns {
        let regex = try NSRegularExpression(pattern: pattern)  // CPU 낭비!
    }
}

// ✅ 올바른 방법 - static let으로 한 번만 컴파일
private static let cachedPatterns: [CachedPattern] = {
    let definitions: [(String, NotificationType)] = [
        ("\\?\\s*$", .question),
        // ...
    ]
    return definitions.compactMap { (pattern, type) in
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        return CachedPattern(regex: regex, type: type)
    }
}()
```

### 2. 마우스 드래그 쓰로틀링

```swift
// 마우스 드래그 이벤트는 초당 100+회 발생할 수 있음
private var lastDragTime: Date?
private let dragThrottleInterval: TimeInterval = 0.016  // ~60fps

case .leftMouseDragged:
    let now = Date()
    if let lastTime = lastDragTime, now.timeIntervalSince(lastTime) < dragThrottleInterval {
        return  // 이벤트 무시
    }
    lastDragTime = now
    // 처리 로직...
```

### 3. 터미널 출력 버퍼링

```swift
// ❌ 매 바이트마다 처리
override func dataReceived(slice: ArraySlice<UInt8>) {
    super.dataReceived(slice: slice)
    if let output = String(bytes: slice, encoding: .utf8) {
        onOutput?(output)  // CPU 낭비!
    }
}

// ✅ 버퍼링 후 일정 간격으로 처리
private var outputBuffer: [UInt8] = []
private var outputFlushTask: DispatchWorkItem?
private let outputFlushDelay: TimeInterval = 0.05

override func dataReceived(slice: ArraySlice<UInt8>) {
    super.dataReceived(slice: slice)
    outputBuffer.append(contentsOf: slice)

    outputFlushTask?.cancel()
    outputFlushTask = DispatchWorkItem { [weak self] in
        self?.flushOutputBuffer()
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + outputFlushDelay, execute: outputFlushTask!)
}
```

### 4. objectWillChange 디바운싱

```swift
// ❌ 즉시 전파
sessionManager.objectWillChange
    .receive(on: DispatchQueue.main)
    .sink { [weak self] _ in
        self?.objectWillChange.send()
    }

// ✅ 디바운싱 적용
sessionManager.objectWillChange
    .debounce(for: .milliseconds(16), scheduler: DispatchQueue.main)
    .sink { [weak self] _ in
        self?.objectWillChange.send()
    }
```

### 5. display() 호출 제거

```swift
// ❌ 동기 강제 리드로우
termView.needsDisplay = true
termView.display()  // 블로킹!

// ✅ 시스템에 맡기기
termView.needsDisplay = true
// display() 제거 - 시스템이 최적 타이밍에 렌더링
```

---

## 빌드 및 설치 스크립트

### build-app.sh (테스트 빌드)

```bash
#!/bin/bash
APP_NAME="MacViber"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# 기존 앱 종료
pkill -x "$APP_NAME" 2>/dev/null || true
sleep 1

# 빌드
swift build -c release

# 앱 번들 생성
mkdir -p "$PROJECT_DIR/build/$APP_NAME.app/Contents/MacOS"
cp "$PROJECT_DIR/.build/release/$APP_NAME" "$PROJECT_DIR/build/$APP_NAME.app/Contents/MacOS/"

# 실행
open "$PROJECT_DIR/build/$APP_NAME.app"
```

### install-app.sh (프로덕션 설치)

```bash
#!/bin/bash
APP_NAME="MacViber"

# Production/Test 모드 선택
if [[ "$1" == "--test" ]]; then
    INSTALL_MODE="TEST"
else
    INSTALL_MODE="PRODUCTION"
fi

# 기존 앱 종료 및 제거
pkill -x "$APP_NAME" 2>/dev/null
rm -rf "/Applications/$APP_NAME.app"

# 설치
cp -R "build/$APP_NAME.app" "/Applications/"

echo "✅ $APP_NAME.app installed to /Applications"
```

---

## 추가된 회피해야 할 함정들

### 7. 자동 저장 CPU 문제

**증상**: Notes 편집 시 CPU 사용량이 높음

**원인**: 매 키 입력마다 debounced save Task 생성/취소

**해결**: 자동 저장 제거, 수동 Save 버튼 사용

### 8. 정규식 반복 컴파일

**증상**: 터미널 출력 처리 시 CPU 100%

**원인**: 매 출력마다 NSRegularExpression 새로 컴파일

**해결**: `static let`으로 정규식 캐싱

### 9. display() 강제 호출

**증상**: 테마 변경 시 UI 버벅임

**원인**: `display()` 동기 호출로 메인 스레드 블로킹

**해결**: `needsDisplay = true`만 사용, `display()` 제거

### 10. HSplitView/VSplitView 비율 무시

**증상**: Split 버튼 클릭 시 50/50이 아닌 불균형한 비율로 분할됨

**원인**: `HSplitView`/`VSplitView`는 `ratio` 값을 무시하고 자체적으로 divider 위치 관리
```swift
// SplitNode에 ratio: 0.5가 저장되지만...
case .split(_, let direction, let first, let second, _):
//                                                    ↑ ratio 무시!
    HSplitView {
        firstView.frame(minWidth: 150)  // 최소값만 설정, 비율 미적용
        secondView.frame(minWidth: 150)
    }
```

**해결**: `GeometryReader` + `HStack`/`VStack` + 커스텀 draggable divider 사용
```swift
case .split(_, let direction, let first, let second, let ratio):
    SplitContainerView(
        direction: direction,
        first: first,
        second: second,
        initialRatio: ratio,  // ratio 실제 적용
        ...
    )
```

---

## 13단계: Split View 비율 제어

```
HSplitView/VSplitView 대신 커스텀 SplitContainerView 사용:

SplitContainerView:
- GeometryReader로 전체 크기 파악
- HStack/VStack으로 비율에 따라 크기 할당
- @State ratio로 드래그 조절 가능
- 드래그 가능한 Divider (4pt 너비)
```

### 핵심 코드 패턴

```swift
struct SplitContainerView: View {
    let direction: SplitDirection
    let first: SplitNode
    let second: SplitNode
    let initialRatio: CGFloat

    @State private var ratio: CGFloat
    @State private var isDragging = false

    private let dividerWidth: CGFloat = 4
    private let minRatio: CGFloat = 0.15
    private let maxRatio: CGFloat = 0.85

    init(...) {
        self._ratio = State(initialValue: initialRatio)
        // ...
    }

    var body: some View {
        GeometryReader { geometry in
            if direction == .horizontal {
                let availableWidth = geometry.size.width - dividerWidth
                let firstWidth = availableWidth * ratio
                let secondWidth = availableWidth * (1 - ratio)

                HStack(spacing: 0) {
                    SplitTerminalView(node: first, ...)
                        .frame(width: firstWidth)

                    // Draggable divider
                    Rectangle()
                        .fill(isDragging ? Color.accentColor.opacity(0.5) : Color.gray.opacity(0.3))
                        .frame(width: dividerWidth)
                        .onHover { hovering in
                            if hovering { NSCursor.resizeLeftRight.push() }
                            else { NSCursor.pop() }
                        }
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    isDragging = true
                                    let newRatio = (firstWidth + value.translation.width) / availableWidth
                                    ratio = min(max(newRatio, minRatio), maxRatio)
                                }
                                .onEnded { _ in isDragging = false }
                        )

                    SplitTerminalView(node: second, ...)
                        .frame(width: secondWidth)
                }
            } else {
                // VStack for vertical split (동일한 패턴)
            }
        }
    }
}
```

### 비율 제약
- **초기 비율**: 0.5 (정확히 50/50)
- **최소 비율**: 0.15 (각 pane 최소 15%)
- **최대 비율**: 0.85 (각 pane 최대 85%)

> ⚠️ **주의**: `HSplitView`/`VSplitView`는 초기 비율 설정 API가 없으므로 커스텀 구현 필수.

---

## 14단계: IME 지원 (한글 입력)

```
CustomTerminalView에 IME(Input Method Editor) 지원 추가:

NSTextInputClient 프로토콜 구현:
- setMarkedText(_:selectedRange:replacementRange:)
- unmarkText()
- hasMarkedText
- markedRange(), selectedRange()
- attributedSubstring(forProposedRange:actualRange:)
- validAttributesForMarkedText
- firstRect(forCharacterRange:actualRange:)
- characterIndex(for:)
- insertText(_:replacementRange:)
```

### 핵심 코드 패턴

```swift
class CustomTerminalView: LocalProcessTerminalView, NSTextInputClient {
    private var markedTextString: String = ""
    private var markedTextRange: NSRange = NSRange(location: NSNotFound, length: 0)

    override func keyDown(with event: NSEvent) {
        // IME 입력 처리를 위해 inputContext로 전달
        inputContext?.handleEvent(event)
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        if let str = string as? String {
            markedTextString = str
            markedTextRange = NSRange(location: 0, length: str.count)
        } else if let attrStr = string as? NSAttributedString {
            markedTextString = attrStr.string
            markedTextRange = NSRange(location: 0, length: attrStr.length)
        }
        needsDisplay = true
    }

    func unmarkText() {
        markedTextString = ""
        markedTextRange = NSRange(location: NSNotFound, length: 0)
    }

    func insertText(_ string: Any, replacementRange: NSRange) {
        let text: String
        if let str = string as? String {
            text = str
        } else if let attrStr = string as? NSAttributedString {
            text = attrStr.string
        } else {
            return
        }
        // 터미널에 텍스트 전송
        send(txt: text)
        unmarkText()
    }

    var hasMarkedText: Bool {
        return !markedTextString.isEmpty
    }
}
```

> ⚠️ **주의**: `keyDown`에서 `super.keyDown(with:)` 호출 전에 `inputContext?.handleEvent(event)`를 먼저 호출해야 함.

---

## 15단계: Dock Badge

```
읽지 않은 알림 개수를 Dock 아이콘에 표시:

SessionManager에 updateDockBadge() 메서드:
- 읽지 않은 알림 개수 계산
- NSApp.dockTile.badgeLabel 설정
- 0개면 빈 문자열로 배지 제거
```

### 핵심 코드 패턴

```swift
// SessionManager.swift
func updateDockBadge() {
    let unreadCount = notifications.filter { !$0.isRead }.count

    DispatchQueue.main.async {
        if unreadCount > 0 {
            NSApp.dockTile.badgeLabel = "\(unreadCount)"
        } else {
            NSApp.dockTile.badgeLabel = ""
        }
    }
}

// 알림 발생 시 호출
func handleNotification(_ notification: ClaudeNotification) {
    notifications.append(notification)
    updateDockBadge()
    // 시스템 알림 표시...
}

// 알림 읽음 처리 시 호출
func markNotificationAsRead(_ id: UUID) {
    if let index = notifications.firstIndex(where: { $0.id == id }) {
        notifications[index].isRead = true
        updateDockBadge()
    }
}
```

---

## 16단계: Syntax Highlighting 설치

```
zsh 구문 강조 자동 설치 기능:

SyntaxHighlightingInstaller:
- Homebrew로 zsh-syntax-highlighting 설치 확인
- ~/.zshrc에 source 라인 추가
- 설치 상태 확인 메서드

SyntaxHighlightColors (TerminalTheme 내):
- command: 명령어 색상
- string: 문자열 색상
- option: 옵션/플래그 색상
- path: 경로 색상
- error: 에러 색상
```

### 핵심 코드 패턴

```swift
class SyntaxHighlightingInstaller {
    static let shared = SyntaxHighlightingInstaller()

    private let highlightingPath = "/opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
    private let sourceCommand: String

    init() {
        sourceCommand = "source \(highlightingPath)"
    }

    func isInstalled() -> Bool {
        FileManager.default.fileExists(atPath: highlightingPath)
    }

    func isConfigured() -> Bool {
        guard let zshrc = try? String(contentsOfFile: NSHomeDirectory() + "/.zshrc") else {
            return false
        }
        return zshrc.contains(sourceCommand)
    }

    func install() async throws {
        // Homebrew로 설치
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/brew")
        process.arguments = ["install", "zsh-syntax-highlighting"]
        try process.run()
        process.waitUntilExit()
    }

    func configure() throws {
        let zshrcPath = NSHomeDirectory() + "/.zshrc"
        var content = (try? String(contentsOfFile: zshrcPath)) ?? ""
        content += "\n\n# Syntax highlighting\n\(sourceCommand)\n"
        try content.write(toFile: zshrcPath, atomically: true, encoding: .utf8)
    }
}
```

---

## 17단계: Custom Color Settings

```
사용자 커스텀 색상 시스템:

CustomColorSettings:
- useCustomBackground: Bool
- useCustomForeground: Bool
- backgroundColor: ThemeColor?
- foregroundColor: ThemeColor?
- UserDefaults에 저장

ThemeManager 확장:
- @Published customColors: CustomColorSettings
- effectiveBackgroundColor: 커스텀 또는 테마 색상
- effectiveForegroundColor: 커스텀 또는 테마 색상
```

### 핵심 코드 패턴

```swift
struct CustomColorSettings: Codable {
    var useCustomBackground: Bool = false
    var useCustomForeground: Bool = false
    var backgroundColor: ThemeColor?
    var foregroundColor: ThemeColor?
}

class ThemeManager: ObservableObject {
    @Published var currentTheme: TerminalTheme
    @Published var customColors: CustomColorSettings

    var effectiveBackgroundColor: NSColor {
        if customColors.useCustomBackground, let bg = customColors.backgroundColor {
            return bg.nsColor
        }
        return currentTheme.background.nsColor
    }

    var effectiveForegroundColor: NSColor {
        if customColors.useCustomForeground, let fg = customColors.foregroundColor {
            return fg.nsColor
        }
        return currentTheme.foreground.nsColor
    }
}
```

---

## 18단계: Notification Preferences

```
알림 필터링 및 자동 핸들 설정:

NotificationPreferences:
- enableSystemNotifications: Bool
- enableSoundAlerts: Bool
- autoHandlePermissions: Bool (자동으로 Allow 클릭)
- mutedSessionIds: Set<UUID> (음소거된 세션)
- mutedPatternTypes: Set<NotificationType>

NotificationPreferencesManager:
- @Published preferences: NotificationPreferences
- UserDefaults에 저장
- shouldNotify(session:, type:) -> Bool
```

### 핵심 코드 패턴

```swift
struct NotificationPreferences: Codable {
    var enableSystemNotifications: Bool = true
    var enableSoundAlerts: Bool = true
    var autoHandlePermissions: Bool = false
    var mutedSessionIds: Set<UUID> = []
    var mutedPatternTypes: Set<String> = []  // NotificationType.rawValue
}

class NotificationPreferencesManager: ObservableObject {
    static let shared = NotificationPreferencesManager()

    @Published var preferences: NotificationPreferences {
        didSet { save() }
    }

    func shouldNotify(sessionId: UUID, type: NotificationType) -> Bool {
        guard preferences.enableSystemNotifications else { return false }
        guard !preferences.mutedSessionIds.contains(sessionId) else { return false }
        guard !preferences.mutedPatternTypes.contains(type.rawValue) else { return false }
        return true
    }

    func toggleMuteSession(_ sessionId: UUID) {
        if preferences.mutedSessionIds.contains(sessionId) {
            preferences.mutedSessionIds.remove(sessionId)
        } else {
            preferences.mutedSessionIds.insert(sessionId)
        }
    }
}
```

---

## 19단계: Custom Pattern Editor

```
사용자 정의 알림 패턴 추가 기능:

CustomPattern:
- id: UUID
- name: String
- pattern: String (정규식)
- type: NotificationType
- isEnabled: Bool

CustomPatternMatcher:
- patterns: [CustomPattern]
- UserDefaults에 저장
- match(text:) -> NotificationType?

CustomPatternEditorView:
- 패턴 목록 표시
- 추가/편집/삭제 UI
- 정규식 테스트 기능
```

### 핵심 코드 패턴

```swift
struct CustomPattern: Identifiable, Codable {
    var id = UUID()
    var name: String
    var pattern: String
    var type: NotificationType
    var isEnabled: Bool = true

    var compiledRegex: NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
    }
}

class CustomPatternMatcher: ObservableObject {
    static let shared = CustomPatternMatcher()

    @Published var patterns: [CustomPattern] = [] {
        didSet { save() }
    }

    func match(text: String) -> NotificationType? {
        for pattern in patterns where pattern.isEnabled {
            guard let regex = pattern.compiledRegex else { continue }
            let range = NSRange(text.startIndex..., in: text)
            if regex.firstMatch(in: text, range: range) != nil {
                return pattern.type
            }
        }
        return nil
    }
}
```

---

## 20단계: Logger

```
전역 로깅 시스템:

Logger:
- static func debug(_:), info(_:), warning(_:), error(_:)
- 로그 레벨 필터링
- 파일/콘솔 출력 옵션
```

### 핵심 코드 패턴

```swift
enum LogLevel: Int, Comparable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

class Logger {
    static var minimumLevel: LogLevel = .info

    static func debug(_ message: String, file: String = #file, line: Int = #line) {
        log(.debug, message, file: file, line: line)
    }

    static func info(_ message: String, file: String = #file, line: Int = #line) {
        log(.info, message, file: file, line: line)
    }

    static func warning(_ message: String, file: String = #file, line: Int = #line) {
        log(.warning, message, file: file, line: line)
    }

    static func error(_ message: String, file: String = #file, line: Int = #line) {
        log(.error, message, file: file, line: line)
    }

    private static func log(_ level: LogLevel, _ message: String, file: String, line: Int) {
        guard level >= minimumLevel else { return }

        let fileName = (file as NSString).lastPathComponent
        let timestamp = ISO8601DateFormatter().string(from: Date())
        print("[\(timestamp)] [\(level)] [\(fileName):\(line)] \(message)")
    }
}
```

---

## 21단계: Resizable Sidebar

```
Notes 사이드바 너비 조절 기능:

ResizableSidebar:
- @Binding width: CGFloat
- 최소/최대 너비 제약
- 드래그 가능한 divider
- 더블 클릭으로 기본 너비 복원
```

### 핵심 코드 패턴

```swift
struct ResizableSidebar<Content: View>: View {
    @Binding var width: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat
    let defaultWidth: CGFloat
    let content: () -> Content

    @State private var isDragging = false

    var body: some View {
        HStack(spacing: 0) {
            // Draggable divider
            Rectangle()
                .fill(isDragging ? Color.accentColor.opacity(0.5) : Color.gray.opacity(0.2))
                .frame(width: 4)
                .onHover { hovering in
                    if hovering { NSCursor.resizeLeftRight.push() }
                    else { NSCursor.pop() }
                }
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            isDragging = true
                            let newWidth = width - value.translation.width
                            width = min(max(newWidth, minWidth), maxWidth)
                        }
                        .onEnded { _ in isDragging = false }
                )
                .onTapGesture(count: 2) {
                    withAnimation { width = defaultWidth }
                }

            // Content
            content()
                .frame(width: width)
        }
    }
}
```

---

## 요약: 개발 순서 (최종)

1. **프로젝트 설정** - Package.swift, 기본 구조
2. **모델** - TerminalSession, SplitNode, SplitViewState
3. **TerminalController** - SwiftTerm 래핑
4. **SessionManager** - 세션/컨트롤러 관리, Split view 상태
5. **MainViewModel** - UI 상태 관리, 비즈니스 로직
6. **MainView** - NavigationSplitView 구조
7. **TerminalView** - NSViewRepresentable
8. **SplitTerminalView** - 재귀적 분할 뷰
9. **사이드바** - TerminalListView, FavoritesView
10. **키보드 단축키** - Commands
11. **알림 시스템** - Claude Code 연동
12. **Notes 사이드바** - Markdown 편집/미리보기
13. **CPU 최적화** - 정규식 캐싱, 쓰로틀링, 버퍼링
14. **IME 지원** - 한글 입력 (NSTextInputClient)
15. **Dock Badge** - 읽지 않은 알림 개수 표시
16. **Syntax Highlighting** - zsh 구문 강조 설치
17. **Custom Color Settings** - 사용자 커스텀 색상
18. **Notification Preferences** - 알림 필터링/자동 핸들
19. **Custom Pattern Editor** - 사용자 정의 알림 패턴
20. **Logger** - 전역 로깅 시스템
21. **Resizable Sidebar** - Notes 사이드바 너비 조절
