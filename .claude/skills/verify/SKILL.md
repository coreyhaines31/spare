---
name: verify
description: Drive a dev build of Spare (macOS menu bar app + `spare` CLI) the way a user does and capture proof. Use before claiming a Spare change works, to reproduce a bug, or when asked to verify/test Spare end to end.
---

# Verify Spare

Spare is a macOS menu bar app (no Dock icon, `LSUIElement`) plus a `spare` command-line tool bundled inside it at `Spare.app/Contents/MacOS/spare-cli`. The CLI is the scripted surface: most commands read the Mac directly, and `idle`, `quit`, and `leftovers --close` talk to the running app over distributed notifications. The panel is SwiftUI in an `NSPopover`.

Everything goes through one helper. Run it from anywhere in the repo:

```sh
V=.claude/skills/verify/scripts/spare-verify
$V build            # make app -> dist/Spare.app (release build, ad-hoc signed)
$V launch           # park the installed Spare, start the dev build, wait until ready
$V doctor           # read-only health check; run first and after anything surprising
$V cli <args...>    # run the dev build's `spare`, recording evidence
$V fixture-server <name>   # throwaway python http.server Spare lists as a project; prints its port
$V teardown         # stop what launch started, restore the installed Spare and its data
```

## Isolation (read this first)

Only one Spare can run at a time. Every copy shares the bundle id `com.spareformac.Spare`, the defaults domain, `~/Library/Application Support/Spare/recaps.json`, and the request notification channel, so a `spare quit` would reach two instances at once. So `launch`:

1. records any running Spare (normally `~/Applications/Spare.app`, the person's own) in `.build/verify-state/parked`,
2. exports the defaults domain and copies `recaps.json` into the state dir,
3. quits the installed copy (Apple Event, then SIGTERM by PID, never by name),
4. starts `dist/Spare.app` with `open -n -g`.

`teardown` reverses all of it. Never leave a run without teardown: until then the person's own Spare is not running. If a run dies midway, run `teardown`; it works from whatever state exists.

## Launch

```sh
$V build && $V launch
```

Ready means `spare idle --json` succeeds, which needs the CLI to find the running app by bundle id. Launch prints `ready: pid <pid>, evidence in <dir>`. There is no data dir to seed; Spare reads live processes. On launch the app opens its panel and activates itself, so the person sees it appear. That is expected.

## Doctor

```sh
$V doctor
```

Every line must read `ok`:
- the recorded PID runs this checkout's `dist/Spare.app`
- no other Spare instance is running
- the build is newer than every file in `Sources/` (otherwise `build`, `teardown`, `launch`)
- the CLI reaches the running app
- `status --json` parses

## Drive

Use `$V cli ...` for every CLI action so evidence is recorded. Address things by **port** or **id** from `--json` output, not by display name: names like `Claude · coreyhaines` change with the person's workload.

For anything that could close something (`quit`, `leftovers --close`), target only what this run started. `fixture-server` creates a folder outside the repo (under `$TMPDIR/spare-verify-fixtures/`) running `python3 -m http.server`, which Spare lists as a Project with that port. Started inside the checkout, Spare would group it with the whole repo, and stopping it would stop everything running there.

Never approve a request against the person's real apps. Prove the request path with `--timeout N`: the app answers `waiting`, the CLI times out, withdraws the request, and exits 4.

The panel itself can only be driven or captured when the terminal has Accessibility and Screen Recording permission (System Settings > Privacy & Security). Without them, `osascript` UI scripting fails with -1719 and `screencapture` fails with "could not create image from display". Check before planning a panel proof: see [features/panel.md](features/panel.md).

## Evidence

Each `$V cli` call writes `NN.cmd`, `NN.stdout`, `NN.stderr`, `NN.exit` into `artifacts/verify/<run-id>/` (gitignored). Proof standards:

- Exercise the real CLI or panel path, never internal functions or test-only flags. `Spare --snapshot` is a debug sampler, not a user path.
- Capture the action and the resulting state: for a request, the `waiting` note on stderr (`Waiting for approval in Spare's panel`) plus the final JSON outcome and exit code.
- Verify side effects with a second read: after a declined or timed-out quit, `list --projects --json` still lists the fixture port and `curl` against it still answers.
- Readings are live and vary between calls; assert shapes, kinds, and exit codes, not exact numbers.

## Cleanup

```sh
$V teardown
```

It kills fixture servers and the dev Spare by the PIDs it recorded, re-imports the saved defaults, restores `recaps.json`, relaunches every parked app, and removes `.build/verify-state/`. It never touches `artifacts/verify/`. Afterwards, confirm the person's Spare is back: `pgrep -lf 'Spare.app/Contents/MacOS/Spare$'` shows `~/Applications/Spare.app` (or `/Applications/Spare.app`).

## Feature map

[features/README.md](features/README.md) lists every mapped feature with its recipe. A proof through one entry point does not cover the others the map lists.

## Gotchas

- `status` exits 2 under Warning and 3 under Critical memory pressure. That is a successful reading, not an error.
- Release `Info.plist` is reused, so the dev build has Sparkle pointed at the real appcast. If the checkout's version is behind the latest release, Sparkle may offer an update in the dev build; dismiss it, never install.
- Anything the person's Spare would have recorded while parked is not recorded; the restored `recaps.json` drops what the dev build wrote.
- `idle` only knows about apps used since this Spare launched, so it is empty right after `launch`.
