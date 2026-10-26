import CommandChainCore
import SwiftUI

struct CommandRow: View {
    @EnvironmentObject private var store: CommandStore
    let command: String
    let filter: CommandFilter

    @State private var isHovering = false
    @State private var copied = false

    var body: some View {
        let isFavorite = store.isFavorite(command)

        HStack(spacing: 6) {
            Text(command)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(command)

            if filter == .mostUsed {
                Text("\(store.count(of: command))×")
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.quaternary))
            }

            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) { store.toggleFavorite(command) }
            } label: {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .foregroundStyle(isFavorite ? AnyShapeStyle(Color.yellow) : AnyShapeStyle(.tertiary))
                    .scaleEffect(isFavorite ? 1.05 : 1)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help(isFavorite ? "Remove from Favorites" : "Add to Favorites")

            Button(action: copy) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .foregroundStyle(copied ? AnyShapeStyle(Color.green) : AnyShapeStyle(.secondary))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("Copy to Clipboard")
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isHovering ? Color.primary.opacity(0.07) : .clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(perform: copy)
        .contextMenu {
            Button("Copy", action: copy)
            Button(isFavorite ? "Remove from Favorites" : "Add to Favorites") { store.toggleFavorite(command) }
            Divider()
            Button("Remove from History", role: .destructive) { store.forget(command) }
        }
    }

    private func copy() {
        store.copy(command)
        withAnimation(.easeOut(duration: 0.15)) { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeOut(duration: 0.2)) { copied = false }
        }
    }
}
