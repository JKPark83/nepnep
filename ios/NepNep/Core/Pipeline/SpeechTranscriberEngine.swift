import AVFoundation
import Speech

/// 기본 엔진 — SpeechAnalyzer/SpeechTranscriber (03-m2 §1, M0 §3 코드 재사용)
struct SpeechTranscriberEngine: TranscriptionEngine {
    let id: EngineID = .speechTranscriber

    private func makeTranscriber() -> SpeechTranscriber {
        SpeechTranscriber(
            locale: Locale(identifier: "ko-KR"),
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [.audioTimeRange])
    }

    func isReady() async -> Bool {
        let transcriber = makeTranscriber()
        guard let request = try? await AssetInventory
            .assetInstallationRequest(supporting: [transcriber]) else { return true }
        _ = request
        return false
    }

    /// 언어 에셋 미설치 시 다운로드·설치 (AssetInventory)
    static func ensureAssetsInstalled(onProgress: (@Sendable (Double) -> Void)? = nil) async throws {
        let transcriber = SpeechTranscriberEngine().makeTranscriber()
        guard let req = try await AssetInventory
            .assetInstallationRequest(supporting: [transcriber]) else { return }

        // AssetInstallationRequest.progress 폴링 → 다운로드 진행률 전달
        let poller: Task<Void, Never>? = onProgress.map { report in
            let progress = req.progress
            return Task {
                while !Task.isCancelled {
                    report(progress.fractionCompleted)
                    try? await Task.sleep(for: .milliseconds(300))
                }
            }
        }
        defer { poller?.cancel() }
        try await req.downloadAndInstall()
        onProgress?(1)
    }

    func transcribe(url: URL,
                    progress: @escaping (Double) -> Void) async throws -> [TranscriptWord] {
        let transcriber = makeTranscriber()

        if let req = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await req.downloadAndInstall()
        }

        let audioFile = try AVAudioFile(forReading: url)
        let totalSeconds = Double(audioFile.length) / audioFile.processingFormat.sampleRate

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        async let collected: [TranscriptWord] = {
            var acc: [TranscriptWord] = []
            for try await result in transcriber.results where result.isFinal {
                for run in result.text.runs {
                    let text = String(result.text[run.range].characters)
                    if let range = run.audioTimeRange {
                        acc.append(TranscriptWord(
                            text: text,
                            start: range.start.seconds,
                            end: range.end.seconds,
                            confidence: 1))
                        if totalSeconds > 0 {
                            progress(min(1, range.end.seconds / totalSeconds))
                        }
                    } else {
                        acc.append(TranscriptWord(text: text, start: -1, end: -1, confidence: 1))
                    }
                }
            }
            return acc
        }()

        if let last = try await analyzer.analyzeSequence(from: audioFile) {
            try await analyzer.finalizeAndFinish(through: last)
        }
        return try await collected
    }
}
