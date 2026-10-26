import AppKit
import SpareCore

let help = """
spare: see what's using this Mac and what's safe to close.

Usage: spare <command> [options]

Commands:
  status             CPU, memory, and memory pressure right now
  list               Apps, projects, and AI agents using the most, largest first
  show <name>        What something is, what closing it affects, and its processes
  idle               Apps left open but unused for 2+ hours (needs Spare running)
  leftovers [app]    Browser sessions left open by automation tools and agents
  strays [name]      Headless browsers, MCP servers, tunnels, and old dev servers
                     that agents left running and nothing owns anymore
  recap [period]     Saved history: today (default), week, or 7d
  quit <name>        Ask to quit an app or stop a project or agent
  open               Open Spare

Options:
  --json             Machine-readable output, for every command
  --apps, --projects, --agents
                     Only show that kind in `list`
  --sort cpu         Sort `list` by CPU instead of memory
  --limit N          Rows in `list` (default 15, 0 for all)
  --close            With `leftovers` or `strays`: ask to close them
  --timeout N        Seconds `quit` and `--close` wait for an answer (default 120)

<name> is a name from `spare list` (any case; the start of a name works when it's
unique), an id from --json output, a process ID, or a port.

Nothing closes without the person's approval. `quit` and `--close`
show the request in Spare's panel and wait for them to approve or decline it.
They need Spare running; every other command works on its own.

Exit codes: 0 success, 1 error or not found, 2 memory pressure is Warning (status),
3 memory pressure is Critical (status), 4 declined, timed out, or withdrawn.

More: https://github.com/coreyhaines31/spare#command-line
"""

struct Options {
    var command = ""
    var positional: [String] = []
    var filter = WorkloadFilter.all
    var sortCPU = false
    var limit = 15
    var close = false
    var timeout: TimeInterval = 120

    init(_ arguments: [String]) {
        var remaining = arguments[...]
        while let argument = remaining.popFirst() {
            switch argument {
            case "--json": Output.json = true
            case "--apps": filter = .apps
            case "--projects": filter = .projects
            case "--agents": filter = .agents
            case "--close": close = true
            case "--sort":
                switch remaining.popFirst() {
                case "cpu": sortCPU = true
                case "memory": sortCPU = false
                default: Output.fail("--sort takes cpu or memory.")
                }
            case "--limit":
                guard let value = remaining.popFirst().flatMap(Int.init), value >= 0 else { Output.fail("--limit takes a number, or 0 for all.") }
                limit = value
            case "--timeout":
                guard let value = remaining.popFirst().flatMap(Double.init), value > 0 else { Output.fail("--timeout takes a number of seconds.") }
                timeout = value
            case "-h", "--help": command = "help"
            case "-v", "--version": command = "version"
            default:
                if argument.hasPrefix("-") && Int(argument) == nil { Output.fail("Unknown option \(argument). Run `spare --help`.") }
                if command.isEmpty { command = argument } else { positional.append(argument) }
            }
        }
    }
}

func version() -> String {
    spareAppURL.flatMap { Bundle(url: $0)?.infoDictionary?["CFBundleShortVersionString"] as? String } ?? "development build"
}

func openSpare() {
    guard let url = spareAppURL else { Output.fail("Couldn’t find Spare.app. Download it from https://spareformac.com.") }
    let done = DispatchSemaphore(value: 0)
    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
        if let error { Output.fail("Couldn’t open Spare: \(error.localizedDescription)") }
        done.signal()
    }
    done.wait()
    print("Opened Spare. Look for the gauge icon in the menu bar.")
}

let options = Options(Array(CommandLine.arguments.dropFirst()))
switch options.command {
case "", "help": print(help)
case "version": print("spare \(version())")
case "status": Commands.status()
case "list", "ls": Commands.list(options)
case "show":
    guard !options.positional.isEmpty else { Output.fail("Which one? Usage: spare show <name>") }
    Commands.show(options.positional.joined(separator: " "))
case "idle": Commands.idle()
case "leftovers": Commands.leftovers(options)
case "strays": Commands.strays(options)
case "recap": Commands.recap(options)
case "quit", "stop":
    guard !options.positional.isEmpty else { Output.fail("Which one? Usage: spare quit <name>") }
    Requests.quit(options.positional.joined(separator: " "), options: options)
case "open": openSpare()
default: Output.fail("Unknown command “\(options.command)”. Run `spare --help`.")
}
