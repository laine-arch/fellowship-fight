class_name Sim
extends RefCounted
## Deterministic fight simulation. Both phones run this with the same inputs and must reach the
## exact same state, so: no randf()/sin() here, plain +-*/ on floats only, and the arithmetic
## order matches the original web version line for line (see web-legacy/src.html).
## State is plain Dictionaries/Arrays so rollback can snapshot it with duplicate(true).

const W := 960
const DIR_L := 1
const DIR_R := 2
const DIR_U := 4
const DIR_D := 8

# Gameplay stats only. Visuals live in game/data/characters.gd.
const CHARS := {
	"bubbles": {"hp": 1000, "spd": 1.12, "pow": 0.92, "scale": 1.0, "proj": "bubble"},
	"preacher": {"hp": 1050, "spd": 0.92, "pow": 1.12, "scale": 1.07, "proj": "wave"},
}

# su=startup, act=active, rec=recovery, d=damage, hs=hitstun, bs=blockstun, lv: mid|low|high
# box: [forward, heightAboveFeet, w, h]  chain: button -> next move
const MOVES := {
	"jab": {"su": 4, "act": 3, "rec": 9, "d": 42, "hs": 16, "bs": 10, "lv": "mid", "box": [58, 156, 52, 28], "push": 4, "chain": {"p": "cross", "k": "kick"}},
	"cross": {"su": 6, "act": 3, "rec": 14, "d": 62, "hs": 19, "bs": 12, "lv": "mid", "box": [66, 150, 56, 30], "push": 6, "chain": {"k": "round"}},
	"round": {"su": 9, "act": 4, "rec": 20, "d": 92, "hs": 26, "bs": 14, "lv": "mid", "box": [70, 160, 70, 46], "push": 9, "launch": [7, 11]},
	"kick": {"su": 7, "act": 4, "rec": 14, "d": 66, "hs": 18, "bs": 12, "lv": "mid", "box": [78, 98, 70, 34], "push": 6, "chain": {"k": "spin", "p": "cross"}},
	"spin": {"su": 9, "act": 5, "rec": 20, "d": 86, "hs": 24, "bs": 14, "lv": "mid", "box": [82, 150, 72, 50], "push": 9, "launch": [8, 10]},
	"lowP": {"su": 4, "act": 3, "rec": 8, "d": 34, "hs": 15, "bs": 9, "lv": "low", "box": [62, 70, 52, 26], "push": 3, "crouch": 1, "chain": {"p": "lowP", "k": "sweep"}},
	"sweep": {"su": 8, "act": 5, "rec": 22, "d": 72, "hs": 30, "bs": 14, "lv": "low", "box": [80, 16, 86, 28], "push": 5, "crouch": 1, "trip": 1},
	"airP": {"su": 4, "act": 9, "rec": 0, "d": 54, "hs": 18, "bs": 11, "lv": "high", "box": [52, 110, 56, 44], "push": 4, "air": 1},
	"airK": {"su": 5, "act": 11, "rec": 0, "d": 70, "hs": 20, "bs": 12, "lv": "high", "box": [56, 40, 60, 56], "push": 5, "air": 1},
	"proj": {"su": 13, "act": 0, "rec": 24, "spawn": 13},
	"rush": {"su": 7, "act": 16, "rec": 18, "d": 98, "hs": 26, "bs": 16, "lv": "mid", "box": [58, 140, 60, 70], "push": 8, "launch": [8, 9], "dash": 10, "chip": 10},
	"upper": {"su": 3, "act": 14, "rec": 14, "d": 108, "hs": 30, "bs": 16, "lv": "mid", "box": [40, 190, 54, 96], "push": 3, "launch": [3, 15], "inv": 9, "rise": 15, "chip": 12},
	"super": {"su": 12, "act": 0, "rec": 34, "spawn": 12, "sup": 1, "inv": 30},
}

static var _dedupe: RegEx
static var _dp: RegEx
static var _qcf1: RegEx
static var _qcf2: RegEx


