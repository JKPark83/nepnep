import XCTest
@testable import NepNep

/// 라이브 자막 누적기 (녹음 중 미리보기)
final class LiveTranscriptBufferTests: XCTestCase {

    func testCommitAccumulates() {
        var buffer = LiveTranscriptBuffer()
        buffer.commit("안녕하세요")
        buffer.commit("오늘 회의를 시작하겠습니다")
        XCTAssertEqual(buffer.finalized, "안녕하세요 오늘 회의를 시작하겠습니다")
        XCTAssertEqual(buffer.display, "안녕하세요 오늘 회의를 시작하겠습니다")
    }

    /// 미확정 꼬리는 쌓이면 안 된다 — 같은 말이 여러 겹으로 보이던 원인
    func testPendingReplacesInsteadOfAccumulating() {
        var buffer = LiveTranscriptBuffer()
        buffer.setPending("오늘")
        buffer.setPending("오늘 회의")
        buffer.setPending("오늘 회의를")
        XCTAssertEqual(buffer.pending, "오늘 회의를")
        XCTAssertEqual(buffer.display, "오늘 회의를")
    }

    /// 확정이 오면 그 구간을 추정하던 꼬리는 사라져야 한다
    func testCommitClearsPending() {
        var buffer = LiveTranscriptBuffer()
        buffer.setPending("오늘 회의르")
        buffer.commit("오늘 회의를 시작합니다")
        XCTAssertEqual(buffer.pending, "")
        XCTAssertEqual(buffer.display, "오늘 회의를 시작합니다")
    }

    func testDisplayIsFinalizedPlusPending() {
        var buffer = LiveTranscriptBuffer()
        buffer.commit("첫 문장입니다")
        buffer.setPending("두 번째")
        XCTAssertEqual(buffer.display, "첫 문장입니다 두 번째")
    }

    /// 전사기가 조각에 공백을 붙여 주든 말든 결과가 같아야 한다
    func testFragmentsAreSpacedExactlyOnce() {
        var buffer = LiveTranscriptBuffer()
        buffer.commit("  안녕하세요  ")
        buffer.commit("반갑습니다")
        XCTAssertEqual(buffer.finalized, "안녕하세요 반갑습니다")
    }

    func testBlankInputIsIgnored() {
        var buffer = LiveTranscriptBuffer()
        buffer.commit("안녕하세요")
        buffer.commit("   ")
        buffer.setPending("\n")
        XCTAssertEqual(buffer.display, "안녕하세요")
    }

    /// 긴 녹음에서 메모리가 무한정 늘지 않도록 앞에서부터 버린다
    func testTrimsToLimitKeepingTheTail() {
        var buffer = LiveTranscriptBuffer()
        for _ in 0..<50 { buffer.commit("가나다라마", limit: 20) }
        XCTAssertEqual(buffer.finalized.count, 20)
        XCTAssertTrue(buffer.finalized.hasSuffix("가나다라마"))
    }

    func testResetClearsEverything() {
        var buffer = LiveTranscriptBuffer()
        buffer.commit("안녕하세요")
        buffer.setPending("반갑")
        buffer.reset()
        XCTAssertTrue(buffer.isEmpty)
        XCTAssertEqual(buffer.display, "")
    }
}
