# MacViber Changelog (2026-01-23 ~ 2026-01-24)

## Overview

이 기간 동안 MacViber의 핵심 백엔드 로직을 **Rust로 마이그레이션**하는 대규모 작업이 진행되었습니다. 크로스 플랫폼(macOS, Linux, Windows) 지원을 위한 기반을 구축했습니다.

---

## 2026-01-23

### fix: resolve memory leak in session subscription management
**커밋**: `6fe51efa`

세션 구독 관리에서 발생하던 메모리 누수 문제를 해결했습니다.

**변경 내용**:
- 세션별 cancellables 딕셔너리 추가로 고아 구독(orphan subscriptions) 방지
- 개별 세션 종료 시 구독 정리
- `TerminalController.terminate()`에서 테마/색상 구독 명시적 취소
- `terminateAllSessions()`에서 모든 세션 cancellables 정리

**영향받은 파일**: SessionManager 관련 파일

---

### refactor: extract SplitNode tree operations from SessionManager
**커밋**: `9c8cbaa3`

SessionManager에서 SplitNode 트리 조작 로직을 분리하여 코드 중복을 제거했습니다.

**변경 내용**:
- `SplitNode+Actions.swift` 생성 (순수 트리 조작 메서드)
- `split()`, `removingPane()`, `updatingSession()`, `paneId(for:)`, `parentSplitInfo()` 메서드 추가
- SessionManager에서 SplitNode 확장 메서드 사용하도록 리팩토링
- SessionManager에서 약 80줄의 중복 트리 순회 코드 제거

**영향받은 파일**:
- `MacViber/Backend/Domain/SplitNode+Actions.swift` (신규)
- `MacViber/Backend/Core/SessionManager.swift`

---

### refactor: split backend and UI directories
**커밋**: `99d55ee8`

백엔드와 UI 로직을 디렉토리 수준에서 분리했습니다.

**변경 내용**:
- `Core/`와 `Domain/`을 `MacViber/Backend/`로 이동 (백엔드 로직 격리)
- `App/`과 `Presentation/`을 `MacViber/UI/`로 이동 (SwiftUI 분리)
- `git mv`를 사용하여 파일 히스토리 보존 (향후 Rust FFI 추출 용이)

**새 디렉토리 구조**:
```
MacViber/
├── Backend/
│   ├── Core/
│   ├── Domain/
│   └── FFI/
└── UI/
    ├── App/
    └── Presentation/
```

---

## 2026-01-24

### feat: add Rust core with FFI scaffolding for cross-platform support
**커밋**: `cef2e72a`

크로스 플랫폼 지원을 위한 Rust 코어 프로젝트와 FFI 기반을 구축했습니다.

**변경 내용**:
- Rust 프로젝트 초기화 (`core/`) - tokio, portable-pty, regex 포함
- C ABI 바인딩을 위한 FFI 레이어 추가 (`ffi.rs`)
- Swift FFI 래퍼 생성 (`RustCore.swift`) - dlopen/dlsym 사용
- Rust + Swift 통합 빌드 스크립트 추가
- C 헤더 자동 생성을 위한 cbindgen 설정
- 모델 포함: Session, SplitNode, Notification
- 서비스 스텁 포함: PatternMatcher, NotificationDetector

**새 파일**:
- `core/Cargo.toml`
- `core/src/lib.rs`
- `core/src/ffi.rs`
- `core/src/models/` (session.rs, split_node.rs, notification.rs)
- `core/src/services/` (pattern_matcher.rs, notification_detector.rs)
- `MacViber/Backend/FFI/RustCore.swift`

---

### fix: update RustCore.swift to use proper dylib loading paths
**커밋**: `df250384`

RustCore.swift의 동적 라이브러리 로딩 경로를 수정했습니다.

**변경 내용**:
- 개발/프로덕션 환경을 위한 다중 검색 경로를 가진 `loadLibrary()` 추가
- FFI 통합 테스트 추가 (`Tests/FFITest.swift`)
- 모든 FFI 함수가 캐시된 라이브러리 핸들 사용

**영향받은 파일**:
- `MacViber/Backend/FFI/RustCore.swift`
- `Tests/FFITest.swift` (신규)

---

### feat: add PatternMatcher and NotificationDetector FFI bindings
**커밋**: `35462529`

패턴 매칭과 알림 감지를 위한 FFI 바인딩을 추가했습니다.

**Rust FFI 함수** (`core/src/ffi.rs`):
```rust
// PatternMatcher
pattern_matcher_create() -> *mut PatternMatcher
pattern_matcher_destroy(handle)
pattern_matcher_add_pattern(handle, name, regex) -> i32
pattern_matcher_remove_pattern(handle, name) -> i32
pattern_matcher_match(handle, text, out_name, out_len) -> i32
pattern_matcher_invalidate_cache(handle)

// NotificationDetector
notification_detector_create() -> *mut NotificationDetector
notification_detector_destroy(handle)
notification_detector_detect(handle, output, out_notification) -> i32
notification_detector_reset(handle)
```

**Swift 래퍼**:
- `RustPatternMatcher` 클래스
- `RustNotificationDetector` 클래스

---

### feat: add SplitViewState FFI bindings for split view management
**커밋**: `08ef5b8f`

분할 뷰 관리를 위한 FFI 바인딩을 추가했습니다.

**Rust 구현** (`core/src/models/split_node.rs`):
- `all_pane_ids()` - 모든 패인 ID 조회
- 세션 검색 및 네비게이션 메서드

