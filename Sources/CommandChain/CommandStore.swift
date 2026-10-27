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

    let paths: AppPaths
    private let inbox: CommandInbox
    private let integration: ShellIntegration
    private let paster = TerminalPaster()
    private var pollTimer: Timer?
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

        try? integration.writeHookScript()
        ingest()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.ingest() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer

        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.flush() }
        }
    }

    // MARK: Reading

    func commands(for filter: CommandFilter, matching query: String) -> [String] {
        let all = history.commands(for: filter)
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return all }
        return all.filter { $0.localizedCaseInsensitiveContains(query) }
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
        guard pasteOnClick else { return false }
        guard TerminalPaster.hasPermission else {
            needsAccessibility = true
            return false
        }
        needsAccessibility = false
        return paster.pasteClipboard()
    }

    /// Name of the app a click would paste into, e.g. "Terminal".
    var pasteTargetName: String? {
        paster.targetApp?.localizedName
    }

    func setPasteOnClick(_ enabled: Bool) {
        pasteOnClick = enabled
        UserDefaults.standard.set(enabled, forKey: Self.pasteOnClickKey)
        needsAccessibility = enabled && !TerminalPaster.hasPermission
        if needsAccessibility { TerminalPaster.requestPermission() }
    }

    func refreshAccessibilityStatus() {
        if TerminalPaster.hasPermission || !pasteOnClick { needsAccessibility = false }
    }

    private static let pasteOnClickKey = "pasteOnClick"

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
