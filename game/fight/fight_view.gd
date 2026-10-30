class_name FightView
extends Node2D
## Draws a fight from the simulation state: stage, rigs, projectiles, hit effects, camera and HUD.
## Purely visual. It never changes the game state, so online rollback can rewind freely.

const W := 960.0
const H := 540.0
const GROUND := 492.0
const INK := Color(0.11, 0.06, 0.09)

var g: Dictionary
var names := ["", ""]
var my_idx := 0
var sfx: Sfx
var ping_ms := 0.0
var waiting := false

var font: Font
var rigs: Array = []
var stage_sprite: Sprite2D
var below: Node2D
var above: Node2D
var cam: Camera2D
var hud: Control
var heads := []
var busts := []

var fx: Array = []
var trails := [[], []]
var seen_ev := {}
var banner := {}
var shake := 0.0
var flash := 0.0
var drain := [1.0, 1.0]


func setup(game: Dictionary, player_names: Array, me: int) -> void:
	g = game; names = player_names; my_idx = me
	font = load("res://art/fonts/LuckiestGuy-Regular.ttf")
	for c in get_children(): c.queue_free()
	rigs.clear(); fx.clear(); seen_ev.clear(); banner = {}; trails = [[], []]; drain = [1.0, 1.0]
	stage_sprite = Sprite2D.new()
	stage_sprite.texture = load(Chars.stage(g.stage).image)
	stage_sprite.centered = false
	stage_sprite.scale = Vector2(W / stage_sprite.texture.get_width(), H / stage_sprite.texture.get_height())
	add_child(stage_sprite)
	below = Node2D.new(); add_child(below); below.draw.connect(_draw_below)
	heads.clear(); busts.clear()
	for F in g.F:
		var r: Node2D = Chars.rig(F.c).instantiate()
		add_child(r)
		rigs.append(r)
		heads.append(Chars.head(F.c)); busts.append(Chars.bust(F.c))
	above = Node2D.new(); above.z_index = 10; add_child(above); above.draw.connect(_draw_above)
	cam = Camera2D.new()
	cam.position = Vector2(W / 2, H / 2)
	cam.limit_left = 0; cam.limit_top = 0; cam.limit_right = int(W); cam.limit_bottom = int(H)
	add_child(cam); cam.make_current()
	var layer := CanvasLayer.new(); add_child(layer)
	hud = Control.new(); hud.set_anchors_preset(Control.PRESET_FULL_RECT); hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hud); hud.draw.connect(_draw_hud)


## Called every rendered frame with the current game state.
func show_state(game: Dictionary, delta: float) -> void:
	g = game
	_process_events()
	for i in 2:
		var F: Dictionary = g.F[i]
		var r: Node2D = rigs[i]
		r.position = Vector2(F.x, GROUND - F.y)
		r.z_index = 1 if F.st == "atk" else 0
		r.show_state(F, g.frame, Sim.char_stats(F.c).scale, delta, g.stop > 0)
		var sp = r.strike_point(F)
		if sp != null:
			trails[i].append({"p": sp, "at": Time.get_ticks_msec()})
			if trails[i].size() > 10: trails[i].pop_front()
	# camera: push in on supers and K.O.
	var tz := 1.0
	var tp := Vector2(W / 2, H / 2)
	if g.superFlash > 0:
		var S: Dictionary = g.F[g.superBy]; tz = 1.14; tp = Vector2(S.x, GROUND - S.y - 130)
	elif g.ph == "ko" and g.pt < 60:
		var L: Dictionary = g.F[0] if g.F[0].hp <= 0 else g.F[1]; tz = 1.08; tp = Vector2(L.x, GROUND - 120)
	var k := 1.0 - pow(0.86, delta * 60)
	cam.zoom = cam.zoom.lerp(Vector2(tz, tz), k)
	cam.position = cam.position.lerp(tp, k)
	cam.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake
	shake = maxf(0, shake * pow(0.85, delta * 60) - 0.01)
	for f in fx: f.t += delta * 60
	fx = fx.filter(func(f): return f.t < f.life)
	if banner: banner.t += delta * 60
	if banner and banner.t >= banner.life: banner = {}
	flash = maxf(0, flash - delta * 60)
	below.queue_redraw(); above.queue_redraw(); hud.queue_redraw()


