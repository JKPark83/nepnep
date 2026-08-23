import AVFoundation
import Foundation
import Observation

/// 워치 녹음 (이슈 #15 §3).
///
/// 아이폰의 `RecordingSession`과 달리 AVAudioEngine 탭을 쓰지 않고 `AVAudioRecorder`로
/// 바로 AAC를 만든다. 아이폰과 같은 16kHz mono PCM으로 두면 115MB/h라 워치 저장 공간에도,
/// WCSession 전송에도 무리다. 여기서 32kbps AAC(약 14MB/h)로 줄이고 아이폰이 되돌린다.
@MainActor
@Observable
final class WatchRecorder {
    static let shared = WatchRecorder()

    /// 아이폰은 4시간(`RecordingSession.maxDuration`)이지만 워치는 1시간에서 끊는다.
    /// 배터리·저장 공간도 있지만, 무엇보다 watchOS가 그렇게 오래 앱을 살려 둘지가 불확실하다.
    static let maxDuration: TimeInterval = 60 * 60

    enum State: Equatable {
        case idle
        case requestingPermission
        case recording
        case pausedByInterruption
    }

    private(set) var state: State = .idle
    private(set) var elapsed: TimeInterval = 0
    /// 아직 전송 큐에 들어가지 않은 진행 중인 녹음 — 파일 정리에서 빼내기 위해 필요하다
    private(set) var meetingIDInProgress: UUID?
    /// 알림으로 한 번 띄우고 사라지는 문구 (권한 거부, 인터럽션, 최대 길이 도달)
    var errorMessage: String?

    private var recorder: AVAudioRecorder?
    private var startedAt: Date?
    private var gapRanges: [GapRange] = []
    private var interruptionBeganAt: TimeInterval?
    private var ticker: Timer?
    private var interruptionObserver: NSObjectProtocol?

    /// 아이폰이 처리 완료 후 만드는 m4a와 같은 설정 (`AudioTranscoder.transcode`)
    private static let settings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 16_000,
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 32_000,
    ]

    private init() {}

    // MARK: - 시작

    func start() async {
        guard state == .idle else { return }
        errorMessage = nil

        state = .requestingPermission
        guard await AVAudioApplication.requestRecordPermission() else {
            state = .idle
            errorMessage = "마이크 권한이 필요해요. 워치 설정에서 허용해 주세요."
            return
        }

        let id = UUID()
        do {
            try WatchAudioStore.createDirectory()
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .default)
            try session.setActive(true)

            let recorder = try AVAudioRecorder(url: WatchAudioStore.url(for: id),
                                               settings: Self.settings)
            guard recorder.record() else {
                throw NSError(domain: "WatchRecorder", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "마이크를 사용할 수 없어요."])
            }
            self.recorder = recorder
        } catch {
            state = .idle
            WatchAudioStore.remove(id)
            errorMessage = "녹음을 시작하지 못했어요: \(error.localizedDescription)"
            return
        }

        meetingIDInProgress = id
        startedAt = Date()
        gapRanges = []
        interruptionBeganAt = nil
        elapsed = 0
        state = .recording
        observeInterruptions()
        startTicker()
    }

    // MARK: - 정지 · 전송

    func stop() {
        guard state == .recording || state == .pausedByInterruption else { return }
        stopTicker()
        // 인터럽트 도중에 정지하면 구간이 열린 채로 남는다
        closeOpenGap()

        let duration = recorder?.currentTime ?? elapsed
        recorder?.stop()
        recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false)
        removeInterruptionObserver()

        let id = meetingIDInProgress
        let started = startedAt
        let gaps = gapRanges

        meetingIDInProgress = nil
        startedAt = nil
        gapRanges = []
        interruptionBeganAt = nil
        elapsed = 0
        state = .idle

        guard let id, let started else { return }
        guard WatchAudioStore.fileSize(id) > 0 else {
            WatchAudioStore.remove(id)
            errorMessage = "녹음된 내용이 없어요."
            return
        }

        WatchSessionClient.shared.send(
            envelope: WatchRecordingEnvelope(
                meetingID: id,
                // 아이폰이 내려준 기본 회의 유형을 그대로 되돌려준다. 한 번도 동기화된 적이
                // 없으면 빈 문자열이고, 아이폰이 .general로 해석한다.
                typeRaw: WatchSessionClient.shared.context.defaultTypeRaw,
                startedAt: started,
                duration: max(duration, 0),
                gapRanges: gaps),
            audio: WatchAudioStore.url(for: id))
    }

    // MARK: - 인터럽션

    private func observeInterruptions() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main) { [weak self] note in
                guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
                let optionsRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                Task { @MainActor in
                    self?.handleInterruption(
                        type: type,
                        options: AVAudioSession.InterruptionOptions(rawValue: optionsRaw))
                }
            }
    }

    private func removeInterruptionObserver() {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        interruptionObserver = nil
    }

    private func handleInterruption(type: AVAudioSession.InterruptionType,
                                    options: AVAudioSession.InterruptionOptions) {
        switch type {
        case .began:
            guard state == .recording else { return }
            recorder?.pause()
            interruptionBeganAt = recorder?.currentTime ?? elapsed
            state = .pausedByInterruption
        case .ended:
            guard state == .pausedByInterruption else { return }
            closeOpenGap()
            if options.contains(.shouldResume),
               (try? AVAudioSession.sharedInstance().setActive(true)) != nil,
               recorder?.record() == true {
                state = .recording
                return
            }
            // watchOS는 통화·Siri 인터럽션 뒤 재개가 취약하다. 조용히 멈춰 있는 것보다
            // 여기서 끊고 지금까지 녹음한 것만이라도 아이폰으로 넘기는 편이 낫다.
            stop()
            errorMessage = "녹음이 중단돼 지금까지 녹음한 내용만 보냈어요."
        @unknown default:
            break
        }
    }

    private func closeOpenGap() {
        guard let began = interruptionBeganAt else { return }
        let now = recorder?.currentTime ?? elapsed
        gapRanges.append(GapRange(start: began, end: max(now, began)))
        interruptionBeganAt = nil
    }

    // MARK: - 경과 시간

    private func startTicker() {
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        guard state == .recording, let recorder else { return }
        // AVAudioRecorder가 일시정지 구간을 빼고 세어 준다
        elapsed = recorder.currentTime
        if elapsed >= Self.maxDuration {
            stop()
            errorMessage = "1시간이 다 돼 녹음을 마쳤어요. 아이폰으로 보냈어요."
        }
    }
}
