import Foundation
import SwiftData

/// 워치가 보낸 회의를 아이폰 저장소에 앉히고 파이프라인에 태운다 (이슈 #15 §4).
///
/// 자리표시자와 오디오가 어느 순서로 도착해도 같은 회의로 합쳐져야 하므로,
/// 두 경로 모두 `meetingID` 기준 upsert를 거친다. 회의 `id`는 워치가 만들어 고정한 값이다.
@MainActor
enum WatchIngest {
    /// 오디오보다 먼저 도착한 자리표시자 — 목록에 "전송 대기 중"으로 먼저 뜬다.
    static func upsertPlaceholder(_ envelope: WatchRecordingEnvelope) {
        guard let context = PhoneWatchSession.shared.modelContext else { return }
        _ = upsert(envelope, context: context)
    }

    static func ingest(envelope: WatchRecordingEnvelope, stagedAudio: URL) async {
        guard let context = PhoneWatchSession.shared.modelContext else { return }
        let meeting = upsert(envelope, context: context)

        // 이미 처리 중이거나 끝난 회의면 같은 파일이 두 번 온 것이다 — 다시 태우지 않는다.
        guard meeting.status == .pendingTransfer else {
            try? FileManager.default.removeItem(at: stagedAudio)
            return
        }

        let cafURL = AudioFileStore.mergedCafURL(meetingID: meeting.id)
        do {
            try AudioFileStore.createDirectory(for: meeting.id)
            // 60분짜리 디코드가 메인 스레드를 잡으면 UI가 멈춘다
            try await Task.detached(priority: .userInitiated) {
                try AudioTranscoder.decodeToPipelineCAF(source: stagedAudio, to: cafURL)
            }.value
        } catch {
            meeting.status = .failed
            meeting.failureReasonRaw = ProcessingFailureReason.engineError.rawValue
            try? context.save()
            PhoneWatchSession.shared.pushContext()
            return
        }
        try? FileManager.default.removeItem(at: stagedAudio)

        meeting.audioFileName = "audio/\(meeting.id.uuidString)/recording.caf"
        meeting.audioSize = AudioFileStore.fileSize(at: cafURL)
        try? context.save()

        // 여기서부터는 아이폰 녹음과 완전히 같은 경로다 (RecordingSession.stop과 동일)
        ProcessingCoordinator.shared.enqueue(meeting: meeting)
    }

    private static func upsert(_ envelope: WatchRecordingEnvelope,
                               context: ModelContext) -> Meeting {
        let id = envelope.meetingID
        let descriptor = FetchDescriptor<Meeting>(predicate: #Predicate { $0.id == id })
        if let existing = try? context.fetch(descriptor).first { return existing }

        // 제목은 워치가 아니라 여기서 붙인다 — 아이폰 녹음과 같은 규칙이어야 하고,
        // 어차피 요약이 끝나면 `Meeting.summaryTitle`로 다시 바뀐다.
        let type = MeetingType(rawValue: envelope.typeRaw) ?? .general
        let meeting = Meeting(id: id,
                              title: Meeting.autoTitle(date: envelope.startedAt),
                              type: type,
                              createdAt: envelope.startedAt)
        meeting.duration = envelope.duration
        meeting.gapRanges = envelope.gapRanges
        meeting.status = .pendingTransfer
        context.insert(meeting)
        try? context.save()
        PhoneWatchSession.shared.pushContext()
        return meeting
    }
}
