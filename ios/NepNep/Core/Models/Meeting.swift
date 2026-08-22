import Foundation
import SwiftData

enum MeetingType: String, CaseIterable, Codable {
    case general, oneOnOne, interview, standup

    var displayName: String {
        switch self {
        case .general: return "일반"
        case .oneOnOne: return "1on1"
        case .interview: return "인터뷰"
        case .standup: return "스탠드업"
        }
    }

    /// 설정 > 기본 회의 유형 (08-m5 §5)
    static let defaultKey = "defaultMeetingType"

    static var defaultType: MeetingType {
        guard let raw = UserDefaults.standard.string(forKey: defaultKey) else { return .general }
        return MeetingType(rawValue: raw) ?? .general
    }
}

enum MeetingStatus: String, Codable {
    case recording
    case recorded      // 녹음 종료·복구됨, 파이프라인 미시작 (M2 전 임시 종착 상태)
    case processing
    case done
    case failed
}

/// 인터럽트 등으로 녹음이 비어 있는 구간
struct GapRange: Codable, Equatable {
    var start: TimeInterval
    var end: TimeInterval
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

    /// "8월 22일 일반 회의" 형태의 자동 제목 (와이어프레임 1c 노트 1)
    static func autoTitle(type: MeetingType, date: Date = .now) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ko_KR")
        fmt.dateFormat = "M월 d일"
        return "\(fmt.string(from: date)) \(type.displayName) 회의"
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
        if MeetingType.allCases.contains(where: { autoTitle(type: $0, date: date) == title }) {
            return true
        }
        return title.hasPrefix(isoDatePrefix(date))
    }

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
    var templateTypeRaw: String          // general/oneOnOne/interview/standup
    var oneLiner: String = ""            // 한 줄 요약 (홈 카드에도 사용)
    var sectionsData: Data = Data()      // [SummarySection] JSON
    var generatedAt: Date = Date.distantPast
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

    init(text: String, assignee: String? = nil, due: String? = nil,
         isDone: Bool = false, orderIndex: Int) {
        self.text = text
        self.assignee = assignee
        self.due = due
        self.isDone = isDone
        self.orderIndex = orderIndex
    }
}