static func char_stats(id: String) -> Dictionary:
	return CHARS.get(id, CHARS["bubbles"])


static func new_fighter(idx: int, char_id: String) -> Dictionary:
	var c := char_stats(char_id)
	return {
		"i": idx, "c": char_id if CHARS.has(char_id) else "bubbles", "x": 660.0 if idx else 300.0, "y": 0.0, "vx": 0.0, "vy": 0.0,
		"f": -1 if idx else 1, "hp": c.hp, "max": c.hp, "m": 0, "st": "idle", "t": 0, "mv": null,
		"hitDone": 0, "contact": 0, "stun": 0, "combo": 0, "jug": 0, "inv": 0, "wins": 0, "projOut": 0,
		"dirHist": [], "presses": [], "flash": 0, "airAtk": 0, "landLag": 0,
		"h": 0, "v": 0, "num": 5, "cb": false, "pc": null,
	}


static func new_game(c0: String, c1: String, stage: String, seed: int = 12345) -> Dictionary:
	return {
		"ph": "intro", "pt": 0, "round": 1, "timer": 60 * 60, "F": [new_fighter(0, c0), new_fighter(1, c1)],
		"proj": [], "ev": [], "evId": 0, "stop": 0, "slow": 0, "rng": seed, "stage": stage,
		"winner": -1, "roundWinner": -1, "frame": 0, "superFlash": 0, "superBy": -1,
	}


static func emit_ev(g: Dictionary, e: Dictionary) -> void:
	g.evId += 1
	e.id = g.evId
	e.fr = g.frame
	g.ev.append(e)
	if g.ev.size() > 24:
		g.ev.pop_front()


# --- 32-bit integer helpers (match JavaScript's |0, >>> and Math.imul) ---
static func _i32(x: int) -> int:
	x = x & 0xFFFFFFFF
	return x - 0x100000000 if x >= 0x80000000 else x


static func _u32(x: int) -> int:
	return x & 0xFFFFFFFF


static func _imul(a: int, b: int) -> int:
	return _i32(_i32(a) * _i32(b))


## mulberry32, kept in game state so both phones roll the same numbers
static func rnd(g: Dictionary) -> float:
	g.rng = _i32(g.rng + 0x6D2B79F5)
	var t: int = g.rng
	t = _imul(t ^ (_u32(t) >> 15), t | 1)
	t = t ^ _i32(t + _imul(t ^ (_u32(t) >> 7), t | 61))
	return float(_u32(t ^ (_u32(t) >> 14))) / 4294967296.0


static func reset_round(g: Dictionary) -> void:
	for i in 2:
		var F: Dictionary = g.F[i]
		var c := char_stats(F.c)
		F.x = 660.0 if i else 300.0
		F.y = 0.0; F.vx = 0.0; F.vy = 0.0; F.f = -1 if i else 1; F.hp = c.hp; F.st = "idle"; F.t = 0; F.mv = null
		F.stun = 0; F.combo = 0; F.jug = 0; F.inv = 0; F.projOut = 0; F.presses = []; F.landLag = 0
	g.proj = []
	g.timer = 60 * 60
	g.ph = "intro"
	g.pt = 0
	g.roundWinner = -1


## inp: {b: direction bits, p/k/s: press counters}. A press is a counter change.
static func feed_input(F: Dictionary, inp: Dictionary, frame: int) -> void:
	var fwd := DIR_R if F.f > 0 else DIR_L
	var back := DIR_L if F.f > 0 else DIR_R
	var b: int = inp.b
	var h := 1 if (b & fwd) else (-1 if (b & back) else 0)
	var v := 1 if (b & DIR_U) else (-1 if (b & DIR_D) else 0)
	var num: int
	if v == 1: num = 9 if h == 1 else (7 if h == -1 else 8)
	elif v == -1: num = 3 if h == 1 else (1 if h == -1 else 2)
	else: num = 6 if h == 1 else (4 if h == -1 else 5)
	F.dirHist.append(num)
	if F.dirHist.size() > 24:
		F.dirHist.pop_front()
	F.h = h; F.v = v; F.num = num
	if F.pc == null:
		F.pc = {"p": inp.p, "k": inp.k, "s": inp.s}
	for key in ["p", "k", "s"]:
		var now: int = inp[key]
		if now != F.pc[key]:
			F.presses.append({"b": key, "fr": frame, "num": num, "motion": motion_of(F.dirHist)})
			F.pc[key] = now
	F.presses = F.presses.filter(func(p): return frame - p.fr < 10)


