import XCTest
@testable import NepNep

final class SummaryTemplateTests: XCTestCase {
    /// 템플릿 4종의 섹션 제목이 05-m3 §2 정의와 일치한다
    func testSectionTitlesPerTemplate() {
        XCTAssertEqual(SummaryTemplates.template(for: .general).keyPointsTitle, "주요 논의")
        XCTAssertEqual(SummaryTemplates.template(for: .general).decisionsTitle, "결정사항")
        XCTAssertEqual(SummaryTemplates.template(for: .oneOnOne).decisionsTitle, "합의사항")
        XCTAssertEqual(SummaryTemplates.template(for: .interview).keyPointsTitle, "질문 · 답변 요지")
        XCTAssertEqual(SummaryTemplates.template(for: .standup).decisionsTitle, "블로커")
    }

    /// 템플릿별 instructions는 서로 다르고, 타입이 올바르다
    func testInstructionsDifferPerTemplate() {
        let all = MeetingType.allCases.map { SummaryTemplates.template(for: $0) }
        XCTAssertEqual(Set(all.map(\.instructions)).count, all.count)
        for (type, template) in zip(MeetingType.allCases, all) {
            XCTAssertEqual(template.type, type)
        }
    }

    /// "내용|담당자|기한" 파싱 — 전체/부분/파이프 없음/빈 항목
    func testParseActionItem() {
        let full = SummaryTemplates.parseActionItem("문서 공유|김철수|8월 26일")
        XCTAssertEqual(full?.text, "문서 공유")
        XCTAssertEqual(full?.assignee, "김철수")
        XCTAssertEqual(full?.due, "8월 26일")

        let noDue = SummaryTemplates.parseActionItem("문서 공유|김철수|")
        XCTAssertEqual(noDue?.assignee, "김철수")
        XCTAssertNil(noDue?.due)

        let plain = SummaryTemplates.parseActionItem("문서 공유")
        XCTAssertEqual(plain?.text, "문서 공유")
        XCTAssertNil(plain?.assignee)

        XCTAssertNil(SummaryTemplates.parseActionItem("|김철수|8월 26일"))
        XCTAssertNil(SummaryTemplates.parseActionItem("  "))
    }

    /// reduce 프롬프트는 구간 번호와 비어 있지 않은 항목만 담는다
    func testReducePromptAssembly() {
        let digests = [
            ChunkDigest(points: ["로드맵 논의"], decisions: ["결제 개편 9월"], actionItems: ["문서 공유|김철수|"]),
            ChunkDigest(points: ["온보딩 논의"], decisions: [], actionItems: []),
        ]
        let prompt = SummaryTemplates.reducePrompt(digests: digests)
        XCTAssertTrue(prompt.contains("[구간 1]"))
        XCTAssertTrue(prompt.contains("[구간 2]"))
        XCTAssertTrue(prompt.contains("논의: 로드맵 논의"))
        XCTAssertTrue(prompt.contains("결정: 결제 개편 9월"))
        XCTAssertTrue(prompt.contains("할 일: 문서 공유|김철수|"))
        // 2번 구간은 빈 결정·할 일 줄이 없어야 한다
        XCTAssertEqual(prompt.components(separatedBy: "결정: ").count, 2)
        XCTAssertEqual(prompt.components(separatedBy: "할 일: ").count, 2)
    }
}
