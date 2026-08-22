import PDFKit
import XCTest
@testable import NepNep

final class SummaryPDFRendererTests: XCTestCase {

    private func pdf(sections: [SummarySection]) -> PDFDocument? {
        let data = SummaryPDFRenderer.pdfData(
            title: "테스트 회의",
            metaText: "2026년 8월 22일 오후 3:00 · 30분 · 참석 2명",
            oneLiner: "한 줄 요약입니다",
            sections: sections,
            todos: [SummaryTextBuilder.TodoLine(
                text: "배포하기", isDone: false, assignee: "박진곤", due: "8월 26일")])
        return PDFDocument(data: data)
    }

    // 짧은 요약은 한 장, 본문은 모두 실린다
    func testShortSummaryFitsOnePage() {
        let document = pdf(sections: [
            SummarySection(title: "핵심 논의", bullets: ["첫 번째", "두 번째"]),
        ])

        XCTAssertEqual(document?.pageCount, 1)
        let text = document?.string ?? ""
        XCTAssertTrue(text.contains("테스트 회의"))
        XCTAssertTrue(text.contains("핵심 논의"))
        XCTAssertTrue(text.contains("배포하기 — 박진곤 (8월 26일)"))
    }

    // 한 장을 넘기면 다음 장으로 이어진다 (페이지 나누기 루프가 실제로 진행되는지)
    func testLongSummaryPaginates() {
        let bullets = (1...200).map { "논의 항목 \($0) — 페이지를 넘기기 위한 충분히 긴 문장입니다." }
        let document = pdf(sections: [SummarySection(title: "핵심 논의", bullets: bullets)])

        XCTAssertGreaterThan(document?.pageCount ?? 0, 1)
        XCTAssertTrue(document?.string?.contains("논의 항목 200") ?? false)
    }

    // 요약이 비어도 렌더링이 멈추지 않고 유효한 PDF가 나온다
    func testEmptySummaryStillRenders() {
        let data = SummaryPDFRenderer.pdfData(
            title: "빈 회의", metaText: "메타", oneLiner: "", sections: [], todos: [])

        XCTAssertEqual(PDFDocument(data: data)?.pageCount, 1)
    }
}
