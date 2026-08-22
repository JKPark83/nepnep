import Foundation

/// Meeting 요약 → 평문·Markdown 변환 (#4 공유하기)
/// 순수 함수만 — API·SwiftData 의존 없음 (테스트 대상)
enum SummaryTextBuilder {
    struct TodoLine {
        let text: String
        let isDone: Bool
        let assignee: String?
        let due: String?
    }

    /// 메신저·메일 본문에 그대로 붙는 평문
    static func plainText(title: String,
                          metaText: String,
                          oneLiner: String,
                          sections: [SummarySection],
                          todos: [TodoLine]) -> String {
        var lines = [title, metaText]

        if !oneLiner.isEmpty {
            lines.append(contentsOf: ["", "[한 줄 요약]", oneLiner])
        }
        for section in sections where !section.bullets.isEmpty {
            lines.append(contentsOf: ["", "[\(section.title)]"])
            lines.append(contentsOf: section.bullets.map { "• \($0)" })
        }
        if !todos.isEmpty {
            lines.append(contentsOf: ["", "[할 일]"])
            lines.append(contentsOf: todos.map { "\($0.isDone ? "☑" : "☐") \(todoText($0))" })
        }
        return lines.joined(separator: "\n")
    }

    /// Obsidian·Apple Notes로 그대로 들어가는 Markdown
    static func markdown(title: String,
                         metaText: String,
                         oneLiner: String,
                         sections: [SummarySection],
                         todos: [TodoLine]) -> String {
        var lines = ["# \(title)", "", metaText]

        if !oneLiner.isEmpty {
            lines.append(contentsOf: ["", "## 한 줄 요약", "", oneLiner])
        }
        for section in sections where !section.bullets.isEmpty {
            lines.append(contentsOf: ["", "## \(section.title)", ""])
            lines.append(contentsOf: section.bullets.map { "- \($0)" })
        }
        if !todos.isEmpty {
            lines.append(contentsOf: ["", "## 할 일", ""])
            lines.append(contentsOf: todos.map { "- [\($0.isDone ? "x" : " ")] \(todoText($0))" })
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// 담당자·기한 suffix — Notion/Google Docs 빌더와 같은 표기
    static func todoText(_ todo: TodoLine) -> String {
        var text = todo.text
        if let assignee = todo.assignee { text += " — \(assignee)" }
        if let due = todo.due { text += " (\(due))" }
        return text
    }

    /// 파일명으로 못 쓰는 문자를 걷어낸다 (경로 구분자·콜론)
    static func safeFileName(_ title: String) -> String {
        let cleaned = title
            .components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|\n\r"))
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "회의록" : cleaned
    }
}
