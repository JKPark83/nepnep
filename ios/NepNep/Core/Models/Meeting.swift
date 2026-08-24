import Foundation
import SwiftData

/// 회의 유형 — 일반 회의 하나만 남겼다 (#21).
/// 유형별 프롬프트를 4종 유지하면 손볼 때마다 비용이 4배가 되는데, 정작 일반 회의
/// 품질부터 부족해서 general 하나에 집중하기로 했다. 저장돼 있던 oneOnOne 등
/// legacy rawValue는 `Meeting.type`의 `?? .general` 폴백이 흡수한다.
enum MeetingType: String, CaseIterable, Codable {
    case general

    var displayName: String { "일반" }

    static var defaultType: MeetingType { .general }
}

enum MeetingStatus: String, Codable {
    case recording
    case recorded      // 녹음 종료·복구됨, 파이프라인 미시작 (M2 전 임시 종착 상태)
    /// 워치에서 녹음은 끝났지만 오디오가 아직 아이폰에 도착하지 않음.
    /// 자리표시자로 목록에 먼저 나타나고, 파일이 오면 processing으로 넘어간다.
    case pendingTransfer
    case processing
    case done
    case failed

    /// 워치 목록에 내려보낼 표시 문자열 (홈 카드 배지와 같은 문구)
    var watchDisplayText: String {
        switch self {
        case .processing: return "처리 중"
        case .done: return "완료"
        case .failed: return "실패"
        case .pendingTransfer: return "전송 대기 중"
        case .recorded, .recording: return "녹음됨"
        }
    }
}

@Model
final class Meeting {
    @Attribute(.unique) var id: UUID
    var title: String
    var typeRaw: String
    var createdAt: Date
    var duration: TimeInterval
    var statusRaw: String
    var processingStage: String?
    var processingProgress: Double
    var audioFileName: String?
    var audioSize: Int64
    var notionPageURL: String?
    var googleDocURL: String?
    var gapRanges: [GapRange]
    /// 처리 실패 원인 (03-m2 §4) — ProcessingFailureReason rawValue
    var failureReasonRaw: String?
    /// Foundation Models 비가용으로 요약을 건너뜀 (05-m3 §4) — 처리 전체는 성공 처리
    var summaryUnavailable: Bool = false
    /// 요약 실패 사유 한 줄 — 요약 카드에 그대로 보여준다 (#21).
    /// 실패 원인이 무엇이든 같은 문구만 나오던 문제를 없애기 위한 값.
    var summaryFailureReason: String?
    @Relationship(deleteRule: .cascade) var speakers: [Speaker]
    @Relationship(deleteRule: .cascade) var utterances: [Utterance]
    @Relationship(deleteRule: .cascade) var summary: Summary?

    init(id: UUID = UUID(),
         title: String,
         type: MeetingType,
         createdAt: Date = .now) {
        self.id = id
        self.title = title
        self.typeRaw = type.rawValue
        self.createdAt = createdAt
        self.duration = 0
        self.statusRaw = MeetingStatus.recording.rawValue
        self.processingStage = nil
        self.processingProgress = 0
        self.audioFileName = nil
        self.audioSize = 0
        self.notionPageURL = nil
        self.googleDocURL = nil
        self.gapRanges = []
        self.failureReasonRaw = nil
        self.summaryUnavailable = false
        self.summaryFailureReason = nil
        self.speakers = []
        self.utterances = []
        self.summary = nil
    }

    var type: MeetingType {
        get { MeetingType(rawValue: typeRaw) ?? .general }
        set { typeRaw = newValue.rawValue }
    }

    var status: MeetingStatus {
        get { MeetingStatus(rawValue: statusRaw) ?? .failed }
        set { statusRaw = newValue.rawValue }
    }

    /// "8월 22일 회의" 형태의 자동 제목 (와이어프레임 1c 노트 1).
    /// 유형이 하나뿐이라 유형명은 빼고 날짜만 쓴다 (#21).
    static func autoTitle(date: Date = .now) -> String {
        "\(monthDay(date)) 회의"
    }

    private static func monthDay(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ko_KR")
        fmt.dateFormat = "M월 d일"
        return fmt.string(from: date)
    }

    /// 요약이 뽑아낸 주제로 만든 "2026-08-22 - 킥오프 일정 조율" 형태의 제목.
    /// 주제가 비면 nil — 호출 측이 기존 제목을 유지한다.
    static func summaryTitle(topic: String, date: Date) -> String? {
        let trimmed = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return "\(isoDatePrefix(date))\(trimmed)"
    }

    /// 사용자가 직접 바꾸지 않은 제목인지 — 자동 제목이거나 이전 요약이 만든 제목.
    /// 후자를 포함해야 템플릿 변경 재요약에서 제목이 첫 요약 결과로 굳지 않는다.
    static func isAutoTitle(_ title: String, date: Date) -> Bool {
        if title == autoTitle(date: date) { return true }
        // 유형별 자동 제목을 쓰던 시절에 만들어진 회의도 자동 제목으로 인정한다 (#21)
        if legacyTypeNames.contains(where: { "\(monthDay(date)) \($0) 회의" == title }) {
            return true
        }
        return title.hasPrefix(isoDatePrefix(date))
    }

