#!/bin/bash
# Builds build/Easie.app. Works with just the Xcode Command Line Tools.
#   scripts/build.sh            release build, ad-hoc signed
#   SIGN_ID="Developer ID Application: Your Name (TEAMID)" scripts/build.sh
#                               signed for distribution (then run scripts/notarize.sh)
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/Easie.app
# Universal by default (Apple Silicon + Intel). For a quicker local build: ARCHS=arm64 scripts/build.sh
ARCHS="${ARCHS:-arm64 x86_64}"

# Each architecture builds into the same output folder, so keep a copy of each before the next one.
SLICES=()
for arch in $ARCHS; do
  echo "→ Building for $arch"
  swift build -c release --triple "$arch-apple-macosx13.0"
  mkdir -p build/slices
  cp "$(swift build -c release --triple "$arch-apple-macosx13.0" --show-bin-path)/Easie" "build/slices/Easie-$arch"
  SLICES+=("build/slices/Easie-$arch")
done
BIN=build/slices/Easie
lipo -create "${SLICES[@]}" -output "$BIN"

if [ ! -f build/AppIcon.icns ]; then
  echo "→ Drawing app icon"
  ICONSET=build/AppIcon.iconset
  mkdir -p "$ICONSET"
  swift scripts/IconRenderer.swift build/icon-1024.png
  for size in 16 32 128 256 512; do
    sips -z $size $size build/icon-1024.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) build/icon-1024.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o build/AppIcon.icns
fi

echo "→ Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Easie"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

if [ -n "${SIGN_ID:-}" ]; then
  codesign --force --options runtime --timestamp --entitlements Resources/Easie.entitlements --sign "$SIGN_ID" "$APP"
else
  codesign --force --sign - "$APP"   # ad-hoc: fine on your own Mac
fi

echo "✓ Built $APP"
