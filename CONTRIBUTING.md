# Contributing to Spare

Thanks for helping. Bug reports, fixes, and ideas are all welcome. For something larger than a small fix, please [open an issue](https://github.com/coreyhaines31/spare/issues) first so we can agree on the approach.

## Build from source

You'll need:

- An Apple-silicon Mac with macOS 14 or later.
- **Full Xcode** installed at `/Applications/Xcode.app` (the Command Line Tools alone aren't enough). The `Makefile` points builds at Xcode for you without changing your system setting.
- [SwiftLint](https://github.com/realm/SwiftLint) for `make lint`: `brew install swiftlint`.

Then:

```sh
git clone https://github.com/coreyhaines31/spare.git
cd spare
make app        # builds dist/Spare.app (ad-hoc signed, for local use)
make run        # builds and opens it
```

If you already have the released Spare running, quit it first (gear menu → Quit Spare) so you don't end up with two menu bar icons.

Other commands:

```sh
make test       # unit tests
make lint       # SwiftLint, strict
make build      # debug build without bundling the app
```

Useful launch options for a local build:

```sh
open dist/Spare.app --args --window             # open in a window instead of the menu bar panel
dist/Spare.app/Contents/MacOS/Spare --snapshot  # print one system reading as JSON and exit
```

## How the code is organized

| Folder | What's in it |
|---|---|
| `Sources/CSpare` | A small C module that reads processes, memory, and CPU from macOS APIs, and sends stop signals after rechecking a process's identity. |
| `Sources/SpareCore` | Plain Swift logic with no UI: grouping processes into apps, projects, and agents; helper roles; session origins; recaps; idle apps; health. Almost all tests live here. |
| `Sources/Spare` | The SwiftUI and AppKit app: the menu bar panel, detail views, the Recap window, and Sparkle updates. |
| `Tests/SpareCoreTests` | Unit tests for `SpareCore`. |
| `scripts` | `bundle.sh` builds the app, `icon/` draws the app icon, `release.sh` makes a signed release. |

[How Spare works](docs/how-it-works.md) explains the measurements and heuristics behind the code.

## Sending a change

1. Fork the repo and create a branch.
2. Keep each commit to one logical change.
3. Add or update tests in `Tests/SpareCoreTests` for logic changes.
4. Run `make lint` and `make test`; both must pass.
5. Open a pull request describing what changed and how you checked it. Screenshots help for UI changes.

A few principles keep Spare trustworthy:

- **Never close anything automatically.** Every quit or stop is reviewed by the person first, and macOS processes are never offered for stopping.
- **Stay local.** No telemetry or network requests beyond Sparkle's update check, and nothing that saves process arguments or paths.
- **Be honest about limits.** Prefer "Spare can't tell" over a guess presented as fact.

## Releasing (maintainers)

`scripts/release.sh` builds a release, exports it with Developer ID cloud signing, notarizes the app and DMG, writes `SHA256SUMS.txt`, and writes a Sparkle `appcast.xml` signed with the EdDSA key stored in the keychain account `SPARKLE_ACCOUNT` (default `spare`).

```sh
TEAM_ID=… DEVELOPMENT_IDENTITY="Apple Development: …" NOTARY_PROFILE=… bash scripts/release.sh
```

Bump `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist` first, and release from `main`. The script doesn't publish anything. Create the GitHub release with the DMG, `appcast.xml`, and `SHA256SUMS.txt` attached; the app reads its update feed from the latest release.