func _process_events() -> void:
	for e in g.ev:
		var key := "%d|%s|%s|%s" % [e.fr, e.k, str(e.get("i", "")), str(e.get("n", ""))]
		if seen_ev.has(key): continue
		seen_ev[key] = e.fr
		if g.frame - e.fr < 30: _spawn_fx(e)
	if seen_ev.size() > 400:
		for key in seen_ev.keys():
			if absi(g.frame - seen_ev[key]) > 120: seen_ev.erase(key)


func _spawn_fx(e: Dictionary) -> void:
	var at := Vector2(e.get("x", 0.0), GROUND - e.get("y", 0.0))
	match e.k:
		"hit", "big":
			var big: bool = e.k == "big"
			for i in (14 if big else 8):
				fx.append({"k": "spark", "p": at, "v": Vector2(randf_range(-6, 6), randf_range(-7, 3)), "t": 0.0, "life": 18.0})
			fx.append({"k": "ring", "p": at, "t": 0.0, "life": 12.0, "big": big})
			for i in (4 if big else 2):
				fx.append({"k": "slash", "p": at, "a": randf() * PI, "t": 0.0, "life": 9.0})
			if e.get("combo", 1) >= 2: fx.append({"k": "combo", "n": e.combo, "i": e.i, "t": 0.0, "life": 60.0})
			shake = 10.0 if big else 5.0
			if big: flash = 3.0
			_snd(e.k)
		"block":
			fx.append({"k": "shield", "p": at, "t": 0.0, "life": 10.0}); _snd("block")
		"pop":
			for i in 10: fx.append({"k": "drop", "p": at, "v": Vector2(randf_range(-4, 4), randf_range(-6, 2)), "t": 0.0, "life": 22.0})
			_snd("block")
		"whiff": _snd("whiff")
		"proj": _snd("proj")
		"wave": _snd("wave")
		"super": _snd("super")
		"round":
			banner = {"text": "FINAL ROUND" if e.get("fin", 0) else "ROUND %d" % e.n, "t": 0.0, "life": 70.0, "hot": false}; _snd("bell")
		"fight": banner = {"text": "FIGHT!", "t": 0.0, "life": 40.0, "hot": true}
		"ko": banner = {"text": "K.O.", "t": 0.0, "life": 150.0, "hot": true}; shake = 14.0; _snd("ko")
		"time": banner = {"text": "TIME!", "t": 0.0, "life": 150.0, "hot": true}; _snd("bell")
		"land": shake = maxf(shake, 4.0)


func _snd(k: String) -> void:
	if sfx: sfx.play(k)


# ---------- world layers ----------
func _draw_below() -> void:
	if g.superFlash > 0:
		below.draw_rect(Rect2(0, 0, W, H), Color(0.04, 0, 0.12, minf(0.7, g.superFlash / 20.0)))
	for F in g.F:
		var sc: float = Sim.char_stats(F.c).scale
		var k := maxf(0.4, 1.0 - F.y / 300.0)
		below.draw_set_transform(Vector2(F.x, GROUND + 2), 0, Vector2(1, 0.2))
		below.draw_circle(Vector2.ZERO, 50 * sc * k, Color(0.08, 0, 0.12, 0.35))
	below.draw_set_transform(Vector2.ZERO)


func _draw_above() -> void:
	for p in g.proj: _draw_proj(p)
	var now := Time.get_ticks_msec()
	for T in trails:
		while T.size() and now - T[0].at > 140: T.pop_front()
		for i in range(1, T.size()):
			var a: float = 1.0 - (now - T[i].at) / 140.0
			var kk: float = float(i) / T.size()
			above.draw_line(T[i - 1].p, T[i].p, Color(1, 0.96, 0.78, 0.55 * a * kk), 6 + 18 * kk * a, true)
			above.draw_line(T[i - 1].p, T[i].p, Color(1, 1, 1, 0.8 * a * kk), 2 + 6 * kk * a, true)
	for f in fx:
		var k: float = f.t / f.life
		match f.k:
			"spark":
				var p: Vector2 = f.p + f.v * f.t + Vector2(0, 0.25 * f.t * f.t)
				above.draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), Color.WHITE if k < 0.3 else Color(1, 0.69, 0.13, 1 - k))
			"ring":
				above.draw_arc(f.p, (60.0 if f.big else 40.0) * k + 8, 0, TAU, 32, Color(1, 0.95, 0.77, 1 - k), 6 * (1 - k))
				if k < 0.45:
					var pts := PackedVector2Array()
					for i in 8:
						var aa := i / 8.0 * TAU
						var rr := 14.0 if i % 2 else 34.0 * (1.4 if f.big else 1.0)
						pts.append(f.p + Vector2(cos(aa), sin(aa)) * rr)
					above.draw_colored_polygon(pts, Color(1, 1, 1, 0.9 - k * 2))
			"slash":
				var d := Vector2(cos(f.a), sin(f.a)) * (34 + 70 * k)
				above.draw_line(f.p - d, f.p + d, Color(1, 1, 1, 1 - k), 5 * (1 - k) + 1, true)
			"shield":
				above.draw_arc(f.p, 30 + k * 10, 0, TAU, 32, Color(0.5, 0.83, 1, 1 - k), 5)
			"drop":
				above.draw_circle(f.p + f.v * f.t + Vector2(0, 0.2 * f.t * f.t), 3, Color(0.75, 0.91, 1, 1 - k))


