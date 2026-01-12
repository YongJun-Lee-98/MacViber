# WinViber 개발 가이드 (Windows 버전)

Claude Code를 사용하여 MacViber의 Windows 버전인 WinViber를 개발할 때 참고할 가이드입니다.

---

## 기술 스택

### Tauri + Rust + React + TypeScript + xterm.js

| macOS (MacViber) | Windows (WinViber) |
|------------------|-------------------|
| Swift/SwiftUI | Rust/Tauri + React |
| SwiftTerm | xterm.js + portable-pty |
| NSViewRepresentable | React Component |
| UserDefaults | tauri-plugin-store |
| NSOpenPanel | Tauri dialog API |
| NSPasteboard | Tauri clipboard API |
| NSApp.dockTile | Windows Overlay Icon |
| NotificationCenter | Tauri Event System |

### Tauri 장점 (vs Electron)

| 특성 | Tauri | Electron |
|------|-------|----------|
| 앱 크기 | ~3-10MB | ~150MB+ |
| 메모리 사용 | ~30-50MB | ~100-300MB |
| 시작 시간 | 빠름 | 느림 |
| 보안 | 강력 (Rust) | 보통 |
| 백엔드 | Rust (네이티브) | Node.js |

---

## 1단계: 프로젝트 초기 설정

```
Windows용 Tauri + React 앱 "WinViber"을 만들어줘.
- Tauri 2.0 + React + TypeScript + Vite
- xterm.js 라이브러리 (터미널 에뮬레이터)
- portable-pty (Rust PTY 라이브러리)
- tauri-plugin-store (설정 저장)
- tauri-plugin-dialog (파일/폴더 선택)
- tauri-plugin-clipboard-manager (클립보드)
- tauri-plugin-notification (시스템 알림)
- react-markdown (Notes 기능용)
- 최소 Windows 10 (1903+) 타겟 (ConPTY 지원 필수)
```

### 프로젝트 생성

```bash
# Tauri 프로젝트 생성
npm create tauri-app@latest winviber -- --template react-ts

cd winviber

# 추가 의존성 설치
npm install xterm xterm-addon-fit xterm-addon-web-links xterm-addon-unicode11
npm install zustand react-markdown remark-gfm
npm install @tauri-apps/plugin-store @tauri-apps/plugin-dialog
npm install @tauri-apps/plugin-clipboard-manager @tauri-apps/plugin-notification
```

### 예상 디렉토리 구조

```
winviber/
├── package.json
├── vite.config.ts
├── tsconfig.json
├── src-tauri/                         # Rust 백엔드
│   ├── Cargo.toml
│   ├── tauri.conf.json
│   ├── capabilities/
│   │   └── default.json
│   ├── src/
│   │   ├── main.rs
│   │   ├── lib.rs
│   │   ├── terminal/
│   │   │   ├── mod.rs
│   │   │   ├── pty_manager.rs         # PTY 프로세스 관리
│   │   │   └── shell.rs               # 셸 설정
│   │   ├── session/
│   │   │   ├── mod.rs
│   │   │   └── manager.rs             # 세션 관리
│   │   ├── notification/
│   │   │   ├── mod.rs
│   │   │   └── detector.rs            # Claude 알림 감지
│   │   └── commands/
│   │       ├── mod.rs
│   │       ├── terminal_commands.rs   # 터미널 IPC 명령
│   │       └── file_commands.rs       # 파일 관련 명령
│   └── icons/
├── src/                               # React 프론트엔드
│   ├── main.tsx
│   ├── App.tsx
│   ├── components/
│   │   ├── Terminal/
│   │   │   ├── TerminalView.tsx
│   │   │   ├── TerminalPane.tsx
│   │   │   └── SplitTerminalView.tsx
│   │   ├── Sidebar/
│   │   │   ├── TerminalList.tsx
│   │   │   └── Favorites.tsx
│   │   ├── Notification/
│   │   │   ├── NotificationGrid.tsx
│   │   │   └── NotificationCard.tsx
│   │   ├── Settings/
│   │   │   ├── ThemePicker.tsx
│   │   │   ├── ColorSettings.tsx
│   │   │   └── NotificationSettings.tsx
│   │   └── Note/
│   │       ├── MarkdownEditor.tsx
│   │       ├── MarkdownPreview.tsx
│   │       └── RightSidebar.tsx
│   ├── hooks/
│   │   ├── useTerminal.ts
│   │   ├── useSession.ts
│   │   └── useSplitView.ts
│   ├── store/
│   │   ├── sessionStore.ts
│   │   ├── themeStore.ts
│   │   └── notificationStore.ts
│   ├── types/
│   │   ├── terminal.ts
│   │   ├── session.ts
│   │   └── notification.ts
│   ├── utils/
│   │   ├── claudeDetector.ts
│   │   └── logger.ts
│   └── styles/
│       └── global.css
└── public/
```

---

## 2단계: Rust Cargo.toml 설정

```toml
# src-tauri/Cargo.toml

[package]
name = "winviber"
version = "1.0.0"
edition = "2021"

[build-dependencies]
tauri-build = { version = "2", features = [] }

[dependencies]
tauri = { version = "2", features = ["tray-icon"] }
tauri-plugin-store = "2"
tauri-plugin-dialog = "2"
tauri-plugin-clipboard-manager = "2"
tauri-plugin-notification = "2"
tauri-plugin-shell = "2"

serde = { version = "1", features = ["derive"] }
serde_json = "1"
tokio = { version = "1", features = ["full"] }
uuid = { version = "1", features = ["v4", "serde"] }
chrono = { version = "0.4", features = ["serde"] }
regex = "1"
lazy_static = "1"
parking_lot = "0.12"
log = "0.4"
env_logger = "0.11"

# Windows PTY
[target.'cfg(windows)'.dependencies]
portable-pty = "0.8"
conpty = "0.7"

[features]
default = ["custom-protocol"]
custom-protocol = ["tauri/custom-protocol"]
```

---

## 3단계: 핵심 데이터 모델

### Rust 모델 (src-tauri/src/session/mod.rs)

