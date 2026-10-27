import Foundation

/// The dropdown options: three fixed lists, plus one per category the user has commands in.
public enum CommandFilter: Hashable, Identifiable, RawRepresentable {
    case recent, mostUsed, favorites
    case category(CommandCategory)

    /// Always shown, in this order.
    public static let fixed: [CommandFilter] = [.recent, .mostUsed, .favorites]

    public init?(rawValue: String) {
        switch rawValue {
        case "recent": self = .recent
        case "mostUsed": self = .mostUsed
        case "favorites": self = .favorites
        default:
            // Builds before dynamic categories stored "android", "ios" or "detox" directly.
            let id = rawValue.hasPrefix("category:") ? String(rawValue.dropFirst("category:".count)) : rawValue
            guard let category = CommandCategory.all.first(where: { $0.id == id }) else { return nil }
            self = .category(category)
        }
    }

    public var rawValue: String {
        switch self {
        case .recent: return "recent"
        case .mostUsed: return "mostUsed"
        case .favorites: return "favorites"
        case .category(let category): return "category:\(category.id)"
        }
    }

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .recent: return "Recent"
        case .mostUsed: return "Most Used"
        case .favorites: return "Favorites"
        case .category(let category): return category.title
        }
    }

    public var systemImage: String {
        switch self {
        case .recent: return "clock"
        case .mostUsed: return "chart.bar"
        case .favorites: return "star"
        case .category(let category): return category.systemImage
        }
    }
}

/// A platform, language or tool, detected from the command text. A command can be in several
/// (e.g. `npx detox test -c ios.sim.debug` is Detox, iOS and Node.js).
public struct CommandCategory: Hashable, Identifiable {
    public let id: String
    public let title: String
    public let systemImage: String
    /// Matches when one of these is a program the command runs (see `ParsedCommand.programs`).
    let programs: Set<String>
    /// Extra rule for categories that need more than program names.
    let rule: ((ParsedCommand) -> Bool)?

