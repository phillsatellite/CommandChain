import AppKit
import SwiftUI

struct FooterBar: View {
    @EnvironmentObject private var store: CommandStore
    let totalCount: Int

    var body: some View {
        HStack {
            Menu {
                Toggle("Capture Terminal Commands", isOn: Binding(
                    get: { !store.isPaused },
                    set: { store.setPaused(!$0) }
                ))
                .disabled(!store.shellIntegrationInstalled)

                Toggle("Launch at Login", isOn: Binding(
                    get: { store.launchesAtLogin },
                    set: { store.setLaunchesAtLogin($0) }
                ))

                Divider()

                Button("Import Existing Shell History") { importHistory() }
                if store.shellIntegrationInstalled {
                    Button("Remove Shell Integration…") { confirmUninstall() }
                } else {
                    Button("Enable Shell Integration") { store.installShellIntegration() }
                }

                Divider()

                Button("Clear Recent") { store.clearRecent() }
                Button("Clear All History…") { confirmClearAll() }

                Divider()

                Button("About Command Chain") {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.orderFrontStandardAboutPanel(nil)
                }
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Settings")

            Spacer()

            HStack(spacing: 5) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                Text(statusText)
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

            Spacer()

            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
                .font(.system(size: 12))
                .keyboardShortcut("q")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var statusColor: Color {
        if !store.shellIntegrationInstalled { return .gray }
        return store.isPaused ? .orange : .green
    }

    private var statusText: String {
        if !store.shellIntegrationInstalled { return "Capture off" }
        if store.isPaused { return "Paused" }
        return totalCount == 1 ? "1 command saved" : "\(totalCount) commands saved"
    }

    private func importHistory() {
        let count = store.importShellHistory()
        alert(
            title: count == 0 ? "Nothing to Import" : "Imported \(count) Commands",
            message: count == 0 ? "No ~/.zsh_history or ~/.bash_history file was found." : "Most Used and the platform lists now include your existing shell history."
        )
    }

    private func confirmUninstall() {
        guard confirm(
            title: "Remove Shell Integration?",
            message: "Command Chain will remove its line from your shell profile and stop recording new commands. Your saved history stays.",
            action: "Remove"
        ) else { return }
        store.uninstallShellIntegration()
    }

    private func confirmClearAll() {
        guard confirm(
            title: "Clear All History?",
            message: "This removes every saved command and usage count. Favorites are kept.",
            action: "Clear"
        ) else { return }
        store.clearHistory()
    }

    private func confirm(title: String, message: String, action: String) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: action).hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func alert(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
