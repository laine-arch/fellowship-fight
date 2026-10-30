extends SceneTree
## Online test bot: godot --headless -s res://tests/net_bot.gd -- <server_url> <name> <delay_ms> <seconds>
## Joins the lobby, queues, picks a fighter, mashes random inputs and prints its checkpoints so two
## bots' runs can be compared (they must agree on every confirmed state hash).

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var url: String = args[0]
	var nm: String = args[1]
	var delay := int(args[2])
	var seconds := float(args[3])
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.lobby.debug_delay_ms = delay
	main.cfg.set_value("player", "id", "bot-" + nm.to_lower() + "-0001")
	main.server_url = url
	main.nick_edit.text = nm
	main._go_lobby()
	while not main.lobby.is_open: await process_frame
	await create_timer(0.3).timeout
	main._toggle_search()
	while main.mode != "net": await process_frame
	main.sel.me = "bubbles" if nm.ends_with("A") else "preacher"
	main._on_ready()
	while main.rb == null: await process_frame
	print("[%s] fighting as side %d" % [nm, main.my_idx])
	if args.size() > 4 and args[4] == "quick":
		# same change on both phones before frame 0: a short deciding round
		for F in main.rb.game.F: F.wins = 2
		main.rb.game.timer = 400
		main.rb.game.F[1].hp = 1
	var D := [0, 1, 2, 4, 8, 9, 10, 5, 6]
	var t0 := Time.get_ticks_msec()
	var done := false
	while Time.get_ticks_msec() - t0 < seconds * 1000 and not main.result_shown:
		if randf() < 0.1: main.input.dir_keys = D.pick_random()
		var r := randf()
		if r < 0.05: main.input.press("p")
		elif r < 0.09: main.input.press("k")
		elif r < 0.1: main.input.press("s")
		await process_frame
	await create_timer(1.0).timeout  # let queued messages (incl. the result) go out
	var rb: Rollback = main.rb if main.rb else null
	var hs := []
	if rb:
		var keys: Array = rb.my_hash.keys(); keys.sort()
		for k in keys.slice(-4): hs.append("%d:%d" % [k, rb.my_hash[k]])
		print("[%s] f=%d rmax=%d ping=%d desyncs=%d ph=%s wins=%d-%d result=%s hashes=%s" % [nm, rb.f, rb.rmax, int(rb.ping), rb.desyncs, main.game.ph, main.game.F[0].wins, main.game.F[1].wins, main.result_shown, " ".join(hs)])
	quit()
