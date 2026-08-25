import AVFoundation
import Foundation
import SwiftData
import UIKit

/// 녹음 상태 머신 (02-m1 §4)
/// idle → requestingPermission → recording ⇄ paused(user|interruption)
///      → stopping(청크 병합) → handoff → idle
@MainActor
@Observable
final class RecordingSession {
    static let shared = RecordingSession()

    enum State: Equatable {
        case idle
        case requestingPermission
        case recording
        case pausedByUser
        case pausedByInterruption
        case stopping
    }

    static let maxDuration: TimeInterval = 4 * 3600   // F1-6

    private(set) var state: State = .idle
    private(set) var elapsed: TimeInterval = 0        // 일시정지 구간 제외 누적
    private(set) var levelDB: Float = -160            // 탭 버퍼 RMS→dB
    private(set) var silenceSeconds: TimeInterval = 0 // -50dB 미만 연속 시간
    var currentMeeting: Meeting?
    var errorMessage: String?
    /// 4시간 도달 자동 정지 알림 (F1-6)
    var didAutoStop = false

    /// 녹음 중 라이브 자막 (PRD F2-4 예외). 화면에만 쓰고 정지하면 버린다 —
    /// 저장되는 전사는 지금까지처럼 종료 후 일괄 파이프라인이 만든다.
    private(set) var liveText = LiveTranscriptBuffer()
    /// 자막이 실제로 돌고 있는지. 꺼져 있거나 에셋이 없으면 화면이 자막 영역을 감춘다.
    private(set) var isLiveTranscribing = false

    private let engine = AVAudioEngine()
    private let sessionController = AudioSessionController()
    private var writer: ChunkedAudioWriter?
    private var converter: AVAudioConverter?
    private var live: LiveTranscriber?
    private var ticker: Timer?
    private var lastTickAt: Date?
    private var interruptionBeganAt: TimeInterval?

    var modelContext: ModelContext?

    // MARK: - 시작

    func start(type: MeetingType) async {
        guard state == .idle else { return }
        errorMessage = nil
        didAutoStop = false

        guard AudioFileStore.hasEnoughFreeSpace() else {
            errorMessage = "저장 공간이 부족해요. 공간을 확보한 뒤 다시 시도해 주세요."
            return
        }

        state = .requestingPermission
        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else {
            state = .idle
            errorMessage = "마이크 권한이 필요해요. 설정에서 허용해 주세요."
            return
        }

        let meeting = Meeting(title: Meeting.autoTitle(), type: type)
        modelContext?.insert(meeting)
        try? modelContext?.save()
        currentMeeting = meeting

        do {
            try startEngine(meetingID: meeting.id)
        } catch {
            state = .idle
            // 시작조차 못한 빈 회의는 목록에 남기지 않는다
            currentMeeting = nil
            modelContext?.delete(meeting)
            try? modelContext?.save()
            errorMessage = Self.startFailureMessage(error)
            return
        }

        CrashRecovery.markActive(meetingID: meeting.id)
        elapsed = 0
        silenceSeconds = 0
        state = .recording
        startTicker()
        await startLiveTranscription()
        RecordingLiveActivityController.shared.start(title: meeting.title)
    }

    /// 통화 중 세션 활성화 거부(insufficientPriority) 등 시스템 에러를 한국어 안내로 변환
    private static func startFailureMessage(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == NSOSStatusErrorDomain,
           nsError.code == AVAudioSession.ErrorCode.insufficientPriority.rawValue {
            return "통화 중에는 녹음을 시작할 수 없어요. 통화를 끝낸 뒤 다시 시도해 주세요."
        }
        return "녹음을 시작하지 못했어요: \(error.localizedDescription)"
    }

