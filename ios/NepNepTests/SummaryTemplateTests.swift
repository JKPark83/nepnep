import XCTest
@testable import NepNep

final class SummaryTemplateTests: XCTestCase {
    /// 프롬프트는 영어로 쓰되 "출력은 한국어" 제약이 map·reduce 양쪽에 있어야 한다 (#21)
    func testInstructionsForceKoreanOutput() {
        for instructions in [SummaryTemplates.mapInstructions, SummaryTemplates.reduceInstructions] {
            XCTAssertTrue(instructions.contains("Write every output value in Korean"))
            XCTAssertTrue(instructions.contains("Never write English in any field"))
        }
        // 제목은 최종 요약에서만 만든다
        XCTAssertTrue(SummaryTemplates.reduceInstructions.contains("title:"))
        XCTAssertFalse(SummaryTemplates.mapInstructions.contains("title:"))
    }

    /// 두 프롬프트 모두 자리표시자 금지를 못 박는다 — "내용|담당자|기한"이 값으로 나오던 사고 (#21)
    func testInstructionsBanPlaceholders() {
        for instructions in [SummaryTemplates.mapInstructions, SummaryTemplates.reduceInstructions] {
            XCTAssertTrue(instructions.contains("내용, 담당자, 기한, 미정, 없음"))
        }
    }

    /// map 프롬프트는 화자 명단을 함께 실어 보낸다
    func testMapPromptCarriesSpeakerRoster() {
        let prompt = SummaryTemplates.mapPrompt(chunkText: "화자 1: 안녕하세요",
                                                speakers: ["화자 1", "김철수"])
        XCTAssertTrue(prompt.contains("화자 1, 김철수"))
        XCTAssertTrue(prompt.contains("화자 1: 안녕하세요"))
    }

    /// 용어집은 map·reduce 양쪽 프롬프트에 실린다 (#21 후속)
    func testPromptsCarryGlossary() {
        let terms = ["Redis", "카프카"]
        let map = SummaryTemplates.mapPrompt(chunkText: "화자 1: 래디스 씁니다",
                                             speakers: ["화자 1"],
                                             glossary: terms)
        let reduce = SummaryTemplates.reducePrompt(digests: [digest(topic: "캐시", points: [])],
                                                   speakers: ["화자 1"],
                                                   glossary: terms)
        for prompt in [map, reduce] {
            XCTAssertTrue(prompt.contains("Redis, 카프카"))
            // 원문에 없는 용어를 끌어다 쓰지 못하게 하는 문장이 같이 가야 한다
            XCTAssertTrue(prompt.contains("Never introduce one of these terms"))
        }
    }

    /// 영어 용어는 등록 표기와 상관없이 알파벳으로 적힌다 — "레디스"로 등록해도 Redis
    func testGlossaryForcesLatinSpellingForEnglishTerms() {
        let prompt = SummaryTemplates.mapPrompt(chunkText: "화자 1: 래디스 씁니다",
                                                speakers: ["화자 1"],
                                                glossary: ["레디스"])
        XCTAssertTrue(prompt.contains("write it in the Latin alphabet"))
        // 지시문의 영어 금지 규칙이 예외를 열어 주지 않으면 두 지시가 충돌한다
        for instructions in [SummaryTemplates.mapInstructions, SummaryTemplates.reduceInstructions] {
            XCTAssertTrue(instructions.contains("except for the proper nouns listed in the prompt"))
        }
    }

    func testEmptyGlossaryAddsNothingToPrompt() {
        let prompt = SummaryTemplates.mapPrompt(chunkText: "본문", speakers: ["화자 1"])
        XCTAssertFalse(prompt.contains("Known proper nouns"))
    }

