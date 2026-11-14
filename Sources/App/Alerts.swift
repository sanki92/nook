import AppKit
import UserNotifications

final class Alerts: NSObject, UNUserNotificationCenterDelegate {
    private var tracker = AlertTracker()
    private let center = UNUserNotificationCenter.current()
    var onOpen: ((Int32) -> Void)?

    override init() {
        super.init()
        center.delegate = self
        center.requestAuthorization(options: [.alert]) { _, _ in }
    }

    func update(agents: [Agent]) {
        for agent in tracker.entered(agents) {
            let content = UNMutableNotificationContent()
            content.title = agent.name
            content.body = stateWords[agent.state] ?? ""
            content.userInfo = ["pid": Int(agent.pid)]
            center.add(UNNotificationRequest(identifier: agent.id, content: content, trigger: nil))
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let pid = response.notification.request.content.userInfo["pid"] as? Int ?? 0
        DispatchQueue.main.async { [weak self] in
            if pid > 0 { self?.onOpen?(Int32(pid)) }
        }
        completionHandler()
    }
}
