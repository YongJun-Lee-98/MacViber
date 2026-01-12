# MacViber 프로젝트 구조도

## Git 이력 요약 (최근 30 커밋)

### 주요 마일스톤
```
53fd9f8 refactor: rename project from MultiTerm to MacViber
230f046 chore: prepare for v1.0.0 release
302820a feat: auto-update checker with GitHub Releases integration
668b584 feat: add configurable output buffer delay setting (v1.1.2)
3c1727f fix: correct background color rendering for wide characters (Korean/CJK)
d35279c feat: add Korean IME composition display support (v1.3.0)
fe667a6 fix: enable copy/paste in Notes sidebar (v1.3.2)
e8f8502 style: increase Notes sidebar initial width to 350 (v1.3.3)
de7df51 fix: resolve scroll jumping and selection loss during fast terminal output
```

### 버전 히스토리
- v1.0.0: 초기 릴리즈
- v1.1.x: 출력 버퍼 설정, 버그 수정
- v1.2.x: 즐겨찾기 개선, 업데이트 체커
- v1.3.x: 한글 IME 지원, Notes 기능 개선

---

## 현재 디렉토리 구조

```
MultiTerm/
├── Package.swift                 # SPM 설정 (SwiftTerm + swift-argument-parser)
├── LocalPackages/
│   └── SwiftTerm/               # 로컬 SwiftTerm 패키지 (수정됨)
│       └── Sources/SwiftTerm/
│           ├── Mac/             # macOS 터미널 뷰
│           ├── iOS/             # iOS 터미널 뷰
│           └── [Core files]     # 터미널 에뮬레이션 핵심
│
├── MacViber/
│   ├── App/
│   │   └── MacViberApp.swift    # 앱 진입점, Commands
│   │
│   ├── Core/
│   │   ├── Logger.swift
│   │   ├── Terminal/
│   │   │   ├── TerminalController.swift      # SwiftTerm 래핑
│   │   │   └── TerminalConfiguration.swift   # 설정
│   │   └── Parser/
│   │       ├── ClaudeNotificationDetector.swift  # 알림 감지
│   │       └── CustomPatternMatcher.swift        # 사용자 정의 패턴
│   │
│   ├── Domain/
│   │   ├── Models/
│   │   │   ├── TerminalSession.swift     # 세션 모델
│   │   │   ├── SplitNode.swift           # 분할 뷰 트리 구조
│   │   │   ├── TerminalTheme.swift       # 테마
│   │   │   ├── ClaudeNotification.swift  # 알림 모델
│   │   │   ├── CustomPattern.swift       # 사용자 정의 패턴
│   │   │   ├── Note.swift                # 노트 모델
│   │   │   ├── NotificationPreferences.swift
│   │   │   ├── CustomColorSettings.swift
│   │   │   └── UpdatePreferences.swift
│   │   │
│   │   └── Services/
│   │       ├── SessionManager.swift      # 핵심: 세션/분할 상태 관리
│   │       ├── ThemeManager.swift
│   │       ├── FavoritesManager.swift
│   │       ├── NoteManager.swift
│   │       ├── NotificationPreferencesManager.swift
│   │       ├── SyntaxHighlightingInstaller.swift
│   │       └── UpdateChecker.swift
│   │
│   ├── Presentation/
│   │   ├── ViewModels/
│   │   │   ├── MainViewModel.swift
│   │   │   ├── TerminalListViewModel.swift
│   │   │   ├── NotificationGridViewModel.swift
│   │   │   ├── NotificationSettingsViewModel.swift
│   │   │   └── NoteViewModel.swift
│   │   │
│   │   └── Views/
│   │       ├── MainView.swift            # 메인 레이아웃
│   │       ├── Components/
│   │       │   └── ResizableSidebar.swift
│   │       ├── Terminal/
│   │       │   ├── TerminalView.swift        # NSViewRepresentable
│   │       │   ├── TerminalPaneView.swift    # 개별 패널
│   │       │   └── SplitTerminalView.swift   # 분할 뷰 컨테이너
│   │       ├── Sidebar/
│   │       │   ├── TerminalListView.swift
│   │       │   └── FavoritesView.swift
│   │       ├── Notification/
│   │       │   ├── NotificationGridView.swift
│   │       │   └── NotificationCardView.swift
│   │       ├── Settings/
│   │       │   ├── ThemePickerView.swift
│   │       │   ├── ColorSettingsView.swift
│   │       │   ├── NotificationSettingsView.swift
│   │       │   ├── CustomPatternListView.swift
│   │       │   ├── CustomPatternEditorView.swift
│   │       │   └── UpdateAlertView.swift
│   │       └── Note/
│   │           ├── MarkdownEditorView.swift
│   │           ├── MarkdownPreviewView.swift
│   │           └── RightSidebarView.swift
│   │
│   └── Resources/
│       └── Info.plist
│
├── Scripts/
│   ├── build-app.sh
│   ├── install-app.sh
│   ├── setup.sh
│   └── create-dmg.sh
│
└── build/
    └── MacViber.app
```

