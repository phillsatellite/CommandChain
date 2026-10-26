import Foundation

public struct AppPaths {
    public let directory: URL

    /// `COMMANDCHAIN_HOME` overrides the location (used by tests and the hook script).
    public static var standard: AppPaths {
        if let override = ProcessInfo.processInfo.environment["COMMANDCHAIN_HOME"], !override.isEmpty {
            return AppPaths(directory: URL(fileURLWithPath: override, isDirectory: true))
        }
        return AppPaths(directory: defaultDirectory)
    }

    public static var defaultDirectory: URL {
        supportDirectory.appendingPathComponent("CommandChain", isDirectory: true)
    }

    /// Builds from before the rename kept their data under "CommandCache". Moves it over once.
    public static func migrateFromCommandCache() {
        let fm = FileManager.default
        let legacy = supportDirectory.appendingPathComponent("CommandCache", isDirectory: true)
        guard !fm.fileExists(atPath: defaultDirectory.path), fm.fileExists(atPath: legacy.path) else { return }
        try? fm.moveItem(at: legacy, to: defaultDirectory)
    }

    private static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    public init(directory: URL) {
        self.directory = directory
    }

    public var store: URL { directory.appendingPathComponent("store.json") }
    public var inbox: URL { directory.appendingPathComponent("inbox.log") }
    public var hookScript: URL { directory.appendingPathComponent("hook.sh") }
    /// While this file exists the shell hook records nothing.
    public var pauseFlag: URL { directory.appendingPathComponent("paused") }

    public func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
