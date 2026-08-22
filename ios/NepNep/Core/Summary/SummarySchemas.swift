import FoundationModels

/// Foundation Models @Generable 출력 스키마 (05-m3 §2)

/// map 단계 — 청크별 요지
@Generable
struct ChunkDigest: Codable {
    @Guide(description: "이 구간의 핵심 논의 3~5개, 한국어 한 문장씩")
    var points: [String]
    @Guide(description: "구간에서 결정된 사항, 없으면 빈 배열")
    var decisions: [String]
    @Guide(description: "할 일. '내용|담당자|기한' 형태, 담당자·기한을 모르면 빈칸으로 둔다")
    var actionItems: [String]
}

/// reduce 단계 — 최종 요약
@Generable
struct FinalSummary {
    @Guide(description: "회의 전체 한 줄 요약, 한국어 60자 이내")
    var oneLiner: String
    @Guide(description: "주요 논의 불릿 3~6개, 한국어 한 문장씩")
    var keyPoints: [String]
    @Guide(description: "결정사항 불릿, 없으면 빈 배열")
    var decisions: [String]
    @Guide(description: "할 일. '내용|담당자|기한' 형태, 담당자·기한을 모르면 빈칸으로 둔다")
    var actionItems: [String]
}