    private func startEngine(meetingID: UUID) throws {
        try sessionController.activate()
        sessionController.onInterruption = { [weak self] event in
            Task { @MainActor in self?.handleInterruption(event) }
        }

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        // 입력 장치가 없으면 0Hz/0ch — 이 포맷으로 installTap하면 NSException으로 크래시
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw NSError(domain: "RecordingSession", code: 2, userInfo: [
                NSLocalizedDescriptionKey:
                    "마이크 입력을 사용할 수 없어요. 시뮬레이터라면 I/O > Audio Input 설정과 Mac 마이크 권한을 확인해 주세요."])
        }
        let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                         sampleRate: ChunkedAudioWriter.sampleRate,
                                         channels: 1,
                                         interleaved: true)!
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw NSError(domain: "RecordingSession", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "포맷 변환기 생성 실패"])
        }
        self.converter = converter
        let writer = ChunkedAudioWriter(meetingID: meetingID)
        self.writer = writer

        // 라이브 자막기는 탭이 붙기 전에 만들어 둬야 클로저가 잡아 갈 수 있다.
        // 분석기가 뜨기 전까지는 feed()가 조용히 버린다.
        let live = LiveTranscriber()
        self.live = live

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.processTap(buffer: buffer, converter: converter, writer: writer,
                             live: live,
                             ratio: targetFormat.sampleRate / inputFormat.sampleRate)
        }
        try engine.start()
    }

    /// 탭 콜백 (오디오 스레드): RMS 계산 + 16k mono 변환 + 청크 기록 + 라이브 자막 공급
    nonisolated private func processTap(buffer: AVAudioPCMBuffer,
                                        converter: AVAudioConverter,
                                        writer: ChunkedAudioWriter,
                                        live: LiveTranscriber,
                                        ratio: Double) {
        // 레벨 (RMS→dB)
        var db: Float = -160
        if let data = buffer.floatChannelData?[0] {
            let n = Int(buffer.frameLength)
            if n > 0 {
                var sum: Float = 0
                for i in 0..<n { sum += data[i] * data[i] }
                let rms = (sum / Float(n)).squareRoot()
                db = rms > 0 ? 20 * log10(rms) : -160
            }
        }
        Task { @MainActor [weak self] in self?.levelDB = db }

        // 변환 → 기록
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let out = AVAudioPCMBuffer(pcmFormat: converter.outputFormat,
                                         frameCapacity: capacity) else { return }
        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, outStatus in
            if fed {
                outStatus.pointee = .noDataNow
                return nil
            }
            fed = true
            outStatus.pointee = .haveData
            return buffer
        }
        if error == nil, out.frameLength > 0 {
            writer.append(out)
            // 같은 버퍼를 라이브 자막에도 흘린다. 여기서 뭐가 잘못돼도 저장은
            // 이미 끝난 뒤라 녹음에는 영향이 없다.
            live.feed(out)
        }
    }

    // MARK: - 라이브 자막 (PRD F2-4 예외)

    /// 설정에서 껐거나 언어 에셋이 없으면 조용히 비활성으로 남는다 — 알럿은 띄우지 않는다
    private func startLiveTranscription() async {
        guard let live else { return }
        liveText.reset()
        await live.start(sourceFormat: converter?.outputFormat) { [weak self] update in
            guard let self else { return }
            switch update {
            case .pending(let text): liveText.setPending(text)
            case .final(let text): liveText.commit(text)
            }
        }
        isLiveTranscribing = live.isActive
    }

    // MARK: - 일시정지·재개

    func pause() {
        guard state == .recording else { return }
        engine.pause()
        live?.pause()
        state = .pausedByUser
        RecordingLiveActivityController.shared.update(elapsed: elapsed, isPaused: true)
    }

    func resume() {
        guard state == .pausedByUser || state == .pausedByInterruption else { return }
        do {
            try engine.start()
            live?.resume()
            state = .recording
            RecordingLiveActivityController.shared.update(elapsed: elapsed, isPaused: false)
        } catch {
            errorMessage = "재개하지 못했어요: \(error.localizedDescription)"
        }
    }

    private func handleInterruption(_ event: AudioSessionController.InterruptionEvent) {
        switch event {
        case .began:
            guard state == .recording else { return }
            engine.pause()
            live?.pause()
            state = .pausedByInterruption
            interruptionBeganAt = elapsed
            RecordingLiveActivityController.shared.update(elapsed: elapsed, isPaused: true)
        case .ended(let shouldResume):
            guard state == .pausedByInterruption else { return }
            if let began = interruptionBeganAt {
                currentMeeting?.gapRanges.append(GapRange(start: began, end: elapsed))
                interruptionBeganAt = nil
            }
            if shouldResume { resume() }
        }
    }

    // MARK: - 정지

    func stop() {
        guard state == .recording || state == .pausedByUser || state == .pausedByInterruption else { return }
        state = .stopping
        stopTicker()
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        sessionController.deactivate()
        stopLiveTranscription()
        RecordingLiveActivityController.shared.end()

        guard let meeting = currentMeeting else {
            state = .idle
            return
        }

        do {
            let mergedURL = try writer?.finishAndMerge()
                ?? AudioFileStore.mergedCafURL(meetingID: meeting.id)
            meeting.duration = elapsed
            meeting.audioFileName = "audio/\(meeting.id.uuidString)/recording.caf"
            meeting.audioSize = AudioFileStore.fileSize(at: mergedURL)
            try? modelContext?.save()
            CrashRecovery.clearActive()
            // 처리 파이프라인 시작 (03-m2 §4)
            ProcessingCoordinator.shared.enqueue(meeting: meeting)
        } catch {
            errorMessage = "녹음 파일 정리에 실패했어요: \(error.localizedDescription)"
        }

        writer = nil
        converter = nil
        currentMeeting = nil
        state = .idle
    }

    /// 자막 텍스트는 여기서 버린다 — 저장되는 전사는 일괄 파이프라인이 만든다
    private func stopLiveTranscription() {
        let live = self.live
        self.live = nil
        isLiveTranscribing = false
        liveText.reset()
        Task { await live?.finish() }
    }

    // MARK: - 경과 시간

    private func startTicker() {
        lastTickAt = Date()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
        lastTickAt = nil
    }

    private func tick() {
        let now = Date()
        defer { lastTickAt = now }
        guard state == .recording, let last = lastTickAt else { return }
        let dt = now.timeIntervalSince(last)
        elapsed += dt

        // 무음 감지 (1c 노트 2)
        if levelDB < -50 {
            silenceSeconds += dt
        } else {
            silenceSeconds = 0
        }

        // 최대 길이 가드 (F1-6)
        if elapsed >= Self.maxDuration {
            didAutoStop = true
            stop()
        }
    }
}
