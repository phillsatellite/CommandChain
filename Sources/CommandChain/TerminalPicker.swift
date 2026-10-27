import AppKit
import SwiftUI

/// The bar above the list: shows which terminal window ▶ (and click-to-paste) sends commands to,
/// and opens a menu of every open terminal window and tab to pick a different one.
struct TerminalPicker: View {
    @EnvironmentObject private var store: CommandStore
    @State private var anchor = MenuAnchor.Reference()

    var body: some View {
        let isPinned = store.pinnedTarget != nil
        let name = store.currentTargetName

        Button(action: showMenu) {
            HStack(spacing: 6) {
                Image(systemName: isPinned ? "pin.fill" : "macwindow")
                    .foregroundStyle(isPinned ? Theme.accent : Color.secondary)
                    .frame(width: 14)
                Text(isPinned ? "Pinned to" : "Sending to")
                    .foregroundStyle(.secondary)
                    .fixedSize()
                Text(name ?? "No terminal open")
                    .foregroundStyle(name == nil ? Color.secondary : Color.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .font(.system(size: 12, weight: .medium))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(MenuAnchor(reference: anchor))
        .help("Where ▶ and click-to-paste send commands. Click to pick another window or tab.")
    }

    /// Built on click rather than ahead of time, so it lists the windows open right now.
    private func showMenu() {
        guard let view = anchor.view else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false

        let automatic = MenuAction("Window You Were Last In") { store.pin(nil) }
        automatic.state = store.pinnedTarget == nil ? .on : .off
        menu.addItem(automatic)

        let targets = store.terminalTargets()
        if targets.isEmpty {
            menu.addItem(.separator())
            if TerminalPaster.hasPermission {
                menu.addItem(Self.label("No terminal windows open"))
            } else {
                menu.addItem(MenuAction("Allow Accessibility Access to List Windows…") {
                    TerminalPaster.openAccessibilitySettings()
                })
            }
        }

        var app: pid_t?
        var window: Int?
        for target in targets {
            if target.app.processIdentifier != app {
                app = target.app.processIdentifier
                window = nil
                menu.addItem(.separator())
                menu.addItem(Self.header(target.app.localizedName ?? "Terminal"))
            }
            // A window with tabs gets its title as a label, with its tabs indented under it.
            if target.tabNumber != nil, target.windowNumber != window {
                menu.addItem(Self.label(target.windowTitle))
            }
            window = target.windowNumber

            let item = MenuAction(Self.shortened(target.title.isEmpty ? "Untitled" : target.title)) { store.pin(target) }
            item.indentationLevel = target.tabNumber == nil ? 0 : 1
            item.state = store.pinnedTarget == target ? .on : .off
            menu.addItem(item)
        }

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: view)
    }

    private static func header(_ title: String) -> NSMenuItem {
        if #available(macOS 14, *) { return .sectionHeader(title: title) }
        return label(title)
    }

    private static func label(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: shortened(title), action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    /// Keeps long window titles from making the menu wider than the screen.
    private static func shortened(_ title: String) -> String {
        guard title.count > 60 else { return title }
        return title.prefix(40) + "…" + title.suffix(19)
    }
}

/// A menu item that runs a closure.
private final class MenuAction: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func fire() { handler() }
}

/// An invisible AppKit view to pop a menu up from.
private struct MenuAnchor: NSViewRepresentable {
    final class Reference {
        weak var view: NSView?
    }

    let reference: Reference

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        reference.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        reference.view = nsView
    }
}
