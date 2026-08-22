# 넵넵 개발 계획서 — 09. M6 마감·출시 (v0.1)

작성일: 2026-08-22 | 버전: v0.1 | 베이스 커밋: main @ dcaeef9 | 선행: [07-m5-server-iap](07-m5-server-iap.md) · [08-m5-gdocs-storage](08-m5-gdocs-storage.md)

**한 줄 요약:** 온보딩(1a) · 설정 잔여 섹션(전사 엔진, 1h) · 심사 대비 항목을 마감하고, 전 마일스톤 회귀 체크리스트를 돌려 App Store에 제출한다. PRD §11 M6.

관련 문서: [00-overview](00-overview.md)

## 디자인 참조

- 온보딩(1a)·설정 전사 엔진 섹션(1h)은 와이어프레임 확정본 기준. 착수 전 `/design-sync` 확인 (import 프롬프트는 00-overview §4).

## 목표

첫 실행부터 구매·내보내기까지 전 플로우가 심사 기준을 통과할 상태로 정리되고, 회귀 체크리스트 전 항목이 통과한 빌드가 제출된다.

## 산출물

| 파일 | 구분 | 내용 |
|---|---|---|
| `Features/Onboarding/OnboardingView.swift` | 신설 | 1a — 가치 소개 + 권한 요청 |
| `Features/Settings/EngineSection.swift` | 신설 | 전사 엔진 선택·WhisperKit 다운로드 (1h) |
| `Features/Settings/SettingsView.swift` | 재활용·수정 | 엔진 섹션 삽입 — 1h 최종 구성 완성 |
| `Core/Support/AppReviewSupport.swift` | 신설 | 심사용 처리(아래 §3) |
| `docs/plan/m6-regression.md` | 신설 | 회귀 체크리스트 실행 기록 |
| App Store Connect 메타데이터 | 신설 | 스크린샷·설명·개인정보 영양표 |

## 핵심 작업

### 1. 온보딩 (1a)

- 첫 실행 1회만 (`UserDefaults hasOnboarded`). 와이어프레임 1a 확정본 구성대로 구현 — 착수 시 `/design-sync`로 페이지 수·카피를 확인해 그대로 옮긴다(이 문서에 카피를 중복 기록하지 않음).
- 권한 요청 2건을 온보딩 마지막 단계에서: 마이크(`AVAudioApplication.requestRecordPermission`) → 알림(`UNUserNotificationCenter.requestAuthorization(options: [.alert, .sound])`). 거부 시에도 진행 가능, 녹음 시작 시점에 설정 앱 유도 알럿(마이크 필수).
- SpeechTranscriber 에셋 다운로드를 온보딩 직후 백그라운드로 선요청(`ModelAssetManager.ensureSpeechAsset`) — 첫 회의 처리 대기를 줄인다.

### 2. 설정 — 전사 엔진 섹션 (1h 노트 3, F2-2·3)

- 라디오 2행: SpeechTranscriber("iOS 기본 · 빠르고 배터리 소모가 적어요") / WhisperKit("약 600MB · 전문 용어·외래어에 더 정확하지만 처리가 2배 느리고 배터리를 더 씁니다" — 실측치는 M0 결과로 갱신).
- WhisperKit 상태 전이: 받기 버튼 → 다운로드 진행률 → 선택 가능 라디오. 다운로드 중 이탈해도 계속(`ModelAssetManager` Task 보유), 실패 시 "받기"로 복귀 + 에러 한 줄.
- 삭제: WhisperKit 모델 삭제 행(선택 중이면 SpeechTranscriber로 자동 전환).

### 3. 심사 대비 (AppReviewSupport + 메타데이터)

- **계정 없는 구독** 심사 포인트: 페이월에 약관(EULA)·개인정보 처리방침 링크 필수(1i에 이미 배치 — URL 실연결), 구매 복원 버튼 확인.
- 개인정보 영양표: 온디바이스 기본(수집 없음) / 클라우드 사용 시 오디오 전송(미저장) / 구독 식별자(originalTransactionID) — PRD §8과 일치하게 작성.
- 심사원용 안내(App Review 메모): 클라우드 기능은 Sandbox 구독으로 시험 가능함을 명시 + 시연용 짧은 샘플 오디오 파일 앱 내 import 경로 안내.
- 마이크·알림 권한 문구(Info.plist usage description) 한국어·영어 검수.
- 법적 문서: 개인정보 처리방침·이용약관 정적 페이지를 `server/public/`(Vercel 정적 호스팅)에 게시하고 앱·App Store Connect에 URL 등록.

### 4. 품질 마감

- 접근성 1차: 홈·녹음·상세 화면 VoiceOver 레이블(버튼·상태), Dynamic Type Large까지 레이아웃 깨짐 확인.
- 다크 모드 전 화면 육안 점검 (DesignTokens 누락 하드코딩 색 검출: `rg "Color\(red|\.init\(red" ios/`).
- 크래시·에러 로깅: 외부 SDK 추가하지 않음(PRD §8 무저장 원칙) — `os.Logger` 카테고리 정리만.

### 5. 회귀 체크리스트 (`m6-regression.md`에 실행 기록)

각 항목은 이전 문서의 완료 기준 재실행이다:

| # | 시나리오 | 원 문서 |
|---|---|---|
| R1 | 1h 녹음(잠금·인터럽트 포함) → 처리 → 전사·요약 | 02·03·05 |
| R2 | 강제 종료 복구(녹음 중 / 처리 중) | 02·03 |
| R3 | 화자 이름 지정·합치기·검색 | 04 |
| R4 | Notion·Google 내보내기 + 재내보내기 갱신 + 자동 내보내기 | 06·08 |
| R5 | 구매·복원·페이월 3진입점 | 07 |
| R6 | 클라우드 처리 E2E + 사용량 차감 + 402 폴백 | 07 |
| R7 | 오디오만 삭제 → 재생 비활성·회의록 유지 | 08 |
| R8 | 온보딩 첫 실행 → 권한 거부 경로 | 09 |
| R9 | 엔진 전환(WhisperKit 다운로드 포함) 후 처리 | 03·09 |
| R10 | 배터리: 1h 녹음 ≤10%, 30분 처리 발열 `serious` 미만 | 02·03 |

## 완료 기준

- [ ] `xcodebuild test` 전체 스위트 통과 (누적 유닛 테스트 전부)
- [ ] `m6-regression.md`에 R1~R10 전 항목 통과 기록 (기기·OS 버전·일시 포함)
- [ ] 온보딩: 삭제 후 재설치 → 1a 플로우 → 권한 2건 요청 → 홈 빈 상태 진입
- [ ] 설정 화면이 1h 확정본과 최종 일치 (연동·구독·사용량·엔진·저장 공간·기본값 전 섹션)
- [ ] App Store Connect: 스크린샷(6.9"·6.3")·설명·영양표·심사 메모 등록, 심사 제출 완료
