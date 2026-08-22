import Foundation

/// 전사 단어 × 화자 세그먼트 병합 (03-m2 §2, F3-2)
struct MergedUtterance: Codable, Equatable {
    let speakerKey: String
    let text: String
    let start: TimeInterval
    let end: TimeInterval
    let confidence: Double
}

enum TranscriptMerger {
    /// 발화를 끊는 단어 간 최대 간격
    static let gapThreshold: TimeInterval = 1.5

    static func merge(words: [TranscriptWord],
                      segments: [SpeakerSegment]) -> [MergedUtterance] {
        guard !words.isEmpty else { return [] }

        // 화자분리 실패(빈 세그먼트) → 전체를 단일 화자로 (03-m2 §2 테스트 케이스)
        let effectiveSegments = segments.isEmpty
            ? [SpeakerSegment(speakerKey: "speaker-0",
                              start: words.first!.start,
                              end: words.last!.end)]
            : segments

        var utterances: [MergedUtterance] = []
        var currentKey: String?
        var currentText = ""
        var currentStart: TimeInterval = 0
        var currentEnd: TimeInterval = 0
        var confidences: [Double] = []

        func flush() {
            guard let key = currentKey, !currentText.isEmpty else { return }
            let avg = confidences.isEmpty ? 0
                : confidences.reduce(0, +) / Double(confidences.count)
            utterances.append(MergedUtterance(
                speakerKey: key, text: currentText,
                start: currentStart, end: currentEnd, confidence: avg))
            currentKey = nil
            currentText = ""
            confidences = []
        }

        for word in words {
            // 타임스탬프 없는 단어(-1)는 진행 중인 발화에 이어 붙인다
            guard word.start >= 0 else {
                if currentKey != nil {
                    currentText += word.text
                    confidences.append(word.confidence)
                }
                continue
            }

            let key = speakerKey(for: word, in: effectiveSegments)
            let gapExceeded = currentKey != nil && (word.start - currentEnd) > gapThreshold
            if key != currentKey || gapExceeded {
                flush()
                currentKey = key
                currentStart = word.start
            }
            currentText += word.text
            currentEnd = word.end
            confidences.append(word.confidence)
        }
        flush()
        return utterances
    }

    /// 단어 중심점이 포함되는 세그먼트, 없으면 경계 거리가 가장 가까운 세그먼트 (03-m2 §2-1)
    private static func speakerKey(for word: TranscriptWord,
                                   in segments: [SpeakerSegment]) -> String {
        let mid = (word.start + word.end) / 2
        if let hit = segments.first(where: { mid >= $0.start && mid < $0.end }) {
            return hit.speakerKey
        }
        let nearest = segments.min { distance(mid, to: $0) < distance(mid, to: $1) }!
        return nearest.speakerKey
    }

    private static func distance(_ t: TimeInterval, to seg: SpeakerSegment) -> TimeInterval {
        if t < seg.start { return seg.start - t }
        if t >= seg.end { return t - seg.end }
        return 0
    }

    /// 발화 등장 순서대로 화자 키 나열 — Speaker 레코드 생성용 (03-m2 §2-3)
    static func speakerKeysInOrder(_ utterances: [MergedUtterance]) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        for u in utterances where !seen.contains(u.speakerKey) {
            seen.insert(u.speakerKey)
            ordered.append(u.speakerKey)
        }
        return ordered
    }
}
