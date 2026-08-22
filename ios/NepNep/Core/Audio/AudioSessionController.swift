import AVFoundation

/// 오디오 세션 설정·인터럽트 알림 구독 (02-m1 §3)
final class AudioSessionController {
    enum InterruptionEvent {
        case began
        case ended(shouldResume: Bool)
    }

    var onInterruption: ((InterruptionEvent) -> Void)?

    private var observer: NSObjectProtocol?

    func activate() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetoothHFP])
        try session.setActive(true)

        observer = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session, queue: .main) { [weak self] note in
                self?.handleInterruption(note)
            }
    }

    func deactivate() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func handleInterruption(_ note: Notification) {
        guard let info = note.userInfo,
              let typeRaw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeRaw)
        else { return }

        switch type {
        case .began:
            onInterruption?(.began)
        case .ended:
            let optionsRaw = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
            onInterruption?(.ended(shouldResume: options.contains(.shouldResume)))
        @unknown default:
            break
        }
    }
}