static func motion_of(hist: Array) -> Variant:
	if _dedupe == null:
		_dedupe = RegEx.create_from_string("(\\d)\\1+")
		_dp = RegEx.create_from_string("6[52]*2[12]*3")
		_qcf1 = RegEx.create_from_string("2[12]*3[3]*6")
		_qcf2 = RegEx.create_from_string("2[1]*3")
	var s := ""
	for n in hist.slice(-16):
		s += str(n)
	var d := _dedupe.sub(s, "$1", true)
	if _dp.search(d): return "dp"
	if _qcf1.search(d) or (_qcf2.search(d) and s.ends_with("6")): return "qcf"
	return null


static func take_press(F: Dictionary, keys: Array) -> Variant:
	for i in F.presses.size():
		if keys.has(F.presses[i].b):
			var p = F.presses[i]
			F.presses.remove_at(i)
			return p
	return null


static func start_move(g: Dictionary, F: Dictionary, name: String) -> void:
	var M: Dictionary = MOVES[name]
	F.st = "atk"; F.mv = name; F.t = 0; F.hitDone = 0; F.contact = 0
	if M.has("inv"): F.inv = M.inv
	if name == "upper": F.vy = 0.0
	if name == "super":
		F.m = 0; g.superFlash = 40; g.superBy = F.i
		emit_ev(g, {"k": "super", "i": F.i})
	if not M.has("air") and name != "upper": F.vx = 0.0
	emit_ev(g, {"k": "whiff", "i": F.i})


static func choose_special(F: Dictionary, pr: Dictionary) -> String:
	if pr.num == 2 or pr.num == 1 or pr.num == 3:
		if F.m >= 100: return "super"
	if pr.num == 8 or pr.num == 7 or pr.num == 9: return "upper"
	if pr.num == 6: return "rush"
	return "rush" if F.projOut else "proj"


static func can_act(F: Dictionary) -> bool:
	return F.st == "idle" or F.st == "walk" or F.st == "crouch"


