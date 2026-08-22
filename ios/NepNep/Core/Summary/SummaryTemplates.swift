import Foundation

/// 템플릿 4종의 instructions·섹션 제목 정의 (05-m3 §2)
/// 출력 스키마(FinalSummary)는 공통이고, 관점과 섹션 제목만 템플릿별로 다르다.
enum SummaryTemplates {
    struct Template {
        let type: MeetingType
        /// reduce(최종 요약) 단계 instructions
        let instructions: String
        /// FinalSummary.keyPoints 섹션 제목
        let keyPointsTitle: String
        /// FinalSummary.decisions 섹션 제목
        let decisionsTitle: String
    }

    /// map(청크 요지) 단계 공통 instructions — 템플릿과 무관하게 사실 추출만
    static let mapInstructions = """
        당신은 회의록 정리 도우미입니다. 주어진 회의 전사 일부에서 핵심 논의, \
        결정사항, 할 일을 사실 그대로 한국어로 추출하세요. 전사에 없는 내용을 \
        지어내지 마세요. 할 일은 '내용|담당자|기한' 형태로 쓰고 모르는 항목은 \
        빈칸으로 둡니다.
        """

    static func template(for type: MeetingType) -> Template {
        switch type {
        case .general:
            return Template(
                type: .general,
                instructions: base + "일반 회의록입니다. 논의 흐름과 결론이 잘 드러나게 정리하세요.",
                keyPointsTitle: "주요 논의",
                decisionsTitle: "결정사항")
        case .oneOnOne:
            return Template(
                type: .oneOnOne,
                instructions: base + """
                    1on1 대화입니다. 서로 주고받은 피드백과 합의한 내용을 중심으로 \
                    정리하세요. keyPoints에는 주요 대화 주제와 피드백을, decisions에는 \
                    둘이 합의한 사항을 담으세요.
                    """,
                keyPointsTitle: "주요 대화 · 피드백",
                decisionsTitle: "합의사항")
        case .interview:
            return Template(
                type: .interview,
                instructions: base + """
                    인터뷰 기록입니다. keyPoints에는 '질문 — 답변 요지' 형태로 주요 \
                    문답을, decisions에는 인터뷰어의 평가 메모나 인상적인 포인트를 \
                    담으세요.
                    """,
                keyPointsTitle: "질문 · 답변 요지",
                decisionsTitle: "평가 메모")
        case .standup:
            return Template(
                type: .standup,
                instructions: base + """
                    스탠드업 회의입니다. keyPoints에는 참석자별 어제 한 일과 오늘 할 \
                    일을, decisions에는 블로커와 해결 방안을 담으세요.
                    """,
                keyPointsTitle: "어제 · 오늘",
                decisionsTitle: "블로커")
        }
    }

    private static let base = """
        당신은 회의록 정리 도우미입니다. 구간별 요지 모음을 바탕으로 회의 전체를 \
        한국어로 요약하세요. title에는 이 회의를 목록에서 한눈에 알아볼 수 있는 \
        주제를 20자 이내로 적되, 날짜나 '회의' 같은 말은 넣지 않습니다. \
        요지에 없는 내용을 지어내지 마세요. 할 일은 \
        '내용|담당자|기한' 형태로 쓰고 모르는 항목은 빈칸으로 둡니다.
        """

    /// map 단계 프롬프트
    static func mapPrompt(chunkText: String) -> String {
        "다음은 회의 전사의 일부입니다.\n\n\(chunkText)"
    }

    /// reduce 단계 프롬프트 — digest 모음을 텍스트로 병합
    static func reducePrompt(digests: [ChunkDigest]) -> String {
        var lines: [String] = ["다음은 회의를 구간별로 정리한 요지입니다."]
        for (i, digest) in digests.enumerated() {
            lines.append("\n[구간 \(i + 1)]")
            if !digest.points.isEmpty {
                lines.append("논의: " + digest.points.joined(separator: " / "))
            }
            if !digest.decisions.isEmpty {
                lines.append("결정: " + digest.decisions.joined(separator: " / "))
            }
            if !digest.actionItems.isEmpty {
                lines.append("할 일: " + digest.actionItems.joined(separator: " / "))
            }
        }
        return lines.joined(separator: "\n")
    }

    /// "내용|담당자|기한" → (text, assignee, due). 파이프 없으면 전체를 text로 (05-m3 §4)
    static func parseActionItem(_ raw: String) -> (text: String, assignee: String?, due: String?)? {
        let parts = raw.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard let first = parts.first, !first.isEmpty else { return nil }
        let assignee = parts.count > 1 && !parts[1].isEmpty ? parts[1] : nil
        let due = parts.count > 2 && !parts[2].isEmpty ? parts[2] : nil
        return (first, assignee, due)
    }
}
