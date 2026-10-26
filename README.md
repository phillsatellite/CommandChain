# CommandCache

A macOS menu bar app that remembers the commands you run in Terminal, so you can find and copy them again in one click.

- **Recent**: your last 30 commands, newest first. Running a command again moves it to the top instead of adding a duplicate.
- **Most Used**: your top 50 commands by run count.
- **Favorites**: star any command, or add one with **+**. Drag to reorder.
- **Android / iOS / Detox**: commands detected automatically (`adb`, `./gradlew`, `run-android`… / `xcodebuild`, `xcrun simctl`, `pod`, `run-ios`… / anything with `detox`).
- Search, a copy button on every row (or click the row), and a right-click menu.
- Native SwiftUI, follows light/dark mode and the system accent color. Lives in the menu bar only, with no Dock icon.

Requires macOS 13 Ventura or later. Universal build (Apple silicon + Intel).

## Install

1. Download `CommandCache-x.y.z.dmg` from the [Releases](../../releases) page.
2. Open it and drag **CommandCache** into **Applications**.
3. Launch it. A terminal icon appears in the menu bar.
4. Click it, then click **Enable** to turn on terminal capture. Open a new Terminal window and your commands will start showing up.

> **"CommandCache can't be opened because Apple cannot check it for malicious software"**
> Release builds are unsigned unless the project has an Apple Developer ID set up (see below).
> To open it the first time: try to open the app, then go to **System Settings → Privacy & Security**, scroll down, and click **Open Anyway**.
> Or run `xattr -dr com.apple.quarantine /Applications/CommandCache.app`.

## How capture works

**Enable** adds this block to `~/.zshrc` (and `~/.bash_profile` / `~/.bashrc` if you have them):

```sh
# >>> CommandCache >>>
[ -f "$HOME/Library/Application Support/CommandCache/hook.sh" ] && . "$HOME/Library/Application Support/CommandCache/hook.sh"
# <<< CommandCache <<<
```

The hook appends each command to `~/Library/Application Support/CommandCache/inbox.log`, and the app picks those up every second. The shell never waits on the app, and commands run while the app is closed are imported the next time it launches. If you delete the app, the `[ -f … ]` guard means your shell keeps working.

- **Privacy:** start a command with a space to keep it out of CommandCache. You can also pause capture from the ⚙︎ menu, or right-click a command → *Remove from History*.
- History is stored locally in `~/Library/Application Support/CommandCache/store.json`. Nothing leaves your Mac.
- ⚙︎ → **Import Existing Shell History** seeds Most Used and the platform lists from `~/.zsh_history` / `~/.bash_history`.
- ⚙︎ → **Remove Shell Integration…** removes the block again.

## Develop

Requires Xcode 15+ or the Swift 5.9+ Command Line Tools.

```sh
swift run CommandCache          # run from source (menu bar icon appears)
scripts/test.sh                 # unit tests
scripts/build-app.sh            # → build/CommandCache.app (universal, ad-hoc signed)
scripts/make-dmg.sh             # → build/CommandCache-<version>.dmg
```

Set `COMMANDCACHE_HOME=/some/dir` to point the app and hook at a throwaway data folder while developing.

Layout:

| Path | What |
| --- | --- |
| `Sources/CommandCacheCore` | History rules (Recent limit, dedupe, Most Used, favorites), category detection, shell hook, history import. No UI, fully unit tested. |
| `Sources/CommandCache` | The SwiftUI menu bar app. |
| `scripts/` | Build, icon, DMG and test scripts. |
| `.github/workflows/release.yml` | Tests on every push; builds and publishes the DMG for `v*` tags. |

## Releasing

1. Bump `VERSION`, commit.
2. `git tag v1.0.0 && git push origin v1.0.0`
3. GitHub Actions builds the DMG and attaches it to a new Release.

### Signing & notarization (optional, recommended for public distribution)

With an [Apple Developer Program](https://developer.apple.com/programs/) membership, add these repository secrets and the workflow will sign with your Developer ID and notarize the DMG, so users get no Gatekeeper warning:

| Secret | Value |
| --- | --- |
| `MACOS_CERT_P12` | Your *Developer ID Application* certificate exported as .p12, base64-encoded |
| `MACOS_CERT_PASSWORD` | The .p12 password |
| `MACOS_SIGN_IDENTITY` | e.g. `Developer ID Application: Jane Doe (ABCDE12345)` |
| `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD` | For `notarytool` (use an app-specific password) |

Locally: `SIGN_IDENTITY="Developer ID Application: …" scripts/build-app.sh && SIGN_IDENTITY=… NOTARY_PROFILE=<profile> scripts/make-dmg.sh`.
