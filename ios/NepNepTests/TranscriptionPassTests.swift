import XCTest
@testable import NepNep

/// 재전사 집계 (#21 후속)
final class TranscriptionPassTests: XCTestCase {

    private func words(_ text: String, confidences: [Double]) -> [TranscriptWord] {
        confidences.enumerated().map { index, score in
            TranscriptWord(text: index == 0 ? text : "",
                           start: Double(index), end: Double(index) + 1,
                           confidence: score)
        }
    }

    func testPassJoinsText() {
        let pass = TranscriptionPass(words: [
            TranscriptWord(text: "레포지토리를 ", start: 0, end: 1, confidence: 0.9),
            TranscriptWord(text: "정리합시다", start: 1, end: 2, confidence: 0.9),
        ])
        XCTAssertEqual(pass.text, "레포지토리를 정리합시다")
        XCTAssertEqual(pass.wordCount, 2)
    }

    func testConfidenceStats() {
        let pass = TranscriptionPass(words: words("안녕", confidences: [1, 0.5, 0.8, 1]))
        XCTAssertEqual(pass.averageConfidence, 0.825, accuracy: 0.001)
        XCTAssertEqual(pass.minimumConfidence, 0.5, accuracy: 0.001)
        XCTAssertEqual(pass.scoredRatio, 0.5, accuracy: 0.001)
    }

    /// scoredRatio 0 = 신뢰도 속성이 안 붙어 온 것. 화면이 이걸로 경고한다
    func testAllOnesMeansNoConfidenceAttribute() {
        let pass = TranscriptionPass(words: words("안녕", confidences: [1, 1, 1]))
        XCTAssertEqual(pass.scoredRatio, 0)
    }

    func testEmptyWordsDoNotCrash() {
        let pass = TranscriptionPass(words: [])
        XCTAssertEqual(pass.wordCount, 0)
        XCTAssertEqual(pass.averageConfidence, 0)
        XCTAssertEqual(pass.minimumConfidence, 0)
        XCTAssertEqual(pass.scoredRatio, 0)
    }
}
