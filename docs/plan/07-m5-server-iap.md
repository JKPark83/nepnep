# 넵넵 개발 계획서 — 07. M5-A 구독·클라우드 처리 (v0.1)

작성일: 2026-08-22 | 버전: v0.1 | 베이스 커밋: main @ dcaeef9 | 선행: [06-m4-notion](06-m4-notion.md)

**한 줄 요약:** StoreKit 2 구독(월 6,900원) + 페이월(1i) + 클라우드 파이프라인(RTZR STT + Claude 요약, Vercel 서버 경유) + 월 20시간 사용량 관리를 완성한다. PRD F8 · F9.

관련 문서: [00-overview](00-overview.md) · [08-m5-gdocs-storage](08-m5-gdocs-storage.md)와 병행 가능

## 디자인 참조

- 페이월(1i), 녹음 화면 클라우드 토글(1c), 설정 구독·사용량 섹션(1h)은 와이어프레임 확정본 기준. 착수 전 `/design-sync` 확인 (import 프롬프트는 00-overview §4).

## 목표

프로 구독자가 녹음 화면에서 클라우드 토글을 켜고 녹음하면, 서버 경유로 RTZR 전사(+화자분리)와 Claude 요약이 수행되고 사용량이 차감된다. 무료 사용자는 토글 시 페이월을 만난다.

## 산출물

| 파일 | 구분 | 내용 |
|---|---|---|
| `server/src/routes/subscription.ts` | 신설 | `POST /v1/subscription/verify` — App Store Server API 검증 |
| `server/src/routes/cloudTranscribe.ts` | 신설 | `POST /v1/cloud/transcribe` · `GET /v1/cloud/transcribe/:jobId` |
| `server/src/routes/cloudSummarize.ts` | 신설 | `POST /v1/cloud/summarize` — Claude 프록시 |
| `server/src/lib/rtzr.ts` | 신설 | RTZR 인증(JWT 6h 캐시)·제출·폴링 |
| `server/src/lib/appstore.ts` | 신설 | JWS 검증 (`@apple/app-store-server-library`) |
| `server/src/lib/usage.ts` | 신설 | Vercel KV 사용량 카운터 |
| `Core/Cloud/PurchaseService.swift` | 신설 | StoreKit 2 구독 상태 @Observable |
| `Core/Cloud/CloudPipelineClient.swift` | 신설 | 업로드→폴링→결과 매핑 |
| `Core/Cloud/UsageTracker.swift` | 신설 | 잔여 시간 조회·표시용 |
| `Core/Pipeline/ProcessingCoordinator.swift` | 재활용·수정 | `processingMode == .cloud` 분기 |
| `Features/Paywall/PaywallView.swift` | 신설 | 1i |
| `Features/Recording/RecordingView.swift` | 재활용·수정 | 클라우드 토글 활성화 (F8-2·9-3) |
| `Features/Settings/SettingsView.swift` | 재활용·수정 | 구독·사용량 섹션 (1h) |
| `NepNepTests/UsageTrackerTests.swift` | 신설 | 시간 차감·월 초기화 표시 로직 |

## 핵심 작업

### 1. StoreKit 2 구독 (F8)

- App Store Connect: 구독 그룹 1개, 상품 `com.nepnep.pro.monthly` ₩6,900. 로컬 개발은 `.storekit` 구성 파일로.
- `PurchaseService`: `Product.products(for:)` → `product.purchase()` → `Transaction.currentEntitlements`로 상태 판정. `Transaction.updates` 상시 구독(백그라운드 갱신·환불 반영). `AppStore.sync()`로 복원(F8-4).
- 계정 없는 설계이므로 사용자 식별자는 `Transaction.appAccountToken` 대신 **`originalTransactionID`** 를 서버 사용량 키로 사용 (재설치·복원에도 동일).
- 서버 검증: 앱이 JWS representation을 `POST /v1/subscription/verify`로 전달 → 서버는 `@apple/app-store-server-library`의 `SignedDataVerifier`로 서명·만료 검증 → `{active, originalTransactionID, expiresAt}` 반환. 클라우드 API 호출 시 이 검증 결과로 발급한 단기 세션 토큰(HMAC, 24h)을 Authorization에 사용 — 요청마다 Apple 검증을 반복하지 않기 위함.

### 2. 페이월 (1i — F8-1·5)

