// Scoreboard storage: Postgres when DATABASE_URL is set (e.g. Supabase), otherwise a JSON file.
import fs from 'node:fs';
import path from 'node:path';

export async function openScores({ databaseUrl, file } = {}) {
  if (databaseUrl) return openPg(databaseUrl);
  return openFile(file || path.join(process.cwd(), 'data', 'scores.json'));
}

async function openPg(url) {
  const { default: pg } = await import('pg');
  const pool = new pg.Pool({ connectionString: url, ssl: url.includes('localhost') ? false : { rejectUnauthorized: false }, max: 4 });
  await pool.query(`create table if not exists scores (
    id text primary key, name text not null, w int not null default 0, l int not null default 0,
    rw int not null default 0, rl int not null default 0, updated timestamptz not null default now())`);
  return {
    kind: 'postgres',
    async record(id, name, won, rw, rl) {
      await pool.query(`insert into scores (id, name, w, l, rw, rl) values ($1, $2, $3, $4, $5, $6)
        on conflict (id) do update set name = excluded.name, w = scores.w + excluded.w, l = scores.l + excluded.l,
        rw = scores.rw + excluded.rw, rl = scores.rl + excluded.rl, updated = now()`, [id, name, won ? 1 : 0, won ? 0 : 1, rw, rl]);
    },
    async top(n = 50) {
      const r = await pool.query('select name, w, l, rw, rl from scores order by w desc, l asc, (rw - rl) desc limit $1', [n]);
      return r.rows;
    },
    async close() { await pool.end(); },
  };
}

function openFile(file) {
  let rows = {};
  try { rows = JSON.parse(fs.readFileSync(file, 'utf8')); } catch { rows = {}; }
  let timer = null;
  const save = () => {
    clearTimeout(timer);
    timer = setTimeout(() => {
      try { fs.mkdirSync(path.dirname(file), { recursive: true }); fs.writeFileSync(file, JSON.stringify(rows)); } catch (e) { console.error('score save failed', e.message); }
    }, 500);
  };
  return {
    kind: 'file',
    async record(id, name, won, rw, rl) {
      const r = rows[id] || (rows[id] = { name, w: 0, l: 0, rw: 0, rl: 0 });
      r.name = name; r.w += won ? 1 : 0; r.l += won ? 0 : 1; r.rw += rw; r.rl += rl;
      save();
    },
    async top(n = 50) {
      return Object.values(rows).sort((a, b) => (b.w - a.w) || (a.l - b.l) || ((b.rw - b.rl) - (a.rw - a.rl))).slice(0, n);
    },
    async close() { clearTimeout(timer); },
  };
}
