# Third-party notices

## The Easie app

The app has **no third-party dependencies**: no Swift packages, frameworks or code from other projects are
compiled into it or shipped with it. It uses only Apple's system frameworks (AppKit, SwiftUI, Foundation,
PDFKit, ImageIO, Vision, Compression, CoreServices, UniformTypeIdentifiers, OSLog), which are part of macOS.

The popup's symbols come from SF Symbols, which Apple licenses for use in apps on Apple platforms.
The app icon is drawn by `scripts/IconRenderer.swift` and is part of this project (MIT).

Easie talks to Pages, Keynote and Numbers through AppleScript when they are installed on the user's Mac;
those apps are not included or redistributed.

## The download page (`site/`)

Fonts are loaded from Google Fonts at view time; they are not stored in this repository.

| Font | Licence |
| --- | --- |
| [Bricolage Grotesque](https://fonts.google.com/specimen/Bricolage+Grotesque) | SIL Open Font License 1.1 |
| [Instrument Sans](https://fonts.google.com/specimen/Instrument+Sans) | SIL Open Font License 1.1 |
| [JetBrains Mono](https://fonts.google.com/specimen/JetBrains+Mono) | SIL Open Font License 1.1 |

Hosting: GitHub Pages and Vercel. Deployment uses the GitHub Actions
[`actions/checkout`](https://github.com/actions/checkout), [`actions/configure-pages`](https://github.com/actions/configure-pages),
[`actions/upload-pages-artifact`](https://github.com/actions/upload-pages-artifact) and
[`actions/deploy-pages`](https://github.com/actions/deploy-pages) (all MIT).

## The launch video kit (`marketing/launch-video/`)

These tools are used to *make* the video. None of them is bundled with Easie, and none of them is
stored in this repository; each is installed separately by whoever rebuilds the video.

| Tool | Used for | Licence |
| --- | --- | --- |
| [Puppeteer](https://github.com/puppeteer/puppeteer) (`puppeteer-core`) | driving headless Chrome to render frames | Apache-2.0 |
| Google Chrome | rendering the frames | Google's terms (installed by the user) |
| [FFmpeg](https://ffmpeg.org) | encoding video and mixing audio, run as a command-line tool | LGPL-2.1+ / GPL-2.0+ depending on the build |
| [Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M) voice model | the voiceover | Apache-2.0 |
| [kokoro-onnx](https://github.com/thewh1teagle/kokoro-onnx) | running the voice model | MIT |
| [ONNX Runtime](https://github.com/microsoft/onnxruntime) | running the voice model | MIT |
| [whisper.cpp](https://github.com/ggml-org/whisper.cpp) and OpenAI [Whisper](https://github.com/openai/whisper) models | timing words and checking the voice can be understood | MIT |
| [NumPy](https://numpy.org), [SciPy](https://scipy.org), [python-soundfile](https://github.com/bastibe/python-soundfile) | synthesising the music and sound effects, mixing | BSD-3-Clause |
| [Inter Tight](https://fonts.google.com/specimen/Inter+Tight), Bricolage Grotesque, JetBrains Mono (Google Fonts) | titles and captions | SIL Open Font License 1.1 |

The music and sound effects are synthesised by `kit/music.py` and `kit/sfx.py`; no samples or recordings
from others are used. The recreated macOS screens in the video are set in the Mac's system font, as a user
interface mock-up.

The video shows Finder, the Dock and file icons as they appear on a Mac, including icons for Apple's and
Microsoft's apps. Those icons belong to their owners. They are captured locally when the video is rebuilt
(`capture/run.sh`) and are deliberately kept out of this repository (see `.gitignore`).

## Trademarks

Apple, Mac, macOS, Finder, Pages, Keynote, Numbers, Safari and SF Symbols are trademarks of Apple Inc.
Microsoft, Word, Excel and PowerPoint are trademarks of Microsoft Corporation. Google Chrome is a trademark of
Google LLC. Easie is an independent project and is not affiliated with or endorsed by any of them.
