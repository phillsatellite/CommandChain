import AppKit
import CommandChainCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: CommandStore
    @AppStorage("selectedFilter") private var storedFilter: CommandFilter = .recent
    @State private var query = ""
    @State private var isAddingFavorite = false
    @State private var newFavorite = ""
    @State private var justInstalled = false
    /// Tools picked with the filter button; the list only shows commands for these. Empty = no filter.
    @State private var toolFilter: Set<CommandCategory>

    init(toolFilter: Set<CommandCategory> = []) {
        _toolFilter = State(initialValue: toolFilter)
    }

    /// The saved choice, unless it's a category that no longer has commands (e.g. after clearing history).
    private var filter: CommandFilter {
        if case .category(let category) = storedFilter, !store.categoriesInUse.contains(category) {
            return .recent
        }
        return storedFilter
    }

    /// Switching lists also clears the tool filter, so it never quietly hides commands somewhere else.
    private var filterSelection: Binding<CommandFilter> {
        Binding(get: { filter }, set: { storedFilter = $0; toolFilter = [] })
    }

    var body: some View {
        let tools = store.tools(in: filter)
        // Only the picked tools that this list still has, e.g. after removing the last Docker command.
        let activeTools = toolFilter.intersection(tools)
        let commands = store.commands(for: filter, matching: query, tools: activeTools)

        VStack(spacing: 0) {
            header
            HStack(spacing: 8) {
                SearchField(text: $query)
                ToolFilterMenu(tools: tools, selection: $toolFilter)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
            if !activeTools.isEmpty {
                ToolFilterChips(tools: tools.filter(activeTools.contains), selection: $toolFilter)
                    .padding(.bottom, 10)
            }
            TerminalPicker()
                .padding(.horizontal, 20)
                .padding(.bottom, 10)

            if filter == .favorites && isAddingFavorite {
                addFavoriteField
            }

            if !store.shellIntegrationInstalled {
                SetupBanner { store.installShellIntegration(); justInstalled = true }
            } else if justInstalled {
                Notice(systemImage: "checkmark.circle.fill", tint: Theme.accent,
                       text: "Capture is on. Open a new Terminal window to start recording.") {
                    justInstalled = false
                }
            }
            if store.showsUpdateBanner, let update = store.availableUpdate {
                UpdateBanner(release: update)
            }
            if store.needsAccessibility {
                AccessibilityBanner()
            }
            if let error = store.lastError {
                Notice(systemImage: "exclamationmark.triangle.fill", tint: .orange, text: error) {
                    store.lastError = nil
                }
            }

            Group {
                if commands.isEmpty {
                    EmptyState(filter: filter, isSearching: !query.isEmpty, isFiltered: !activeTools.isEmpty) {
                        toolFilter = []
                    }
                } else {
                    list(commands, isFiltered: !activeTools.isEmpty)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            FooterBar(totalCount: store.history.stats.count)
        }
        .background(Theme.background)
        // Opaque instead of the see-through menu bar glass; matches the panel's corner radius.
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .tint(Theme.accent)
        .frame(width: 400, height: 560)
        .onAppear {
            store.refreshIntegrationStatus()
            store.refreshAccessibilityStatus()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            // A pull-down, not a pop-up: pop-ups line the selected item up with the button,
            // which pushes earlier items off the top of the screen this close to the menu bar.
            Menu {
                Picker("Show", selection: filterSelection) {
                    ForEach(CommandFilter.fixed) { option in
                        Label(option.title, systemImage: option.systemImage).tag(option)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()

                // A tab per platform or tool, added once you've run a command for it.
                let categories = store.categoriesInUse
                if !categories.isEmpty {
                    Divider()
                    Picker("Categories", selection: filterSelection) {
                        ForEach(categories) { category in
                            Label(category.title, systemImage: category.systemImage)
                                .tag(CommandFilter.category(category))
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            } label: {
                ListMenuLabel(filter: filter)
            }
            .modifier(PlainMenuStyle())
            .fixedSize()

            Spacer()

            if filter == .favorites {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { isAddingFavorite.toggle() }
                } label: {
                    Image(systemName: isAddingFavorite ? "xmark" : "plus")
                }
                .buttonStyle(CircleButtonStyle(tint: Theme.accent, isProminent: true))
                .help(isAddingFavorite ? "Cancel" : "Add a favorite command")
            }

            newTerminalButton
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    /// Opens a new terminal window, or a tab if that's picked in settings. Right-click for either.
    private var newTerminalButton: some View {
        let kind = store.newTerminalKind
        return Button { store.openNewTerminal() } label: {
            Image(systemName: kind.systemImage)
        }
        .buttonStyle(CircleButtonStyle())
        .help("New \(store.newTerminalName) \(kind.title) (right-click for a \(kind == .window ? "tab" : "window"))")
        .contextMenu {
            ForEach(NewTerminalKind.allCases) { option in
                Button { store.openNewTerminal(option) } label: {
                    Label("New \(option.title)", systemImage: option.systemImage)
                }
            }
        }
    }

    private var addFavoriteField: some View {
        HStack(spacing: 8) {
            TextField("e.g. npx detox test -c ios.sim.debug", text: $newFavorite)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .onSubmit(saveNewFavorite)
            Button("Add", action: saveNewFavorite)
                .buttonStyle(PillButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(newFavorite.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).fill(Theme.card))
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func saveNewFavorite() {
        store.addFavorite(newFavorite)
        newFavorite = ""
        isAddingFavorite = false
    }

    private func list(_ commands: [String], isFiltered: Bool) -> some View {
        // Dragging only makes sense in the full, unfiltered favorites list.
        let canReorder = filter == .favorites && query.isEmpty && !isFiltered
        return List {
            ForEach(Array(commands.enumerated()), id: \.element) { index, command in
                CommandRow(command: command, isFirst: index == 0, isLast: index == commands.count - 1)
                    // The list adds its own 8pt margin, so this lines the card up with the search bar.
                    .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            .onMove(perform: canReorder ? { store.moveFavorites(from: $0, to: $1) } : nil)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 1)
        // A fresh list per filter, so switching filters always starts at the top
        // instead of keeping the previous filter's scroll position.
        .id(filter)
    }
}

/// Lets the title menu draw its own SwiftUI label instead of a standard pop-up button.
struct PlainMenuStyle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 14, *) {
            content.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
        } else {
            content.menuStyle(.borderlessButton).menuIndicator(.hidden)
        }
    }
}

// MARK: - Pieces

/// The list picker's button: a raised pill with the list's icon, name and a chevron,
/// so it reads as something to click rather than a heading.
struct ListMenuLabel: View {
    let filter: CommandFilter
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: filter.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text(filter.title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.primary)
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 12)
        .padding(.trailing, 11)
        .frame(height: 34)
        .background(Capsule().fill(isHovering ? Theme.cardHover : Theme.card))
        .contentShape(Capsule())
        .onHover { isHovering = $0 }
    }
}

struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search", text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .font(.system(size: 14))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.fill))
    }
}

/// iOS-style card with a Settings-like icon tile, used for setup prompts.
struct PromptCard<Buttons: View>: View {
    let systemImage: String
    let color: Color
    let title: String
    let message: String
    @ViewBuilder let buttons: Buttons

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IconTile(systemImage: systemImage, color: color)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) { buttons }
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).fill(Theme.card))
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
}

struct SetupBanner: View {
    let enable: () -> Void

    var body: some View {
        PromptCard(
            systemImage: "terminal.fill",
            color: Theme.accent,
            title: "Turn on terminal capture",
            message: "Adds one line to ~/.zshrc so commands you run are saved here. Start a command with a space to keep it private."
        ) {
            Button("Enable", action: enable).buttonStyle(PillButtonStyle())
        }
    }
}

struct AccessibilityBanner: View {
    @EnvironmentObject private var store: CommandStore

    var body: some View {
        PromptCard(
            systemImage: "hand.raised.fill",
            color: .orange,
            title: "Allow pasting into Terminal",
            message: "Turn on Command Chain in Privacy & Security → Accessibility. Until then, clicking a command or ▶ only copies it.\n\nAlready on? A new version can't use the old entry, and switching it off and on isn't enough. Select Command Chain in that list, remove it with −, then turn this setting on again."
        ) {
            Button("Open Settings") { TerminalPaster.openAccessibilitySettings() }
                .buttonStyle(PillButtonStyle())
            Button("Not Now") { store.needsAccessibility = false }
                .buttonStyle(PillButtonStyle(isProminent: false))
        }
    }
}

struct UpdateBanner: View {
    @EnvironmentObject private var store: CommandStore
    let release: AppRelease

    var body: some View {
        PromptCard(
            systemImage: "arrow.down.circle.fill",
            color: .blue,
            title: "Command Chain \(release.version) is available",
            message: "Download it, quit Command Chain, then drag the new version into Applications and choose Replace. Your history is kept."
        ) {
            Button("Download") { store.openUpdatePage() }
                .buttonStyle(PillButtonStyle())
            Button("Not Now") { store.dismissUpdate() }
                .buttonStyle(PillButtonStyle(isProminent: false))
        }
    }
}

struct Notice: View {
    let systemImage: String
    let tint: Color
    let text: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 15))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: dismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(CircleButtonStyle())
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).fill(Theme.card))
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
}

struct EmptyState: View {
    let filter: CommandFilter
    let isSearching: Bool
    /// The tool filter is on, which only empties a list together with a search.
    var isFiltered = false
    var clearFilter: () -> Void = {}

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: isSearching ? "magnifyingglass" : filter.systemImage)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 64, height: 64)
                .background(Circle().fill(Theme.fill))
            Text(isSearching ? "No Results" : title)
                .font(.system(size: 17, weight: .semibold))
            Text(isSearching ? (isFiltered ? "Try a different search, or clear the tool filter." : "Try a different search.") : message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
            if isFiltered {
                Button("Clear Filter", action: clearFilter)
                    .buttonStyle(PillButtonStyle(isProminent: false))
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 24)
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
        case .favorites: return "Tap the star next to any command, or use + to add one."
        case .recent, .mostUsed: return "Commands you run in Terminal will show up here. Tabs for iOS, Git, Docker and more appear as you use them."
        case .category(let category): return "\(category.title) commands you run will show up here."
        }
    }
}
