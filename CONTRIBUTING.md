# Contributing to Easie

Thanks for helping. Easie is a small, dependency-free Mac app, and the goal is to keep it that way: one
right-click, fast, offline, and safe with any file.

## Ways to help

- **Report a bug.** Open an [issue](https://github.com/Mrabbi3/Easie/issues/new/choose) with your macOS version,
  the Easie version, and the file type. A sample file (with nothing private in it) helps most.
- **Ask for a format or a feature.** Say what you're converting from and to, and why.
- **Send a pull request.** Fixes, new formats, translations and docs are all welcome.

Security problems go through a private report instead. See [SECURITY.md](SECURITY.md).

## Set up

You need macOS 13 or later and the Xcode Command Line Tools (`xcode-select --install`). Full Xcode is optional.

```bash
git clone https://github.com/Mrabbi3/Easie.git && cd Easie
ARCHS=arm64 scripts/build.sh      # quick single-architecture build into build/Easie.app
scripts/install.sh                # or: build, copy to /Applications, register the right-click menu
```

Try a change without Finder through the command line mode:

```bash
build/Easie.app/Contents/MacOS/Easie convert sample.docx --to pdf --out /tmp
build/Easie.app/Contents/MacOS/Easie formats
```

## Before you open a pull request

1. `scripts/smoke-test.sh` passes (it converts sample files through every path; the Pages, Keynote and
   Numbers checks run only when those apps are installed).
2. `scripts/security-test.sh` passes (hostile files: tracking web page, zip bomb, nested JSON, overwrite check).
3. New behaviour has a line in one of those scripts, so it stays tested.
4. The README is updated if you changed what Easie converts or how it's used.

CI runs the build and both test scripts on every pull request.

## Guidelines

- **No third-party dependencies** in the app. Easie is built only on Apple's frameworks; that keeps it small,
  auditable and free of licence obligations. If you think one is needed, open an issue first.
- **No network access.** Easie must never connect to the internet, and converted web pages must not either
  (see `SafeHTML.swift`).
- **Never overwrite.** Conversions write new files only.
- **Refuse hostile input instead of crashing.** Keep size and depth limits on anything that parses untrusted files.
- **Match the code around you**: Swift's standard style, small types, comments that say *why*.
- Keep pull requests focused: one fix or feature each, with a clear description of what changed and how you tested it.

## Licence

By contributing, you agree that your contribution is released under the project's [MIT License](LICENSE).
Only submit work you wrote yourself or have the right to share under that licence.
