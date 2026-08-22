# 넵넵 개발 계획서 — 03. M2-A 처리 파이프라인 (v0.1)

작성일: 2026-08-22 | 버전: v0.1 | 베이스 커밋: main @ dcaeef9 | 선행: [02-m1](02-m1-recording.md)

**한 줄 요약:** 녹음 정지 → 전사(엔진 2종) → 화자분리 → 병합 → (요약 자리 비움) 파이프라인을 `BGContinuedProcessingTask` 안에서 체크포인트와 함께 완주시키고, 완료 로컬 알림까지 연결한다. PRD F2 · F3 · F10(-4 UI 제외).

관련 문서: [00-overview](00-overview.md) · [PRD F2·F3·F10](../PRD.md) · UI는 [04-m2-transcript-ui](04-m2-transcript-ui.md)

## 목표

실기기에서 정지 버튼을 누르고 앱을 백그라운드로 보내도, 몇 분 뒤 "회의록이 준비됐어요" 알림이 오고 Meeting에 화자 라벨이 붙은 Utterance들이 저장되어 있다.

## 산출물

| 파일 | 구분 | 내용 |
|---|---|---|
| `Core/Pipeline/ProcessingCoordinator.swift` | 신설 | 파이프라인 오케스트레이션 + BGContinuedProcessingTask |
| `Core/Pipeline/ProcessingCheckpoint.swift` | 신설 | 단계별 중간 산출물 저장·복원 |
| `Core/Pipeline/TranscriptionEngine.swift` | 신설 | 엔진 프로토콜 + 공용 타입 |
| `Core/Pipeline/SpeechTranscriberEngine.swift` | 신설 | 기본 엔진 (M0 §3 코드 재사용) |
| `Core/Pipeline/WhisperKitEngine.swift` | 신설 | 대안 엔진 (M0 §4 코드 재사용) |
| `Core/Pipeline/DiarizationService.swift` | 신설 | FluidAudio 래퍼 (M0 §5 코드 재사용) |
| `Core/Pipeline/TranscriptMerger.swift` | 신설 | 타임스탬프 × 세그먼트 병합 (F3-2) |
| `Core/Pipeline/ModelAssetManager.swift` | 신설 | 엔진별 에셋 상태 관리 (F2-3) |
| `Core/Support/NotificationService.swift` | 신설 | 완료/실패 로컬 알림 + 딥링크 |
| `Core/Audio/AudioTranscoder.swift` | 재활용·수정 | 파이프라인 성공 후 CAF→m4a 실행 연결 |
| `NepNepTests/TranscriptMergerTests.swift` | 신설 | 병합 케이스 |
| `NepNepTests/CheckpointTests.swift` | 신설 | 저장·복원 라운드트립 |

## 핵심 작업

### 1. 공용 타입과 엔진 프로토콜

```swift
struct TranscriptWord: Codable { let text: String; let start: TimeInterval; let end: TimeInterval; let confidence: Double }
struct SpeakerSegment: Codable { let speakerKey: String; let start: TimeInterval; let end: TimeInterval }

protocol TranscriptionEngine {
    var id: EngineID { get }                       // .speechTranscriber | .whisperKit
    func isReady() async -> Bool                   // 에셋 설치 여부
    func transcribe(url: URL, progress: @escaping (Double) -> Void) async throws -> [TranscriptWord]
}
```

- SpeechTranscriberEngine: M0 코드에 진행률 추가 — `AVAudioFile.length` 대비 마지막 결과의 `audioTimeRange.end`로 계산.
- WhisperKitEngine: `WhisperKit.transcribe`의 콜백 기반 진행률 사용. 모델 variant는 `ModelAssetManager.whisperVariant` 상수 1곳 (M0 판정값).

### 2. TranscriptMerger (F3-2 — 유닛 테스트 대상 1순위)

입력: `[TranscriptWord]` + `[SpeakerSegment]`. 출력: `[MergedUtterance]`.

알고리즘:
1. 각 단어의 중심점 `mid = (start+end)/2`가 포함되는 화자 세그먼트에 배정. 어느 세그먼트에도 안 들어가면 **가장 가까운 세그먼트**(경계 거리 최소)에 배정.
2. 인접 단어가 같은 화자면 하나의 발화로 이어 붙인다. 화자가 바뀌거나 단어 간 간격 > 1.5초면 발화를 끊는다.
3. 발화 confidence = 단어 confidence 평균. 화자 라벨은 세그먼트 등장 순서대로 "화자 1", "화자 2"… (Speaker 레코드 생성, colorIndex 순환 0..7).

