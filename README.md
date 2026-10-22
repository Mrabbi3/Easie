# Easie

Convert any file into any format — free, no ads, no account, fully offline.

Right-click a file in Finder → **Edit with Easie**. The file pops up with every format it can
become arranged around it. Click one and it's done: the new file appears next to the original,
and nothing is ever overwritten. Click elsewhere or press Esc to close the popup.

Opening Easie itself shows a small setup window:

- **Right-click menu** switch: turns "Edit with Easie" on or off in Finder.
- **Pages, Keynote and Numbers**: asks macOS once, up front, to let Easie use those apps.
- A drop area to try it out.

Easie has no Dock icon while you use it from Finder. After the first use it stays quietly in the
background (about 30 MB), so the popup appears in about 0.2 s instead of starting the app each time.
"Quit Easie" in the setup window stops it; it starts again on the next right-click.

## What converts to what

| From | To |
| --- | --- |
| Word (DOCX, DOC), ODT, RTF, HTML, TXT, Markdown | PDF, DOCX, DOC, ODT, RTF, HTML, TXT, MD, Pages, JSON, PNG, JPG |
| Pages | PDF, DOCX, DOC, ODT, RTF, HTML, TXT, MD, JSON, PNG, JPG |
| PowerPoint (PPTX) | PDF, Keynote, PNG, JPG (one per slide), and the slide text as DOCX, TXT, MD, JSON, HTML, RTF, ODT |
| Keynote | PDF, PPTX, PNG, JPG, and the slide text as DOCX, TXT, MD, JSON, HTML, RTF |
| Excel (XLSX), Numbers | CSV, TSV, JSON, PDF, DOCX, HTML, MD, TXT, and each other (every sheet is kept) |
| CSV, TSV, JSON | XLSX, Numbers, CSV, TSV, JSON, PDF, DOCX, HTML, MD, TXT |
| PDF | DOCX, ODT, RTF, HTML, TXT, MD, JSON, PNG, JPG, TIFF, HEIC (scanned PDFs are read with OCR) |
| PNG, JPG, HEIC, TIFF, GIF, BMP, WebP | Any of those image formats, PDF, and TXT / DOCX / JSON via text recognition (OCR) |

Run `build/Easie.app/Contents/MacOS/Easie formats` for the exact list on your Mac
(HEIC and WebP output depend on the Mac's built-in encoders).

### How the engine works

- **Built-in frameworks** handle most formats: AppKit's text system for documents, PDFKit, ImageIO, and Vision for OCR.
- **Excel and PowerPoint** files are read directly (they're ZIP files of XML), so they need no Office install.
  Easie reads every sheet of a workbook, including real dates, and reads each slide's title, bullet points, tables and speaker notes.
  It also writes `.xlsx`.
- **Pages, Keynote and Numbers** keep their formats private, so Easie asks those (free) apps to open and export the file.
  This also gives pixel-perfect PDFs and images of PowerPoint decks.
  The apps open briefly in the background. Easie closes any it had to start, and it never closes documents you already had open.
  The first time, macOS asks to let Easie control the app.
  Without Keynote, PowerPoint → PDF still works, but it lays out the slide text instead of the slide design.

## Build & run

Only the Xcode **Command Line Tools** are needed (full Xcode is optional).

```bash
scripts/install.sh        # build, copy to /Applications, register the right-click menu
scripts/smoke-test.sh     # convert sample files through every path
scripts/security-test.sh  # hostile files: tracking web page, zip bomb, nested JSON, overwrite check
scripts/make-dmg.sh       # build/Easie.dmg for your download page
```

Builds are universal (Apple Silicon + Intel). For a faster local build use `ARCHS=arm64 scripts/build.sh`.

## Privacy and safety

- Easie never connects to the internet. Web pages are cleaned before conversion (`SafeHTML.swift`), so
  scripts, tracking pixels, remote fonts and references to other files on the Mac are dropped.
- Conversions only ever write new files; an existing name gets " (1)", " (2)"…
- Hostile files are refused rather than crashing: ZIP parts over 512 MB, images decode at most 16,384 px,
  JSON nests at most 512 levels.
- Temporary files from Pages/Keynote/Numbers exports go to a private temp folder that is deleted afterwards.
- Diagnostics are debug-level only (not stored by macOS) and never include file contents.

The public download page lives in `site/index.html`.

Finder shows **Edit with Easie** at the bottom of the right-click menu, or under **Quick Actions** / **Services**
when you have many. If it doesn't appear, open Easie and make sure the Right-click menu switch is on.

There's also a command line mode:

```bash
Easie convert report.docx notes.md --to pdf --out ~/Desktop
```

## Project layout

```
Sources/EasieCore/   conversion engine (no UI)
  Format.swift            formats and what each converts to
  ConversionEngine.swift  load → convert → write, PDF layout, rendering, OCR
  AppleApps.swift         Pages / Keynote / Numbers bridge (AppleScript)
  XLSX.swift              Excel reader and writer
  PPTX.swift              PowerPoint text reader, slide renderings
  Zip.swift, XMLNode.swift  ZIP and XML plumbing for Office files
  SafeHTML.swift          strips anything a web page could use to reach the network
  Tables.swift            CSV/TSV and table ↔ JSON
  JSON.swift              order-preserving JSON parser/writer
  Markdown.swift          Markdown ↔ rich text
Sources/Easie/       the Mac app
  AppDelegate.swift       launch flow, Finder service, menus
  RadialMenu.swift        the right-click popup and its animation
  ConversionSession.swift what one right-click is converting
  FormatStyle.swift       file-style format icons
  SetupView.swift         setup window (switch, permissions, try it)
  SystemIntegration.swift right-click on/off, Automation permission
  CLI.swift               `Easie convert …`
Resources/Info.plist  bundle info, "Open With", and the Finder service
scripts/              build, install, DMG, icon, smoke test
```

## Shipping outside the App Store

To let people download Easie from your website without macOS warning that it's from an "unidentified developer":

1. Join the Apple Developer Program ($99/year) and create a **Developer ID Application** certificate.
2. Build signed: `SIGN_ID="Developer ID Application: Your Name (TEAMID)" scripts/build.sh && scripts/make-dmg.sh`
   (this signs with `Resources/Easie.entitlements`, which allows controlling Pages/Keynote/Numbers)
3. Notarize: `xcrun notarytool submit build/Easie.dmg --apple-id you@example.com --team-id TEAMID --wait`
   then `xcrun stapler staple build/Easie.dmg`.

Without that, people can still install it, but they must open
System Settings → Privacy & Security → **Open Anyway** the first time.

## Ideas for next steps

- PDF → PowerPoint (one slide per page) and images → PowerPoint
- High-fidelity Word → PDF through Pages, as an option (keeps headers, footers and images)
- Merge several images or PDFs into one PDF; split a PDF into pages
- Compress PDFs and resize images
- A top-level Finder menu with a submenu of formats (Finder Sync extension; needs full Xcode)
- Settings: output folder, image quality, page size
- Auto-updates with Sparkle
