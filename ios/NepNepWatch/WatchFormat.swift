import Foundation

/// 워치에서만 쓰는 표시 포맷.
///
/// 회의 목록 문구는 아이폰이 이미 만들어 내려주므로(`WatchMeetingRow.metaText`) 여기서
/// 다룰 일이 없다. 아이폰이 아직 모르는 값 — 녹음 중 경과 시간과 전송 대기 항목 — 만 맡는다.
enum WatchFormat {
    /// "5:07" / "1:02:30"
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(max(seconds, 0).rounded())
        let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60)
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
