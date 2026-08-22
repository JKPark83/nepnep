import Foundation

/// 월 클라우드 사용량 조회·표시 (07-m5 §4, F8-3)
/// 실제 누적은 서버 KV — 여기는 표시·잔여 계산 로직과 캐시만.
@MainActor
@Observable
final class UsageTracker {
    static let shared = UsageTracker()
    nonisolated static let monthlyLimitSeconds: TimeInterval = 20 * 3600

    /// 서버 verify 응답으로 갱신되는 이번 달 사용량 (초)
    var usedSeconds: TimeInterval = 0

    var remainingSeconds: TimeInterval {
        Self.remainingSeconds(usedSeconds: usedSeconds)
    }

    /// "0.5시간 / 20시간" — 소수점 한 자리 반올림, .0은 생략
    nonisolated static func usageText(usedSeconds: TimeInterval) -> String {
        "\(hoursText(seconds: usedSeconds)) / \(hoursText(seconds: monthlyLimitSeconds))"
    }

    nonisolated static func hoursText(seconds: TimeInterval) -> String {
        let hours = (seconds / 3600 * 10).rounded() / 10
        if hours == hours.rounded() {
            return "\(Int(hours))시간"
        }
        return "\(hours)시간"
    }

    nonisolated static func remainingSeconds(usedSeconds: TimeInterval) -> TimeInterval {
        max(0, monthlyLimitSeconds - usedSeconds)
    }

    /// 서버 KV 키의 월 구분과 동일한 규칙 (UTC yyyy-MM)
    nonisolated static func monthKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: date)
    }
}
