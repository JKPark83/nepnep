import Foundation

/// Meeting → Notion 블록 JSON 변환 (06-m4 §3)
/// 순수 함수만 — API·SwiftData 의존 없음 (테스트 대상)
enum NotionBlockBuilder {
    static let maxRichTextLength = 2000    // rich_text 1개당 제한
    static let maxBlocksPerRequest = 100   // 요청당 블록 제한

    /// 전사 한 줄 (Utterance + Speaker 해석 결과)
    struct TranscriptLine {
        let speakerName: String
        let timeText: String     // "03:12"
        let text: String
    }

    struct TodoLine {
        let text: String
        let isDone: Bool
        let assignee: String?
        let due: String?
    }

    // MARK: - 블록 생성

    static func blocks(title: String,
                       metaText: String,
                       oneLiner: String,
                       sections: [SummarySection],
                       todos: [TodoLine],
                       transcript: [TranscriptLine]) -> [[String: Any]] {
        var blocks: [[String: Any]] = []
        blocks.append(block("heading_1", richTexts(title)))
        blocks.append([
            "object": "block",
            "type": "callout",
            "callout": [
                "rich_text": richTexts(metaText),
                "icon": ["type": "emoji", "emoji": "🎙️"],
            ] as [String: Any],
        ])

        if !oneLiner.isEmpty {
            blocks.append(block("heading_2", richTexts("한 줄 요약")))
            blocks.append(block("paragraph", richTexts(oneLiner)))
        }
        for section in sections where !section.bullets.isEmpty {
            blocks.append(block("heading_2", richTexts(section.title)))
            for bullet in section.bullets {
                blocks.append(block("bulleted_list_item", richTexts(bullet)))
            }
        }
        if !todos.isEmpty {
            blocks.append(block("heading_2", richTexts("할 일")))
            for todo in todos {
                var suffix = ""
                if let assignee = todo.assignee { suffix += " — \(assignee)" }
                if let due = todo.due { suffix += " (\(due))" }
                blocks.append([
                    "object": "block",
                    "type": "to_do",
                    "to_do": [
                        "rich_text": richTexts(todo.text + suffix),
                        "checked": todo.isDone,
                    ] as [String: Any],
                ])
            }
        }
        if !transcript.isEmpty {
            blocks.append(block("heading_2", richTexts("전사")))
            for line in transcript {
                var parts: [[String: Any]] = [[
                    "type": "text",
                    "text": ["content": "\(line.speakerName) [\(line.timeText)]  "],
                    "annotations": ["bold": true],
                ]]
                parts.append(contentsOf: richTexts(line.text))
                blocks.append(block("paragraph", parts))
            }
        }
        return blocks
    }

    /// 요청당 100블록 제한 대응 분할
    static func chunked(_ blocks: [[String: Any]],
                        size: Int = maxBlocksPerRequest) -> [[[String: Any]]] {
        stride(from: 0, to: blocks.count, by: size).map {
            Array(blocks[$0..<min($0 + size, blocks.count)])
        }
    }

    /// 2,000자 제한 대응: 긴 텍스트를 같은 블록 안의 rich_text 배열로 분할
    static func richTexts(_ text: String) -> [[String: Any]] {
        guard !text.isEmpty else { return [] }
        var result: [[String: Any]] = []
        var remaining = Substring(text)
        while !remaining.isEmpty {
            let piece = remaining.prefix(maxRichTextLength)
            result.append(["type": "text", "text": ["content": String(piece)]])
            remaining = remaining.dropFirst(piece.count)
        }
        return result
    }

    private static func block(_ type: String, _ richTexts: [[String: Any]]) -> [String: Any] {
        ["object": "block", "type": type, type: ["rich_text": richTexts]]
    }
}
