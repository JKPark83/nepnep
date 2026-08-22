import Foundation
import UserNotifications

/// 알림 딥링크 → 상세 화면 이동 (04-m2 §5)
@MainActor
@Observable
final class Router {
    static let shared = Router()

    /// NavigationStack 경로 — Meeting.id 푸시
    var path: [UUID] = []

    func openMeeting(_ id: UUID) {
        path = [id]
    }
}

/// 처리 완료/실패 알림 탭 → 해당 회의 열기
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        guard let raw = userInfo["meetingID"] as? String,
              let id = UUID(uuidString: raw) else { return }
        await MainActor.run { Router.shared.openMeeting(id) }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification)
        async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
