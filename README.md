# Spare

A little breathing room for your Mac.

Spare is a native macOS menu bar app that turns resource readings into recognizable apps, projects, and explanations. It helps you decide what to close before your Mac becomes uncomfortable to use.

## MVP

- Live CPU, memory pressure, estimated memory usage, and short resource histories.
- Apps grouped with their helpers; recognized development tools grouped by working folder or project.
- Recognition for common local AI tools, including Claude, Codex, Ollama, Aider, and OpenCode.
- Search and sorting by memory or CPU; unidentified background processes are available separately.
- Explanations of what an app or project does and what closing it affects.
- Listening TCP ports for recognized development processes.
- Reviewed, graceful app quit and development-process stop requests. No automatic cleanup or force killing.
- Menu bar warning indicator; optional notifications after about a minute of sustained pressure, with a ten-minute cooldown.

## Run locally

Requires macOS 14 or later and full Xcode at `/Applications/Xcode.app`. Built and tested on Apple silicon; Intel has not been tested.

```sh
make app
open dist/Spare.app
```

Click the leaf in the menu bar to open Spare. The menu at the top right offers pressure notifications and Quit Spare. Notifications are off until you enable them. The app starts monitoring immediately and does not change login settings.

For a standalone inspection window:

```sh
open dist/Spare.app --args --window
```

Quit an already running copy first when changing launch arguments. For a read-only system snapshot:

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

Spare reads processes belonging to your user. System totals include other users and macOS. Ownership is inferred from app bundle paths and parent processes. Development project names come from the working directory and nearby project manifests; multiple sessions for one project may appear together. Review the process list before stopping a group. Agent detection is heuristic; tools running behind generic runtimes may appear as development tasks.

Quit requests can be refused or delayed by an app. Development stop sends SIGTERM to the reviewed process identities after rechecking ownership and start time; it does not kill a whole process group or newly created children. A supervisor may restart a stopped service. Unknown background tasks have no stop button. Low CPU never means an agent is finished.

## Privacy and limits

All monitoring stays on your Mac. No account, telemetry, cloud service, network requests, command-line arguments, environment variables, or tab contents are collected. The last 15 minutes of system samples are held in memory only. Notification preference is saved locally.

This MVP cannot identify individual browser tabs, inspect Docker containers, measure per-app power consumption, predict every freeze, or fix system-level contention. It reports sustained CPU load and memory pressure rather than claiming a diagnosis. Login launch, signed updates, and richer attribution are future work.

## License

MIT. Commercial use and hosted products are permitted. Future services can be developed separately; already-published MIT code remains available under that license.
