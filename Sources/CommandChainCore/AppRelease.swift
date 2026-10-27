import Foundation

/// A dotted version like 1.2.0, compared number by number, so 1.10 is newer than 1.9
/// and 1.1 is the same as 1.1.0.
public struct AppVersion: Comparable, CustomStringConvertible {
    public let parts: [Int]

    /// Accepts "1.2.0" and tag names like "v1.2.0". Ignores pre-release suffixes like "-beta.1".
    public init?(_ string: String) {
        var text = Substring(string.trimmingCharacters(in: .whitespaces))
        if text.first == "v" || text.first == "V" { text = text.dropFirst() }
        let core = text.prefix { $0 != "-" && $0 != "+" }
        let parts = core.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, !parts.contains(nil) else { return nil }
        self.parts = parts.compactMap { $0 }
    }

    public var description: String {
        parts.map(String.init).joined(separator: ".")
    }

    public static func < (a: AppVersion, b: AppVersion) -> Bool {
        compare(a, b) < 0
    }

    public static func == (a: AppVersion, b: AppVersion) -> Bool {
        compare(a, b) == 0
    }

    /// Missing trailing parts count as 0.
    private static func compare(_ a: AppVersion, _ b: AppVersion) -> Int {
        for index in 0..<max(a.parts.count, b.parts.count) {
            let x = index < a.parts.count ? a.parts[index] : 0
            let y = index < b.parts.count ? b.parts[index] : 0
            if x != y { return x < y ? -1 : 1 }
        }
        return 0
    }
}

/// The newest published release, as returned by GitHub's `releases/latest` API.
public struct AppRelease: Decodable, Equatable {
    public let version: AppVersion
    /// The release page, which has the DMG to download.
    public let pageURL: URL

    /// Where the app looks for new versions.
    public static let latestURL = URL(string: "https://api.github.com/repos/phillsatellite/CommandChain/releases/latest")!

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case pageURL = "html_url"
    }

    public init(version: AppVersion, pageURL: URL) {
        self.version = version
        self.pageURL = pageURL
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let tag = try container.decode(String.self, forKey: .tagName)
        guard let version = AppVersion(tag) else {
            throw DecodingError.dataCorruptedError(forKey: .tagName, in: container, debugDescription: "Not a version: \(tag)")
        }
        self.version = version
        pageURL = try container.decode(URL.self, forKey: .pageURL)
    }

    public func isNewer(than current: AppVersion) -> Bool {
        version > current
    }
}