static func step_fighter(g: Dictionary, F: Dictionary, O: Dictionary) -> void:
	var c := char_stats(F.c)
	F.t += 1
	if F.inv > 0: F.inv -= 1
	if F.flash > 0: F.flash -= 1
	var grounded: bool = F.y <= 0
	if grounded and (can_act(F) or F.st == "block"):
		F.f = 1 if O.x >= F.x else -1
	match F.st:
		"hit", "block":
			F.stun -= 1
			if F.stun <= 0 and grounded:
				F.st = "crouch" if F.st == "hit" and F.v == -1 else "idle"
				F.t = 0; F.combo = 0; F.jug = 0
		"fly":
			if grounded and F.t > 3:
				F.st = "down"; F.t = 0; F.vx = 0.0
				emit_ev(g, {"k": "land", "x": F.x})
		"down":
			F.inv = 2
			if F.t > 40:
				if F.hp <= 0: F.t = 40
				else: F.st = "getup"; F.t = 0
		"getup":
			F.inv = 2
			if F.t > 14:
				F.st = "idle"; F.t = 0; F.combo = 0; F.jug = 0
		"ko", "win":
			pass
		"land":
			if F.t > F.landLag:
				F.st = "idle"; F.t = 0
		"jump":
			var pr = take_press(F, ["p", "k"])
			if pr != null and not F.airAtk:
				F.airAtk = 1; F.st = "atk"; F.mv = "airP" if pr.b == "p" else "airK"; F.t = 0; F.hitDone = 0
				emit_ev(g, {"k": "whiff", "i": F.i})
		"atk":
			var M: Dictionary = MOVES[F.mv]
			var end: int = M.su + M.act + M.rec
			if M.has("chain") and F.t >= M.su and F.t < end - 1:
				var pr = null
				for p in F.presses:
					if M.chain.has(p.b):
						pr = p
						break
				if pr != null and (F.contact or F.t >= M.su + M.act):
					F.presses.erase(pr)
					var nm: String = M.chain[pr.b]
					if pr.b == "p" and (pr.motion == "qcf" or pr.motion == "dp"):
						nm = "upper" if pr.motion == "dp" else "proj"
					start_move(g, F, nm)
					step_physics(g, F, O)
					return
			if not M.has("sup") and F.contact and F.mv != "upper" and F.mv != "proj" and F.mv != "rush":
				var pr = null
				for p in F.presses:
					if p.b == "s" or (p.b == "p" and p.motion != null):
						pr = p
						break
				if pr != null:
					F.presses.erase(pr)
					start_move(g, F, choose_special(F, pr) if pr.b == "s" else ("upper" if pr.motion == "dp" else "proj"))
					step_physics(g, F, O)
					return
			if M.has("spawn") and F.t == M.spawn: spawn_proj(g, F, M.has("sup"))
			if M.has("sup") and F.t > M.spawn and F.t < M.spawn + 26 and (F.t - M.spawn) % 6 == 0: spawn_proj(g, F, true)
			if M.has("dash") and F.t >= M.su and F.t < M.su + M.act: F.vx = F.f * M.dash * c.spd
			elif M.has("dash") and F.t == M.su + M.act: F.vx = 0.0
			if M.has("rise") and F.t == M.su:
				F.vy = float(M.rise); F.vx = F.f * 2.5
			if M.has("air"):
				if grounded and F.t > 1:
					F.st = "land"; F.t = 0; F.landLag = 3; F.mv = null
			elif F.mv == "upper":
				if grounded and F.t > M.su + 2:
					F.st = "land"; F.t = 0; F.landLag = M.rec; F.mv = null
			elif F.t >= end:
				F.st = "crouch" if M.has("crouch") and F.v == -1 else "idle"
				F.t = 0; F.mv = null
	if can_act(F) and grounded:
		var pr = take_press(F, ["p", "k", "s"])
		if pr != null:
			var nm: String
			if pr.b == "s": nm = choose_special(F, pr)
			elif pr.b == "p" and pr.motion == "dp": nm = "upper"
			elif pr.b == "p" and pr.motion == "qcf": nm = "jab" if F.projOut else "proj"
			elif F.v == -1: nm = "lowP" if pr.b == "p" else "sweep"
			else: nm = "jab" if pr.b == "p" else "kick"
			start_move(g, F, nm)
		elif F.v == 1:
			F.st = "jump"; F.t = 0; F.vy = 17.5; F.vx = F.h * 4.6 * F.f * (0.9 + c.spd * 0.1); F.airAtk = 0; F.y = 0.01
		elif F.v == -1:
			if F.st != "crouch":
				F.st = "crouch"; F.t = 0
			F.vx = 0.0
		elif F.h != 0:
			F.st = "walk"
			F.vx = F.f * F.h * (3.5 if F.h > 0 else 2.7) * c.spd
		else:
			if F.st != "idle":
				F.st = "idle"; F.t = 0
			F.vx = 0.0
	step_physics(g, F, O)


static func step_physics(_g: Dictionary, F: Dictionary, _O: Dictionary) -> void:
	F.x += F.vx
	if F.y > 0 or F.vy > 0:
		F.y += F.vy
		F.vy -= 0.92
		if F.y <= 0:
			F.y = 0.0; F.vy = 0.0
			if F.st == "jump":
				F.st = "land"; F.t = 0; F.landLag = 3
	if F.y <= 0 and (F.st == "hit" or F.st == "block"): F.vx *= 0.82
	if F.st == "land" or F.st == "down" or F.st == "getup" or F.st == "ko": F.vx *= 0.8
	F.x = maxf(44.0, minf(W - 44.0, F.x))


