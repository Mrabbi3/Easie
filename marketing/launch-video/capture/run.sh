#!/bin/bash
# Builds capture/Shots.swift against a scratch copy of Easie's sources and renders the app's real
# views to shots/app/. The copy makes the popup's centre disc visible to the tool; the app is untouched.
set -euo pipefail
cd "$(dirname "$0")"
ROOT=../../..; PKG=.pkg; DEMO=.demo
rm -rf "$PKG" "$DEMO" && mkdir -p "$PKG/Sources/EasieShots" "$DEMO"
cp -R "$ROOT/Sources/EasieCore" "$PKG/Sources/"
for f in ConversionSession FormatStyle RadialMenu SetupView SystemIntegration; do cp "$ROOT/Sources/Easie/$f.swift" "$PKG/Sources/EasieShots/"; done
sed -i '' 's/private var center: some View/var center: some View/' "$PKG/Sources/EasieShots/RadialMenu.swift"
cp Shots.swift "$PKG/Sources/EasieShots/main.swift"
printf 'import OSLog\nlet log = Logger(subsystem: "app.easie.Easie", category: "shots")\n' > "$PKG/Sources/EasieShots/Log.swift"
cat > "$PKG/Package.swift" <<'SWIFT'
// swift-tools-version:5.10
import PackageDescription
let package = Package(name: "EasieShots", platforms: [.macOS(.v13)], targets: [
    .target(name: "EasieCore", path: "Sources/EasieCore"),
    .executableTarget(name: "EasieShots", dependencies: ["EasieCore"], path: "Sources/EasieShots"),
])
SWIFT
# demo files, written by Easie's own engine (fictional content)
cat > "$DEMO/Q3 Report.md" <<'MD'
# Q3 Report

**Northwind Studio** · July – September

## Highlights

- Revenue grew **18%** to $2.4M
- 1,280 new customers, 96% kept
- Shipped the redesigned mobile app

## Next quarter

1. Open the Lisbon office
2. Launch annual plans
3. Hire four engineers
MD
cat > "$DEMO/invoice.html" <<'HTML'
<h1>Invoice 0412</h1><p>Northwind Studio · Due 30 November</p>
<table border=1><tr><th>Item</th><th>Qty</th><th>Amount</th></tr><tr><td>Design sprint</td><td>1</td><td>$4,800</td></tr>
<tr><td>Prototype</td><td>2</td><td>$2,400</td></tr><tr><th colspan=2>Total</th><th>$7,200</th></tr></table>
HTML
EASIE="$ROOT/build/Easie.app/Contents/MacOS/Easie"
"$EASIE" convert "$DEMO/Q3 Report.md" --to docx >/dev/null && rm "$DEMO/Q3 Report.md"
"$EASIE" convert "$DEMO/invoice.html" --to pdf >/dev/null && mv "$DEMO/invoice.pdf" "$DEMO/Invoice 0412.pdf" && rm "$DEMO/invoice.html"
swift build -c release --package-path "$PKG" 2>&1 | grep -E "error|warning: unre|Compiling|Build" | tail -5
"$PKG/.build/release/EasieShots" "$PWD/../shots/app" "$PWD/$DEMO" "$ROOT/build/AppIcon.icns"
