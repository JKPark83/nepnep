import Foundation

/// 워치 안의 녹음 파일 위치 (이슈 #15 §3)
/// Documents/recordings/<meetingID>.m4a — 전송이 끝나면 지운다.
enum WatchAudioStore {
    static var directory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("recordings", isDirectory: true)
    }

    static func url(for meetingID: UUID) -> URL {
        directory.appendingPathComponent("\(meetingID.uuidString).m4a")
    }

    static func createDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    static func remove(_ meetingID: UUID) {
        try? FileManager.default.removeItem(at: url(for: meetingID))
    }

    static func fileSize(_ meetingID: UUID) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url(for: meetingID).path)[.size] as? Int64) ?? 0
    }

    /// 아직 전송 큐에 남아 있는 회의를 뺀 나머지 파일을 지운다.
    /// 워치가 강제 종료돼 완료 콜백을 놓친 파일이 영영 남는 걸 막는다.
    static func sweep(keeping ids: Set<UUID>) {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        for url in contents where url.pathExtension == "m4a" {
            let name = url.deletingPathExtension().lastPathComponent
            guard let id = UUID(uuidString: name), ids.contains(id) else {
                try? FileManager.default.removeItem(at: url)
                continue
            }
        }
    }
}
