import XCTest
@testable import NepNep

final class NotionBlockBuilderTests: XCTestCase {

    private func makeBlocks(oneLiner: String = "",
                            sections: [SummarySection] = [],
                            todos: [NotionBlockBuilder.TodoLine] = [],
                            transcript: [NotionBlockBuilder.TranscriptLine] = []) -> [[String: Any]] {
        NotionBlockBuilder.blocks(title: "테스트 회의",
                                  metaText: "2026년 8월 22일 · 30분 · 참석 2명",
                                  oneLiner: oneLiner,
                                  sections: sections,
                                  todos: todos,
                                  transcript: transcript)
    }

    private func blockTypes(_ blocks: [[String: Any]]) -> [String] {
        blocks.compactMap { $0["type"] as? String }
    }

    // 할 일 → to_do 블록, isDone → checked 매핑
    func testTodoCheckedMapping() {
        let blocks = makeBlocks(todos: [
            .init(text: "회의록 공유", isDone: true, assignee: "화자 1", due: nil),
            .init(text: "일정 확정", isDone: false, assignee: nil, due: "8월 26일"),
        ])
        let todoBlocks = blocks.filter { $0["type"] as? String == "to_do" }
        XCTAssertEqual(todoBlocks.count, 2)

        let payloads = todoBlocks.compactMap { $0["to_do"] as? [String: Any] }
        XCTAssertEqual(payloads[0]["checked"] as? Bool, true)
        XCTAssertEqual(payloads[1]["checked"] as? Bool, false)

        // 담당자·기한이 텍스트에 병합됨
        let firstText = (payloads[0]["rich_text"] as? [[String: Any]])?
            .compactMap { ($0["text"] as? [String: Any])?["content"] as? String }
            .joined() ?? ""
        XCTAssertTrue(firstText.contains("화자 1"))
    }

    // 2,000자 초과 텍스트는 같은 블록 안에서 rich_text로 분할
    func testLongTextSplitsIntoMultipleRichTexts() {
        let long = String(repeating: "가", count: 4500)
        let parts = NotionBlockBuilder.richTexts(long)
        XCTAssertEqual(parts.count, 3)   // 2000 + 2000 + 500
        let lengths = parts.compactMap {
            (($0["text"] as? [String: Any])?["content"] as? String)?.count
        }
        XCTAssertEqual(lengths, [2000, 2000, 500])
        XCTAssertTrue(lengths.allSatisfy { $0 <= NotionBlockBuilder.maxRichTextLength })
    }

    // 요약 없음 → 요약 관련 블록 없이 전사만
    func testEmptySummaryProducesTranscriptOnly() {
        let blocks = makeBlocks(transcript: [
            .init(speakerName: "화자 1", timeText: "00:05", text: "안녕하세요"),
        ])
        let types = blockTypes(blocks)
        XCTAssertFalse(types.contains("bulleted_list_item"))
        XCTAssertFalse(types.contains("to_do"))
        // heading_1(제목) + callout(메타) + heading_2(전사) + paragraph(발화 1)
        XCTAssertEqual(types, ["heading_1", "callout", "heading_2", "paragraph"])

        // 발화 rich_text 첫 요소는 볼드 화자명
        let para = blocks.last?["paragraph"] as? [String: Any]
        let first = (para?["rich_text"] as? [[String: Any]])?.first
        XCTAssertEqual((first?["annotations"] as? [String: Any])?["bold"] as? Bool, true)
    }

    // 100블록 단위 분할
    func testChunkingRespectsBlockLimit() {
        let transcript = (0..<250).map {
            NotionBlockBuilder.TranscriptLine(
                speakerName: "화자 1", timeText: "00:00", text: "발화 \($0)")
        }
        let blocks = makeBlocks(transcript: transcript)
        // heading_1 + callout + heading_2 + 250 = 253
        XCTAssertEqual(blocks.count, 253)

        let batches = NotionBlockBuilder.chunked(blocks)
        XCTAssertEqual(batches.map(\.count), [100, 100, 53])
    }

    // 페이지 URL → 32자리 hex ID 파싱
    func testPageIDParsing() {
        XCTAssertEqual(
            NotionAPIClient.pageID(
                fromURL: "https://www.notion.so/워크스페이스/테스트-회의-089f5efab1974d20a1f9152812a693bd"),
            "089f5efab1974d20a1f9152812a693bd")
        XCTAssertEqual(
            NotionAPIClient.pageID(
                fromURL: "https://www.notion.so/089f5efab1974d20a1f9152812a693bd?pvs=4"),
            "089f5efab1974d20a1f9152812a693bd")
        XCTAssertNil(NotionAPIClient.pageID(fromURL: "https://www.notion.so/붙은-아이디-없음"))
    }
}
