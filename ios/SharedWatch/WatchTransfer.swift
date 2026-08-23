import Foundation

/// 아이폰 앱과 워치 앱이 함께 쓰는 타입. **Foundation 말고는 아무것도 import하지 않는다.**
///
/// `ios/Shared`는 ActivityKit·AppIntents를 쓰고 `RecordingSession`을 직접 참조하므로
/// 워치 타깃에 넣을 수 없다. `Meeting`도 SwiftData `@Model`이라 공유가 안 된다.
/// 그래서 전송 경계에서만 쓰는 순수 Codable 타입을 여기 따로 둔다.

/// 인터럽트 등으로 녹음이 비어 있는 구간
struct GapRange: Codable, Equatable {
    var start: TimeInterval
    var end: TimeInterval
}

/// 워치가 녹음을 마치고 아이폰으로 보내는 회의 한 건의 서술.
///
/// 자리표시자(`transferUserInfo`)와 실제 오디오(`transferFile`의 metadata) 양쪽에
/// 같은 형태로 실린다. 두 큐 사이에는 순서 보장이 없으므로 **어느 쪽이 먼저 도착해도
/// 같은 회의로 합쳐지도록** `meetingID`를 워치가 만들어 고정한다.
struct WatchRecordingEnvelope: Codable, Equatable {
    /// 워치 앱만 업데이트된 채 오래된 아이폰 앱에 붙는 경우를 걸러내기 위한 값
    static let currentVersion = 1

    var version: Int
    var meetingID: UUID
    /// `MeetingType.rawValue`. 워치는 이 값을 해석하지 않고 그대로 실어 보내기만 한다 —
    /// 아이폰이 자기 기본 회의 유형을 내려주고, 워치는 그걸 되돌려준다.
    /// 제목도 같은 이유로 여기 없다. 아이폰이 자기 규칙(`Meeting.autoTitle`)으로 붙인다.
    var typeRaw: String
    var startedAt: Date
    var duration: TimeInterval
    var gapRanges: [GapRange]
    /// 오디오 파일 확장자. 지금은 항상 "m4a"(AAC 16kHz mono 32kbps).
    var audioFormat: String

    init(meetingID: UUID,
         typeRaw: String,
         startedAt: Date,
         duration: TimeInterval,
         gapRanges: [GapRange] = [],
         audioFormat: String = "m4a",
         version: Int = WatchRecordingEnvelope.currentVersion) {
        self.version = version
        self.meetingID = meetingID
        self.typeRaw = typeRaw
        self.startedAt = startedAt
        self.duration = duration
        self.gapRanges = gapRanges
        self.audioFormat = audioFormat
    }
}

/// 워치 목록에 뿌릴 회의 한 줄.
///
/// 워치는 아이폰의 도메인 타입을 하나도 모른다 — 표시 문자열을 아이폰이 만들어 내려주고
/// 워치는 그리기만 한다. 덕분에 `MeetingType`·`MeetingStatus`·날짜 포맷터를 공유할 필요가 없고,
/// 두 화면의 문구가 어긋날 일도 없다.
struct WatchMeetingRow: Codable, Hashable, Identifiable {
    var id: UUID
    var title: String
    /// "오늘 오후 2:00 · 48분 · 일반"
    var metaText: String
    /// "완료" / "처리 중" / "전송 대기 중" …
    var statusText: String
    /// 한 줄 요약. 비어 있으면 워치 상세에서 안내 문구로 대체한다.
    var oneLiner: String
}

/// 아이폰 → 워치로 내려가는 상태 전부. `updateApplicationContext`로 통째로 덮어쓴다.
struct WatchContextPayload: Codable, Equatable {
    /// 최근 회의부터 정렬된 상태로 내려온다 — 워치는 다시 정렬하지 않는다.
    var rows: [WatchMeetingRow]
    /// 아이폰 설정의 기본 회의 유형. 워치는 녹음할 때 이 값을 그대로 봉투에 담는다.
    var defaultTypeRaw: String

    static let empty = WatchContextPayload(rows: [], defaultTypeRaw: "")
}

/// WCSession은 `[String: Any]`만 받으므로 JSON으로 싸서 한 칸에 넣는다.
enum WatchPayload {
    static let envelopeKey = "nepnep.envelope"
    static let contextKey = "nepnep.context"

    /// 목록은 최근 것부터 이만큼만 보낸다. application context에는 크기 제한이 있고,
    /// 워치에서 손가락으로 넘길 수 있는 양도 이 정도가 한계다.
    static let maxRows = 20
    static let maxTitleLength = 60
    static let maxOneLinerLength = 120

    static func encode<T: Encodable>(_ value: T, key: String) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(value) else { return [:] }
        return [key: data]
    }

    static func decode<T: Decodable>(_ type: T.Type,
                                     key: String,
                                     from dictionary: [String: Any]) -> T? {
        guard let data = dictionary[key] as? Data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// 표시용 문자열을 잘라 낸다. 잘린 티가 나야 사용자가 아이폰에서 보게 된다.
    static func truncated(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "…"
    }
}
