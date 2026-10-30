extends SceneTree
## Headless parity check: godot --headless -s res://tests/parity_run.gd -- <frames> <seed>
## Must print exactly what tools/parity/js_run.mjs prints.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var frames := int(args[0]) if args.size() > 0 else 6000
	var x := int(args[1]) if args.size() > 1 else 42
	var D := [0, 1, 2, 4, 8, 9, 10, 5, 6]
	var st := [{"b": 0, "p": 0, "k": 0, "s": 0}, {"b": 0, "p": 0, "k": 0, "s": 0}]
	var g := Sim.new_game("bubbles", "preacher", "plaza", 777)
	var out := PackedStringArray()
	for f in frames:
		for s in st:
			x = (x * 16807) % 2147483647
			if x % 9 == 0:
				x = (x * 16807) % 2147483647
				s.b = D[x % 9]
			x = (x * 16807) % 2147483647
			var q := x % 40
			if q == 0: s.p = (s.p + 1) % 16
			elif q == 1: s.k = (s.k + 1) % 16
			elif q == 2: s.s = (s.s + 1) % 16
		Sim.step(g, [st[0].duplicate(), st[1].duplicate()])
		if f % 30 == 29:
			var parts := [g.frame, g.ph, g.pt, g.timer, g.rng, g.round, g.stop, g.superFlash]
			for F in g.F:
				parts.append_array([F.x, F.y, F.vx, F.vy, F.hp, F.m, F.st, F.t, F.mv, F.stun, F.wins, F.f, F.inv, F.combo, F.presses.size()])
			for p in g.proj:
				parts.append_array([p.x, p.y, p.vx, p.life, p.o])
			var s := PackedStringArray()
			for v in parts:
				if v is int or v is float: s.append("%.6f" % (0.0 if v == 0 else v))
				elif v == null: s.append("null")
				else: s.append(str(v))
			out.append(" ".join(s))
	print("\n".join(out))
	quit()