    init(_ id: String, _ title: String, _ systemImage: String, programs: Set<String> = [], rule: ((ParsedCommand) -> Bool)? = nil) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.programs = programs
        self.rule = rule
    }

    public static func == (a: CommandCategory, b: CommandCategory) -> Bool { a.id == b.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }

    public func matches(_ command: String) -> Bool {
        matches(ParsedCommand(command))
    }

    func matches(_ parsed: ParsedCommand) -> Bool {
        !programs.isDisjoint(with: parsed.programs) || rule?(parsed) == true
    }

    /// Every category the command belongs to, in `all` order.
    public static func matching(_ command: String) -> [CommandCategory] {
        let parsed = ParsedCommand(command)
        return all.filter { $0.matches(parsed) }
    }

    // MARK: Categories

    public static let ios = CommandCategory("ios", "iOS", "iphone") { parsed in
        parsed.text.range(of: #"(?<![a-z])ios(?![a-z])"#, options: .regularExpression) != nil
            || !parsed.words.isDisjoint(with: iosTools)
            || parsed.text.range(of: #"\.xcworkspace|\.xcodeproj|\.ipa\b|\bpodfile\b|\bsimulator\b|\btestflight\b"#, options: .regularExpression) != nil
    }

    public static let android = CommandCategory("android", "Android", "smartphone") { parsed in
        parsed.text.contains("android")
            || !parsed.words.isDisjoint(with: androidTools)
            || parsed.text.range(of: #"\.apk\b|\.aab\b|\bassemble(debug|release)\b|\binstall(debug|release)\b"#, options: .regularExpression) != nil
    }

    public static let detox = CommandCategory("detox", "Detox", "checkmark.seal") { parsed in
        parsed.text.contains("detox")
    }

    public static let all: [CommandCategory] = [
        ios, android, detox,
        CommandCategory("react-native", "React Native", "atom", programs: ["react-native", "watchman"]),
        CommandCategory("expo", "Expo", "e.square", programs: ["expo", "eas"]),
        CommandCategory("flutter", "Flutter", "bird", programs: ["flutter", "dart", "fvm"]),
        CommandCategory("fastlane", "Fastlane", "bolt", programs: ["fastlane", "match", "gym", "pilot", "supply"]),
        CommandCategory("swift", "Swift", "swift", programs: ["swift", "swiftc", "swiftlint", "swiftformat", "tuist", "xcodegen"]),
        CommandCategory("node", "Node.js", "hexagon", programs: ["node", "npm", "npx", "nvm", "fnm", "corepack", "nodemon", "tsc", "ts-node", "tsx"]),
        CommandCategory("yarn", "Yarn", "y.square", programs: ["yarn"]),
        CommandCategory("pnpm", "pnpm", "p.square", programs: ["pnpm", "pnpx"]),
        CommandCategory("bun", "Bun", "b.square", programs: ["bun", "bunx"]),
        CommandCategory("deno", "Deno", "d.square", programs: ["deno"]),
        CommandCategory("python", "Python", "chevron.left.forwardslash.chevron.right", programs: [
            "python", "python3", "pip", "pip3", "pipx", "poetry", "uv", "uvx", "pipenv", "pyenv",
            "conda", "pytest", "jupyter", "django-admin", "flask", "black", "ruff", "mypy",
        ]),
        CommandCategory("ruby", "Ruby", "diamond", programs: ["ruby", "gem", "bundle", "bundler", "rails", "rake", "rbenv", "rvm", "irb"]),
        CommandCategory("java", "Java & Kotlin", "cup.and.saucer", programs: ["java", "javac", "mvn", "jenv", "kotlin", "kotlinc", "sdk"]),
        CommandCategory("go", "Go", "hare", programs: ["go", "gofmt", "golangci-lint"]),
        CommandCategory("rust", "Rust", "gearshape.2", programs: ["cargo", "rustc", "rustup"]),
        CommandCategory("php", "PHP", "p.circle", programs: ["php", "composer", "artisan"]),
        CommandCategory("dotnet", ".NET", "number", programs: ["dotnet", "nuget"]),
        CommandCategory("git", "Git", "arrow.triangle.branch", programs: ["git", "gh", "tig", "lazygit", "git-lfs"]),
        CommandCategory("docker", "Docker", "shippingbox", programs: ["docker", "docker-compose", "podman", "colima"]),
        CommandCategory("kubernetes", "Kubernetes", "steeringwheel", programs: ["kubectl", "helm", "k9s", "minikube", "kind", "kubectx", "kubens"]),
        CommandCategory("cloud", "Cloud", "cloud", programs: ["aws", "gcloud", "gsutil", "az", "vercel", "netlify", "heroku", "flyctl", "fly", "wrangler"]),
        CommandCategory("firebase", "Firebase", "flame", programs: ["firebase"]),
        CommandCategory("terraform", "Terraform", "square.stack.3d.up", programs: ["terraform", "tofu", "pulumi"]),
        CommandCategory("database", "Databases", "cylinder", programs: ["psql", "pg_dump", "mysql", "sqlite3", "redis-cli", "mongosh", "mongo", "supabase", "prisma"]),
        CommandCategory("homebrew", "Homebrew", "mug", programs: ["brew"]),
        CommandCategory("remote", "SSH & Remote", "network", programs: ["ssh", "scp", "sftp", "rsync", "mosh", "ssh-keygen", "ssh-add"]),
        CommandCategory("build", "Make & CMake", "hammer", programs: ["make", "cmake", "ninja", "bazel"]),
    ]

    static let androidTools: Set<String> = [
        "adb", "gradle", "gradlew", "emulator", "sdkmanager", "avdmanager", "bundletool",
        "aapt", "aapt2", "apksigner", "zipalign", "logcat", "scrcpy", "keytool",
    ]

    static let iosTools: Set<String> = [
        "xcodebuild", "xcrun", "simctl", "pod", "xcode-select", "xcodes", "ios-deploy",
        "agvtool", "xcpretty", "xcbeautify", "instruments", "idb", "applesimutils", "carthage",
    ]
}

/// A command broken down for category matching.
struct ParsedCommand {
    /// Lowercased full text.
    let text: String
    /// Basename of every word, so `./gradlew` and `~/Library/Android/sdk/platform-tools/adb` match.
    let words: Set<String>
    /// The programs the command actually runs: the first word of each `;`/`&&`/`|` segment
    /// (after `sudo`, `env`, `FOO=bar` and similar), plus what a runner like `npx` or `yarn` launches.
    /// Quoted text is ignored, so `git commit -m "fix docker"` only runs `git`.
    let programs: Set<String>

    init(_ command: String) {
        text = command.lowercased()
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ";&|()"))
        words = Set(text.components(separatedBy: separators).filter { !$0.isEmpty }.map(Self.basename))
        programs = Self.programs(in: Self.removingQuotedText(text))
    }

    /// Prefixes that run the next word as the real program.
    private static let wrappers: Set<String> = ["sudo", "env", "time", "nohup", "exec", "command", "caffeinate", "arch", "nice"]
    /// Tools whose next word is (usually) another program or package to run.
    private static let runners: Set<String> = ["npx", "bunx", "pnpx", "uvx", "yarn", "pnpm", "bun", "npm", "bundle", "poetry", "uv", "pipx"]
    /// Subcommands of runners that come before the program name, e.g. `bundle exec pod install`.
    private static let runnerVerbs: Set<String> = ["exec", "dlx", "run", "x"]

    static func programs(in text: String) -> Set<String> {
        var result = Set<String>()
        for segment in text.components(separatedBy: CharacterSet(charactersIn: ";|&\n()")) {
            var words = segment.split(whereSeparator: \.isWhitespace).map(String.init)
            while let first = words.first {
                if first.contains("="), !first.hasPrefix("-") {
                    words.removeFirst() // FOO=bar
                } else if wrappers.contains(basename(first)) {
                    words.removeFirst()
                    while words.first?.hasPrefix("-") == true { words.removeFirst() } // e.g. `arch -x86_64`
                } else {
                    break
                }
            }
            guard let first = words.first else { continue }
            let program = basename(first)
            result.insert(program)
            guard runners.contains(program) else { continue }
            var rest = words.dropFirst().filter { !$0.hasPrefix("-") }[...]
            if let verb = rest.first, runnerVerbs.contains(verb) { rest = rest.dropFirst() }
            if let launched = rest.first { result.insert(basename(launched)) }
        }
        return result
    }

    static func removingQuotedText(_ text: String) -> String {
        var result = ""
        var quote: Character?
        for ch in text {
            if let open = quote {
                if ch == open { quote = nil }
            } else if ch == "\"" || ch == "'" {
                quote = ch
            } else {
                result.append(ch)
            }
        }
        return result
    }

    static func basename(_ word: String) -> String {
        String(word.split(separator: "/").last ?? Substring(word))
    }
}