static func hurtbox(F: Dictionary) -> Variant:
	var sc: float = char_stats(F.c).scale
	if F.st == "down" or F.st == "getup" or F.st == "ko": return null
	var crouch: bool = F.st == "crouch" or (F.st == "block" and F.cb) or (F.st == "atk" and F.mv != null and MOVES[F.mv].has("crouch")) or (F.st == "hit" and F.cb)
	var h := (128 if crouch else 205) * sc
	return {"x": F.x - 30 * sc, "y": F.y, "w": 60 * sc, "h": h}


static func rect_hit(a: Dictionary, b: Dictionary) -> bool:
	return a.x < b.x + b.w and a.x + a.w > b.x and a.y < b.y + b.h and a.y + a.h > b.y


static func is_blocking(D: Dictionary, lv: String) -> bool:
	if not (D.st == "idle" or D.st == "walk" or D.st == "crouch" or D.st == "block") or D.y > 0: return false
	if D.h != -1: return false
	var crouching: bool = D.v == -1
	if lv == "low" and not crouching: return false
	if lv == "high" and crouching: return false
	return true


static func apply_hit(g: Dictionary, A: Dictionary, D: Dictionary, dmg: int, hs: int, bs: int, lv: String, push: int, launch, trip: int, chip: int, x: float, y: float, is_proj: bool) -> bool:
	if D.inv > 0 or D.hp <= 0: return false
	if D.st == "fly" and D.jug >= 3: return false
	var c := char_stats(A.c)
	if is_blocking(D, lv):
		D.st = "block"; D.cb = D.v == -1; D.stun = bs; D.t = 0; D.vx = A.f * push * 0.9
		var ch := int(roundf((chip if chip else (12 if is_proj else 0)) * c.pow))
		D.hp = maxi(1, D.hp - ch)
		D.m = mini(100, D.m + 3); A.m = mini(100, A.m + 2)
		g.stop = 4
		emit_ev(g, {"k": "block", "x": x, "y": y})
		return true
	D.combo = D.combo + 1 if (D.st == "hit" or D.st == "fly") else 1
	var scale := maxf(0.45, 1 - 0.12 * (D.combo - 1))
	var real := int(roundf(dmg * c.pow * scale))
	D.hp = maxi(0, D.hp - real); D.flash = 6
	A.m = mini(100, A.m + 9); D.m = mini(100, D.m + 5)
	D.cb = D.v == -1 and D.y <= 0
	if launch != null or trip or D.y > 0 or D.st == "fly" or D.hp <= 0:
		D.st = "fly"; D.t = 0; D.jug += 1
		D.vy = 6.0 if trip else (float(launch[1]) if launch != null else 8.0)
		D.vx = A.f * (launch[0] if launch != null else (1.5 if trip else 4.5))
		D.y = maxf(D.y, 0.5)
	else:
		D.st = "hit"; D.t = 0; D.stun = hs; D.vx = float(A.f * push)
	D.mv = null
	g.stop = 9 if real > 80 else 6
	emit_ev(g, {"k": "big" if real > 80 else "hit", "x": x, "y": y, "dmg": real, "combo": D.combo, "i": A.i})
	return true


static func check_hits(g: Dictionary, A: Dictionary, D: Dictionary) -> void:
	if A.st != "atk" or A.hitDone: return
	var M: Dictionary = MOVES[A.mv]
	if not M.has("box"): return
	if A.t < M.su or A.t >= M.su + M.act: return
	var sc: float = char_stats(A.c).scale
	var fw: int = M.box[0]; var hy: int = M.box[1]; var w: int = M.box[2]; var h: int = M.box[3]
	var cx: float = A.x + A.f * fw * sc
	var cy: float = A.y + hy * sc
	var hb := {"x": cx - w * sc / 2, "y": cy - h * sc / 2, "w": w * sc, "h": h * sc}
	var hu = hurtbox(D)
	if D.st == "fly": hu = {"x": D.x - 34, "y": D.y, "w": 68, "h": 130}
	if hu == null or not rect_hit(hb, hu): return
	A.hitDone = 1
	var ok := apply_hit(g, A, D, M.d, M.hs, M.bs, M.lv, M.push, M.get("launch"), M.get("trip", 0), M.get("chip", 0),
		(maxf(hb.x, hu.x) + minf(hb.x + hb.w, hu.x + hu.w)) / 2, cy, false)
	if ok:
		A.contact = 1
		if D.x <= 46 or D.x >= W - 46: A.vx = float(-A.f * 3)


