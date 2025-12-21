# MacViber

macOS 다중 터미널 관리 앱 - Claude Code 알림 감지 및 그리드 표시 기능 포함  
<img width="1536" height="1024" alt="githubimg" src="https://github.com/user-attachments/assets/8d373ff8-3e72-4273-991d-a03692e093a3" />  

## Download

[**MacViber-v1.2.0.dmg**](https://github.com/YongJun-Lee-98/MacViber/releases/download/v1.2.0/MacViber-v1.2.0.dmg)

> macOS 14.0 (Sonoma) 이상 필요

## 기능

### 터미널 관리
- 여러 터미널 세션 동시 관리
- **터미널 분할 뷰** - 여러 터미널을 좌우/상하로 분할하여 동시에 표시
- **터미널 별명(Alias)** - 터미널에 별명을 지정하여 쉽게 구분
- **터미널 잠금** - 실수로 닫히지 않도록 터미널 잠금 기능
- 좌측 사이드바에서 터미널 리스트 관리

### Claude Code 알림
- Claude Code 알림 자동 감지 (질문, 권한 요청, 완료, 에러)
- 알림 발생 시 그리드 분할 화면으로 표시
- 시스템 알림 연동 (macOS Notification Center)

## Installation

### Prerequisites

- macOS 14.0 (Sonoma) or later
- Swift 5.9 or later
- Xcode 15.0 or later (for building)

### Quick Setup

Run the automated setup script:

```bash
./Scripts/setup.sh
```

The script will:
1. Verify Swift and macOS versions
2. Check Xcode Command Line Tools
3. Resolve package dependencies
4. Offer to build the project

### Manual Setup

```bash
# 1. Clone the repository
git clone https://github.com/YongJun-Lee-98/MacViber.git
cd MacViber

# 2. Resolve dependencies
swift package resolve

# 3. Build the project
swift build -c release
```

## 요구사항

- macOS 14.0 (Sonoma) 이상
- Xcode 15.0 이상 (빌드 시)

## 빌드 및 설치

### 앱 번들 빌드 (권장)

```bash
./Scripts/build-app.sh
```

빌드 완료 후:
```bash
# 앱 실행
open build/MacViber.app

# Applications 폴더에 설치
cp -R build/MacViber.app /Applications/
```

### 개발 모드 실행

```bash
swift run
```

### Xcode에서 열기

```bash
open Package.swift
```

## 사용법

### 키보드 단축키

앱 내에서 `Cmd + /` 또는 툴바의 `(?)` 버튼을 클릭하면 단축키 도움말을 볼 수 있습니다.

#### 터미널
| 단축키 | 기능 |
|--------|------|
| `⌘ T` | 새 터미널 추가 |
| `⌘ W` | 현재 터미널 닫기 |

#### 분할 뷰
| 단축키 | 기능 |
|--------|------|
| `⌘ D` | 좌우 분할 |
| `⇧⌘ D` | 상하 분할 |
| `⇧⌘ W` | 현재 패널 닫기 |

#### 패널 이동
| 단축키 | 기능 |
|--------|------|
| `⌥⌘ ]` | 다음 패널로 이동 |
| `⌥⌘ [` | 이전 패널로 이동 |

#### 도움말
| 단축키 | 기능 |
|--------|------|
| `⌘ /` | 키보드 단축키 보기 |

### 터미널 관리

1. **새 터미널 추가**: 툴바의 `+` 버튼 또는 `⌘ T`
2. **터미널 전환**: 좌측 사이드바에서 클릭
3. **터미널 이름 변경**: 우클릭 → Rename
4. **터미널 별명 설정**: 우클릭 → Set Alias
5. **터미널 복제**: 우클릭 → Duplicate
6. **터미널 잠금/해제**: 우클릭 → Lock/Unlock (잠금 시 삭제 방지)
7. **터미널 닫기**: 우클릭 → Close

### 분할 뷰

여러 터미널을 동시에 볼 수 있는 분할 화면 기능:

1. **분할 모드 진입**: 툴바의 분할 버튼(⊞) 클릭 또는 `⌘ D`
2. **추가 분할**: 패널 헤더의 분할 버튼 또는 단축키
3. **패널 닫기**: 패널 헤더의 X 버튼 또는 `⇧⌘ W`
4. **패널 간 이동**: `⌥⌘ ]` / `⌥⌘ [`
5. **분할 모드 종료**: 툴바 메뉴에서 "Exit Split View"

### 알림 기능

Claude Code 실행 중 질문이나 권한 요청이 발생하면:

1. 자동으로 알림 그리드 화면으로 전환
2. 여러 터미널에서 동시에 알림 발생 시 그리드 분할 표시
3. 카드에서 바로 응답 가능 (Allow/Deny, 텍스트 입력)
4. "View Terminal" 버튼으로 해당 터미널로 이동
5. 시스템 알림 (macOS Notification Center)

### 상태 표시

| 색상 | 상태 |
|------|------|
| 🟢 초록 | 실행 중 |
| 🟠 주황 | 입력 대기 (알림) |
| ⚫ 회색 | 대기 중 |
| 🔴 빨강 | 종료됨 |

### Claude Code CLI 통합

MacViber은 [Claude Code CLI](https://claude.ai/code)와 완벽하게 호환됩니다. Claude Code의 **슬래시 명령어** (`/help`, `/review` 등)와 **파일 자동완성** (`@` 트리거)을 사용하려면 shell 설정이 필요합니다.

#### 문제 증상

- Claude Code 대화 중 `/` 입력 시 명령어 목록이 표시되지만
- **방향키 ↑↓로 명령어를 선택하려고 하면 shell history가 대신 나타남**
- 더 많은 명령어를 보려고 해도 표시되지 않음

#### 해결 방법

**zsh 사용자** (대부분의 macOS 사용자)

`~/.zshrc` 파일 끝에 다음을 추가하세요:

```zsh
# Enable TUI application support (Claude Code, vim, etc.)
function zle-line-init {
    echoti smkx
}
function zle-line-finish {
    echoti rmkx
}
zle -N zle-line-init
zle -N zle-line-finish
```

**bash 사용자**

`~/.bashrc` 또는 `~/.bash_profile`에 다음을 추가하세요:

```bash
# Enable application cursor mode for readline
bind 'set enable-keypad on'
```

#### 적용 방법

```bash
# 1. 설정 파일 편집
nano ~/.zshrc
# 또는
code ~/.zshrc

# 2. 위의 코드 추가 후 저장

# 3. 변경사항 적용
source ~/.zshrc

# 4. MacViber 재시작 (터미널 세션 새로 시작)
```

#### 확인 방법

1. MacViber에서 `claude` 실행
2. `/` 입력하여 슬래시 명령어 목록 표시
3. **방향키 ↑↓로 명령어 선택 가능** ✅

문제가 지속되면 MacViber을 완전히 재시작하세요.

#### 기술적 배경

이 설정은 zsh의 라인 에디터(ZLE)가 명령어 실행 시 제대로 제어권을 넘겨주도록 합니다:
- `zle-line-init`: 프롬프트 표시 시 application cursor mode 활성화
- `zle-line-finish`: 명령어 실행 시 application cursor mode 비활성화
- Claude Code나 vim 같은 TUI 앱이 방향키를 직접 받을 수 있게 됨

**참고**: 이 설정은 Claude Code뿐만 아니라 vim, emacs, htop 등 모든 TUI 애플리케이션과의 호환성을 향상시킵니다.

## 프로젝트 구조

```
MacViber/
├── Package.swift                     # SPM 설정
├── Scripts/
│   └── build-app.sh                  # 앱 번들 빌드 스크립트
├── build/
│   └── MacViber.app                 # 빌드된 앱 번들
└── MacViber/
    ├── App/
    │   └── MacViberApp.swift        # 앱 진입점, 키보드 단축키, 도움말 뷰
    ├── Core/
    │   ├── Terminal/                 # SwiftTerm 래퍼
    │   └── Parser/                   # Claude 알림 감지
    ├── Domain/
    │   ├── Models/
    │   │   ├── TerminalSession.swift # 터미널 세션 (별명, 잠금 포함)
    │   │   ├── SplitNode.swift       # 분할 뷰 트리 구조
    │   │   └── ClaudeNotification.swift
    │   └── Services/
    │       └── SessionManager.swift  # 세션 및 분할 상태 관리
    ├── Presentation/
    │   ├── ViewModels/
    │   │   ├── MainViewModel.swift
    │   │   ├── TerminalListViewModel.swift
    │   │   └── NotificationGridViewModel.swift
    │   └── Views/
    │       ├── MainView.swift
    │       ├── Terminal/
    │       │   ├── TerminalView.swift
    │       │   ├── SplitTerminalView.swift  # 분할 뷰 컨테이너
    │       │   └── TerminalPaneView.swift   # 개별 패널
    │       ├── Sidebar/
    │       │   └── TerminalListView.swift
    │       └── Notification/
    │           ├── NotificationGridView.swift
    │           └── NotificationCardView.swift
    └── Resources/
```

## Dependencies

MacViber uses the following open-source libraries:

### SwiftTerm
- **Repository**: https://github.com/migueldeicaza/SwiftTerm
- **License**: MIT License
- **Usage**: Terminal emulation core
- **Integration**: Local package (LocalPackages/SwiftTerm)

### swift-argument-parser
- **Repository**: https://github.com/apple/swift-argument-parser
- **Version**: 1.6.2
- **License**: Apache License 2.0
- **Usage**: CLI argument parsing

For complete license information, see [docs/LICENSES.md](docs/LICENSES.md).

## Credits

- **App Icon**: Generated by ChatGPT (DALL-E)

## License

MacViber is licensed under the [MIT License](LICENSE).

### Third-Party Licenses

This project uses open-source libraries:
- **SwiftTerm**: MIT License - Terminal emulation
- **swift-argument-parser**: Apache License 2.0 - CLI parsing

See [docs/LICENSES.md](docs/LICENSES.md) for complete license texts and redistribution obligations.
