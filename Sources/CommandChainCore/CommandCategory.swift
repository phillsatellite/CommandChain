import Foundation

/// The dropdown options.
public enum CommandFilter: String, CaseIterable, Identifiable, Codable {
    case recent, mostUsed, favorites, android, ios, detox

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .recent: return "Recent"
        case .mostUsed: return "Most Used"
        case .favorites: return "Favorites"
        case .android: return "Android"
        case .ios: return "iOS"
        case .detox: return "Detox"
        }
    }

    public var systemImage: String {
        switch self {
        case .recent: return "clock"
        case .mostUsed: return "chart.bar"
        case .favorites: return "star"
        case .android: return "smartphone"
        case .ios: return "iphone"
        case .detox: return "checkmark.seal"
        }
    }

    public var category: CommandCategory? {
        switch self {
        case .android: return .android
        case .ios: return .ios
        case .detox: return .detox
        default: return nil
        }
    }
}

/// Platform buckets, detected from the command text. A command can be in more than one
/// (e.g. `detox build -c ios.sim.debug` is both Detox and iOS).
public enum CommandCategory: CaseIterable {
    case android, ios, detox

    public var title: String {
        switch self {
        case .android: return "Android"
        case .ios: return "iOS"
        case .detox: return "Detox"
        }
    }

    public func matches(_ command: String) -> Bool {
        let lower = command.lowercased()
        let programs = Self.programNames(in: lower)
        switch self {
        case .detox:
            return lower.contains("detox")
        case .android:
            return lower.contains("android")
                || !programs.isDisjoint(with: Self.androidTools)
                || lower.range(of: #"\.apk\b|\.aab\b|\bassemble(debug|release)\b|\binstall(debug|release)\b"#, options: .regularExpression) != nil
        case .ios:
            return lower.range(of: #"(?<![a-z])ios(?![a-z])"#, options: .regularExpression) != nil
                || !programs.isDisjoint(with: Self.iosTools)
                || lower.range(of: #"\.xcworkspace|\.xcodeproj|\.ipa\b|\bpodfile\b|\bsimulator\b|\btestflight\b"#, options: .regularExpression) != nil
        }
    }

    static let androidTools: Set<String> = [
        "adb", "gradle", "gradlew", "emulator", "sdkmanager", "avdmanager", "bundletool",
        "aapt", "aapt2", "apksigner", "zipalign", "logcat", "scrcpy", "keytool",
    ]

    static let iosTools: Set<String> = [
        "xcodebuild", "xcrun", "simctl", "pod", "xcode-select", "xcodes", "ios-deploy",
        "agvtool", "xcpretty", "xcbeautify", "instruments", "idb", "applesimutils", "carthage",
    ]

    /// Basenames of every word, so `./gradlew`, `~/Library/Android/sdk/platform-tools/adb` etc. match.
    static func programNames(in command: String) -> Set<String> {
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ";&|()"))
        return Set(command.components(separatedBy: separators).compactMap { word in
            word.isEmpty ? nil : String(word.split(separator: "/").last ?? Substring(word))
        })
    }
}
