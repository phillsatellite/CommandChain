# Command Chain

A macOS menu bar app that remembers the commands you run in Terminal, so you can find and copy them again in one click.

- **Recent**: your last 30 commands, newest first. Running a command again moves it to the top instead of adding a duplicate.
- **Most Used**: your top 50 commands by run count.
- **Favorites**: star any command, or add one with **+**. Drag to reorder.
- **Android / iOS / Detox**: commands detected automatically (`adb`, `./gradlew`, `run-android`… / `xcodebuild`, `xcrun simctl`, `pod`, `run-ios`… / anything with `detox`).
- Search, a copy button on every row (or click the row), and a right-click menu.
- Native SwiftUI, follows light/dark mode and the system accent color. Lives in the menu bar only, with no Dock icon.

Requires macOS 13 Ventura or later. Universal build (Apple silicon + Intel).

## Install

1. Download `CommandChain-x.y.z.dmg` from the [Releases](https://github.com/phillsatellite/CommandChain/releases) page.
2. Open it and drag **Command Chain** into **Applications**.
3. Launch it. A terminal icon appears in the menu bar.
4. Click it, then click **Enable** to turn on terminal capture. Open a new Terminal window and your commands will start showing up.

> **"Command Chain can't be opened because Apple cannot check it for malicious software"**
> Release builds are unsigned unless the project has an Apple Developer ID set up (see below).
> To open it the first time: try to open the app, then go to **System Settings → Privacy & Security**, scroll down, and click **Open Anyway**.
> Or run `xattr -dr com.apple.quarantine "/Applications/Command Chain.app"`.

## How capture works

**Enable** adds this block to `~/.zshrc` (and `~/.bash_profile` / `~/.bashrc` if you have them):

```sh
# >>> Command Chain >>>
[ -f "$HOME/Library/Application Support/CommandChain/hook.sh" ] && . "$HOME/Library/Application Support/CommandChain/hook.sh"
# <<< Command Chain <<<
```

The hook appends each command to `~/Library/Application Support/CommandChain/inbox.log`, and the app picks those up every second. The shell never waits on the app, and commands run while the app is closed are imported the next time it launches. If you delete the app, the `[ -f … ]` guard means your shell keeps working.

- **Privacy:** start a command with a space to keep it out of Command Chain. You can also pause capture from the ⚙︎ menu, or right-click a command → *Remove from History*.
- History is stored locally in `~/Library/Application Support/CommandChain/store.json`. Nothing leaves your Mac.
- ⚙︎ → **Import Existing Shell History** seeds Most Used and the platform lists from `~/.zsh_history` / `~/.bash_history`.
- ⚙︎ → **Remove Shell Integration…** removes the block again.
