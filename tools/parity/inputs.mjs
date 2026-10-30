// Shared deterministic input script for the parity test (Park–Miller LCG: exact in both JS doubles and GDScript ints).
export function makeInputs(frames, seed) {
  let x = seed; const r = () => (x = (x * 16807) % 2147483647);
  const D = [0, 1, 2, 4, 8, 9, 10, 5, 6];
  const st = [{ b: 0, p: 0, k: 0, s: 0 }, { b: 0, p: 0, k: 0, s: 0 }], out = [];
  for (let f = 0; f < frames; f++) {
    for (const s of st) {
      if (r() % 9 === 0) s.b = D[r() % 9];
      const q = r() % 40;
      if (q === 0) s.p = (s.p + 1) % 16; else if (q === 1) s.k = (s.k + 1) % 16; else if (q === 2) s.s = (s.s + 1) % 16;
    }
    out.push(st.map(s => ({ ...s })));
  }
  return out;
}