static func spawn_proj(g: Dictionary, F: Dictionary, sup: bool) -> void:
	var c := char_stats(F.c)
	if not sup and F.projOut: return
	if not sup: F.projOut = 1
	var wave: bool = c.proj == "wave"
	var off: float
	if sup: off = 110 + (rnd(g) * 60 - 30) * (0 if wave else 1)
	else: off = 140
	var y: float = F.y + off * c.scale
	g.proj.append({"o": F.i, "x": F.x + F.f * 60, "y": y, "vx": F.f * (6.5 if wave else 5.2) * (1.5 if sup else 1), "kind": c.proj,
		"sup": 1 if sup else 0, "life": 140, "r": (46 if wave else 30) if sup else (34 if wave else 26), "t": 0, "hits": 3 if sup and wave else 1})
	emit_ev(g, {"k": "wave" if wave else "proj"})


static func step_proj(g: Dictionary) -> void:
	for p in g.proj:
		p.x += p.vx; p.t += 1; p.life -= 1
		if p.kind == "bubble": p.y += 0.8 if p.t % 38 < 19 else -0.8
	for i in g.proj.size():
		for j in range(i + 1, g.proj.size()):
			var a: Dictionary = g.proj[i]; var b: Dictionary = g.proj[j]
			if a.o == b.o or a.life <= 0 or b.life <= 0: continue
			if absf(a.x - b.x) < a.r + b.r and absf(a.y - b.y) < a.r + b.r:
				a.life = 0; b.life = 0
				emit_ev(g, {"k": "pop", "x": (a.x + b.x) / 2, "y": (a.y + b.y) / 2})
	for p in g.proj:
		if p.life <= 0: continue
		var D: Dictionary = g.F[1 - p.o]; var A: Dictionary = g.F[p.o]
		var hu = hurtbox(D)
		if hu == null and D.st == "fly": hu = {"x": D.x - 34, "y": D.y, "w": 68, "h": 130}
		if hu != null and rect_hit({"x": p.x - p.r, "y": p.y - p.r, "w": p.r * 2, "h": p.r * 2}, hu):
			var dmg := (70 if p.kind == "wave" else 44) if p.sup else 78
			var launch = null
			if p.sup:
				p.hits -= 1
				if p.hits <= 0: launch = [6, 9]
			if apply_hit(g, A, D, dmg, 20, 14, "mid", 5, launch, 0, 8 if p.sup else 12, p.x, p.y, true):
				if not p.sup or p.hits <= 0: p.life = 0
				else: p.x += p.vx * 3
			else:
				p.life = 0
			if p.life <= 0: emit_ev(g, {"k": "pop", "x": p.x, "y": p.y})
		if p.x < -60 or p.x > W + 60: p.life = 0
	for p in g.proj:
		if p.life <= 0 and not p.sup: g.F[p.o].projOut = 0
	g.proj = g.proj.filter(func(p): return p.life > 0)
	for F in g.F:
		var any := false
		for p in g.proj:
			if p.o == F.i and not p.sup: any = true
		if not any: F.projOut = 0


static func push_apart(g: Dictionary) -> void:
	var a: Dictionary = g.F[0]; var b: Dictionary = g.F[1]
	if a.st == "down" or b.st == "down": return
	var dx: float = b.x - a.x
	var mn := 52.0
	if absf(dx) < mn and absf(a.y - b.y) < 150:
		var ov := (mn - absf(dx)) / 2 * (1 if dx >= 0 else -1)
		a.x -= ov; b.x += ov
		for F in g.F: F.x = maxf(44.0, minf(W - 44.0, F.x))


