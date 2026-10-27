import CommandChainCore
import SwiftUI

/// The button next to the search field: narrows the list to commands for the tools you tick.
/// Ticking several shows commands for any of them.
struct ToolFilterMenu: View {
    /// The tools the current list's commands use.
    let tools: [CommandCategory]
    @Binding var selection: Set<CommandCategory>

    var body: some View {
        let isActive = !selection.isDisjoint(with: tools)

        Menu {
            if isActive {
                Button("Show All Commands") { selection = [] }
                Divider()
            }
            ForEach(tools) { tool in
                Toggle(isOn: Binding(
                    get: { selection.contains(tool) },
                    set: { isOn in
                        if isOn { selection.insert(tool) } else { selection.remove(tool) }
                    }
                )) {
                    Label(tool.title, systemImage: tool.systemImage)
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isActive ? Theme.accent : Color.secondary)
                .frame(width: 34, height: 33)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isActive ? Theme.accent.opacity(0.18) : Theme.fill)
                )
                .contentShape(Rectangle())
        }
        .modifier(PlainMenuStyle())
        .fixedSize()
        .disabled(tools.isEmpty)
        .opacity(tools.isEmpty ? 0.5 : 1)
        .help(tools.isEmpty ? "No tools to filter by in this list yet" : "Show only commands for certain tools")
    }
}

/// The tools the list is narrowed to, under the search field. Click one to stop filtering by it.
struct ToolFilterChips: View {
    let tools: [CommandCategory]
    @Binding var selection: Set<CommandCategory>

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tools) { tool in
                    Button { selection.remove(tool) } label: {
                        HStack(spacing: 5) {
                            Image(systemName: tool.systemImage)
                                .font(.system(size: 10, weight: .semibold))
                            Text(tool.title)
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(Capsule().fill(Theme.accent.opacity(0.18)))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Stop filtering by \(tool.title)")
                }
            }
            .padding(.horizontal, 16)
        }
    }
}
