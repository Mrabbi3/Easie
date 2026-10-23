# Easie launch video kit

Rebuilds Easie's 33-second launch video (a music-only cut and a voiced cut), and the README's demo clips.
Every frame is a pure function of time in a web page (`kit/motion.js`), rendered frame by frame in headless
Chrome; the music and sound effects are synthesised; the voice is a local text-to-speech model.

The Easie interface in the video is real: `capture/run.sh` renders the app's own SwiftUI views (format icons,
every state of the popup, the setup window) to images offscreen, from a scratch copy of the sources, and runs
a real conversion through Easie's engine. The laptop, desktop, Finder window and menu are recreations.

## What you need

- macOS with the Xcode Command Line Tools, and Easie built once (`scripts/build.sh` in the repository root)
- Google Chrome, Node.js 18+, FFmpeg, and `whisper-cli` ([whisper.cpp](https://github.com/ggml-org/whisper.cpp))
  with the `ggml-base.en` and `ggml-large-v3-turbo-q5_0` models in `~/.local/share/whisper-models/`
- Python 3 with NumPy, SciPy and soundfile (music, effects, mix)
- For the voiced cut: [kokoro-onnx](https://github.com/thewh1teagle/kokoro-onnx) with `kokoro-v1.0.onnx` and
  `voices-v1.0.bin` in `~/.local/share/kokoro/`

Licences for all of these are listed in [THIRD_PARTY_NOTICES.md](../../THIRD_PARTY_NOTICES.md).

## Rebuild

```bash
cd marketing/launch-video
npm install                                   # puppeteer-core
capture/run.sh                                # real Easie views -> shots/app/
python3 kit/sfx.py                            # sound effects -> audio/sfx/
python3 kit/music.py launch --dur 33 --drop 4 --brk 24 --hit 28 --out audio/music/launch.wav
cp audio/music/launch.wav audio/music/launch-vo.wav

# music-only cut -> launch/out/easie-launch.mp4
python3 -c "import numpy, soundfile; soundfile.write('launch/vo/vo.wav', numpy.zeros(33 * 48000, 'float32'), 48000)"
node kit/render.mjs launch/launch.html && python3 kit/mix.py launch 0.62

# voiced cut -> launch-vo/out/easie-launch-vo.mp4
python3 kit/voice.py launch/vo-read --engine kokoro --kvoice af_heart --takes 3 --wps 2.6 | tee launch/vo-read/run.log
python3 kit/place_vo.py launch/vo-read launch-vo/vo --dur 33
node kit/render.mjs launch-vo/launch-vo.html && python3 kit/mix.py launch-vo 0.5
```

`mkdir -p launch/vo` first if it doesn't exist. Use whichever Python has the packages (for example a venv).

QA while editing: `node kit/render.mjs launch/launch.html --grid 48` makes a contact sheet, and
`--at 12.5,15` makes full-size stills. Opening `launch/launch.html` in a browser gives a scrub bar (space plays).

## Files

| Path | What it is |
| --- | --- |
| `launch/film.js`, `launch/film.css` | the film: every scene, camera move and sound cue, timed to a 120 BPM grid |
| `launch/launch.html` | music-only cut |
| `launch-vo/launch-vo.html` | voiced cut (same film; a few captions follow the voice) |
| `launch/vo-read/script.txt` | the voiceover lines (`shown | spoken` fixes pronunciation) |
| `kit/place_vo.py` | puts each voice line at its caption's time (`SLOTS`) |
| `kit/` | the motion kit, renderer, music, effects, voice and mix scripts |
| `capture/` | renders Easie's own views offscreen |

Generated files (`shots/`, `audio/`, `*/out/`, voice takes) are not committed. `shots/` contains renders of
macOS and Office icons, which belong to Apple and Microsoft.

## Making a new film

1. Change the copy in `launch/film.js` (captions are `K(...)` calls with their times) or the voice lines in `script.txt`.
2. Keep cuts on the beat: `DROP`, `BRK` and `HIT` at the top of `film.js` are the music's drop, breakdown and
   final hit, and `music.py` is called with the same values.
3. Contact sheet → stills of dense moments → full render → mix → listen, and run Whisper on the finished mix
   to make sure the voice is still clear over the music.
