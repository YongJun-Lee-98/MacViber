# Windows MultiTerm 개발 가이드 (codex-dev) - Tauri + Rust + React

이 문서는 `DEVELOPMENT_GUIDE.md`의 MacViber 기능을 **Windows 환경에서 동일하게 구현**하기 위한 가이드입니다.
Tauri + Rust + React + xterm.js 조합을 기준으로 작성했습니다.

---

## 1단계: 프로젝트 초기 설정

```
Windows 앱 "MultiTerm"를 만들어줘.
- Tauri + Rust + React(Vite) 사용
- 터미널 UI: xterm.js (+ xterm-addon-fit)
- Markdown Notes: react-markdown + remark-gfm
- Rust 백엔드: portable-pty + tokio + serde + regex
- 최소 Windows 10 2004 이상
- build.ps1 / install.ps1 / dev.ps1 스크립트 포함
```

### 예상 디렉토리 구조

```
MultiTerm/
├── package.json
├── src/
│   ├── app/
│   │   └── App.tsx
│   ├── core/
│   │   ├── logger.ts
│   │   └── parser/
│   │       ├── claudeNotificationDetector.ts
│   │       └── customPatternMatcher.ts
│   ├── domain/
│   │   ├── models/
│   │   │   ├── terminalSession.ts
│   │   │   ├── splitNode.ts
│   │   │   ├── claudeNotification.ts
│   │   │   ├── customPattern.ts
│   │   │   ├── note.ts
│   │   │   ├── notificationPreferences.ts
│   │   │   └── customColorSettings.ts
│   │   └── services/
│   │       ├── sessionStore.ts
│   │       ├── themeStore.ts
│   │       ├── favoritesStore.ts
│   │       ├── noteStore.ts
│   │       └── notificationPreferencesStore.ts
│   ├── presentation/
│   │   ├── viewModels/
│   │   │   └── useMainViewModel.ts
│   │   └── views/
│   │       ├── MainView.tsx
│   │       ├── components/
│   │       │   └── ResizableSidebar.tsx
│   │       ├── terminal/
│   │       │   ├── TerminalView.tsx
│   │       │   ├── TerminalPaneView.tsx
│   │       │   └── SplitTerminalView.tsx
│   │       ├── sidebar/
│   │       │   ├── TerminalListView.tsx
│   │       │   └── FavoritesView.tsx
│   │       ├── notification/
│   │       │   ├── NotificationGridView.tsx
│   │       │   └── NotificationCardView.tsx
│   │       └── note/
│   │           ├── MarkdownEditorView.tsx
│   │           ├── MarkdownPreviewView.tsx
│   │           └── RightSidebarView.tsx
│   └── assets/
│       └── appicon.png
├── src-tauri/
│   ├── Cargo.toml
│   ├── tauri.conf.json
│   └── src/
│       ├── main.rs
│       ├── core/
│       │   └── logger.rs
│       ├── terminal/
│       │   ├── mod.rs
│       │   ├── pty_manager.rs
│       │   └── pty_session.rs
│       ├── parser/
│       │   ├── claude_notification_detector.rs
│       │   └── custom_pattern_matcher.rs
│       └── services/
│           ├── session_manager.rs
│           ├── theme_manager.rs
│           ├── favorites_manager.rs
│           ├── note_manager.rs
│           └── notification_preferences_manager.rs
└── Scripts/
    ├── build.ps1
    ├── install.ps1
    └── dev.ps1
```

---

## 2단계: 핵심 데이터 모델 (TypeScript)

```ts
export type SessionStatus = "idle" | "running" | "waitingInput" | "terminated";

export interface TerminalSession {
  id: string;
  name: string;
  workingDirectory: string;
  status: SessionStatus;
  alias?: string;
  isLocked: boolean;
  hasUnreadNotification: boolean;
  lastActivity: string;
  displayName: string;
}

export type SplitNode =
  | { type: "terminal"; id: string; sessionId: string }
  | { type: "split"; id: string; direction: "horizontal" | "vertical"; first: SplitNode; second: SplitNode; ratio: number };

export interface SplitViewState {
  rootNode?: SplitNode;
  focusedPaneId?: string;
}
```

