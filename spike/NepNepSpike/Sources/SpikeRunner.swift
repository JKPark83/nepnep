import AVFoundation
import FluidAudio
import Speech
import UIKit
import WhisperKit

enum SpikeEngine: String, CaseIterable, Identifiable, Codable {
    case apple = "SpeechTranscriber"
    case whisperTurbo = "Whisper turbo"
    case whisperLarge = "Whisper large"

    var id: String { rawValue }

    var whisperVariant: String? {
        switch self {
        case .apple: return nil
        case .whisperTurbo: return "large-v3-v20240930_turbo_632MB"
        case .whisperLarge: return "large-v3-v20240930_626MB"
        }
    }
}

struct SpikeWord: Codable {
    let text: String
    let start: TimeInterval
    let end: TimeInterval
}

struct SpikeSegment: Codable {
    let speaker: String
    let start: TimeInterval
    let end: TimeInterval
}

struct SpikeResult: Codable {
    let file: String
    let engine: String
    let transcribeSec: Double
    let diarizeSec: Double
    let thermalAfterTranscribe: String
    let thermalAfterDiarize: String
    let batteryStart: Float
    let batteryEnd: Float
    let text: String
    let words: [SpikeWord]
    let segments: [SpikeSegment]
    let ranAt: Date
}

@Observable
final class SpikeRunner {
    var statusLine = "대기 중"
    var isRunning = false
    var lastResult: SpikeResult?
    var lastError: String?

    func run(url: URL, engine: SpikeEngine) async {
        isRunning = true
        lastError = nil
        defer { isRunning = false }

        UIDevice.current.isBatteryMonitoringEnabled = true
        let batteryStart = UIDevice.current.batteryLevel
        let clock = ContinuousClock()

        do {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            // 1. 전사
            statusLine = "전사 중 (\(engine.rawValue))…"
            var words: [SpikeWord] = []
            let transcribeStart = clock.now
            if let variant = engine.whisperVariant {
                words = try await transcribeWithWhisper(url: url, variant: variant)
            } else {
                words = try await transcribeWithApple(url: url)
            }
            let transcribeSec = seconds(clock.now - transcribeStart)
            let thermal1 = thermalName()

            // 2. 화자분리
            statusLine = "화자분리 중 (FluidAudio)…"
            let diarizeStart = clock.now
            let segments = try await diarize(url: url)
            let diarizeSec = seconds(clock.now - diarizeStart)
            let thermal2 = thermalName()

            lastResult = SpikeResult(
                file: url.lastPathComponent,
                engine: engine.rawValue,
                transcribeSec: transcribeSec,
                diarizeSec: diarizeSec,
                thermalAfterTranscribe: thermal1,
                thermalAfterDiarize: thermal2,
                batteryStart: batteryStart,
                batteryEnd: UIDevice.current.batteryLevel,
                text: words.map(\.text).joined(),
                words: words,
                segments: segments,
                ranAt: Date())
            statusLine = "완료 — 전사 \(Int(transcribeSec))s · 화자분리 \(Int(diarizeSec))s"
        } catch {
            lastError = "\(error)"
            statusLine = "실패"
        }
    }

    // MARK: - SpeechTranscriber (계획서 01 §3)

    private func transcribeWithApple(url: URL) async throws -> [SpikeWord] {
        let transcriber = SpeechTranscriber(
            locale: Locale(identifier: "ko-KR"),
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [.audioTimeRange])

        if let req = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            statusLine = "언어 에셋 다운로드 중…"
            try await req.downloadAndInstall()
            statusLine = "전사 중 (SpeechTranscriber)…"
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        async let collected: [SpikeWord] = {
            var acc: [SpikeWord] = []
            for try await result in transcriber.results where result.isFinal {
                for run in result.text.runs {
                    let text = String(result.text[run.range].characters)
                    if let range = run.audioTimeRange {
                        acc.append(SpikeWord(
                            text: text,
                            start: range.start.seconds,
                            end: range.end.seconds))
                    } else {
                        acc.append(SpikeWord(text: text, start: -1, end: -1))
                    }
                }
            }
            return acc
        }()

        let audioFile = try AVAudioFile(forReading: url)
        if let last = try await analyzer.analyzeSequence(from: audioFile) {
            try await analyzer.finalizeAndFinish(through: last)
        }
        return try await collected
    }

    // MARK: - WhisperKit (계획서 01 §4)

    private func transcribeWithWhisper(url: URL, variant: String) async throws -> [SpikeWord] {
        statusLine = "Whisper 모델 준비 중 (\(variant))…"
        let pipe = try await WhisperKit(WhisperKitConfig(model: variant))
        statusLine = "전사 중 (WhisperKit)…"
        let opts = DecodingOptions(language: "ko", withoutTimestamps: false, wordTimestamps: true)
        let results = try await pipe.transcribe(audioPath: url.path, decodeOptions: opts)
        var words: [SpikeWord] = []
        for result in results {
            for seg in result.segments {
                if let wordTimings = seg.words, !wordTimings.isEmpty {
                    for w in wordTimings {
                        words.append(SpikeWord(text: w.word, start: Double(w.start), end: Double(w.end)))
                    }
                } else {
                    words.append(SpikeWord(text: seg.text, start: Double(seg.start), end: Double(seg.end)))
                }
            }
        }
        return words
    }

    // MARK: - FluidAudio (계획서 01 §5)

    private func diarize(url: URL) async throws -> [SpikeSegment] {
        let manager = OfflineDiarizerManager(config: OfflineDiarizerConfig())
        statusLine = "화자분리 모델 준비 중…"
        try await manager.prepareModels()
        statusLine = "화자분리 중 (FluidAudio)…"
        let result = try await manager.process(url)
        return result.segments.map {
            SpikeSegment(
                speaker: $0.speakerId,
                start: TimeInterval($0.startTimeSeconds),
                end: TimeInterval($0.endTimeSeconds))
        }
    }

    // MARK: - 계측 보조

    private func seconds(_ d: Duration) -> Double {
        Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
    }

    private func thermalName() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }
}
