# Memory - MacViber 프로젝트 기록

SwiftTerm 기반 MacViber에서 Wrap/Mac 터미널 기반 새 프로젝트로 마이그레이션하기 위한 참조 문서.

## 문서 목록

| 파일 | 설명 |
|------|------|
| `01_project_structure.md` | 현재 프로젝트 구조도, Git 이력, 컴포넌트 관계도 |
| `02_migration_considerations.md` | 터미널 백엔드 옵션 비교, 기능 마이그레이션 난이도, 권장 접근법 |
| `03_lessons_learned.md` | 개발 중 해결한 주요 문제점과 해결책 |

---

## Quick Summary

### 현재 프로젝트 핵심
- **SwiftTerm** 기반 터미널 에뮬레이션
- **Claude Code 알림** 실시간 감지 (출력 스트림 분석)
- **Split View** (최대 4개 패널)
- **SwiftUI** + **NSViewRepresentable** 아키텍처

### 마이그레이션 핵심 과제
1. **출력 캡처** - SwiftTerm의 dataReceived 대체 방안 필요
2. **터미널 임베딩** - 외부 앱 사용 시 창 관리 또는 웹뷰 고려
3. **알림 감지** - 출력 캡처 방식에 의존

### 권장 마이그레이션 경로
```
Option A: PTY 직접 관리 + NSTextView (가장 유사한 경험)
Option B: script 명령어 + 파일 감시 (간단한 구현)
Option C: Tauri + xterm.js (크로스 플랫폼 목표 시)
```

---

## 참조 파일
- `/DEVELOPMENT_GUIDE.md` - 상세 개발 가이드 (1400+ 라인)
- `/README.md` - 프로젝트 소개 및 사용법
- `/LocalPackages/SwiftTerm/` - 수정된 SwiftTerm 패키지