```rust
use serde::{Deserialize, Serialize};
use uuid::Uuid;
use chrono::{DateTime, Utc};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub enum SessionStatus {
    Idle,
    Running,
    WaitingForInput,
    Terminated,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub enum ShellType {
    PowerShell,
    Cmd,
    Wsl,
    GitBash,
}

impl ShellType {
    pub fn get_path(&self) -> &str {
        match self {
            ShellType::PowerShell => "pwsh.exe",  // PowerShell Core, 폴백: powershell.exe
            ShellType::Cmd => "cmd.exe",
            ShellType::Wsl => "wsl.exe",
            ShellType::GitBash => r"C:\Program Files\Git\bin\bash.exe",
        }
    }

    pub fn get_args(&self) -> Vec<&str> {
        match self {
            ShellType::PowerShell => vec!["-NoLogo"],
            ShellType::Cmd => vec![],
            ShellType::Wsl => vec![],
            ShellType::GitBash => vec!["--login", "-i"],
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TerminalSession {
    pub id: Uuid,
    pub name: String,
    pub working_directory: String,
    pub status: SessionStatus,
    pub alias: Option<String>,
    pub is_locked: bool,
    pub has_unread_notification: bool,
    pub last_activity: DateTime<Utc>,
    pub shell_type: ShellType,
}

impl TerminalSession {
    pub fn new(name: String, working_directory: String, shell_type: ShellType) -> Self {
        Self {
            id: Uuid::new_v4(),
            name,
            working_directory,
            status: SessionStatus::Idle,
            alias: None,
            is_locked: false,
            has_unread_notification: false,
            last_activity: Utc::now(),
            shell_type,
        }
    }

    pub fn display_name(&self) -> &str {
        self.alias.as_deref().unwrap_or(&self.name)
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub enum SplitDirection {
    Horizontal,
    Vertical,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "camelCase")]
pub enum SplitNode {
    Terminal {
        id: Uuid,
        session_id: Uuid,
    },
    Split {
        id: Uuid,
        direction: SplitDirection,
        first: Box<SplitNode>,
        second: Box<SplitNode>,
        ratio: f64,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SplitViewState {
    pub root_node: Option<SplitNode>,
    pub focused_pane_id: Option<Uuid>,
}
```

### TypeScript 모델 (src/types/session.ts)

```typescript
// src/types/session.ts

export enum SessionStatus {
  Idle = 'idle',
  Running = 'running',
  WaitingForInput = 'waitingForInput',
  Terminated = 'terminated',
}

export enum ShellType {
  PowerShell = 'powerShell',
  Cmd = 'cmd',
  Wsl = 'wsl',
  GitBash = 'gitBash',
}

export interface TerminalSession {
  id: string;
  name: string;
  workingDirectory: string;
  status: SessionStatus;
  alias?: string;
  isLocked: boolean;
  hasUnreadNotification: boolean;
  lastActivity: string;
  shellType: ShellType;
}

export enum SplitDirection {
  Horizontal = 'horizontal',
  Vertical = 'vertical',
}

export type SplitNode =
  | { type: 'terminal'; id: string; sessionId: string }
  | {
      type: 'split';
      id: string;
      direction: SplitDirection;
      first: SplitNode;
      second: SplitNode;
      ratio: number;
    };

export interface SplitViewState {
  rootNode: SplitNode | null;
  focusedPaneId: string | null;
}
```

---

## 4단계: Rust PTY Manager

```rust
// src-tauri/src/terminal/pty_manager.rs

use portable_pty::{native_pty_system, CommandBuilder, PtySize, PtyPair, MasterPty, Child};
use std::collections::HashMap;
use std::io::{Read, Write};
use std::sync::Arc;
use parking_lot::Mutex;
use tokio::sync::mpsc;
use uuid::Uuid;
use tauri::{AppHandle, Emitter};

use crate::session::ShellType;

pub struct PtyInstance {
    pub master: Box<dyn MasterPty + Send>,
    pub child: Box<dyn Child + Send + Sync>,
    pub session_id: Uuid,
}

pub struct PtyManager {
    instances: Arc<Mutex<HashMap<Uuid, PtyInstance>>>,
    app_handle: AppHandle,
}

impl PtyManager {
    pub fn new(app_handle: AppHandle) -> Self {
        Self {
            instances: Arc::new(Mutex::new(HashMap::new())),
            app_handle,
        }
    }

    pub fn create_terminal(
        &self,
        session_id: Uuid,
        working_directory: &str,
        shell_type: ShellType,
    ) -> Result<(), String> {
        let pty_system = native_pty_system();

        // PTY 크기 설정
        let pair = pty_system
            .openpty(PtySize {
                rows: 24,
                cols: 80,
                pixel_width: 0,
                pixel_height: 0,
            })
            .map_err(|e| e.to_string())?;

        // 셸 명령 설정
        let shell_path = shell_type.get_path();
        let shell_args = shell_type.get_args();

        let mut cmd = CommandBuilder::new(shell_path);
        for arg in shell_args {
            cmd.arg(arg);
        }
        cmd.cwd(working_directory);

        // 환경 변수 설정
        cmd.env("TERM", "xterm-256color");
        cmd.env("COLORTERM", "truecolor");

        // 자식 프로세스 시작
        let child = pair.slave.spawn_command(cmd).map_err(|e| e.to_string())?;

        // 출력 읽기 스레드 시작
        let master = pair.master;
        let reader = master.try_clone_reader().map_err(|e| e.to_string())?;

        self.start_reader_thread(session_id, reader);

        // 인스턴스 저장
        let instance = PtyInstance {
            master,
            child,
            session_id,
        };

        self.instances.lock().insert(session_id, instance);

        Ok(())
    }

    fn start_reader_thread(&self, session_id: Uuid, mut reader: Box<dyn Read + Send>) {
        let app_handle = self.app_handle.clone();

        std::thread::spawn(move || {
            let mut buffer = [0u8; 4096];

            loop {
                match reader.read(&mut buffer) {
                    Ok(0) => {
                        // EOF - 프로세스 종료
                        let _ = app_handle.emit("terminal:exit", TerminalExitPayload {
                            terminal_id: session_id.to_string(),
                            exit_code: 0,
                        });
                        break;
                    }
                    Ok(n) => {
                        let data = String::from_utf8_lossy(&buffer[..n]).to_string();
                        let _ = app_handle.emit("terminal:data", TerminalDataPayload {
                            terminal_id: session_id.to_string(),
                            data,
                        });
                    }
                    Err(e) => {
                        log::error!("PTY read error: {}", e);
                        break;
                    }
                }
            }
        });
    }

    pub fn write(&self, session_id: Uuid, data: &str) -> Result<(), String> {
        let instances = self.instances.lock();
        if let Some(instance) = instances.get(&session_id) {
            let mut writer = instance.master.take_writer().map_err(|e| e.to_string())?;
            writer.write_all(data.as_bytes()).map_err(|e| e.to_string())?;
            Ok(())
        } else {
            Err("Terminal not found".to_string())
        }
    }

    pub fn resize(&self, session_id: Uuid, cols: u16, rows: u16) -> Result<(), String> {
        let instances = self.instances.lock();
        if let Some(instance) = instances.get(&session_id) {
            instance
                .master
                .resize(PtySize {
                    rows,
                    cols,
                    pixel_width: 0,
                    pixel_height: 0,
                })
                .map_err(|e| e.to_string())?;
            Ok(())
        } else {
            Err("Terminal not found".to_string())
        }
    }

    pub fn kill(&self, session_id: Uuid) -> Result<(), String> {
        let mut instances = self.instances.lock();
        if let Some(mut instance) = instances.remove(&session_id) {
            instance.child.kill().map_err(|e| e.to_string())?;
            Ok(())
        } else {
            Err("Terminal not found".to_string())
        }
    }

    pub fn kill_all(&self) {
        let mut instances = self.instances.lock();
        for (_, mut instance) in instances.drain() {
            let _ = instance.child.kill();
        }
    }
}

#[derive(Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
struct TerminalDataPayload {
    terminal_id: String,
    data: String,
}

#[derive(Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
struct TerminalExitPayload {
    terminal_id: String,
    exit_code: i32,
}
```

