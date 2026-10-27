import AppKit
import ApplicationServices

/// What the header's terminal button opens.
enum NewTerminalKind: String, CaseIterable, Identifiable {
    case window, tab

    var id: String { rawValue }
    var title: String { self == .window ? "Window" : "Tab" }
    var systemImage: String { self == .window ? "macwindow.badge.plus" : "plus.rectangle.on.rectangle" }
}

/// A terminal window, or one tab of a window with several, that commands can be sent to.
/// Two targets are equal when they're the same window or tab, even if its title has changed.
struct TerminalTarget: Equatable {
    let app: NSRunningApplication
    /// The window, or for a tab, the window showing its tab bar right now.
    let window: AXUIElement
    /// The tab's button in the window's tab bar; nil for a window without tabs.
    let tab: AXUIElement?
    let title: String
    let windowTitle: String
    /// 1 for the app's front window, 2 for the one behind it, and so on.
    let windowNumber: Int
    /// The tab's position in its tab bar, from 1; nil for a window without tabs.
    let tabNumber: Int?
    let isFrontWindow: Bool
    /// The tab that's showing in its window (always true for a window without tabs).
    let isSelectedTab: Bool

    /// Where a paste goes if you don't pick anything: the selected tab of the app's front window.
    var isFront: Bool { isFrontWindow && isSelectedTab }

    /// For the panel, e.g. "phill — -zsh — 120×30" or "npm · Tab 2".
    var displayName: String {
        let name = title.isEmpty ? (app.localizedName ?? "Terminal") : title
        return tabNumber.map { "\(name) · Tab \($0)" } ?? name
    }

    static func == (a: TerminalTarget, b: TerminalTarget) -> Bool {
        a.app.processIdentifier == b.app.processIdentifier && CFEqual(a.tab ?? a.window, b.tab ?? b.window)
    }
}

/// Types a command into another app by switching to it and pressing ⌘V (and Return, to run it).
/// Also opens new terminal windows and tabs the same way, with ⌘N and ⌘T.
///
/// Sending keystrokes to another app needs Accessibility access
/// (System Settings → Privacy & Security → Accessibility).
@MainActor
final class TerminalPaster {
    enum Destination {
        /// Whatever app you were using before you opened Command Chain.
        case previousApp
        /// The most recent terminal app, so Return never lands in a browser or editor.
        case terminal
        /// A window or tab picked in the panel.
        case target(TerminalTarget)
    }

    /// The last app other than Command Chain that was in front.
    private(set) var previousApp: NSRunningApplication?
    /// The last terminal app that was in front, or any running one.
    private(set) var terminalApp: NSRunningApplication?
    private var observer: NSObjectProtocol?

