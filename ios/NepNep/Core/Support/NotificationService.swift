import Foundation
import UserNotifications

/// 처리 완료/실패 로컬 알림 (03-m2 §6, F10-3)
/// 권한 요청은 온보딩(M6)에서 — 여기서는 권한이 있으면 발송만 한다.
enum NotificationService {
    /// 설정 > 처리 완료 알림 토글 (08-m5 §5) — 키 부재 시 켜짐
    static let doneNotificationKey = "doneNotificationEnabled"

    private static var notificationEnabled: Bool {
        let defaults = UserDefaults.standard
        return defaults.object(forKey: doneNotificationKey) == nil
            || defaults.bool(forKey: doneNotificationKey)
    }

    static func notifyDone(meeting: Meeting) {
        guard notificationEnabled else { return }
        send(title: "회의록이 준비됐어요 — \(meeting.title)",
             body: "탭해서 확인해 보세요",
             meetingID: meeting.id)
    }

    static func notifyFailed(meeting: Meeting) {
        guard notificationEnabled else { return }
        send(title: "정리하지 못했어요 — \(meeting.title)",
             body: "탭해서 다시 시도",
             meetingID: meeting.id)
    }

    private static func send(title: String, body: String, meetingID: UUID) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.userInfo = ["meetingID": meetingID.uuidString]
            let request = UNNotificationRequest(identifier: meetingID.uuidString,
                                                content: content,
                                                trigger: nil)
            center.add(request)
        }
    }
}
