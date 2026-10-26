#!/usr/bin/env bash
# Builds "build/Command Chain.app" as a universal (Apple silicon + Intel) binary.
#
# Signing: by default the app is ad-hoc signed, which runs fine on the machine that built it
# and on others after the user approves it once (see README). To ship a Developer ID–signed
# build, set SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)".
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-$(tr -d '[:space:]' < VERSION)}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
APP="build/Command Chain.app"

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "▸ Compiling (arm64 + x86_64)"
for arch in arm64 x86_64; do
  swift build -c release --product CommandChain --triple "$arch-apple-macosx13.0"
done
lipo -create \
  .build/arm64-apple-macosx/release/CommandChain \
  .build/x86_64-apple-macosx/release/CommandChain \
  -output "$APP/Contents/MacOS/CommandChain"

echo "▸ Assembling bundle"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" Resources/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "▸ Rendering icon"
ICONSET="build/AppIcon.iconset"
mkdir -p "$ICONSET"
swift scripts/make-icon.swift build/icon-1024.png
for size in 16 32 128 256 512; do
  sips -z $size $size build/icon-1024.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z $double $double build/icon-1024.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "▸ Signing ($([[ $SIGN_IDENTITY == - ]] && echo ad-hoc || echo "$SIGN_IDENTITY"))"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign --force --sign - "$APP"
else
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
fi
codesign --verify --strict "$APP"

echo "✓ $APP ($VERSION, build $BUILD_NUMBER)"