    static let terminalBundleIDs: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "dev.warp.Warp",
        "com.mitchellh.ghostty", "net.kovidgoyal.kitty", "org.alacritty", "io.alacritty",
        "com.github.wez.wezterm", "co.zeit.hyper", "org.tabby",
    ]

    init() {
        // Reading windows from a terminal that's busy shouldn't freeze the panel.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 1)
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let workspace = NSWorkspace.shared
        if let front = workspace.frontmostApplication, front.processIdentifier != ownPID {
            previousApp = front
        }
        terminalApp = [workspace.frontmostApplication].compactMap { $0 }.first(where: Self.isTerminal)
            ?? workspace.runningApplications.first(where: Self.isTerminal)
        terminalApp.map(Self.remember)
        observer = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != ownPID else { return }
            MainActor.assumeIsolated {
                self?.previousApp = app
                if Self.isTerminal(app) {
                    self?.terminalApp = app
                    Self.remember(app)
                }
            }
        }
    }

    /// Saved so the terminal button can launch the terminal you use even after it has quit.
    private static func remember(_ terminal: NSRunningApplication) {
        UserDefaults.standard.set(terminal.bundleIdentifier, forKey: lastTerminalKey)
    }

    private static let lastTerminalKey = "lastTerminalBundleID"

    /// The terminal to launch when none is running: the last one you used, else Apple's Terminal.
    private var terminalToLaunch: URL? {
        let workspace = NSWorkspace.shared
        if let id = UserDefaults.standard.string(forKey: Self.lastTerminalKey),
           let url = workspace.urlForApplication(withBundleIdentifier: id) {
            return url
        }
        return workspace.urlForApplication(withBundleIdentifier: "com.apple.Terminal")
    }

    /// The terminal the terminal button would use, e.g. "iTerm".
    var terminalName: String {
        app(for: .terminal)?.localizedName
            ?? terminalToLaunch?.deletingPathExtension().lastPathComponent
            ?? "Terminal"
    }

    static func isTerminal(_ app: NSRunningApplication) -> Bool {
        app.bundleIdentifier.map(terminalBundleIDs.contains) ?? false
    }

    func app(for destination: Destination) -> NSRunningApplication? {
        let app: NSRunningApplication?
        switch destination {
        case .previousApp: app = previousApp
        case .terminal:
            // Fall back to any terminal that's open if the last one has quit.
            app = terminalApp.flatMap { $0.isTerminated ? nil : $0 }
                ?? NSWorkspace.shared.runningApplications.first(where: Self.isTerminal)
        case .target(let target): app = target.app
        }
        return app.flatMap { $0.isTerminated ? nil : $0 }
    }

    // MARK: Windows and tabs

    /// Every window and tab of every running terminal, starting with the terminal you used last.
    func allTargets() -> [TerminalTarget] {
        let last = app(for: .terminal)
        let others = NSWorkspace.shared.runningApplications.filter { Self.isTerminal($0) && $0 != last }
        return ([last].compactMap { $0 } + others).flatMap(Self.targets(in:))
    }

    /// Where ▶ goes when nothing is picked: the selected tab of the last terminal's front window.
    func frontTarget() -> TerminalTarget? {
        guard let app = app(for: .terminal) else { return nil }
        let targets = Self.targets(in: app)
        return targets.first(where: \.isFront) ?? targets.first
    }

    /// The picked window or tab as it is now (its title may have changed), or nil if it has closed.
    func resolve(_ target: TerminalTarget) -> TerminalTarget? {
        guard !target.app.isTerminated else { return nil }
        let current = Self.targets(in: target.app)
        if let same = current.first(where: { $0 == target }) { return same }
        // A window picked before it had tabs now shows a tab bar; use the tab that is that window.
        guard target.tab == nil else { return nil }
        return current.first { CFEqual($0.window, target.window) && $0.isSelectedTab }
    }

    /// The app's windows, front first, with one entry per tab for windows that have several.
    /// Only lists windows in the current Space, since that's all macOS reports.
    static func targets(in app: NSRunningApplication) -> [TerminalTarget] {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        let main = Self.element(element, kAXMainWindowAttribute)
        let windows = elements(element, kAXWindowsAttribute)
            .filter { string($0, kAXSubroleAttribute) == kAXStandardWindowSubrole }
        var result: [TerminalTarget] = []
        for (index, window) in windows.enumerated() {
            let windowTitle = string(window, kAXTitleAttribute) ?? ""
            let isFrontWindow = main.map { CFEqual($0, window) } ?? (index == 0)
            let tabs = tabButtons(in: window)
            guard tabs.count > 1 else {
                result.append(TerminalTarget(
                    app: app, window: window, tab: nil, title: windowTitle, windowTitle: windowTitle,
                    windowNumber: index + 1, tabNumber: nil, isFrontWindow: isFrontWindow, isSelectedTab: true
                ))
                continue
            }
            for (tabIndex, tab) in tabs.enumerated() {
                result.append(TerminalTarget(
                    app: app, window: window, tab: tab, title: string(tab, kAXTitleAttribute) ?? "",
                    windowTitle: windowTitle, windowNumber: index + 1, tabNumber: tabIndex + 1,
                    isFrontWindow: isFrontWindow, isSelectedTab: (attribute(tab, kAXValueAttribute) as? NSNumber)?.intValue == 1
                ))
            }
        }
        return result
    }

    /// Shows the target's tab and puts its window in front of the app's other windows.
    static func focus(_ target: TerminalTarget) {
        var window = target.window
        if let tab = target.tab {
            AXUIElementPerformAction(tab, kAXPressAction as CFString)
            // Each tab is its own window, and the tab bar moves to whichever one is showing.
            window = element(tab, kAXWindowAttribute) ?? window
        }
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(AXUIElementCreateApplication(target.app.processIdentifier), kAXFocusedWindowAttribute as CFString, window)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }

    /// The tab buttons of a window that uses standard macOS tabs (Terminal does; some apps draw their own).
    private static func tabButtons(in window: AXUIElement) -> [AXUIElement] {
        guard let bar = elements(window, kAXChildrenAttribute).first(where: { string($0, kAXRoleAttribute) == kAXTabGroupRole }) else {
            return []
        }
        return elements(bar, kAXChildrenAttribute).filter { string($0, kAXRoleAttribute) == kAXRadioButtonRole }
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    private static func element(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func elements(_ element: AXUIElement, _ name: String) -> [AXUIElement] {
        attribute(element, name) as? [AXUIElement] ?? []
    }

    private static func string(_ element: AXUIElement, _ name: String) -> String? {
        attribute(element, name) as? String
    }

    static var hasPermission: Bool { AXIsProcessTrusted() }

    /// Shows the system dialog that sends the user to the Accessibility settings.
    static func requestPermission() {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    /// Expects the command to already be on the clipboard. Returns false if it can't paste.
    func pasteClipboard(into destination: Destination, pressReturn: Bool = false) -> Bool {
        guard Self.hasPermission, let app = app(for: destination) else { return false }
        var picked: TerminalTarget?
        if case .target(let target) = destination { picked = target }
        switchTo(app, focusing: picked) {
            Self.press(Self.vKey, flags: .maskCommand)
            if pressReturn {
                // Let the paste land before running it.
                try? await Task.sleep(nanoseconds: 150_000_000)
                Self.press(Self.returnKey)
            }
        }
        return true
    }

    /// Opens a new window or tab in the last terminal you used. If no terminal is running it
    /// launches one instead, which opens a window by itself and needs no Accessibility access.
    /// Returns false if it couldn't.
    func openNewTerminal(_ kind: NewTerminalKind) -> Bool {
        if let target = app(for: .terminal) {
            guard Self.hasPermission else { return false }
            // With every window closed there's nothing to add a tab to, so open a window.
            let key = kind == .tab && Self.hasWindows(target) ? Self.tKey : Self.nKey
            switchTo(target) { Self.press(key, flags: .maskCommand) }
            return true
        }
        guard let url = terminalToLaunch else { return false }
        Self.closePanel()
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        return true
    }

    /// Closes the panel, brings `target` (and the `window` in it, if given) to the front,
    /// then presses `keys` once it has focus.
    private func switchTo(_ target: NSRunningApplication, focusing window: TerminalTarget? = nil, then keys: @escaping @MainActor () async -> Void) {
        Self.closePanel()
        window.map(Self.focus)
        if #available(macOS 14, *) { NSApp.yieldActivation(to: target) }
        target.activate(options: [])
        Task { @MainActor in
            for _ in 0..<20 where NSWorkspace.shared.frontmostApplication?.processIdentifier != target.processIdentifier {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            // Again once the app is in front, in case activating it brought another window forward.
            window.map(Self.focus)
            // Give the app a moment to focus its window before the keystroke arrives.
            try? await Task.sleep(nanoseconds: 100_000_000)
            await keys()
        }
    }

    /// Whether the app has any windows open. Assumes it does if it can't tell.
    private static func hasWindows(_ app: NSRunningApplication) -> Bool {
        var windows: CFTypeRef?
        let element = AXUIElementCreateApplication(app.processIdentifier)
        guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &windows) == .success,
              let list = windows as? [AXUIElement] else { return true }
        return !list.isEmpty
    }

    /// Closes the menu bar panel the same way clicking the menu bar icon again would.
    /// (It doesn't close by itself when another app comes to the front.)
    static func closePanel() {
        for window in NSApp.windows {
            if let button = statusButton(in: window.contentView) {
                button.performClick(nil)
                return
            }
        }
    }

    private static func statusButton(in view: NSView?) -> NSStatusBarButton? {
        guard let view else { return nil }
        if let button = view as? NSStatusBarButton { return button }
        for subview in view.subviews {
            if let button = statusButton(in: subview) { return button }
        }
        return nil
    }

    private static let vKey: CGKeyCode = 0x09 // kVK_ANSI_V
    private static let nKey: CGKeyCode = 0x2D // kVK_ANSI_N
    private static let tKey: CGKeyCode = 0x11 // kVK_ANSI_T
    private static let returnKey: CGKeyCode = 0x24 // kVK_Return

    private static func press(_ key: CGKeyCode, flags: CGEventFlags = []) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: isDown)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }
}
