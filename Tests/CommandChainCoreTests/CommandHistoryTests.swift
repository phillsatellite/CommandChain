import AppKit
import Foundation
import Testing
@testable import CommandChainCore

@Suite struct CommandHistoryTests {
    @Test func recentKeepsAtMostThirty() {
        var history = CommandHistory()
        for i in 1...45 { history.record("echo \(i)") }
        #expect(history.recent.count == 30)
        #expect(history.recent.first == "echo 45")
        #expect(history.recent.last == "echo 16")
    }

    @Test func repeatedCommandMovesToTopInsteadOfDuplicating() {
        var history = CommandHistory()
        history.record("git status")
        history.record("ls")
        history.record("pwd")
        history.record("git status")
        #expect(history.recent == ["git status", "pwd", "ls"])
        #expect(history.count(of: "git status") == 2)
    }

    @Test func ignoresTrivialCommands() {
        var history = CommandHistory()
        history.record("exit")
        history.record("  clear ")
        #expect(history.recent.isEmpty)
    }

    @Test func mostUsedSortsByCount() {
        var history = CommandHistory()
        for _ in 0..<3 { history.record("yarn ios") }
        history.record("ls")
        for _ in 0..<2 { history.record("adb devices") }
        #expect(history.commands(for: .mostUsed) == ["yarn ios", "adb devices", "ls"])
    }

    @Test func mostUsedSurvivesFallingOutOfRecent() {
        var history = CommandHistory()
        for _ in 0..<5 { history.record("npx detox test") }
        for i in 0..<40 { history.record("echo \(i)") }
        #expect(!history.recent.contains("npx detox test"))
        #expect(history.commands(for: .mostUsed).first == "npx detox test")
        #expect(history.commands(for: .category(.detox)) == ["npx detox test"])
    }

    @Test func favoritesToggle() {
        var history = CommandHistory()
        history.toggleFavorite("pod install")
        history.toggleFavorite("adb reverse tcp:8081 tcp:8081")
        #expect(history.favorites == ["adb reverse tcp:8081 tcp:8081", "pod install"])
        history.toggleFavorite("pod install")
        #expect(history.favorites == ["adb reverse tcp:8081 tcp:8081"])
    }

    @Test func forgetKeepsFavorites() {
        var history = CommandHistory()
        history.record("pod install")
        history.toggleFavorite("pod install")
        history.forget("pod install")
        #expect(history.recent.isEmpty)
        #expect(history.favorites == ["pod install"])
        #expect(history.commands(for: .category(.ios)) == ["pod install"])
    }

    @Test func moveFavorites() {
        var history = CommandHistory()
        for c in ["c", "b", "a"] { history.addFavorite(c) }
        history.moveFavorites(fromOffsets: [0], toOffset: 3)
        #expect(history.favorites == ["b", "c", "a"])
    }

    @Test func codableRoundTrip() throws {
        var history = CommandHistory()
        history.record("ls -la")
        history.toggleFavorite("ls -la")
        let data = try JSONEncoder().encode(history)
        #expect(try JSONDecoder().decode(CommandHistory.self, from: data) == history)
    }
}

@Suite struct CategoryTests {
    @Test(arguments: [
        "adb devices", "./gradlew assembleDebug", "cd android && ./gradlew clean",
        "npx react-native run-android", "yarn android", "emulator -avd Pixel_7",
        "~/Library/Android/sdk/platform-tools/adb logcat", "bundletool build-apks",
    ])
    func android(_ command: String) {
        #expect(CommandCategory.android.matches(command))
        #expect(!CommandCategory.ios.matches(command))
    }

    @Test(arguments: [
        "xcrun simctl list devices", "cd ios && pod install", "npx react-native run-ios",
        "xcodebuild -workspace App.xcworkspace -scheme App", "yarn ios", "npx expo run:ios",
        "open ios/App.xcworkspace", "bundle exec fastlane ios beta",
    ])
    func ios(_ command: String) {
        #expect(CommandCategory.ios.matches(command))
        #expect(!CommandCategory.android.matches(command))
    }

    @Test func detoxCanAlsoBePlatform() {
        #expect(CommandCategory.detox.matches("npx detox test -c ios.sim.debug"))
        #expect(CommandCategory.ios.matches("npx detox test -c ios.sim.debug"))
        #expect(CommandCategory.android.matches("detox build -c android.emu.release"))
    }

    @Test(arguments: ["git status", "brew install macos-trash", "ls studios", "cat scenarios.md", "npm run podcast"])
    func notAPlatform(_ command: String) {
        for category in [CommandCategory.ios, .android, .detox] {
            #expect(!category.matches(command), "\(category.title) matched \(command)")
        }
    }

