# SwiftTerm → Wrap/Mac 터미널 마이그레이션 고려사항

## 1. 터미널 백엔드 옵션 비교

### 옵션 A: Warp 터미널 연동
```
장점:
- 현대적인 터미널 UX
- AI 기능 내장
- 블록 기반 출력

단점:
- 외부 앱 의존성
- API/연동 방식 제한적
- 상용 서비스 (구독 모델)
```

### 옵션 B: macOS Terminal.app 연동
```
장점:
- 시스템 내장 (설치 불필요)
- AppleScript 지원
- 안정적

단점:
- UI 커스터마이징 제한
- 프로그래밍 제어 어려움
- 구식 느낌
```

### 옵션 C: iTerm2 연동
```
장점:
- AppleScript API
- 프로필 시스템
- 분할 뷰 내장

단점:
- 외부 앱 의존성
- 큰 앱 크기
```

### 옵션 D: 직접 PTY 관리 (SwiftTerm 대체)
```
장점:
- 완전한 제어권
- 의존성 없음

단점:
- 개발 난이도 높음
- 터미널 에뮬레이션 복잡
```

---

## 2. SwiftTerm에서 벗어나면 잃는 것들

### 직접 제어 기능
```
- PTY 직접 생성/관리
- 터미널 출력 실시간 캡처 (알림 감지 핵심)
- 프로그래밍 방식 입력 전송
- 버퍼 접근 (텍스트 추출)
- 스크롤백 제어
```

### UI 통합
```
- SwiftUI 앱 내 터미널 임베딩
- 동일 창 내 다중 터미널
- Split View 구현
- 테마/폰트 통합 제어
```

### 현재 해결된 문제들
```
- 한글 IME 처리
- cmd+c 복사 버그 수정
- 스크롤 점핑 방지
- 빠른 출력 시 버퍼링
```

---

## 3. 마이그레이션 시 재설계 필요 영역

### 3.1 터미널 제어 레이어
```
현재 (SwiftTerm):
┌────────────────────────────────────────┐
│            TerminalController          │
│   LocalProcessTerminalView 직접 래핑   │
│   - startProcess(shell, env)           │
│   - send(text)                         │
│   - onOutput callback                  │
└────────────────────────────────────────┘

마이그레이션 후:
┌────────────────────────────────────────┐
│        TerminalProcessManager          │
│   외부 터미널 앱 제어 또는 PTY 직접 관리│
│   - launchTerminal(path)               │
│   - sendCommand(text)                  │
│   - captureOutput() ← 가장 어려운 부분 │
└────────────────────────────────────────┘
```

### 3.2 출력 캡처 방식 변경
```
현재:
- CustomTerminalView.dataReceived() 오버라이드
- 바이트 스트림 직접 수신
- ClaudeNotificationDetector로 전달

새 방식 (외부 터미널):
옵션 1: script 명령어로 세션 기록
옵션 2: expect/pexpect 스타일 PTY 감시
옵션 3: 터미널 앱의 AppleScript API 활용
```

### 3.3 UI 아키텍처
```
현재:
- NSViewRepresentable로 SwiftTerm 뷰 임베딩
- SwiftUI 레이아웃 내 완전 통합

새 방식 (외부 터미널):
옵션 1: 앱 윈도우 관리 (외부 터미널 창 배치)
옵션 2: 터미널 뷰 임베딩 (가능한 경우)
옵션 3: 웹뷰 기반 터미널 (xterm.js 등)
```

---

## 4. 핵심 기능 마이그레이션 난이도

| 기능 | 현재 구현 | 마이그레이션 난이도 | 대안 |
|------|----------|-------------------|------|
| **출력 실시간 캡처** | dataReceived 오버라이드 | ⚠️ 높음 | script/PTY 감시 |
| **Claude 알림 감지** | 출력 스트림 분석 | ⚠️ 높음 | 동일 (출력 캡처 의존) |
| **Split View** | SwiftUI 레이아웃 | ✅ 중간 | 창 관리 또는 웹뷰 |
| **터미널 테마** | SwiftTerm 직접 설정 | ✅ 낮음 | 외부 터미널 프로필 |
| **한글 IME** | NSTextInputClient | ✅ 외부 터미널이 처리 | 불필요 |
| **텍스트 복사** | 수동 Selection 추적 | ✅ 외부 터미널이 처리 | 불필요 |
| **Favorites/Navigation** | 앱 내 UI | ✅ 낮음 | 동일하게 유지 |
| **Notes 사이드바** | 앱 내 UI | ✅ 낮음 | 동일하게 유지 |

