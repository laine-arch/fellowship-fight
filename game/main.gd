extends Node
## Fellowship Fighter: screens and game flow (title → lobby → select → fight → result).
## Offline practice runs the sim locally against CpuBrain; online matches go through the
## lobby server and run with Rollback.

const DEFAULT_SERVER := "ws://localhost:8080"
const INK := Color(0.11, 0.06, 0.09)
const GOLD := Color(1, 0.82, 0.23)

var display_font: Font
var theme_ui: Theme
var ui: Control
var screens := {}
var fight_view: FightView
var touch: TouchControls
var input: LocalInput
var sfx: Sfx
var lobby: LobbyClient
var cfg := ConfigFile.new()

var nick := ""
var stats := {"w": 0, "l": 0, "rw": 0, "rl": 0}
var mode := ""            # "", "cpu", "net"
var game := {}
var names := ["", ""]
var my_idx := 0
var cpu: CpuBrain
var rb: Rollback
var acc := 0.0
var paused := false
var result_shown := false
var searching := false
var match_info := {}      # {id, side, opp}
var sel := {}             # select-screen state
var lobby_data := {"players": [], "board": []}
var server_url := DEFAULT_SERVER
var lobby_name := "main"


func _ready() -> void:
	cfg.load("user://settings.cfg")
	nick = cfg.get_value("player", "nick", "")
	stats = cfg.get_value("player", "stats", stats)
	if not cfg.has_section_key("player", "id"):
		cfg.set_value("player", "id", (str(randi()) + str(Time.get_unix_time_from_system())).md5_text().substr(0, 24))
		cfg.save("user://settings.cfg")
	_read_link_options()
	display_font = load("res://art/fonts/LuckiestGuy-Regular.ttf")
	theme_ui = _make_theme()
	input = LocalInput.new(); add_child(input)
	sfx = Sfx.new(); add_child(sfx)
	lobby = LobbyClient.new(); add_child(lobby)
	lobby.message.connect(_on_server)
	lobby.connected.connect(func(): _refresh_lobby())
	lobby.disconnected.connect(func(): _refresh_lobby())
	fight_view = FightView.new(); add_child(fight_view); fight_view.sfx = sfx; fight_view.visible = false
	var layer := CanvasLayer.new(); layer.layer = 5; add_child(layer)
	touch = TouchControls.new(); touch.input = input; touch.visible = false
	layer.add_child(touch)
	var ui_layer := CanvasLayer.new(); ui_layer.layer = 10; add_child(ui_layer)
	ui = Control.new(); ui.set_anchors_preset(Control.PRESET_FULL_RECT); ui.theme = theme_ui; ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(ui)
	_build_title(); _build_lobby(); _build_select(); _build_result(); _build_pause()
	show_screen("title")


# Options from the page link, e.g. https://…/?lobby=youth&server=wss://my-server.onrender.com
func _read_link_options() -> void:
	server_url = ProjectSettings.get_setting("fellowship/server_url", DEFAULT_SERVER)
	if OS.has_feature("web"):
		var q = JavaScriptBridge.eval("window.location.search", true)
		if q is String:
			for part in q.trim_prefix("?").split("&", false):
				var kv: PackedStringArray = part.split("=")
				if kv.size() == 2 and kv[0] == "server": server_url = kv[1].uri_decode()
				if kv.size() == 2 and kv[0] == "lobby": lobby_name = kv[1].uri_decode()


