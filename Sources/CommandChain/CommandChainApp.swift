import AppKit
import SwiftUI

@main
struct CommandChainApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = CommandStore()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(store)
        } label: {
            Image(systemName: "terminal")
                .onAppear {
                    #if DEBUG
                    DebugSnapshot.runIfRequested(store: store)
                    #endif
                }
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only: no Dock icon (also set via LSUIElement in the bundled app's Info.plist).
        NSApp.setActivationPolicy(.accessory)
    }
}
