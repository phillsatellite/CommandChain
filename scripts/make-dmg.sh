#!/usr/bin/env bash
# Packages "build/Command Chain.app" into build/CommandChain-<version>.dmg (drag-to-Applications).
#
# Notarization (optional): set NOTARY_PROFILE to a keychain profile created with
#   xcrun notarytool store-credentials <profile> --apple-id … --team-id … --password <app-specific-password>
# The app must have been built with a Developer ID SIGN_IDENTITY.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-$(tr -d '[:space:]' < VERSION)}"
APP="build/Command Chain.app"
DMG="build/CommandChain-$VERSION.dmg"
[[ -d "$APP" ]] || { echo "Run scripts/build-app.sh first" >&2; exit 1; }

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG"
hdiutil create -volname "Command Chain" -srcfolder "$STAGING" -ov -format UDZO -fs HFS+ "$DMG" >/dev/null

if [[ -n "${SIGN_IDENTITY:-}" && "$SIGN_IDENTITY" != "-" ]]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
fi

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  echo "▸ Notarizing"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
fi

echo "✓ $DMG"
