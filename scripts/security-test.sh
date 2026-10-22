#!/bin/bash
# Feeds Easie hostile files and checks it stays safe:
#  - web pages can't make network requests or pull in other files on the Mac
#  - zip bombs, absurdly nested JSON and malformed spreadsheets are refused or handled, not crashed on
set -uo pipefail
cd "$(dirname "$0")/.."

[ -d build/Easie.app ] || scripts/build.sh
EASIE="$PWD/build/Easie.app/Contents/MacOS/Easie"
DIR=build/security
rm -rf "$DIR" && mkdir -p "$DIR"
cd "$DIR"
fail=0
pass() { echo "✓ $1"; }
bad() { echo "✗ $1"; fail=1; }

# 1. A web page full of things that would phone home. A local server records every request.
PORT=8765
python3 -m http.server $PORT --bind 127.0.0.1 > server.log 2>&1 &
SERVER=$!
sleep 0.8
cat > evil.html <<EOF
<html><head><link rel="stylesheet" href="http://127.0.0.1:$PORT/style.css">
<style>@import url("http://127.0.0.1:$PORT/import.css"); body{background:url(http://127.0.0.1:$PORT/bg.png)}</style>
<script>fetch("http://127.0.0.1:$PORT/script")</script></head>
<body onload="alert(1)"><h1>Quarterly report</h1><p>Revenue grew <b>12%</b>.</p>
<img src="http://127.0.0.1:$PORT/pixel.png"><img src="//127.0.0.1:$PORT/pixel2.png">
<img src="file://$HOME/Pictures/secret.png"><img src="../../../../etc/hosts">
<iframe src="http://127.0.0.1:$PORT/frame"></iframe></body></html>
EOF
for target in pdf docx md txt; do "$EASIE" convert evil.html --to $target >/dev/null 2>&1 || bad "evil.html → $target failed"; done
sleep 0.5
kill $SERVER 2>/dev/null
wait $SERVER 2>/dev/null
if grep -q "GET" server.log; then bad "web page made network requests:"; grep GET server.log; else pass "web page made no network requests"; fi
grep -q "Quarterly report" evil.txt && pass "web page text still converted" || bad "web page text missing"

# 2. A zip bomb dressed up as a PowerPoint (600 MB of spaces in a ~600 KB file).
python3 - <<'EOF'
import zipfile
with zipfile.ZipFile('bomb.pptx', 'w', zipfile.ZIP_DEFLATED) as z:
    z.writestr('ppt/presentation.xml', b'<?xml version="1.0"?><p:presentation xmlns:p="x" xmlns:r="y"><p:sldIdLst><p:sldId id="256" r:id="rId1"/></p:sldIdLst></p:presentation>')
    z.writestr('ppt/_rels/presentation.xml.rels', b'<?xml version="1.0"?><Relationships><Relationship Id="rId1" Type="slide" Target="slides/slide1.xml"/></Relationships>')
    z.writestr('ppt/slides/slide1.xml', b'<' + b' ' * (600 * 1024 * 1024 - 2) + b'>')
open('deep.json', 'w').write('[' * 100000 + ']' * 100000)
sheet = '<?xml version="1.0"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData><row r="1"><c r="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA1" t="inlineStr"><is><t>boom</t></is></c><c r="A1" t="inlineStr"><is><t>ok</t></is></c></row></sheetData></worksheet>'
with zipfile.ZipFile('weird.xlsx', 'w') as z:
    z.writestr('xl/workbook.xml', '<?xml version="1.0"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="S" sheetId="1" r:id="rId1"/></sheets></workbook>')
    z.writestr('xl/_rels/workbook.xml.rels', '<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="worksheet" Target="worksheets/sheet1.xml"/></Relationships>')
    z.writestr('xl/worksheets/sheet1.xml', sheet)
EOF
memory=$(/usr/bin/time -l "$EASIE" convert bomb.pptx --to txt 2>&1 >/dev/null | awk '/maximum resident/ {print int($1/1048576)}')
[ "${memory:-9999}" -lt 200 ] && pass "zip bomb refused (peak memory ${memory} MB)" || bad "zip bomb used ${memory} MB"

# 3. JSON nested 100,000 levels deep must be refused, not crash.
"$EASIE" convert deep.json --to csv >/dev/null 2>&1
[ $? -eq 1 ] && pass "deeply nested JSON refused cleanly" || bad "deeply nested JSON crashed Easie"

# 4. A spreadsheet with a garbage cell reference still converts its real data.
"$EASIE" convert weird.xlsx --to csv >/dev/null 2>&1 && grep -q "ok" weird.csv && pass "malformed spreadsheet handled" || bad "malformed spreadsheet"

# 5. Nothing is ever overwritten.
echo "keep me" > notes.txt
cp notes.txt original.txt
printf '# Notes\n' > notes.md
"$EASIE" convert notes.md --to txt >/dev/null 2>&1
cmp -s notes.txt original.txt && [ -f "notes (1).txt" ] && pass "existing files are never overwritten" || bad "an existing file was overwritten"

echo
[ $fail -eq 0 ] && echo "✓ All security checks passed" || echo "✗ Some security checks failed"
exit $fail
