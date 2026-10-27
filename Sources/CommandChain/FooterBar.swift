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

                Toggle("Paste into Terminal on Click", isOn: Binding(
                    get: { store.pasteOnClick },
                    set: { store.setPasteOnClick($0) }
                ))

                Picker("Terminal Button Opens", selection: Binding(
                    get: { store.newTerminalKind },
                    set: { store.setNewTerminalKind($0) }
                )) {
                    ForEach(NewTerminalKind.allCases) { kind in
                        Text("New \(kind.title)").tag(kind)
                    }
                }
                .pickerStyle(.menu)

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
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Theme.fill))
                    .contentShape(Circle())
            }
            .modifier(PlainMenuStyle())
            .fixedSize()
            .help("Settings")

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                Text(statusText)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)

            Spacer()

            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(PillButtonStyle(isProminent: false))
                .keyboardShortcut("q")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.separator).frame(height: 0.5)
        }
    }

    private var statusColor: Color {
        if !store.shellIntegrationInstalled { return .gray }
        return store.isPaused ? .orange : Theme.accent
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