    /// reduce 프롬프트는 구간 번호와 주제·요지를 담고, 비어 있는 결정 줄은 만들지 않는다
    func testReducePromptAssembly() {
        let digests = [
            digest(topic: "로드맵",
                   points: ["화자 1 — 일정이 촉박하다"],
                   decisions: [DecisionItem(content: "결제 개편 9월", rationale: "",
                                            decider: "", revisitCondition: "")]),
            digest(topic: "온보딩", points: ["화자 1 — 문서가 없다"]),
        ]
        let prompt = SummaryTemplates.reducePrompt(digests: digests, speakers: ["화자 1"])
        XCTAssertTrue(prompt.contains("[구간 1] 로드맵"))
        XCTAssertTrue(prompt.contains("[구간 2] 온보딩"))
        XCTAssertTrue(prompt.contains("화자 1 — 일정이 촉박하다"))
        XCTAssertTrue(prompt.contains("결정: 결제 개편 9월"))
        // 2번 구간은 빈 결정 줄이 없어야 한다
        XCTAssertEqual(prompt.components(separatedBy: "결정: ").count, 2)
    }

    // MARK: - 후처리

    /// 실제로 저장됐던 "내용 / 화자 1 / 미정" 같은 자리표시자는 전부 걸러진다 (#21)
    func testCleanActionItemsDropsPlaceholders() {
        let items = [
            action("내용", assignee: "화자 1", due: "미정"),
            action("  "),
            action("온보딩 설계 문서 작성", assignee: "김철수", due: "미정"),
        ]
        let cleaned = SummaryTemplates.cleanActionItems(items)
        XCTAssertEqual(cleaned.count, 1)
        XCTAssertEqual(cleaned[0].task, "온보딩 설계 문서 작성")
        XCTAssertEqual(cleaned[0].assignee, "김철수")
        // 기한이 자리표시자면 비워 둔다 — "미정" 배지를 그리지 않기 위해
        XCTAssertEqual(cleaned[0].due, "")
    }

    /// 브리핑 한 줄로 "1"만 나오던 사고 — 글자 없는 값과 너무 짧은 값은 걷어낸다 (#21)
    func testMeaningfulnessDropsScraps() {
        XCTAssertFalse(SummaryTemplates.isMeaningful("1", minLength: SummaryTemplates.minSentenceLength))
        XCTAssertFalse(SummaryTemplates.isMeaningful("2.", minLength: SummaryTemplates.minPhraseLength))
        XCTAssertFalse(SummaryTemplates.isMeaningful("네", minLength: SummaryTemplates.minPhraseLength))
        XCTAssertTrue(SummaryTemplates.isMeaningful("메모리는 배치 저장으로 가기로 했다",
                                                    minLength: SummaryTemplates.minSentenceLength))

        let briefing = SummaryTemplates.cleanBullets(
            ["1", "문구화는 배치 처리 보고서를 작성 중이다", "  "],
            limit: 3, minLength: SummaryTemplates.minSentenceLength)
        XCTAssertEqual(briefing, ["문구화는 배치 처리 보고서를 작성 중이다"])
    }

    /// 기한 칸에 "완료", 담당자 칸에 "화자 4"가 들어오던 문제 — 값이 아니라 빈 칸으로 본다 (#21)
    func testDetailRejectsStatusWordsAndDefaultSpeakerLabels() {
        XCTAssertEqual(SummaryTemplates.detail("완료"), "")
        XCTAssertEqual(SummaryTemplates.detail("진행중"), "")
        XCTAssertEqual(SummaryTemplates.detail("화자 4"), "")
        XCTAssertEqual(SummaryTemplates.detail("김택현"), "김택현")
        XCTAssertEqual(SummaryTemplates.detail("8월 26일"), "8월 26일")
        // 이름이 지정된 화자는 그대로 남는다
        XCTAssertFalse(SummaryTemplates.isDefaultSpeakerLabel("화자현수"))
        XCTAssertTrue(SummaryTemplates.isDefaultSpeakerLabel("화자 12"))
    }

