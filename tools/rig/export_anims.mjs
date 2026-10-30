// Exports the web version's poses and animations as rig keyframes for Godot (game/data/anims.json).
// Each key holds the joint rotations/positions of the cut-out rig built by game/tools/build_fighters.gd.
import fs from 'node:fs';
const src = fs.readFileSync(new URL('../../web-legacy/src.html', import.meta.url), 'utf8');
const lines = src.split('\n');
const grab = (a, b) => { const i = lines.findIndex(l => l.startsWith(a)), j = lines.findIndex((l, k) => k > i && l.startsWith(b)); return lines.slice(i, j).join('\n'); };
const code = 'const D2R = Math.PI / 180;\n' + grab('const P = (o) =>', '// ---------- moves') + grab('// ---------- animation', 'function squash')
  + '\nreturn { P, POSE, lerpPose, EASE, ANIM, poseOf };';
const { POSE, ANIM, poseOf } = new Function(code)();
const D2R = Math.PI / 180, L1 = 50, L2 = 52;
const AIR = new Set(['jump', 'airP', 'airK', 'upper', 'fly']);
const legH = l => Math.cos(l[0] * D2R) * L1 + Math.cos((l[0] + l[1]) * D2R) * L2;
const r4 = v => Math.round(v * 10000) / 10000;
function rig(p, anim) {
  const hy = p.g ? Math.max(legH(p.fl), legH(p.bl)) + 8 : (p.hy || 0) + (AIR.has(anim) ? 98 : 0);
  const t = p.t * D2R;
  return {
    root: [r4(p.hx || 0), r4(-hy + (p.by || 0)), r4((p.r || 0) * D2R)],
    torso: r4(t), head: r4((p.hd + p.t * 0.3) * D2R - t),
    fa_u: r4(-p.fa[0] * D2R - t), fa_l: r4(-p.fa[1] * D2R), ba_u: r4(-p.ba[0] * D2R - t), ba_l: r4(-p.ba[1] * D2R),
    fl_u: r4(-p.fl[0] * D2R), fl_l: r4(-p.fl[1] * D2R), bl_u: r4(-p.bl[0] * D2R), bl_l: r4(-p.bl[1] * D2R),
  };
}
const TR = { s: -1.8, o: 0.3333, i: 2, b: 0.3333 };
const out = {};
// keyed move animations (editable in Godot: few keys with easing)
for (const [name, keys] of Object.entries(ANIM)) {
  const air = name === 'airP' || name === 'airK' || name === 'upper';
  const ks = keys.map(k => ({ f: k[0], tr: 1, rig: rig(POSE[k[1]], air ? 'jump' : name) }));
  // the web version eases the segment ending at a key; Godot eases the segment starting at a key
  for (let i = 1; i < keys.length; i++) ks[i - 1].tr = TR[keys[i][2] || 's'];
  out[name] = { len: Math.max(1, keys[keys.length - 1][0]), loop: false, keys: ks };
}
// procedural animations: sampled from the web version's pose functions
const sample = (name, len, step, F, loop, gframe) => {
  const keys = [];
  for (let f = 0; f <= len; f += step) {
    const FF = Object.assign({ i: 0, t: f, vx: 0, f: 1, vy: 0, stun: 0, combo: 1, cb: false, landLag: 3 }, F);
    keys.push({ f, tr: 1, rig: rig(poseOf(FF, { frame: gframe ? f : 0 }), FF.st) });
  }
  out[name] = { len, loop, keys };
};
sample('idle', 82, 3, { st: 'idle' }, true, true);
sample('walk', 37, 2, { st: 'walk', vx: 1 }, true, true);
sample('walk_back', 37, 2, { st: 'walk', vx: -1 }, true, true);
sample('crouch', 6, 1, { st: 'crouch' }, false, false);
sample('hit', 22, 2, { st: 'hit', stun: 10, combo: 1 }, false, false);
sample('hit_big', 22, 2, { st: 'hit', stun: 30, combo: 3 }, false, false);
sample('hit_low', 18, 2, { st: 'hit', cb: true }, false, false);
sample('block', 4, 1, { st: 'block' }, false, false);
sample('cblock', 4, 1, { st: 'block', cb: true }, false, false);
sample('fly', 24, 3, { st: 'fly' }, false, false);
sample('down', 14, 1, { st: 'down' }, false, false);
sample('getup', 15, 1, { st: 'getup' }, false, false);
sample('win', 50, 3, { st: 'win' }, true, true);
// progress-based (seeked by the game from velocity or recovery time): length 60 = 0..1
out.jump = { len: 60, loop: false, keys: [
  { f: 0, tr: 0.3333, rig: rig(POSE.crouch, 'crouch') }, { f: 8, tr: -1.8, rig: rig(POSE.jumpUp, 'jump') },
  { f: 34, tr: -1.8, rig: rig(POSE.jump, 'jump') }, { f: 60, tr: 1, rig: rig(POSE.fall, 'jump') }] };
out.land = { len: 60, loop: false, keys: [{ f: 0, tr: 0.3333, rig: rig(POSE.crouch, 'crouch') }, { f: 60, tr: 1, rig: rig(POSE.stand, 'stand') }] };
fs.writeFileSync(new URL('../../game/data/anims.json', import.meta.url), JSON.stringify(out, null, 0));
console.log(Object.keys(out).length, 'animations');