# ---------------- theme & helpers ----------------
func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 18
	var btn := StyleBoxFlat.new()
	btn.bg_color = Color(1, 0.75, 0.2); btn.set_corner_radius_all(12); btn.border_color = Color(0.66, 0.42, 0); btn.border_width_bottom = 5
	btn.content_margin_left = 18; btn.content_margin_right = 18; btn.content_margin_top = 10; btn.content_margin_bottom = 10
	var hov := btn.duplicate(); hov.bg_color = Color(1, 0.84, 0.4)
	var prs := btn.duplicate(); prs.border_width_bottom = 2; prs.content_margin_top = 13
	var dis := btn.duplicate(); dis.bg_color = Color(0.5, 0.45, 0.35)
	for st in [["normal", btn], ["hover", hov], ["pressed", prs], ["disabled", dis], ["focus", hov]]:
		t.set_stylebox(st[0], "Button", st[1])
	t.set_font("font", "Button", display_font); t.set_font_size("font_size", "Button", 20)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]: t.set_color(c, "Button", Color(0.1, 0.07, 0))
	t.set_color("font_disabled_color", "Button", Color(0.25, 0.22, 0.2))
	var le := StyleBoxFlat.new(); le.bg_color = Color(0.12, 0.14, 0.21); le.set_corner_radius_all(10); le.set_border_width_all(2); le.border_color = Color(0.17, 0.19, 0.31)
	le.content_margin_left = 14; le.content_margin_top = 10; le.content_margin_bottom = 10
	t.set_stylebox("normal", "LineEdit", le); t.set_stylebox("focus", "LineEdit", le)
	t.set_font_size("font_size", "LineEdit", 22)
	var panel := StyleBoxFlat.new(); panel.bg_color = Color(0.08, 0.1, 0.15, 0.94); panel.set_corner_radius_all(14); panel.set_border_width_all(1); panel.border_color = Color(0.17, 0.19, 0.31)
	panel.content_margin_left = 16; panel.content_margin_right = 16; panel.content_margin_top = 12; panel.content_margin_bottom = 12
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_color("font_color", "Label", Color(0.95, 0.94, 0.92))
	return t


func _alt(b: Button) -> Button:
	var s := StyleBoxFlat.new(); s.bg_color = Color(0.12, 0.14, 0.21); s.set_corner_radius_all(12); s.border_color = Color(0.04, 0.05, 0.08); s.border_width_bottom = 5
	s.content_margin_left = 18; s.content_margin_right = 18; s.content_margin_top = 10; s.content_margin_bottom = 10
	b.add_theme_stylebox_override("normal", s); b.add_theme_stylebox_override("hover", s); b.add_theme_stylebox_override("focus", s)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]: b.add_theme_color_override(c, Color(0.95, 0.94, 0.92))
	return b


func _button(text: String, cb: Callable, alt := false) -> Button:
	var b := Button.new(); b.text = text; b.pressed.connect(func(): sfx.play("whiff"); cb.call())
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return _alt(b) if alt else b


func _title(text: String, size := 54) -> Label:
	var l := Label.new(); l.text = text
	l.add_theme_font_override("font", display_font); l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", GOLD); l.add_theme_color_override("font_outline_color", INK); l.add_theme_constant_override("outline_size", 12)
	return l


func _note(text: String) -> Label:
	var l := Label.new(); l.text = text; l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 14); l.add_theme_color_override("font_color", Color(0.6, 0.63, 0.71))
	return l


func _screen(id: String) -> VBoxContainer:
	var root := Control.new(); root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new(); bg.set_anchors_preset(Control.PRESET_FULL_RECT); bg.color = Color(0.04, 0.05, 0.08, 0.97); root.add_child(bg)
	var scroll := ScrollContainer.new(); scroll.set_anchors_preset(Control.PRESET_FULL_RECT); scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var margin := MarginContainer.new(); margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right"]: margin.add_theme_constant_override("margin_" + side, 90)
	margin.add_theme_constant_override("margin_top", 18); margin.add_theme_constant_override("margin_bottom", 18)
	scroll.add_child(margin)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 10); margin.add_child(v)
	ui.add_child(root)
	screens[id] = root
	return v


func show_screen(id: String) -> void:
	for k in screens: screens[k].visible = k == id
	var fighting := id == ""
	fight_view.visible = fighting or id == "result" or id == "pause"
	touch.visible = fighting and (DisplayServer.is_touchscreen_available() or OS.has_feature("web_android") or OS.has_feature("web_ios"))
	if pause_btn: pause_btn.visible = fighting


func _toast(text: String) -> void:
	var l := Label.new(); l.text = text
	l.add_theme_font_size_override("font_size", 16)
	var p := PanelContainer.new(); p.add_child(l); ui.add_child(p)
	p.position = Vector2(ui.size.x / 2 - 150, 14)
	get_tree().create_timer(2.6).timeout.connect(p.queue_free)


func _save() -> void:
	cfg.set_value("player", "nick", nick); cfg.set_value("player", "stats", stats); cfg.save("user://settings.cfg")


