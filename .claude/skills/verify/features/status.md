# Status

`spare status` reports CPU in use and available, memory used of total, swap, and macOS memory pressure, with a plain-language title and advice. The exit code encodes pressure so scripts and agents can branch on it.

## Sub-features

- `status-text` prints a title line, a CPU/pressure/memory line, and advice.
- `status-json` prints `cpu_percent`, `cpu_available_percent`, `memory_pressure`, `memory_used`, `memory_used_bytes`, `memory_total`, `memory_total_bytes`, `swap_bytes`, `title`, `message`.
- `status-exit` exits 0 Normal, 2 Warning, 3 Critical.

## How to get to it (user POV)

- Run `spare status` or `spare status --json` in a terminal. Works without the app running.
- The panel's overview header shows the same reading (see [panel.md](./panel.md)).

## Driving it with spare-verify

Preconditions:

- Doctor is all `ok`.

- **Text reading.** Run `$V cli status`. Stdout has three lines; the second starts `CPU ` and contains `Memory pressure Normal|Warning|Critical` and `GB of`.
- **JSON reading.** Run `$V cli status --json`. Stdout parses as one object with every key in `status-json`; `memory_pressure` is `normal`, `warning`, or `critical`.
- **Exit code matches pressure.** Compare the recorded exit with `memory_pressure`: `normal` -> 0, `warning` -> 2, `critical` -> 3.

## Gotchas

- Exit 2 or 3 is a successful reading. Don't treat it as a failure, and don't run it under `set -e` or `pipefail` without capturing the code.
- The first reading after launch or wake can say "Getting a feel for your Mac" while CPU needs two samples; retry after a few seconds.
- Memory pressure can be `Unavailable` for one reading; retry once before calling it drift.
