// Tag the next events with a scenario id: npm run mark -- A2
const id = process.argv[2];
if (!id) {
  console.error("Usage: npm run mark -- <scenario-id>   e.g. A2");
  process.exit(1);
}
const port = Number(process.env.BESTIARY_PORT || 7777);
try {
  await fetch(`http://127.0.0.1:${port}/mark?s=${encodeURIComponent(id)}`, { method: "POST" });
  console.log(`Scenario set to ${id}`);
} catch {
  console.error("Listener not running. Start it first: npm run listen");
  process.exit(1);
}
