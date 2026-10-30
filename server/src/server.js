// Fellowship Fighter lobby server.
// One WebSocket per player. Players join a lobby (optionally a named one from the link, e.g. ?lobby=youth),
// queue for a match, get paired at random, and then the server relays rollback inputs between the pair.
// The fight itself runs on both phones; the server never simulates it.
import http from 'node:http';
import crypto from 'node:crypto';
import { WebSocketServer } from 'ws';
import { openScores } from './scores.js';

const MAX_MSG = 8 * 1024;
const NAME_RE = /[^\p{L}\p{N} _.\-'!?]/gu;

export async function createServer({ port = 0, databaseUrl, scoresFile, log = console.log } = {}) {
  const scores = await openScores({ databaseUrl, file: scoresFile });
  const lobbies = new Map(); // name -> { players:Set, queue:Set, dirty }
  let nextMatch = 1;

  const httpServer = http.createServer((req, res) => {
    if (req.url === '/' || req.url === '/health') { res.writeHead(200, { 'content-type': 'text/plain' }); res.end('ok'); return; }
    if (req.url.startsWith('/scores')) {
      scores.top(50).then(rows => { res.writeHead(200, { 'content-type': 'application/json', 'access-control-allow-origin': '*' }); res.end(JSON.stringify(rows)); })
        .catch(() => { res.writeHead(500); res.end(); });
      return;
    }
    res.writeHead(404); res.end();
  });
  const wss = new WebSocketServer({ server: httpServer, maxPayload: MAX_MSG });

  const lobbyOf = name => {
    let l = lobbies.get(name);
    if (!l) { l = { name, players: new Set(), queue: new Set(), dirty: true }; lobbies.set(name, l); }
    return l;
  };
  const send = (p, msg) => { if (p && p.ws.readyState === 1) p.ws.send(JSON.stringify(msg)); };
  const touch = l => { l.dirty = true; };

  async function broadcastLobby(l) {
    if (!l.dirty) return; l.dirty = false;
    const players = [...l.players].filter(p => p.name).map(p => ({ n: p.name, st: p.state, w: p.w, l: p.l, rw: p.rw, rl: p.rl }));
    let board = [];
    try { board = await scores.top(50); } catch (e) { log('scores read failed', e.message); }
    for (const p of l.players) send(p, { t: 'lobby', you: p.name, players, board });
  }

  function endMatch(m, reason) {
    if (m.over) return; m.over = true;
    for (const p of m.players) {
      if (p.match !== m) continue;
      p.match = null; p.state = 'idle';
      const o = m.players.find(q => q !== p);
      if (reason === 'left' && o) send(p, { t: 'oppLeft' });
      touch(p.lobby);
    }
  }

  function pair(l) {
    const q = [...l.queue].filter(p => p.ws.readyState === 1);
    for (let i = q.length - 1; i > 0; i--) { const j = crypto.randomInt(i + 1); [q[i], q[j]] = [q[j], q[i]]; }
    for (let i = 0; i + 1 < q.length; i += 2) {
      const a = q[i], b = q[i + 1];
      l.queue.delete(a); l.queue.delete(b);
      const m = { id: nextMatch++, players: [a, b], picks: [null, null], ready: [false, false], ep: 0, results: [null, null], rematch: [false, false], over: false };
      a.match = m; b.match = m; a.side = 0; b.side = 1; a.state = 'play'; b.state = 'play';
      send(a, { t: 'match', id: m.id, side: 0, opp: b.name });
      send(b, { t: 'match', id: m.id, side: 1, opp: a.name });
      touch(l);
    }
  }

  async function settle(m) {
    const [r0, r1] = m.results;
    if (!r0 || !r1 || m.recorded === m.ep) return;
    m.recorded = m.ep;
    // only count a result both phones agree on
    if (r0.won === r1.won || r0.a !== r1.b || r0.b !== r1.a) return;
    for (let s = 0; s < 2; s++) {
      const p = m.players[s], r = m.results[s];
      p.w += r.won ? 1 : 0; p.l += r.won ? 0 : 1; p.rw += r.a; p.rl += r.b;
      try { await scores.record(p.id, p.name, r.won, r.a, r.b); } catch (e) { log('score write failed', e.message); }
    }
    touch(m.players[0].lobby);
  }

  wss.on('connection', (ws) => {
    const p = { ws, id: null, name: null, lobby: null, state: 'idle', match: null, side: 0, w: 0, l: 0, rw: 0, rl: 0 };
    ws.on('message', (data, isBinary) => {
      if (isBinary) return;
      let msg; try { msg = JSON.parse(data.toString()); } catch { return; }
      if (!msg || typeof msg.t !== 'string') return;
      const m = p.match;
      switch (msg.t) {
        case 'hello': {
          if (p.name) return;
          p.name = String(msg.name || '').replace(NAME_RE, '').trim().slice(0, 16) || 'Fighter';
          p.id = /^[A-Za-z0-9_-]{8,64}$/.test(msg.id || '') ? msg.id : crypto.randomUUID();
          const ln = String(msg.lobby || 'main').toLowerCase().replace(/[^a-z0-9-]/g, '').slice(0, 24) || 'main';
          p.lobby = lobbyOf(ln); p.lobby.players.add(p); touch(p.lobby);
          send(p, { t: 'welcome', id: p.id, lobby: ln });
          return;
        }
        case 'queue': if (p.lobby && !m) { p.state = 'q'; p.lobby.queue.add(p); touch(p.lobby); } return;
        case 'unqueue': if (p.lobby) { p.lobby.queue.delete(p); if (!m) p.state = 'idle'; touch(p.lobby); } return;
        case 'leave': if (m) { endMatch(m, 'left'); } return;
      }
      if (!m || m.over) return;
      const o = m.players[1 - p.side];
      switch (msg.t) {
        case 'pick': {
          m.picks[p.side] = typeof msg.c === 'string' ? msg.c.slice(0, 32) : null;
          m.ready[p.side] = !!msg.ready && !!m.picks[p.side];
          send(o, { t: 'oppPick', c: m.picks[p.side], ready: m.ready[p.side] });
          if (m.ready[0] && m.ready[1]) {
            m.ready = [false, false]; m.results = [null, null];
            const go = { t: 'go', ep: m.ep, c: [...m.picks], seed: crypto.randomInt(1, 2 ** 31 - 1) };
            send(m.players[0], go); send(m.players[1], go);
          }
          return;
        }
        case 'in': // rollback inputs: pass straight through to the opponent
          send(o, msg); return;
        case 'result':
          m.results[p.side] = { won: !!msg.won, a: msg.a | 0, b: msg.b | 0 };
          settle(m); return;
        case 'rematch':
          m.rematch[p.side] = true;
          if (m.rematch[0] && m.rematch[1]) { m.rematch = [false, false]; m.ep++; m.ready = [false, false]; send(m.players[0], { t: 'rematch', ep: m.ep }); send(m.players[1], { t: 'rematch', ep: m.ep }); }
          else send(o, { t: 'oppRematch' });
          return;
      }
    });
    ws.on('close', () => {
      if (p.match) endMatch(p.match, 'left');
      if (p.lobby) { p.lobby.players.delete(p); p.lobby.queue.delete(p); touch(p.lobby); }
    });
  });

  const tick = setInterval(() => { for (const l of lobbies.values()) { pair(l); broadcastLobby(l); if (!l.players.size) lobbies.delete(l.name); } }, 400);
  const beat = setInterval(() => {
    for (const ws of wss.clients) { if (ws._ffDead) { ws.terminate(); continue; } ws._ffDead = true; ws.ping(); ws.once('pong', () => { ws._ffDead = false; }); }
  }, 20000);

  await new Promise(r => httpServer.listen(port, r));
  return {
    port: httpServer.address().port,
    async close() { clearInterval(tick); clearInterval(beat); for (const ws of wss.clients) ws.terminate(); await new Promise(r => wss.close(r)); await new Promise(r => httpServer.close(r)); await scores.close(); },
  };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const s = await createServer({ port: Number(process.env.PORT) || 8080, databaseUrl: process.env.DATABASE_URL });
  console.log(`Fellowship Fighter server listening on :${s.port}`);
}
