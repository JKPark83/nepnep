import XCTest
@testable import NepNep

final class GoogleDocsRequestBuilderTests: XCTestCase {

    private func makeParagraphs() -> [GoogleDocsRequestBuilder.Paragraph] {
        GoogleDocsRequestBuilder.paragraphs(
            title: "테스트 회의",
            metaText: "2026년 8월 22일 · 30분 · 참석 2명",
            oneLiner: "한 줄 요약입니다",
            sections: [SummarySection(title: "핵심 논의", bullets: ["첫 번째", "두 번째"])],
            todos: [GoogleDocsRequestBuilder.TodoLine(
                text: "배포하기", isDone: false, assignee: "박진곤", due: "8월 26일")],
            transcript: [GoogleDocsRequestBuilder.TranscriptLine(
                speakerName: "화자 1", timeText: "03:12", text: "안녕하세요")])
    }

    private func insertTexts(_ requests: [[String: Any]]) -> [[String: Any]] {
        requests.compactMap { $0["insertText"] as? [String: Any] }
    }

    // 역순 조립: 모든 insertText는 index 1, 요청 순서상 첫 삽입은 마지막 문단·마지막 삽입은 제목
    func testInsertRequestsReverseAssemblyAtIndexOne() {
        let paragraphs = makeParagraphs()
        let requests = GoogleDocsRequestBuilder.insertRequests(paragraphs: paragraphs)
        let inserts = insertTexts(requests)

        XCTAssertEqual(inserts.count, paragraphs.count)
        for insert in inserts {
            let location = insert["location"] as? [String: Any]
            XCTAssertEqual(location?["index"] as? Int, 1)
        }
        XCTAssertEqual(inserts.first?["text"] as? String, "화자 1 [03:12]  안녕하세요\n")
        XCTAssertEqual(inserts.last?["text"] as? String, "테스트 회의\n")
    }

    // 문단 순서·스타일·불릿 프리셋: 요약 불릿=DISC, 할 일=CHECKBOX(담당자·기한 suffix)
    func testParagraphStylesAndBulletPresets() {
        let paragraphs = makeParagraphs()

        XCTAssertEqual(paragraphs.first?.namedStyle, "HEADING_1")
        let headings = paragraphs.filter { $0.namedStyle == "HEADING_2" }.map(\.text)
        XCTAssertEqual(headings, ["한 줄 요약", "핵심 논의", "할 일", "전사"])

        let discBullets = paragraphs.filter { $0.bulletPreset == "BULLET_DISC_CIRCLE_SQUARE" }
        XCTAssertEqual(discBullets.map(\.text), ["첫 번째", "두 번째"])

        let checkboxes = paragraphs.filter { $0.bulletPreset == "BULLET_CHECKBOX" }
        XCTAssertEqual(checkboxes.map(\.text), ["배포하기 — 박진곤 (8월 26일)"])
    }

    // 스타일 range는 UTF-16 코드 유닛 길이 기준 {1, 1+length}
    func testStyleRangeUsesUTF16Length() {
        let paragraph = GoogleDocsRequestBuilder.Paragraph(
            text: "🎙️ 테스트", namedStyle: "NORMAL_TEXT", bulletPreset: nil)
        let requests = GoogleDocsRequestBuilder.insertRequests(paragraphs: [paragraph])

        let style = requests.compactMap { $0["updateParagraphStyle"] as? [String: Any] }.first
        let range = style?["range"] as? [String: Any]
        XCTAssertEqual(range?["startIndex"] as? Int, 1)
        XCTAssertEqual(range?["endIndex"] as? Int, 1 + "🎙️ 테스트".utf16.count)
    }

    // 재내보내기: deleteContentRange(1, endIndex-1)가 맨 앞, 이후 삽입 시퀀스
    func testReplaceRequestsStartWithDelete() {
        let paragraphs = makeParagraphs()
        let requests = GoogleDocsRequestBuilder.replaceRequests(endIndex: 120, paragraphs: paragraphs)

        let delete = requests.first?["deleteContentRange"] as? [String: Any]
        let range = delete?["range"] as? [String: Any]
        XCTAssertEqual(range?["startIndex"] as? Int, 1)
        XCTAssertEqual(range?["endIndex"] as? Int, 119)

        // 사실상 빈 문서(endIndex ≤ 2)면 삭제 생략
        let fresh = GoogleDocsRequestBuilder.replaceRequests(endIndex: 2, paragraphs: paragraphs)
        XCTAssertNil(fresh.first?["deleteContentRange"])
        XCTAssertNotNil(fresh.first?["insertText"])
    }
}