# ---------------- title ----------------
var nick_edit: LineEdit

func _build_title() -> void:
	var v := _screen("title")
	v.add_child(_title("FELLOWSHIP\nFIGHTER", 60))
	v.add_child(_note("Street brawler · Best of 5 · Live lobby"))
	var card := PanelContainer.new(); v.add_child(card)
	var cv := VBoxContainer.new(); cv.add_theme_constant_override("separation", 10); card.add_child(cv)
	nick_edit = LineEdit.new(); nick_edit.placeholder_text = "Your fighter name"; nick_edit.max_length = 16; nick_edit.text = nick
	cv.add_child(nick_edit)
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 10); cv.add_child(row)
	row.add_child(_button("Enter lobby", _go_lobby))
	row.add_child(_button("Practice vs CPU", _go_cpu, true))
	cv.add_child(_note("Move: drag the left side of the screen (arrows/WASD).  Attack: PUNCH, KICK (J/K).  Combos: P,P,K · K,K · down+P, down+K.\nSPECIAL (L) = projectile · toward+SP = rush · up+SP = uppercut · full bar: down+SP = SUPER."))


func _take_nick() -> bool:
	var n := nick_edit.text.strip_edges().substr(0, 16)
	if n == "":
		_toast("Pick a fighter name first"); return false
	nick = n; _save(); return true


func _go_lobby() -> void:
	if not _take_nick(): return
	if not lobby.is_open: lobby.open(server_url, nick, lobby_name, cfg.get_value("player", "id"))
	show_screen("lobby"); _refresh_lobby()


func _go_cpu() -> void:
	if not _take_nick(): return
	_stop_search()
	mode = "cpu"
	_open_select("CPU")


# ---------------- lobby ----------------
var lobby_status: Label
var find_btn: Button
var live_box: VBoxContainer
var board_box: VBoxContainer

func _build_lobby() -> void:
	var v := _screen("lobby")
	v.add_child(_title("THE LOBBY", 44))
	lobby_status = _note("Connecting…"); v.add_child(lobby_status)
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 10); v.add_child(row)
	find_btn = _button("Find a match", _toggle_search); row.add_child(find_btn)
	row.add_child(_button("Practice vs CPU", _go_cpu, true))
	row.add_child(_button("Back", func(): _stop_search(); show_screen("title"), true))
	var cols := HBoxContainer.new(); cols.add_theme_constant_override("separation", 10); v.add_child(cols)
	for which in ["In lobby now", "All-time"]:
		var p := PanelContainer.new(); p.size_flags_horizontal = Control.SIZE_EXPAND_FILL; cols.add_child(p)
		var pv := VBoxContainer.new(); p.add_child(pv)
		var h := _title(which.to_upper(), 20); pv.add_child(h)
		var box := VBoxContainer.new(); pv.add_child(box)
		if which == "In lobby now": live_box = box
		else: board_box = box


func _row(cells: Array, me := false) -> HBoxContainer:
	var r := HBoxContainer.new()
	for i in cells.size():
		var l := Label.new(); l.text = str(cells[i])
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL if i == 1 else Control.SIZE_SHRINK_BEGIN
		l.custom_minimum_size.x = 0 if i == 1 else 46
		l.add_theme_font_size_override("font_size", 15)
		if me: l.add_theme_color_override("font_color", GOLD)
		r.add_child(l)
	return r


func _refresh_lobby() -> void:
	if lobby_status == null: return
	for c in live_box.get_children(): c.queue_free()
	for c in board_box.get_children(): c.queue_free()
	if not lobby.is_open:
		lobby_status.text = "Connecting to the lobby server… (practice vs CPU works offline)"
		return
	var players: Array = lobby_data.players
	var searching_n := players.filter(func(p): return p.st == "q").size()
	var fighting_n := players.filter(func(p): return p.st == "play").size()
	lobby_status.text = ("You're the only one here. Share the link to bring friends in." if players.size() <= 1
		else "%d fighters · %d searching · %d fighting" % [players.size(), searching_n, fighting_n])
	live_box.add_child(_row(["#", "Fighter", "Status", "W", "L"]))
	var sorted := players.duplicate()
	sorted.sort_custom(func(a, b): return a.w > b.w or (a.w == b.w and a.l < b.l))
	for i in sorted.size():
		var p: Dictionary = sorted[i]
		var stt := "Searching" if p.st == "q" else ("Fighting" if p.st == "play" else "Idle")
		live_box.add_child(_row([i + 1, p.n, stt, p.w, p.l], p.n == nick))
	board_box.add_child(_row(["#", "Fighter", "W", "L", "Rds"]))
	var board: Array = lobby_data.board
	if board.is_empty(): board_box.add_child(_note("No online matches recorded yet. Win one!"))
	for i in board.size():
		var b: Dictionary = board[i]
		board_box.add_child(_row([i + 1, b.name, b.w, b.l, "%d-%d" % [b.rw, b.rl]]))


