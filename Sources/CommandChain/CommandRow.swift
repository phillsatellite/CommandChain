import CommandChainCore
import SwiftUI

/// One command inside the grouped card.
struct CommandRow: View {
    @EnvironmentObject private var store: CommandStore
    let command: String
    let isFirst: Bool
    let isLast: Bool

    @State private var isHovering = false
    @State private var copied = false

    var body: some View {
        let isFavorite = store.isFavorite(command)

        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(command)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) { store.toggleFavorite(command) }
            } label: {
                Image(systemName: isFavorite ? "star.fill" : "star")
            }
            .buttonStyle(CircleButtonStyle(tint: .yellow, isProminent: isFavorite))
            .help(isFavorite ? "Remove from Favorites" : "Add to Favorites")

            Button(action: copyOnly) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(CircleButtonStyle(tint: Theme.accent, isProminent: copied))
            .help("Copy to Clipboard")

            Button(action: run) {
                Image(systemName: "play.fill")
                    .offset(x: 1) // optically center the triangle
            }
            .buttonStyle(CircleButtonStyle(tint: Theme.accent, isFilled: true))
            .help("Run in \(store.runTargetName ?? "Terminal")")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(CardSlice(roundTop: isFirst, roundBottom: isLast).fill(isHovering ? Theme.cardHover : Theme.card))
        .overlay(alignment: .top) {
            // iOS-style inset separator between rows.
            if !isFirst {
                Rectangle().fill(Theme.separator).frame(height: 0.5).padding(.leading, 14)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(perform: click)
        .help("\(clickHint)\n\(command)")
        .contextMenu {
            Button("Run in \(store.runTargetName ?? "Terminal")", action: run)
            Button("Copy", action: copyOnly)
            Button(isFavorite ? "Remove from Favorites" : "Add to Favorites") { store.toggleFavorite(command) }
            Divider()
            Button("Remove from History", role: .destructive) { store.forget(command) }
        }
    }

    /// e.g. "Ran 3 times · iOS · Detox"
    private var subtitle: String {
        let count = store.count(of: command)
        let runs = count == 0 ? "Not run yet" : count == 1 ? "Ran once" : "Ran \(count) times"
        let categories = store.categories(of: command).map(\.title)
        return ([runs] + categories).joined(separator: " · ")
    }

    private var clickHint: String {
        guard store.pasteOnClick else { return "Click to copy" }
        return "Click to paste into \(store.pasteTargetName ?? "Terminal")"
    }

    private func click() {
        // If it pasted, the panel is closing, so there's no need for the checkmark.
        if !store.copyOrPaste(command) { showCopied() }
    }

    private func run() {
        // If it ran, the panel is closing, so there's no need for the checkmark.
        if !store.run(command) { showCopied() }
    }

    private func copyOnly() {
        store.copy(command)
        showCopied()
    }

    private func showCopied() {
        withAnimation(.easeOut(duration: 0.15)) { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeOut(duration: 0.2)) { copied = false }
        }
    }
}
