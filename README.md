# Spare

A little breathing room for your Mac.

Spare is a native macOS menu bar app that turns resource readings into recognizable apps, projects, and explanations. It helps you decide what to close before your Mac becomes uncomfortable to use.

## MVP

- Live CPU, memory pressure, estimated memory usage, and short resource histories.
- Five-minute memory charts for identified workloads and sessions, with a “Growing recently” card for notable increases.
- Daily and weekly recaps with CPU charts, elevated-pressure time, resource rankings, busiest hours, and previous-period comparisons.
- A recent-activity timeline with pressure changes, recoveries, monitoring gaps, and snapshots of the largest identified resource users.
- Apps grouped with their helpers; recognized development tools grouped by working folder or project.
- Recognition for common local AI tools, including Claude, Codex, Ollama, Aider, and OpenCode.
- Apps, Projects, and Agents filters; search by name, folder, or local port; sorting by memory or CPU.
- A specific review suggestion during elevated pressure, based on the largest visible resource user that Spare can help close.
- Agent-owned runtime processes stay with the agent; independent development servers remain separate.
- Explanations of what an app or project does and what closing it affects.
- Listening TCP ports for recognized development processes.
- Live detail readings, with a frozen process list when you begin reviewing a stop request.
- Individual agent and development sessions inside a project, inferred from parent relationships and distinguished by start time.
- Reviewed, graceful app quit and development-process stop requests, followed by feedback from subsequent readings. No automatic cleanup or force killing.
- Optional launch at login and a persistent window available from the menu.
- Menu bar warning indicator; optional notifications after about a minute of sustained pressure, with a ten-minute cooldown.

## Run locally

Requires macOS 14 or later and full Xcode at `/Applications/Xcode.app`. Built and tested on Apple silicon; Intel has not been tested.

```sh
make app
open dist/Spare.app
```

Click the leaf in the menu bar to open Spare. Use the clock button beside the menu to see recent activity. Timeline entries capture readings at that moment; **View current** opens the workload’s current readings for review. The Settings menu at the top right offers pressure notifications, unidentified background processes, and Quit Spare. The overview keeps search and filters above the app list; use Back to return from a session to its project, or from current readings to recent activity. Notifications are off until you enable them. The app starts monitoring immediately. Launch at login is off by default; enable it from the menu if wanted. If macOS requires approval, the menu links to Login Items in System Settings.

Use the chart button in the toolbar to open **Recap**, then choose **Today** or **This week**. History starts with this version; earlier activity cannot be recovered. The recap updates every 30 seconds. Save-history and clear-history controls are at the bottom of this view.

Memory history and technical details are collapsed in the detail view. Use **About these readings** in the footer for an explanation of CPU and memory measurements.

For a standalone inspection window:

```sh
open dist/Spare.app --args --window
```

You can also choose **Open in a window** from the menu, or open Spare again from Finder. Quit an already running copy first when changing launch arguments. For a read-only system snapshot:

```sh
dist/Spare.app/Contents/MacOS/Spare --snapshot
```

## Development

```sh
brew install swiftlint  # if needed
make lint
make test
make build
```

Swift Package Manager, SwiftUI, AppKit, and a small C module using macOS process APIs. There are no third-party runtime dependencies. `make` selects the full Xcode toolchain without changing your system selection. The build script creates an ad-hoc-signed local app. Distribution signing and notarization are not set up.

## How to interpret the readings

CPU percentages use the capacity of your whole Mac, so they differ from Activity Monitor's per-core process percentages. The first measurement needs a second sample. Memory pressure comes from macOS; high RAM or swap usage alone does not trigger a warning. System used memory is an estimate; process physical footprints can overlap and won't sum to the system total. The memory sparkline shows estimated usage, not historical pressure.

Spare reads processes belonging to your user. System totals include other users and macOS. Ownership is inferred from app bundle paths and parent processes. Development project names come from the working directory and nearby project manifests; multiple sessions for one project appear together. Open the project to review an individual session, or review the whole group. Session boundaries are inferred from visible parent processes; if a parent exits, its remaining tools may appear as a new session. Review the process list before stopping anything. Agent detection is heuristic; tools running behind generic runtimes may appear as development tasks.

Quit requests can be refused or delayed by an app. Development stop sends SIGTERM to the reviewed process identities after rechecking ownership and start time; it does not kill a whole process group or newly created children. A supervisor may restart a stopped service. Spare checks accepted stop requests against subsequent process readings, reports when those identities are no longer detected, and reports remaining processes after 15 seconds. Disappearance from the readings is not proof of reclaimed memory or successful saving. Unknown background tasks have no stop button. Low CPU never means an agent is finished.

Growth highlights require at least 60 seconds of continuous readings and a net increase of both 256 MB and 25%. Growth may be normal. Charts use a labeled scale and reset after monitoring gaps, app restarts, or complete process replacement. Changes to the group’s helpers or sessions are disclosed. Trends are limited to 256 groups/sessions and 101 points each, prioritized by current memory use.

## Daily and weekly recaps

Recaps retain up to 30 days of compact hourly summaries. CPU averages are time-weighted; “CPU above 85%” measures observed busy time, not necessarily a problem. Memory pressure time uses macOS warning/critical readings; unavailable pressure is shown separately. Charts show recorded hourly averages today or daily averages this week; orange bars mark periods that included elevated memory pressure. The local calendar determines day and week boundaries, including daylight-saving changes.

Rankings combine top-level apps/projects/agents with their helpers, without also counting nested sessions. Their averages use all recorded time as the denominator, including time when a workload was absent. Seen/running time does not measure active use. At most 128 workload summaries are retained per hour, so smaller tasks may be omitted. Contributor names describe measured use, not the cause of a slowdown.

Comparisons use average CPU and the proportion of known memory-pressure readings, with recorded duration shown for each period. They appear after both periods have at least a minute of coverage. Sleep, pauses, restarts, and sample gaps over ten seconds are unobserved, never filled as idle time. There is no backfill. Retention is enforced while Spare runs; if it is closed for over 30 days, old summaries are pruned the next time it runs.

## Privacy and limits

All monitoring stays on your Mac. No account, telemetry, cloud service, network requests, command-line arguments, environment variables, or tab contents are collected. The last 15 minutes of system samples and up to 80 recent activity entries are held in memory only. Activity entries retain at most three contributor names and their resource totals. They expire after 15 minutes, disappear when Spare quits, and can be cleared with the timeline’s Clear button. Memory trends are also held only in memory, for up to five minutes, and discarded when a tracked workload disappears. Recap history is saved locally at `~/Library/Application Support/Spare/recaps.json`, with user-only file permissions. It contains hourly totals, app/project display names, workload kinds, and hashed grouping identifiers; it does not persist executable paths, process lists, or individual sessions. Saving is enabled by default and can be paused. **Clear saved history** removes all saved recap summaries after confirmation. Preferences are saved locally. History is written at most once per minute during monitoring and on a normal quit; a crash may lose the last minute. Read/write failures are shown in the recap view; an unreadable archive is preserved until you explicitly clear it.

This MVP cannot identify individual browser tabs, inspect Docker containers, measure per-app power consumption, predict every freeze, or fix system-level contention. It reports sustained CPU load and memory pressure rather than claiming a diagnosis. Signed updates and richer attribution are future work. Review suggestions identify measured resource use; they do not prove that a workload is causing a slowdown or that it is safe to interrupt.

## License

MIT. Commercial use and hosted products are permitted. Future services can be developed separately; already-published MIT code remains available under that license.
