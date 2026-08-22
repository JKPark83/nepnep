import XCTest
@testable import NepNep

final class TranscriptChunkerTests: XCTestCase {
    /// 한도 내 줄들은 하나의 청크로 합쳐지고, 줄 중간은 절대 자르지 않는다
    func testPacksLinesWithoutCutting() {
        let lines = ["화자 1: 안녕하세요", "화자 2: 반갑습니다", "화자 1: 시작할까요"]
        let chunks = TranscriptChunker.chunk(lines, limit: 100)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0], lines.joined(separator: "\n"))
    }

    /// 한도를 넘기면 줄 경계에서만 나뉜다
    func testSplitsAtLineBoundary() {
        let lines = [String(repeating: "가", count: 60),
                     String(repeating: "나", count: 60),
                     String(repeating: "다", count: 60)]
        let chunks = TranscriptChunker.chunk(lines, limit: 130)
        XCTAssertEqual(chunks.count, 2)
        XCTAssertEqual(chunks[0], lines[0] + "\n" + lines[1])
        XCTAssertEqual(chunks[1], lines[2])
    }

    /// 한 줄 자체가 한도를 넘으면 문장 부호 기준으로 분할한다
    func testOversizedLineSplitsBySentence() {
        let long = String(repeating: "가", count: 50) + ". "
            + String(repeating: "나", count: 50) + "!"
        let chunks = TranscriptChunker.chunk([long], limit: 60)
        XCTAssertEqual(chunks.count, 2)
        XCTAssertTrue(chunks[0].hasSuffix("."))
        XCTAssertTrue(chunks[1].hasSuffix("!"))
    }

    /// 구분자 없는 초장문도 문자 단위로 강제 분할되어 어떤 청크도 한도를 넘지 않는다
    func testDelimiterlessLongLineHardSplit() {
        let long = String(repeating: "가", count: 250)
        let chunks = TranscriptChunker.chunk([long], limit: 100)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 100 })
        XCTAssertEqual(chunks.map(\.count).reduce(0, +), 250)
    }

    /// 빈 입력 → 빈 결과
    func testEmptyInput() {
        XCTAssertTrue(TranscriptChunker.chunk([]).isEmpty)
        XCTAssertTrue(TranscriptChunker.chunk(["", "  "]).isEmpty)
    }

    /// 청크를 이어 붙이면 원문 순서가 유지된다
    func testOrderPreserved() {
        let lines = (1...20).map { "화자 \($0 % 3 + 1): \($0)번째 발화입니다" }
        let chunks = TranscriptChunker.chunk(lines, limit: 80)
        let rejoined = chunks.joined(separator: "\n")
        XCTAssertEqual(rejoined, lines.joined(separator: "\n"))
    }
}
