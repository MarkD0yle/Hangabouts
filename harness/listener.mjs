// Local listener for Claude Code hook events (Spec 001).
// Receives POST /hooks/<EventName> from the sandbox's http hooks and
// appends one JSON line per event to logs/events.jsonl.
// No dependencies. Node 18+.

import http from "node:http";
import { appendFileSync, mkdirSync, readFileSync, writeFileSync, existsSync } from "node:fs";
import { execFile } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const LOG_DIR = join(ROOT, "logs");
const LOG_FILE = join(LOG_DIR, "events.jsonl");
const SCENARIO_FILE = join(LOG_DIR, "current-scenario");
const PORT = Number(process.env.BESTIARY_PORT || 7777);
const HOST = "127.0.0.1"; // local only, never exposed to the network

mkdirSync(LOG_DIR, { recursive: true });

function currentScenario() {
  return existsSync(SCENARIO_FILE) ? readFileSync(SCENARIO_FILE, "utf8").trim() : "untagged";
}

// Which app is in front when the event arrives. Helps explain the "away" rule.
// macOS only; returns null elsewhere. lsappinfo needs no extra permissions.
function frontApp() {
  return new Promise((resolve) => {
    if (process.platform !== "darwin") return resolve(null);
    execFile("/bin/sh", ["-c", "lsappinfo info -only name \"$(lsappinfo front)\""], { timeout: 500 }, (err, out) => {
      if (err) return resolve(null);
      const m = out.match(/"LSDisplayName"="([^"]*)"/);
      resolve(m ? m[1] : out.trim() || null);
    });
  });
}

const COLOURS = {
  Notification: "\x1b[44;97m", PermissionRequest: "\x1b[44;97m",
  Stop: "\x1b[42;30m", StopFailure: "\x1b[41;97m",
};

function readBody(req) {
  return new Promise((resolve, reject) => {
    let data = "";
    req.on("data", (c) => {
      data += c;
      if (data.length > 5_000_000) { reject(new Error("body too large")); req.destroy(); }
    });
    req.on("end", () => resolve(data));
    req.on("error", reject);
  });
}

const server = http.createServer(async (req, res) => {
  const receivedAtMs = Date.now();
  const url = new URL(req.url, `http://${HOST}`);

  // Tag the following events with a scenario id, e.g. POST /mark?s=A2
  if (url.pathname === "/mark") {
    const s = (url.searchParams.get("s") || "").replace(/[^A-Za-z0-9_-]/g, "");
    writeFileSync(SCENARIO_FILE, s || "untagged");
    appendFileSync(LOG_FILE, JSON.stringify({ type: "mark", scenario: s, receivedAt: new Date(receivedAtMs).toISOString(), receivedAtMs }) + "\n");
    console.log(`\n\x1b[1m── scenario ${s} ──\x1b[0m`);
    res.writeHead(200, { "content-type": "application/json" }).end("{}");
    return;
  }

  const m = url.pathname.match(/^\/hooks\/([A-Za-z]+)$/);
  if (req.method !== "POST" || !m) {
    res.writeHead(404).end();
    return;
  }

  const event = m[1];
  let payload = null;
  try {
    const raw = await readBody(req);
    payload = raw ? JSON.parse(raw) : null;
  } catch {
    payload = { _unparsed: true };
  }

  // Answer first with an empty object: no decision, so Claude Code behaves
  // exactly as it would without the hook (important for PermissionRequest).
  res.writeHead(200, { "content-type": "application/json" }).end("{}");

  const app = await frontApp();
  const line = {
    type: "event",
    scenario: currentScenario(),
    event,
    receivedAt: new Date(receivedAtMs).toISOString(),
    receivedAtMs,
    frontApp: app,
    payload,
  };
  appendFileSync(LOG_FILE, JSON.stringify(line) + "\n");

  const sub = payload?.notification_type || payload?.tool_name || "";
  const sess = String(payload?.session_id || "").slice(0, 8);
  const col = COLOURS[event] || "\x1b[2m";
  console.log(`${new Date(receivedAtMs).toLocaleTimeString()}  ${col} ${event} \x1b[0m ${sub}  session:${sess}  front:${app ?? "?"}`);
  if (event === "Notification" || event === "PermissionRequest") process.stdout.write("\x07");
});

server.listen(PORT, HOST, () => {
  console.log(`Bestiary listener on http://${HOST}:${PORT}  →  ${LOG_FILE}`);
  console.log(`Current scenario: ${currentScenario()}  (change with: npm run mark -- A2)`);
});
