import XCTest
@testable import NepNep

final class UsageTrackerTests: XCTestCase {

    // 초 → 시간 표시 반올림 (.0 생략)
    func testHoursTextRounding() {
        XCTAssertEqual(UsageTracker.hoursText(seconds: 0), "0시간")
        XCTAssertEqual(UsageTracker.hoursText(seconds: 1800), "0.5시간")
        XCTAssertEqual(UsageTracker.hoursText(seconds: 3600), "1시간")
        XCTAssertEqual(UsageTracker.hoursText(seconds: 5400), "1.5시간")
        XCTAssertEqual(UsageTracker.hoursText(seconds: 72_000), "20시간")
        // 30분 회의(0.5h) 표시, 사소한 초 단위는 한 자리로 반올림
        XCTAssertEqual(UsageTracker.hoursText(seconds: 1860), "0.5시간")
    }

    func testUsageText() {
        XCTAssertEqual(UsageTracker.usageText(usedSeconds: 0), "0시간 / 20시간")
        XCTAssertEqual(UsageTracker.usageText(usedSeconds: 1800), "0.5시간 / 20시간")
    }

    // 월 경계 키 생성 (UTC yyyy-MM — 서버 KV 키 규칙과 동일)
    func testMonthKeyAtBoundary() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!

        let endOfAugust = utc.date(from: DateComponents(
            year: 2026, month: 8, day: 31, hour: 23, minute: 59, second: 59))!
        XCTAssertEqual(UsageTracker.monthKey(for: endOfAugust), "2026-08")

        let startOfSeptember = endOfAugust.addingTimeInterval(1)
        XCTAssertEqual(UsageTracker.monthKey(for: startOfSeptember), "2026-09")
    }

    // 잔여 계산 — 음수 없음
    func testRemainingSeconds() {
        XCTAssertEqual(UsageTracker.remainingSeconds(usedSeconds: 0), 72_000)
        XCTAssertEqual(UsageTracker.remainingSeconds(usedSeconds: 71_000), 1_000)
        XCTAssertEqual(UsageTracker.remainingSeconds(usedSeconds: 80_000), 0)
    }
}