---

## 5단계: Tauri Commands (IPC)

```rust
// src-tauri/src/commands/terminal_commands.rs

use tauri::State;
use uuid::Uuid;
use crate::terminal::PtyManager;
use crate::session::ShellType;

#[tauri::command]
pub async fn create_terminal(
    pty_manager: State<'_, PtyManager>,
    session_id: String,
    working_directory: String,
    shell_type: String,
) -> Result<String, String> {
    let session_uuid = Uuid::parse_str(&session_id).map_err(|e| e.to_string())?;

    let shell = match shell_type.as_str() {
        "powerShell" => ShellType::PowerShell,
        "cmd" => ShellType::Cmd,
        "wsl" => ShellType::Wsl,
        "gitBash" => ShellType::GitBash,
        _ => ShellType::PowerShell,
    };

    pty_manager.create_terminal(session_uuid, &working_directory, shell)?;
    Ok(session_id)
}

#[tauri::command]
pub fn write_terminal(
    pty_manager: State<'_, PtyManager>,
    terminal_id: String,
    data: String,
) -> Result<(), String> {
    let uuid = Uuid::parse_str(&terminal_id).map_err(|e| e.to_string())?;
    pty_manager.write(uuid, &data)
}

#[tauri::command]
pub fn resize_terminal(
    pty_manager: State<'_, PtyManager>,
    terminal_id: String,
    cols: u16,
    rows: u16,
) -> Result<(), String> {
    let uuid = Uuid::parse_str(&terminal_id).map_err(|e| e.to_string())?;
    pty_manager.resize(uuid, cols, rows)
}

#[tauri::command]
pub fn kill_terminal(
    pty_manager: State<'_, PtyManager>,
    terminal_id: String,
) -> Result<(), String> {
    let uuid = Uuid::parse_str(&terminal_id).map_err(|e| e.to_string())?;
    pty_manager.kill(uuid)
}
```

```rust
// src-tauri/src/main.rs

#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod terminal;
mod session;
mod notification;
mod commands;

use terminal::PtyManager;
use commands::terminal_commands::*;

fn main() {
    tauri::Builder::default()
        .plugin(tauri_plugin_store::Builder::new().build())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_clipboard_manager::init())
        .plugin(tauri_plugin_notification::init())
        .setup(|app| {
            let pty_manager = PtyManager::new(app.handle().clone());
            app.manage(pty_manager);
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            create_terminal,
            write_terminal,
            resize_terminal,
            kill_terminal,
        ])
        .on_window_event(|window, event| {
            if let tauri::WindowEvent::CloseRequested { .. } = event {
                // 앱 종료 시 모든 PTY 정리
                if let Some(pty_manager) = window.state::<PtyManager>().try_get() {
                    pty_manager.kill_all();
                }
            }
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
```

---

## 6단계: React Terminal Component

```typescript
// src/components/Terminal/TerminalView.tsx

import React, { useEffect, useRef, useCallback } from 'react';
import { Terminal } from 'xterm';
import { FitAddon } from 'xterm-addon-fit';
import { WebLinksAddon } from 'xterm-addon-web-links';
import { Unicode11Addon } from 'xterm-addon-unicode11';
import { invoke } from '@tauri-apps/api/core';
import { listen, UnlistenFn } from '@tauri-apps/api/event';
import 'xterm/css/xterm.css';

interface TerminalTheme {
  background: string;
  foreground: string;
  cursor: string;
  cursorAccent: string;
  selectionBackground: string;
  black: string;
  red: string;
  green: string;
  yellow: string;
  blue: string;
  magenta: string;
  cyan: string;
  white: string;
  brightBlack: string;
  brightRed: string;
  brightGreen: string;
  brightYellow: string;
  brightBlue: string;
  brightMagenta: string;
  brightCyan: string;
  brightWhite: string;
}

interface TerminalViewProps {
  sessionId: string;
  workingDirectory: string;
  shellType: string;
  theme: TerminalTheme;
  onOutput?: (data: string) => void;
  onExit?: (exitCode: number) => void;
}

export const TerminalView: React.FC<TerminalViewProps> = ({
  sessionId,
  workingDirectory,
  shellType,
  theme,
  onOutput,
  onExit,
}) => {
  const terminalRef = useRef<HTMLDivElement>(null);
  const xtermRef = useRef<Terminal | null>(null);
  const fitAddonRef = useRef<FitAddon | null>(null);

  useEffect(() => {
    if (!terminalRef.current) return;

    // xterm.js 인스턴스 생성
    const terminal = new Terminal({
      cursorBlink: true,
      cursorStyle: 'block',
      fontSize: 14,
      fontFamily: '"Cascadia Code", Consolas, "Courier New", monospace',
      theme: theme,
      allowTransparency: true,
      scrollback: 10000,
      windowsMode: true, // Windows CRLF 처리
    });

    // Addons
    const fitAddon = new FitAddon();
    const webLinksAddon = new WebLinksAddon();
    const unicodeAddon = new Unicode11Addon();

    terminal.loadAddon(fitAddon);
    terminal.loadAddon(webLinksAddon);
    terminal.loadAddon(unicodeAddon);
    terminal.unicode.activeVersion = '11';

    terminal.open(terminalRef.current);
    fitAddon.fit();

    xtermRef.current = terminal;
    fitAddonRef.current = fitAddon;

    // PTY 프로세스 생성 (Tauri invoke)
    invoke('create_terminal', {
      sessionId,
      workingDirectory,
      shellType,
    }).catch(console.error);

    // 터미널 입력 → Rust PTY
    terminal.onData((data) => {
      invoke('write_terminal', {
        terminalId: sessionId,
        data,
      }).catch(console.error);
    });

    // 이벤트 리스너들
    let unlistenData: UnlistenFn;
    let unlistenExit: UnlistenFn;

    const setupListeners = async () => {
      // Rust PTY → 터미널 출력
      unlistenData = await listen<{ terminalId: string; data: string }>(
        'terminal:data',
        (event) => {
          if (event.payload.terminalId === sessionId) {
            terminal.write(event.payload.data);
            onOutput?.(event.payload.data);
          }
        }
      );

      // 터미널 종료 이벤트
      unlistenExit = await listen<{ terminalId: string; exitCode: number }>(
        'terminal:exit',
        (event) => {
          if (event.payload.terminalId === sessionId) {
            onExit?.(event.payload.exitCode);
          }
        }
      );
    };

    setupListeners();

    // 크기 변경 감지
    const resizeObserver = new ResizeObserver(() => {
      fitAddon.fit();
      const { cols, rows } = terminal;
      invoke('resize_terminal', {
        terminalId: sessionId,
        cols,
        rows,
      }).catch(console.error);
    });
    resizeObserver.observe(terminalRef.current);

    // Cleanup
    return () => {
      resizeObserver.disconnect();
      terminal.dispose();
      unlistenData?.();
      unlistenExit?.();
      invoke('kill_terminal', { terminalId: sessionId }).catch(console.error);
    };
  }, [sessionId, workingDirectory, shellType]);

  // 테마 변경 시 업데이트
  useEffect(() => {
    if (xtermRef.current) {
      xtermRef.current.options.theme = theme;
    }
  }, [theme]);

  return (
    <div
      ref={terminalRef}
      style={{
        width: '100%',
        height: '100%',
        backgroundColor: theme.background,
      }}
    />
  );
};
```

