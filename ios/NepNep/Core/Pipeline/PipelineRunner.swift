import Foundation

/// 전사 → 화자분리 → 병합 순수 실행기 (03-m2 §4의 실행 골격)
/// BG 태스크·SwiftData 반영은 ProcessingCoordinator가 담당하고,
/// 여기는 체크포인트 재개 로직만 갖는다 — 유닛 테스트에서 스텁 주입 대상.
struct PipelineRunner {
    enum StageProgress {
        case transcribing(Double)   // 0…1
        case diarizing
        case merging
        case summarizing(Double)    // 0…1 — 러너 밖(ProcessingCoordinator)에서만 발행
    }

    let engine: TranscriptionEngine
    let diarizer: DiarizationProviding
    let checkpoint: ProcessingCheckpoint

    /// 체크포인트가 있으면 완료된 단계는 건너뛴다 (F10-2)
    func run(audioURL: URL,
             onProgress: @escaping (StageProgress) -> Void) async throws -> [MergedUtterance] {
        let state = checkpoint.loadState()

        // 1. 전사
        let words: [TranscriptWord]
        if let saved = checkpoint.loadWords(), state != nil {
            words = saved
        } else {
            onProgress(.transcribing(0))
            words = try await engine.transcribe(url: audioURL) { onProgress(.transcribing($0)) }
            try checkpoint.saveWords(words, engineID: engine.id)
        }

        // 2. 화자분리
        let segments: [SpeakerSegment]
        if let saved = checkpoint.loadSegments(), state?.stage == .diarized {
            segments = saved
        } else {
            onProgress(.diarizing)
            segments = try await diarizer.diarize(url: audioURL)
            try checkpoint.saveSegments(segments, engineID: engine.id)
        }

        // 3. 병합 (순수 연산 — 체크포인트 불필요)
        onProgress(.merging)
        return TranscriptMerger.merge(words: words, segments: segments)
    }
}