테스트 케이스(최소): 겹침 경계 단어의 중심점 배정 / 세그먼트 밖 단어의 최근접 배정 / 1.5초 간격 발화 분리 / 화자 2·4명 시나리오 / 빈 세그먼트(화자분리 실패) 시 전체를 "화자 1"로.

### 3. ProcessingCheckpoint (F10-2)

```
Documents/audio/<meetingID>/checkpoint/
 ├ words.json       # 전사 완료 시
 ├ segments.json    # 화자분리 완료 시
 └ state.json       # {stage, engineID, updatedAt}
```

- 각 단계 완료 직후 원자적 write(`.atomic`). 파이프라인 시작 시 `state.json`을 읽어 완료된 단계는 건너뛴다.
- 전 단계 성공(요약은 M3에서 stage 추가) 후 checkpoint 디렉터리 삭제.
- 테스트: 라운드트립(save→load 동일성), 부분 체크포인트에서 재개 시 남은 단계만 실행되는지(엔진을 스텁으로 주입해 호출 횟수 검증).

### 4. ProcessingCoordinator (F10-1·2·3)

```swift
@Observable final class ProcessingCoordinator {
    func enqueue(meeting: Meeting) // 정지 직후 RecordingSession.handoff에서 호출
}
```

- 실행 골격: `BGContinuedProcessingTask` 제출 → 태스크 클로저 안에서 순차 실행. 단계마다 `meeting.processingStage/-Progress` 갱신(SwiftData 저장은 메인 액터 경유). iOS 26의 continued processing은 시스템 Live Activity로 진행률을 노출하므로 `task.progress`도 함께 갱신한다.
- Info.plist: `BGTaskSchedulerPermittedIdentifiers`에 `com.nepnep.processing.continued` 추가 (와일드카드 미사용).
- OS가 태스크를 만료시키면: 체크포인트는 이미 단계별로 저장돼 있으므로 `meeting.status`를 `.processing` 유지 + `needsResume` 플래그. **다음 포그라운드 진입 시(`scenePhase == .active`) 미완료 Meeting을 스캔해 재-enqueue** (F10-2의 "다음 실행 시 재개").
- 단계 실패 시: `meeting.status = .failed` + 실패 원인 enum 저장(엔진 에셋 없음/저장공간/모델 오류) → 실패 알림. 전사·화자분리 산출물은 보존(F5-4 대비).
- 파이프라인 성공 후: `AudioTranscoder.transcode(caf → m4a, AAC 32kbps mono)` 실행, 성공 시 CAF 삭제·`audioSize` 갱신 (00-overview 결정 "오디오 저장 포맷").

### 5. ModelAssetManager (F2-2·3)

```swift
@Observable final class ModelAssetManager {
    var speechAssetState: AssetState   // notInstalled/downloading(progress)/installed
    var whisperState: AssetState
    var selectedEngine: EngineID       // UserDefaults 저장, 기본 .speechTranscriber
    func ensureSpeechAsset() async throws   // AssetInventory 요청 (M0 §3)
    func downloadWhisper() async throws     // WhisperKit.download(variant:progressCallback:)
}
```

- 엔진 전환 UI는 설정 화면(M6)이지만 상태 모델·다운로드 로직은 여기서 완성. 미설치 엔진 선택 시 파이프라인은 시작 전에 `.failed(assetMissing)`로 빠지지 않고 다운로드 유도 에러를 던진다.

### 6. NotificationService (F10-3)

- 권한 요청은 온보딩(M6)에서. M2에서는 `UNUserNotificationCenter` 권한이 있으면 발송.
- 완료: "회의록이 준비됐어요 — <제목>", userInfo에 `meetingID`. 탭 → `NepNepApp`의 `onOpenURL`/delegate에서 해당 상세 화면으로 딥링크 (상세 화면은 M2-B 이후 실동작).
- 실패: "정리하지 못했어요 — 탭해서 다시 시도".

## 완료 기준

- [ ] `xcodebuild test`: TranscriptMergerTests(≥5케이스)·CheckpointTests(≥3케이스) 통과
- [ ] 실기기: 10분 녹음 → 정지 → 즉시 홈 화면으로 나가 잠금 → 완료 알림 수신 → Meeting에 Utterance·Speaker 저장 확인
- [ ] 실기기: 처리 중 앱 강제 종료 → 재실행 → 체크포인트부터 재개해 완주 (전사를 다시 돌지 않았음을 로그로 확인)
- [ ] 엔진 전환: `selectedEngine = .whisperKit` 상태에서 동일 파일 처리 완주 (모델 다운로드 포함)
- [ ] 처리 성공 후 `recording.m4a`만 남고 CAF·checkpoint가 삭제됨
