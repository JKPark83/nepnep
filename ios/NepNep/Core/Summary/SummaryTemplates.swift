import Foundation

/// 요약 프롬프트와 후처리 (05-m3 §2, #21 개편)
///
/// 프롬프트 원칙:
/// - 모델 지시문은 영어, 값은 한국어. 온디바이스 모델이 영어 지시를 더 안정적으로
///   따르고, 지시문이 값으로 새어 나오는 사고도 줄어든다. 대신 "출력은 예외 없이
///   한국어" 제약을 map·reduce 양쪽에 못 박는다.
/// - 회의 유형은 일반 하나뿐이라 템플릿 분기가 없다 (#21).
/// - 모델 지시만 믿지 않는다. 개수 제한·자리표시자 제거·중복 제거는 후처리에서
///   한 번 더 강제한다. 실제로 "내용|담당자|기한"을 값으로 뱉어 할 일이 46개
///   생성된 사고가 있었다.
/// - 회의록 표(결정·할 일·보류)는 reduce에 다시 묻지 않고 구간 요지에서 병합한다.
///   모델 호출을 늘리면 요청 제한에 그대로 걸리고, 병합·중복 제거는 코드가 더 잘한다.
enum SummaryTemplates {
    /// 회의록 섹션 제목 — 화면과 내보내기가 같은 문구를 쓴다
    static let briefingTitle = "세 줄 브리핑"
    static let decisionsTitle = "1. 결정 사항"
    static let actionItemsTitle = "2. 액션 아이템"
    static let agendaTitle = "3. 논의 내용"
    static let parkingLotTitle = "4. 보류·미결"

    /// 할 일 상한 — 지시문에도 넣지만 코드에서 한 번 더 자른다
    static let maxActionItems = 10
    /// 결정 사항 상한
    static let maxDecisions = 8
    /// 보류·미결 상한
    static let maxOpenIssues = 6
    /// 안건 상한 — 구간이 18개여도 안건이 18개일 리는 없다
    static let maxAgendaItems = 6
    /// 브리핑 줄 수
    static let briefingLines = 3

    /// 할 일 상태 — 이 셋 밖의 값이 오면 대기로 떨어뜨린다
    static let statusDone = "완료"
    static let statusInProgress = "진행중"
    static let statusWaiting = "대기"
    static var allowedStatuses: [String] { [statusDone, statusInProgress, statusWaiting] }

    // MARK: - instructions

    /// map(청크 요지) 단계 — 사실 추출만. 요약·해석·보충 금지.
    static let mapInstructions = """
        You are extracting facts from one segment of a Korean meeting transcript.

        Rules:
        - Write every output value in Korean. Never write English in any field, except for the proper nouns listed in the prompt — those keep the spelling given there.
        - Use only what is actually said in the segment. Never invent, infer, or fill gaps.
        - topic: what this segment is about, as a short Korean noun phrase.
        - points: 3 to 5 short Korean sentences. Begin each with the speaker's name and a \
        dash, using the speaker names listed in the prompt exactly as written. Never create \
        a new name.
        - decisions: only conclusions the participants actually agreed on or confirmed. \
        Something that was merely discussed is not a decision. Leave rationale, decider, \
        and revisitCondition as an empty string unless the segment states them. \
        Empty array if none.
        - actionItems: only tasks someone was actually asked to do, each written as a full \
        Korean sentence naming who does what. A bare noun phrase naming a topic is not a task. \
        Fill assignee and due only when the transcript states them; otherwise leave them as \
        an empty string. Never put a status word in the due field, and never put a generic \
        speaker label in assignee. \
        status must be exactly 완료, 진행중, or 대기.
        - openIssues: only items the participants explicitly put off without concluding.
        - place and absentees: fill these only when someone says them out loud. This is \
        almost always an empty string. Never guess a location from the topic.
        - Never output placeholder words such as 내용, 담당자, 기한, 미정, 없음, TBD. \
        When you have no value, output an empty string or an empty array instead.
        - Prefer leaving an array empty over filling it with something weak. A short \
        segment where nothing was settled should return empty decisions, actionItems, \
        and openIssues. Empty is a correct answer.
        """