func _toggle_search() -> void:
	if searching: _stop_search()
	else:
		if not lobby.is_open: _toast("Still connecting to the lobby…"); return
		searching = true; lobby.send({"t": "queue"}); find_btn.text = "Cancel search"
		lobby_status.text = "Searching for an opponent…"


func _stop_search() -> void:
	if searching: lobby.send({"t": "unqueue"})
	searching = false
	if find_btn: find_btn.text = "Find a match"


func _on_server(m: Dictionary) -> void:
	match m.t:
		"lobby":
			lobby_data = m; _refresh_lobby()
		"match":
			searching = false; find_btn.text = "Find a match"
			match_info = m; mode = "net"; my_idx = int(m.side)
			_toast("Matched with %s!" % m.opp)
			_open_select(str(m.opp))
		"oppPick":
			if screens.select.visible:
				sel.op = m.c if Sim.CHARS.has(m.c) else null; sel.op_ready = m.ready; _render_select()
		"go":
			if mode == "net" and screens.select.visible:
				var c: Array = m.c
				var stage_id: String = Chars.STAGES[int(m.seed) % Chars.STAGES.size()].id
				_start_fight(str(c[0]), str(c[1]), stage_id, int(m.seed))
		"in":
			if rb: rb.receive(m)
		"rematch":
			_open_select(str(match_info.get("opp", "Opponent")))
		"oppRematch":
			_toast("%s wants a rematch!" % match_info.get("opp", "Opponent"))
		"oppLeft":
			_toast("Opponent left the match")
			_end_net_match()


func _end_net_match() -> void:
	mode = ""; rb = null; match_info = {}
	paused = false; screens.pause.visible = false
	show_screen("lobby"); _refresh_lobby()


# ---------------- character select ----------------
var grid: GridContainer
var vs_me: Label
var vs_op: Label
var ready_btn: Button
var sel_note: Label

func _build_select() -> void:
	var v := _screen("select")
	v.add_child(_title("CHOOSE YOUR FIGHTER", 38))
	var vs := HBoxContainer.new(); vs.add_theme_constant_override("separation", 12); v.add_child(vs)
	for who in ["me", "op"]:
		var p := PanelContainer.new(); p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sb := StyleBoxFlat.new(); sb.bg_color = Color(0.11, 0.23, 0.6) if who == "me" else Color(0.6, 0.06, 0.08)
		sb.set_border_width_all(3); sb.border_color = Color(0.91, 0.89, 0.95); sb.content_margin_left = 12; sb.content_margin_top = 8; sb.content_margin_bottom = 8; sb.content_margin_right = 12
		p.add_theme_stylebox_override("panel", sb)
		var l := Label.new(); l.add_theme_font_size_override("font_size", 16); p.add_child(l); vs.add_child(p)
		if who == "me": vs_me = l
		else: vs_op = l
		if who == "me": vs.add_child(_title("VS", 34))
	grid = GridContainer.new(); grid.columns = 4; grid.add_theme_constant_override("h_separation", 10); v.add_child(grid)
	for c in Chars.LIST:
		var b := TextureButton.new(); b.custom_minimum_size = Vector2(150, 150)
		b.texture_normal = Chars.head(c.id); b.ignore_texture_size = true; b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		var holder := PanelContainer.new()
		var sb := StyleBoxFlat.new(); sb.bg_color = Color(0.42, 0.17, 0.71); sb.set_border_width_all(4); sb.border_color = Color(0.91, 0.89, 0.95)
		holder.add_theme_stylebox_override("panel", sb); holder.set_meta("id", c.id); holder.set_meta("sb", sb)
		var vb := VBoxContainer.new(); holder.add_child(vb); vb.add_child(b)
		var nl := Label.new(); nl.text = c.name.to_upper(); nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nl.add_theme_font_override("font", display_font); nl.add_theme_color_override("font_color", Color(1, 0.88, 0.29)); vb.add_child(nl)
		b.pressed.connect(func(): if not sel.get("ready", false): sel.me = c.id; sfx.play("whiff"); _render_select(); _send_pick())
		grid.add_child(holder)
	for i in Chars.LOCKED_SLOTS:
		var lock := PanelContainer.new(); lock.custom_minimum_size = Vector2(150, 180)
		var sb := StyleBoxFlat.new(); sb.bg_color = Color(0.2, 0.1, 0.36); sb.set_border_width_all(4); sb.border_color = Color(0.5, 0.45, 0.6)
		lock.add_theme_stylebox_override("panel", sb)
		var q := _title("?", 56); q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; q.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; lock.add_child(q)
		grid.add_child(lock)
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 10); v.add_child(row)
	ready_btn = _button("Ready!", _on_ready); row.add_child(ready_btn)
	row.add_child(_button("Leave", _leave_select, true))
	sel_note = _note(""); v.add_child(sel_note)