    /// 할 일 정리에서도 같은 규칙이 적용된다
    func testCleanActionItemsScrubsDetails() {
        let cleaned = SummaryTemplates.cleanActionItems([
            action("페르소나 유지", assignee: "화자 5", due: "완료", status: "완료"),
            action("배치 처리 보고서를 금요일까지 작성한다", assignee: "화자 4", due: "완료", status: "진행중"),
        ])
        XCTAssertEqual(cleaned.count, 1, "두 어절짜리 주제어는 할 일이 아니다")
        XCTAssertEqual(cleaned[0].assignee, "")
        XCTAssertEqual(cleaned[0].due, "")
        XCTAssertEqual(cleaned[0].status, SummaryTemplates.statusInProgress)
    }

    /// 중복 제거와 10개 상한은 코드에서도 강제한다
    func testCleanActionItemsDeduplicatesAndCaps() {
        let duplicated = (1...15).map { action("작업 \($0)번 문서를 작성한다") }
            + [action("작업 1번 문서를 작성한다.")]
        let cleaned = SummaryTemplates.cleanActionItems(duplicated)
        XCTAssertEqual(cleaned.count, SummaryTemplates.maxActionItems)
        XCTAssertEqual(Set(cleaned.map(\.task)).count, cleaned.count)
    }

    /// 상태는 세 값 안으로만 들어온다 — 모델이 "진행 중", "in progress"를 섞어 뱉는다 (#21)
    func testStatusNormalization() {
        XCTAssertEqual(SummaryTemplates.normalizedStatus("진행 중"), SummaryTemplates.statusInProgress)
        XCTAssertEqual(SummaryTemplates.normalizedStatus("In Progress"), SummaryTemplates.statusInProgress)
        XCTAssertEqual(SummaryTemplates.normalizedStatus("완료됨"), SummaryTemplates.statusDone)
        XCTAssertEqual(SummaryTemplates.normalizedStatus(""), SummaryTemplates.statusWaiting)
        XCTAssertEqual(SummaryTemplates.normalizedStatus("몰라요"), SummaryTemplates.statusWaiting)
    }

