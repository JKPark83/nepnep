import SwiftUI

/// 녹음 중 화면 — 경과 시간과 정지 버튼뿐이다.
/// 전사·화자분리는 전부 아이폰 몫이라 워치가 보여 줄 진행 상황이 따로 없다.
struct WatchRecordingView: View {
    @State private var recorder = WatchRecorder.shared

    var body: some View {
        VStack(spacing: 12) {
            Text(WatchFormat.duration(recorder.elapsed))
                .font(.system(.title, design: .rounded).monospacedDigit())
                .contentTransition(.numericText())

            if recorder.state == .pausedByInterruption {
                Label("잠시 멈춤", systemImage: "pause.circle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("남은 시간 \(WatchFormat.duration(WatchRecorder.maxDuration - recorder.elapsed))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Button {
                recorder.stop()
            } label: {
                Label("정지", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .padding(.horizontal, 4)
        .navigationTitle("녹음 중")
        .navigationBarBackButtonHidden()
    }
}
