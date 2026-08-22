import Foundation

/// 파일 경로 규약 (02-m1 §2)
/// Documents/audio/<meetingID>/
///  ├ chunk-000.caf …   녹음 중 5분 단위
///  ├ recording.caf     정지 시 병합본 (파이프라인 입력)
///  └ recording.m4a     처리 완료 후 트랜스코드본
enum AudioFileStore {
    static var root: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("audio", isDirectory: true)
    }

    static func directory(for meetingID: UUID) -> URL {
        root.appendingPathComponent(meetingID.uuidString, isDirectory: true)
    }

    static func chunkURL(meetingID: UUID, index: Int) -> URL {
        directory(for: meetingID)
            .appendingPathComponent(String(format: "chunk-%03d.caf", index))
    }

    static func mergedCafURL(meetingID: UUID) -> URL {
        directory(for: meetingID).appendingPathComponent("recording.caf")
    }

    static func m4aURL(meetingID: UUID) -> URL {
        directory(for: meetingID).appendingPathComponent("recording.m4a")
    }

    static func createDirectory(for meetingID: UUID) throws {
        try FileManager.default.createDirectory(
            at: directory(for: meetingID), withIntermediateDirectories: true)
    }

    static func chunkURLs(meetingID: UUID) -> [URL] {
        let dir = directory(for: meetingID)
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil)) ?? []
        return contents
            .filter { $0.lastPathComponent.hasPrefix("chunk-") && $0.pathExtension == "caf" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func removeDirectory(for meetingID: UUID) {
        try? FileManager.default.removeItem(at: directory(for: meetingID))
    }

    static func fileSize(at url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
    }

    /// 시작 전 여유 공간 체크: 예상 용량(115MB/h × 2h) + 500MB (02-m1 §2)
    static func hasEnoughFreeSpace() -> Bool {
        let required: Int64 = (115 * 2 + 500) * 1_000_000
        guard let values = try? root.deletingLastPathComponent()
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
            let capacity = values.volumeAvailableCapacityForImportantUsage
        else { return true }
        return capacity >= required
    }
}
