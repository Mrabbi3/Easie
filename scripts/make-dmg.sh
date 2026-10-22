#!/bin/bash
# Packages build/Easie.app into build/Easie.dmg (drag-to-Applications installer) for your website.
set -euo pipefail
cd "$(dirname "$0")/.."

[ -d build/Easie.app ] || scripts/build.sh

STAGE=build/dmg
rm -rf "$STAGE" build/Easie.dmg
mkdir -p "$STAGE"
cp -R build/Easie.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Easie" -srcfolder "$STAGE" -ov -format UDZO build/Easie.dmg >/dev/null
rm -rf "$STAGE"

if [ -n "${SIGN_ID:-}" ]; then
  codesign --force --sign "$SIGN_ID" build/Easie.dmg
fi
echo "✓ build/Easie.dmg"