---

## 7단계: Session Store (Zustand)

```typescript
// src/store/sessionStore.ts

import { create } from 'zustand';
import { v4 as uuidv4 } from 'uuid';
import {
  TerminalSession,
  SessionStatus,
  ShellType,
  SplitNode,
  SplitViewState,
  SplitDirection,
} from '../types/session';

interface SessionState {
  sessions: TerminalSession[];
  selectedSessionId: string | null;
  splitViewState: SplitViewState;

  // Actions
  createSession: (name: string, workingDirectory: string, shellType?: ShellType) => TerminalSession;
  closeSession: (id: string) => void;
  selectSession: (id: string | null) => void;
  updateSessionStatus: (id: string, status: SessionStatus) => void;
  setSessionAlias: (id: string, alias: string | null) => void;
  toggleSessionLock: (id: string) => void;

  // Split View
  setSplitViewRoot: (node: SplitNode | null) => void;
  setFocusedPane: (paneId: string | null) => void;
  splitPane: (paneId: string, direction: SplitDirection, newSessionId: string) => void;
  removePaneFromSplit: (paneId: string) => void;
  updatePaneSession: (paneId: string, newSessionId: string) => void;
  findPaneIdForSession: (sessionId: string) => string | null;
  swapPaneSessions: (paneId1: string, paneId2: string) => void;
}

export const useSessionStore = create<SessionState>((set, get) => ({
  sessions: [],
  selectedSessionId: null,
  splitViewState: {
    rootNode: null,
    focusedPaneId: null,
  },

  createSession: (name, workingDirectory, shellType = ShellType.PowerShell) => {
    const session: TerminalSession = {
      id: uuidv4(),
      name,
      workingDirectory,
      status: SessionStatus.Idle,
      isLocked: false,
      hasUnreadNotification: false,
      lastActivity: new Date().toISOString(),
      shellType,
    };

    set((state) => ({
      sessions: [...state.sessions, session],
      selectedSessionId: session.id,
    }));

    return session;
  },

  closeSession: (id) => {
    const state = get();
    const session = state.sessions.find((s) => s.id === id);
    if (session?.isLocked) return;

    set((state) => {
      const newSessions = state.sessions.filter((s) => s.id !== id);
      const newSelectedId =
        state.selectedSessionId === id
          ? newSessions[0]?.id || null
          : state.selectedSessionId;
      return {
        sessions: newSessions,
        selectedSessionId: newSelectedId,
      };
    });
  },

  selectSession: (id) => set({ selectedSessionId: id }),

  updateSessionStatus: (id, status) => {
    set((state) => ({
      sessions: state.sessions.map((s) =>
        s.id === id ? { ...s, status, lastActivity: new Date().toISOString() } : s
      ),
    }));
  },

  setSessionAlias: (id, alias) => {
    set((state) => ({
      sessions: state.sessions.map((s) =>
        s.id === id ? { ...s, alias: alias || undefined } : s
      ),
    }));
  },

  toggleSessionLock: (id) => {
    set((state) => ({
      sessions: state.sessions.map((s) =>
        s.id === id ? { ...s, isLocked: !s.isLocked } : s
      ),
    }));
  },

  // Split View 메서드들
  setSplitViewRoot: (node) => {
    set((state) => ({
      splitViewState: { ...state.splitViewState, rootNode: node },
    }));
  },

  setFocusedPane: (paneId) => {
    set((state) => ({
      splitViewState: { ...state.splitViewState, focusedPaneId: paneId },
    }));
  },

  splitPane: (paneId, direction, newSessionId) => {
    set((state) => {
      const newNode = splitNodeAtPane(
        state.splitViewState.rootNode,
        paneId,
        direction,
        newSessionId
      );
      return {
        splitViewState: {
          ...state.splitViewState,
          rootNode: newNode,
        },
      };
    });
  },

  removePaneFromSplit: (paneId) => {
    set((state) => {
      const newNode = removePane(state.splitViewState.rootNode, paneId);
      return {
        splitViewState: {
          ...state.splitViewState,
          rootNode: newNode,
          focusedPaneId:
            newNode?.type === 'terminal'
              ? newNode.id
              : state.splitViewState.focusedPaneId,
        },
      };
    });
  },

  updatePaneSession: (paneId, newSessionId) => {
    set((state) => {
      const newNode = updatePaneSessionId(
        state.splitViewState.rootNode,
        paneId,
        newSessionId
      );
      return {
        splitViewState: { ...state.splitViewState, rootNode: newNode },
      };
    });
  },

  findPaneIdForSession: (sessionId) => {
    return findPaneBySessionId(get().splitViewState.rootNode, sessionId);
  },

  swapPaneSessions: (paneId1, paneId2) => {
    const state = get();
    const session1 = getSessionIdForPane(state.splitViewState.rootNode, paneId1);
    const session2 = getSessionIdForPane(state.splitViewState.rootNode, paneId2);

    if (session1 && session2) {
      let newNode = updatePaneSessionId(
        state.splitViewState.rootNode,
        paneId1,
        session2
      );
      newNode = updatePaneSessionId(newNode, paneId2, session1);
      set({
        splitViewState: { ...state.splitViewState, rootNode: newNode },
      });
    }
  },
}));

// Helper 함수들
function splitNodeAtPane(
  node: SplitNode | null,
  paneId: string,
  direction: SplitDirection,
  newSessionId: string
): SplitNode | null {
  if (!node) return null;

  if (node.type === 'terminal' && node.id === paneId) {
    return {
      type: 'split',
      id: uuidv4(),
      direction,
      first: node,
      second: { type: 'terminal', id: uuidv4(), sessionId: newSessionId },
      ratio: 0.5,
    };
  }

  if (node.type === 'split') {
    return {
      ...node,
      first: splitNodeAtPane(node.first, paneId, direction, newSessionId) || node.first,
      second: splitNodeAtPane(node.second, paneId, direction, newSessionId) || node.second,
    };
  }

  return node;
}

function removePane(node: SplitNode | null, paneId: string): SplitNode | null {
  if (!node) return null;

  if (node.type === 'terminal') {
    return node.id === paneId ? null : node;
  }

  if (node.type === 'split') {
    if (node.first.type === 'terminal' && node.first.id === paneId) {
      return node.second;
    }
    if (node.second.type === 'terminal' && node.second.id === paneId) {
      return node.first;
    }

    const newFirst = removePane(node.first, paneId);
    const newSecond = removePane(node.second, paneId);

    if (!newFirst) return newSecond;
    if (!newSecond) return newFirst;

    return { ...node, first: newFirst, second: newSecond };
  }

  return node;
}

function updatePaneSessionId(
  node: SplitNode | null,
  paneId: string,
  newSessionId: string
): SplitNode | null {
  if (!node) return null;

  if (node.type === 'terminal') {
    return node.id === paneId ? { ...node, sessionId: newSessionId } : node;
  }

  if (node.type === 'split') {
    return {
      ...node,
      first: updatePaneSessionId(node.first, paneId, newSessionId) || node.first,
      second: updatePaneSessionId(node.second, paneId, newSessionId) || node.second,
    };
  }

  return node;
}

function findPaneBySessionId(node: SplitNode | null, sessionId: string): string | null {
  if (!node) return null;

  if (node.type === 'terminal') {
    return node.sessionId === sessionId ? node.id : null;
  }

  if (node.type === 'split') {
    return (
      findPaneBySessionId(node.first, sessionId) ||
      findPaneBySessionId(node.second, sessionId)
    );
  }

  return null;
}

function getSessionIdForPane(node: SplitNode | null, paneId: string): string | null {
  if (!node) return null;

  if (node.type === 'terminal') {
    return node.id === paneId ? node.sessionId : null;
  }

  if (node.type === 'split') {
    return (
      getSessionIdForPane(node.first, paneId) ||
      getSessionIdForPane(node.second, paneId)
    );
  }

  return null;
}
```

