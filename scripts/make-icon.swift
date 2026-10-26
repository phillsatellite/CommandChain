// Renders the 1024px app icon: a macOS-style squircle with a terminal prompt.
// Usage: swift scripts/make-icon.swift <output.png>
import AppKit

let size: CGFloat = 1024
let output = CommandLine.arguments.dropFirst().first ?? "AppIcon.png"

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Apple's icon grid: 824px body centred in 1024 with ~185px corner radius.
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let squircle = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.shadowBlurRadius = 24
shadow.shadowOffset = NSSize(width: 0, height: -10)
NSGraphicsContext.saveGraphicsState()
shadow.set()
NSColor.black.setFill()
squircle.fill()
NSGraphicsContext.restoreGraphicsState()

NSGradient(colors: [
    NSColor(calibratedRed: 0.20, green: 0.22, blue: 0.27, alpha: 1),
    NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.10, alpha: 1),
])!.draw(in: squircle, angle: -90)

// Title bar with traffic lights.
NSGraphicsContext.saveGraphicsState()
squircle.addClip()
NSColor.white.withAlphaComponent(0.07).setFill()
NSRect(x: 100, y: 790, width: 824, height: 134).fill()
for (i, color) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
    color.setFill()
    NSBezierPath(ovalIn: NSRect(x: 190 + CGFloat(i) * 62, y: 836, width: 42, height: 42)).fill()
}
NSGraphicsContext.restoreGraphicsState()

// Prompt ">" and stacked history lines.
let chevron = NSBezierPath()
chevron.lineWidth = 46
chevron.lineCapStyle = .round
chevron.lineJoinStyle = .round
chevron.move(to: NSPoint(x: 230, y: 640))
chevron.line(to: NSPoint(x: 340, y: 560))
chevron.line(to: NSPoint(x: 230, y: 480))
NSColor(calibratedRed: 0.35, green: 0.85, blue: 0.55, alpha: 1).setStroke()
chevron.stroke()

for (i, width) in [360.0, 280.0, 220.0].enumerated() {
    let y = 545 - CGFloat(i) * 120
    let alpha = 1.0 - Double(i) * 0.3
    NSColor.white.withAlphaComponent(alpha).setFill()
    NSBezierPath(roundedRect: NSRect(x: 400, y: y, width: width, height: 36), xRadius: 18, yRadius: 18).fill()
}

// Star = favorites.
let star = NSBezierPath()
let center = NSPoint(x: 740, y: 255)
for i in 0..<10 {
    let radius: CGFloat = i % 2 == 0 ? 78 : 34
    let angle = CGFloat(i) * .pi / 5 + .pi / 2
    let point = NSPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
    i == 0 ? star.move(to: point) : star.line(to: point)
}
star.close()
NSColor.systemYellow.setFill()
star.fill()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
