import Foundation

/// Meeting → Google Docs batchUpdate 요청 변환 (08-m5 §2)
/// 순수 함수만 — API·SwiftData 의존 없음 (테스트 대상).
/// 인덱스는 뒤에서 앞으로(항상 index 1에) 삽입하면 재계산이 필요 없다 — 역순 조립.
enum GoogleDocsRequestBuilder {
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

    /// 문단 중간 표현 — 문서에 위에서 아래 순서로 배열
    struct Paragraph: Equatable {
        let text: String                 // 개행 미포함
        let namedStyle: String           // "HEADING_1" | "HEADING_2" | "NORMAL_TEXT"
        let bulletPreset: String?        // "BULLET_DISC_CIRCLE_SQUARE" | "BULLET_CHECKBOX"
    }

    // MARK: - Meeting 내용 → 문단 (Notion과 동일 순서: 제목→메타→요약→섹션→할 일→전사)

    static func paragraphs(title: String,
                           metaText: String,
                           oneLiner: String,
                           sections: [SummarySection],
                           todos: [TodoLine],
                           transcript: [TranscriptLine]) -> [Paragraph] {
        var result: [Paragraph] = []
        result.append(Paragraph(text: title, namedStyle: "HEADING_1", bulletPreset: nil))
        result.append(Paragraph(text: "🎙️ \(metaText)", namedStyle: "NORMAL_TEXT", bulletPreset: nil))

        if !oneLiner.isEmpty {
            result.append(Paragraph(text: "한 줄 요약", namedStyle: "HEADING_2", bulletPreset: nil))
            result.append(Paragraph(text: oneLiner, namedStyle: "NORMAL_TEXT", bulletPreset: nil))
        }
        for section in sections where !section.bullets.isEmpty {
            result.append(Paragraph(text: section.title, namedStyle: "HEADING_2", bulletPreset: nil))
            for bullet in section.bullets {
                result.append(Paragraph(text: bullet, namedStyle: "NORMAL_TEXT",
                                        bulletPreset: "BULLET_DISC_CIRCLE_SQUARE"))
            }
        }
        if !todos.isEmpty {
            result.append(Paragraph(text: "할 일", namedStyle: "HEADING_2", bulletPreset: nil))
            for todo in todos {
                var suffix = ""
                if let assignee = todo.assignee { suffix += " — \(assignee)" }
                if let due = todo.due { suffix += " (\(due))" }
                result.append(Paragraph(text: todo.text + suffix, namedStyle: "NORMAL_TEXT",
                                        bulletPreset: "BULLET_CHECKBOX"))
            }
        }
        if !transcript.isEmpty {
            result.append(Paragraph(text: "전사", namedStyle: "HEADING_2", bulletPreset: nil))
            for line in transcript {
                result.append(Paragraph(
                    text: "\(line.speakerName) [\(line.timeText)]  \(line.text)",
                    namedStyle: "NORMAL_TEXT", bulletPreset: nil))
            }
        }
        return result
    }

    // MARK: - 문단 → batchUpdate 요청 (역순 조립)

    /// 빈 문서(본문 시작 index 1)에 삽입하는 요청 시퀀스.
    /// 마지막 문단부터 index 1에 삽입 → 앞 문단이 삽입될 때마다 뒤 내용이 밀려나 순서가 맞는다.
    static func insertRequests(paragraphs: [Paragraph]) -> [[String: Any]] {
        var requests: [[String: Any]] = []
        for paragraph in paragraphs.reversed() {
            // Docs API 인덱스는 UTF-16 코드 유닛 기준
            let length = paragraph.text.utf16.count
            requests.append([
                "insertText": [
                    "location": ["index": 1],
                    "text": paragraph.text + "\n",
                ] as [String: Any],
            ])
            let range: [String: Any] = ["startIndex": 1, "endIndex": 1 + length]
            requests.append([
                "updateParagraphStyle": [
                    "range": range,
                    "paragraphStyle": ["namedStyleType": paragraph.namedStyle],
                    "fields": "namedStyleType",
                ] as [String: Any],
            ])
            if let preset = paragraph.bulletPreset {
                requests.append([
                    "createParagraphBullets": [
                        "range": range,
                        "bulletPreset": preset,
                    ] as [String: Any],
                ])
            }
        }
        return requests
    }

    /// 재내보내기: 문서 전체(1 ~ endIndex-1) 삭제 후 재삽입 (08-m5 §2)
    static func replaceRequests(endIndex: Int, paragraphs: [Paragraph]) -> [[String: Any]] {
        var requests: [[String: Any]] = []
        if endIndex > 2 {
            requests.append([
                "deleteContentRange": [
                    "range": ["startIndex": 1, "endIndex": endIndex - 1],
                ] as [String: Any],
            ])
        }
        requests.append(contentsOf: insertRequests(paragraphs: paragraphs))
        return requests
    }
}