---

## 8단계: Split Terminal View

```typescript
// src/components/Terminal/SplitTerminalView.tsx

import React, { useState, useCallback, useRef } from 'react';
import { SplitNode, SplitDirection } from '../../types/session';
import { TerminalPane } from './TerminalPane';
import styles from './SplitTerminalView.module.css';

interface SplitTerminalViewProps {
  node: SplitNode;
  focusedPaneId: string | null;
  onFocusPane: (paneId: string) => void;
  onClosePane: (paneId: string) => void;
}

export const SplitTerminalView: React.FC<SplitTerminalViewProps> = ({
  node,
  focusedPaneId,
  onFocusPane,
  onClosePane,
}) => {
  if (node.type === 'terminal') {
    return (
      <TerminalPane
        paneId={node.id}
        sessionId={node.sessionId}
        isFocused={focusedPaneId === node.id}
        onFocus={() => onFocusPane(node.id)}
        onClose={() => onClosePane(node.id)}
      />
    );
  }

  return (
    <SplitContainer
      direction={node.direction}
      initialRatio={node.ratio}
      first={
        <SplitTerminalView
          node={node.first}
          focusedPaneId={focusedPaneId}
          onFocusPane={onFocusPane}
          onClosePane={onClosePane}
        />
      }
      second={
        <SplitTerminalView
          node={node.second}
          focusedPaneId={focusedPaneId}
          onFocusPane={onFocusPane}
          onClosePane={onClosePane}
        />
      }
    />
  );
};

interface SplitContainerProps {
  direction: SplitDirection;
  initialRatio: number;
  first: React.ReactNode;
  second: React.ReactNode;
}

const SplitContainer: React.FC<SplitContainerProps> = ({
  direction,
  initialRatio,
  first,
  second,
}) => {
  const [ratio, setRatio] = useState(initialRatio);
  const [isDragging, setIsDragging] = useState(false);
  const containerRef = useRef<HTMLDivElement>(null);

  const minRatio = 0.15;
  const maxRatio = 0.85;
  const dividerSize = 4;

  const handleMouseDown = useCallback(
    (e: React.MouseEvent) => {
      e.preventDefault();
      setIsDragging(true);

      const handleMouseMove = (e: MouseEvent) => {
        if (!containerRef.current) return;

        const rect = containerRef.current.getBoundingClientRect();
        let newRatio: number;

        if (direction === SplitDirection.Horizontal) {
          newRatio = (e.clientX - rect.left) / rect.width;
        } else {
          newRatio = (e.clientY - rect.top) / rect.height;
        }

        setRatio(Math.min(Math.max(newRatio, minRatio), maxRatio));
      };

      const handleMouseUp = () => {
        setIsDragging(false);
        document.removeEventListener('mousemove', handleMouseMove);
        document.removeEventListener('mouseup', handleMouseUp);
      };

      document.addEventListener('mousemove', handleMouseMove);
      document.addEventListener('mouseup', handleMouseUp);
    },
    [direction]
  );

  const isHorizontal = direction === SplitDirection.Horizontal;

  return (
    <div
      ref={containerRef}
      className={styles.splitContainer}
      style={{ flexDirection: isHorizontal ? 'row' : 'column' }}
    >
      <div
        className={styles.pane}
        style={
          isHorizontal
            ? { width: `calc(${ratio * 100}% - ${dividerSize / 2}px)` }
            : { height: `calc(${ratio * 100}% - ${dividerSize / 2}px)` }
        }
      >
        {first}
      </div>

      <div
        className={`${styles.divider} ${isDragging ? styles.dragging : ''}`}
        style={{
          width: isHorizontal ? dividerSize : '100%',
          height: isHorizontal ? '100%' : dividerSize,
          cursor: isHorizontal ? 'col-resize' : 'row-resize',
        }}
        onMouseDown={handleMouseDown}
        onDoubleClick={() => setRatio(0.5)}
      />

      <div
        className={styles.pane}
        style={
          isHorizontal
            ? { width: `calc(${(1 - ratio) * 100}% - ${dividerSize / 2}px)` }
            : { height: `calc(${(1 - ratio) * 100}% - ${dividerSize / 2}px)` }
        }
      >
        {second}
      </div>
    </div>
  );
};
```

---

## 9단계: Claude 알림 감지

### Rust 구현

```rust
// src-tauri/src/notification/detector.rs

use lazy_static::lazy_static;
use regex::Regex;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub enum NotificationType {
    Question,
    WaitingForInput,
    Error,
    Completion,
    Custom,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DetectedNotification {
    pub notification_type: NotificationType,
    pub message: String,
}

struct CachedPattern {
    regex: Regex,
    notification_type: NotificationType,
}

lazy_static! {
    // 정규식 한 번만 컴파일 (CPU 최적화)
    static ref PATTERNS: Vec<CachedPattern> = vec![
        // Question patterns
        CachedPattern {
            regex: Regex::new(r"\?\s*$").unwrap(),
            notification_type: NotificationType::Question,
        },
        CachedPattern {
            regex: Regex::new(r"(?i)do you want to").unwrap(),
            notification_type: NotificationType::Question,
        },
        CachedPattern {
            regex: Regex::new(r"(?i)would you like").unwrap(),
            notification_type: NotificationType::Question,
        },
        CachedPattern {
            regex: Regex::new(r"(?i)should i").unwrap(),
            notification_type: NotificationType::Question,
        },
        // Waiting for input patterns
        CachedPattern {
            regex: Regex::new(r"(?i)waiting for (?:your )?(?:input|response)").unwrap(),
            notification_type: NotificationType::WaitingForInput,
        },
        CachedPattern {
            regex: Regex::new(r"(?i)press enter to continue").unwrap(),
            notification_type: NotificationType::WaitingForInput,
        },
        CachedPattern {
            regex: Regex::new(r"\[Y/n\]").unwrap(),
            notification_type: NotificationType::WaitingForInput,
        },
        CachedPattern {
            regex: Regex::new(r"\[y/N\]").unwrap(),
            notification_type: NotificationType::WaitingForInput,
        },
        // Error patterns
        CachedPattern {
            regex: Regex::new(r"(?i)error:").unwrap(),
            notification_type: NotificationType::Error,
        },
        CachedPattern {
            regex: Regex::new(r"(?i)failed:").unwrap(),
            notification_type: NotificationType::Error,
        },
        // Completion patterns
        CachedPattern {
            regex: Regex::new(r"(?i)task completed").unwrap(),
            notification_type: NotificationType::Completion,
        },
        CachedPattern {
            regex: Regex::new(r"(?i)successfully").unwrap(),
            notification_type: NotificationType::Completion,
        },
    ];
}

pub fn detect_notification(text: &str) -> Option<DetectedNotification> {
    if text.trim().is_empty() {
        return None;
    }

    // 최근 5줄만 확인 (성능 최적화)
    let lines: Vec<&str> = text.lines().collect();
    let recent_lines: Vec<&str> = lines.iter().rev().take(5).copied().collect();
    let recent_text = recent_lines.join("\n");

    for pattern in PATTERNS.iter() {
        if pattern.regex.is_match(&recent_text) {
            // 매칭된 줄 찾기
            let matched_line = lines
                .iter()
                .rev()
                .find(|line| pattern.regex.is_match(line))
                .map(|s| s.trim().to_string())
                .unwrap_or_else(|| recent_text.clone());

            return Some(DetectedNotification {
                notification_type: pattern.notification_type.clone(),
                message: matched_line,
            });
        }
    }

    None
}
```

