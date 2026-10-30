// Renders each fighter's body parts as separate cel-shaded PNGs (2x) for the Godot cut-out rig,
// reusing the web version's drawing code so both versions look the same.
// Output: game/art/fighters/<id>/<part>.png + parts.json (pivot of each image, in 1x pixels).
import fs from 'node:fs';
import { createRequire } from 'node:module';
const { chromium } = createRequire(import.meta.url)('playwright'); // npm i -g playwright (or set NODE_PATH)
const root = new URL('../../', import.meta.url);
const src = fs.readFileSync(new URL('web-legacy/src.html', root), 'utf8');
const lines = src.split('\n');
const grab = (a, b) => { const i = lines.findIndex(l => l.startsWith(a)), j = lines.findIndex((l, k) => k > i && l.startsWith(b)); return lines.slice(i, j).join('\n'); };
const chars = new Function(grab('const CHARS = [', 'const LOCKED_SLOTS') + '\nreturn CHARS;')();
const drawCode = grab('const INK =', 'function drawFighter');
const S = 2; // render scale
// [name, width, height, pivotX, pivotY] in 1x units
const PARTS = [['torso', 96, 132, 48, 112], ['upper_arm', 48, 84, 24, 24], ['forearm', 40, 72, 20, 20], ['fist', 40, 40, 20, 20],
  ['thigh', 48, 100, 24, 24], ['shin', 40, 92, 20, 20], ['shoe', 56, 36, 18, 18]];
const b64 = p => 'data:image/png;base64,' + fs.readFileSync(new URL(p, root)).toString('base64');
const browser = await chromium.launch();
const page = await browser.newPage();
await page.setContent('<canvas id=c></canvas>');
for (const c of chars) {
  const dir = new URL(`game/art/fighters/${c.id}/`, root);
  const shirt = b64(`game/art/fighters/${c.id}/shirt.png`);
  const out = await page.evaluate(async ({ drawCode, c, shirt, PARTS, S }) => {
    const cv = document.getElementById('c'); const ctx = cv.getContext('2d');
    const img = new Image(); img.src = shirt; await img.decode();
    // eslint-disable-next-line no-new-func
    const lib = new Function('ctx', drawCode + '\nreturn { celPart, limbSegs, shadeOf, drawFist, drawShoe, INK, LIGHT };')(ctx);
    const res = {};
    for (const [name, w, h, px, py] of PARTS) {
      cv.width = w * S; cv.height = h * S; ctx.setTransform(S, 0, 0, S, px * S, py * S); ctx.clearRect(-999, -999, 9999, 9999);
      ctx.lineCap = 'round'; ctx.lineJoin = 'round';
      const shirtP = ctx.createPattern(img, 'repeat'), pants = c.pants, skinD = c.skinD || lib.shadeOf(c.skin), dark = 'rgba(30,8,45,.42)';
      if (name === 'upper_arm' || name === 'forearm' || name === 'fist') {
        const L = lib.limbSegs(0, 0, 0, 0, 38, 35, [14, 16.5, 11.5, 13, 8.5]);
        if (name === 'upper_arm') {
          lib.celPart(L.upper, c.skin, skinD, false);
          const u = L.upper; lib.celPart([[u[0][0], u[0][1], u[1][0] + (u[1][2] - u[1][0]) * .25, u[1][1] + (u[1][3] - u[1][1]) * .25, 18.5, 18]], shirtP, dark, false);
        } else if (name === 'forearm') {
          lib.celPart(L.lower.map(s => [s[0], s[1] - 38, s[2], s[3] - 38, s[4], s[5]]), c.skin, skinD, false);
        } else lib.drawFist(0, 0, 0, c.skin, skinD, false);
      } else if (name === 'thigh' || name === 'shin') {
        const L = lib.limbSegs(0, 0, 0, 0, 50, 52, [17.5, 17, 12.5, 14, 10]);
        if (name === 'thigh') lib.celPart(L.upper, pants, dark, false);
        else lib.celPart(L.lower.map(s => [s[0], s[1] - 50, s[2], s[3] - 50, s[4], s[5]]), pants, dark, false);
      } else if (name === 'shoe') lib.drawShoe(0, 0, 0, c, false);
      else if (name === 'torso') {
        const T = 74, INK = lib.INK;
        const torso = (o = 0, ox = 0, oy = 0) => { ctx.beginPath();
          ctx.moveTo(-23 - o + ox, 6 + o + oy); ctx.lineTo(23 + o + ox, 6 + o + oy);
          ctx.quadraticCurveTo(28 + o + ox, -T * .45 + oy, 36 + o + ox, -T + 16 + oy); ctx.quadraticCurveTo(35 + o + ox, -T - 4 - o + oy, 12 + ox, -T - 5 - o + oy);
          ctx.lineTo(-14 + ox, -T - 5 - o + oy); ctx.quadraticCurveTo(-38 - o + ox, -T - 3 - o + oy, -37 - o + ox, -T + 16 + oy);
          ctx.quadraticCurveTo(-29 - o + ox, -T * .45 + oy, -23 - o + ox, 6 + o + oy); ctx.closePath(); };
        lib.celPart([[0, -T + 6, 2, -T - 14, 10, 9]], c.skin, skinD, false);
        torso(3); ctx.fillStyle = INK; ctx.fill();
        torso(); ctx.fillStyle = shirtP; ctx.fill();
        ctx.save(); torso(); ctx.clip(); ctx.fillStyle = dark; ctx.fillRect(-60, -T - 20, 120, T + 40);
        torso(-1, 6, -5); ctx.fillStyle = shirtP; ctx.fill();
        ctx.strokeStyle = 'rgba(28,15,22,.55)'; ctx.lineWidth = 2; ctx.beginPath();
        ctx.moveTo(-18, -T + 26); ctx.quadraticCurveTo(-2, -T + 34, 16, -T + 26);
        ctx.moveTo(-14, -T * .38); ctx.quadraticCurveTo(-4, -T * .3, 8, -T * .4);
        ctx.moveTo(-7, -T - 4); ctx.quadraticCurveTo(2, -T + 6, 11, -T - 4);
        ctx.stroke(); ctx.restore();
        ctx.fillStyle = INK; ctx.fillRect(-26, -2, 52, 11); ctx.fillStyle = lib.shadeOf(c.pants, .55, 0); ctx.fillRect(-24, 0, 48, 7); ctx.fillStyle = '#c9a227'; ctx.fillRect(2, 0, 8, 7);
      }
      res[name] = cv.toDataURL('image/png');
    }
    return res;
  }, { drawCode, c, shirt, PARTS, S });
  const meta = { scale: 1 / S, headAnchor: c.headAnchor, headH: c.headH, parts: {} };
  for (const [name, w, h, px, py] of PARTS) {
    fs.writeFileSync(new URL(name + '.png', dir), Buffer.from(out[name].split(',')[1], 'base64'));
    meta.parts[name] = { pivot: [px, py], size: [w, h] };
  }
  fs.writeFileSync(new URL('parts.json', dir), JSON.stringify(meta, null, 1));
  console.log('rendered', c.id);
}
await browser.close();
