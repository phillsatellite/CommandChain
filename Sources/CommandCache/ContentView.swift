import AppKit
import CommandCacheCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: CommandStore
    @AppStorage("selectedFilter") private var filter: CommandFilter = .recent
    @State private var query = ""
    @State private var isAddingFavorite = false
    @State private var newFavorite = ""
    @State private var justInstalled = false

    var body: some View {
        let commands = store.commands(for: filter, matching: query)

        VStack(spacing: 0) {
            header
            SearchField(text: $query)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)

            if filter == .favorites && isAddingFavorite {
                addFavoriteField
            }

            Divider()

            if !store.shellIntegrationInstalled {
                SetupBanner { store.installShellIntegration(); justInstalled = true }
            } else if justInstalled {
                Notice(systemImage: "checkmark.circle.fill", tint: .green,
                       text: "Capture is on. Open a new Terminal window to start recording.") {
                    justInstalled = false
                }
            }
            if let error = store.lastError {
                Notice(systemImage: "exclamationmark.triangle.fill", tint: .orange, text: error) {
                    store.lastError = nil
                }
            }

            if commands.isEmpty {
                EmptyState(filter: filter, isSearching: !query.isEmpty)
            } else {
                list(commands)
            }

            Divider()
            FooterBar(totalCount: store.history.stats.count)
        }
        .frame(width: 400, height: 540)
        .onAppear { store.refreshIntegrationStatus() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            // A pull-down, not a pop-up: pop-ups line the selected item up with the button,
            // which pushes earlier items off the top of the screen this close to the menu bar.
            Menu {
                Picker("Show", selection: $filter) {
                    ForEach(CommandFilter.allCases) { option in
                        Label(option.title, systemImage: option.systemImage).tag(option)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                Label(filter.title, systemImage: filter.systemImage)
            }
            .fixedSize()

            Spacer()

            if filter == .favorites {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { isAddingFavorite.toggle() }
                } label: {
                    Image(systemName: isAddingFavorite ? "xmark.circle.fill" : "plus.circle.fill")
                        .font(.system(size: 16))
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.borderless)
                .help(isAddingFavorite ? "Cancel" : "Add a favorite command")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var addFavoriteField: some View {
        HStack(spacing: 8) {
            TextField("Command to save, e.g. npx detox test -c ios.sim.debug", text: $newFavorite)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
                .onSubmit(saveNewFavorite)
            Button("Add", action: saveNewFavorite)
                .keyboardShortcut(.defaultAction)
                .disabled(newFavorite.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func saveNewFavorite() {
        store.addFavorite(newFavorite)
        newFavorite = ""
        isAddingFavorite = false
    }

    private func list(_ commands: [String]) -> some View {
        let canReorder = filter == .favorites && query.isEmpty
        return List {
            ForEach(commands, id: \.self) { command in
                CommandRow(command: command, filter: filter)
                    .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
                    .listRowSeparator(.hidden)
            }
            .onMove(perform: canReorder ? { store.moveFavorites(from: $0, to: $1) } : nil)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 30)
    }
}

// MARK: - Pieces

struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search commands", text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.quaternary.opacity(0.6)))
    }
}

struct SetupBanner: View {
    let enable: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "terminal.fill")
                .font(.system(size: 20))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text("Turn on terminal capture")
                    .font(.system(size: 13, weight: .semibold))
                Text("Adds one line to ~/.zshrc so commands you run are saved here. Start a command with a space to keep it private.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Enable", action: enable)
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.accentColor.opacity(0.1)))
        .padding(10)
    }
}

struct Notice: View {
    let systemImage: String
    let tint: Color
    let text: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage).foregroundStyle(tint)
            Text(text)
                .font(.system(size: 11))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: dismiss) {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint.opacity(0.1)))
        .padding(.horizontal, 10)
        .padding(.top, 8)
    }
}

struct EmptyState: View {
    let filter: CommandFilter
    let isSearching: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: isSearching ? "magnifyingglass" : filter.systemImage)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)
            Text(isSearching ? "No Matches" : title)
                .font(.system(size: 13, weight: .semibold))
            Text(isSearching ? "Try a different search." : message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var title: String {
        switch filter {
        case .favorites: return "No Favorites"
        case .recent, .mostUsed: return "No Commands Yet"
        default: return "No \(filter.title) Commands"
        }
    }

    private var message: String {
        switch filter {
        case .favorites: return "Click the star next to any command, or use + to add one."
        case .recent, .mostUsed: return "Commands you run in Terminal will show up here."
        case .android: return "adb, gradlew, emulator and run-android commands appear here."
        case .ios: return "xcodebuild, xcrun, pod and run-ios commands appear here."
        case .detox: return "Any command that runs Detox appears here."
        }
    }
}
