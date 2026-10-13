# How Spare works

The details behind Spare's readings, recaps, and limits. For installing and getting started, see the [README](../README.md).

## Readings

Process CPU counters are converted from Mach time units to nanoseconds before calculating percentages. Version 0.7 corrects earlier under-reporting on Apple silicon and migrates any locally saved version-1 recap CPU totals. CPU percentages use the capacity of your whole Mac, so they differ from Activity Monitor's per-core process percentages. The first measurement needs a second sample. Memory pressure comes from macOS; high RAM or swap usage alone does not trigger a warning. System used memory is an estimate; process physical footprints can overlap and won't sum to the system total. The memory sparkline shows estimated usage, not historical pressure.

Spare reads processes belonging to your user. System totals include other users and macOS. Ownership is inferred from app bundle paths and parent processes. Development project names come from the working directory and nearby project manifests; multiple sessions for one project appear together. Open the project to review an individual session, or review the whole group. Session boundaries are inferred from visible parent processes; if a parent exits, its remaining tools may appear as a new session. Review the process list before stopping anything. Agent detection is heuristic; tools running behind generic runtimes may appear as development tasks.

Quit requests can be refused or delayed by an app. Development stop sends SIGTERM to the reviewed process identities after rechecking ownership and start time; it does not kill a whole process group or newly created children. A supervisor may restart a stopped service. Spare checks accepted stop requests against subsequent process readings, reports when those identities are no longer detected, and reports remaining processes after 15 seconds. Disappearance from the readings is not proof of reclaimed memory or successful saving. Unknown background tasks have no stop button. Low CPU never means an agent is finished.

Growth highlights require at least 60 seconds of continuous readings and a net increase of both 256 MB and 25%. Growth may be normal. Charts use a labeled scale and reset after monitoring gaps, app restarts, or complete process replacement. Changes to the group’s helpers or sessions are disclosed. Trends are limited to 256 groups/sessions and 101 points each, prioritized by current memory use.

## Recaps

Recaps retain up to 30 days of compact hourly summaries. CPU averages are time-weighted; “CPU above 85%” measures observed busy time, not necessarily a problem. Memory pressure time uses macOS warning/critical readings; unavailable pressure is shown separately. Charts show recorded hourly averages today or daily averages this week; orange bars mark periods that included elevated memory pressure. The local calendar determines day and week boundaries, including daylight-saving changes. Last 7 days includes today and the preceding six calendar days; its comparison uses the seven calendar days immediately before that range.

Rankings combine top-level apps/projects/agents with their helpers, without also counting nested sessions. Their averages use all recorded time as the denominator, including time when a workload was absent. Seen/running time does not measure active use. At most 128 workload summaries are retained per hour, so smaller tasks may be omitted. Contributor names describe measured use, not the cause of a slowdown.

Comparisons use average CPU and the proportion of known memory-pressure readings, with recorded duration shown for each period. They appear after both periods have at least a minute of coverage. Explicit sleep/wake notifications reset the sampler and history baselines, including for short sleeps. Sleep, pauses, restarts, and sample gaps over ten seconds are unobserved, never filled as idle time. There is no backfill. Retention is enforced while Spare runs; if it is closed for over 30 days, old summaries are pruned the next time it runs.

## While you were away

After five minutes without keyboard or mouse input, Spare begins a temporary away summary while history recording is enabled. When input resumes, at least a minute of observed readings produces a return card in the overview and Recap window. It shows recorded and unobserved time, memory-pressure time, the largest recorded users, and which groups are detected now. The first five idle minutes are excluded. Running now does not establish that it is the same session, or that an agent completed productive work.

This uses only macOS’s elapsed-input-idle counter, never keystrokes or mouse contents. Away summaries remain in memory for up to 18 hours; dismissing, pausing history, clearing history, or quitting removes them. Ordinary hourly resource summaries retain the existing 30-day local policy. CSV exports include display names and hourly measurements, but no raw process paths or commands. Names are quoted and spreadsheet formulas neutralized.

