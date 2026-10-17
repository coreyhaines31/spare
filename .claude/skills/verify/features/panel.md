# Panel

The menu bar gauge (accessibility label `Spare`, or `Spare: <health>` plus enabled readings) toggles a popover with the overview, the grouped list, row details, the gear menu, and the request prompt. `Open in a window` shows the same view in a window titled `Spare`; the chart button opens `Spare — Recap`.

## Sub-features

- `panel-toggle` clicking the gauge opens or closes the popover; launch opens it once.
- `panel-overview` CPU and memory pressure header, then rows grouped and sorted.
- `panel-detail` clicking a row shows what it is, the consequence, memory history, and `Inside` for browsers.
- `panel-gear` the `Settings` menu: `Open in a window`, `Launch at login`, `Show in Menu Bar` (CPU, GPU, Memory, Startup disk), `Warn about sustained pressure`, `Show unidentified processes`, `Install Command Line Tool…`, `Check for Updates…`, `Open Activity Monitor`, `Quit Spare`.
- `panel-request` a CLI request shows `<Verb> <name>?` and `<requester> asked Spare to <verb> <name>, which is using <memory>.` with the action button.
- `panel-recap` `Daily and weekly recap` opens the Recap window.

## How to get to it (user POV)

- Click the gauge in the menu bar.
- Open Spare again from Applications (reopen shows the window).
- `spare open`, or any `spare quit` request, brings the panel forward.

## Driving it with spare-verify

Preconditions:

- Doctor is all `ok`.
- The terminal running the agent has **Accessibility** and **Screen Recording** in System Settings > Privacy & Security. Check: `osascript -e 'tell application "System Events" to get name of every process whose name is "Spare"'` prints `Spare` (not error -1719), and `screencapture -x /tmp/spare-check.png` succeeds.

- **Window proof.** Run `$V cli open`, then read the `Spare` window's UI tree: `osascript -e 'tell application "System Events" to tell process "Spare" to get entire contents of window "Spare"'` > `artifacts/verify/<run-id>/panel.ax.txt`, and capture it with `screencapture -x -l <windowid>`. The tree contains `Settings` and `Daily and weekly recap`.
- **Request prompt.** With a fixture, start `$V cli quit $port --timeout 30 --json` in the background, then capture the window. It shows `Stop verify-quit-fixture?`. Let it time out, or click the action button only for the fixture.

## Gotchas

- Not yet proven: on 2026-10-14 the agent terminal had neither permission, so every panel path was `verified-unreachable` (prerequisite: Accessibility + Screen Recording for the terminal app). Granting them is the person's call; never change security settings.
- The popover is transient: activating another app closes it. Prefer `Open in a window` for captures.
- Settings toggles write to the person's defaults domain; teardown restores the snapshot, but avoid `Launch at login` (it registers a login item for the dev build's path).
