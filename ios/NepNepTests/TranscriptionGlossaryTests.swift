import XCTest
@testable import NepNep

/// 전사 맞춤 어휘 파싱 (#21 후속)
final class TranscriptionGlossaryTests: XCTestCase {

    func testParseAcceptsNewlinesAndCommas() {
        let terms = TranscriptionGlossary.parse("레포지토리\n컨텍스트, 페르소나\n\nDB")
        XCTAssertEqual(terms, ["레포지토리", "컨텍스트", "페르소나", "DB"])
    }

    func testParseTrimsAndDropsBlanks() {
        let terms = TranscriptionGlossary.parse("  넵넵  ,,\n   \n 김택현 ")
        XCTAssertEqual(terms, ["넵넵", "김택현"])
    }

    /// 대소문자만 다른 중복은 힌트로서 값이 없다 — 첫 표기를 남긴다
    func testParseDeduplicatesIgnoringCase() {
        let terms = TranscriptionGlossary.parse("SwiftData, swiftdata, SwiftUI")
        XCTAssertEqual(terms, ["SwiftData", "SwiftUI"])
    }

    /// 문장을 통째로 붙여 넣으면 힌트가 아니라 잡음이 된다
    func testParseDropsOverlongTerms() {
        let long = String(repeating: "가", count: TranscriptionGlossary.maxTermLength + 1)
        XCTAssertEqual(TranscriptionGlossary.parse("정상어,\(long)"), ["정상어"])
    }

    func testParseCapsAtMaxTerms() {
        let text = (0..<(TranscriptionGlossary.maxTerms + 20))
            .map { "용어\($0)" }
            .joined(separator: "\n")
        let terms = TranscriptionGlossary.parse(text)
        XCTAssertEqual(terms.count, TranscriptionGlossary.maxTerms)
        XCTAssertEqual(terms.first, "용어0")
    }

    func testParseEmptyTextYieldsNoTerms() {
        XCTAssertTrue(TranscriptionGlossary.parse("").isEmpty)
        XCTAssertTrue(TranscriptionGlossary.parse("  \n , \n ").isEmpty)
    }
}