func _draw_proj(p: Dictionary) -> void:
	var c := Vector2(p.x, GROUND - p.y)
	if p.kind == "bubble":
		var r: float = p.r * (1 + sin(p.t / 4.0) * 0.05)
		above.draw_circle(c, r, Color(0.7, 0.88, 1, 0.3))
		above.draw_circle(c + Vector2(r * 0.15, r * 0.15), r * 0.75, Color(1, 0.55, 0.86, 0.22))
		above.draw_arc(c, r, 0, TAU, 32, Color(1, 1, 1, 0.85), 2.5, true)
		above.draw_circle(c + Vector2(-r * 0.4, -r * 0.45), r * 0.18, Color(1, 1, 1, 0.9))
	else:
		var dir := signf(p.vx)
		for i in 4:
			var rr: float = p.r * (0.5 + i * 0.22) + sin((p.t + i * 5) / 3.0) * 2
			var start := -1.1 if dir > 0 else PI - 1.1
			above.draw_arc(c + Vector2(-dir * i * 14, 0), rr, start, start + 2.2, 16, Color(1, (200 - i * 30) / 255.0, (80 + i * 20) / 255.0, 0.95 - i * 0.2), 6 - i, true)
		if p.sup: above.draw_circle(c, p.r * 0.7, Color(1, 0.94, 0.7, 0.35))


# ---------- HUD ----------
func _text(t: String, pos: Vector2, size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, outline := 6) -> void:
	hud.draw_string_outline(font, pos, t, align, width, size, outline, INK)
	hud.draw_string(font, pos, t, align, width, size, color)


