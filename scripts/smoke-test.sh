#!/bin/bash
# Pushes sample files through every kind of conversion using the built app's CLI mode.
set -uo pipefail
cd "$(dirname "$0")/.."

[ -d build/Easie.app ] || scripts/build.sh
EASIE="$PWD/build/Easie.app/Contents/MacOS/Easie"
DIR=build/smoke
rm -rf "$DIR" && mkdir -p "$DIR"

cat > "$DIR/notes.md" <<'EOF'
# Trip plan

Pack **light** and bring *sunscreen*. See [the map](https://maps.apple.com).

## Checklist
- Passport
- Charger
- Snacks

1. Book hotel
2. Rent car
EOF
printf 'Hello from Easie.\nThis is plain text.\n' > "$DIR/hello.txt"
printf '<h1>Invoice</h1><p>Total: <b>$42</b></p><table border=1><tr><th>Item</th><th>Qty</th></tr><tr><td>Tea</td><td>3</td></tr></table>' > "$DIR/invoice.html"
printf 'name,age,city\n"Smith, Ann",34,Dhaka\nBob,27,"New ""York"""\n' > "$DIR/people.csv"
printf '{"users":[{"id":1,"name":"Ann","tags":["a","b"]},{"id":2,"name":"Bob","active":true}]}' > "$DIR/users.json"

fail=0
run() { "$EASIE" convert "$@" || fail=1; }

run "$DIR/notes.md" --to docx
run "$DIR/notes.docx" --to pdf
run "$DIR/notes.pdf" --to png
run "$DIR/notes.png" --to jpg
run "$DIR/notes.jpg" --to txt          # OCR
run "$DIR/notes.png" --to pdf
run "$DIR/notes.pdf" --to md
run "$DIR/notes.docx" --to json
run "$DIR/notes.docx" --to odt
run "$DIR/notes.odt" --to rtf
run "$DIR/hello.txt" --to pdf
run "$DIR/invoice.html" --to docx
run "$DIR/invoice.html" --to pdf
run "$DIR/people.csv" --to json
run "$DIR/people.json" --to tsv
run "$DIR/people.csv" --to pdf
run "$DIR/people.csv" --to md
run "$DIR/users.json" --to csv
run "$DIR/notes.png" --to heic

# Office files, read and written by Easie itself
printf 'id,name,joined,zip\n1,Ann,2026-01-05,02134\n2,Bob,2026-02-11,10001\n' > "$DIR/members.csv"
run "$DIR/members.csv" --to xlsx
run "$DIR/members.xlsx" --to json
run "$DIR/members.xlsx" --to pdf
mkdir -p "$DIR/roundtrip"
run "$DIR/members.xlsx" --to csv --out "$DIR/roundtrip"
cmp -s "$DIR/members.csv" "$DIR/roundtrip/members.csv" || { echo "✗ CSV → XLSX → CSV changed the data"; fail=1; }

# Pages, Keynote and Numbers (only when installed)
app() { [ -d "/Applications/$1.app" ]; }
if app Numbers; then run "$DIR/members.xlsx" --to numbers; run "$DIR/members.numbers" --to csv --out "$DIR/from-numbers"; fi
if app Pages; then run "$DIR/notes.docx" --to pages; run "$DIR/notes.pages" --to pdf --out "$DIR/from-pages"; run "$DIR/notes.pages" --to md --out "$DIR/from-pages"; fi
if app Keynote; then
  osascript - "$PWD/$DIR/deck.key" <<'APPLESCRIPT'
on run argv
	tell application id "com.apple.iWork.Keynote"
		set d to make new document with properties {document theme:theme "White"}
		set object text of default title item of first slide of d to "Hello from Easie"
		save d in POSIX file (item 1 of argv)
		close d saving no
		quit
	end tell
end run
APPLESCRIPT
  run "$DIR/deck.key" --to pptx
  run "$DIR/deck.pptx" --to md
  run "$DIR/deck.pptx" --to png
  run "$DIR/deck.key" --to pdf --out "$DIR/from-keynote"
fi

echo
if [ $fail -eq 0 ]; then echo "✓ All conversions succeeded (outputs in $DIR)"; else echo "✗ Some conversions failed"; fi
exit $fail
