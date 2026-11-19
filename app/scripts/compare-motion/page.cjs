// Spec 006 M2: runs the page's own script (snuffler-hanging.html) against a fake clock and prints, for every
// 60 Hz step of a fixed scenario, the uniforms it would have drawn. main.swift prints the same from SnufflerMotion.
// See run.sh. Node 18+, no packages.
const fs = require('fs');
const html = fs.readFileSync(process.argv[2], 'utf8');
const script = html.slice(html.lastIndexOf('<script>') + 8, html.lastIndexOf('</script>'));
const scenario = JSON.parse(fs.readFileSync(process.argv[3], 'utf8'));

let clock = 100, timeouts = [], nextId = 1, raf = [], posts = [], drawn = null;
const classes = new Set(['hidden']);
const stage = {
  get className() { return [...classes].join(' '); },
  set className(v) { classes.clear(); v.split(' ').filter(Boolean).forEach(c => classes.add(c)); },
  classList: { add: c => classes.add(c), remove: c => classes.delete(c), contains: c => classes.has(c),
               toggle: (c, on) => { if (on) classes.add(c); else classes.delete(c); } }
};
const gl = new Proxy({}, { get: (_, name) => {
  if (name === 'getShaderParameter' || name === 'getProgramParameter') return () => true;
  if (name === 'getUniformLocation') return (p, n) => n;
  if (name === 'uniform1f') return (loc, v) => { drawn[loc] = v; };
  if (name === 'uniform2f') return () => { drawn = {}; };
  return () => ({});
} });
const els = { stage, hit: { setAttribute() {}, addEventListener() {}, setPointerCapture() {} },
              gl: { getContext: () => gl }, fs: { textContent: '' } };
const window = { devicePixelRatio: 2 };
const math = Object.create(Math); math.random = () => 0.5;
new Function('window', 'document', 'performance', 'setTimeout', 'clearTimeout', 'requestAnimationFrame', 'console', 'Math', script)(
  window, { getElementById: id => els[id] }, { now: () => clock * 1000 },
  (fn, ms) => { timeouts.push({ id: nextId, at: clock + ms / 1000, fn }); return nextId++; },
  id => { timeouts = timeouts.filter(t => t.id !== id); },
  fn => raf.push(fn),
  { log: (tag, m) => posts.push(m.type) }, math);

const names = ['uYaw','uSwing','uSignSwing','uSignYaw','uBlink','uKick','uTail','uSniff','uFail','uBreathe','uRaiseR','uRaiseL','uShakeR','uShakeL','uTired','uBody','uGrip'];
const h = window.hangabout;
for (let i = 0; i < scenario.steps; i++) {
  clock = 100 + i / 60; posts = []; drawn = null;
  for (const a of scenario.actions.filter(a => a.step === i)) {
    if (a.do === 'show') h.show(a.arg); else if (a.do === 'nudge') h.nudge(a.arg); else if (a.do === 'swap') h.swapArms();
    else if (a.do === 'turn') h.turn(a.arg); else if (a.do === 'tired') h.setTired(a.arg); else if (a.do === 'idle') h.setIdle(a.arg);
    else if (a.do === 'reduced') h.setReducedMotion(a.arg); else if (a.do === 'climb') h.climb();
  }
  for (;;) {   // timers that have come due, in order
    const due = timeouts.filter(t => t.at <= clock).sort((a, b) => a.at - b.at || a.id - b.id)[0];
    if (!due) break;
    timeouts = timeouts.filter(t => t !== due); due.fn();
  }
  const run = raf; raf = []; run.forEach(fn => fn());
  const st = classes.has('hidden') ? 'hidden' : classes.has('dropping') ? 'dropping' : classes.has('climbing') ? 'climbing' : 'hanging';
  console.log([i, st, posts.filter(p => p !== 'ready').join('+'), drawn ? names.map(n => drawn[n].toFixed(6)).join(',') : 'still'].join(';'));
}
