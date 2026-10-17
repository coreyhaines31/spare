# Recap

`spare recap [today|week|7d]` summarizes saved history: time recorded, average and peak CPU, time under elevated memory pressure, and what used the most. The same data drives the panel's Recap window, which also exports CSV.

## Sub-features

- `recap-text` starts `<Period> · recorded <duration>`, then `Average CPU N% · peak N%`, pressure summary, `Most memory:` and `Most CPU:` lines.
- `recap-json` keys: `period`, `start`, `end`, `recorded_seconds`, `average_cpu_percent`, `peak_cpu_percent`, `elevated_pressure_seconds`, `elevated_pressure_percent`, `summary`, `top_by_memory`, `top_by_cpu`.
- `recap-periods` accepts `today` (default), `week`, `7d`; anything else exits 1 with `Choose a period: today, week, or 7d.`

## How to get to it (user POV)

- Run `spare recap`, `spare recap week`, `spare recap 7d`.
- In the panel, the chart button (`Daily and weekly recap`) opens the `Spare — Recap` window.

## Driving it with spare-verify

Preconditions:

- Doctor is all `ok`.

- **Today.** Run `$V cli recap`. Exit 0; first line starts `Today · recorded`.
- **JSON.** Run `$V cli recap 7d --json`. Exit 0; every `recap-json` key present; `recorded_seconds` > 0.
- **Bad period.** Run `$V cli recap month`. Exit 1, `Choose a period`.

## Gotchas

- History is the person's real `recaps.json`, so values vary; launch backs it up and teardown restores it.
- If history saving is paused in the app, recorded time stops growing. That is the setting, not a bug.