func _open_select(op_name: String) -> void:
	sel = {"me": cfg.get_value("player", "last_char") if cfg.has_section_key("player", "last_char") else null, "op": null, "ready": false, "op_ready": mode == "cpu", "op_name": op_name}
	sel_note.text = "Practice match against the computer. Results don't count." if mode == "cpu" else "Best of 5 rounds. The match starts when both players are ready."
	result_shown = false
	show_screen("select"); _render_select()
	if mode == "net" and sel.me: _send_pick()


func _render_select() -> void:
	for h in grid.get_children():
		if not h.has_meta("id"): continue
		var sb: StyleBoxFlat = h.get_meta("sb")
		var id: String = h.get_meta("id")
		sb.border_color = GOLD if id == sel.me else (Color(1, 0.3, 0.24) if id == sel.op else Color(0.91, 0.89, 0.95))
	vs_me.text = "%s (you)\n%s%s" % [nick, Chars.get_char(sel.me).name.to_upper() if sel.me else "Choosing…", "\n✓ READY" if sel.ready else ""]
	vs_op.text = "%s\n%s%s" % [sel.op_name, Chars.get_char(sel.op).name.to_upper() if sel.op else "Choosing…", "\n✓ READY" if sel.op_ready else ""]
	ready_btn.disabled = sel.me == null or sel.ready
	ready_btn.text = "Waiting…" if sel.ready else "Ready!"


func _send_pick() -> void:
	if mode == "net": lobby.send({"t": "pick", "c": sel.me, "ready": sel.ready})


func _on_ready() -> void:
	if sel.me == null: return
	sel.ready = true
	cfg.set_value("player", "last_char", sel.me); _save()
	_render_select()
	if mode == "cpu":
		var others := Chars.LIST.filter(func(c): return c.id != sel.me)
		sel.op = others.pick_random().id if others.size() else sel.me
		_render_select()
		get_tree().create_timer(0.5).timeout.connect(func(): _start_fight(sel.me, sel.op, Chars.STAGES.pick_random().id, randi() % 2147483647))
	else:
		_send_pick()


func _leave_select() -> void:
	if mode == "net":
		lobby.send({"t": "leave"}); _end_net_match()
	else:
		mode = ""; show_screen("lobby" if lobby.is_open else "title")


# ---------------- fight ----------------
func _start_fight(c0: String, c1: String, stage_id: String, seed: int) -> void:
	game = Sim.new_game(c0, c1, stage_id, seed)
	if mode == "cpu":
		my_idx = 0; names = [nick, "CPU"]; cpu = CpuBrain.new()
	else:
		names = [nick, sel.op_name] if my_idx == 0 else [sel.op_name, nick]
		rb = Rollback.new(game, my_idx)
	input.reset_counters()
	acc = 0.0; paused = false; result_shown = false
	fight_view.setup(game, names, my_idx)
	show_screen("")


