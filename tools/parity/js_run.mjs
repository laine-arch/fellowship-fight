// Runs the original web sim (extracted from web-legacy/src.html) on the shared input script and prints state dumps.
import fs from 'node:fs';
import { makeInputs } from './inputs.mjs';
const src = fs.readFileSync(new URL('../../web-legacy/src.html', import.meta.url), 'utf8');
const cut = (a, b) => { const i = src.indexOf(a), j = src.indexOf(b, i); return src.slice(i, j); };
const code = 'const W = 960;\n' + cut('const CHARS = [', 'const LOCKED_SLOTS') + "const charById = id => CHARS.find(c => c.id === id) || CHARS[0];\n"
  + cut('const MOVES = {', '// ---------- sound') + cut('// ---------- game simulation', '// ---------- CPU')
  + 'return { newGame, stepGame };';
const { newGame, stepGame } = new Function(code)();
const [frames, seed] = [Number(process.argv[2] || 6000), Number(process.argv[3] || 42)];
const g = newGame('bubbles', 'preacher', 'plaza', 'net'); g.rng = 777;
const ins = makeInputs(frames, seed);
const n = v => typeof v === 'number' ? v.toFixed(6) : String(v);
for (let f = 0; f < frames; f++) {
  stepGame(g, ins[f]);
  if (f % 30 === 29) {
    const parts = [g.frame, g.ph, g.pt, g.timer, g.rng, g.round, g.stop, g.superFlash];
    for (const F of g.F) parts.push(F.x, F.y, F.vx, F.vy, F.hp, F.m, F.st, F.t, F.mv, F.stun, F.wins, F.f, F.inv, F.combo, F.presses.length);
    for (const p of g.proj) parts.push(p.x, p.y, p.vx, p.life, p.o);
    console.log(parts.map(n).join(' '));
  }
}
