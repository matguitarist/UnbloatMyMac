import Foundation
import ServiceManagement
import UnbloatMyMacKit
import UserNotifications

/// Tells the person when a macOS update put back tweaks, even when the app is
/// closed. A login agent (Resources/LaunchAgents, registered with
/// SMAppService) runs `UnbloatMyMac --login-check` at each login; it posts
/// one notification per set of put-back tweaks, then quits.
enum RevertWatch {
    static let plistName = "com.mathieuares.unbloatmymac.watch.plist"

    enum Status: Equatable { case off, on, needsApproval }

    static var status: Status {
        guard !Store.isOverridden else { return .off }
        switch SMAppService.agent(plistName: plistName).status {
        case .enabled: return .on
        case .requiresApproval: return .needsApproval
        default: return .off
        }
    }

    /// Registers or removes the login agent. Turning it on asks for notification permission first.
    static func set(_ on: Bool) async throws {
        guard !Store.isOverridden else { return }
        let service = SMAppService.agent(plistName: plistName)
        if on {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            try service.register()
        } else {
            try await service.unregister()
        }
    }

    // MARK: The login check

    /// Where the last notice's key is kept, so each set of put-back tweaks is told once.
    private static var keyURL: URL {
        Store.isOverridden ? Store.url.deletingPathExtension().appendingPathExtension("notice.txt")
                           : Store.folder.appending(path: "revert-notice.txt")
    }

    /// The notification's words for a notice.
    static func message(_ notice: RevertNotice) -> (title: String, body: String) {
        let count = notice.tweaks.count
        let title = notice.macOSUpdated
            ? String(localized: "macOS put back \(count) tweaks")
            : String(localized: "\(count) tweaks were put back")
        let body = notice.macOSUpdated
            ? String(localized: "A macOS update reset settings UnbloatMyMac changed. Open UnbloatMyMac to apply them again.")
            : String(localized: "Something reset settings UnbloatMyMac changed. Open UnbloatMyMac to apply them again.")
        return (title, body)
    }

    /// `--login-check`: posts a notification when there is something new to tell. `--dry-run` prints it instead.
    static func runCheck(dryRun: Bool) -> Int32 {
        let engine = Store.makeEngine()
        let lastKey = try? String(contentsOf: keyURL, encoding: .utf8)
        guard let notice = engine.revertNotice(lastKey: lastKey) else {
            if dryRun { print("Nothing was put back.") }
            return 0
        }
        let (title, body) = message(notice)
        if dryRun {
            print("\(title)\n\(body)")
            return 0
        }
        engine.log?.add(.warning, .app, "At login, \(notice.tweaks.count) tweaks were put back", detail: notice.tweaks.joined(separator: "\n"))
        guard post(title: title, body: body) else { return 1 }
        try? notice.key.write(to: keyURL, atomically: true, encoding: .utf8)
        return 0
    }

    /// Posts and waits, since the process quits right after.
    private static func post(title: String, body: String) -> Bool {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: "reverted", content: content, trigger: nil)
        let done = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var posted = false
        UNUserNotificationCenter.current().add(request) { error in
            posted = error == nil
            done.signal()
        }
        _ = done.wait(timeout: .now() + 10)
        return posted
    }
}
