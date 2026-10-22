#!/bin/bash
# Builds Easie, copies it to Applications and registers the Finder right-click service.
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/build.sh

DEST=/Applications
[ -w "$DEST" ] || DEST="$HOME/Applications"
mkdir -p "$DEST"

pkill -x Easie 2>/dev/null || true
rm -rf "$DEST/Easie.app"
cp -R build/Easie.app "$DEST/"

/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST/Easie.app"
/System/Library/CoreServices/pbs -update

echo "✓ Installed to $DEST/Easie.app"
echo "  Right-click any file in Finder → Edit with Easie (under Quick Actions or Services)"
