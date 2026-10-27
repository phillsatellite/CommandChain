# Command Chain

A macOS menu bar app that remembers the commands you run in Terminal, so you can find and copy them again in one click.

- **Recent**: your last 30 commands, newest first. Running a command again moves it to the top instead of adding a duplicate.
- **Most Used**: your top 50 commands by run count.
- **Favorites**: star any command, or add one with **+**. Drag to reorder.
- **Automatic tabs**: besides Recent, Most Used and Favorites, a tab appears for each platform or tool you actually use: iOS, Android, Detox, React Native, Expo, Git, Docker, Node.js, Python, Homebrew and about 25 more. Commands are sorted by the program they run, so `git commit -m "fix docker"` is Git, not Docker.
- Search, a copy button on every row (or click the row), and a right-click menu.
- **Run with ▶**: the play button types the command into your terminal and runs it.
- **New terminal**: the button at the top right opens a new window in your terminal, or a new tab if you prefer.
- **Pick a window**: the bar under the search field shows which terminal window ▶ sends to. Click it to send commands to any other open window or tab.
- **Paste into Terminal** (optional): click a command and it's typed into the app you were just using, ready to run.
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

## Run and paste into Terminal

The **▶** button on each command switches to your most recent terminal window (Terminal, iTerm, Warp, Ghostty, kitty, Alacritty, WezTerm, Hyper or Tabby), pastes the command and presses Return. It always goes to a terminal, never to a browser or editor, and tells you if no terminal is open.


Turn on ⚙︎ → **Paste into Terminal on Click**. Clicking a command then closes the panel, switches back to the app you were using before you opened Command Chain (Terminal, iTerm, VS Code, …) and pastes the command at the prompt. It doesn't press Return, so you can still edit it before running. The copy button always just copies.

The button at the top right of the panel opens a new window in the terminal you used last (or starts it if it isn't running). To get a new tab instead, choose ⚙︎ → **Terminal Button Opens → New Tab**, or right-click the button for either one.

The bar under the search field shows where commands go, such as **Sending to phill — -zsh — 120×30**. By default that's the terminal window you used last. Click the bar for a list of every open terminal window, with each tab listed under its window. Pick one and ▶ and click-to-paste go there, even if it's behind other windows; it shows **Pinned to** while one is picked. Choose **Window You Were Last In** to go back. If the window you picked closes, Command Chain doesn't send the command anywhere else. It leaves it on your clipboard and tells you. Tabs are listed for terminals that use standard macOS tabs, like Terminal. Only windows in the current desktop Space are listed.

All of these work by pressing keys (⌘V, Return, ⌘N or ⌘T) for you and reading the window list, which macOS only allows for apps with Accessibility access. The first time you turn it on, macOS asks you to allow Command Chain in **System Settings → Privacy & Security → Accessibility**. Until you do, clicking a command only copies it.

> **Already switched on but it still asks?** Command Chain isn't signed with an Apple Developer ID, so macOS ties the permission to one exact build. After installing a new version, the old entry no longer applies, and switching it off and on doesn't update it. Remove it instead: in **Privacy & Security → Accessibility**, select Command Chain and click **−** (or run `tccutil reset Accessibility com.phillsatellite.CommandChain`). Then turn the setting on again in Command Chain and allow it.
