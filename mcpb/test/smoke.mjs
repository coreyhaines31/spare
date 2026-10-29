// Starts the built server over stdio, calls every tool against this Mac, and fails
// if a call that should work errors or a call that should fail doesn't.
// Run: npm test. SERVER=<path> runs an unpacked .mcpb instead of server/index.mjs.
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

const ok = true;
const fails = false;
const calls = [
  ["spare_status", {}, ok],
  ["spare_list", { limit: 3 }, ok],
  ["spare_list", { kind: "agents", sort: "cpu", limit: 2 }, ok],
  ["spare_show", { name: "Finder" }, ok],
  ["spare_show", { name: "--json" }, fails],
  ["spare_show", { name: "nothing-called-this" }, fails],
  ["spare_idle", {}, ok],
  ["spare_strays", {}, ok],
  ["spare_leftovers", {}, ok],
  ["spare_recap", { period: "week" }, ok],
];
const failures = [];

const transport = new StdioClientTransport({
  command: process.execPath,
  args: [process.env.SERVER ?? new URL("../server/index.mjs", import.meta.url).pathname],
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
for (const [name, args, shouldWork] of calls) {
  const label = `${name} ${JSON.stringify(args)}`;
  let result;
  try {
    result = await client.callTool({ name, arguments: args });
  } catch (error) {
    result = { isError: true, content: [{ type: "text", text: `protocol error: ${error.message}` }] };
  }
  const text = result.content.map((c) => c.text).join("\n");
  const shown = text.length > max ? `${text.slice(0, max)}\n… (${text.length} chars)` : text;
  console.log(`\n### ${label}${result.isError ? " [isError]" : ""}\n${shown}`);
  if (Boolean(result.isError) === shouldWork) failures.push(label);
  if (shouldWork && !result.isError) JSON.parse(text);
}
await client.close();

if (failures.length) {
  console.error(`\nFAILED: ${failures.join("; ")}`);
  process.exit(1);
}
console.log(`\nAll ${calls.length} calls behaved as expected.`);
