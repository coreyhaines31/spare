# Idle and leftovers

`spare idle` lists apps over a memory threshold that haven't been used for 2+ hours since Spare opened. `spare leftovers` lists browser sessions that automation tools (agent-browser, Playwright, Puppeteer) left open, with what opened them; `--close` asks the panel to close them.

## Sub-features

- `idle-list` needs the app running; prints a table or `No apps over <size> have gone unused for 2+ hours since Spare opened.`; `--json` is an array.
- `idle-not-running` fails with `Spare needs to be running to know when you last used each app.`
- `leftovers-list` prints `APP PID MEMORY WHY IT'S A LEFTOVER`; `--json` objects have `app`, `pid`, `memory`, `memory_bytes`, `origin`.
- `leftovers-filter` narrows by app name: `spare leftovers <app>`.
- `leftovers-close` sends a close request to the panel, same flow as [quit-requests.md](./quit-requests.md).

## How to get to it (user POV)

- Run `spare idle`, `spare leftovers`, `spare leftovers --close`.
- In the panel: the **Not used lately** section and the browser automation sessions in a browser's detail.

## Driving it with spare-verify

Preconditions:

- Doctor is all `ok`.

- **Idle answers.** Run `$V cli idle --json`. Exit 0; stdout is a JSON array. Right after launch it is `[]`, which is correct.
- **Leftovers list.** Run `$V cli leftovers --json`. Exit 0; stdout is an array; each object has the `leftovers-list` keys, and `origin` names the tool, e.g. `Kept open in the background by agent-browser`.
- **Close request path.** Only if `leftovers --json` is non-empty: run `$V cli leftovers --close --timeout 6 --json`. Exit 4, `outcome` `timed-out`, stderr `Waiting for approval`; re-run `leftovers --json` and the same PIDs are still listed.

## Gotchas

- Leftovers depend on what the person has running; an empty array is valid, not a failure. To force one, start a headless browser session yourself and close it in cleanup.
- Never approve `leftovers --close`: the sessions belong to the person's other agents.
- `idle` reads the app's activity log from the defaults domain; teardown restores it.
