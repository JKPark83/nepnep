import Foundation

/// 재전사 한 판의 집계 (#21 후속, 개발용)
///
/// 처음에는 어휘 유무를 A/B로 비교하려고 만들었는데, `contextualStrings`가 실제로는
/// 아무 효과가 없다는 게 실측으로 확인돼(`TranscriptionGlossary` 주석 참고)
/// 비교할 두 판이 사라졌다. 지금은 한 판만 돌려 신뢰도가 제대로 실려 오는지,
/// 전사 원문이 어떻게 나오는지 눈으로 확인하는 용도로 남긴다.
struct TranscriptionPass: Equatable {
    let text: String
    let wordCount: Int
    let averageConfidence: Double
    let minimumConfidence: Double
    /// 신뢰도가 1보다 낮게 매겨진 런의 비율.
    /// 0이면 속성이 아예 안 붙어 온 것이다 — 그 자체가 확인해야 할 신호다.
    let scoredRatio: Double

    init(words: [TranscriptWord]) {
        text = words.map(\.text).joined()
        wordCount = words.count

        let scores = words.map(\.confidence)
        averageConfidence = scores.isEmpty
            ? 0 : scores.reduce(0, +) / Double(scores.count)
        minimumConfidence = scores.min() ?? 0
        scoredRatio = scores.isEmpty
            ? 0 : Double(scores.filter { $0 < 1 }.count) / Double(scores.count)
    }
}
