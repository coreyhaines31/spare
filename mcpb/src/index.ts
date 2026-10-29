import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { runSpare } from "./cli.js";

const VERSION = "0.1.0";

const server = new McpServer(
  { name: "spare", version: VERSION },
  {
    instructions:
      "Spare reports what is using this Mac's CPU and memory: apps, projects, AI agents, macOS tasks, " +
      "and processes agents left running. It does not measure disk space. These tools only read; " +
      "quitting or stopping anything is done by the person in the Spare app.",
  },
);

const readOnly = {
  readOnlyHint: true,
  destructiveHint: false,
  idempotentHint: true,
  openWorldHint: false,
} as const;

async function respond(args: string[]) {
  const result = await runSpare(args);
  return {
    content: [{ type: "text" as const, text: result.text }],
    ...(result.ok ? {} : { isError: true }),
  };
}

// Names, ids, PIDs, and ports from Spare's own output. Leading "-" is refused so a
// value can never be read as a flag.
const target = z
  .string()
  .trim()
  .min(1)
  .max(300)
  .regex(/^[^-]/, "Must not start with '-'")
  .regex(/^[^\u0000-\u001f]*$/, "Must not contain control characters");

server.registerTool(
  "spare_status",
  {
    title: "Mac CPU and memory status",
    description:
      "CPU use, memory used/total, swap, and memory pressure (normal, warning, critical) right now, with a one-line verdict. " +
      "Start here for 'is my Mac struggling?'. For what is using the resources, use spare_list.",
    inputSchema: {},
    annotations: { ...readOnly, title: "Mac CPU and memory status" },
  },
  async () => respond(["status"]),
);

server.registerTool(
  "spare_list",
  {
    title: "What's using this Mac",
    description:
      "Apps, projects (dev servers, builds), and AI agents using the most memory or CPU, largest first. " +
      "Each row has a name, id, memory, CPU %, process count, and ports. Pass a name or id to spare_show for details. " +
      "Does not cover disk space.",
    inputSchema: {
      kind: z
        .enum(["all", "apps", "projects", "agents"])
        .default("all")
        .describe("Only show one kind. 'all' includes macOS system tasks too."),
      sort: z.enum(["memory", "cpu"]).default("memory").describe("Sort by memory (default) or CPU."),
      limit: z.number().int().min(1).max(100).default(15).describe("Rows to return, 1-100."),
    },
    annotations: { ...readOnly, title: "What's using this Mac" },
  },
  async ({ kind, sort, limit }) => {
    const args = ["list", "--limit", String(limit)];
    if (kind !== "all") args.push(`--${kind}`);
    if (sort === "cpu") args.push("--sort", "cpu");
    return respond(args);
  },
);

server.registerTool(
  "spare_show",
  {
    title: "Details for one app, project, or agent",
    description:
      "What one item is, what closing it would affect, and its processes. Accepts a name from spare_list (any case; " +
      "a unique prefix works), an id from spare_list, a process ID, or a port number. If the name is ambiguous, " +
      "the error lists the matching ids to retry with.",
    inputSchema: {
      name: target.describe("Name, id, PID, or port, e.g. 'Google Chrome', 'app:/Applications/Slack.app', '4312', or '3000'."),
    },
    annotations: { ...readOnly, title: "Details for one app, project, or agent" },
  },
  async ({ name }) => respond(["show", name]),
);

server.registerTool(
  "spare_idle",
  {
    title: "Apps left open but unused",
    description:
      "Apps that have been open but unused for 2+ hours, with how long and how much memory each holds. " +
      "Needs the Spare app to be running (it tracks when apps were last used).",
    inputSchema: {},
    annotations: { ...readOnly, title: "Apps left open but unused" },
  },
  async () => respond(["idle"]),
);

server.registerTool(
  "spare_strays",
  {
    title: "Processes agents left running",
    description:
      "Headless browsers, MCP servers, tunnels, file servers, and old dev servers that AI agents started and nothing owns anymore. " +
      "Rows with held_by still belong to a live agent session; rows without it are strays. For browser windows " +
      "left open by automation, use spare_leftovers.",
    inputSchema: {
      name: target.optional().describe("Only show strays whose name matches, e.g. 'agent-browser'."),
    },
    annotations: { ...readOnly, title: "Processes agents left running" },
  },
  async ({ name }) => respond(name ? ["strays", name] : ["strays"]),
);

server.registerTool(
  "spare_leftovers",
  {
    title: "Browser sessions left open by automation",
    description:
      "Browser processes that automation tools and agents (Playwright, agent-browser, Puppeteer) left open, with memory and origin. " +
      "For other background processes agents left behind, use spare_strays.",
    inputSchema: {
      app: target.optional().describe("Only one browser, e.g. 'Google Chrome for Testing'."),
    },
    annotations: { ...readOnly, title: "Browser sessions left open by automation" },
  },
  async ({ app }) => respond(app ? ["leftovers", app] : ["leftovers"]),
);

server.registerTool(
  "spare_recap",
  {
    title: "CPU and memory history",
    description:
      "Saved history from the Spare app: average and peak CPU, how long memory pressure was elevated, and the top apps " +
      "by CPU and memory. Use for 'why was my Mac slow earlier / this week?'.",
    inputSchema: {
      period: z
        .enum(["today", "week", "7d"])
        .default("today")
        .describe("'today', 'week' (since the start of this week), or '7d' (last 7 days)."),
    },
    annotations: { ...readOnly, title: "CPU and memory history" },
  },
  async ({ period }) => respond(["recap", period]),
);

await server.connect(new StdioServerTransport());
