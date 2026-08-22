# 넵넵 개발 계획서 — 02. M1 녹음 코어 (v0.1)

작성일: 2026-08-22 | 버전: v0.1 | 베이스 커밋: main @ dcaeef9 | 선행: [01-m0](01-m0-spike.md) 게이트 통과

**한 줄 요약:** 본 프로젝트(`ios/NepNep`)를 생성하고, 크래시에도 유실되지 않는 청크 녹음 + 백그라운드 유지 + Live Activity + 녹음 화면(와이어프레임 1c)을 완성한다. PRD F1 전체.

관련 문서: [00-overview](00-overview.md) · [PRD F1](../PRD.md)

## 디자인 참조

- 녹음 화면·Live Activity는 **와이어프레임 1c 확정본** 그대로: 상단 취소 / 제목(자동 생성 + 연필 수정) / 유형 세그먼트(일반·1on1·인터뷰·스탠드업) / 중앙 대형 경과 시간(SF Mono) / 레벨 미터 / 클라우드 토글(PRO 배지 — M5 전까지 탭 시 "준비 중" 비활성) / 하단 일시정지·완료. 구현 착수 전 `/design-sync`로 최신본 확인.
- 인터랙션 노트 반영: ① 제목은 "회의 유형·시각"으로 자동 생성(예: "8월 22일 일반 회의") ② 레벨 미터는 입력 신호만 시각화, 30초 무음 시 "소리가 들리지 않아요" 힌트 ③ 일시정지 중에는 중앙 버튼이 재개로 바뀜 ④ Live Activity에는 일시정지·완료 두 동작만.

## 목표

화면 잠금·앱 전환·전화 인터럽트·강제 종료 어떤 상황에서도 녹음 데이터가 유실되지 않고, 정지 시점에 처리 파이프라인에 넘길 수 있는 16kHz mono 오디오 파일이 남는다.

## 산출물

| 파일 | 구분 | 내용 |
|---|---|---|
| `ios/NepNep.xcodeproj` | 신설 | 앱 타깃(iOS 26) + `NepNepWidgets` 위젯 익스텐션 + `NepNepTests` |
| `ios/NepNep/Info.plist` | 신설 | `UIBackgroundModes: [audio]`, `NSMicrophoneUsageDescription`, `BGTaskSchedulerPermittedIdentifiers: [com.nepnep.processing]`(M2 대비), `NSSupportsLiveActivities: YES` |
| `ios/NepNep/NepNepApp.swift` | 신설 | ModelContainer 생성, 스토어 Environment 주입, 복구 검사 호출 |
| `ios/NepNep/AppRootView.swift` | 신설 | 임시: HomeView 자리에 "녹음 시작" 버튼 하나 (홈은 M2-B) |
| `ios/NepNep/Core/Models/Meeting.swift` 외 3 | 신설 | §데이터 모델 |
| `ios/NepNep/Core/Audio/AudioSessionController.swift` | 신설 | 세션 설정·인터럽트 처리 |
| `ios/NepNep/Core/Audio/ChunkedAudioWriter.swift` | 신설 | 청크 순차 기록 |
| `ios/NepNep/Core/Audio/RecordingSession.swift` | 신설 | @Observable 녹음 상태 머신 |
| `ios/NepNep/Core/Audio/AudioTranscoder.swift` | 신설 | CAF→m4a (M2에서 호출, 유틸만 준비) |
| `ios/NepNep/Core/Storage/AudioFileStore.swift` | 신설 | 파일 경로 규약·용량 계산·여유 공간 체크 |
| `ios/NepNep/Core/Support/DesignTokens.swift` | 신설 | 00-overview §4 토큰 |
| `ios/NepNep/Features/Recording/RecordingView.swift` 외 2 | 신설 | 녹음 화면 |
| `ios/NepNepWidgets/RecordingLiveActivity.swift` 외 2 | 신설 | Live Activity |

## 핵심 작업

### 1. SwiftData 모델 (PRD §9.5 그대로)

```swift
@Model final class Meeting {
    @Attribute(.unique) var id: UUID
    var title: String
    var typeRaw: String            // MeetingType: general/oneOnOne/interview/standup
    var createdAt: Date
    var duration: TimeInterval
    var statusRaw: String          // MeetingStatus 인코딩: recording/processing/done/failed
    var processingStage: String?   // transcribing/diarizing/merging/summarizing
    var processingProgress: Double // 0...1, 홈 카드 진행률
    var audioFileName: String?     // AudioFileStore 규약 기준 상대 경로
    var audioSize: Int64
    var processingModeRaw: String  // onDevice/cloud
    var notionPageURL: String?
    var googleDocURL: String?
    var gapRanges: [GapRange]      // 인터럽트로 누락된 구간 [Codable]
    @Relationship(deleteRule: .cascade) var speakers: [Speaker]
    @Relationship(deleteRule: .cascade) var utterances: [Utterance]
    @Relationship(deleteRule: .cascade) var summary: Summary?
}
@Model final class Speaker { var id: UUID; var label: String; var customName: String?; var colorIndex: Int }
@Model final class Utterance {
    var speakerID: UUID; var text: String
    var startTime: TimeInterval; var endTime: TimeInterval
    var confidence: Double; var orderIndex: Int   // 정렬 키 — 시간순
}
@Model final class Summary { /* M3에서 필드 확장. 지금은 templateTypeRaw만 */ var templateTypeRaw: String }
```

