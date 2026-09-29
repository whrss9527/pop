import AppKit
import UserNotifications

/// 系统通知：提醒有新版本（带一个「立即更新」按钮）、计时到点；第一次发通知时才请求权限。
final class Notifier: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = Notifier()

    static let updateCategory = "update"
    static let installUpdateAction = "install-update"

    /// 用户点了通知本身
    var onOpen: (@MainActor () -> Void)?
    /// 用户点了「立即更新」
    var onInstall: (@MainActor () -> Void)?

    private var available: Bool { Bundle.main.bundleIdentifier != nil }

    /// 启动时调用：设好 delegate 和通知按钮，程序重启后点旧通知也能收到（不会弹权限请求）。
    func start() {
        guard available else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let install = UNNotificationAction(identifier: Self.installUpdateAction, title: "立即更新", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.updateCategory, actions: [install], intentIdentifiers: [], options: []),
        ])
    }

    func showUpdate(version: String) {
        guard available else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Pop 有新版本 \(version)"
            content.body = "点「立即更新」自动下载安装并重新启动，点通知查看更新内容。"
            content.categoryIdentifier = Notifier.updateCategory
            let request = UNNotificationRequest(identifier: "pop-update-\(version)", content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request) { error in
                if let error {
                    UpdateLog.info("显示通知失败：\(error.localizedDescription)")
                }
            }
        }
    }

    /// 一条普通的提醒（计时到点）
    func showReminder(title: String, body: String) {
        guard available else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            let request = UNNotificationRequest(identifier: "pop-reminder-\(UUID().uuidString)", content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let action = response.actionIdentifier
        // 只有新版本的通知有后续操作；点计时提醒什么都不用做
        let isUpdate = response.notification.request.content.categoryIdentifier == Self.updateCategory
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard isUpdate else { return }
                if action == Self.installUpdateAction {
                    self.onInstall?()
                } else if action == UNNotificationDefaultActionIdentifier {
                    self.onOpen?()
                }
            }
        }
        completionHandler()
    }
}
