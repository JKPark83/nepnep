import ActivityKit
import Foundation

/// Live Activity 시작·갱신·종료 (02-m1 §6)
@MainActor
final class RecordingLiveActivityController {
    static let shared = RecordingLiveActivityController()

    private var activity: Activity<RecordingActivityAttributes>?

    func start(title: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = RecordingActivityAttributes(meetingTitle: title)
        let state = RecordingActivityAttributes.ContentState(
            startedAt: .now, isPaused: false, pausedElapsed: 0)
        activity = try? Activity.request(
            attributes: attributes,
            content: .init(state: state, staleDate: nil))
    }

    func update(elapsed: TimeInterval, isPaused: Bool) {
        guard let activity else { return }
        let state = RecordingActivityAttributes.ContentState(
            startedAt: Date().addingTimeInterval(-elapsed),
            isPaused: isPaused,
            pausedElapsed: elapsed)
        Task { await activity.update(.init(state: state, staleDate: nil)) }
    }

    func end() {
        guard let activity else { return }
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
        self.activity = nil
    }
}