---

## 3단계: TerminalController (핵심) - Rust + xterm.js

### Rust: ConPTY 래핑 (portable-pty)

```rust
#[derive(serde::Serialize)]
struct TerminalOutput {
    session_id: String,
    data: String,
}

#[tauri::command]
fn terminal_create_session(state: tauri::State<PtyManager>, session_id: String, cwd: String) -> Result<(), String> {
    state.create_session(session_id, cwd).map_err(|e| e.to_string())
}

#[tauri::command]
fn terminal_send_input(state: tauri::State<PtyManager>, session_id: String, data: String) -> Result<(), String> {
    state.send_input(&session_id, &data).map_err(|e| e.to_string())
}
```

```rust
pub fn create_session(&self, session_id: String, cwd: String) -> anyhow::Result<()> {
    let pty_system = portable_pty::native_pty_system();
    let pair = pty_system.openpty(portable_pty::PtySize { rows: 30, cols: 120, pixel_width: 0, pixel_height: 0 })?;

    let mut cmd = portable_pty::CommandBuilder::new("pwsh.exe");
    cmd.cwd(std::path::PathBuf::from(&cwd));
    cmd.env("TERM", "xterm-256color");
    cmd.env("PWD", &cwd);

    let child = pair.slave.spawn_command(cmd)?;
    let mut reader = pair.master.try_clone_reader()?;

    self.sessions.insert(session_id.clone(), PtySession::new(pair.master, child));

    let app_handle = self.app_handle.clone();
    std::thread::spawn(move || {
        let mut buf = [0u8; 8192];
        loop {
            let size = match reader.read(&mut buf) {
                Ok(0) | Err(_) => break,
                Ok(n) => n,
            };
            let data = String::from_utf8_lossy(&buf[..size]).to_string();
            let _ = app_handle.emit_all("terminal-output", TerminalOutput { session_id: session_id.clone(), data });
        }
        let _ = app_handle.emit_all("terminal-exit", session_id);
    });

    Ok(())
}
```

### React: xterm.js 연결

```tsx
useEffect(() => {
  const term = new Terminal({ fontFamily: "Cascadia Mono", cursorBlink: true });
  const fit = new FitAddon();
  term.loadAddon(fit);
  term.open(containerRef.current!);
  fit.fit();

  const unlisten = listen<TerminalOutput>("terminal-output", (event) => {
    if (event.payload.session_id === sessionId) {
      term.write(event.payload.data);
    }
  });

  term.onData((data) => invoke("terminal_send_input", { sessionId, data }));
  invoke("terminal_create_session", { sessionId, cwd: workingDirectory });

  return () => {
    unlisten.then((f) => f());
    term.dispose();
  };
}, [sessionId, workingDirectory]);
```

> ⚠️ **주의**: React에서 세션이 바뀔 때 `key={sessionId}`로 TerminalView를 강제 재마운트해야 합니다.

---

## 4단계: SessionManager (프론트 상태 관리)

Zustand(또는 Redux)로 세션/분할 상태를 관리합니다.

```
sessions: TerminalSession[]
selectedSessionId?: string
splitView: SplitViewState

createSession(name, cwd)
closeSession, renameSession, duplicateSession
setSessionAlias, toggleSessionLock

splitPane(paneId, direction, newSessionId)
removePaneFromSplit(paneId)
updatePaneSession(paneId, newSessionId)
findPaneIdForSession(sessionId)
swapPaneSessions(paneId1, paneId2)
```

### ⚠️ 중요: 종료 이벤트 전까지 terminated 처리 금지

`terminal-exit` 이벤트가 오기 전에는 상태를 `terminated`로 변경하지 않습니다.

---

## 5단계: MainViewModel (React Hook)

```
useMainViewModel:
- selectedSessionId
- focusedPaneId
- showNotificationGrid
- columnVisibility

터미널 생성:
- addNewTerminal() -> dialog.open({ directory: true })
- addNewTerminalAtHome()
```

### ⚠️ 핵심 설계 원칙 1: FocusedPaneId는 Store로만 변경