    /// reduce(최종 요약) 단계 — 구간 요지를 회의 전체 관점으로 합친다.
    /// 표는 코드가 병합하므로 여기서는 묻지 않는다.
    static let reduceInstructions = """
        You are writing the narrative part of a Korean meeting's minutes from per-segment digests.

        Rules:
        - Write every output value in Korean. Never write English in any field, except for the proper nouns listed in the prompt — those keep the spelling given there.
        - Use only the information in the digests. Never invent anything.
        - title: the meeting's topic in 20 Korean characters or fewer. No date, and never \
        the word 회의.
        - oneLiner: one Korean sentence of 60 characters or fewer on what the meeting was \
        about and where it landed.
        - briefing: at most 3 Korean sentences, each a complete sentence of at least 20 \
        characters. Each one states what was settled or what changed. A sentence whose only \
        content is that a topic came up does not belong here. \
        Carry the number or date when the digests give one. Write 2 sentences rather than \
        padding to 3 with a sentence that says nothing. \
        Build every sentence from the digests above. Never copy wording from these rules.
        - agenda: group the segments into the agendas the meeting actually worked through. \
        Consecutive segments about the same thing are one agenda, not several. \
        For each agenda write issue as the question at stake, opinions as 2 to 4 sentences \
        that each begin with a speaker's name and a dash, and conclusion as how it landed. \
        When an agenda ended without a conclusion, write 결론 없이 보류 in conclusion. \
        Drop an agenda entirely when all you can say about it is that it was mentioned.
        - Never output placeholder words such as 내용, 담당자, 기한, 미정, 없음, TBD, and \
        never output a bare number or a single word as a sentence. \
        When you have no value, output an empty string or an empty array instead.
        - A short, honest summary beats a padded one. Leave a field empty rather than \
        filling it with a sentence that carries no information.
        """

    // MARK: - 프롬프트 조립

    /// map 단계 프롬프트 — 화자 명단을 함께 주어 없는 화자를 지어내지 못하게 한다
    static func mapPrompt(chunkText: String,
                          speakers: [String],
                          glossary: [String] = []) -> String {
        """
        \(speakerRoster(speakers))
        \(glossaryNote(glossary))

        Transcript segment:

        \(chunkText)
        """
    }

    /// reduce 단계 프롬프트 — digest 모음을 텍스트로 병합.
    /// 결정·할 일·보류는 코드가 따로 병합하므로 문맥용으로만 짧게 얹는다.
    static func reducePrompt(digests: [ChunkDigest],
                             speakers: [String],
                             glossary: [String] = []) -> String {
        var lines = [speakerRoster(speakers), glossaryNote(glossary), "", "Segment digests:"]
        for (i, digest) in digests.enumerated() {
            lines.append("\n[구간 \(i + 1)] \(digest.topic)")
            if !digest.points.isEmpty {
                lines.append(digest.points.joined(separator: "\n"))
            }
            if !digest.decisions.isEmpty {
                lines.append("결정: " + digest.decisions.map(\.content).joined(separator: " / "))
            }
        }
        return lines.joined(separator: "\n")
    }

    /// 컨텍스트 한도를 넘었을 때 digest들을 한 덩어리로 압축하는 프롬프트
    static func compressPrompt(digests: [ChunkDigest],
                               speakers: [String],
                               glossary: [String] = []) -> String {
        reducePrompt(digests: digests, speakers: speakers, glossary: glossary)
            + "\n\nMerge these segment digests into one digest with no duplicates, "
            + "keeping every speaker attribution. Keep writing in Korean."
    }

    private static func speakerRoster(_ speakers: [String]) -> String {
        guard !speakers.isEmpty else { return "Speakers: (unknown)" }
        return "Speakers (use these names exactly): " + speakers.joined(separator: ", ")
    }

