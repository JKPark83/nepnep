import FoundationModels

/// Foundation Models @Generable 출력 스키마 (05-m3 §2, #21 개편)
///
/// 지시문은 영어로 쓰고 값만 한국어로 받는다 — 온디바이스 모델이 영어 지시를 더
/// 안정적으로 따르고, 지시문 자체가 값으로 새어 나오는 사고도 줄어든다.
/// 할 일은 예전에 "내용|담당자|기한" 파이프 문자열로 받았는데, 모델이 그 형식
/// 문자열을 값으로 그대로 뱉는 사고가 반복돼 중첩 구조체로 바꿨다.
///
/// 회의록 템플릿을 표 형태로 넓히면서(#21 후속) 모델 호출 수는 그대로 뒀다.
/// 결정·할 일·보류는 map 단계에서 이미 구간별로 뽑히므로, reduce에 다시 물어보는 대신
/// SummaryTemplates에서 병합한다. 모델에게는 서술이 필요한 것만 맡긴다.

/// 결정 사항 한 줄 — 근거·결정자·재론 조건은 전사에 명시됐을 때만 채운다
@Generable
struct DecisionItem: Codable {
    @Guide(description: "What was decided, in one short Korean sentence.")
    var content: String
    @Guide(description: "Why it was decided that way, only if the transcript states it. Otherwise an empty string.")
    var rationale: String
    @Guide(description: "Who made the call, only if the transcript names them. Otherwise an empty string.")
    var decider: String
    @Guide(description: "The condition under which this decision would be revisited, only if the transcript states one. Otherwise an empty string.")
    var revisitCondition: String
}

/// 할 일 — 담당자·기한은 전사에 명시됐을 때만 채우고, 없으면 빈 문자열
@Generable
struct ActionItem: Codable {
    @Guide(description: "One concrete task as a full Korean sentence saying who does what. A bare noun phrase is not a task.")
    var task: String
    @Guide(description: "Owner's real name, only if the transcript explicitly assigns it. Never a generic speaker label. Otherwise an empty string.")
    var assignee: String
    @Guide(description: "Deadline such as a date or a week, only if the transcript explicitly states one. Never a status word. Otherwise an empty string.")
    var due: String
    @Guide(description: "Exactly one of 완료, 진행중, 대기. Use 대기 when the transcript gives no sign of progress.")
    var status: String
}

/// 보류·미결 (Parking Lot) — 결론 없이 다음으로 넘어간 것
@Generable
struct OpenIssue: Codable {
    @Guide(description: "The unresolved item, in a short Korean noun phrase.")
    var item: String
    @Guide(description: "Why it was left unresolved, in a short Korean phrase.")
    var reason: String
    @Guide(description: "When it will be revisited, only if the transcript states it. Otherwise an empty string.")
    var revisitAt: String
}

/// 안건 하나의 논의 (논점 / 의견 / 결론)
@Generable
struct AgendaItem: Codable {
    @Guide(description: "Agenda title in 20 Korean characters or fewer. A noun phrase, not a sentence.")
    var title: String
    @Guide(description: "The question actually at stake, in one Korean sentence. Often 'A vs B' shaped.")
    var issue: String
    @Guide(description: "2 to 4 Korean sentences on what was argued. Start each with the speaker's name and a dash.")
    var opinions: [String]
    @Guide(description: "How this agenda landed, in one Korean sentence. Say 결론 없이 보류 when nothing was settled.")
    var conclusion: String
}

/// map 단계 — 청크별 요지.
/// 화자별 요지 배열은 걷어내고 points 문장이 직접 발언자를 달게 했다. 화자별 섹션이
/// 안건별 논의로 대체돼 쓸 곳이 없어졌고, 출력이 줄어야 컨텍스트 한도에 여유가 생긴다.
@Generable
struct ChunkDigest: Codable {
    @Guide(description: "What this segment was about, in 20 Korean characters or fewer. A noun phrase.")
    var topic: String
    @Guide(description: "3 to 5 short Korean sentences on what was discussed. Start each with the speaker's name and a dash.")
    var points: [String]
    @Guide(description: "Only conclusions the participants actually agreed on or confirmed. Empty array if none.")
    var decisions: [DecisionItem]
    @Guide(description: "Only tasks someone was actually asked to do. Empty array if none.")
    var actionItems: [ActionItem]
    @Guide(description: "Items explicitly left for later without a conclusion. Empty array if none.")
    var openIssues: [OpenIssue]
    @Guide(description: "Where the meeting is held, only if someone says it out loud in this segment. Otherwise an empty string.")
    var place: String
    @Guide(description: "Names mentioned as absent from this meeting, comma separated. Empty string if nobody is mentioned as absent.")
    var absentees: String
}

/// reduce 단계 — 서술부만. 표(결정·할 일·보류)는 digest에서 코드가 병합한다.
@Generable
struct FinalSummary {
    @Guide(description: "The meeting's topic in Korean, 20 characters or fewer. No date, and never the word 회의.")
    var title: String
    @Guide(description: "One Korean sentence, 60 characters or fewer, on what the meeting was about and where it landed.")
    var oneLiner: String
    @Guide(description: "At most 3 complete Korean sentences. Each states one thing that was settled or changed, with its number or date when there is one. Never a bare word or number.")
    var briefing: [String]
    @Guide(description: "The meeting's agendas in the order they came up, merged so the same agenda never appears twice.")
    var agenda: [AgendaItem]
}
