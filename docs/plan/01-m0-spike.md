# 넵넵 개발 계획서 — 01. M0 기술 검증 스파이크 (v0.1)

작성일: 2026-08-22 | 버전: v0.1 | 베이스 커밋: main @ dcaeef9 | 선행: 없음 (최우선 게이트)

**한 줄 요약:** 출시 코드와 분리된 스파이크 앱으로 "SpeechTranscriber/WhisperKit 전사 + FluidAudio 화자분리" 파이프라인을 실기기에서 실측하고, PRD §11-M0 통과 기준을 판정한다. **미통과 시 이후 마일스톤 착수 금지.**

관련 문서: [00-overview](00-overview.md) · [PRD §11-M0](../PRD.md)

## 목표

iPhone 15 Pro급 실기기에서 30분 한국어 회의 오디오를 두 전사 엔진 × FluidAudio로 처리해 CER·DER·처리 시간·발열·배터리를 수치로 확보하고, 클로바노트와 블라인드 비교해 "체감 동등" 여부를 판정한다.

## 산출물

- `spike/NepNepSpike/` — 신설. 최소 SwiftUI 앱 (화면 1개: 파일 선택 → 실행 → 결과 표시)
  - `SpikeApp.swift` — @main
  - `SpikeView.swift` — 오디오 파일 선택(파일 앱 import), 엔진 선택 세그먼트, 실행 버튼, 단계별 소요 시간·결과 미리보기
  - `SpikeRunner.swift` — 파이프라인 실행 + 계측
  - `ResultExporter.swift` — 전사 텍스트·화자 세그먼트·계측치를 JSON으로 파일 앱에 내보내기
- `spike/testset/README.md` — 신설. 테스트 세트 구성 기록 (PRD §2.3: 2인/4인/6인 × 조용함/시끄러움 × 30분 내외, 최소 8개)
- `docs/plan/m0-results.md` — 신설(스파이크 종료 시). 실측 결과와 게이트 판정 기록

## 핵심 작업

### 1. 테스트 세트 준비 (코딩 전, 병렬 진행)

- 실제 한국어 회의 녹음 8개 확보(직접 녹음 또는 공개 회의 영상 추출). 각 파일에 대해 정답 대본(사람이 교정)과 화자 구간 라벨을 만든다 — CER/DER 계산의 기준.
- 각 파일을 클로바노트에도 입력해 결과 저장 (블라인드 비교용).
- 포맷: 16kHz mono WAV로 통일 (`afconvert -f WAVE -d LEI16@16000 -c 1 in.m4a out.wav`).

### 2. 스파이크 앱 뼈대

Xcode로 `spike/NepNepSpike` iOS App 생성 (iOS 26 타깃, 실기기 서명). SPM 의존성 2개:

```
https://github.com/FluidInference/FluidAudio.git  from: 0.12.4
https://github.com/argmaxinc/argmax-oss-swift.git from: 0.9.0   // product: WhisperKit
```

### 3. SpeechTranscriber 경로

```swift
import Speech

func transcribeWithApple(url: URL) async throws -> [(text: String, range: CMTimeRange?)] {
    let locale = Locale(identifier: "ko-KR")
    let transcriber = SpeechTranscriber(
        locale: locale,
        transcriptionOptions: [],
        reportingOptions: [],                       // volatile 불필요 — 일괄 전사
        attributeOptions: [.audioTimeRange])        // 타임스탬프 필수
    // 에셋 설치 (최초 1회)
    if let req = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
        try await req.downloadAndInstall()
    }
    let analyzer = SpeechAnalyzer(modules: [transcriber])
    async let results: [(String, CMTimeRange?)] = {
        var acc: [(String, CMTimeRange?)] = []
        for try await r in transcriber.results where r.isFinal {
            for run in r.text.runs {
                acc.append((String(r.text[run.range].characters), run.audioTimeRange))
            }
        }
        return acc
    }()
    if let last = try await analyzer.analyzeSequence(from: AVAudioFile(forReading: url)) {
        try await analyzer.finalizeAndFinish(through: last)
    }
    return try await results
}
```

주의: 시뮬레이터에서 에셋 다운로드가 불안정하다는 보고가 있으니 **처음부터 실기기에서만** 돌린다.

### 4. WhisperKit 경로

```swift
import WhisperKit

func transcribeWithWhisper(url: URL, variant: String) async throws -> TranscriptionResult {
    // variant 후보 2개를 모두 실측: "large-v3-v20240930_turbo_632MB", "large-v3-v20240930_626MB"
    let pipe = try await WhisperKit(WhisperKitConfig(model: variant))
    let opts = DecodingOptions(language: "ko", withoutTimestamps: false, wordTimestamps: true)
    return try await pipe.transcribe(audioPath: url.path, decodeOptions: opts).first!
}
```

### 5. FluidAudio 경로

```swift
import FluidAudio

func diarize(url: URL) async throws -> DiarizationResult {
    let manager = OfflineDiarizerManager(config: OfflineDiarizerConfig())
    try await manager.prepareModels()          // 최초 실행 시 HF에서 ~129MB 다운로드
    return try await manager.process(url)      // 메모리맵 스트리밍 — 긴 파일 권장 경로
}
```

### 6. 계측 (SpikeRunner)

- 단계별 소요 시간: `ContinuousClock` 로 전사/화자분리 각각 측정.
- 배터리: 실행 전후 `UIDevice.current.batteryLevel` 기록 (batteryMonitoringEnabled).
- 발열: `ProcessInfo.processInfo.thermalState` 를 단계 종료마다 기록.
- 결과 JSON: `{file, engine, transcribeSec, diarizeSec, thermal, batteryDrop, text, segments[]}`.

### 7. 오프라인 평가 (Mac에서)

- CER: 정답 대본 대비. 간단한 파이썬 스크립트(`jiwer` 라이브러리, `spike/testset/eval.py`)로 계산.
- DER: 화자 라벨 구간 대비 `pyannote.metrics` 사용.
- 블라인드 선호도: 동일 파일의 클로바노트 결과와 넵넵 결과를 나란히 놓고 어느 쪽인지 가린 채 비교 (본인 + 지인 2~3명).

## 완료 기준 (게이트 판정)

- [ ] 실기기에서 8개 테스트 파일 전부 파이프라인 완주 (크래시·중단 없음)
- [ ] `m0-results.md`에 파일×엔진별 CER·DER·처리 시간·발열·배터리 표 기록
- [ ] **게이트 1: 30분 파일 처리(전사+화자분리 합산) ≤ 10분** — 두 엔진 중 하나라도 충족
- [ ] **게이트 2: 클로바노트 블라인드 비교 "체감 동등" 이상** — 8개 중 4개 이상에서 넵넵 선호 또는 무차이
- [ ] 오픈 이슈 B 판정: WhisperKit variant 확정 (turbo vs non-turbo CER 차이 기록)
- [ ] 판정 결과를 00-overview §1 결정 표에 반영 (기본 엔진 확정 포함)

**미통과 시:** PRD §11-M0 지침대로 설계 재검토(클라우드 우선 전환 등)를 별도 문서로 작성하고, 02 이후 문서를 개정하기 전까지 착수하지 않는다.
