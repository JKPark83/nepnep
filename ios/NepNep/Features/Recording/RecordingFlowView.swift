import SwiftUI

/// 녹음 → 처리 전환 플로우 (1c → 1d)
/// 홈의 fullScreenCover 하나 안에서 화면을 교체해 중첩 cover를 피한다.
struct RecordingFlowView: View {
    let initialType: MeetingType
    @State private var processingMeeting: Meeting?

    var body: some View {
        if let meeting = processingMeeting {
            ProcessingView(meeting: meeting)
        } else {
            RecordingView(initialType: initialType) { meeting in
                processingMeeting = meeting
            }
        }
    }
}
