// Claude Supercharger notifier — posts a macOS notification under its own app
// name and icon (osascript's show as "Script Editor"). Clicking one brings back
// the app the notification was sent from.
//
//   notifier <title> <body> [subtitle] [bundle-id-to-activate-on-click]
//
// Exit: 0 posted · 2 notifications not allowed for this app · 3 post failed.
// The caller falls back to osascript on any non-zero exit.
import AppKit
import UserNotifications

final class Notifier: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ n: Notification) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let a = CommandLine.arguments
        guard a.count >= 3 else { return }   // relaunched by a click: wait for didReceive
        center.requestAuthorization(options: [.alert, .sound]) { ok, err in
            guard ok else {
                FileHandle.standardError.write("notifications not allowed: \(err?.localizedDescription ?? "denied")\n".data(using: .utf8)!)
                exit(2)
            }
            let m = UNMutableNotificationContent()
            m.title = a[1]
            m.body = a[2]
            if a.count > 3, !a[3].isEmpty { m.subtitle = a[3] }
            if a.count > 4, !a[4].isEmpty { m.userInfo = ["activate": a[4]] }
            m.sound = .default
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: m, trigger: nil)) { e in
                exit(e == nil ? 0 : 3)
            }
        }
    }

    func userNotificationCenter(_ c: UNUserNotificationCenter, didReceive r: UNNotificationResponse,
                                withCompletionHandler done: @escaping () -> Void) {
        done()
        guard let id = r.notification.request.content.userInfo["activate"] as? String,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { exit(0) }
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, _ in exit(0) }
    }

    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .sound])
    }
}

let app = NSApplication.shared
let notifier = Notifier()
app.delegate = notifier
DispatchQueue.main.asyncAfter(deadline: .now() + 30) { exit(0) }   // never linger
app.run()
