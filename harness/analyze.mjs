// Summarise logs/events.jsonl as Markdown for results/run-<date>.md
// Each `npm run mark -- <id>` starts a new run of that scenario.

import { readFileSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const LOG_FILE = join(ROOT, "logs", "events.jsonl");

if (!existsSync(LOG_FILE)) {
  console.error("No log yet. Run the listener and some scenarios first.");
  process.exit(1);
}

const lines = readFileSync(LOG_FILE, "utf8").split("\n").filter(Boolean).map((l) => {
  try { return JSON.parse(l); } catch { return null; }
}).filter(Boolean);

// ---- split into runs ----
const runs = [];
let run = null;
for (const l of lines) {
  if (l.type === "mark") {
    run = { scenario: l.scenario || "untagged", startMs: l.receivedAtMs, events: [] };
    runs.push(run);
  } else if (l.type === "event") {
    if (!run) { run = { scenario: "untagged", startMs: l.receivedAtMs, events: [] }; runs.push(run); }
    run.events.push(l);
  }
}

const isNotif = (e, type) => e.event === "Notification" && e.payload?.notification_type === type;
const fmtMs = (ms) => (ms == null ? "–" : ms < 1000 ? `${ms} ms` : `${(ms / 1000).toFixed(1)} s`);

function compress(events) {
  const out = [];
  for (const e of events) {
    const name = e.event === "Notification" ? `Notification(${e.payload?.notification_type ?? "?"})` : e.event;
    const last = out[out.length - 1];
    if (last && last.name === name) last.n++;
    else out.push({ name, n: 1 });
  }
  return out.map((x) => (x.n > 1 ? `${x.name}×${x.n}` : x.name)).join(" → ") || "(no events)";
}

function runFacts(r) {
  const ev = r.events;
  const stop = ev.find((e) => e.event === "Stop");
  const idle = ev.find((e) => isNotif(e, "idle_prompt"));
  const perm = ev.find((e) => e.event === "PermissionRequest");
  const notifPerm = ev.find((e) => isNotif(e, "permission_prompt"));
  return {
    permissionRequest: !!perm,
    notificationPermission: !!notifPerm,
    notifDelayAfterPermReq: perm && notifPerm ? notifPerm.receivedAtMs - perm.receivedAtMs : null,
    stop: !!stop,
    idlePrompt: !!idle,
    idleGap: stop && idle ? idle.receivedAtMs - stop.receivedAtMs : null,
    sessions: new Set(ev.map((e) => e.payload?.session_id).filter(Boolean)).size,
    frontApps: [...new Set(ev.map((e) => e.frontApp).filter(Boolean))].join(", ") || "–",
  };
}

// ---- output ----
const yn = (b) => (b ? "yes" : "**no**");
let md = `# Spec 001 results\n\nGenerated ${new Date().toISOString()} from ${lines.length} log lines, ${runs.length} runs.\n\n`;

md += `## Runs\n\n| Scenario | Run | PermissionRequest | Notification (permission) | Stop | idle_prompt | Stop → idle | Sessions | Front app at events |\n|---|---|---|---|---|---|---|---|---|\n`;
const runNo = {};
for (const r of runs) {
  runNo[r.scenario] = (runNo[r.scenario] || 0) + 1;
  const f = runFacts(r);
  md += `| ${r.scenario} | ${runNo[r.scenario]} | ${yn(f.permissionRequest)} | ${yn(f.notificationPermission)} | ${yn(f.stop)} | ${yn(f.idlePrompt)} | ${fmtMs(f.idleGap)} | ${f.sessions} | ${f.frontApps} |\n`;
}

md += `\n## Event order per run\n\n`;
const runNo2 = {};
for (const r of runs) {
  runNo2[r.scenario] = (runNo2[r.scenario] || 0) + 1;
  md += `- **${r.scenario} #${runNo2[r.scenario]}:** ${compress(r.events)}\n`;
}

// Payload fields per event type
const fields = {};
let total = 0, routable = 0;
for (const r of runs) for (const e of r.events) {
  total++;
  if (e.payload?.session_id && e.payload?.cwd) routable++;
  const key = e.event === "Notification" ? `Notification(${e.payload?.notification_type ?? "?"})` : e.event;
  fields[key] ??= new Set();
  Object.keys(e.payload || {}).forEach((k) => fields[key].add(k));
}
md += `\n## Payload fields seen\n\n| Event | Fields |\n|---|---|\n`;
for (const [k, v] of Object.entries(fields).sort()) md += `| ${k} | ${[...v].sort().join(", ")} |\n`;

md += `\n## Routing check\n\n${routable} of ${total} events carry both \`session_id\` and \`cwd\`${total && routable === total ? ". **Pass.**" : ". **Check the events without them.**"}\n`;

// Scenario summary for the decision table
md += `\n## Summary by scenario\n\n| Scenario | Runs | PermissionRequest | Notification (permission) | Stop |\n|---|---|---|---|---|\n`;
const by = {};
for (const r of runs) {
  const f = runFacts(r);
  const s = (by[r.scenario] ??= { runs: 0, pr: 0, np: 0, st: 0 });
  s.runs++; s.pr += f.permissionRequest; s.np += f.notificationPermission; s.st += f.stop;
}
for (const [s, v] of Object.entries(by).sort()) md += `| ${s} | ${v.runs} | ${v.pr}/${v.runs} | ${v.np}/${v.runs} | ${v.st}/${v.runs} |\n`;

console.log(md);
