import AppKit
import CommandChainCore
import UserNotifications

/// Asks GitHub for the newest release, and shows a macOS notification that opens its download page.
@MainActor
final class UpdateChecker: NSObject {
    /// The version that's running, from the app's Info.plist.
    static var currentVersion: AppVersion? {
        #if DEBUG
        // `-debugCurrentVersion 1.0.0` pretends to be an older build, for trying out the update banner.
        if let override = UserDefaults.standard.string(forKey: "debugCurrentVersion") { return AppVersion(override) }
        #endif
        return (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init)
    }

    /// Builds run straight from `.build` have no app bundle, which the notification center needs.
    private static var canNotify: Bool { Bundle.main.bundleIdentifier != nil }

    override init() {
        super.init()
        if Self.canNotify { UNUserNotificationCenter.current().delegate = self }
    }

    static func latestRelease() async throws -> AppRelease {
        var request = URLRequest(url: AppRelease.latestURL, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "GitHub answered with status \(http.statusCode)."])
        }
        return try JSONDecoder().decode(AppRelease.self, from: data)
    }

    /// Clicking the notification opens the release page. macOS asks for permission the first time.
    func notify(about release: AppRelease) {
        guard Self.canNotify else { return }
        let content = UNMutableNotificationContent()
        content.title = "Command Chain \(release.version) is available"
        content.body = "Click to open the download page on GitHub."
        content.userInfo = ["url": release.pageURL.absoluteString]
        let request = UNNotificationRequest(identifier: "update-\(release.version)", content: content, trigger: nil)
        Task {
            let center = UNUserNotificationCenter.current()
            guard (try? await center.requestAuthorization(options: [.alert])) == true else { return }
            try? await center.add(request)
        }
    }
}

extension UpdateChecker: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let link = response.notification.request.content.userInfo["url"] as? String, let url = URL(string: link) {
            DispatchQueue.main.async { NSWorkspace.shared.open(url) }
        }
        completionHandler()
    }

    /// Shows the notification even while the panel is open.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }
}
