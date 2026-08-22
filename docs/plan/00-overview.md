# 넵넵(NepNep) 개발 계획서 — 00. 전체 개요 (v0.1)

작성일: 2026-08-22 | 버전: v0.1 | 베이스 커밋: main @ dcaeef9

**한 줄 요약:** [PRD](../PRD.md) 전체(F1~F11, M0~M6)를 마일스톤 단위 plan 문서 10개로 구체화한다. 각 마일스톤 문서는 단순 코더가 위에서부터 순서대로 코딩할 수 있는 수준의 파일 경로·코드 스케치·완료 기준을 담는다.

관련 문서: [PRD](../PRD.md) · 와이어프레임: [claude.ai/design — NepNep Wireframes](https://claude.ai/design/p/71aacacc-9ee1-4fa8-9a5b-4316c2bcfabe?file=NepNep+Wireframes.dc.html)

## 문서 구성

| 문서 | 범위 | PRD 매핑 |
|---|---|---|
| [00-overview.md](00-overview.md) | 확정 결정 · 아키텍처 · 디렉터리 구조 · 디자인 가이드 · 의존성 그래프 · 위험 · 체크리스트 | 전체 |
| [01-m0-spike.md](01-m0-spike.md) | 기술 검증 스파이크 (게이트) | §11-M0 |
| [02-m1-recording.md](02-m1-recording.md) | 녹음 코어 + Live Activity | F1 |
| [03-m2-pipeline.md](03-m2-pipeline.md) | 전사·화자분리·병합·백그라운드 처리 | F2 · F3 · F10 |
| [04-m2-transcript-ui.md](04-m2-transcript-ui.md) | 홈 리스트 · 처리 중 화면 · 대화록 UI · 화자 지정 | F4 · F6 일부 · F10-4 |
| [05-m3-summary.md](05-m3-summary.md) | Foundation Models 요약 + 회의록 상세·편집 | F5 · F6 |
| [06-m4-notion.md](06-m4-notion.md) | Notion 내보내기 + 서버 OAuth 최소 기능 | F7 |
| [07-m5-server-iap.md](07-m5-server-iap.md) | 서버 프록시 전체 · IAP · 클라우드 파이프라인 | F9 |
| [08-m5-gdocs-storage.md](08-m5-gdocs-storage.md) | Google Docs 내보내기 + 저장공간 관리 | F8 · F11 |
| [09-m6-release.md](09-m6-release.md) | 온보딩 완성 · 설정 화면 · 출시 준비 | §5.3 · S8 · §11-M6 |

## 1. 확정 결정 모음

인터뷰(2026-08-22)와 리서치로 확정. 이후 문서는 이 표를 재논의하지 않는다.

| 항목 | 확정값 | 근거 |
|---|---|---|
| 로컬 DB | **SwiftData** | 사용자 확정. iOS 26 전용 앱, @Query·SwiftUI 통합. PRD 오픈 이슈 #2 해소 |
| 앱 아키텍처 | **MV + Observation** (@Observable 스토어를 Environment 주입, ViewModel 계층 없음) | 사용자 확정 |
| plan 문서 분할 | **마일스톤별 10개 문서** (M2는 파이프라인/UI 2개로 분할) | 사용자 확정 |
| 서버 프록시 | **Vercel + TypeScript(Hono)**, M4에 OAuth 교환 최소 기능 먼저 배포 | 사용자 확정. Notion OAuth 토큰 교환은 client secret 서버 보관 필수 ([Notion Authorization](https://developers.notion.com/docs/authorization)) |
| Xcode 구조 | **단일 앱 타깃 + 폴더 분리**, Live Activity용 Widget Extension 1개 추가 | 사용자 확정 |
| 테스트 전략 | **코어 로직만 유닛 테스트** (병합·체크포인트·블록 변환·사용량 계산). UI·오디오는 실기기 수동 검증 | 사용자 확정 |
| 백그라운드 처리 API | **`BGContinuedProcessingTask`** (iOS 26 신규) — 사용자 액션으로 시작한 장시간 작업 전용, 시스템 Live Activity 진행률 자동 제공. 실패 대비 체크포인트 재개 병행 | 리서치: [WWDC25 #227](https://developer.apple.com/videos/play/wwdc2025/227/), [BGContinuedProcessingTask 문서](https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtask). `beginBackgroundTask`는 실질 30초뿐이라 부적합 |
| 요약 청크 전략 | **map-reduce 필수.** Foundation Models 컨텍스트 4,096토큰(입출력 합산). `contextSize`/`tokenCount(for:)`로 동적 측정 | 리서치: [TN3193](https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window) |
| 화자분리 파이프라인 | FluidAudio **OfflineDiarizerManager** (`process(url:)`, 메모리맵 스트리밍). 모델은 HF 자동 다운로드 ~129MB | 리서치: [FluidAudio GettingStarted](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Diarization/GettingStarted.md) |
| WhisperKit 모델 | **`large-v3-v20240930_turbo_632MB`** (가정 — M0에서 `large-v3-v20240930_626MB`와 CER 실측 비교 후 확정) | 리서치: iPhone 15 Pro에서 turbo 8.45x(30분≈3.6분), non-turbo 5.78x(≈5.2분). [WhisperKit Benchmarks](https://huggingface.co/spaces/argmaxinc/whisperkit-benchmarks). 오픈 이슈 #7 |
| WhisperKit 패키지 | `https://github.com/argmaxinc/argmax-oss-swift.git` (구 WhisperKit 저장소 통합), product name `WhisperKit` | 리서치: 저장소 이전 확인 |
| 오디오 저장 포맷 | 녹음: **CAF(PCM Int16, 16kHz mono)** 청크 순차 기록(크래시 내구, ≈115MB/h) → 처리 완료 후 **AAC m4a 32kbps mono로 트랜스코드**(≈14MB/h) 후 CAF 삭제 (가정) | PRD F1-1(16kHz mono 입력 규격) + F11 저장공간 절감. 오픈 이슈 A |
| 클라우드 STT | RTZR: `POST openapi.vito.ai/v1/authenticate`(JWT 6h) → `POST /v1/transcribe`(multipart, `use_diarization:true`) → 5초 간격 폴링 | 리서치: [RTZR docs](https://developers.rtzr.ai/docs/en/) |
| Notion 블록 제한 | 요청당 100블록 · rich_text 2,000자 · 초당 3요청 → 분할 append 유틸 필수 | 리서치: [Append block children](https://developers.notion.com/reference/patch-block-children) |
| 클라우드 요약 모델 | claude-sonnet-5 (가정 — M5에서 A/B) | PRD 오픈 이슈 #5 |
| 디자인 소스 | **claude.ai/design 와이어프레임(1a~1i, 완성본)이 단일 진실 소스.** 각 마일스톤 UI 착수 전 design sync로 최신본 동기화 | 사용자 지시 (아래 §4) |
| 재내보내기 동작 | **기존 페이지/문서 갱신** (새 페이지 생성 아님) + 갱신 여부 한 줄 안내 | 와이어프레임 1g 노트 4가 PRD F7-6보다 우선 (사용자: "와이어프레임 수준으로 작성") |
| 자동 내보내기 | 회의 정리 완료 시 자동 내보내기 스위치 제공 (내보내기 시트 + 설정 > 연동) | 와이어프레임 1g 노트 2 |

## 2. 아키텍처

```
┌─ iOS 앱 (SwiftUI, iOS 26+, 단일 타깃) ────────────────────────────┐
│                                                                    │
│  Views (Features/*)          @Observable 스토어 (Environment 주입) │
│  ┌──────────┐  ┌───────────────────────────────────────────┐      │
│  │ Home     │  │ MeetingStore      · SwiftData CRUD        │      │
│  │ Recording│──│ RecordingSession  · AVAudioEngine + 청크  │      │
│  │ Detail   │  │ ProcessingCoordinator · 파이프라인 오케스트레이션│
│  │ Export   │  │ ExportService     · Notion/GDocs          │      │
│  │ Settings │  │ PurchaseService   · StoreKit 2            │      │
│  └──────────┘  └───────────────────────────────────────────┘      │
│                                                                    │
│  온디바이스 파이프라인 (ProcessingCoordinator가 순차 실행,          │
│  BGContinuedProcessingTask 안에서 단계별 체크포인트 저장)          │
│  녹음 CAF ─→ TranscriptionEngine(SpeechTranscriber|WhisperKit)     │
│           ─→ FluidAudio OfflineDiarizer ─→ TranscriptMerger        │
│           ─→ SummaryService(Foundation Models, map-reduce)         │
│                                                                    │
│  NepNepWidgets (Widget Extension): 녹음 Live Activity              │
└────────────┬───────────────────────────────────────────────────────┘
             │ HTTPS (무료 흐름은 내보내기 텍스트 외 전송 없음)
┌────────────▼──────────────────────────────────────────────────────┐
│ 서버 프록시 (Vercel + Hono, server/ 디렉터리)                      │
│  M4: POST /v1/oauth/notion/exchange   (code→token, secret 은닉)   │
│  M5: POST /v1/oauth/google/exchange · /v1/subscription/verify     │
│      /v1/cloud/transcribe(+폴링) — RTZR·Claude 중계, 무저장       │
│  저장: Vercel KV (익명 기기키 → 구독 상태·월 사용량)               │
└───────────────────────────────────────────────────────────────────┘
```

| 영역 | 선택 | 비고 |
|---|---|---|
| 클라이언트 | SwiftUI · Swift Concurrency · SwiftData · Observation | iOS 26+, iPhone 15 Pro+ |
| 위젯 | WidgetKit + ActivityKit | 녹음 Live Activity (다이나믹 아일랜드) |
| 전사 | Speech(SpeechAnalyzer) / WhisperKit | 설정에서 전환 |
| 화자분리 | FluidAudio 0.12+ | SPM |
| 요약 | FoundationModels | @Generable guided generation |
| 서버 | Hono on Vercel Functions + Vercel KV + Vercel Blob | Blob은 M5 오디오 중계용 |
| 결제 | StoreKit 2 + App Store Server API | 검증은 서버 |

## 3. 레포 디렉터리 구조

계획된 전체 트리. 각 파일의 생성 시점은 해당 마일스톤 문서의 산출물 절에 명시.

```
nepnep/
├── docs/
│   ├── PRD.md
│   └── plan/                        # 본 계획서 10개
├── ios/
│   ├── NepNep.xcodeproj
│   ├── NepNep/
│   │   ├── NepNepApp.swift          # @main, 스토어 주입, 딥링크 라우팅
│   │   ├── AppRootView.swift        # 온보딩 완료 여부 분기
│   │   ├── Core/
│   │   │   ├── Models/              # SwiftData 모델 (M1)
│   │   │   │   ├── Meeting.swift
│   │   │   │   ├── Speaker.swift
│   │   │   │   ├── Utterance.swift
│   │   │   │   └── Summary.swift
│   │   │   ├── Audio/               # 녹음·재생 (M1)
│   │   │   │   ├── AudioSessionController.swift
│   │   │   │   ├── ChunkedAudioWriter.swift
│   │   │   │   ├── RecordingSession.swift
│   │   │   │   ├── AudioPlayerService.swift
│   │   │   │   └── AudioTranscoder.swift
│   │   │   ├── Pipeline/            # 처리 파이프라인 (M2)
│   │   │   │   ├── ProcessingCoordinator.swift
│   │   │   │   ├── ProcessingCheckpoint.swift
│   │   │   │   ├── TranscriptionEngine.swift      # 프로토콜
│   │   │   │   ├── SpeechTranscriberEngine.swift
│   │   │   │   ├── WhisperKitEngine.swift
│   │   │   │   ├── DiarizationService.swift
│   │   │   │   ├── TranscriptMerger.swift
│   │   │   │   └── ModelAssetManager.swift        # 에셋 다운로드 상태
│   │   │   ├── Summary/             # 요약 (M3)
│   │   │   │   ├── SummaryService.swift
│   │   │   │   ├── SummaryTemplates.swift
│   │   │   │   ├── SummarySchemas.swift           # @Generable 구조체
│   │   │   │   └── TranscriptChunker.swift
│   │   │   ├── Export/              # 내보내기 (M4·M5)
│   │   │   │   ├── NotionAPIClient.swift
│   │   │   │   ├── NotionBlockBuilder.swift
│   │   │   │   ├── NotionExportService.swift
│   │   │   │   ├── GoogleDocsClient.swift
│   │   │   │   ├── GoogleDocsExportService.swift
│   │   │   │   └── OAuthCoordinator.swift         # ASWebAuthenticationSession 공용
│   │   │   ├── Cloud/               # 유료 파이프라인 (M5)
│   │   │   │   ├── CloudProcessingClient.swift
│   │   │   │   └── PurchaseService.swift
│   │   │   ├── Storage/
│   │   │   │   ├── AudioFileStore.swift           # 파일 경로 규약·용량 계산 (M1)
│   │   │   │   └── KeychainStore.swift            # 토큰 저장 (M4)
│   │   │   └── Support/
│   │   │       ├── NotificationService.swift      # 로컬 알림 (M2)
│   │   │       └── DesignTokens.swift             # §4 토큰 (M1)
│   │   ├── Features/
│   │   │   ├── Home/                # (M2-UI)
│   │   │   │   ├── HomeView.swift
│   │   │   │   ├── MeetingCardView.swift
│   │   │   │   └── HomeEmptyStateView.swift
│   │   │   ├── Recording/           # (M1)
│   │   │   │   ├── RecordingView.swift
│   │   │   │   ├── LevelMeterView.swift
│   │   │   │   └── MeetingTypePicker.swift
│   │   │   ├── Processing/          # (M2-UI)
│   │   │   │   └── ProcessingView.swift
│   │   │   ├── MeetingDetail/       # (M2-UI · M3)
│   │   │   │   ├── MeetingDetailView.swift
│   │   │   │   ├── TranscriptListView.swift
│   │   │   │   ├── UtteranceRow.swift
│   │   │   │   ├── SummarySectionView.swift
│   │   │   │   ├── ActionItemListView.swift
│   │   │   │   └── SpeakerAssignSheet.swift
│   │   │   ├── Export/              # (M4)
│   │   │   │   ├── ExportSheet.swift
│   │   │   │   └── NotionTargetPicker.swift
│   │   │   ├── Onboarding/          # (M6)
│   │   │   │   └── OnboardingFlow.swift
│   │   │   ├── Settings/            # (M5·M6)
│   │   │   │   ├── SettingsView.swift
│   │   │   │   ├── EnginePickerView.swift
│   │   │   │   ├── StorageManagementView.swift
│   │   │   │   └── UsageView.swift
│   │   │   └── Paywall/             # (M5)
│   │   │       └── PaywallView.swift
│   │   ├── Resources/Assets.xcassets
│   │   └── Info.plist               # audio 백그라운드 모드, BGTaskScheduler 식별자
│   ├── NepNepWidgets/               # Widget Extension (M1)
│   │   ├── NepNepWidgetsBundle.swift
│   │   ├── RecordingLiveActivity.swift
│   │   └── RecordingActivityAttributes.swift      # 앱과 공유(양쪽 타깃 멤버십)
│   └── NepNepTests/
│       ├── TranscriptMergerTests.swift            # (M2)
│       ├── CheckpointTests.swift                  # (M2)
│       ├── TranscriptChunkerTests.swift           # (M3)
│       ├── NotionBlockBuilderTests.swift          # (M4)
│       └── UsageCalculatorTests.swift             # (M5)
├── server/                          # Vercel 프로젝트 (M4 최소 → M5 확장)
│   ├── package.json
│   ├── vercel.json
│   ├── api/index.ts                 # Hono 앱 엔트리
│   └── src/
│       ├── routes/oauth.ts          # M4: notion, M5: google
│       ├── routes/subscription.ts   # M5
│       ├── routes/cloud.ts          # M5
│       ├── lib/kv.ts
│       └── lib/appstore.ts          # App Store Server API 검증
└── spike/                           # M0 스파이크 전용 (출시 코드와 분리)
    └── NepNepSpike/                 # 최소 앱: 파이프라인 실측 하네스
```

## 4. 디자인 가이드 — 와이어프레임 연동 (모든 마일스톤 공통)

**단일 진실 소스는 claude.ai/design 프로젝트(NepNep Wireframes)다.** 각 마일스톤 문서의 UI 작업은 아래 규약을 따른다.

1. 와이어프레임은 전 화면 완성 상태다: **1a 온보딩 · 1b 홈 · 1c 녹음+Live Activity · 1d 처리 중 · 1e 회의록 상세(요약/전사) · 1f 화자 이름 지정 시트 · 1g 내보내기 시트(선택→진행→완료) · 1h 설정 · 1i 페이월.** 각 프레임의 레이아웃·문구·상태·인터랙션 노트를 그대로 구현한다.
2. **각 마일스톤의 UI 작업 착수 직전에 `/design-sync`(claude design의 design sync)로 해당 화면 최신본을 받아 변경 여부를 확인한다.** 가져오기 프롬프트: claude_design MCP(`https://api.anthropic.com/v1/design/mcp`, `/design-login` 인증)로 프로젝트 `https://claude.ai/design/p/71aacacc-9ee1-4fa8-9a5b-4316c2bcfabe`의 `NepNep Wireframes.dc.html`(+ `support.js`)을 읽는다.
3. 디자인 토큰은 `Core/Support/DesignTokens.swift` 한 곳에 정의하고 하드코딩을 금지한다.

와이어프레임에서 추출한 토큰 (DesignTokens.swift의 초기값):

| 토큰 | 라이트 | 다크 |
|---|---|---|
| `accent` | #0F7A72 | #3FBFB0 |
| `accentSoft` (배지·아이콘 배경) | rgba(15,122,114,.1) | rgba(63,191,176,.15) |
| `background` | #F7F6F3 | #0B0B0C |
| `card` | #FFFFFF | #18191B |
| `textPrimary / secondary / tertiary` | #17181A / #6B6B70 / #A8A8AD | #F3F3F5 / #9A9AA0 / #6B6B72 |
| `fill` (필드·보조 버튼) | rgba(0,0,0,.05) | rgba(255,255,255,.07) |
| 상태색 처리중/실패 | #B4741C / #B03A31 (배경 .12 투명) | #E0A34A / #FF8579 (.16 투명) |

레이아웃 규칙: 8pt 그리드 · 화면 좌우 여백 20pt · 섹션 간격 24pt · 카드 라운드 16pt(내부 12pt, 시트 상단 22pt) · 버튼 높이 52pt · 셀 최소 52pt · 탭 타깃 44pt · 구분선 1px 좌 16pt 인셋 · 녹음 FAB 68pt 원형. 타입: SF Pro/Pretendard 시스템 스케일(34/28/22/17/15/13/11), 경과 시간은 SF Mono Semibold tabular-nums.

## 5. 의존성 그래프 · 병렬화 지점

```
M0 (게이트: 통과 못 하면 이후 착수 금지)
 └→ M1 (녹음 코어) ─→ M2-A (파이프라인) ─→ M2-B (대화록 UI) ─→ M3 (요약+상세)
                                                    │               └→ M4 (Notion + 서버 최소) ─→ TestFlight
                                                    │                        └→ M5-A (서버·IAP·클라우드)
                                                    │                        └→ M5-B (GDocs·저장공간)
                                                    └──────────────────────────→ M6 (온보딩·설정·출시)
```

- M2-B의 홈 리스트/처리 중 화면은 M2-A의 상태 모델만 확정되면 병렬 착수 가능 (같은 사람이면 순차).
- M5-A와 M5-B는 서로 독립 — 병렬 가능. M5-B의 Google OAuth 교환 엔드포인트만 M5-A 서버 작업과 공유.
- M6 온보딩은 M4 이후 언제든 착수 가능 (모델 다운로드 화면은 M2-A의 ModelAssetManager에 의존).

## 6. 위험 요소와 완화책 (plan 수준)

| 위험 | 확률 | 영향 | 완화책 |
|---|---|---|---|
| SpeechTranscriber 한국어 에셋 다운로드 불안정 (포럼에 "asset not found" 보고) | 중 | 기본 엔진 못 씀 | M0에서 실기기 검증. 실패 시 WhisperKit을 기본 엔진으로 승격 (설정 구조는 동일) |
| `BGContinuedProcessingTask`가 기대만큼 실행 시간을 주지 않음 | 중 | 백그라운드 완주 실패 | 체크포인트 재개(M2-A)가 안전망. 포그라운드 복귀 시 이어서 처리 |
| Foundation Models 4,096토큰 제약으로 map-reduce 품질 저하 | 중 | 요약 신뢰도 | M3에서 청크 크기·프롬프트 QA 세트로 조정. 실패 시 재시도 + 클라우드 업셀 |
| Vercel 함수 제약(요청 바디 4.5MB·실행 시간)으로 M5 오디오 중계 불가 | 높 | 클라우드 파이프라인 재설계 | Vercel Blob 클라이언트 직접 업로드 + 서버는 URL만 중계로 설계 (07 문서에 반영). 부족하면 Cloudflare Workers+R2로 이전 검토 |
| 와이어프레임이 구현 중 개정되어 코드와 어긋남 | 중 | 재작업 | 각 마일스톤 UI 착수 직전 design sync로 재확인하는 규약 (§4-2) |
| SwiftData 대량 Utterance(1시간 회의 ≈ 수백~천 행) 저장 성능 | 저 | 리스트 버벅임 | Utterance는 배치 insert, 리스트는 지연 로딩. 문제 시 Utterance만 JSON 파일로 분리 (가정 유지) |

## 7. 완료 체크리스트 (전체)

- [ ] M0: 실기기에서 30분 한국어 회의 → 전사+화자분리 실측, 클로바노트 대비 체감 동등 + 30분 처리 ≤ 10분
- [ ] M1: 백그라운드·인터럽트·강제종료에서 녹음 파일이 유실되지 않고 복구됨
- [ ] M2-A: 정지 → 백그라운드 방치 → "회의록 준비" 알림 → 화자 라벨 대화록 생성
- [ ] M2-B: 홈 리스트 상태 배지·처리 진행률·화자 이름 지정이 와이어프레임대로 동작
- [ ] M3: 템플릿 4종 요약 + 할 일 구조화 추출 + 인라인 편집
- [ ] M4: 실 Notion 워크스페이스 DB에 회의록 페이지 자동 생성 → TestFlight 배포
- [ ] M5: 샌드박스 구독 → 클라우드 처리 완주 + 사용량 카운팅, GDocs 내보내기, 저장공간 관리
- [ ] M6: 온보딩 완주 → 심사 제출 자료 완비, 테스트 세트 회귀 통과
- [ ] 전체: 신규 기기에서 설치 → 온보딩 → 녹음 → 회의록 → Notion 내보내기 E2E 완주

## 8. 오픈 이슈

| # | 항목 | 채택한 기본값 | 달라지면 |
|---|---|---|---|
| A | 오디오 보관 포맷 (녹음 CAF → 완료 후 AAC 트랜스코드) | 트랜스코드 채택 (가정) | 트랜스코드 생략 시 1시간 ≈ 115MB 보관 — F11 화면의 용량 표시만 커짐, 구조 변화 없음 |
| B | WhisperKit 모델 variant | turbo_632MB (가정) | M0 실측에서 non-turbo 626MB의 한국어 CER이 유의미하게 좋으면 교체 — 상수 1곳 변경 |
| C | 클라우드 요약 Claude 모델 티어 | claude-sonnet-5 (가정) | M5에서 A/B — 서버 환경변수만 변경 |
| D | RTZR 무료 한도·단가 실계약 조건 | 시간당 ₩1,000(할인 전) 기준 원가 계산 | 단가 확정 시 §10 수익성 재검토 (PRD 오픈 이슈 #6) |
| E | Utterance 저장 위치 (SwiftData vs JSON 파일) | SwiftData (가정) | 성능 문제 시 M2-A에서 JSON 분리 — TranscriptMerger 출력부만 변경 |
