import XCTest
@testable import NepNep

final class TranscriptMergerTests: XCTestCase {
    private func word(_ text: String, _ start: Double, _ end: Double,
                      conf: Double = 1) -> TranscriptWord {
        TranscriptWord(text: text, start: start, end: end, confidence: conf)
    }

    private func seg(_ key: String, _ start: Double, _ end: Double) -> SpeakerSegment {
        SpeakerSegment(speakerKey: key, start: start, end: end)
    }

    /// 겹침 경계 단어는 중심점으로 배정한다 (03-m2 §2-1)
    func testBoundaryWordAssignedByMidpoint() {
        // 단어 0.8~1.4 → 중심 1.1 → B 세그먼트
        let words = [word("안녕", 0, 0.5), word("하세요", 0.8, 1.4)]
        let segments = [seg("A", 0, 1.0), seg("B", 1.0, 3.0)]
        let result = TranscriptMerger.merge(words: words, segments: segments)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].speakerKey, "A")
        XCTAssertEqual(result[1].speakerKey, "B")
    }

    /// 어느 세그먼트에도 없는 단어는 경계 거리가 가장 가까운 세그먼트로 (03-m2 §2-1)
    func testOutsideWordAssignedToNearestSegment() {
        // 중심 5.25 — A(0~2)와의 거리 3.25, B(6~8)와의 거리 0.75 → B
        let words = [word("음", 5.0, 5.5)]
        let segments = [seg("A", 0, 2), seg("B", 6, 8)]
        let result = TranscriptMerger.merge(words: words, segments: segments)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].speakerKey, "B")
    }

    /// 같은 화자라도 단어 간격 > 1.5초면 발화를 끊는다 (03-m2 §2-2)
    func testGapOverThresholdSplitsUtterance() {
        let words = [word("첫", 0, 0.5), word("발화", 0.6, 1.0),
                     word("둘째", 3.0, 3.5)]   // 1.0 → 3.0 간격 2초
        let segments = [seg("A", 0, 10)]
        let result = TranscriptMerger.merge(words: words, segments: segments)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].text, "첫발화")
        XCTAssertEqual(result[1].text, "둘째")
    }

    /// 화자 2명 교대 시나리오 (03-m2 §2 테스트 케이스)
    func testTwoSpeakerAlternation() {
        let words = [word("여보세요", 0, 1), word("네", 2, 2.5),
                     word("반갑습니다", 2.6, 3.5), word("저도요", 4.5, 5)]
        let segments = [seg("A", 0, 1.5), seg("B", 2, 4), seg("A", 4.2, 6)]
        let result = TranscriptMerger.merge(words: words, segments: segments)
        XCTAssertEqual(result.map(\.speakerKey), ["A", "B", "A"])
        XCTAssertEqual(result[1].text, "네반갑습니다")
    }

    /// 화자 4명 시나리오 + 등장 순서 화자 키 (03-m2 §2-3)
    func testFourSpeakersAndKeyOrder() {
        let words = (0..<4).map { word("말\($0)", Double($0 * 2), Double($0 * 2) + 1) }
        let segments = [seg("D", 0, 1.5), seg("C", 2, 3.5),
                        seg("B", 4, 5.5), seg("A", 6, 7.5)]
        let result = TranscriptMerger.merge(words: words, segments: segments)
        XCTAssertEqual(result.count, 4)
        XCTAssertEqual(TranscriptMerger.speakerKeysInOrder(result), ["D", "C", "B", "A"])
    }

    /// 화자분리 실패(빈 세그먼트) → 전체 단일 화자 (03-m2 §2 테스트 케이스)
    func testEmptySegmentsFallsBackToSingleSpeaker() {
        let words = [word("가", 0, 1), word("나", 5, 6)]
        let result = TranscriptMerger.merge(words: words, segments: [])
        XCTAssertEqual(Set(result.map(\.speakerKey)).count, 1)
    }

    /// 발화 confidence는 단어 confidence 평균 (03-m2 §2-3)
    func testConfidenceIsAverage() {
        let words = [word("가", 0, 0.5, conf: 0.8), word("나", 0.6, 1.0, conf: 0.4)]
        let segments = [seg("A", 0, 2)]
        let result = TranscriptMerger.merge(words: words, segments: segments)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].confidence, 0.6, accuracy: 0.0001)
    }

    /// 타임스탬프 없는 단어(-1)는 진행 중 발화에 이어 붙는다
    func testTimestamplessWordAppendsToCurrentUtterance() {
        let words = [word("가", 0, 0.5), word("나", -1, -1), word("다", 0.7, 1.0)]
        let segments = [seg("A", 0, 2)]
        let result = TranscriptMerger.merge(words: words, segments: segments)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].text, "가나다")
    }
}