    private static let legacyTypeNames = ["일반", "1on1", "인터뷰", "스탠드업"]

    /// 제목은 정렬·검색·파일명으로 흘러가는 값이라 앱의 "M월 d일" 표기 대신 ISO를 쓴다
    private static func isoDatePrefix(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        return "\(fmt.string(from: date)) - "
    }
}

@Model
final class Speaker {
    @Attribute(.unique) var id: UUID
    var label: String          // "화자 1" …
    var customName: String?
    var colorIndex: Int

    init(id: UUID = UUID(), label: String, customName: String? = nil, colorIndex: Int) {
        self.id = id
        self.label = label
        self.customName = customName
        self.colorIndex = colorIndex
    }

    var displayName: String { customName ?? label }
}

@Model
final class Utterance {
    var speakerID: UUID
    var text: String
    var startTime: TimeInterval
    var endTime: TimeInterval
    var confidence: Double
    var orderIndex: Int

    init(speakerID: UUID, text: String,
         startTime: TimeInterval, endTime: TimeInterval,
         confidence: Double, orderIndex: Int) {
        self.speakerID = speakerID
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.confidence = confidence
        self.orderIndex = orderIndex
    }
}

/// 템플릿별 가변 섹션 — sectionsData에 JSON 배열로 저장 (05-m3 §1)
struct SummarySection: Codable, Equatable {
    let title: String
    let bullets: [String]
}

@Model
final class Summary {
    var templateTypeRaw: String          // MeetingType rawValue (지금은 general 하나)
    var oneLiner: String = ""            // 한 줄 요약 (홈 카드에도 사용)
    var sectionsData: Data = Data()      // [SummarySection] JSON — 내보내기가 읽는 평문 형태
    var generatedAt: Date = Date.distantPast
    // 회의록 템플릿 구조체들 (#21). 화면은 이 원본을 표로 그리고,
    // 내보내기는 위 sections(평문)를 그대로 쓴다 — 둘 다 같은 요약에서 나온다.
    var briefingData: Data = Data()      // [String] JSON — 세 줄 브리핑
    var decisionsData: Data = Data()     // [DecisionItem] JSON
    var agendaData: Data = Data()        // [AgendaItem] JSON
    var parkingLotData: Data = Data()    // [OpenIssue] JSON
    /// 전사에서 직접 언급됐을 때만 채워지는 머리말 값. 비면 화면에서 줄째로 뺀다.
    var place: String = ""
    var absentees: String = ""
    @Relationship(deleteRule: .cascade) var todos: [TodoItem] = []

    init(templateTypeRaw: String,
         oneLiner: String = "",
         sections: [SummarySection] = [],
         generatedAt: Date = .now) {
        self.templateTypeRaw = templateTypeRaw
        self.oneLiner = oneLiner
        self.sectionsData = (try? JSONEncoder().encode(sections)) ?? Data()
        self.generatedAt = generatedAt
        self.todos = []
    }

    var sections: [SummarySection] {
        get { (try? JSONDecoder().decode([SummarySection].self, from: sectionsData)) ?? [] }
        set { sectionsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var briefing: [String] {
        get { (try? JSONDecoder().decode([String].self, from: briefingData)) ?? [] }
        set { briefingData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var decisions: [DecisionItem] {
        get { (try? JSONDecoder().decode([DecisionItem].self, from: decisionsData)) ?? [] }
        set { decisionsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var agenda: [AgendaItem] {
        get { (try? JSONDecoder().decode([AgendaItem].self, from: agendaData)) ?? [] }
        set { agendaData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var parkingLot: [OpenIssue] {
        get { (try? JSONDecoder().decode([OpenIssue].self, from: parkingLotData)) ?? [] }
        set { parkingLotData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    /// 회의록 템플릿 개편(#21) 이전에 저장된 요약인지 — 구조체 칸이 통째로 비어 있다.
    /// 이런 요약은 저장된 평문 섹션을 그대로 보여주고, 다시 요약해야 새 형태가 된다.
    var isLegacyShape: Bool {
        briefingData.isEmpty && decisionsData.isEmpty
            && agendaData.isEmpty && parkingLotData.isEmpty
    }

    var templateType: MeetingType {
        get { MeetingType(rawValue: templateTypeRaw) ?? .general }
        set { templateTypeRaw = newValue.rawValue }
    }
}

@Model
final class TodoItem {
    var text: String
    var assignee: String?
    var due: String?           // 자유 텍스트 기한 ("8월 26일")
    var isDone: Bool
    var orderIndex: Int
    /// 회의 시점의 상태 (완료·진행중·대기) — 회의록 표에 그대로 들어간다 (#21).
    /// 체크박스(isDone)는 사용자가 나중에 끄고 켜는 값이라 따로 둔다.
    var status: String = SummaryTemplates.statusWaiting

    init(text: String, assignee: String? = nil, due: String? = nil,
         isDone: Bool = false, orderIndex: Int,
         status: String = SummaryTemplates.statusWaiting) {
        self.text = text
        self.assignee = assignee
        self.due = due
        self.isDone = isDone
        self.orderIndex = orderIndex
        self.status = status
    }
}