---

## 핵심 컴포넌트 관계도

```
┌─────────────────────────────────────────────────────────────────┐
│                        MacViberApp                              │
│                    (Entry Point + Commands)                     │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                         MainView                                │
│                  NavigationSplitView Layout                     │
├─────────────────┬─────────────────────────┬─────────────────────┤
│   Sidebar       │      Detail             │    Right Sidebar    │
│ TerminalList    │ SplitTerminal/Grid      │    Notes            │
└─────────────────┴─────────────────────────┴─────────────────────┘
        │                   │                        │
        ▼                   ▼                        ▼
┌───────────────┐  ┌────────────────┐      ┌────────────────┐
│MainViewModel  │  │SplitTerminalView│     │NoteViewModel   │
└───────────────┘  └────────────────┘      └────────────────┘
        │                   │
        ▼                   ▼
┌─────────────────────────────────────────┐
│            SessionManager               │
│  (Singleton: Sessions + SplitState)     │
├─────────────────────────────────────────┤
│  - sessions: [TerminalSession]          │
│  - controllers: [UUID: TerminalController]
│  - splitViewState: SplitViewState       │
│  - notifications: [ClaudeNotification]  │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│         TerminalController              │
│    (SwiftTerm LocalProcessTerminalView  │
│           Wrapper)                      │
├─────────────────────────────────────────┤
│  - sessionId: UUID                      │
│  - terminalView: CustomTerminalView     │
│  - notificationPublisher                │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│          CustomTerminalView             │
│   (LocalProcessTerminalView 상속)       │
├─────────────────────────────────────────┤
│  - NSTextInputClient (IME)              │
│  - 수동 Selection 추적                  │
│  - 출력 버퍼링                          │
│  - 알림 감지 (onOutput)                 │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│              SwiftTerm                  │
│    (LocalPackages/SwiftTerm)            │
├─────────────────────────────────────────┤
│  - Terminal emulation core              │
│  - PTY management                       │
│  - Buffer management                    │
│  - Rendering (NSView)                   │
└─────────────────────────────────────────┘
```

---

## 주요 기능 목록

### 터미널 관리
- [x] 다중 터미널 세션
- [x] Split View (최대 4개 패널)
- [x] 터미널 별명(Alias)
- [x] 터미널 잠금
- [x] 즐겨찾기 폴더

### Claude Code 연동
- [x] 알림 자동 감지 (질문, 권한, 완료, 에러)
- [x] 알림 그리드 뷰
- [x] 시스템 알림 (Notification Center)
- [x] Dock Badge

### 편의 기능
- [x] 한글 IME 지원
- [x] 텍스트 복사(cmd+c) 수정
- [x] Notes 사이드바 (Markdown)
- [x] 테마 시스템
- [x] 커스텀 색상 설정
- [x] 자동 업데이트 체커

### 키보드 단축키
- Cmd+T: 새 터미널
- Cmd+W: 터미널 닫기
- Cmd+D: 좌우 분할
- Shift+Cmd+D: 상하 분할
- Alt+Cmd+]/[: 패널 이동
