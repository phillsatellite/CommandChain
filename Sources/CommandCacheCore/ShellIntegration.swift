import Foundation

/// Installs a tiny zsh/bash hook that appends every command you run to `inbox.log`.
/// The app drains that file, so the shell never waits on the app (and works when it isn't running).
public struct ShellIntegration {
    public static let beginMarker = "# >>> CommandCache >>>"
    public static let endMarker = "# <<< CommandCache <<<"

    public let paths: AppPaths
    public let homeDirectory: URL

    public init(paths: AppPaths, homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.paths = paths
        self.homeDirectory = homeDirectory
    }

    /// Shell startup files we hook into. zsh is the macOS default, so ~/.zshrc is always used;
    /// bash files are only touched if they already exist.
    public var startupFiles: [URL] {
        let zshrc = homeDirectory.appendingPathComponent(".zshrc")
        let bash = [".bash_profile", ".bashrc"]
            .map { homeDirectory.appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        return [zshrc] + bash
    }

    public var isInstalled: Bool {
        let zshrc = homeDirectory.appendingPathComponent(".zshrc")
        guard let contents = try? String(contentsOf: zshrc, encoding: .utf8) else { return false }
        return contents.contains(Self.beginMarker)
    }

    /// Writes the hook script. Called on every launch so app updates also update the hook.
    public func writeHookScript() throws {
        try paths.ensureDirectory()
        try Self.hookScript.write(to: paths.hookScript, atomically: true, encoding: .utf8)
    }

    public func install() throws {
        try writeHookScript()
        for file in startupFiles {
            var contents = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            guard !contents.contains(Self.beginMarker) else { continue }
            if !contents.isEmpty && !contents.hasSuffix("\n") { contents += "\n" }
            contents += "\n" + sourceBlock + "\n"
            // Non-atomic write so a symlinked dotfile (e.g. from a dotfiles repo) stays a symlink.
            try Data(contents.utf8).write(to: file)
        }
    }

    public func uninstall() throws {
        for file in startupFiles {
            guard let contents = try? String(contentsOf: file, encoding: .utf8),
                  contents.contains(Self.beginMarker) else { continue }
            try Data(Self.removingBlock(from: contents).utf8).write(to: file)
        }
    }

    var sourceBlock: String {
        let path = paths.hookScript.path
        let home = homeDirectory.path
        let shellPath = path.hasPrefix(home + "/") ? "$HOME" + path.dropFirst(home.count) : path
        return """
        \(Self.beginMarker)
        [ -f "\(shellPath)" ] && . "\(shellPath)"
        \(Self.endMarker)
        """
    }

    static func removingBlock(from contents: String) -> String {
        var lines: [Substring] = []
        var skipping = false
        for line in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            if line == beginMarker { skipping = true; continue }
            if skipping { if line == endMarker { skipping = false }; continue }
            lines.append(line)
        }
        // Drop the blank line install() added before the block.
        var result = lines.joined(separator: "\n")
        while result.hasSuffix("\n\n") { result.removeLast() }
        return result
    }

    /// Lines are escaped so one command == one line: `\` -> `\\`, tab -> `\t`, newline -> `\n`.
    public static let hookScript = #"""
    # CommandCache shell integration. Managed by CommandCache.app — edits are overwritten on launch.
    # Start a command with a space to keep it out of CommandCache.

    _commandcache_dir="${COMMANDCACHE_HOME:-$HOME/Library/Application Support/CommandCache}"

    _commandcache_write() {
      [ -d "$_commandcache_dir" ] || return 0
      [ -e "$_commandcache_dir/paused" ] && return 0
      local cmd="$1"
      case "$cmd" in ' '*) return 0 ;; esac
      [ -z "${cmd//[[:space:]]/}" ] && return 0
      cmd="${cmd//\\/\\\\}"
      cmd="${cmd//$'\t'/\\t}"
      cmd="${cmd//$'\n'/\\n}"
      printf '%s\n' "$cmd" >> "$_commandcache_dir/inbox.log" 2>/dev/null
      return 0
    }

    if [ -n "$ZSH_VERSION" ]; then
      autoload -Uz add-zsh-hook
      _commandcache_preexec() { _commandcache_write "$1"; }
      add-zsh-hook preexec _commandcache_preexec
    elif [ -n "$BASH_VERSION" ]; then
      # bash has no preexec, so read the newest history entry each time the prompt is drawn.
      # The first prompt only records a baseline, so old history isn't re-logged on shell start.
      _commandcache_last=""
      _commandcache_ready=""
      _commandcache_prompt() {
        local entry num
        entry="$(HISTTIMEFORMAT= builtin history 1)"
        entry="${entry#"${entry%%[! ]*}"}"
        num="${entry%%[!0-9]*}"
        if [ -z "$_commandcache_ready" ]; then
          _commandcache_ready=1; _commandcache_last="$num"; return 0
        fi
        [ -z "$num" ] || [ "$num" = "$_commandcache_last" ] && return 0
        _commandcache_last="$num"
        entry="${entry#"$num"}"; entry="${entry#\*}"
        entry="${entry#"${entry%%[! ]*}"}"
        _commandcache_write "$entry"
      }
      case "$PROMPT_COMMAND" in
        *_commandcache_prompt*) ;;
        *) PROMPT_COMMAND="_commandcache_prompt${PROMPT_COMMAND:+; $PROMPT_COMMAND}" ;;
      esac
    fi
    """#
}
