import AppKit
import SwiftUI

/// iOS "grouped list" colors: near-black page with raised cards in dark mode,
/// light gray page with white cards in light mode.
enum Theme {
    static let background = Color.dynamic(light: rgb(0xF2F2F7), dark: rgb(0x000000))
    static let card = Color.dynamic(light: rgb(0xFFFFFF), dark: rgb(0x1C1C1E))
    static let cardHover = Color.dynamic(light: rgb(0xE9E9EE), dark: rgb(0x2C2C2E))
    /// Search bar and secondary button fill.
    static let fill = Color.dynamic(light: rgb(0x767680, alpha: 0.12), dark: rgb(0x767680, alpha: 0.24))
    static let separator = Color.dynamic(light: rgb(0x3C3C43, alpha: 0.18), dark: rgb(0x545458, alpha: 0.55))
    /// iOS system green, which also matches the app icon.
    static let accent = Color.dynamic(light: rgb(0x34C759), dark: rgb(0x30D158))

    static let cornerRadius: CGFloat = 12

    private static func rgb(_ hex: Int, alpha: CGFloat = 1) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension Color {
    static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}

/// Round icon button with a soft tinted fill, like iOS action buttons.
struct CircleButtonStyle: ButtonStyle {
    var tint: Color = .primary
    var isProminent = false

    func makeBody(configuration: Configuration) -> some View {
        CircleButton(configuration: configuration, tint: tint, isProminent: isProminent)
    }

    private struct CircleButton: View {
        let configuration: Configuration
        let tint: Color
        let isProminent: Bool
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isProminent ? tint : Color.secondary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(isProminent ? tint.opacity(0.18) : Theme.fill))
                .overlay(Circle().fill(Color.primary.opacity(configuration.isPressed ? 0.15 : isHovering ? 0.07 : 0)))
                .contentShape(Circle())
                .onHover { isHovering = $0 }
        }
    }
}

/// Capsule button. Prominent = solid accent, otherwise a gray fill.
struct PillButtonStyle: ButtonStyle {
    var isProminent = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(isProminent ? Color.black : Color.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Capsule().fill(isProminent ? Theme.accent : Theme.fill))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}

/// White glyph on a colored rounded square, like the icons in iOS Settings.
struct IconTile: View {
    let systemImage: String
    let color: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(color))
    }
}

/// A row's slice of a grouped card: only the first and last rows get rounded corners,
/// so consecutive rows read as one card.
struct CardSlice: Shape {
    var roundTop: Bool
    var roundBottom: Bool
    var radius: CGFloat = Theme.cornerRadius

    func path(in rect: CGRect) -> Path {
        let top = roundTop ? min(radius, rect.height / 2) : 0
        let bottom = roundBottom ? min(radius, rect.height / 2) : 0
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + top))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.minX + top, y: rect.minY), radius: top)
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY + top), radius: top)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottom))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.maxX - bottom, y: rect.maxY), radius: bottom)
        path.addLine(to: CGPoint(x: rect.minX + bottom, y: rect.maxY))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY - bottom), radius: bottom)
        path.closeSubpath()
        return path
    }
}