```ts
// ❌ focusedPaneId = paneId
// ✅ sessionStore.setFocusedPane(paneId)
```

### ⚠️ 핵심 설계 원칙 2: FolderPicker 사용 전 상태 캡처

```ts
const wasSplit = isSplitViewActive;
const capturedPaneId = focusedPaneId;
const folder = await open({ directory: true });
if (folder) {
  const session = createSession(...);
  if (wasSplit && capturedPaneId) updatePaneSession(capturedPaneId, session.id);
  else selectSession(session.id);
}
```

### ⚠️ 핵심 설계 원칙 3: SWAP 로직

```ts
if (isSplitViewActive && focusedPaneId) {
  const existing = findPaneIdForSession(sessionId);
  if (existing && existing !== focusedPaneId) swapPaneSessions(focusedPaneId, existing);
  else updatePaneSession(focusedPaneId, sessionId);
} else {
  selectSession(sessionId);
}
```

---

## 6단계: View 계층 구조 (React)

```
MainView
- Layout Grid (Left / Center / Right)
  - Left: Sidebar (TerminalListView + FavoritesView)
  - Center: Content (NotificationGridView / SplitTerminalView / TerminalContainerView / EmptyStateView)
  - Right: Notes Sidebar (ResizableSidebar)
```

---

## 7단계: 사이드바 구성

```
TerminalListView:
- selection 유지
- Favorites 섹션
- Terminals 섹션

TerminalListItemView:
- 상태 인디케이터 (색상 원)
- displayName
- 경로 표시
- hover 시 Lock/Close 버튼
```

Selection 바인딩:

```ts
onClick={() => onSelectSession(session.id)}
```

---

## 8단계: 즐겨찾기 시스템

```
FavoritesStore:
- favorites: FavoriteFolder[]
- JSON 저장 (appDataDir)

FavoriteFolder:
- id, path, name

FavoritesView:
- 클릭 시 onOpenTerminal(path)
- 드래그로 재정렬
- 컨텍스트 메뉴로 삭제
```

---

## 9단계: 알림 시스템 (Claude Code 연동)

```
ClaudeNotificationDetector:
- 터미널 출력에서 키워드/패턴 감지 (Rust에서 처리 권장)

ClaudeNotification:
- id, sessionId, type, message, timestamp, isRead

NotificationGridView:
- 알림 카드 리스트
- 응답 입력
- 해당 세션 이동
```

### 시스템 알림
- `tauri-plugin-notification`으로 토스트 표시
- 필터링은 NotificationPreferences로 제어

---

## 10단계: 키보드 단축키

React에서 앱 내부 단축키 처리:

```ts
useEffect(() => {
  const handler = (e: KeyboardEvent) => {
    if (e.ctrlKey && e.key === "t") addNewTerminal();
    if (e.ctrlKey && e.key === "w") closeTerminal();
    if (e.ctrlKey && e.key === "d" && e.shiftKey) splitVertical();
    if (e.ctrlKey && e.key === "d" && !e.shiftKey) splitHorizontal();
  };
  window.addEventListener("keydown", handler);
  return () => window.removeEventListener("keydown", handler);
}, []);
```

---

## 11단계: Notes 사이드바

```
NoteStore:
- 파일 위치: %AppData%\\MultiTerm\\note.md
- load(), save()

NoteViewModel:
- selectedTab (edit/preview)
- content
- saveNote() 수동 저장

RightSidebarView:
- Header: Notes + Edit/Preview
- Content: MarkdownEditorView / MarkdownPreviewView
- Footer: Save 버튼 + 저장 성공 메시지
```

```ts
await writeTextFile(notePath, content);
setShowSavedMessage(true);
setTimeout(() => setShowSavedMessage(false), 2000);
```

> ⚠️ **주의**: 자동 저장은 CPU 사용량 증가 가능. 수동 저장 권장.

---

## 12단계: CPU 최적화 패턴

### 1. 정규식 캐싱 (Rust)