func _draw_hud() -> void:
	var bw := 356.0
	var bh := 22.0
	var top := 24.0
	var cx := W / 2
	for i in 2:
		var F: Dictionary = g.F[i]
		var x := cx + 46 if i else cx - 46 - bw
		var k := maxf(0.0, float(F.hp) / F.max)
		drain[i] = maxf(k, drain[i] - 0.004)
		hud.draw_rect(Rect2(x - 4, top - 4, bw + 8, bh + 8), INK)
		hud.draw_rect(Rect2(x - 2, top - 2, bw + 4, bh + 4), Color(0.85, 0.83, 0.89))
		hud.draw_rect(Rect2(x, top, bw, bh), Color(0.48, 0.05, 0.07))
		var dw: float = bw * drain[i]
		hud.draw_rect(Rect2(x if i else x + bw - dw, top, dw, bh), Color(0.91, 0.2, 0.12))
		var w := bw * k
		hud.draw_rect(Rect2(x if i else x + bw - w, top, w, bh), Color(1, 0.84, 0.2))
		hud.draw_rect(Rect2(x if i else x + bw - w, top, w, 7), Color(1, 0.95, 0.6))
		# portrait + names
		var ps := 50.0
		var px := W - 18 - ps if i else 18.0
		var py := top + bh + 10
		hud.draw_rect(Rect2(px - 3, py - 3, ps + 6, ps + 6), INK)
		hud.draw_rect(Rect2(px, py, ps, ps), Color(0.42, 0.17, 0.71))
		var ht: Texture2D = heads[i]
		var hk := ps * 1.18 / ht.get_height()
		var sw := minf(ht.get_width(), ps / hk)
		var src := Rect2(ht.get_width() / 2.0 - sw / 2, 0, sw, (ps - 2) / hk)
		var dw2 := sw * hk
		# player 2 faces left: mirror around the portrait's centre
		hud.draw_set_transform(Vector2(px + ps / 2, 0), 0, Vector2(-1 if i else 1, 1))
		hud.draw_texture_rect_region(ht, Rect2(-dw2 / 2, py + 2, dw2, ps - 2), src)
		hud.draw_set_transform(Vector2.ZERO)
		var nm: String = (names[i] if names[i] != "" else Chars.get_char(F.c).name) + (" (you)" if i == my_idx else "")
		_text(nm, Vector2(px - 10 - 300 if i else px + ps + 10, py + 26), 24, Color(0.83, 0.94, 1), HORIZONTAL_ALIGNMENT_RIGHT if i else HORIZONTAL_ALIGNMENT_LEFT, 300 if i else -1, 6)
		_text(Chars.get_char(F.c).name.to_upper(), Vector2(px - 10 - 300 if i else px + ps + 10, py + 44), 13, Color(1, 0.82, 0.4), HORIZONTAL_ALIGNMENT_RIGHT if i else HORIZONTAL_ALIGNMENT_LEFT, 300 if i else -1, 4)
		for r in 3:
			var mx := cx + 58 + r * 22 if i else cx - 58 - r * 22
			hud.draw_circle(Vector2(mx, top + bh + 16), 8, INK)
			hud.draw_circle(Vector2(mx, top + bh + 16), 6, Color(1, 0.81, 0.18) if r < F.wins else Color(0.23, 0.16, 0.29))
		# super gauge
		var mw := 190.0
		var mx2 := W - 22 - mw if i else 22.0
		var my := H - 30.0
		var full: bool = F.m >= 100
		hud.draw_rect(Rect2(mx2 - 3, my - 3, mw + 6, 20), INK)
		hud.draw_rect(Rect2(mx2, my, mw, 14), Color(0.09, 0.23, 0.27))
		var mm: float = mw * F.m / 100.0
		var mc := (Color.WHITE if g.frame % 16 < 8 else Color(1, 0.82, 0.23)) if full else Color(1, 0.6, 0.1)
		hud.draw_rect(Rect2(mx2 + mw - mm if i else mx2, my, mm, 14), mc)
		_text("SUPER!  DOWN+SP" if full else "SUPER", Vector2(W - 24 - 300 if i else 24.0, my - 6), 15, Color.WHITE if full else Color(0.75, 0.9, 1), HORIZONTAL_ALIGNMENT_RIGHT if i else HORIZONTAL_ALIGNMENT_LEFT, 300 if i else -1, 4)
	# KO badge + timer
	var danger: bool = g.F[0].hp < g.F[0].max / 4 or g.F[1].hp < g.F[1].max / 4
	hud.draw_rect(Rect2(cx - 41, top - 11, 82, 44), INK)
	hud.draw_rect(Rect2(cx - 38, top - 8, 76, 38), Color(0.85, 0.62, 0.18))
	hud.draw_rect(Rect2(cx - 34, top - 4, 68, 30), Color(1, 0.16, 0.1) if danger and g.frame % 30 < 15 else Color(0.6, 0.06, 0.06))
	_text("KO", Vector2(cx - 40, top + 20), 28, Color(1, 0.91, 0.66), HORIZONTAL_ALIGNMENT_CENTER, 80, 4)
	var secs := "%02d" % maxi(0, ceili(g.timer / 60.0))
	_text(secs, Vector2(cx - 60, top + 86), 52, Color(1, 0.55, 0.15) if g.timer < 600 else Color(1, 0.93, 0.6), HORIZONTAL_ALIGNMENT_CENTER, 120, 8)
	if ping_ms > 0:
		var pc := Color(0.24, 0.86, 0.52) if ping_ms < 120 else (Color(1, 0.82, 0.4) if ping_ms < 220 else Color(1, 0.42, 0.24))
		_text("PING %d ms" % int(ping_ms), Vector2(cx - 80, top + 106), 12, pc, HORIZONTAL_ALIGNMENT_CENTER, 160, 3)
	if waiting:
		_text("WAITING FOR OPPONENT...", Vector2(0, H / 2 + 110), 26, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, W, 6)
	# combo counters (latest per side)
	for side in 2:
		for f in fx:
			if f.k == "combo" and f.i == side:
				var a := minf(1.0, (1.0 - f.t / f.life) * 3)
				_text("%d HITS" % f.n, Vector2(W - 40 - 300 if side else 40.0, 190), 40, Color(1, 0.69, 0.13, a), HORIZONTAL_ALIGNMENT_RIGHT if side else HORIZONTAL_ALIGNMENT_LEFT, 300 if side else -1, 7)
	if g.superFlash > 0:
		_text(Chars.get_char(g.F[g.superBy].c).super, Vector2(0, 190), 52, Color(0.85, 0.95, 1), HORIZONTAL_ALIGNMENT_CENTER, W, 9)
	if banner:
		var big: bool = banner.hot
		var s: float = 1.6 - banner.t * 0.075 if banner.t < 8 else 1.0
		var size := int((104 if big else 76) * s)
		_text(banner.text, Vector2(0, H / 2 + 10 + size * 0.35), size, Color(1, 0.3, 0.15) if big else Color(0.85, 0.95, 1), HORIZONTAL_ALIGNMENT_CENTER, W, 12)
	if g.ph == "ko" and g.pt > 110:
		var rw: int = g.roundWinner
		var txt: String = "DRAW" if rw < 0 else (names[rw] if names[rw] != "" else Chars.get_char(g.F[rw].c).name) + " wins!"
		_text(txt, Vector2(0, H / 2 + 74), 40, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, W, 7)
	if flash > 0:
		hud.draw_rect(Rect2(0, 0, W, H), Color(1, 0.98, 0.92, flash * 0.07))
	if g.ph == "intro" and g.round == 1 and g.pt <= 90:
		_draw_versus()