    @Test(arguments: [
        ("git push origin main", ["Git"]),
        ("docker compose up -d", ["Docker"]),
        ("brew install wget", ["Homebrew"]),
        ("python3 -m venv .venv", ["Python"]),
        ("npx expo start", ["Expo", "Node.js"]),
        ("yarn detox test", ["Detox", "Yarn"]),
        ("sudo gem install cocoapods", ["Ruby"]),
        ("bundle exec fastlane ios beta", ["iOS", "Fastlane", "Ruby"]),
        ("kubectl get pods | grep api", ["Kubernetes"]),
        ("FOO=1 cargo build --release", ["Rust"]),
        ("arch -x86_64 pod install", ["iOS"]),
        ("ls -la", []),
    ])
    func detectsToolsAndLanguages(_ command: String, _ expected: [String]) {
        #expect(CommandCategory.matching(command).map(\.title) == expected)
    }

    @Test func ignoresProgramNamesInsideQuotes() {
        #expect(CommandCategory.matching(#"git commit -m "bump docker and python""#).map(\.title) == ["Git"])
    }

    @Test func categoryIDsAreUnique() {
        let ids = CommandCategory.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func everyCategoryIconExists() {
        for category in CommandCategory.all {
            #expect(NSImage(systemSymbolName: category.systemImage, accessibilityDescription: nil) != nil,
                    "missing SF Symbol \(category.systemImage) for \(category.title)")
        }
    }
}

@Suite struct FilterTests {
    @Test func onlyCategoriesWithCommandsBecomeTabs() {
        var history = CommandHistory()
        #expect(history.categoriesInUse().isEmpty)
        history.record("ls")
        #expect(history.categoriesInUse().isEmpty)
        history.record("git status")
        history.record("adb devices")
        #expect(history.categoriesInUse().map(\.title) == ["Android", "Git"])
        history.forget("adb devices")
        #expect(history.categoriesInUse().map(\.title) == ["Git"])
    }

    @Test func favoriteThatWasNeverRunStillCreatesItsTab() {
        var history = CommandHistory()
        history.addFavorite("docker ps")
        #expect(history.categoriesInUse().map(\.title) == ["Docker"])
        #expect(history.commands(for: .category(CommandCategory.all.first { $0.id == "docker" }!)) == ["docker ps"])
    }

    @Test func savedSelectionRoundTripsAndReadsOldValues() {
        for filter in CommandFilter.fixed + CommandCategory.all.map(CommandFilter.category) {
            #expect(CommandFilter(rawValue: filter.rawValue) == filter)
        }
        // Builds before dynamic tabs saved these.
        #expect(CommandFilter(rawValue: "ios") == .category(.ios))
        #expect(CommandFilter(rawValue: "android") == .category(.android))
        #expect(CommandFilter(rawValue: "nonsense") == nil)
    }

    private static func category(_ id: String) -> CommandCategory {
        CommandCategory.all.first { $0.id == id }!
    }

    @Test func toolFilterOffersOnlyToolsInTheList() {
        var history = CommandHistory()
        history.record("git status")
        history.record("docker ps")
        history.record("ls -la")
        history.record("npx detox test -c ios.sim.debug")
        #expect(history.tools(in: .recent).map(\.title) == ["Detox", "Docker", "Git", "iOS", "Node.js"])
        // A tool's own tab offers the other tools its commands use, not itself.
        #expect(history.tools(in: .category(.ios)).map(\.title) == ["Detox", "Node.js"])
        #expect(history.tools(in: .favorites).isEmpty)
    }

    @Test func toolFilterShowsCommandsInAnyPickedTool() {
        var history = CommandHistory()
        history.record("git status")
        history.record("docker ps")
        history.record("ls -la")
        history.record("git push")
        let git = Self.category("git"), docker = Self.category("docker")
        #expect(history.commands(for: .recent, tools: []) == ["git push", "ls -la", "docker ps", "git status"])
        #expect(history.commands(for: .recent, tools: [git]) == ["git push", "git status"])
        #expect(history.commands(for: .recent, tools: [git, docker]) == ["git push", "docker ps", "git status"])
        #expect(history.commands(for: .mostUsed, tools: [docker]) == ["docker ps"])
    }
}

@Suite struct InboxAndImportTests {
    @Test func unescape() {
        #expect(CommandInbox.parse("echo a\\nb\nprintf 'x\\\\ny'\n\n") == ["echo a\nb", "printf 'x\\ny'"])
        #expect(CommandInbox.parse("a\\tb") == ["a\tb"])
    }

