import Foundation

/// 회의 용어집 (#21 후속)
///
/// 온디바이스 전사기는 회의에서 반복되는 고유명사·기술 용어를 자주 놓친다 —
/// "카프카"가 "카프가"로, "펄프 픽션"이 "포프 픽션"으로 적히는 식이다.
///
/// 처음에는 `AnalysisContext.contextualStrings`로 전사 단계에서 잡으려 했는데,
/// 실측해 보니 그 API가 아무 효과가 없었다. 같은 오디오를 컨텍스트 없이 /
/// `setContext`로 / 생성자 인자로 세 번 돌린 결과가 바이트 단위로 같았고,
/// 한국어뿐 아니라 영어에서도 마찬가지였다. SDK에 다른 주입 경로도 없다.
///
/// 그래서 용어집은 요약 프롬프트로 옮겼다. 전사 원문은 그대로 두고, 요약·제목·
/// 안건에서만 올바른 표기가 나오게 한다 — 사용자가 실제로 읽는 쪽은 거기다.
enum TranscriptionGlossary {
    static let storageKey = "transcription.glossary"

    /// 프롬프트에 통째로 실리므로 컨텍스트 한도를 갉아먹는다. 상한을 둔다.
    static let maxTerms = 100
    static let maxTermLength = 40

    static var rawText: String {
        get { UserDefaults.standard.string(forKey: storageKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: storageKey) }
    }

    static var terms: [String] { parse(rawText) }

    /// 줄바꿈·쉼표 아무거나로 구분 — 사용자가 어떻게 적든 받아 준다.
    static func parse(_ text: String) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for piece in text.split(whereSeparator: { $0.isNewline || $0 == "," }) {
            let term = piece.trimmingCharacters(in: .whitespaces)
            guard !term.isEmpty, term.count <= maxTermLength else { continue }
            guard seen.insert(term.lowercased()).inserted else { continue }
            result.append(term)
            if result.count == maxTerms { break }
        }
        return result
    }
}