- 진입 3곳만: 녹음 화면 토글(무료 사용자) / 설정 "프로 자세히 보기" / 사용량 초과 알럿. 실행 시 자동 표시 금지.
- 레이아웃: 무료 카드 먼저("현재 사용 중" 배지) → 프로 카드(accent 테두리, "무료 기능은 그대로 포함" 명시) → 암호화·미저장 문구(구매 버튼 바로 위) → "프로 시작하기" → 구매 복원 · 약관.
- 구매 성공 → 시트 닫힘, 토글 켜짐(페이월이 토글에서 열렸을 때). 구독 중 재진입 시 사용량 화면으로 대체(1i 노트 3 — 설정의 사용량 섹션 재사용).

### 3. 클라우드 파이프라인 (F9)

업로드 경로 — Vercel 4.5MB body 제한 대응(00-overview 위험):

```
앱: recording.caf → AAC m4a 64kbps 임시 인코딩 (1h ≈ 28MB)
 → Vercel Blob 클라이언트 직접 업로드 (서버가 발급한 업로드 토큰 사용, /v1/cloud/upload-token)
 → POST /v1/cloud/transcribe {blobURL, durationSec} → 서버: 사용량 선검증 → RTZR 제출(use_diarization:true) → {jobId}
 → 앱이 GET /v1/cloud/transcribe/:jobId 를 10s 간격 폴링 (서버는 RTZR 폴링 결과 중계, 429 회피 위해 서버측 5s 캐시)
 → 완료: utterances[{start_at, duration, msg, spk}] → TranscriptWord/SpeakerSegment로 매핑 → 기존 TranscriptMerger 경로 재사용 없이 spk 그대로 화자 확정
 → POST /v1/cloud/summarize {digest 입력} → Claude(claude-sonnet-5, JSON 스키마 응답) → FinalSummary와 동일 구조로 매핑
 → 서버: 완료 시 사용량 차감(duration 기준) + Blob 즉시 삭제
```

- ProcessingCoordinator 분기: cloud 모드에서는 전사·화자분리·요약 세 단계가 "업로드 → 클라우드 처리 대기 → 요약" 단계로 대체되되 `processingStage` 표기는 동일 3단계 유지(1d 화면 재사용). RTZR 큐 지연(최대 30분+)이 있으므로 폴링은 포그라운드 재진입 시에도 재개 가능해야 함 — jobId를 체크포인트에 저장.
- 실패 폴백(F9-4): 업로드·RTZR·Claude 어느 단계든 실패 시 알럿 "클라우드 처리에 실패했어요 — 기기에서 처리할까요?" → 승인 시 onDevice 파이프라인으로 재enqueue(사용량 미차감).
- 서버 무저장 원칙: Blob은 처리 완료·실패 즉시 삭제, 전사·요약 결과는 응답으로만 전달하고 KV에는 사용량 숫자만.

### 4. 사용량 관리 (F8-3, 1h)

- KV 키: `usage:{originalTransactionID}:{yyyy-MM}` → 초 단위 누적. 제출 시점에 `잔여 < duration`이면 402 응답 → 앱은 "이번 달 클라우드 시간을 다 썼어요" 알럿 + 온디바이스 폴백 제안 + 페이월 아님(이미 구독자).
- 설정 표시: "이번 달 클라우드 사용 N시간 / 20시간 · 매월 1일 초기화" — `GET /v1/subscription/verify` 응답에 사용량 포함. 무료 사용자에게도 행 노출(0시간 / 20시간, 1h 노트 2).
- `UsageTrackerTests`: 초→시간 표시 반올림 / 월 경계 키 생성 / 잔여 계산.

### 5. 녹음 화면 토글 연결 (F9-3)

- M1의 `disabled(true)` 제거. 무료: 토글 시 페이월 표시 + 토글 원복(1c 노트 3). 프로: 토글 상태를 `meeting.processingModeRaw`에 기록, 잔여 시간 부족 시 토글에 경고 문구.

## 완료 기준

- [ ] Sandbox 계정: 구매 → 프로 전환 → 복원 → 다른 기기 시뮬레이션(재설치)에서 복원 정상
- [ ] 실기기: 프로 상태에서 클라우드 토글 ON → 30분 녹음 → RTZR+Claude 경유 회의록 완성, 설정 사용량이 0.5시간 증가
- [ ] 무료 상태 토글 → 페이월 표시, 구매 없이 닫으면 토글 OFF 유지
- [ ] 사용량 20시간 소진 상태(KV 수동 세팅) → 클라우드 제출 시 402 → 온디바이스 폴백 동작
- [ ] 클라우드 처리 중 앱 종료 → 재실행 → jobId 폴링 재개로 완주
- [ ] 서버: 처리 완료 후 Blob 삭제 확인(목록 API), KV에 오디오·텍스트 부재 확인
- [ ] `xcodebuild test`: UsageTrackerTests ≥3케이스 통과
