#!/bin/bash
# Builds the download page into build/site for GitHub Pages and Vercel.
# site/index.html is written without a document skeleton (it is also published as a Claude
# artifact, which adds one), so this adds the doctype, charset, viewport and icons. The
# Content-Security-Policy is repeated here for hosts that can't send headers (GitHub Pages):
# the page loads nothing but its own inline code and Google Fonts.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=build/site
rm -rf "$OUT" && mkdir -p "$OUT"
cat - site/index.html > "$OUT/index.html" <<'HEAD'
<!doctype html>
<html lang="en">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline' https://fonts.googleapis.com; font-src https://fonts.gstatic.com; img-src 'self' data:; base-uri 'none'; form-action 'none'">
<meta name="referrer" content="strict-origin-when-cross-origin">
<link rel="icon" type="image/png" href="icon.png">
<link rel="apple-touch-icon" href="icon.png">
HEAD
cp site/icon.png "$OUT/"
echo "✓ Built $OUT"
