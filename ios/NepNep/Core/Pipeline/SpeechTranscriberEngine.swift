import AVFoundation
import Speech

/// 기본 엔진 — SpeechAnalyzer/SpeechTranscriber (03-m2 §1, M0 §3 코드 재사용)
struct SpeechTranscriberEngine: TranscriptionEngine {
    let id: EngineID = .speechTranscriber

    private func makeTranscriber() -> SpeechTranscriber {
        // transcriptionConfidence를 켜야 구간별 신뢰도가 실려 온다. 예전에는 1로
        // 박아 넣어서 어디가 잘못 들렸는지 알 길이 없었다 (#21 후속).
        SpeechTranscriber(
            locale: Locale(identifier: "ko-KR"),
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [.audioTimeRange, .transcriptionConfidence])
    }

    /// 전사기가 선호하는 오디오 포맷.
    /// 녹음 캡처를 16kHz에 고정해 둔 게 손해인지 판단하려면 이 값이 필요하다 (#21 후속).
    static func preferredAudioFormat() async -> AVAudioFormat? {
        await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [SpeechTranscriberEngine().makeTranscriber()])
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

        // 맞춤 어휘(AnalysisContext.contextualStrings)는 여기 실어 봤자 소용이 없다.
        // 실측 결과 setContext든 생성자 인자든 결과가 바이트 단위로 같았고, ko-KR뿐
        // 아니라 en-US에서도 그랬다. 용어집은 요약 프롬프트 쪽으로 옮겼다 (#21 후속).
        let analyzer = SpeechAnalyzer(modules: [transcriber])

        async let collected: [TranscriptWord] = {
            var acc: [TranscriptWord] = []
            for try await result in transcriber.results where result.isFinal {
                for run in result.text.runs {
                    let text = String(result.text[run.range].characters)
                    // 신뢰도를 안 주는 런도 있다. 그때는 깎지 않고 1로 둔다.
                    let confidence = run.transcriptionConfidence ?? 1
                    if let range = run.audioTimeRange {
                        acc.append(TranscriptWord(
                            text: text,
                            start: range.start.seconds,
                            end: range.end.seconds,
                            confidence: confidence))
                        if totalSeconds > 0 {
                            progress(min(1, range.end.seconds / totalSeconds))
                        }
                    } else {
                        acc.append(TranscriptWord(text: text, start: -1, end: -1,
                                                  confidence: confidence))
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
