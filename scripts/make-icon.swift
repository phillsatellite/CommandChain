// Renders the 1024px app icon: a macOS-style terminal window with a prompt and two chain links.
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

let green = NSColor(calibratedRed: 0.35, green: 0.85, blue: 0.55, alpha: 1)

// Prompt ">" in the empty top-left corner.
let chevron = NSBezierPath()
chevron.lineWidth = 40
chevron.lineCapStyle = .round
chevron.lineJoinStyle = .round
chevron.move(to: NSPoint(x: 205, y: 705))
chevron.line(to: NSPoint(x: 290, y: 645))
chevron.line(to: NSPoint(x: 205, y: 585))
green.setStroke()
chevron.stroke()

// Two interlocking chain links on a diagonal. Each link is a stroked capsule; the
// second crossing is redrawn so link A passes over B at one point and under it at the other.
let ctx = NSGraphicsContext.current!.cgContext
let chainCenter = CGPoint(x: 545, y: 420)
let angle = 35 * CGFloat.pi / 180
let linkLength: CGFloat = 300, linkHeight: CGFloat = 150, spacing: CGFloat = 200, stroke: CGFloat = 52
let gapColor = NSColor(calibratedRed: 0.11, green: 0.12, blue: 0.15, alpha: 1).cgColor

func chainTransform(_ offset: CGFloat) -> CGAffineTransform {
    CGAffineTransform(translationX: chainCenter.x, y: chainCenter.y).rotated(by: angle).translatedBy(x: offset, y: 0)
}

func linkRing(at offset: CGFloat) -> CGPath {
    var transform = chainTransform(offset)
    let rect = CGRect(x: -linkLength / 2, y: -linkHeight / 2, width: linkLength, height: linkHeight)
    let capsule = CGPath(roundedRect: rect, cornerWidth: linkHeight / 2, cornerHeight: linkHeight / 2, transform: &transform)
    return capsule.copy(strokingWithWidth: stroke, lineCap: .round, lineJoin: .round, miterLimit: 10)
}

func drawLink(_ ring: CGPath, colors: [NSColor], clip: CGPath? = nil) {
    ctx.saveGState()
    if let clip { ctx.addPath(clip); ctx.clip() }
    // One layer per link, so a partial redraw blends in without a seam at the clip edge.
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    // A dark outline cuts a gap into whatever link is underneath, which sells the overlap.
    ctx.addPath(ring)
    ctx.setStrokeColor(gapColor)
    ctx.setLineWidth(22)
    ctx.strokePath()
    ctx.saveGState()
    ctx.addPath(ring)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors.map(\.cgColor) as CFArray, locations: nil)!
    let box = ring.boundingBox
    ctx.drawLinearGradient(gradient, start: CGPoint(x: box.minX, y: box.maxY), end: CGPoint(x: box.maxX, y: box.minY), options: [])
    ctx.restoreGState()
    ctx.endTransparencyLayer()
    ctx.restoreGState()
}

let linkA = linkRing(at: -spacing / 2)
let linkB = linkRing(at: spacing / 2)
let silver = [NSColor.white, NSColor(calibratedWhite: 0.78, alpha: 1)]
let greens = [NSColor(calibratedRed: 0.55, green: 0.95, blue: 0.70, alpha: 1), NSColor(calibratedRed: 0.20, green: 0.70, blue: 0.42, alpha: 1)]

drawLink(linkA, colors: silver)
drawLink(linkB, colors: greens)
// Redraw A over B on the upper side of the chain's axis only.
var upper = chainTransform(0)
drawLink(linkA, colors: silver, clip: CGPath(rect: CGRect(x: -600, y: 0, width: 1200, height: 600), transform: &upper))

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
