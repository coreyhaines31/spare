// Starts the built server over stdio and calls every tool against this Mac.
// Run: npm test. SERVER=<path> runs an unpacked .mcpb instead of server/index.js.
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

const calls = [
  ["spare_status", {}],
  ["spare_list", { limit: 3 }],
  ["spare_list", { kind: "agents", sort: "cpu", limit: 2 }],
  ["spare_show", { name: "Finder" }],
  ["spare_show", { name: "--json" }],
  ["spare_show", { name: "nothing-called-this" }],
  ["spare_idle", {}],
  ["spare_strays", {}],
  ["spare_leftovers", {}],
  ["spare_recap", { period: "week" }],
];

const transport = new StdioClientTransport({
  command: process.execPath,
  args: [process.env.SERVER ?? new URL("../server/index.js", import.meta.url).pathname],
  env: { ...process.env, SPARE_CLI: process.env.SPARE_CLI ?? "" },
});
const client = new Client({ name: "spare-smoke", version: "0.0.0" });
await client.connect(transport);

const { tools } = await client.listTools();
console.log(`tools: ${tools.map((t) => t.name).join(", ")}`);
for (const tool of tools) {
  if (!tool.annotations?.readOnlyHint || tool.annotations?.destructiveHint !== false) {
    throw new Error(`${tool.name} is not annotated read-only`);
  }
}

const max = Number(process.env.SMOKE_CHARS ?? 600);
for (const [name, args] of calls) {
  let result;
  try {
    result = await client.callTool({ name, arguments: args });
  } catch (error) {
    console.log(`\n### ${name} ${JSON.stringify(args)} -> protocol error: ${error.message}`);
    continue;
  }
  const text = result.content.map((c) => c.text).join("\n");
  const shown = text.length > max ? `${text.slice(0, max)}\n… (${text.length} chars)` : text;
  console.log(`\n### ${name} ${JSON.stringify(args)}${result.isError ? " [isError]" : ""}\n${shown}`);
}
await client.close();