func _draw_versus() -> void:
	var t: float = g.pt
	var k := minf(1.0, t / 14.0)
	var fade := minf(1.0, (t - 78) / 12.0) if t > 78 else 0.0
	var a := 1.0 - fade
	hud.draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(W / 2 + 60, 0), Vector2(W / 2 - 60, H), Vector2(0, H)]), Color(0.11, 0.23, 0.6, a))
	hud.draw_colored_polygon(PackedVector2Array([Vector2(W / 2 + 60, 0), Vector2(W, 0), Vector2(W, H), Vector2(W / 2 - 60, H)]), Color(0.6, 0.06, 0.08, a))
	for i in 14:
		var yy := fmod(i * 47 + t * 9, H)
		hud.draw_line(Vector2(0, yy), Vector2(W, yy - 120), Color(1, 1, 1, 0.08 * a), 3)
	hud.draw_line(Vector2(W / 2 + 60, 0), Vector2(W / 2 - 60, H), Color(INK, a), 10)
	hud.draw_line(Vector2(W / 2 + 60, 0), Vector2(W / 2 - 60, H), Color(1, 0.82, 0.23, a), 4)
	var ease := 1.0 - pow(1.0 - k, 3)
	for i in 2:
		var bt: Texture2D = busts[i]
		var h := H * 0.86
		var w := bt.get_width() * h / bt.get_height()
		var off := (1.0 - ease) * W * 0.6
		var x := 40 - off if i == 0 else W - 40 + off - w
		hud.draw_set_transform(Vector2(x + w / 2, 0), 0, Vector2(-1 if i else 1, 1))
		hud.draw_texture_rect(bt, Rect2(-w / 2, H - h, w, h), false, Color(1, 1, 1, a))
		hud.draw_set_transform(Vector2.ZERO)
		var F: Dictionary = g.F[i]
		var nm: String = names[i] if names[i] != "" else Chars.get_char(F.c).name
		_text(nm, Vector2(W - 30 - 400 if i else 30.0, H - 70), 40, Color(0.83, 0.94, 1, a), HORIZONTAL_ALIGNMENT_RIGHT if i else HORIZONTAL_ALIGNMENT_LEFT, 400 if i else -1, 7)
		_text(Chars.get_char(F.c).name.to_upper(), Vector2(W - 30 - 400 if i else 30.0, H - 34), 26, Color(1, 0.75, 0.3, a), HORIZONTAL_ALIGNMENT_RIGHT if i else HORIZONTAL_ALIGNMENT_LEFT, 400 if i else -1, 5)
	var vs := 1.0 + maxf(0, 0.8 - t / 20.0)
	_text("VS", Vector2(0, H / 2 + 10 + 40 * vs), int(110 * vs), Color(1, 0.45, 0.2, a), HORIZONTAL_ALIGNMENT_CENTER, W, 12)
