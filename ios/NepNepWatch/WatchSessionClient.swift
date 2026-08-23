import Foundation
import Observation
import WatchConnectivity

/// 워치 쪽 WatchConnectivity 엔드포인트 (이슈 #15 §4·§5).
///
/// 전송 대기 목록을 따로 저장하지 않고 `WCSession.outstandingFileTransfers`를 그대로 읽는다.
/// 시스템 큐가 유일한 진실이라 앱이 죽었다 살아나도 어긋나지 않는다.
@MainActor
@Observable
final class WatchSessionClient: NSObject {
    static let shared = WatchSessionClient()

    /// 아이폰이 마지막으로 내려준 목록 + 기본 회의 유형
    private(set) var context: WatchContextPayload = .empty
    /// 아직 아이폰에 도착하지 않은 녹음 (오래된 것부터)
    private(set) var pending: [WatchRecordingEnvelope] = []
    private(set) var isReachable = false

    private override init() { super.init() }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// 녹음 한 건을 아이폰으로 보낸다.
    ///
    /// 자리표시자(userInfo)와 오디오(file)를 따로 보내되 **같은 봉투**를 싣는다.
    /// 두 큐 사이에는 순서 보장이 없지만, 아이폰이 `meetingID`로 합치므로 어느 쪽이 먼저 와도 된다.
    func send(envelope: WatchRecordingEnvelope, audio: URL) {
        let payload = WatchPayload.encode(envelope, key: WatchPayload.envelopeKey)
        let session = WCSession.default
        session.transferUserInfo(payload)
        session.transferFile(audio, metadata: payload)
        refreshPending()
    }

    /// 시스템 큐를 읽어 대기 목록을 다시 만들고, 큐에 없는 오디오 파일은 정리한다.
    func refreshPending() {
        guard WCSession.isSupported() else { return }
        pending = WCSession.default.outstandingFileTransfers.compactMap {
            WatchPayload.decode(WatchRecordingEnvelope.self,
                                key: WatchPayload.envelopeKey,
                                from: $0.file.metadata ?? [:])
        }
        .sorted { $0.startedAt < $1.startedAt }

        var keep = Set(pending.map(\.meetingID))
        // 녹음 중인 파일은 아직 큐에 없다 — 쓸어버리면 안 된다
        if let recording = WatchRecorder.shared.meetingIDInProgress { keep.insert(recording) }
        WatchAudioStore.sweep(keeping: keep)
    }
}

// MARK: - WCSessionDelegate

extension WatchSessionClient: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        let received = session.receivedApplicationContext
        Task { @MainActor in
            apply(received)
            isReachable = session.isReachable
            refreshPending()
        }
    }

    nonisolated func session(_ session: WCSession,
                             didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in apply(applicationContext) }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in
            isReachable = reachable
            refreshPending()
        }
    }

    nonisolated func session(_ session: WCSession,
                             didFinish fileTransfer: WCSessionFileTransfer,
                             error: Error?) {
        let envelope = WatchPayload.decode(WatchRecordingEnvelope.self,
                                           key: WatchPayload.envelopeKey,
                                           from: fileTransfer.file.metadata ?? [:])
        Task { @MainActor in
            // 실패한 전송은 시스템이 다시 시도한다 — 원본을 지우면 복구할 길이 없다.
            if error == nil, let envelope {
                WatchAudioStore.remove(envelope.meetingID)
            }
            refreshPending()
        }
    }

    @MainActor
    private func apply(_ dictionary: [String: Any]) {
        guard let payload = WatchPayload.decode(WatchContextPayload.self,
                                                key: WatchPayload.contextKey,
                                                from: dictionary) else { return }
        context = payload
    }
}