**FFI 함수**:
```rust
split_view_state_create() -> *mut SplitViewState
split_view_state_destroy(handle)
split_view_state_enter(handle, session_id)
split_view_state_exit(handle)
split_view_state_is_active(handle) -> bool
split_view_state_split_pane(handle, direction, session_id) -> i32
split_view_state_close_pane(handle, pane_id) -> i32
split_view_state_focus_pane(handle, pane_id) -> i32
split_view_state_focus_next/previous/up/down/left/right(handle) -> i32
split_view_state_get_focused_pane_id(handle, out_id) -> i32
split_view_state_get_all_pane_ids(handle, out_ids, max_count) -> i32
```

**Swift 래퍼**: `RustSplitViewState` 클래스

---

### feat: add session management FFI functions
**커밋**: `8ff1fae8`

세션 관리를 위한 FFI 함수를 추가했습니다.

**Rust 모델 확장** (`core/src/models/session.rs`):
- `alias` 필드 추가
- `is_locked` 필드 추가
- `SessionStatus` 열거형: Idle, Running, WaitingForInput, Terminated

**FFI 함수**:
```rust
core_rename_session(handle, session_id, new_name) -> i32
core_set_session_alias(handle, session_id, alias) -> i32
core_toggle_session_lock(handle, session_id) -> i32
core_set_session_status(handle, session_id, status) -> i32
core_get_session_info(handle, session_id, out_info) -> i32
core_get_all_session_ids(handle, out_ids, max_count) -> i32
```

**데이터 구조**: `SessionInfoFFI` (세션 정보 조회용)

---

### feat: implement PTY with portable-pty for cross-platform terminal
**커밋**: `09871a7d`

크로스 플랫폼 터미널을 위한 실제 PTY 구현을 추가했습니다.

**변경 내용**:
- PTY 스텁을 실제 portable-pty 구현으로 교체
- `core/src/terminal/pty.rs` 추가

**FFI 함수**:
```rust
pty_spawn(working_dir, cols, rows) -> *mut PtyHandle
pty_destroy(handle)
pty_write(handle, data, len) -> i32
pty_read(handle, buffer, buffer_len) -> i32
pty_resize(handle, cols, rows) -> i32
pty_is_alive(handle) -> bool
```

**PtyHandle**: 스레드 안전한 reader/writer를 포함한 portable-pty 래퍼

---

### feat: extend Swift FFI wrappers with session management and RustPty class
**커밋**: `bc32a798`

Swift FFI 래퍼를 세션 관리와 PTY 클래스로 확장했습니다.

**RustCore 클래스 확장**:
```swift
func renameSession(_ sessionId: UUID, newName: String) -> Bool
func setSessionAlias(_ sessionId: UUID, alias: String?) -> Bool
func toggleSessionLock(_ sessionId: UUID) -> Bool
func setSessionStatus(_ sessionId: UUID, status: SessionStatus) -> Bool
func getSessionInfo(_ sessionId: UUID) -> SessionInfo?
var allSessionIds: [UUID]
```

**RustPty 클래스** (신규):
```swift
init?(workingDirectory: String, cols: UInt16, rows: UInt16)
var isAlive: Bool
func write(_ data: Data) -> Bool
func read() -> Data?
func resize(cols: UInt16, rows: UInt16) -> Bool
func startAsyncRead(onData: @escaping (Data) -> Void)
func stopAsyncRead()
```

---

### chore: bump build number to 58
**커밋**: `948b9e5d`

빌드 번호를 53에서 58로 증가했습니다.

**영향받은 파일**: `MacViber/Resources/Info.plist`

---

### chore: remove obsolete development guide documents
**커밋**: `80516649`

더 이상 필요하지 않은 AI 개발 가이드 문서들을 제거했습니다.

**삭제된 파일**:
- `DEVELOPMENT_GUIDE.md`
- `claude-dev.md`
- `codex-dev.md`
- `gemini-guide-tauri.md`
- `memory/00_README.md`
- `memory/01_project_structure.md`
- `memory/02_migration_considerations.md`
- `memory/03_lessons_learned.md`

---

## Architecture Summary

### Before (2026-01-22)
```
MacViber/
├── App/
├── Core/
├── Domain/
├── Presentation/
└── Resources/
```

### After (2026-01-24)
```
MacViber/
├── Backend/
│   ├── Core/           # SessionManager, TerminalController
│   ├── Domain/         # SplitNode, Models
│   └── FFI/            # RustCore.swift (Swift FFI wrappers)
├── UI/
│   ├── App/            # App entry point
│   └── Presentation/   # SwiftUI Views
└── Resources/

core/                   # Rust project (NEW)
├── Cargo.toml
├── src/
│   ├── lib.rs          # Core struct + session management
│   ├── ffi.rs          # C ABI FFI layer (~800 lines)
│   ├── models/
│   │   ├── session.rs
│   │   ├── split_node.rs
│   │   └── notification.rs
│   ├── services/
│   │   ├── pattern_matcher.rs
│   │   └── notification_detector.rs
│   └── terminal/
│       └── pty.rs      # Cross-platform PTY
└── include/
    └── macviber_core.h # Auto-generated C header
```

---

## FFI Test Results

모든 FFI 테스트 통과:
```
Core: init, create_session, rename, alias, lock, status, close ✅
PatternMatcher: add_pattern, match, remove ✅
NotificationDetector: detect, reset ✅
SplitViewState: enter, split, close, navigate ✅
PTY: spawn, write, read, resize, is_alive ✅
```

---

## Next Steps

1. **SessionManager 점진적 교체** - Swift SessionManager에서 RustCore FFI 호출로 전환
2. **TerminalController PTY 교체** - 네이티브 macOS PTY를 RustPty로 교체
3. **Linux/Windows 빌드 테스트** - `cargo build --target x86_64-unknown-linux-gnu`
4. **정적 라이브러리 링킹** - dylib에서 staticlib으로 전환하여 앱 번들에 포함
