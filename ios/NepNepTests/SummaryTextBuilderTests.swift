import XCTest
@testable import NepNep

final class SummaryTextBuilderTests: XCTestCase {

    private let sections = [
        SummarySection(title: "핵심 논의", bullets: ["첫 번째", "두 번째"]),
        SummarySection(title: "결정 사항", bullets: ["8월 26일 배포"]),
    ]
    private let todos = [
        SummaryTextBuilder.TodoLine(
            text: "배포하기", isDone: false, assignee: "박진곤", due: "8월 26일"),
        SummaryTextBuilder.TodoLine(
            text: "공지 쓰기", isDone: true, assignee: nil, due: nil),
    ]

    private func plain(oneLiner: String = "한 줄 요약입니다",
                       sections: [SummarySection]? = nil,
                       todos: [SummaryTextBuilder.TodoLine]? = nil) -> String {
        SummaryTextBuilder.plainText(
            title: "테스트 회의",
            metaText: "2026년 8월 22일 오후 3:00 · 30분 · 참석 2명",
            oneLiner: oneLiner,
            sections: sections ?? self.sections,
            todos: todos ?? self.todos)
    }

    private func markdown(oneLiner: String = "한 줄 요약입니다",
                          sections: [SummarySection]? = nil,
                          todos: [SummaryTextBuilder.TodoLine]? = nil) -> String {
        SummaryTextBuilder.markdown(
            title: "테스트 회의",
            metaText: "2026년 8월 22일 오후 3:00 · 30분 · 참석 2명",
            oneLiner: oneLiner,
            sections: sections ?? self.sections,
            todos: todos ?? self.todos)
    }

    // 평문: 제목 → 메타 → 한 줄 요약 → 섹션 → 할 일 순서와 글머리표
    func testPlainTextLayout() {
        let lines = plain().components(separatedBy: "\n")

        XCTAssertEqual(lines.first, "테스트 회의")
        XCTAssertEqual(lines[1], "2026년 8월 22일 오후 3:00 · 30분 · 참석 2명")
        XCTAssertEqual(lines.filter { $0.hasPrefix("[") },
                       ["[한 줄 요약]", "[핵심 논의]", "[결정 사항]", "[할 일]"])
        XCTAssertTrue(lines.contains("• 첫 번째"))
        XCTAssertTrue(lines.contains("☐ 배포하기 — 박진곤 (8월 26일)"))
        XCTAssertTrue(lines.contains("☑ 공지 쓰기"))
    }

    // Markdown: 헤딩 레벨, 불릿, 체크박스 표기
    func testMarkdownLayout() {
        let text = markdown()
        let lines = text.components(separatedBy: "\n")

        XCTAssertEqual(lines.first, "# 테스트 회의")
        XCTAssertEqual(lines.filter { $0.hasPrefix("## ") },
                       ["## 한 줄 요약", "## 핵심 논의", "## 결정 사항", "## 할 일"])
        XCTAssertTrue(lines.contains("- 첫 번째"))
        XCTAssertTrue(lines.contains("- [ ] 배포하기 — 박진곤 (8월 26일)"))
        XCTAssertTrue(lines.contains("- [x] 공지 쓰기"))
        XCTAssertTrue(text.hasSuffix("\n"))
    }

    // 담당자·기한 suffix는 Notion/Google Docs 빌더와 같은 표기여야 한다
    func testTodoSuffixMatchesOtherBuilders() {
        XCTAssertEqual(SummaryTextBuilder.todoText(todos[0]), "배포하기 — 박진곤 (8월 26일)")
        XCTAssertEqual(SummaryTextBuilder.todoText(todos[1]), "공지 쓰기")
        XCTAssertEqual(SummaryTextBuilder.todoText(SummaryTextBuilder.TodoLine(
            text: "검토", isDone: false, assignee: nil, due: "내일")), "검토 (내일)")
    }

    // 빈 한 줄 요약·빈 섹션·할 일 없음이면 그 머리글 자체가 빠진다
    func testEmptyPartsAreOmitted() {
        let emptyBullets = [SummarySection(title: "핵심 논의", bullets: [])]
        let text = plain(oneLiner: "", sections: emptyBullets, todos: [])

        XCTAssertFalse(text.contains("[한 줄 요약]"))
        XCTAssertFalse(text.contains("[핵심 논의]"))
        XCTAssertFalse(text.contains("[할 일]"))
        XCTAssertEqual(text, "테스트 회의\n2026년 8월 22일 오후 3:00 · 30분 · 참석 2명")

        let md = markdown(oneLiner: "", sections: emptyBullets, todos: [])
        XCTAssertFalse(md.contains("## "))
    }

    // 파일명: 경로 구분자·콜론을 걷어내고, 다 걷힌 뒤 비면 기본 이름을 쓴다
    func testSafeFileName() {
        XCTAssertEqual(SummaryTextBuilder.safeFileName("8월 22일 일반 회의"), "8월 22일 일반 회의")
        XCTAssertEqual(SummaryTextBuilder.safeFileName("Q3/Q4 계획: 검토"), "Q3 Q4 계획  검토")
        XCTAssertEqual(SummaryTextBuilder.safeFileName("///"), "회의록")
        XCTAssertEqual(SummaryTextBuilder.safeFileName(""), "회의록")
    }
}
