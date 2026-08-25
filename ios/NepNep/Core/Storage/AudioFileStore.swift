import Foundation

/// 파일 경로 규약 (02-m1 §2)
/// Application Support/audio/<meetingID>/
///  ├ chunk-000.caf …   녹음 중 5분 단위
///  ├ recording.caf     정지 시 병합본 (파이프라인 입력)
///  └ recording.m4a     처리 완료 후 트랜스코드본
enum AudioFileStore {
    /// 녹음이 사는 곳. 문서 폴더가 아니다.
    ///
    /// engines.yml을 파일 앱에서 고칠 수 있게 문서 폴더를 열어 뒀는데
    /// (UIFileSharingEnabled), 녹음이 거기 있으면 회의 오디오가 통째로 파일 앱에
    /// 같이 보인다. 지원 폴더는 열리지 않으므로 녹음은 이쪽에 둔다.
    static var container: URL {
        let url = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        // 지원 폴더는 문서 폴더와 달리 앱 설치 시점에 만들어져 있지 않다.
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var root: URL {
        container.appendingPathComponent("audio", isDirectory: true)
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

    /// 문서 폴더에 남아 있던 녹음을 지원 폴더로 옮긴다 (실행마다 1회, 앱 시작 직후).
    ///
    /// 파일 앱을 열기 전에 녹음하던 사람들의 파일이 문서 폴더에 있다. 그대로 두면
    /// 회의 오디오가 파일 앱에 보인다.
    static func migrateFromDocumentsIfNeeded() {
        let documents = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
        migrate(from: documents, to: container)
    }

    /// 회의 폴더를 하나씩 옮긴다.
    ///
    /// 통째로 옮기지 않는 이유는 중간에 실패해도 남은 것만 다음 실행에서 이어
    /// 옮기게 하기 위해서다. 목적지에 같은 이름이 이미 있으면 건드리지 않는다 —
    /// 새로 녹음한 쪽을 옛것으로 덮어쓰는 편이 훨씬 나쁘다.
    static func migrate(from documents: URL, to container: URL) {
        let fm = FileManager.default
        for name in ["audio", "watch-inbox"] {
            let old = documents.appendingPathComponent(name, isDirectory: true)
            guard let entries = try? fm.contentsOfDirectory(
                at: old, includingPropertiesForKeys: nil) else { continue }

            let new = container.appendingPathComponent(name, isDirectory: true)
            try? fm.createDirectory(at: new, withIntermediateDirectories: true)
            for entry in entries {
                let destination = new.appendingPathComponent(entry.lastPathComponent)
                guard !fm.fileExists(atPath: destination.path) else { continue }
                try? fm.moveItem(at: entry, to: destination)
            }
            // 다 옮겼을 때만 빈 껍데기를 치운다. 남은 게 있으면 그대로 둔다.
            let leftovers = (try? fm.contentsOfDirectory(
                at: old, includingPropertiesForKeys: nil)) ?? []
            if leftovers.isEmpty { try? fm.removeItem(at: old) }
        }
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