## Grouping and labels

Spare groups each app with its helper processes by bundle path and parent process. Inside an app, helpers are labeled by role from their launch arguments: Chromium and Electron helpers declare `--type=renderer`, `gpu-process`, or `utility`, and WebKit helpers are recognized by name. Another process running the app's own executable without `--type` is shown as a separate session, and Spare walks its parent processes to report what opened it.

Development rows summarize the distinct commands in a project folder, servers with listening ports first. Package runners such as `npm exec` and `npx` and version suffixes are removed, and `key=value` arguments are never shown.

Known macOS processes are labeled only when they run from Apple's system locations (`/System`, `/usr/libexec`, `/usr/sbin`, `/usr/bin`, `/sbin`), so a look-alike elsewhere stays unidentified. Spare never offers to stop them.

## Not used lately

Spare records when each app comes to the front. Apps that can quit, have been idle for two or more hours, and use at least 300 MB are marked. Idle time errs short: if Spare wasn't running for more than ten minutes before it launched, earlier activity isn't trusted, and relaunching an app resets its clock.

## The command line

`spare` takes its own reading each time it runs (two samples a second apart, for CPU) and groups processes with the same code as the panel, so names and totals match. `spare idle` reads the times Spare saved for when each app was last in front, and only trusts activity seen since the running Spare launched. `spare recap` reads the saved recap history without changing it. Leftover sessions are browser processes that run the browser itself rather than a helper, whose launcher has exited or runs detached in the background, such as an agent-browser daemon.

`spare quit` and `spare leftovers --close` don't close anything themselves. They send a request to the running app as a local distributed notification. The app looks the target up again in its own latest reading, shows the request in its panel with who asked (found from the command's parent processes, such as *Claude in website*), and acts only if you approve. Its reply says whether you approved, declined, or the request couldn't be shown. A request that gets no answer within the timeout (120 seconds by default), or that you withdraw with Control-C, is removed from the panel. Only one request is shown at a time. Any app on your Mac can post these notifications, but the worst one can do is ask you a question.

## Privacy, in full

All monitoring stays on your Mac. No account, telemetry, or cloud service is involved, and the only network request is Sparkle's update check. The `spare` command makes no network requests. Tab contents are never read. Command-line arguments of your own processes are read on your Mac to label helpers and summarize commands; they are shown in Spare but never saved or sent, and `key=value` arguments are left out of summaries. macOS returns a process's environment variables in the same buffer as its arguments; Spare discards that part without using it. Spare saves when each app was last in front, to find apps you haven't used lately; clearing saved history clears it too. Accessibility permission is requested only when you ask Spare to open Chrome's Task Manager. The last 15 minutes of system samples and up to 80 recent activity entries are held in memory only. Activity entries retain at most three contributor names and their resource totals. They expire after 15 minutes, disappear when Spare quits, and can be cleared with the timeline’s Clear button. Memory trends are also held only in memory, for up to five minutes, and discarded when a tracked workload disappears. Recap history is saved locally at `~/Library/Application Support/Spare/recaps.json`, with user-only file permissions. It contains hourly totals, app/project display names, workload kinds, and hashed grouping identifiers; it does not persist executable paths, process lists, or individual sessions. Saving is enabled by default and can be paused. **Clear saved history** removes all saved recap summaries after confirmation. Preferences are saved locally. History is written at most once per minute during monitoring and on a normal quit; a crash may lose the last minute. Read/write failures are shown in the recap view; an unreadable archive is preserved until you explicitly clear it.

Spare cannot tell which tab or site a browser process runs (Chrome's own Task Manager can), inspect Docker containers, measure per-app power consumption, predict every freeze, or fix system-level contention. It reports sustained CPU load and memory pressure rather than claiming a diagnosis. Richer attribution is future work. Review suggestions identify measured resource use; they do not prove that a workload is causing a slowdown or that it is safe to interrupt.
