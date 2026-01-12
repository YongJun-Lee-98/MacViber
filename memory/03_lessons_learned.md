# MacViber 개발 시 해결한 주요 문제점 (Lessons Learned)

## SwiftTerm 관련 이슈

### 1. 텍스트 복사(cmd+c) 안됨
```
원인: SwiftTerm의 keyDown()에서 selection.active = false 실행
해결: NSEvent 모니터로 마우스 이벤트 독립 추적 → 수동 selection 구현
```

### 2. 한글 IME 입력 안됨
```
원인: SwiftTerm의 기본 keyDown 처리가 IME 무시
해결: NSTextInputClient 프로토콜 구현
      inputContext?.handleEvent(event) 호출
```

### 3. 빠른 출력 시 스크롤 점핑
```
원인: 매 바이트마다 렌더링 트리거
해결: 출력 버퍼링 (configurable delay: 0.05초 기본)
```

---

## SwiftUI + NSViewRepresentable 이슈

### 4. 터미널 뷰 변경 안됨
```
원인: SwiftUI가 NSViewRepresentable 재사용
해결: .id(session.id) modifier로 강제 재생성
```

### 5. 새 터미널이 즉시 terminated 상태
```
원인: @Published isRunning = false 초기값이 구독자에게 전달
해결: controller.$isRunning.dropFirst().sink { ... }
```

### 6. Split view에서 focusedPaneId가 nil
```
원인: 로컬 설정값이 SessionManager 구독에 의해 덮어씌워짐
해결: 항상 SessionManager 메서드를 통해 설정
```

### 7. NSOpenPanel 후 상태 불일치
```
원인: 모달 중 SwiftUI 상태가 변경될 수 있음
해결: 모달 열기 전 필요한 상태 캡처
      let wasInSplitView = isSplitViewActive
      let capturedPaneId = focusedPaneId
```

### 8. Split view에서 동일 세션 중복 참조
```
원인: Pane A에서 Pane B의 세션 선택 시 B가 빈 화면
해결: SWAP 로직 구현 - swapPaneSessions(paneId1, paneId2)
```

---

## 성능 최적화 이슈

### 9. 정규식 CPU 100%
```
원인: 매 터미널 출력마다 NSRegularExpression 새로 컴파일
해결: static let으로 정규식 캐싱
```

### 10. 마우스 드래그 시 CPU 급증
```
원인: 초당 100+회 이벤트 발생
해결: 쓰로틀링 (0.016초, ~60fps)
```

### 11. objectWillChange 폭발
```
원인: 모든 상태 변경이 즉시 전파
해결: debounce(for: .milliseconds(16))
```

### 12. display() 호출 시 UI 버벅임
```
원인: 동기 렌더링으로 메인 스레드 블로킹
해결: needsDisplay = true만 사용, display() 제거
```

---

## UI 레이아웃 이슈

### 13. HSplitView/VSplitView 비율 무시
```
원인: SwiftUI의 Split 뷰가 ratio 값 무시
해결: GeometryReader + HStack/VStack + 커스텀 divider 구현
```

### 14. Notes 자동 저장 CPU 문제
```
원인: 매 키 입력마다 debounced save Task 생성/취소
해결: 자동 저장 제거, 수동 Save 버튼 사용
```

---

## 좌표 변환 주의점

### 터미널 Selection 좌표 계산
```swift
// macOS 좌표계: 하단이 0 (반전 필요)
let screenRow = Int((bounds.height - point.y) / cellHeight)

// 스크롤 오프셋 적용
let bufferRow = screenRow + terminal.buffer.yDisp
```

---

## 필수 체크리스트

새 프로젝트에서 확인할 항목:

- [ ] NSViewRepresentable에 .id() 적용
- [ ] @Published 구독 시 dropFirst() 고려
- [ ] 상태 변경은 항상 Manager 싱글톤 통해
- [ ] 모달 전 상태 캡처
- [ ] 정규식 컴파일 캐싱
- [ ] 이벤트 쓰로틀링/디바운싱
- [ ] display() 직접 호출 금지
