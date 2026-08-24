import AVFoundation
import Speech

/// 녹음 중 라이브 자막용 스트리밍 전사기 (PRD F2-4 예외)
///
/// 종료 후 일괄 전사(`SpeechTranscriberEngine`)와는 완전히 별개다. 이쪽은
/// `.volatileResults`를 켜서 말하는 도중에도 추정 텍스트를 받고, 결과는 화면에만
/// 쓰고 버린다. 저장도, 화자분리도, 타임스탬프 병합도 하지 않는다.
///
/// 녹음 안정성이 항상 우선이다. 여기서 나는 실패는 전부 조용히 삼킨다 — 에셋이
/// 없거나 분석기가 죽으면 자막만 멎고 녹음은 그대로 간다. 사용자에게 알럿을
/// 띄우지 않는 것도 같은 이유다. 자막은 어디까지나 미리보기다.
@MainActor
final class LiveTranscriber {
    /// 라이브 자막 켬/끔 (설정 > 기본값). 배터리를 더 쓰는 기능이라 끌 수 있게 뒀다 (D6).
    enum Setting {
        static let storageKey = "recording.liveCaption"
        /// 기본은 켬 — 값이 아직 없으면 처음 실행이다
        static var isEnabled: Bool {
            UserDefaults.standard.object(forKey: storageKey) as? Bool ?? true
        }
    }

    enum Update {
        case pending(String)
        case final(String)
    }

    /// 오디오 탭 스레드가 직접 밀어 넣는 통로. `Continuation`은 Sendable이라
    /// 메인 액터로 홉 없이 yield할 수 있다 — 탭 콜백을 붙잡고 있으면 녹음이
    /// 끊기므로 이 경로에는 await이 하나도 없어야 한다.
    private nonisolated let sink: AsyncStream<AnalyzerInput>.Continuation
    private let stream: AsyncStream<AnalyzerInput>

    /// 일시정지 중 공급 차단. 탭 스레드에서 읽으므로 락 없이 두되, 한 버퍼쯤
    /// 늦게 반영돼도 자막이 반 초 이어질 뿐이라 문제가 되지 않는다.
    private nonisolated(unsafe) var isFeeding = false

    /// 캡처 포맷과 전사기 선호 포맷이 다를 때만 만든다. 실측으로는 둘 다
    /// 16kHz mono Int16이라 보통 nil로 남는다. 탭 스레드에서만 쓰므로 락은 없다.
    private nonisolated(unsafe) var converter: AVAudioConverter?

    private var analyzer: SpeechAnalyzer?
    private var results: Task<Void, Never>?

    /// 분석기가 실제로 돌고 있는지. 에셋이 없으면 false로 남고 화면은 자막 영역을 감춘다.
    private(set) var isActive = false

    init() {
        let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        self.stream = stream
        sink = continuation
    }

    /// 실시간 전사기 — 배치 경로의 `makeTranscriber()`와 옵션이 다르므로 따로 만든다.
    /// `.volatileResults`가 켜져야 말하는 도중에도 추정 텍스트가 흘러나온다.
    /// 타임스탬프·신뢰도는 화면에 쓸 데가 없어 요청하지 않는다 — 그만큼 가볍다.
    private static func makeTranscriber() -> SpeechTranscriber {
        SpeechTranscriber(locale: Locale(identifier: "ko-KR"),
                          transcriptionOptions: [],
                          reportingOptions: [.volatileResults],
                          attributeOptions: [])
    }

    /// 분석기를 띄운다. 실패하면 조용히 비활성으로 남는다.
    /// - Parameters:
    ///   - sourceFormat: 호출부가 먹여 줄 버퍼의 포맷. 전사기가 원하는 포맷과
    ///     다르면 여기서 전용 변환기를 만든다 — 캡처·저장 포맷은 건드리지 않는다.
    ///   - onUpdate: 확정/미확정 텍스트가 올 때마다 메인 액터에서 호출된다.
    func start(sourceFormat: AVAudioFormat?,
               onUpdate: @escaping @MainActor (Update) -> Void) async {
        guard Setting.isEnabled, !isActive else { return }

        let transcriber = Self.makeTranscriber()
        // 에셋이 없으면 여기서 접는다. 녹음 중에 수백 MB를 받게 할 수는 없다 —
        // 일괄 전사 경로가 온보딩에서 이미 받아 두는 물건이다.
        do {
            let pending = try await AssetInventory.assetInstallationRequest(supporting: [transcriber])
            guard pending == nil else { return }
        } catch {
            return
        }

        if let sourceFormat,
           let wanted = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]),
           wanted != sourceFormat {
            converter = AVAudioConverter(from: sourceFormat, to: wanted)
        }

        // 맞춤 어휘(contextualStrings)는 싣지 않는다 — 실측 결과 전사에 아무 영향이
        // 없었다. 근거는 `TranscriptionGlossary` 주석에 적어 뒀다.
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        do {
            try await analyzer.start(inputSequence: stream)
        } catch {
            return
        }
        self.analyzer = analyzer
        isActive = true
        isFeeding = true

        results = Task { @MainActor in
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    onUpdate(result.isFinal ? .final(text) : .pending(text))
                }
            } catch {
                // 자막만 멎는다. 녹음은 계속 간다.
                self.isActive = false
                self.isFeeding = false
            }
        }
    }

    /// 오디오 탭 스레드에서 호출된다
    nonisolated func feed(_ buffer: AVAudioPCMBuffer) {
        guard isFeeding else { return }
        guard let converter else {
            sink.yield(AnalyzerInput(buffer: buffer))
            return
        }
        let ratio = converter.outputFormat.sampleRate / converter.inputFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let out = AVAudioPCMBuffer(pcmFormat: converter.outputFormat,
                                         frameCapacity: capacity) else { return }
        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed {
                status.pointee = .noDataNow
                return nil
            }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        if error == nil, out.frameLength > 0 {
            sink.yield(AnalyzerInput(buffer: out))
        }
    }

    func pause() { isFeeding = false }

    func resume() { isFeeding = isActive }

    /// 녹음이 끝났다 — 스트림을 닫고 분석기를 정리한다
    func finish() async {
        isFeeding = false
        guard isActive else { return }
        isActive = false
        sink.finish()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        results?.cancel()
        results = nil
        analyzer = nil
        converter = nil
    }
}
