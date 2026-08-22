import SwiftData
import SwiftUI
import UserNotifications

@main
struct NepNepApp: App {
    @Environment(\.scenePhase) private var scenePhase
    let container: ModelContainer

    init() {
        container = try! ModelContainer(
            for: Meeting.self, Speaker.self, Utterance.self, Summary.self, TodoItem.self)
        // 크래시 복구 검사 (02-m1 §5) — 복구되면 status == .recorded → 홈 배너 노출
        _ = CrashRecovery.recoverIfNeeded(context: container.mainContext)
        RecordingSession.shared.modelContext = container.mainContext
        ProcessingCoordinator.shared.modelContext = container.mainContext
        // BG 태스크 등록은 런치 완료 전에 1회 (03-m2 §4)
        ProcessingCoordinator.shared.register()
        // 알림 탭 → 상세 딥링크 (04-m2 §5)
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        #if DEBUG
        DebugSeed.seedIfNeeded(context: container.mainContext)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            // 만료·강제 종료로 멈춘 처리 재개 (F10-2)
            if phase == .active {
                #if DEBUG
                // 데모 시드의 '처리 중' 회의를 실제 파이프라인에 태우지 않는다
                guard !DebugSeed.isEnabled else { return }
                #endif
                ProcessingCoordinator.shared.resumeUnfinishedIfNeeded()
            }
        }
    }
}
