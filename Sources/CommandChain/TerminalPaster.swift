import AppKit
import ApplicationServices

/// Pastes a command into the app you were using before you opened Command Chain
/// (usually Terminal), by switching back to it and pressing ⌘V.
///
/// Sending keystrokes to another app needs Accessibility access
/// (System Settings → Privacy & Security → Accessibility).
@MainActor
final class TerminalPaster {
    /// The last app other than Command Chain that was in front.
    private(set) var targetApp: NSRunningApplication?
    private var observer: NSObjectProtocol?

    init() {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != ownPID {
            targetApp = front
        }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != ownPID else { return }
            MainActor.assumeIsolated { self?.targetApp = app }
        }
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
    func pasteClipboard() -> Bool {
        guard Self.hasPermission, let target = targetApp, !target.isTerminated else { return false }
        Self.closePanel()
        if #available(macOS 14, *) { NSApp.yieldActivation(to: target) }
        target.activate(options: [])
        Task { @MainActor in
            for _ in 0..<20 where NSWorkspace.shared.frontmostApplication?.processIdentifier != target.processIdentifier {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            // Give the app a moment to focus its window before the keystroke arrives.
            try? await Task.sleep(nanoseconds: 100_000_000)
            Self.pressCommandV()
        }
        return true
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

    private static func pressCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 0x09 // kVK_ANSI_V
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: isDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }
}
