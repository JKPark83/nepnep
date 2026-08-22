import AppIntents

/// Live Activity 버튼 인텐트 (02-m1 §6)
/// LiveActivityIntent 채택 → 앱 프로세스에서 실행되므로 RecordingSession에 바로 접근한다.
struct PauseResumeRecordingIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "녹음 일시정지/재개"

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        let session = RecordingSession.shared
        if session.state == .recording {
            session.pause()
        } else {
            session.resume()
        }
        #endif
        return .result()
    }
}

struct StopRecordingIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "녹음 완료"

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        RecordingSession.shared.stop()
        #endif
        return .result()
    }
}
