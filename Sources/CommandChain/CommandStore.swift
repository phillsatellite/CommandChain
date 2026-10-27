import AppKit
import CommandChainCore
import ServiceManagement

/// Owns the history, polls the shell inbox and persists to disk.
@MainActor
final class CommandStore: ObservableObject {
    @Published private(set) var history: CommandHistory
    @Published private(set) var shellIntegrationInstalled: Bool
    @Published private(set) var isPaused: Bool
    @Published var lastError: String?
    /// Clicking a command pastes it into the app you came from instead of only copying it.
    @Published private(set) var pasteOnClick: Bool
    /// Paste on click is on but Accessibility access hasn't been granted yet.
    @Published var needsAccessibility = false
    /// What the header's terminal button opens.
    @Published private(set) var newTerminalKind: NewTerminalKind
    /// The window or tab picked in the panel; ▶ and click-to-paste go there. Nil means automatic:
    /// ▶ goes to the terminal window you used last and click-to-paste to the app you were in.
    @Published private(set) var pinnedTarget: TerminalTarget?
    /// Where ▶ sends commands right now, shown above the list. Refreshed while the panel is open.
    @Published private(set) var currentTarget: TerminalTarget?
    /// A newer version on GitHub, once a check has found one.
    @Published private(set) var availableUpdate: AppRelease?
    /// Check GitHub for a new version at launch and once a day.
    @Published private(set) var checksForUpdates: Bool
    /// The version whose banner you closed with Not Now.
    @Published private var dismissedUpdate: String?

    let paths: AppPaths
    private let inbox: CommandInbox
    private let integration: ShellIntegration
    private let paster = TerminalPaster()
    private let updater = UpdateChecker()
    private var categoryCache: [String: [CommandCategory]] = [:]
    private var pollTimer: Timer?
    private var updateTimer: Timer?
    private var saveWorkItem: DispatchWorkItem?

