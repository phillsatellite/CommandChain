#if DEBUG
import AppKit
import SwiftUI

/// Debug builds only: `CommandCache --snapshot out.png [light|dark]` renders the popover to a PNG and exits.
/// Handy for checking layout without clicking the menu bar.
enum DebugSnapshot {
    @MainActor
    static func runIfRequested(store: CommandStore) {
        let args = CommandLine.arguments
        guard let flag = args.firstIndex(of: "--snapshot"), args.count > flag + 1 else { return }
        let output = URL(fileURLWithPath: args[flag + 1])
        let dark = args.count > flag + 2 && args[flag + 2] == "dark"

        let root = ContentView()
            .environmentObject(store)
            .background(Color(nsColor: .windowBackgroundColor))
        let host = NSHostingView(rootView: root)
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.frame = NSRect(x: 0, y: 0, width: 400, height: 540)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.backgroundColor = dark ? NSColor(white: 0.17, alpha: 1) : NSColor(white: 0.96, alpha: 1)
        window.contentView = host
        window.orderFrontRegardless()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            host.layoutSubtreeIfNeeded()
            let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: output)
            exit(0)
        }
    }
}
#endif