### TypeScript 구현 (프론트엔드)

```typescript
// src/utils/claudeDetector.ts

import { NotificationType } from '../types/notification';

interface CachedPattern {
  regex: RegExp;
  type: NotificationType;
}

// 정규식 한 번만 컴파일
const cachedPatterns: CachedPattern[] = [
  { regex: /\?\s*$/i, type: NotificationType.Question },
  { regex: /do you want to/i, type: NotificationType.Question },
  { regex: /would you like/i, type: NotificationType.Question },
  { regex: /should i/i, type: NotificationType.Question },
  { regex: /waiting for (?:your )?(?:input|response)/i, type: NotificationType.WaitingForInput },
  { regex: /press enter to continue/i, type: NotificationType.WaitingForInput },
  { regex: /\[Y\/n\]/i, type: NotificationType.WaitingForInput },
  { regex: /\[y\/N\]/i, type: NotificationType.WaitingForInput },
  { regex: /error:/i, type: NotificationType.Error },
  { regex: /failed:/i, type: NotificationType.Error },
  { regex: /task completed/i, type: NotificationType.Completion },
  { regex: /successfully/i, type: NotificationType.Completion },
];

export function detectClaudeNotification(
  text: string
): { type: NotificationType; message: string } | null {
  if (!text || text.trim().length === 0) return null;

  const lines = text.split('\n');
  const recentLines = lines.slice(-5).join('\n');

  for (const { regex, type } of cachedPatterns) {
    if (regex.test(recentLines)) {
      const matchedLine =
        lines.reverse().find((line) => regex.test(line)) || recentLines;
      return { type, message: matchedLine.trim() };
    }
  }

  return null;
}

// 출력 버퍼링 (CPU 최적화)
export class OutputBuffer {
  private buffer: string = '';
  private flushTimeout: ReturnType<typeof setTimeout> | null = null;
  private flushDelay: number = 50;

  constructor(private onFlush: (data: string) => void) {}

  append(data: string): void {
    this.buffer += data;

    if (this.flushTimeout) {
      clearTimeout(this.flushTimeout);
    }

    this.flushTimeout = setTimeout(() => {
      this.flush();
    }, this.flushDelay);
  }

  private flush(): void {
    if (this.buffer.length > 0) {
      this.onFlush(this.buffer);
      this.buffer = '';
    }
    this.flushTimeout = null;
  }

  destroy(): void {
    if (this.flushTimeout) {
      clearTimeout(this.flushTimeout);
    }
  }
}
```

---

## 10단계: 키보드 단축키

```typescript
// src/hooks/useShortcuts.ts

import { useEffect } from 'react';
import { register, unregisterAll } from '@tauri-apps/plugin-global-shortcut';
import { open } from '@tauri-apps/plugin-dialog';
import { useSessionStore } from '../store/sessionStore';
import { SplitDirection, ShellType } from '../types/session';

export function useShortcuts() {
  const {
    createSession,
    closeSession,
    selectedSessionId,
    splitPane,
    splitViewState,
  } = useSessionStore();

  useEffect(() => {
    const setupShortcuts = async () => {
      // Ctrl+T: 새 터미널
      await register('CommandOrControl+T', async () => {
        const folder = await open({
          directory: true,
          multiple: false,
          title: 'Select Working Directory',
        });

        if (folder) {
          const name = (folder as string).split('\\').pop() || 'Terminal';
          createSession(name, folder as string, ShellType.PowerShell);
        }
      });

      // Ctrl+Shift+T: 홈 디렉토리에 새 터미널
      await register('CommandOrControl+Shift+T', () => {
        const homePath = process.env.USERPROFILE || 'C:\\Users\\Default';
        createSession('Home', homePath, ShellType.PowerShell);
      });

      // Ctrl+W: 터미널 닫기
      await register('CommandOrControl+W', () => {
        if (selectedSessionId) {
          closeSession(selectedSessionId);
        }
      });

      // Ctrl+D: 수평 분할
      await register('CommandOrControl+D', () => {
        const { focusedPaneId } = splitViewState;
        if (focusedPaneId && selectedSessionId) {
          const newSession = createSession('New', 'C:\\', ShellType.PowerShell);
          splitPane(focusedPaneId, SplitDirection.Horizontal, newSession.id);
        }
      });

      // Ctrl+Shift+D: 수직 분할
      await register('CommandOrControl+Shift+D', () => {
        const { focusedPaneId } = splitViewState;
        if (focusedPaneId && selectedSessionId) {
          const newSession = createSession('New', 'C:\\', ShellType.PowerShell);
          splitPane(focusedPaneId, SplitDirection.Vertical, newSession.id);
        }
      });
    };

    setupShortcuts();

    return () => {
      unregisterAll();
    };
  }, [createSession, closeSession, selectedSessionId, splitPane, splitViewState]);
}
```

---

## 11단계: Windows Taskbar 알림