    /// 구간마다 같은 결정이 반복되면 하나로 합치고, 뒤에 온 근거·결정자가 빈 칸을 메운다
    func testMergeDecisionsFillsBlanksAndDeduplicates() {
        let merged = SummaryTemplates.mergeDecisions([
            DecisionItem(content: "v2 채택", rationale: "", decider: "", revisitCondition: ""),
            DecisionItem(content: "v2 채택.", rationale: "성능이 30% 낫다",
                         decider: "박영희", revisitCondition: "3주 내 미달이면 롤백"),
            DecisionItem(content: "없음", rationale: "", decider: "", revisitCondition: ""),
        ])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].rationale, "성능이 30% 낫다")
        XCTAssertEqual(merged[0].decider, "박영희")
        XCTAssertEqual(SummaryTemplates.reconditionLines(merged),
                       ["재론 조건(D-1): 3주 내 미달이면 롤백"])
    }

    /// 보류 항목도 같은 방식으로 합쳐진다
    func testMergeOpenIssues() {
        let merged = SummaryTemplates.mergeOpenIssues([
            OpenIssue(item: "가격 정책", reason: "", revisitAt: ""),
            OpenIssue(item: "가격 정책", reason: "재무 검토 필요", revisitAt: "다음 주"),
        ])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].reason, "재무 검토 필요")
        XCTAssertEqual(merged[0].revisitAt, "다음 주")
    }

    /// 논점도 의견도 없는 안건은 제목만 남은 껍데기라 싣지 않는다
    func testCleanAgendaDropsEmptyItems() {
        let cleaned = SummaryTemplates.cleanAgenda([
            AgendaItem(title: "버전 선택", issue: "v1 vs v2",
                       opinions: ["화자 1 — v2가 낫다", "없음"], conclusion: "v2 채택"),
            AgendaItem(title: "빈 안건", issue: "", opinions: [], conclusion: ""),
            AgendaItem(title: "버전 선택!", issue: "중복", opinions: ["또"], conclusion: ""),
        ])
        XCTAssertEqual(cleaned.count, 1)
        XCTAssertEqual(cleaned[0].opinions, ["화자 1 — v2가 낫다"])
    }

    /// 안건 결론이 결정과 같은 내용일 때만 D-n을 붙인다 — 없는 연결을 지어내지 않는다
    func testDecisionReferenceOnlyWhenItActuallyMatches() {
        let decisions = [
            DecisionItem(content: "온보딩 개편 보류", rationale: "", decider: "", revisitCondition: ""),
            DecisionItem(content: "v2 채택", rationale: "", decider: "", revisitCondition: ""),
        ]
        XCTAssertEqual(SummaryTemplates.decisionReference(for: "v2 채택", in: decisions), "D-2")
        XCTAssertNil(SummaryTemplates.decisionReference(for: "결론 없이 보류", in: decisions))
        XCTAssertNil(SummaryTemplates.decisionReference(for: "", in: decisions))
    }

    /// 장소·불참은 말이 나온 구간에서만 가져온다 — 없으면 빈 문자열이라 화면에서 줄째로 빠진다
    func testFirstFilledSkipsPlaceholders() {
        XCTAssertEqual(SummaryTemplates.firstFilled(["", "미정", "3층 회의실", "1층"]), "3층 회의실")
        XCTAssertEqual(SummaryTemplates.firstFilled(["", "없음"]), "")
    }

    /// 내보내기용 평문 섹션 — 번호와 재론 조건이 그대로 들어간다
    func testExportSectionsRenderTemplateNumbering() {
        let sections = SummaryTemplates.exportSections(
            briefing: ["결제 개편을 9월로 확정했다"],
            decisions: [DecisionItem(content: "v2 채택", rationale: "성능",
                                     decider: "박영희", revisitCondition: "미달 시 롤백")],
            agenda: [AgendaItem(title: "버전 선택", issue: "v1 vs v2",
                                opinions: ["화자 1 — v2가 낫다"], conclusion: "v2 채택")],
            openIssues: [OpenIssue(item: "가격 정책", reason: "재무 검토", revisitAt: "다음 주")])

        XCTAssertEqual(sections.map(\.title),
                       [SummaryTemplates.briefingTitle, SummaryTemplates.decisionsTitle,
                        SummaryTemplates.agendaTitle, SummaryTemplates.parkingLotTitle])
        let decisionBullets = sections[1].bullets
        XCTAssertTrue(decisionBullets[0].hasPrefix("D-1"))
        XCTAssertTrue(decisionBullets[0].contains("결정자: 박영희"))
        XCTAssertEqual(decisionBullets.last, "재론 조건(D-1): 미달 시 롤백")
        XCTAssertTrue(sections[2].bullets.contains("안건 1. 버전 선택"))
        XCTAssertTrue(sections[2].bullets.contains("결론: v2 채택 → D-1"))
        XCTAssertTrue(sections[3].bullets[0].hasPrefix("P-1"))
    }

    /// 비어 있는 표는 섹션째 만들지 않는다
    func testExportSectionsSkipEmptyTables() {
        let sections = SummaryTemplates.exportSections(briefing: [], decisions: [],
                                                       agenda: [], openIssues: [])
        XCTAssertTrue(sections.isEmpty)
    }

    /// 불릿 정리 — 자리표시자·중복 제거 후 상한 적용
    func testCleanBullets() {
        let bullets = ["없음", "로드맵 우선순위 검토", "로드맵 우선순위 검토!", "온보딩 개선", "  "]
        XCTAssertEqual(SummaryTemplates.cleanBullets(bullets),
                       ["로드맵 우선순위 검토", "온보딩 개선"])
        XCTAssertEqual(SummaryTemplates.cleanBullets(bullets, minLength: 8),
                       ["로드맵 우선순위 검토"])
        XCTAssertEqual(SummaryTemplates.cleanBullets(bullets, limit: 1), ["로드맵 우선순위 검토"])
    }

    // MARK: - 헬퍼

    // MARK: - 근거 대조 (#21)

    /// 실제 사고 재현: 영어 발음·취미 잡담 4분 회의의 브리핑에
    /// 지시문 예시였던 "메모리는 배치 저장으로…"가 통째로 실려 나왔다
    func testGroundedDropsSentenceUnrelatedToDigests() {
        let source = SummaryTemplates.digestText([
            digest(topic: "영어 발음과 취미",
                   points: ["화자 1 — 영어 발음이 좋아서 흥미로웠다.",
                            "화자 2 — 두 분의 취미도 비슷하다.",
                            "화자 1 — 최근에 본 영화 이야기를 꺼냈다."]),
        ])
        let lines = [
            "영어 발음이 좋다는 이야기로 시작해 서로의 취미가 비슷하다는 걸 확인했다.",
            "메모리는 배치 저장으로 가기로 하고, 스프링 제작은 다음 주로 미뤘다.",
        ]
        let kept = SummaryTemplates.grounded(lines, in: source)
        XCTAssertEqual(kept, [lines[0]])
    }

    /// 요지를 바꿔 쓴 문장은 살아남아야 한다 — 과하게 거르면 브리핑이 통째로 빈다
    func testGroundedKeepsParaphrase() {
        let source = SummaryTemplates.digestText([
            digest(topic: "배치 저장 전환",
                   points: ["김택현 — 메모리 문제는 배치 저장으로 풀자고 했다.",
                            "박서준 — 스프링 제작은 다음 주로 미루자고 했다."]),
        ])
        let line = "메모리는 배치 저장으로 가기로 하고, 스프링 제작은 다음 주로 미뤘다."
        XCTAssertEqual(SummaryTemplates.grounded([line], in: source), [line])
    }

    /// 요지가 비어 있으면 대조할 근거가 없다 — 그때는 거르지 않는다
    func testGroundedPassesThroughWhenSourceIsEmpty() {
        let lines = ["아무 문장이나"]
        XCTAssertEqual(SummaryTemplates.grounded(lines, in: ""), lines)
    }

    func testDigestTextGathersEveryField() {
        let text = SummaryTemplates.digestText([
            ChunkDigest(topic: "주제어", points: ["요지 문장"],
                        decisions: [DecisionItem(content: "결정 내용", rationale: "",
                                                 decider: "", revisitCondition: "")],
                        actionItems: [action("할 일 문장을 쓴다")],
                        openIssues: [OpenIssue(item: "보류 항목", reason: "", revisitAt: "")],
                        place: "", absentees: ""),
        ])
        for piece in ["주제어", "요지 문장", "결정 내용", "할 일 문장을 쓴다", "보류 항목"] {
            XCTAssertTrue(text.contains(piece), "\(piece)가 빠졌다")
        }
    }

    /// 지시문에 값으로 새어 나갈 예시 문장이 남아 있으면 안 된다
    func testInstructionsCarryNoSampleSentences() {
        for instructions in [SummaryTemplates.mapInstructions,
                             SummaryTemplates.reduceInstructions] {
            XCTAssertFalse(instructions.contains("Good:"), "예시 문장이 남아 있다")
            XCTAssertFalse(instructions.contains("Bad:"), "예시 문장이 남아 있다")
            XCTAssertFalse(instructions.contains("e.g."), "예시 문장이 남아 있다")
        }
    }

    private func digest(topic: String,
                        points: [String],
                        decisions: [DecisionItem] = []) -> ChunkDigest {
        ChunkDigest(topic: topic, points: points, decisions: decisions,
                    actionItems: [], openIssues: [], place: "", absentees: "")
    }

    private func action(_ task: String,
                        assignee: String = "",
                        due: String = "",
                        status: String = "대기") -> ActionItem {
        ActionItem(task: task, assignee: assignee, due: due, status: status)
    }
}
