import Foundation

/// One-time seeding from the shell's own history file, so Most Used isn't empty on day one.
public enum HistoryImporter {
    public struct Entry: Equatable {
        public var command: String
        public var date: Date?
    }

    public static func defaultFiles(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        [".zsh_history", ".bash_history"]
            .map { home.appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    public static func load(_ url: URL) -> [Entry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return parse(String(decoding: unmetafy(data), as: UTF8.self))
    }

    /// Handles plain lines, zsh's EXTENDED_HISTORY (`: 1698000000:0;cmd`) and `\`-continued multi-line commands.
    public static func parse(_ text: String) -> [Entry] {
        var entries: [Entry] = []
        var pending: Entry?
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if var current = pending {
                current.command += "\n" + line
                pending = finish(current, into: &entries)
                continue
            }
            var entry = Entry(command: String(line), date: nil)
            if line.hasPrefix(": "), let semicolon = line.firstIndex(of: ";") {
                let meta = line[line.index(line.startIndex, offsetBy: 2)..<semicolon]
                if let stamp = meta.split(separator: ":").first.flatMap({ TimeInterval($0) }) {
                    entry.date = Date(timeIntervalSince1970: stamp)
                }
                entry.command = String(line[line.index(after: semicolon)...])
            }
            pending = finish(entry, into: &entries)
        }
        if let leftover = pending { entries.append(leftover) }
        return entries.filter { !$0.command.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// Returns the entry back if it continues on the next line, otherwise stores it.
    private static func finish(_ entry: Entry, into entries: inout [Entry]) -> Entry? {
        if entry.command.hasSuffix("\\") {
            var continued = entry
            continued.command.removeLast()
            return continued
        }
        entries.append(entry)
        return nil
    }

    /// zsh stores bytes >= 0x83 as 0x83 followed by (byte ^ 0x20).
    static func unmetafy(_ data: Data) -> Data {
        guard data.contains(0x83) else { return data }
        var out = Data(capacity: data.count)
        var meta = false
        for byte in data {
            if meta { out.append(byte ^ 0x20); meta = false }
            else if byte == 0x83 { meta = true }
            else { out.append(byte) }
        }
        return out
    }
}
