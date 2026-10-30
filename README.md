# Fellowship Fighter

A phone-friendly 2D street fighter with fighters made from real photos, a live lobby with random
matchmaking, best-of-5 matches, a scoreboard and rollback netcode.

| Folder | What it is |
|---|---|
| `game/` | The Godot 4.4 game (open `game/project.godot` in Godot) |
| `server/` | The lobby server: matchmaking, relays match inputs, keeps the scoreboard |
| `web-legacy/` | The original single-page version (the claude.ai artifact), kept for reference |
| `source-art/` | Original photos and the background-removed cut-outs |
| `tools/` | Art pipeline, rig export, and the sim parity test |

## How it fits together

```
 phone A ──WebSocket──┐                ┌──WebSocket── phone B
 (Godot web build)    └── lobby server ┘   (Godot web build)
                          • who's online, random pairing
                          • passes each player's inputs to the other
                          • records agreed results (Postgres or a JSON file)
```

Both phones run the same fight simulation (`game/sim/sim.gd`) with the same inputs. Each phone
predicts the opponent's next input; when the real one arrives and differs, it rewinds and
replays (`game/net/rollback.gd`). The server never simulates anything, so it stays tiny and cheap.

## Deploying (one-time setup)

You need free accounts on **Render** (lobby server) and optionally **Supabase** (lasting scoreboard).
The game itself is hosted on **GitHub Pages** by the workflow in `.github/workflows/web.yml`.

1. **Lobby server on Render**
   - render.com → *New* → *Blueprint* → connect GitHub → pick `laine-arch/fellowship-fight`.
   - Render reads `render.yaml` and creates `fellowship-fight-lobby`. Leave `DATABASE_URL` empty
     for now (or see step 2) and click *Apply*.
   - When it's live, copy its address, e.g. `https://fellowship-fight-lobby.onrender.com`.
     The game uses the same address with `wss://` instead of `https://`.
   - The free plan sleeps after 15 idle minutes; the first player then waits ~1 minute for it to
     wake. The $7/month plan stays awake.
2. **Scoreboard database (optional, recommended)**
   - supabase.com → *New project* → *Connect* → copy the **Session pooler** connection string
     (it starts with `postgresql://`, put your database password in it).
   - In Render → the service → *Environment* → set `DATABASE_URL` to that string. The table is
     created automatically. Without it, scores reset whenever Render restarts the server.
3. **Game on GitHub Pages**
   - GitHub repo → *Settings* → *Pages* → *Source*: **GitHub Actions**.
   - *Settings* → *Secrets and variables* → *Actions* → *Variables* → *New repository variable*:
     `LOBBY_SERVER_URL` = `wss://fellowship-fight-lobby.onrender.com` (your Render address).
   - *Actions* → *Test and deploy web build* → *Run workflow* (it also runs on every push).
     The game appears at `https://laine-arch.github.io/fellowship-fight/`.
4. **Share the link.** Optional link options:
   - `?lobby=youth` puts everyone using that link in their own lobby.
   - `?server=wss://…` points the game at a different lobby server (handy for testing).

## Working on the game

- **Run it:** open `game/project.godot` in Godot 4.4 and press Play. For online play locally,
  start the server first (`cd server && npm install && npm start`); the game connects to
  `ws://localhost:8080` by default (`fellowship/server_url` in Project Settings).
- **Controls:** arrows/WASD to move, J/K/L for punch/kick/special. On phones: drag the left side,
  tap the buttons. Combos: P,P,K · K,K · down+P → down+K. Specials: SPECIAL (projectile),
  toward+SPECIAL (rush), up+SPECIAL (uppercut), down+SPECIAL with a full bar (super).
- **Animations:** each fighter is a cut-out rig in `game/fighters/<id>.tscn` with an
  `AnimationPlayer` holding every move. Open the scene, pick an animation and adjust keys.
  Animations are seeked from the fight state, so the length of each move's attack window comes
  from `Sim.MOVES`, while the poses come from the animation. Note:
  `game/tools/build_fighters.gd` regenerates these scenes from `game/data/anims.json` and
  **overwrites editor changes**, so once you start hand-editing animations, stop re-running it.
- **Gameplay numbers** (damage, speed, frame data) are in `game/sim/sim.gd`. Anything in that
  file must stay deterministic: no `randf()`, `sin()` or other platform-dependent math.

### Adding a fighter

1. Put a clear, full-body photo in `source-art/`, remove the background (e.g. `rembg`), and
   stylise it with `tools/art/stylize_photos.py` (copy one of the existing fighter blocks).
2. Render the body parts: `node tools/rig/render_parts.mjs` (needs Playwright), after adding the
   fighter's colours to the character list it reads.
3. Add the fighter to `Sim.CHARS` (stats) and `Chars.LIST` (name, tag line, super name).
4. Rebuild rigs: `godot --headless --path game -s res://tools/build_fighters.gd`.

**Painted style (the target look):** from one painted illustration of the fighter, run
`python3 tools/art/painted_fighter.py <id>` after adding a `SPEC` entry with coordinates on that
image: the head, a close-up for the portrait, and a strip along the upper arm, forearm, thigh and
shin, the fist and the shirt. It cuts those pieces out of the painting and fits them onto the rig.
Best source image: full body in a side-on fighting stance facing either way, plain background,
no text or logos, plus a head-and-shoulders close-up (a "character sheet" with separate limbs is
even better).

### Adding a stage

Drop a wide image in `game/art/stages/` (1280×720 works well, with the floor in the bottom
fifth) and add it to `Chars.STAGES`.

## Tests

```bash
# lobby server
cd server && npm test
# the Godot sim must match the original web sim exactly
godot --headless --path game --editor --quit
godot --headless --path game -s res://tests/parity_run.gd -- 6000 42 > gd.txt
node tools/parity/js_run.mjs 6000 42 > js.txt && diff js.txt gd.txt
# two headless game clients playing each other through a local server, with 40 ms extra delay each way
(cd server && PORT=8098 npm start) &
godot --headless --path game -s res://tests/net_bot.gd -- ws://localhost:8098 BotA 40 60 quick &
godot --headless --path game -s res://tests/net_bot.gd -- ws://localhost:8098 BotB 40 60 quick
# scripted CPU match with screenshots (needs a display, e.g. xvfb-run)
xvfb-run godot --path game --rendering-driver opengl3 -s res://tests/smoke_cpu.gd
```

## Credits

Font: Luckiest Guy by Astigmatic (Apache 2.0). Everything else is original to this project.
