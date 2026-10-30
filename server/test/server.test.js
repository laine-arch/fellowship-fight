import { test } from 'node:test';
import assert from 'node:assert/strict';
import os from 'node:os';
import path from 'node:path';
import WebSocket from 'ws';
import { createServer } from '../src/server.js';

function client(port) {
  const ws = new WebSocket(`ws://localhost:${port}`);
  const inbox = [];
  const waiters = [];
  ws.on('message', d => { const m = JSON.parse(d); const i = waiters.findIndex(w => w.t === m.t); if (i >= 0) waiters.splice(i, 1)[0].res(m); else inbox.push(m); });
  return {
    ws, send: m => ws.send(JSON.stringify(m)),
    next(t, ms = 3000) {
      const i = inbox.findIndex(m => m.t === t); if (i >= 0) return Promise.resolve(inbox.splice(i, 1)[0]);
      return new Promise((res, rej) => { waiters.push({ t, res }); setTimeout(() => rej(new Error('timeout waiting for ' + t)), ms); });
    },
    open: new Promise(r => ws.on('open', r)),
  };
}

test('pairs two queued players, relays inputs, starts and records a match', async () => {
  const s = await createServer({ scoresFile: path.join(os.tmpdir(), `ff-scores-${Date.now()}.json`), log: () => {} });
  const a = client(s.port), b = client(s.port), c = client(s.port);
  await Promise.all([a.open, b.open, c.open]);
  a.send({ t: 'hello', name: 'Alice', id: 'alice-0001' }); b.send({ t: 'hello', name: 'Bob<script>', id: 'bob-00001' }); c.send({ t: 'hello', name: 'Cara', lobby: 'other' });
  await a.next('welcome'); await b.next('welcome'); await c.next('welcome');
  a.send({ t: 'queue' }); b.send({ t: 'queue' }); c.send({ t: 'queue' });
  const ma = await a.next('match'), mb = await b.next('match');
  assert.equal(ma.id, mb.id); assert.notEqual(ma.side, mb.side);
  assert.equal(mb.opp, 'Alice');
  assert.equal(ma.opp === 'Bobscript' || mb.opp === 'Bobscript', true, 'names are sanitised');
  await assert.rejects(c.next('match', 900), /timeout/, 'a lone player in another lobby is not paired');
  a.send({ t: 'pick', c: 'bubbles', ready: true });
  assert.deepEqual(await b.next('oppPick'), { t: 'oppPick', c: 'bubbles', ready: true });
  b.send({ t: 'pick', c: 'preacher', ready: true });
  const ga = await a.next('go'), gb = await b.next('go');
  assert.deepEqual(ga, gb); assert.equal(ga.c.length, 2);
  a.send({ t: 'in', s: 0, a: [1, 2, 3], f: 3 });
  assert.deepEqual((await b.next('in')).a, [1, 2, 3]);
  const [A, B] = ma.side === 0 ? [a, b] : [b, a];
  A.send({ t: 'result', won: true, a: 3, b: 1 }); B.send({ t: 'result', won: false, a: 1, b: 3 });
  let lob; for (let i = 0; i < 10; i++) { lob = await a.next('lobby'); if (lob.board.length) break; }
  assert.equal(lob.board.length, 2);
  assert.equal(lob.board[0].w, 1);
  A.send({ t: 'rematch' }); await B.next('oppRematch'); B.send({ t: 'rematch' });
  assert.equal((await A.next('rematch')).ep, 1);
  B.ws.close();
  await A.next('oppLeft');
  for (const x of [a, b, c]) x.ws.close();
  await s.close();
});

test('disagreeing results are not recorded', async () => {
  const s = await createServer({ scoresFile: path.join(os.tmpdir(), `ff-scores-${Date.now()}-2.json`), log: () => {} });
  const a = client(s.port), b = client(s.port); await Promise.all([a.open, b.open]);
  a.send({ t: 'hello', name: 'A' }); b.send({ t: 'hello', name: 'B' });
  a.send({ t: 'queue' }); b.send({ t: 'queue' });
  await a.next('match'); await b.next('match');
  a.send({ t: 'result', won: true, a: 3, b: 0 }); b.send({ t: 'result', won: true, a: 3, b: 0 });
  await new Promise(r => setTimeout(r, 900));
  const res = await fetch(`http://localhost:${s.port}/scores`); assert.deepEqual(await res.json(), []);
  a.ws.close(); b.ws.close(); await s.close();
});
