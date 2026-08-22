import ActivityKit
import Foundation

/// Live Activity 공유 타입 (02-m1 §6) — 앱·위젯 양쪽 타깃에 포함된다.
struct RecordingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// 경과 시간 기준 시각. Text(timerInterval:)로 OS가 직접 갱신한다.
        var startedAt: Date
        var isPaused: Bool
        /// 일시정지 시점의 경과 시간 표시용
        var pausedElapsed: TimeInterval
    }

    var meetingTitle: String
}
