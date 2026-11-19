#!/usr/bin/env bash
# Spec 006: checks SnufflerMotion.swift against the old page's own JavaScript (design/snuffler-hanging.html),
# step by step, on a fake clock. Needs Node 18+ and swiftc. Only useful while the motion is meant to match the page.
set -euo pipefail
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HERE="$APP_DIR/scripts/compare-motion"
TMP="$(mktemp -d)"
node "$HERE/page.cjs" "$APP_DIR/../design/snuffler-hanging.html" "$HERE/scenario.json" > "$TMP/page.txt"
swiftc -O -swift-version 5 "$HERE/main.swift" "$APP_DIR/Sources/Hangabouts/SnufflerMotion.swift" "$APP_DIR/Sources/Hangabouts/SnufflerUniforms.swift" -o "$TMP/motion"
"$TMP/motion" "$HERE/scenario.json" > "$TMP/swift.txt"
node - "$TMP/page.txt" "$TMP/swift.txt" <<'JS'
const fs = require('fs');
const [a, b] = [2, 3].map(i => fs.readFileSync(process.argv[i], 'utf8').trim().split('\n').map(l => l.split(';')));
let worst = 0, worstAt = '', frames = 0, bad = [];
a.forEach((p, i) => {
  const s = b[i];
  // While he is hidden the page may draw a frame or two the app never shows; only compare what can be seen.
  const seen = p[1] !== 'hidden' || s[1] !== 'hidden';
  if (p[1] !== s[1] || p[2] !== s[2]) bad.push(`step ${i}: page ${p[1]} ${p[2]} / swift ${s[1]} ${s[2]}`);
  if (!seen) return;
  if ((p[3] === 'still') !== (s[3] === 'still')) { bad.push(`step ${i}: page ${p[3] === 'still' ? 'still' : 'drew'} / swift ${s[3] === 'still' ? 'still' : 'drew'}`); return; }
  if (p[3] === 'still') return;
  frames++;
  const x = p[3].split(',').map(Number), y = s[3].split(',').map(Number);
  x.forEach((v, k) => { const d = Math.abs(v - y[k]); if (d > worst) { worst = d; worstAt = `step ${i}, uniform ${k}`; } });
});
console.log(`${a.length} steps, ${frames} drawn frames compared`);
console.log(`largest difference in any uniform: ${worst.toExponential(2)} (${worstAt})`);
console.log(bad.length ? `MISMATCHES (${bad.length}):\n  ` + bad.slice(0, 15).join('\n  ') : 'stages, shown/climbed and drawn-or-still agree at every step');
process.exit(bad.length || worst > 1e-4 ? 1 : 0);
JS
