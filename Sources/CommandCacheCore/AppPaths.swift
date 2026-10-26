import Foundation

public struct AppPaths {
    public let directory: URL

    /// `COMMANDCACHE_HOME` overrides the location (used by tests and the hook script).
    public static var standard: AppPaths {
        if let override = ProcessInfo.processInfo.environment["COMMANDCACHE_HOME"], !override.isEmpty {
            return AppPaths(directory: URL(fileURLWithPath: override, isDirectory: true))
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return AppPaths(directory: support.appendingPathComponent("CommandCache", isDirectory: true))
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
