import Foundation

/// Reads commands the shell hook appended to `inbox.log`.
public struct CommandInbox {
    public let paths: AppPaths

    public init(paths: AppPaths) {
        self.paths = paths
    }

    /// Moves the inbox aside and returns its commands, oldest first.
    /// Shells re-create `inbox.log` on their next append, so nothing written after the move is lost.
    public func drain() -> [String] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: paths.inbox.path) else { return [] }
        let claimed = paths.directory.appendingPathComponent("inbox-\(UUID().uuidString).processing")
        guard (try? fm.moveItem(at: paths.inbox, to: claimed)) != nil else { return [] }
        defer { try? fm.removeItem(at: claimed) }
        guard let data = try? Data(contentsOf: claimed) else { return [] }
        return Self.parse(String(decoding: data, as: UTF8.self))
    }

    public static func parse(_ text: String) -> [String] {
        text.split(separator: "\n").map(unescape).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// Reverses the hook's escaping: `\\` -> `\`, `\t` -> tab, `\n` -> newline.
    public static func unescape(_ line: Substring) -> String {
        var result = ""
        result.reserveCapacity(line.count)
        var escaping = false
        for ch in line {
            if escaping {
                switch ch {
                case "n": result.append("\n")
                case "t": result.append("\t")
                default: result.append(ch)
                }
                escaping = false
            } else if ch == "\\" {
                escaping = true
            } else {
                result.append(ch)
            }
        }
        if escaping { result.append("\\") }
        return result
    }
}
