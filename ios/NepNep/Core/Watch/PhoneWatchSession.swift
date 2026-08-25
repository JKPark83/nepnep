import Foundation
import SwiftData
import WatchConnectivity

/// 아이폰 쪽 WatchConnectivity 엔드포인트 (이슈 #15 §4·§5).
///
/// 워치가 보낸 오디오를 받아 파이프라인에 태우고, 반대로 최근 회의 목록을 워치에 밀어준다.
/// 델리게이트 콜백은 백그라운드 큐로 들어오므로 SwiftData를 만지는 일은 전부 MainActor로 넘긴다.
final class PhoneWatchSession: NSObject {
    static let shared = PhoneWatchSession()

    /// `NepNepApp.init`에서 주입한다. 워치가 파일을 보내면 앱이 UI 없이 깨어날 수 있는데,
    /// 그때도 컨텍스트가 준비돼 있어야 회의를 만들 수 있다.
    @MainActor var modelContext: ModelContext?

    private override init() { super.init() }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - 아이폰 → 워치

    /// 최근 회의 목록과 기본 회의 유형을 통째로 덮어쓴다.
    /// application context는 최신 1건만 남으므로 자주 불러도 큐가 쌓이지 않는다.
    @MainActor
    func pushContext() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated,
              session.isPaired,
              session.isWatchAppInstalled,
              let context = modelContext else { return }

        let payload = WatchContextPayload(
            rows: Self.rows(from: context),
            defaultTypeRaw: MeetingType.defaultType.rawValue)
        try? session.updateApplicationContext(
            WatchPayload.encode(payload, key: WatchPayload.contextKey))
    }

    @MainActor
    private static func rows(from context: ModelContext) -> [WatchMeetingRow] {
        // 녹음 중인 회의는 아이폰 홈에서도 감추므로 워치에도 내리지 않는다
        let recordingRaw = MeetingStatus.recording.rawValue
        var descriptor = FetchDescriptor<Meeting>(
            predicate: #Predicate { $0.statusRaw != recordingRaw },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = WatchPayload.maxRows

        return ((try? context.fetch(descriptor)) ?? []).map { meeting in
            WatchMeetingRow(
                id: meeting.id,
                title: WatchPayload.truncated(meeting.title,
                                              limit: WatchPayload.maxTitleLength),
                metaText: [MeetingDateFormat.relative(meeting.createdAt),
                           MeetingDateFormat.duration(meeting.duration),
                           meeting.type.displayName].joined(separator: " · "),
                statusText: meeting.status.watchDisplayText,
                oneLiner: WatchPayload.truncated(meeting.summary?.oneLiner ?? "",
                                                 limit: WatchPayload.maxOneLinerLength))
        }
    }
}

// MARK: - WCSessionDelegate

extension PhoneWatchSession: WCSessionDelegate {
    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        Task { @MainActor in pushContext() }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    /// 사용자가 페어링된 워치를 바꾸면 세션이 내려간다 — 새 워치로 다시 붙인다.
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    /// 워치 앱을 뒤늦게 설치했을 때 목록이 비어 있지 않도록
    func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in pushContext() }
    }

    /// 자리표시자 — 녹음이 끝난 직후 도착한다. 오디오 파일보다 먼저 올 수도, 늦게 올 수도 있다.
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let envelope = decodeEnvelope(from: userInfo) else { return }
        Task { @MainActor in WatchIngest.upsertPlaceholder(envelope) }
    }

    /// 실제 오디오. **이 메서드가 반환하는 순간 시스템이 원본을 지운다** —
    /// 비동기로 넘기기 전에 여기서 동기적으로 우리 영역으로 옮겨야 한다.
    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard let envelope = decodeEnvelope(from: file.metadata ?? [:]),
              let staged = try? WatchInbox.stage(file.fileURL, envelope: envelope)
        else { return }
        Task { @MainActor in
            await WatchIngest.ingest(envelope: envelope, stagedAudio: staged)
        }
    }

    /// 워치 앱만 새 버전으로 올라간 경우를 걸러낸다 — 모르는 형식을 반쯤 해석하지 않는다.
    private func decodeEnvelope(from dictionary: [String: Any]) -> WatchRecordingEnvelope? {
        guard let envelope = WatchPayload.decode(WatchRecordingEnvelope.self,
                                                 key: WatchPayload.envelopeKey,
                                                 from: dictionary),
              envelope.version <= WatchRecordingEnvelope.currentVersion
        else { return nil }
        return envelope
    }
}

/// 워치에서 막 도착한 파일을 잠시 두는 곳. 디코드가 끝나면 지운다.
enum WatchInbox {
    static var directory: URL {
        // 녹음과 같은 자리에 둔다 — 문서 폴더는 파일 앱에 열려 있다
        AudioFileStore.container.appendingPathComponent("watch-inbox", isDirectory: true)
    }

    static func stage(_ source: URL, envelope: WatchRecordingEnvelope) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(
            "\(envelope.meetingID.uuidString).\(envelope.audioFormat)")
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }
}