```rust
// src-tauri/src/commands/notification_commands.rs

use tauri::{AppHandle, Manager};
use tauri_plugin_notification::NotificationExt;

#[tauri::command]
pub fn set_badge_count(app: AppHandle, count: u32) -> Result<(), String> {
    let window = app.get_webview_window("main").ok_or("Window not found")?;

    if count > 0 {
        // Windows Taskbar Overlay Icon
        // 실제 구현에서는 동적으로 아이콘 생성 또는 미리 만든 아이콘 사용
        window.set_overlay_icon(Some(
            tauri::image::Image::from_path("icons/badge.png")
                .map_err(|e| e.to_string())?
        )).map_err(|e| e.to_string())?;

        // Taskbar 깜빡임
        window.request_user_attention(Some(tauri::UserAttentionType::Informational))
            .map_err(|e| e.to_string())?;
    } else {
        window.set_overlay_icon(None::<tauri::image::Image>)
            .map_err(|e| e.to_string())?;
    }

    Ok(())
}

#[tauri::command]
pub fn show_notification(
    app: AppHandle,
    title: String,
    body: String,
) -> Result<(), String> {
    app.notification()
        .builder()
        .title(&title)
        .body(&body)
        .show()
        .map_err(|e| e.to_string())?;

    Ok(())
}
```

---

## 12단계: Notes 사이드바

```typescript
// src/components/Note/RightSidebar.tsx

import React, { useState, useCallback, useEffect } from 'react';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import { Prism as SyntaxHighlighter } from 'react-syntax-highlighter';
import { vscDarkPlus } from 'react-syntax-highlighter/dist/esm/styles/prism';
import { Store } from '@tauri-apps/plugin-store';
import styles from './RightSidebar.module.css';

interface RightSidebarProps {
  width: number;
  onWidthChange: (width: number) => void;
  minWidth?: number;
  maxWidth?: number;
}

type Tab = 'edit' | 'preview';

const store = new Store('notes.json');

export const RightSidebar: React.FC<RightSidebarProps> = ({
  width,
  onWidthChange,
  minWidth = 200,
  maxWidth = 600,
}) => {
  const [content, setContent] = useState<string>('');
  const [tab, setTab] = useState<Tab>('edit');
  const [showSavedMessage, setShowSavedMessage] = useState(false);
  const [isDragging, setIsDragging] = useState(false);

  // 로드
  useEffect(() => {
    store.get<string>('note-content').then((saved) => {
      if (saved) setContent(saved);
    });
  }, []);

  // 저장
  const handleSave = useCallback(async () => {
    await store.set('note-content', content);
    await store.save();
    setShowSavedMessage(true);
    setTimeout(() => setShowSavedMessage(false), 2000);
  }, [content]);

  // 리사이즈 핸들러
  const handleMouseDown = useCallback(
    (e: React.MouseEvent) => {
      e.preventDefault();
      setIsDragging(true);

      const startX = e.clientX;
      const startWidth = width;

      const handleMouseMove = (e: MouseEvent) => {
        const delta = startX - e.clientX;
        const newWidth = Math.min(Math.max(startWidth + delta, minWidth), maxWidth);
        onWidthChange(newWidth);
      };

      const handleMouseUp = () => {
        setIsDragging(false);
        document.removeEventListener('mousemove', handleMouseMove);
        document.removeEventListener('mouseup', handleMouseUp);
      };

      document.addEventListener('mousemove', handleMouseMove);
      document.addEventListener('mouseup', handleMouseUp);
    },
    [width, minWidth, maxWidth, onWidthChange]
  );

  return (
    <div className={styles.container} style={{ width }}>
      {/* Resize Handle */}
      <div
        className={`${styles.resizeHandle} ${isDragging ? styles.dragging : ''}`}
        onMouseDown={handleMouseDown}
        onDoubleClick={() => onWidthChange(300)}
      />

      <div className={styles.content}>
        {/* Header */}
        <div className={styles.header}>
          <span className={styles.title}>Notes</span>
          <div className={styles.tabs}>
            <button
              className={`${styles.tab} ${tab === 'edit' ? styles.active : ''}`}
              onClick={() => setTab('edit')}
            >
              Edit
            </button>
            <button
              className={`${styles.tab} ${tab === 'preview' ? styles.active : ''}`}
              onClick={() => setTab('preview')}
            >
              Preview
            </button>
          </div>
        </div>

        {/* Body */}
        <div className={styles.body}>
          {tab === 'edit' ? (
            <textarea
              className={styles.editor}
              value={content}
              onChange={(e) => setContent(e.target.value)}
              placeholder="Write your notes in Markdown..."
              spellCheck={false}
            />
          ) : (
            <div className={styles.preview}>
              <ReactMarkdown
                remarkPlugins={[remarkGfm]}
                components={{
                  code({ node, inline, className, children, ...props }: any) {
                    const match = /language-(\w+)/.exec(className || '');
                    return !inline && match ? (
                      <SyntaxHighlighter
                        style={vscDarkPlus}
                        language={match[1]}
                        PreTag="div"
                        {...props}
                      >
                        {String(children).replace(/\n$/, '')}
                      </SyntaxHighlighter>
                    ) : (
                      <code className={className} {...props}>
                        {children}
                      </code>
                    );
                  },
                }}
              >
                {content}
              </ReactMarkdown>
            </div>
          )}
        </div>

        {/* Footer */}
        <div className={styles.footer}>
          <button className={styles.saveButton} onClick={handleSave}>
            Save
          </button>
          {showSavedMessage && <span className={styles.savedMessage}>Saved!</span>}
        </div>
      </div>
    </div>
  );
};
```

---

## 회피해야 할 함정들 (Tauri + Windows)

### 1. portable-pty Windows 빌드 문제

**증상**: `cargo build` 시 portable-pty 컴파일 실패

**원인**: Windows SDK 또는 Visual Studio Build Tools 미설치

**해결**:
```powershell
# Visual Studio Build Tools 설치 (C++ 워크로드 포함)
winget install Microsoft.VisualStudio.2022.BuildTools

# 또는 rustup에서 MSVC 타겟 추가
rustup target add x86_64-pc-windows-msvc
```

### 2. ConPTY 미지원 Windows 버전

**증상**: 터미널이 제대로 동작하지 않음

**원인**: Windows 10 1903 미만 버전은 ConPTY 미지원

**해결**:
```rust
// conpty 크레이트 사용 시 버전 체크
use std::os::windows::ffi::OsStrExt;

fn is_conpty_supported() -> bool {
    // Windows 10 1903 (build 18362) 이상 확인
    let version = os_info::get();
    if let os_info::Type::Windows = version.os_type() {
        // 버전 체크 로직
    }
    true
}
```

### 3. 경로 구분자 문제

**증상**: 파일 경로가 제대로 인식되지 않음

**원인**: Windows는 `\`, Unix는 `/` 사용

**해결**:
```rust
use std::path::PathBuf;

// ❌ 잘못된 방법
let path = format!("{}/{}", dir, file);

// ✅ 올바른 방법
let path = PathBuf::from(dir).join(file);
```

```typescript
// TypeScript에서도 path 모듈 사용
import { join, normalize } from '@tauri-apps/api/path';

const filePath = await join(workingDir, fileName);
```

### 4. PowerShell 실행 정책 문제

**증상**: PowerShell 스크립트 실행 시 권한 오류

**원인**: Windows 기본 실행 정책이 Restricted

**해결**:
```rust
// PowerShell 실행 시 정책 우회
let mut cmd = CommandBuilder::new("powershell.exe");
cmd.args(&["-ExecutionPolicy", "Bypass", "-NoLogo"]);
```

### 5. xterm.js 한글 입력 문제

**증상**: 한글 조합 중 글자가 깨지거나 중복 입력

**원인**: IME 조합 이벤트 처리 미흡

**해결**:
```typescript
// xterm.js 옵션
const terminal = new Terminal({
  windowsMode: true,  // Windows CRLF 처리
});

