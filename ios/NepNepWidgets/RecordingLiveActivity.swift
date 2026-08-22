import ActivityKit
import SwiftUI
import WidgetKit

/// 잠금 화면·다이나믹 아일랜드 (02-m1 §6, 와이어프레임 1c)
struct RecordingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingActivityAttributes.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.85))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.meetingTitle)
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ElapsedText(context: context)
                        .font(.headline.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 12) {
                        Button(intent: PauseResumeRecordingIntent()) {
                            Label(context.state.isPaused ? "재개" : "일시정지",
                                  systemImage: context.state.isPaused ? "play.fill" : "pause.fill")
                        }
                        Button(intent: StopRecordingIntent()) {
                            Label("완료", systemImage: "stop.fill")
                        }
                        .tint(.red)
                    }
                    .buttonStyle(.bordered)
                }
            } compactLeading: {
                Image(systemName: "mic.fill")
                    .foregroundStyle(.red)
            } compactTrailing: {
                ElapsedText(context: context)
                    .font(.caption.monospacedDigit())
                    .frame(maxWidth: 56)
            } minimal: {
                Image(systemName: "mic.fill")
                    .foregroundStyle(.red)
            }
        }
    }
}

private struct LockScreenView: View {
    let context: ActivityViewContext<RecordingActivityAttributes>

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.meetingTitle)
                    .font(.headline)
                    .lineLimit(1)
                Text(context.state.isPaused ? "넵넵 · 일시정지됨" : "넵넵 · 녹음 중")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ElapsedText(context: context)
                .font(.title2.monospacedDigit())
            Button(intent: PauseResumeRecordingIntent()) {
                Image(systemName: context.state.isPaused ? "play.fill" : "pause.fill")
            }
            Button(intent: StopRecordingIntent()) {
                Image(systemName: "stop.fill")
            }
            .tint(.red)
        }
        .buttonStyle(.bordered)
        .padding()
        .foregroundStyle(.white)
    }
}

private struct ElapsedText: View {
    let context: ActivityViewContext<RecordingActivityAttributes>

    var body: some View {
        if context.state.isPaused {
            Text(Duration.seconds(context.state.pausedElapsed),
                 format: .time(pattern: .minuteSecond))
        } else {
            Text(timerInterval: context.state.startedAt...Date(timeIntervalSinceNow: 8 * 3600),
                 countsDown: false)
        }
    }
}