```rust
static PATTERNS: once_cell::sync::Lazy<Vec<(Regex, NotificationType)>> = Lazy::new(|| {
    vec![(Regex::new("\\?\\s*$").unwrap(), NotificationType::Question)]
});
```

### 2. 드래그 이벤트 쓰로틀링

```ts
if (performance.now() - lastDragTime < 16) return;
lastDragTime = performance.now();
```

### 3. 터미널 출력 버퍼링 (Rust)

```rust
// 일정 간격으로 출력 묶어서 emit
```

### 4. 상태 변경 디바운싱

```ts
const debounced = useDebounce(value, 16);
```

---

## 13단계: Split View 비율 제어

React에서 커스텀 Divider로 비율 조절:

```tsx
const [ratio, setRatio] = useState(0.5);
const min = 0.15;
const max = 0.85;
```

```tsx
<div className="split">
  <div style={{ width: `${ratio * 100}%` }} />
  <div className="divider" onPointerDown={startDrag} />
  <div style={{ width: `${(1 - ratio) * 100}%` }} />
</div>
```

---

## 14단계: IME 지원 (한글 입력)

`xterm.js`는 기본 IME 입력을 지원합니다.
IME 입력 문제가 있다면 `rendererType: "dom"` 설정을 우선 적용하세요.

---

## 15단계: 읽지 않은 알림 표시 (Windows 대응)

Windows는 Dock Badge가 없으므로 창 제목에 카운트를 표시:

```ts
const unread = notifications.filter(n => !n.isRead).length;
appWindow.setTitle(unread > 0 ? `MultiTerm (${unread})` : "MultiTerm");
```

---

## 16단계: Syntax Highlighting 설치 (PowerShell)

```
PowerShell의 PSReadLine 설정 추가:
- Install-Module PSReadLine -Force
- $PROFILE에 색상 설정 추가
```

> ⚠️ **주의**: 시스템 설정 변경은 사용자 확인 후 실행.

---

## 17단계: Custom Color Settings

```ts
export interface CustomColorSettings {
  useCustomBackground: boolean;
  useCustomForeground: boolean;
  backgroundColor?: string;
  foregroundColor?: string;
}
```

`ThemeStore`에서 effective 색상을 계산해 xterm 테마에 적용합니다.

---

## 18단계: Notification Preferences

```
NotificationPreferences:
- enableSystemNotifications
- enableSoundAlerts
- autoHandlePermissions
- mutedSessionIds
- mutedPatternTypes
```

`shouldNotify(sessionId, type)`에서 필터링.

---

## 19단계: Custom Pattern Editor

```
CustomPattern:
- id, name, pattern, type, isEnabled

CustomPatternMatcher:
- 패턴 저장/로드
- match(text) -> NotificationType?
```

---

## 20단계: Logger

Rust 로거:

```rust
pub enum LogLevel { Debug, Info, Warn, Error }

pub fn log(level: LogLevel, message: &str, file: &str, line: u32) {
    // stdout + 파일 로깅 옵션
}
```

---

## 21단계: Resizable Sidebar

React에서 드래그로 우측 사이드바 너비 조절:

```tsx
const [width, setWidth] = useState(320);
const min = 240;
const max = 520;
```

---

## 요약: 개발 순서

1. **프로젝트 설정** - Tauri + Rust + React + xterm.js
2. **모델** - TerminalSession, SplitNode, SplitViewState
3. **TerminalController** - ConPTY 래핑 + 이벤트 스트림
4. **SessionManager** - 세션/분할 상태
5. **MainViewModel** - UI 상태/비즈니스 로직
6. **MainView** - 3열 레이아웃
7. **TerminalView** - xterm.js 기반
8. **SplitTerminalView** - 재귀 분할
9. **사이드바** - 터미널 목록/즐겨찾기
10. **키보드 단축키**
11. **알림 시스템**
12. **Notes 사이드바**
13. **CPU 최적화**
14. **IME 지원**
15. **읽지 않은 알림 표시**
16. **Syntax Highlighting 설치**
17. **Custom Color Settings**
18. **Notification Preferences**
19. **Custom Pattern Editor**
20. **Logger**
21. **Resizable Sidebar**