---

## 5. 권장 접근 방식

### 5.1 Wrap 터미널 연동 시
```
1. Warp의 API/CLI 확인
2. tmux 세션 기반 제어 고려
3. warp-cli 명령어 활용
4. 출력 캡처: Warp의 블록 시스템 활용 가능성 조사
```

### 5.2 macOS Terminal.app 연동 시
```
1. AppleScript 기반 제어
   osascript -e 'tell application "Terminal" to do script "cd /path"'

2. 출력 캡처 옵션:
   - script 명령어로 typescript 파일 생성
   - 파일 감시 (FSEvents)로 새 출력 감지
   - 주기적 폴링

3. 창 관리:
   - NSWorkspace로 Terminal.app 창 배치
   - 또는 별도 관리 포기
```

### 5.3 Tauri/Electron + xterm.js 방식 (완전 재작성)
```
장점:
- 크로스 플랫폼
- 웹 기술 활용
- xterm.js의 풍부한 기능

단점:
- 완전 재작성 필요
- 네이티브 macOS 경험 상실
- 앱 크기 증가
```

---

## 6. 출력 캡처 구현 방안

### 방안 A: script 명령어 활용
```bash
# 터미널 시작 시
script -q /tmp/term_session_$UUID.log zsh

# 앱에서 파일 감시
FSEvents로 /tmp/term_session_*.log 모니터링
새 내용 발생 시 ClaudeNotificationDetector 호출
```

### 방안 B: PTY 직접 생성 (Swift)
```swift
import Darwin

func createPty() -> (master: Int32, slave: Int32) {
    var master: Int32 = 0
    var slave: Int32 = 0
    openpty(&master, &slave, nil, nil, nil)
    return (master, slave)
}

// DispatchSource로 master에서 읽기
let source = DispatchSource.makeReadSource(fileDescriptor: master)
source.setEventHandler {
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
    let bytesRead = read(master, buffer, 4096)
    // 출력 처리
}
```

### 방안 C: tmux 세션 활용
```bash
# 세션 생성
tmux new-session -d -s "macviber_$UUID"

# 출력 캡처
tmux pipe-pane -t "macviber_$UUID" 'cat >> /tmp/tmux_output_$UUID.log'

# 명령 전송
tmux send-keys -t "macviber_$UUID" "cd /path" Enter
```

---

## 7. 마이그레이션 단계별 계획

### Phase 1: 프로토타입
```
1. 출력 캡처 방식 PoC
   - script 명령어 테스트
   - PTY 직접 생성 테스트
   - 선택한 방식의 성능/안정성 검증

2. 터미널 제어 PoC
   - 외부 터미널 앱 제어 테스트
   - 또는 PTY + NSTextView 조합 테스트
```

### Phase 2: 핵심 기능 이식
```
1. TerminalProcessManager 구현
2. 출력 스트림 → ClaudeNotificationDetector 연결
3. 기본 단일 터미널 동작 확인
```

### Phase 3: UI 기능 이식
```
1. 다중 세션 관리
2. Split View (가능한 범위 내)
3. Favorites, Notes 등 보조 기능
```

### Phase 4: 최적화
```
1. 출력 캡처 성능 튜닝
2. 메모리 관리
3. CPU 사용량 최적화
```

---

## 8. 결론 및 권장사항

### SwiftTerm 유지가 권장되는 경우
```
- 앱 내 터미널 임베딩이 핵심 가치인 경우
- Claude Code 알림 실시간 감지가 중요한 경우
- 커스텀 터미널 경험이 필요한 경우
```

### 마이그레이션이 권장되는 경우
```
- SwiftTerm 유지보수 부담이 큰 경우
- 외부 터미널의 고급 기능이 필요한 경우
- 크로스 플랫폼 지원이 목표인 경우
```

### 중간 방안: 하이브리드
```
- 기본 터미널: 외부 앱 (Warp/Terminal.app)
- 알림 감지: script/PTY 기반 출력 캡처
- UI: 창 관리 + 알림 그리드 오버레이
```

---

## 9. 추가 조사 필요 항목

- [ ] Warp API 문서 확인
- [ ] iTerm2 AppleScript 기능 범위 확인
- [ ] xterm.js + Swift 브릿지 가능성
- [ ] PTY 직접 관리 시 IME 처리 방법
- [ ] 다른 터미널 관리 앱 (Hyper, Tabby) 분석