func _process(delta: float) -> void:
	if not fight_view.visible or game.is_empty(): return
	if mode == "cpu":
		if not paused:
			acc = minf(acc + delta, 0.2)
			while acc >= 1.0 / 60.0:
				acc -= 1.0 / 60.0
				Sim.step(game, [input.snapshot(), cpu.think(game, game.F[1], game.F[0]).duplicate()])
		if game.ph == "over" and game.pt > 60 and not result_shown:
			result_shown = true
			_show_result(game.winner == 0, "%d – %d vs CPU" % [game.F[0].wins, game.F[1].wins])
	elif mode == "net" and rb:
		var out := rb.tick(delta, input.snapshot())
		lobby.send(out)
		game = rb.game
		fight_view.ping_ms = rb.ping
		fight_view.waiting = rb.stall > 0.4
		if rb.over_confirmed() and not result_shown:
			result_shown = true
			var won: bool = game.winner == my_idx
			var a: int = game.F[my_idx].wins
			var b: int = game.F[1 - my_idx].wins
			lobby.send({"t": "result", "won": won, "a": a, "b": b})
			stats.w += 1 if won else 0; stats.l += 0 if won else 1; stats.rw += a; stats.rl += b; _save()
			_show_result(won, "%d – %d vs %s" % [a, b, sel.op_name])
	fight_view.show_state(game, delta)


# ---------------- result & pause ----------------
var pause_btn: Button
var res_title: Label
var res_sub: Label
var rematch_btn: Button

func _build_result() -> void:
	var v := _screen("result")
	(screens.result.get_child(0) as ColorRect).color = Color(0, 0, 0, 0.75)
	res_title = _title("YOU WIN!", 64); res_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; v.add_child(res_title)
	res_sub = _note(""); res_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; v.add_child(res_sub)
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 10); v.add_child(row)
	rematch_btn = _button("Rematch", _rematch); row.add_child(rematch_btn)
	row.add_child(_button("Back to lobby", _back_from_result, true))


func _show_result(won: bool, sub: String) -> void:
	res_title.text = "YOU WIN!" if won else "YOU LOSE"
	res_sub.text = sub
	rematch_btn.disabled = false; rematch_btn.text = "Rematch"
	show_screen("result")


func _rematch() -> void:
	if mode == "cpu": _open_select("CPU")
	elif mode == "net":
		lobby.send({"t": "rematch"}); rematch_btn.disabled = true; rematch_btn.text = "Waiting…"


func _back_from_result() -> void:
	if mode == "net":
		lobby.send({"t": "leave"}); _end_net_match()
	else:
		mode = ""; game = {}; show_screen("lobby" if lobby.is_open else "title")


func _build_pause() -> void:
	pause_btn = Button.new(); pause_btn.text = "II"; pause_btn.custom_minimum_size = Vector2(44, 30)
	_alt(pause_btn); pause_btn.add_theme_font_size_override("font_size", 14)
	pause_btn.pressed.connect(_toggle_pause)
	ui.add_child(pause_btn)
	# bottom centre, between the super gauges (the top centre holds the KO badge and timer)
	pause_btn.set_anchors_preset(Control.PRESET_CENTER_BOTTOM); pause_btn.offset_left = -22; pause_btn.offset_right = 22; pause_btn.offset_top = -40; pause_btn.offset_bottom = -8
	var v := _screen("pause")
	(screens.pause.get_child(0) as ColorRect).color = Color(0, 0, 0, 0.6)
	v.add_child(_title("PAUSED", 48))
	v.add_child(_note("Online matches keep running while this menu is open."))
	v.add_child(_button("Resume", _toggle_pause))
	v.add_child(_button("Quit match", _quit_match, true))


func _toggle_pause() -> void:
	paused = not paused
	screens.pause.visible = paused
	pause_btn.visible = not paused
	if not paused: show_screen("")


func _quit_match() -> void:
	paused = false; screens.pause.visible = false
	if mode == "net":
		lobby.send({"t": "leave"}); _end_net_match()
	else:
		mode = ""; game = {}; show_screen("lobby" if lobby.is_open else "title")


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.physical_keycode == KEY_ESCAPE and (mode == "cpu" or mode == "net") and not game.is_empty() and game.ph != "over":
		_toggle_pause()
