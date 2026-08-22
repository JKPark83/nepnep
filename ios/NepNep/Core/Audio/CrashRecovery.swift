import Foundation
import SwiftData

/// 크래시 복구 (02-m1 §5, F1-4)
/// 녹음 시작 시 activeRecording 기록, 정상 정지 시 삭제.
/// 앱 시작 시 기록이 남아 있으면 청크를 병합해 "복구된 녹음"으로 되살린다.
enum CrashRecovery {
    private static let key = "activeRecording"

    struct ActiveRecording: Codable {
        let meetingID: UUID
        let startedAt: Date
    }

    static func markActive(meetingID: UUID) {
        let record = ActiveRecording(meetingID: meetingID, startedAt: .now)
        UserDefaults.standard.set(try? JSONEncoder().encode(record), forKey: key)
    }

    static func clearActive() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    /// 앱 시작 시 호출. 복구된 Meeting의 ID를 반환한다 (없으면 nil).
    @MainActor
    static func recoverIfNeeded(context: ModelContext) -> UUID? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let record = try? JSONDecoder().decode(ActiveRecording.self, from: data)
        else { return nil }
        defer { clearActive() }

        let meetingID = record.meetingID
        let chunks = AudioFileStore.chunkURLs(meetingID: meetingID)
        let mergedExists = FileManager.default.fileExists(
            atPath: AudioFileStore.mergedCafURL(meetingID: meetingID).path)
        guard !chunks.isEmpty || mergedExists else { return nil }

        guard let mergedURL = try? ChunkedAudioWriter.mergeChunks(meetingID: meetingID)
        else { return nil }

        let descriptor = FetchDescriptor<Meeting>(
            predicate: #Predicate { $0.id == meetingID })
        guard let meeting = try? context.fetch(descriptor).first else { return nil }

        // 병합본 길이로 duration 추정 (Int16 mono 16kHz → 2바이트/샘플)
        let bytes = AudioFileStore.fileSize(at: mergedURL)
        meeting.duration = TimeInterval(bytes) / (2 * ChunkedAudioWriter.sampleRate)
        meeting.audioFileName = "audio/\(meetingID.uuidString)/recording.caf"
        meeting.audioSize = bytes
        meeting.status = .recorded
        try? context.save()
        return meetingID
    }
}