    /// 사용자가 등록해 둔 용어 (#21 후속).
    ///
    /// 전사기가 고유명사를 흘려 들으면 원문에는 "카프가"처럼 남는다. 여기서
    /// 올바른 표기를 알려 주면 요약 쪽에서라도 제대로 적힌다.
    ///
    /// 영어 용어는 등록 표기와 무관하게 알파벳으로 적게 한다. 한국어 회의에서
    /// 영어 단어는 소리 나는 대로 발음되므로 전사에는 "래디스"로 남는데, 요약에
    /// 그대로 두면 읽는 사람이 무슨 말인지 알 수 없다. `Redis`로 등록하든
    /// `레디스`로 등록하든 결과는 `Redis`여야 한다 — 덕분에 같은 용어를 두 표기로
    /// 등록해 둬도 서로 부딪히지 않는다.
    ///
    /// 다만 목록을 그냥 던지면 모델이 원문에 없는 용어까지 끌어다 쓰므로,
    /// "전사에 대응되는 말이 있을 때만"을 같은 줄에서 못 박는다 — 지시문 예시가
    /// 그대로 요약에 실린 사고가 있었다.
    private static func glossaryNote(_ terms: [String]) -> String {
        guard !terms.isEmpty else { return "" }
        return "Known proper nouns for this meeting: " + terms.joined(separator: ", ")
            + ". The transcript may spell these wrong, and it writes English terms the way "
            + "they sound in Korean. When a word in the transcript is clearly one of them, "
            + "write it using the spelling above. When the term is an English word, always "
            + "write it in the Latin alphabet, even when the transcript spells it in Hangul "
            + "and even when the list above spells it in Hangul. "
            + "Never introduce one of these terms where the transcript has no matching word."
    }

    // MARK: - 후처리

    /// 모델이 값 대신 뱉는 자리표시자들. 이게 그대로 저장돼 할 일이 "내용 / 미정"으로 가득 찼었다.
    private static let placeholders: Set<String> = [
        "내용", "할 일", "할일", "담당자", "기한", "미정", "없음", "해당 없음", "없다",
        "미상", "불명", "언급 없음", "정보 없음", "tbd", "n/a", "na", "none", "-", "—",
    ]

    /// 자리표시자이거나 사실상 빈 값인지
    static func isPlaceholder(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        return placeholders.contains(trimmed.lowercased())
    }

    /// 자리표시자면 빈 문자열로 떨어뜨린다 — 선택 항목(근거·결정자·기한)용
    static func optional(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return isPlaceholder(trimmed) ? "" : trimmed
    }

    /// 담당자·기한 칸 정리 (#21).
    /// 모델이 기한 칸에 "완료"를 적어 상태 배지가 두 번 붙는 일이 있었고, 담당자에는
    /// 이름 대신 "화자 4" 같은 기본 딱지가 들어왔다. 둘 다 값이 아니라 빈 칸으로 본다.
    static func detail(_ value: String) -> String {
        let trimmed = optional(value)
        guard !trimmed.isEmpty else { return "" }
        if allowedStatuses.contains(where: { normalized(trimmed) == normalized($0) }) { return "" }
        if isDefaultSpeakerLabel(trimmed) { return "" }
        return trimmed
    }

