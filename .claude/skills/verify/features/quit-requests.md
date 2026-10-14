# Quit requests

`spare quit <name>` never closes anything itself. It sends a request to the running app, which shows "<requester> asked Spare to stop <name>…" in the panel and waits for the person to choose. The command reports approved, declined, timed out, or withdrawn.

## Sub-features

- `quit-waiting` sends the request; the app acknowledges and stderr shows `Waiting for approval in Spare's panel. Press Control-C to withdraw the request.`
- `quit-timeout` exits 4 with `{"outcome":"timed-out"}` after `--timeout N`, and withdraws the request from the panel.
- `quit-withdraw` exits 4 with `cancelled` on Control-C.
- `quit-approve` exits 0 with `approved` after the person approves, and waits for the processes to exit.
- `quit-decline` exits 4 with `declined`.
- `quit-not-running` fails with `Spare isn't running, so there's no one to approve this.` when no app is up.
- `quit-not-allowed` refuses macOS processes Spare never stops.

## How to get to it (user POV)

- Run `spare quit <name|id|pid|port>` (agents do this per the README's agent prompt).
- The request appears in the panel; the person picks the action button (`Quit` for apps, `Stop` for projects and agents) or declines.

## Driving it with spare-verify

Preconditions:

- Doctor is all `ok`.
- A fixture is running: `port=$($V fixture-server verify-quit-fixture)`, then wait 3s.

- **Request reaches the app and times out.** Run `$V cli quit $port --timeout 6 --json`. Exit 4; stderr has `Waiting for approval`; stdout JSON `outcome` is `timed-out`.
- **Nothing was closed.** Run `$V cli list --projects --json --limit 0`; an object still has `$port` in `ports`. Run `curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:$port/`; it returns `200`.
- **Not allowed.** Run `$V cli quit WindowServer`. Exit 1, message `Spare doesn't close`.
- **Approve and decline.** Need a click in the panel: verified-unreachable without Accessibility for the terminal (see [panel.md](./panel.md)). With it, approve only the fixture, then confirm `outcome` `approved`, exit 0, and the port no longer answers.

## Gotchas

- Proven 2026-10-14: timed-out path, exit 4, fixture still serving.
- Without the `waiting` note on stderr, the request never reached an app. If the CLI says `Spare didn't respond` after 5s, an old (<0.14) or wrong instance is running; run doctor.
- If the person's own Spare were also running, both would get the request. Doctor's "no other Spare instance" check guards this.
