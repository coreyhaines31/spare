# List and show

`spare list` groups everything using resources into things a person recognizes (apps with their helpers, projects by folder with port, AI agents by working folder, labeled macOS processes) and sorts them, largest first. `spare show <name>` explains one item: what it is, what closing it affects, and the processes inside.

## Sub-features

- `list-default` prints a table `NAME KIND MEMORY CPU DETAILS`, 15 rows, plus a `N more` footer.
- `list-filter` limits to `--apps`, `--projects`, or `--agents`.
- `list-sort` sorts by `--sort cpu`; `--limit N` and `--limit 0` for everything.
- `list-json` returns objects with `id`, `kind` (`app`, `project`, `agent`, macOS), `name`, `memory_bytes`, `cpu_percent`, `ports`, `process_count`, `project_path`, `can_quit`, `subtitle`.
- `show-detail` prints name, kind line, explanation, `If you close it:` consequence, and a PID table; projects add `Folder:` and `Open: http://localhost:<port>`.
- `show-missing` exits 1 with `Nothing called "<name>" is running.`

## How to get to it (user POV)

- Run `spare list [options]` and `spare show <name|id|pid|port>`.
- In the panel, the main list and a row's detail view (see [panel.md](./panel.md)).

## Driving it with spare-verify

Preconditions:

- Doctor is all `ok`.
- A fixture is running: `port=$($V fixture-server verify-list-fixture)`.

- **Grouped list.** Run `$V cli list --limit 5`. Exit 0; header row as in `list-default`; a footer `more. Use --limit 0 to show everything.`
- **Project grouping.** Run `$V cli list --projects --json --limit 0`. One object has `ports` containing `$port`, `kind` `project`, `name` `verify-list-fixture`, and `project_path` ending in `spare-verify-fixtures/verify-list-fixture`.
- **Filters.** Run `$V cli list --agents --json --limit 0`. Every object has `kind` `agent`.
- **Sort.** Run `$V cli list --sort cpu --json --limit 0`. `cpu_percent` is non-increasing.
- **Show by port.** Run `$V cli show $port`. Exit 0; stdout names `verify-list-fixture`, the `Project ·` line has `port $port`, and there are `Folder:` and `Open: http://localhost:$port` lines and one `Python` process row.
- **Not found.** Run `$V cli show zzz-not-running`. Exit 1, message `Nothing called`.

## Gotchas

- A fixture started inside a git checkout is grouped with that whole repo (`id` `development:<repo>`), not its own folder. Always use `fixture-server`.
- The person's workload changes between calls; never assert specific third-party apps or counts.
- Spare may take one sampling interval (a few seconds) to list a brand-new process. Wait about 3s after `fixture-server`.