    /// "화자 4"처럼 사용자가 아직 이름을 지정하지 않은 기본 딱지인지
    static func isDefaultSpeakerLabel(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("화자") else { return false }
        let rest = trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)
        return rest.isEmpty || rest.allSatisfy(\.isNumber)
    }

    /// 사람이 읽어서 뜻이 남는 값인지 (#21).
    /// 모델이 브리핑 한 줄로 "1"만 뱉거나, 할 일로 두 어절짜리 주제어를 올리는 일이 있었다.
    /// 글자가 하나도 없거나 너무 짧으면 요약이 아니라 부스러기로 본다.
    static func isMeaningful(_ text: String, minLength: Int) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isPlaceholder(trimmed) else { return false }
        guard trimmed.contains(where: \.isLetter) else { return false }
        return trimmed.count >= minLength
    }

    /// 브리핑·의견처럼 문장이어야 하는 값의 최소 길이
    static let minSentenceLength = 12
    /// 할 일의 최소 길이 — "페르소나 유지" 같은 주제어가 할 일로 올라오던 문제 (#21)
    static let minPhraseLength = 8
    /// 결정·보류의 최소 길이. "v2 채택"처럼 짧아도 진짜인 값이 있어 낮게 잡는다 —
    /// 여기서 과하게 거르면 회의록에서 제일 중요한 줄이 사라진다.
    static let minLabelLength = 4

    /// 브리핑이 구간 요지에 실제로 뿌리내렸는지 (#21).
    ///
    /// 잡담처럼 정리할 게 없는 회의에서 모델이 지시문에 있던 예시 문장을 통째로
    /// 옮겨 적는 사고가 있었다 — 영어 발음 이야기를 4분 한 회의의 브리핑에
    /// "메모리는 배치 저장으로 가기로 하고…"가 실렸다. 지시문 예시는 걷어냈지만,
    /// 채울 내용이 없을 때 아무 문장이나 지어내는 성향 자체는 남는다.
    /// 지어낸 문장은 요지와 글자가 거의 겹치지 않으므로 겹침 비율로 걸러 낸다.
    static func grounded(_ lines: [String],
                         in source: String,
                         minOverlap: Double = 0.25) -> [String] {
        let sourceGrams = bigrams(source)
        guard !sourceGrams.isEmpty else { return lines }
        return lines.filter { line in
            let grams = bigrams(line)
            guard !grams.isEmpty else { return false }
            let shared = grams.filter(sourceGrams.contains).count
            return Double(shared) / Double(grams.count) >= minOverlap
        }
    }

    /// 글자 2-gram — 한국어는 조사·어미가 붙어 단어 단위 비교가 잘 맞지 않는다
    private static func bigrams(_ text: String) -> Set<String> {
        let chars = Array(text.lowercased().filter { $0.isLetter || $0.isNumber })
        guard chars.count >= 2 else { return [] }
        return Set((0..<(chars.count - 1)).map { String(chars[$0...($0 + 1)]) })
    }

    /// 근거 대조용 원문 — 구간 요지를 한 덩어리로
    static func digestText(_ digests: [ChunkDigest]) -> String {
        var parts: [String] = []
        for digest in digests {
            parts.append(digest.topic)
            parts.append(contentsOf: digest.points)
            parts.append(contentsOf: digest.decisions.map(\.content))
            parts.append(contentsOf: digest.actionItems.map(\.task))
            parts.append(contentsOf: digest.openIssues.map(\.item))
        }
        return parts.joined(separator: " ")
    }

    /// 불릿 정리 — 부스러기·자리표시자 제거, 중복 제거, 개수 제한
    static func cleanBullets(_ bullets: [String],
                             limit: Int? = nil,
                             minLength: Int = minLabelLength) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for bullet in bullets {
            let trimmed = bullet.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isMeaningful(trimmed, minLength: minLength),
                  seen.insert(normalized(trimmed)).inserted else { continue }
            result.append(trimmed)
            if let limit, result.count >= limit { break }
        }
        return result
    }

    /// 결정 사항 병합 — 구간마다 같은 결정을 다시 적는 일이 잦아 내용 기준으로 합친다.
    /// 뒤에 온 것이 근거·결정자를 더 채웠으면 빈 칸만 메운다.
    static func mergeDecisions(_ items: [DecisionItem],
                               limit: Int = maxDecisions) -> [DecisionItem] {
        var order: [String] = []
        var merged: [String: DecisionItem] = [:]
        for item in items {
            let content = item.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isMeaningful(content, minLength: minLabelLength) else { continue }
            let key = normalized(content)
            if var existing = merged[key] {
                if existing.rationale.isEmpty { existing.rationale = optional(item.rationale) }
                if existing.decider.isEmpty { existing.decider = optional(item.decider) }
                if existing.revisitCondition.isEmpty {
                    existing.revisitCondition = optional(item.revisitCondition)
                }
                merged[key] = existing
            } else {
                order.append(key)
                merged[key] = DecisionItem(content: content,
                                           rationale: optional(item.rationale),
                                           decider: optional(item.decider),
                                           revisitCondition: optional(item.revisitCondition))
            }
        }
        return order.prefix(limit).compactMap { merged[$0] }
    }

    /// 할 일 정리 — 자리표시자 제거, 중복 제거, 상태 정규화, 상한 적용
    static func cleanActionItems(_ items: [ActionItem],
                                 limit: Int = maxActionItems) -> [ActionItem] {
        var seen = Set<String>()
        var result: [ActionItem] = []
        for item in items {
            let task = item.task.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isMeaningful(task, minLength: minPhraseLength),
                  seen.insert(normalized(task)).inserted else { continue }
            result.append(ActionItem(task: task,
                                     assignee: detail(item.assignee),
                                     due: detail(item.due),
                                     status: normalizedStatus(item.status)))
            if result.count >= limit { break }
        }
        return result
    }

    /// 모델이 "진행 중", "in progress", "완료됨" 같은 변주를 뱉어도 세 값 안으로 밀어 넣는다
    static func normalizedStatus(_ raw: String) -> String {
        let value = normalized(raw)
        if value.isEmpty { return statusWaiting }
        if value.contains("완료") || value.contains("done") { return statusDone }
        if value.contains("진행") || value.contains("progress") { return statusInProgress }
        return statusWaiting
    }

    /// 보류·미결 병합 — 항목 기준으로 합치고 빈 칸만 메운다
    static func mergeOpenIssues(_ issues: [OpenIssue],
                                limit: Int = maxOpenIssues) -> [OpenIssue] {
        var order: [String] = []
        var merged: [String: OpenIssue] = [:]
        for issue in issues {
            let item = issue.item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isMeaningful(item, minLength: minLabelLength) else { continue }
            let key = normalized(item)
            if var existing = merged[key] {
                if existing.reason.isEmpty { existing.reason = optional(issue.reason) }
                if existing.revisitAt.isEmpty { existing.revisitAt = optional(issue.revisitAt) }
                merged[key] = existing
            } else {
                order.append(key)
                merged[key] = OpenIssue(item: item,
                                        reason: optional(issue.reason),
                                        revisitAt: optional(issue.revisitAt))
            }
        }
        return order.prefix(limit).compactMap { merged[$0] }
    }

    /// 안건 정리 — 제목이 같은 안건을 합치고, 빈 안건은 버린다
    static func cleanAgenda(_ items: [AgendaItem],
                            limit: Int = maxAgendaItems) -> [AgendaItem] {
        var seen = Set<String>()
        var result: [AgendaItem] = []
        for item in items {
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let opinions = cleanBullets(item.opinions, minLength: minSentenceLength)
            let issue = optional(item.issue)
            guard !isPlaceholder(title), seen.insert(normalized(title)).inserted else { continue }
            // 의견이 하나도 안 남으면 안건이라 부를 게 없다 — 제목과 논점만으로는
            // "무슨 이야기가 나왔다"는 말만 남아 실을 값이 없다 (#21)
            guard !opinions.isEmpty else { continue }
            result.append(AgendaItem(title: title,
                                     issue: issue,
                                     opinions: opinions,
                                     conclusion: optional(item.conclusion)))
            if result.count >= limit { break }
        }
        return result
    }

    /// 안건 결론이 결정 사항 중 하나와 같은 내용이면 "→ D-2"를 붙여 준다.
    /// 겹치는 것이 없으면 아무것도 붙이지 않는다 — 없는 연결을 지어내는 것보다 낫다.
    static func decisionReference(for conclusion: String,
                                  in decisions: [DecisionItem]) -> String? {
        let target = normalized(conclusion)
        guard !target.isEmpty else { return nil }
        for (i, decision) in decisions.enumerated() {
            let content = normalized(decision.content)
            guard content.count >= 4 else { continue }
            if target.contains(content) || content.contains(target) {
                return "D-\(i + 1)"
            }
        }
        return nil
    }

    /// "재론 조건: …" 주석 줄 — 조건이 달린 결정에만 붙는다.
    /// 조건을 말한 결정이 하나도 없으면 줄 자체가 없다.
    static func reconditionLines(_ decisions: [DecisionItem]) -> [String] {
        decisions.enumerated().compactMap { i, decision in
            decision.revisitCondition.isEmpty
                ? nil : "재론 조건(D-\(i + 1)): \(decision.revisitCondition)"
        }
    }

    /// 구간마다 흩어져 들어온 값 중 처음 채워진 것 하나 — 장소·불참자용
    static func firstFilled(_ values: [String]) -> String {
        values.map(optional).first { !$0.isEmpty } ?? ""
    }

    // MARK: - 내보내기용 평문 섹션

    /// 표를 [SummarySection]으로 펴 준다.
    /// PDF·Notion·Google Docs·텍스트 내보내기가 전부 이 한 모양만 읽으므로,
    /// 회의록 구조가 바뀌어도 내보내기 쪽은 손대지 않는다.
    static func exportSections(briefing: [String],
                               decisions: [DecisionItem],
                               agenda: [AgendaItem],
                               openIssues: [OpenIssue]) -> [SummarySection] {
        var sections: [SummarySection] = []
        if !briefing.isEmpty {
            sections.append(SummarySection(title: briefingTitle, bullets: briefing))
        }
        if !decisions.isEmpty {
            var bullets = decisions.enumerated().map { i, decision -> String in
                var line = "D-\(i + 1)  \(decision.content)"
                if !decision.rationale.isEmpty { line += " · 근거: \(decision.rationale)" }
                if !decision.decider.isEmpty { line += " · 결정자: \(decision.decider)" }
                return line
            }
            bullets.append(contentsOf: reconditionLines(decisions))
            sections.append(SummarySection(title: decisionsTitle, bullets: bullets))
        }
        if !agenda.isEmpty {
            var bullets: [String] = []
            for (i, item) in agenda.enumerated() {
                bullets.append("안건 \(i + 1). \(item.title)")
                if !item.issue.isEmpty { bullets.append("논점: \(item.issue)") }
                for opinion in item.opinions { bullets.append("의견: \(opinion)") }
                if !item.conclusion.isEmpty {
                    let reference = decisionReference(for: item.conclusion, in: decisions)
                    bullets.append("결론: \(item.conclusion)"
                                   + (reference.map { " → \($0)" } ?? ""))
                }
            }
            sections.append(SummarySection(title: agendaTitle, bullets: bullets))
        }
        if !openIssues.isEmpty {
            sections.append(SummarySection(
                title: parkingLotTitle,
                bullets: openIssues.enumerated().map { i, issue in
                    var line = "P-\(i + 1)  \(issue.item)"
                    if !issue.reason.isEmpty { line += " · 사유: \(issue.reason)" }
                    if !issue.revisitAt.isEmpty { line += " · 재논의: \(issue.revisitAt)" }
                    return line
                }))
        }
        return sections
    }

    /// 중복 판정용 정규화 — 공백·문장부호·대소문자 차이는 같은 문장으로 본다
    private static func normalized(_ text: String) -> String {
        text.lowercased().unicodeScalars.filter {
            !CharacterSet.whitespacesAndNewlines.contains($0)
                && !CharacterSet.punctuationCharacters.contains($0)
        }.reduce(into: "") { $0.unicodeScalars.append($1) }
    }
}