    init(paths: AppPaths = .standard) {
        self.paths = paths
        inbox = CommandInbox(paths: paths)
        integration = ShellIntegration(paths: paths)
        // Only for the real data folder, never a COMMANDCHAIN_HOME test folder.
        if paths.directory == AppPaths.defaultDirectory {
            AppPaths.migrateFromCommandCache()
            try? integration.upgradeLegacyInstall()
        }
        history = Self.load(from: paths.store) ?? CommandHistory()
        shellIntegrationInstalled = integration.isInstalled
        isPaused = FileManager.default.fileExists(atPath: paths.pauseFlag.path)
        pasteOnClick = UserDefaults.standard.bool(forKey: Self.pasteOnClickKey)
        newTerminalKind = UserDefaults.standard.string(forKey: Self.newTerminalKindKey).flatMap(NewTerminalKind.init) ?? .window
        checksForUpdates = UserDefaults.standard.object(forKey: Self.checksForUpdatesKey) as? Bool ?? true
        dismissedUpdate = UserDefaults.standard.string(forKey: Self.dismissedUpdateKey)

        try? integration.writeHookScript()
        ingest()
        refreshTarget()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.ingest()
                // Hides the Accessibility banner as soon as access is granted in System Settings.
                self?.refreshAccessibilityStatus()
                // Keeps the window name above the list current, but only while the panel is open.
                if NSApp.keyWindow != nil { self?.refreshTarget() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer

        Task { await checkForUpdates() }
        let daily = Timer(timeInterval: 24 * 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.checkForUpdates() }
        }
        RunLoop.main.add(daily, forMode: .common)
        updateTimer = daily

        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.flush() }
        }
        // The panel becoming key means it just opened.
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshTarget() }
        }
    }

    // MARK: Reading

    func commands(for filter: CommandFilter, matching query: String) -> [String] {
        let all = history.commands(for: filter, categorize: categories(of:))
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return all }
        return all.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    /// Tabs to show after Recent, Most Used and Favorites: only categories you have commands in.
    var categoriesInUse: [CommandCategory] {
        history.categoriesInUse(categorize: categories(of:))
    }

    /// Cached, since a command's categories never change and the view asks on every redraw.
    func categories(of command: String) -> [CommandCategory] {
        if let cached = categoryCache[command] { return cached }
        let found = CommandCategory.matching(command)
        categoryCache[command] = found
        return found
    }

    func isFavorite(_ command: String) -> Bool { history.isFavorite(command) }
    func count(of command: String) -> Int { history.count(of: command) }

    // MARK: Actions

    func copy(_ command: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(command, forType: .string)
    }

    /// What clicking a row does. Always copies; also pastes when that setting is on.
    /// Returns true if it pasted.
    @discardableResult
    func copyOrPaste(_ command: String) -> Bool {
        copy(command)
        guard pasteOnClick, hasAccessibility(), let destination = destination(otherwise: .previousApp) else { return false }
        return paster.pasteClipboard(into: destination)
    }

    /// The play button: pastes into the picked or last terminal window and presses Return.
    /// Returns true if it ran; otherwise the command is only copied and a banner explains why.
    @discardableResult
    func run(_ command: String) -> Bool {
        copy(command)
        guard hasAccessibility(), let destination = destination(otherwise: .terminal) else { return false }
        guard paster.app(for: destination) != nil else {
            lastError = "Open Terminal, iTerm or another terminal app first, then press play. The command is on your clipboard."
            return false
        }
        return paster.pasteClipboard(into: destination, pressReturn: true)
    }

    /// The picked window if there is one, else `fallback`. Nil if the picked window has closed,
    /// so a command never lands in a window you didn't choose.
    private func destination(otherwise fallback: TerminalPaster.Destination) -> TerminalPaster.Destination? {
        guard let pinned = pinnedTarget else { return fallback }
        guard let current = paster.resolve(pinned) else {
            pin(nil)
            lastError = "The window you picked has closed, so nothing was sent. The command is on your clipboard."
            return nil
        }
        return .target(current)
    }

    /// Name of the app a click would paste into, e.g. "Terminal".
    var pasteTargetName: String? {
        pinnedTarget?.app.localizedName ?? paster.previousApp?.localizedName
    }

    /// Name of the terminal the play button would run in.
    var runTargetName: String? {
        pinnedTarget?.app.localizedName ?? paster.app(for: .terminal)?.localizedName
    }

    /// What the bar above the list shows: the window ▶ goes to, or just the terminal's name
    /// when windows can't be read yet (no Accessibility access).
    var currentTargetName: String? {
        currentTarget?.displayName ?? paster.app(for: .terminal)?.localizedName
    }

    /// Every open terminal window and tab, read fresh for the picker menu.
    func terminalTargets() -> [TerminalTarget] {
        TerminalPaster.hasPermission ? paster.allTargets() : []
    }

    /// Sends ▶ and click-to-paste to `target` from now on, or back to automatic with nil.
    func pin(_ target: TerminalTarget?) {
        pinnedTarget = target
        refreshTarget()
    }

    func refreshTarget() {
        guard TerminalPaster.hasPermission else { return show(nil) }
        guard let pinned = pinnedTarget else { return show(paster.frontTarget()) }
        guard let current = paster.resolve(pinned) else {
            pinnedTarget = nil
            lastError = "The window you picked has closed. Commands go to the terminal window you used last again."
            return show(paster.frontTarget())
        }
        // It's a different element if the window has since gained tabs.
        if current != pinned { pinnedTarget = current }
        show(current)
    }

    /// Only publishes real changes, so the once-a-second refresh doesn't redraw the panel for nothing.
    private func show(_ target: TerminalTarget?) {
        if target != currentTarget || target?.displayName != currentTarget?.displayName {
            currentTarget = target
        }
    }

    /// The header's terminal button: a new window or tab (`kind`, or the one picked in settings).
    /// Returns false if it couldn't, e.g. Accessibility access is missing.
    @discardableResult
    func openNewTerminal(_ kind: NewTerminalKind? = nil) -> Bool {
        // Launching a terminal that isn't running needs no access; pressing ⌘N or ⌘T in one does.
        if paster.app(for: .terminal) != nil, !hasAccessibility() { return false }
        return paster.openNewTerminal(kind ?? newTerminalKind)
    }

    /// The terminal the terminal button opens, even if it isn't running.
    var newTerminalName: String { paster.terminalName }

    func setNewTerminalKind(_ kind: NewTerminalKind) {
        newTerminalKind = kind
        UserDefaults.standard.set(kind.rawValue, forKey: Self.newTerminalKindKey)
    }

    /// Shows the Accessibility banner (and the system prompt, the first time) when access is missing.
    private func hasAccessibility() -> Bool {
        if TerminalPaster.hasPermission {
            needsAccessibility = false
            return true
        }
        if !needsAccessibility { TerminalPaster.requestPermission() }
        needsAccessibility = true
        return false
    }

    func setPasteOnClick(_ enabled: Bool) {
        pasteOnClick = enabled
        UserDefaults.standard.set(enabled, forKey: Self.pasteOnClickKey)
        needsAccessibility = enabled && !TerminalPaster.hasPermission
        if needsAccessibility { TerminalPaster.requestPermission() }
    }

    func refreshAccessibilityStatus() {
        guard needsAccessibility else { return }
        if TerminalPaster.hasPermission { needsAccessibility = false }
    }

    private static let pasteOnClickKey = "pasteOnClick"
    private static let newTerminalKindKey = "newTerminalKind"

    // MARK: Updates

    enum UpdateCheckResult {
        case available(AppRelease)
        case upToDate(AppVersion)
        case failed(String)
    }

    /// Runs at launch and once a day while automatic checks are on. `userInitiated` (⚙︎ → Check for Updates)
    /// always runs and leaves showing the result to the caller instead of sending a notification.
    @discardableResult
    func checkForUpdates(userInitiated: Bool = false) async -> UpdateCheckResult {
        guard userInitiated || checksForUpdates else { return .failed("Automatic update checks are off.") }
        guard let current = UpdateChecker.currentVersion else { return .failed("This build doesn't have a version number.") }
        do {
            let latest = try await UpdateChecker.latestRelease()
            guard latest.isNewer(than: current) else {
                availableUpdate = nil
                return .upToDate(current)
            }
            availableUpdate = latest
            // One notification per version, not one a day.
            if UserDefaults.standard.string(forKey: Self.notifiedUpdateKey) != latest.version.description {
                UserDefaults.standard.set(latest.version.description, forKey: Self.notifiedUpdateKey)
                if !userInitiated { updater.notify(about: latest) }
            }
            return .available(latest)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// There's a newer version and you haven't closed its banner.
    var showsUpdateBanner: Bool {
        guard let update = availableUpdate else { return false }
        return update.version.description != dismissedUpdate
    }

    func dismissUpdate() {
        dismissedUpdate = availableUpdate?.version.description
        UserDefaults.standard.set(dismissedUpdate, forKey: Self.dismissedUpdateKey)
    }

    /// Opens the release page with the DMG in your browser.
    func openUpdatePage() {
        guard let url = availableUpdate?.pageURL else { return }
        TerminalPaster.closePanel()
        NSWorkspace.shared.open(url)
    }

    func setChecksForUpdates(_ enabled: Bool) {
        checksForUpdates = enabled
        UserDefaults.standard.set(enabled, forKey: Self.checksForUpdatesKey)
        if enabled { Task { await checkForUpdates() } }
    }

    private static let checksForUpdatesKey = "checksForUpdates"
    private static let dismissedUpdateKey = "dismissedUpdateVersion"
    private static let notifiedUpdateKey = "notifiedUpdateVersion"

    func toggleFavorite(_ command: String) { mutate { $0.toggleFavorite(command) } }
    func addFavorite(_ command: String) { mutate { $0.addFavorite(command) } }
    func moveFavorites(from source: IndexSet, to destination: Int) {
        mutate { $0.moveFavorites(fromOffsets: source, toOffset: destination) }
    }
    func forget(_ command: String) { mutate { $0.forget(command) } }
    func clearRecent() { mutate { $0.clearRecent() } }
    func clearHistory() { mutate { $0.clearHistory() } }

    func installShellIntegration() {
        do {
            try integration.install()
            shellIntegrationInstalled = integration.isInstalled
        } catch {
            lastError = "Couldn't update your shell profile: \(error.localizedDescription)"
        }
    }

    func uninstallShellIntegration() {
        do {
            try integration.uninstall()
            shellIntegrationInstalled = integration.isInstalled
        } catch {
            lastError = "Couldn't update your shell profile: \(error.localizedDescription)"
        }
    }

    func setPaused(_ paused: Bool) {
        let fm = FileManager.default
        if paused {
            fm.createFile(atPath: paths.pauseFlag.path, contents: nil)
        } else {
            try? fm.removeItem(at: paths.pauseFlag)
        }
        isPaused = fm.fileExists(atPath: paths.pauseFlag.path)
    }

    /// Returns how many commands were imported.
    @discardableResult
    func importShellHistory() -> Int {
        let entries = HistoryImporter.defaultFiles().flatMap(HistoryImporter.load)
        guard !entries.isEmpty else { return 0 }
        // Entries without timestamps get evenly spaced fake ones so their order is preserved.
        let base = Date().addingTimeInterval(-Double(entries.count))
        mutate { history in
            for (offset, entry) in entries.enumerated() {
                history.record(entry.command, at: entry.date ?? base.addingTimeInterval(Double(offset)))
            }
        }
        return entries.count
    }

    var launchesAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setLaunchesAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            lastError = "Couldn't change Launch at Login: \(error.localizedDescription). Move Command Chain to Applications and try again."
        }
        objectWillChange.send()
    }

    func refreshIntegrationStatus() {
        shellIntegrationInstalled = integration.isInstalled
    }

    // MARK: Private

    private func ingest() {
        let commands = inbox.drain()
        guard !commands.isEmpty else { return }
        mutate { history in
            for command in commands { history.record(command) }
        }
    }

    private func mutate(_ change: (inout CommandHistory) -> Void) {
        change(&history)
        scheduleSave()
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let snapshot = history
        let url = paths.store
        let paths = paths
        let work = DispatchWorkItem {
            do {
                try paths.ensureDirectory()
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: url, options: .atomic)
            } catch {
                NSLog("Command Chain: failed to save history: \(error)")
            }
        }
        saveWorkItem = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func flush() {
        guard let work = saveWorkItem, !work.isCancelled else { return }
        work.cancel()
        work.perform()
    }

    private static func load(from url: URL) -> CommandHistory? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CommandHistory.self, from: data)
    }
}
