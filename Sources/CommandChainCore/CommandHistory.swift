import Foundation

public struct CommandStats: Codable, Equatable {
    public var count: Int
    public var firstUsed: Date
    public var lastUsed: Date
}

/// Everything Command Chain remembers. Value type so the rules are easy to test.
public struct CommandHistory: Codable, Equatable {
    /// The Recent list never holds more than this many commands.
    public static let recentLimit = 30
    /// Cap on how many distinct commands we keep counts for (feeds Most Used and the platform lists).
    public static let statsLimit = 5000
    public static let mostUsedLimit = 50
    /// Commands not worth remembering.
    public static let ignored: Set<String> = ["exit", "clear", "logout", "reset"]

    /// Newest first, no duplicates.
    public private(set) var recent: [String] = []
    public private(set) var stats: [String: CommandStats] = [:]
    /// Most recently favorited first.
    public private(set) var favorites: [String] = []

    public init() {}

    /// Records a run. A repeated command moves to the top of Recent instead of being added again.
    public mutating func record(_ raw: String, at date: Date = Date()) {
        let command = Self.normalize(raw)
        guard !command.isEmpty, !Self.ignored.contains(command) else { return }

        recent.removeAll { $0 == command }
        recent.insert(command, at: 0)
        if recent.count > Self.recentLimit {
            recent.removeLast(recent.count - Self.recentLimit)
        }

        if var existing = stats[command] {
            existing.count += 1
            existing.lastUsed = max(existing.lastUsed, date)
            stats[command] = existing
        } else {
            stats[command] = CommandStats(count: 1, firstUsed: date, lastUsed: date)
        }
        pruneStatsIfNeeded()
    }

    public func isFavorite(_ command: String) -> Bool {
        favorites.contains(command)
    }

    public mutating func toggleFavorite(_ command: String) {
        if let index = favorites.firstIndex(of: command) {
            favorites.remove(at: index)
        } else {
            favorites.insert(command, at: 0)
        }
    }

    /// Lets users save a command they haven't run yet (e.g. a long Detox invocation).
    public mutating func addFavorite(_ raw: String) {
        let command = Self.normalize(raw)
        guard !command.isEmpty, !favorites.contains(command) else { return }
        favorites.insert(command, at: 0)
    }

    public mutating func moveFavorites(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.map { favorites[$0] }
        var remaining = favorites.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let insertAt = destination - source.filter { $0 < destination }.count
        remaining.insert(contentsOf: moving, at: max(0, min(insertAt, remaining.count)))
        favorites = remaining
    }

    /// Forgets a command everywhere except Favorites.
    public mutating func forget(_ command: String) {
        recent.removeAll { $0 == command }
        stats[command] = nil
    }

    public mutating func clearRecent() {
        recent.removeAll()
    }

    public mutating func clearHistory() {
        recent.removeAll()
        stats.removeAll()
    }

    public func count(of command: String) -> Int {
        stats[command]?.count ?? 0
    }

    /// `categorize` maps a command to its categories; the app passes a cached version.
    public func commands(
        for filter: CommandFilter,
        categorize: (String) -> [CommandCategory] = CommandCategory.matching
    ) -> [String] {
        switch filter {
        case .recent:
            return recent
        case .favorites:
            return favorites
        case .mostUsed:
            return stats
                .sorted { a, b in
                    a.value.count != b.value.count ? a.value.count > b.value.count : a.value.lastUsed > b.value.lastUsed
                }
                .prefix(Self.mostUsedLimit)
                .map(\.key)
        case .category(let category):
            return knownCommands
                .filter { categorize($0).contains(category) }
                .sorted { (stats[$0]?.lastUsed ?? .distantPast) > (stats[$1]?.lastUsed ?? .distantPast) }
        }
    }

    /// Categories with at least one command, alphabetically. These are the tabs after the fixed three.
    public func categoriesInUse(categorize: (String) -> [CommandCategory] = CommandCategory.matching) -> [CommandCategory] {
        var used = Set<CommandCategory>()
        for command in knownCommands { used.formUnion(categorize(command)) }
        return used.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Everything with a usage count, plus favorites that may never have been run.
    private var knownCommands: Set<String> {
        Set(stats.keys).union(favorites)
    }

    static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Drops the least useful commands once we're over the cap. Recent and favorites are always kept.
    private mutating func pruneStatsIfNeeded() {
        guard stats.count > Self.statsLimit else { return }
        let protected = Set(recent).union(favorites)
        let overflow = stats.count - Self.statsLimit
        let victims = stats
            .filter { !protected.contains($0.key) }
            .sorted { a, b in
                a.value.count != b.value.count ? a.value.count < b.value.count : a.value.lastUsed < b.value.lastUsed
            }
            .prefix(overflow)
        for victim in victims { stats[victim.key] = nil }
    }
}
