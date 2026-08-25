import Foundation
import os

/// 요약 실행 진단 (#21)
///
/// 긴 회의에서 요약이 실패해도 흔적이 남지 않아 원인을 알 수 없던 문제를 없애기 위해,
/// map·reduce 각 단계를 OSLog에 남기고 마지막 실행 몇 건은 기기에 저장해
/// 설정 > 요약 진단에서 바로 읽을 수 있게 한다.

/// 요약 한 번의 실행 기록
struct SummaryRunRecord: Codable, Identifiable {
    var id: UUID
    var meetingTitle: String
    var startedAt: Date
    var duration: TimeInterval
    /// "성공" 또는 실패 사유 한 줄
    var outcome: String
    var succeeded: Bool
    /// "+12.3s  map 3/18 완료" 형태의 사람이 읽는 로그
    var events: [String]
    /// 아직 도는 중인 실행. 끝나지 않고 멈춰 버리면 기록이 아예 남지 않아
    /// 어디서 막혔는지 볼 수 없었다 — 진행 중에도 계속 갱신해 둔다 (#21).
    var inProgress = false
}

enum SummaryDiagnostics {
    static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.nepnep.app",
                               category: "summary")

    private static let storageKey = "summaryDiagnosticsRuns"
    /// 최근 실행 5건만 남긴다 — 진단에 그 이상은 필요 없고 UserDefaults를 키울 이유도 없다
    private static let maxRuns = 5

    static var records: [SummaryRunRecord] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([SummaryRunRecord].self, from: data)
        else { return [] }
        return decoded
    }

    /// 같은 id의 기록이 있으면 갈아 끼우고, 없으면 맨 앞에 넣는다.
    /// 진행 중인 실행이 이벤트마다 자기 기록을 갱신하며 쓴다.
    static func upsert(_ record: SummaryRunRecord) {
        var updated = records
        if let index = updated.firstIndex(where: { $0.id == record.id }) {
            updated[index] = record
        } else {
            updated.insert(record, at: 0)
        }
        guard let data = try? JSONEncoder().encode(Array(updated.prefix(maxRuns))) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}

/// 요약 한 번을 따라다니며 이벤트를 모으는 로그.
/// map 루프가 메인 액터 밖에서 도는 구간이 있어 잠금으로 보호한다.
final class SummaryRunLog: @unchecked Sendable {
    private let lock = NSLock()
    private let id = UUID()
    private let meetingTitle: String
    private let startedAt = Date()
    private var events: [String] = []

    init(meetingTitle: String) {
        self.meetingTitle = meetingTitle
        event("요약 시작")
    }

    func event(_ message: String) {
        let stamp = String(format: "+%.1fs", Date().timeIntervalSince(startedAt))
        lock.lock()
        events.append("\(stamp)  \(message)")
        let collected = events
        lock.unlock()
        SummaryDiagnostics.logger.info("[\(self.meetingTitle, privacy: .public)] \(message, privacy: .public)")
        // 이벤트마다 남겨 둬야 끝나지 않고 멈춘 실행도 진단에서 읽을 수 있다 (#21)
        store(outcome: "진행 중", succeeded: false, inProgress: true, events: collected)
    }

    /// 성공/실패 결론을 찍고 기기에 저장한다
    func finish(outcome: String, succeeded: Bool) {
        event(succeeded ? "완료" : "실패 — \(outcome)")
        lock.lock()
        let collected = events
        lock.unlock()
        if succeeded {
            SummaryDiagnostics.logger.info("[\(self.meetingTitle, privacy: .public)] 요약 성공")
        } else {
            SummaryDiagnostics.logger.error("[\(self.meetingTitle, privacy: .public)] 요약 실패: \(outcome, privacy: .public)")
        }
        store(outcome: outcome, succeeded: succeeded, inProgress: false, events: collected)
    }

    private func store(outcome: String, succeeded: Bool,
                       inProgress: Bool, events: [String]) {
        SummaryDiagnostics.upsert(SummaryRunRecord(
            id: id,
            meetingTitle: meetingTitle,
            startedAt: startedAt,
            duration: Date().timeIntervalSince(startedAt),
            outcome: outcome,
            succeeded: succeeded,
            events: events,
            inProgress: inProgress))
    }

    /// 진단·복사용 평문
    static func plainText(_ record: SummaryRunRecord) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ko_KR")
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return ([
            "\(record.meetingTitle) — \(record.succeeded ? "성공" : "실패")",
            "\(fmt.string(from: record.startedAt))  (\(String(format: "%.1f", record.duration))초)",
            record.outcome,
            "",
        ] + record.events).joined(separator: "\n")
    }
}
