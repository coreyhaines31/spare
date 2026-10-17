# Spare verification map

The maintained source for verifying Spare's user-facing behavior. Read this index, then use the matching feature file as the recipe.

## Baseline preconditions

- `dist/Spare.app` built from this checkout (`$V build`).
- `$V launch` succeeded and `$V doctor` is all `ok`; the person's Spare is parked.
- `V=.claude/skills/verify/scripts/spare-verify`.

## Driving conventions

- Run every CLI action as `$V cli <args>`, never the installed `spare` on `PATH`; that one is the person's release build.
- Target closable things by port or `--json` id, and only things this run started (`$V fixture-server`).
- Never approve a request against the person's apps. Prove requests with `--timeout`.
- Live readings change between calls. Assert shape, kind, and exit codes.

## Proof and skip reporting

- CLI proof is the recorded `NN.cmd/stdout/stderr/exit` set in `artifacts/verify/<run-id>/`.
- Mutations (requests) need a second read showing the resulting state.
- Panel proof needs Accessibility + Screen Recording for the terminal. Without them, report `verified-unreachable` with that prerequisite; do not count CLI output as panel proof.
- Report the feature ID and entry point with each artifact.

## Feature entry contract

Each file has an H1, one paragraph, then exactly: `Sub-features`, `How to get to it (user POV)`, `Driving it with spare-verify`, `Gotchas`.

## Features

- [Status](./status.md): CPU, memory, and pressure right now, with pressure-coded exit codes.
- [List and show](./list-and-show.md): grouped apps, projects, and agents; details for one item.
- [Quit requests](./quit-requests.md): `spare quit` asks the panel; the person approves or declines.
- [Idle and leftovers](./idle-and-leftovers.md): unused apps and automation-left browser sessions.
- [Recap](./recap.md): saved history for today, this week, or the last 7 days.
- [Panel](./panel.md): the menu bar gauge, panel, gear menu, and request prompt.