static func step(g: Dictionary, inputs: Array) -> void:
	g.frame += 1
	for i in 2:
		var inp: Dictionary = inputs[i]
		feed_input(g.F[i], inp if g.ph == "fight" else {"b": 0, "p": inp.p, "k": inp.k, "s": inp.s}, g.frame)
	if g.ph != "fight":
		for F in g.F: F.presses = []
	if g.superFlash > 0:
		g.superFlash -= 1
		return
	if g.stop > 0:
		g.stop -= 1
		return
	if g.ph == "ko" and g.slow > 0:
		g.slow -= 1
		if g.slow % 3 != 0: return
	g.pt += 1
	if g.ph == "intro":
		# round 1 opens with a VS splash before the ROUND banner
		var length := 170 if g.round == 1 else 80
		var r0 := 92 if g.round == 1 else 1
		if g.pt == r0: emit_ev(g, {"k": "round", "n": g.round, "fin": 1 if g.F[0].wins == 2 and g.F[1].wins == 2 else 0})
		if g.pt == length - 10: emit_ev(g, {"k": "fight"})
		if g.pt > length:
			g.ph = "fight"; g.pt = 0
		for i in 2: step_fighter(g, g.F[i], g.F[1 - i])
		return
	if g.ph == "fight" or g.ph == "ko":
		for i in 2: step_fighter(g, g.F[i], g.F[1 - i])
		push_apart(g)
		if g.ph == "fight":
			check_hits(g, g.F[0], g.F[1]); check_hits(g, g.F[1], g.F[0])
		step_proj(g)
	if g.ph == "fight":
		g.timer -= 1
		var a: Dictionary = g.F[0]; var b: Dictionary = g.F[1]
		if a.hp <= 0 or b.hp <= 0 or g.timer <= 0:
			var w := -1
			if a.hp <= 0 and b.hp > 0: w = 1
			elif b.hp <= 0 and a.hp > 0: w = 0
			elif g.timer <= 0:
				var ka: float = float(a.hp) / a.max; var kb: float = float(b.hp) / b.max
				w = 0 if ka > kb else (1 if kb > ka else -1)
			g.roundWinner = w; g.ph = "ko"; g.pt = 0; g.slow = 60
			if w >= 0: g.F[w].wins += 1
			emit_ev(g, {"k": "time" if g.timer <= 0 else "ko", "w": w})
			for F in g.F:
				if F.hp <= 0 and F.st != "fly" and F.st != "down":
					F.st = "fly"; F.t = 0; F.vy = 9.0; F.vx = float(-F.f * 5); F.y = 1.0
	elif g.ph == "ko":
		if g.pt == 100 and g.roundWinner >= 0:
			var Wf: Dictionary = g.F[g.roundWinner]
			if Wf.y <= 0:
				Wf.st = "win"; Wf.t = 0; Wf.vx = 0.0; Wf.mv = null
		if g.pt > 190:
			if g.F[0].wins >= 3 or g.F[1].wins >= 3:
				g.ph = "over"; g.pt = 0; g.winner = 0 if g.F[0].wins >= 3 else 1
				emit_ev(g, {"k": "over", "w": g.winner})
			else:
				g.round += 1
				reset_round(g)


## FNV-1a over the state that matters, for the once-a-second desync check between phones.
static func hash_state(g: Dictionary) -> int:
	var parts := [g.frame, g.ph, g.pt, g.timer, g.rng, g.round, g.stop]
	for F in g.F:
		parts.append_array([F.x, F.y, F.vx, F.vy, F.hp, F.m, F.st, F.t, F.mv, F.stun, F.wins, F.f, F.inv])
	for p in g.proj:
		parts.append_array([p.x, p.y, p.vx, p.life, p.o])
	var s := var_to_str(parts)
	var h := 2166136261
	for ch in s.to_utf8_buffer():
		h = ((h ^ ch) * 16777619) & 0xFFFFFFFF
	return h