// Unicode11Addon 필수
import { Unicode11Addon } from 'xterm-addon-unicode11';
terminal.loadAddon(new Unicode11Addon());
terminal.unicode.activeVersion = '11';
```

### 6. Tauri 보안 권한 설정

**증상**: IPC 명령이 동작하지 않음

**원인**: capabilities 설정 누락

**해결**:
```json
// src-tauri/capabilities/default.json
{
  "identifier": "default",
  "description": "Default capabilities",
  "windows": ["main"],
  "permissions": [
    "core:default",
    "store:default",
    "dialog:default",
    "clipboard-manager:default",
    "notification:default",
    "shell:default"
  ]
}
```

### 7. PTY 프로세스 좀비화

**증상**: 앱 종료 후에도 PowerShell/cmd 프로세스가 남아있음

**원인**: PTY 프로세스 정리 미흡

**해결**:
```rust
// main.rs - 앱 종료 시 정리
.on_window_event(|window, event| {
    if let tauri::WindowEvent::CloseRequested { .. } = event {
        if let Some(pty_manager) = window.state::<PtyManager>().try_get() {
            pty_manager.kill_all();
        }
    }
})
```

### 8. Tauri WebView2 미설치

**증상**: Windows에서 앱이 실행되지 않음

**원인**: WebView2 런타임 미설치 (Windows 10 구버전)

**해결**:
```json
// tauri.conf.json - WebView2 번들링
{
  "bundle": {
    "windows": {
      "webviewInstallMode": {
        "type": "embedBootstrapper"
      }
    }
  }
}
```

### 9. 줄바꿈 문자 차이

**증상**: 터미널 출력이 제대로 표시되지 않음

**원인**: Windows는 CRLF(`\r\n`), Unix는 LF(`\n`)

**해결**:
```typescript
// xterm.js windowsMode 사용
const terminal = new Terminal({
  windowsMode: true,  // CRLF 자동 처리
});
```

### 10. Tauri 2.0 마이그레이션 이슈

**증상**: Tauri 1.x 코드가 동작하지 않음

**원인**: Tauri 2.0 API 변경

**해결**:
```typescript
// Tauri 1.x
import { invoke } from '@tauri-apps/api/tauri';
import { listen } from '@tauri-apps/api/event';

// Tauri 2.0
import { invoke } from '@tauri-apps/api/core';
import { listen } from '@tauri-apps/api/event';
```

---

## 빌드 스크립트 (Windows)

### build.ps1 (PowerShell)

```powershell
# scripts/build.ps1

$AppName = "WinViber"
$ProjectDir = Split-Path -Parent $PSScriptRoot

Write-Host "Building $AppName..." -ForegroundColor Cyan

# 프론트엔드 빌드
Set-Location $ProjectDir
npm install
npm run build

# Tauri 빌드
Set-Location "$ProjectDir/src-tauri"
cargo build --release

# 또는 Tauri CLI로 패키징
Set-Location $ProjectDir
npm run tauri build

Write-Host "Build complete!" -ForegroundColor Green
Write-Host "Output: $ProjectDir\src-tauri\target\release\$AppName.exe"
```

### package.json scripts

```json
{
  "scripts": {
    "dev": "vite",
    "build": "tsc && vite build",
    "tauri": "tauri",
    "tauri:dev": "tauri dev",
    "tauri:build": "tauri build"
  }
}
```

### tauri.conf.json

```json
{
  "$schema": "https://schema.tauri.app/config/2",
  "productName": "WinViber",
  "version": "1.0.0",
  "identifier": "com.winviber.app",
  "build": {
    "beforeBuildCommand": "npm run build",
    "beforeDevCommand": "npm run dev",
    "devUrl": "http://localhost:5173",
    "frontendDist": "../dist"
  },
  "app": {
    "windows": [
      {
        "title": "WinViber",
        "width": 1200,
        "height": 800,
        "resizable": true,
        "fullscreen": false
      }
    ],
    "security": {
      "csp": null
    }
  },
  "bundle": {
    "active": true,
    "targets": ["msi", "nsis"],
    "icon": [
      "icons/32x32.png",
      "icons/128x128.png",
      "icons/128x128@2x.png",
      "icons/icon.icns",
      "icons/icon.ico"
    ],
    "windows": {
      "webviewInstallMode": {
        "type": "embedBootstrapper"
      }
    }
  }
}
```

---

## 요약: 개발 순서

1. **프로젝트 설정** - Tauri 2.0 + React + TypeScript 초기화
2. **Rust 백엔드** - PTY Manager (portable-pty), 세션 관리
3. **Tauri Commands** - IPC 명령 정의
4. **데이터 모델** - Rust + TypeScript 타입 정의
5. **Store** - Zustand (Session, Theme, Notification)
6. **Terminal Component** - xterm.js 래핑
7. **Split View** - 재귀적 분할 컨테이너
8. **Sidebar** - Terminal List, Favorites
9. **키보드 단축키** - Tauri global-shortcut
10. **Claude 알림** - 패턴 감지 (Rust + TypeScript)
11. **Notes** - Markdown 에디터/프리뷰
12. **Taskbar Badge** - Windows 오버레이 아이콘
13. **빌드/배포** - Tauri bundler (MSI/NSIS)

---

## macOS vs Windows (Tauri) 기능 대응표

| 기능 | macOS (MacViber) | Windows (WinViber) |
|------|------------------|-------------------|
| 터미널 라이브러리 | SwiftTerm | xterm.js + portable-pty |
| PTY 백엔드 | fork + execve | ConPTY |
| 백엔드 언어 | Swift | Rust |
| UI 프레임워크 | SwiftUI | React |
| 상태 관리 | @Published | Zustand |
| 설정 저장 | UserDefaults | tauri-plugin-store |
| 시스템 알림 | NSUserNotification | tauri-plugin-notification |
| Dock 배지 | NSApp.dockTile | Overlay Icon |
| 파일 다이얼로그 | NSOpenPanel | tauri-plugin-dialog |
| 클립보드 | NSPasteboard | tauri-plugin-clipboard-manager |
| 기본 셸 | zsh | PowerShell |
| 앱 크기 | ~15MB | ~3-10MB |
| 메모리 사용 | ~50MB | ~30-50MB |

---

## Tauri vs Electron 비교

| 특성 | Tauri + Rust | Electron + Node.js |
|------|-------------|-------------------|
| 앱 크기 | 3-10MB | 150MB+ |
| 메모리 | 30-50MB | 100-300MB |
| 시작 시간 | 빠름 | 느림 |
| 보안 | 강력 (Rust) | 보통 |
| 백엔드 성능 | 네이티브 | V8 JIT |
| 학습 곡선 | 높음 (Rust) | 낮음 (JS) |
| 생태계 | 성장 중 | 성숙 |
| WebView | 시스템 (Edge WebView2) | Chromium 번들 |