### 2. 파일 경로 규약 (AudioFileStore)

```
Documents/audio/<meetingID>/
 ├ chunk-000.caf, chunk-001.caf, …   # 녹음 중 (5분 단위)
 ├ recording.caf                      # 정지 시 청크 병합본 (파이프라인 입력)
 └ recording.m4a                      # 처리 완료 후 트랜스코드본 (재생용, CAF 삭제)
```

- 시작 전 여유 공간 체크: `URL.volumeAvailableCapacityForImportantUsageKey` ≥ 예상 용량(115MB/h × 2h) + 500MB. 부족 시 시작 차단 알럿 (F11 화면 유도는 M5-B에서 연결).

### 3. 오디오 세션 + 엔진 (AudioSessionController · ChunkedAudioWriter)

- 세션: `.playAndRecord`, mode `.default`, options `[.allowBluetooth]`. 활성화는 녹음 시작 직전.
- `AVAudioEngine.inputNode`에 탭 설치 → `AVAudioConverter`로 16kHz mono Int16 변환 → `AVAudioFile`(CAF)에 순차 write. **write는 전용 직렬 큐에서, 5분(4800만 샘플 아님 — 300초)마다 파일 교체.** CAF+PCM은 헤더 갱신 없이도 추가 기록이 유효해 크래시 시 마지막 버퍼(≤수백 ms)만 잃는다.
- 인터럽트(F1-5): `AVAudioSession.interruptionNotification` 구독. `.began` → 상태 `.pausedByInterruption`, 타임스탬프 기록. `.ended` + `.shouldResume` → 자동 재개, 누락 구간을 `Meeting.gapRanges`에 append.
- 최대 길이 가드(F1-6): 경과 4시간 도달 시 자동 정지 + 알럿 (분할 저장은 "정지 후 새 회의 시작 유도"로 단순화 — SHOULD 항목).

### 4. 녹음 상태 머신 (RecordingSession, @Observable)

```
idle → requestingPermission → recording ⇄ paused(user | interruption)
     → stopping(청크 병합) → handoff(Meeting 저장, M2에서 파이프라인 트리거) → idle
```

- `elapsed`는 일시정지 구간을 제외하고 누적. 레벨은 탭 버퍼의 RMS→dB 변환값을 20Hz로 게시.
- 정지 시: 청크들을 `recording.caf`로 병합(`AVAudioFile` 순차 read→write), `Meeting.status = .processing`(M2 전까지는 `.recorded` 임시 상태), 청크 삭제.

### 5. 크래시 복구 (F1-4)

- 녹음 시작 시 `UserDefaults`에 `activeRecording = {meetingID, startedAt}` 기록, 정상 정지 시 삭제.
- 앱 시작 시 `activeRecording`이 남아 있으면: 청크 존재 확인 → 병합 → 해당 Meeting을 "복구된 녹음"(status recorded)으로 저장하고 홈 진입 시 안내 배너 (배너 UI는 M2-B, 지금은 로직+로그).

### 6. Live Activity (F1-2)

- `RecordingActivityAttributes`: 고정 `meetingTitle`, 동적 `ContentState {elapsed: Date, isPaused: Bool}` — 경과 시간은 `Text(timerInterval:)`로 OS가 갱신 (푸시 불필요).
- 잠금 화면: 제목 + "넵넵 · 녹음 중" + 경과 시간 + 일시정지/완료 버튼(App Intent — `LiveActivityIntent` 채택으로 앱 프로세스에서 실행). 다이나믹 아일랜드: 컴팩트(마이크 아이콘+경과), 확장(일시정지·완료).
- 녹음 시작 시 `Activity.request`, 상태 변화마다 `activity.update`, 정지 시 `activity.end(dismissalPolicy: .immediate)`.

### 7. 녹음 화면 (RecordingView)

와이어프레임 1c 레이아웃. 유형 변경은 `Meeting.typeRaw` 즉시 반영(F1-7). 클라우드 토글은 렌더링만 하고 `disabled(true)` + M5 TODO 주석. 무음 감지: 레벨이 -50dB 미만 30초 지속 시 힌트 라벨 표시.

## 완료 기준

- [ ] 실기기: 녹음 시작 → 화면 잠금 → 10분 방치 → 해제 → 경과 시간·레벨 정상, Live Activity에 경과 시간 갱신
- [ ] 실기기: 녹음 중 전화 수신 → 자동 일시정지 → 통화 종료 → 자동 재개, `gapRanges`에 구간 1개 기록
- [ ] 실기기: 녹음 중 앱 스와이프 강제 종료 → 재실행 → 복구된 Meeting 생성, 병합된 `recording.caf` 재생 가능(파일 앱 export로 확인)
- [ ] 정지 후 `recording.caf`가 16kHz mono인지 `afinfo`로 확인
- [ ] Live Activity의 일시정지·완료 버튼이 앱을 열지 않고 동작
- [ ] 1시간 연속 녹음 배터리 소모 ≤ 10% (PRD 비기능)