    @Test func drainMovesInboxAside() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let paths = AppPaths(directory: dir)
        try paths.ensureDirectory()
        try "ls\ngit status\n".write(to: paths.inbox, atomically: true, encoding: .utf8)
        let inbox = CommandInbox(paths: paths)
        #expect(inbox.drain() == ["ls", "git status"])
        #expect(inbox.drain().isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
    }

    @Test func zshExtendedHistory() {
        let entries = HistoryImporter.parse(": 1700000000:0;git status\n: 1700000010:3;echo one \\\ntwo\nplain line\n")
        #expect(entries.map(\.command) == ["git status", "echo one \ntwo", "plain line"])
        #expect(entries[0].date == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(entries[2].date == nil)
    }

    @Test func installAndUninstallRoundTrip() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let original = "export PATH=/opt/bin:$PATH\nalias ll='ls -la'"
        try original.write(to: home.appendingPathComponent(".zshrc"), atomically: true, encoding: .utf8)
        let integration = ShellIntegration(paths: AppPaths(directory: home.appendingPathComponent("support")), homeDirectory: home)
        #expect(!integration.isInstalled)
        try integration.install()
        try integration.install()
        let installed = try String(contentsOf: home.appendingPathComponent(".zshrc"), encoding: .utf8)
        #expect(installed.components(separatedBy: ShellIntegration.beginMarker).count == 2)
        #expect(installed.contains("$HOME/support/hook.sh"))
        #expect(integration.isInstalled)
        try integration.uninstall()
        #expect(try String(contentsOf: home.appendingPathComponent(".zshrc"), encoding: .utf8) == original + "\n")
    }

    @Test func upgradesBlockFromBeforeRename() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let zshrc = home.appendingPathComponent(".zshrc")
        try """
        alias ll='ls -la'

        # >>> CommandCache >>>
        [ -f "$HOME/Library/Application Support/CommandCache/hook.sh" ] && . "$HOME/Library/Application Support/CommandCache/hook.sh"
        # <<< CommandCache <<<

        """.write(to: zshrc, atomically: true, encoding: .utf8)
        let integration = ShellIntegration(paths: AppPaths(directory: home.appendingPathComponent("support")), homeDirectory: home)
        try integration.upgradeLegacyInstall()
        let upgraded = try String(contentsOf: zshrc, encoding: .utf8)
        #expect(!upgraded.contains("CommandCache"))
        #expect(upgraded.hasPrefix("alias ll='ls -la'\n"))
        #expect(upgraded.components(separatedBy: ShellIntegration.beginMarker).count == 2)
        #expect(integration.isInstalled)
        // Nothing to upgrade the second time.
        try integration.upgradeLegacyInstall()
        #expect(try String(contentsOf: zshrc, encoding: .utf8) == upgraded)
    }
}

@Suite struct UpdateTests {
    @Test func parsesVersionsAndTags() {
        #expect(AppVersion("1.2.0")?.parts == [1, 2, 0])
        #expect(AppVersion("v1.10")?.parts == [1, 10])
        #expect(AppVersion(" V2 ")?.parts == [2])
        #expect(AppVersion("1.3.0-beta.1")?.parts == [1, 3, 0])
        #expect(AppVersion("") == nil)
        #expect(AppVersion("latest") == nil)
        #expect(AppVersion("1..2") == nil)
    }

    @Test func comparesNumberByNumber() throws {
        let v = { (s: String) in AppVersion(s)! }
        #expect(v("1.10.0") > v("1.9.9"))
        #expect(v("1.1") == v("1.1.0"))
        #expect(v("2.0") > v("1.99"))
        #expect(!(v("1.1.0") < v("1.1")))
    }

    @Test func decodesGitHubRelease() throws {
        let json = """
        {"tag_name": "v1.2.0", "name": "Command Chain", "draft": false, "prerelease": false,
         "html_url": "https://github.com/phillsatellite/CommandChain/releases/tag/v1.2.0",
         "assets": [{"name": "CommandChain-1.2.0.dmg"}]}
        """
        let release = try JSONDecoder().decode(AppRelease.self, from: Data(json.utf8))
        #expect(release.version == AppVersion("1.2.0"))
        #expect(release.pageURL.absoluteString == "https://github.com/phillsatellite/CommandChain/releases/tag/v1.2.0")
        #expect(release.isNewer(than: AppVersion("1.1.0")!))
        #expect(!release.isNewer(than: AppVersion("1.2")!))
        #expect(!release.isNewer(than: AppVersion("1.3.0")!))
    }

    @Test func rejectsReleaseWithoutVersionTag() {
        let json = #"{"tag_name": "nightly", "html_url": "https://github.com/x/y/releases/tag/nightly"}"#
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(AppRelease.self, from: Data(json.utf8))
        }
    }
}
