extends SceneTree
## Plays a scripted CPU match and saves screenshots to /tmp/ff_*.png (run under xvfb-run).

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/ff_%s.png" % name)

func wait(sec: float) -> void:
	await create_timer(sec).timeout

func _init() -> void:
	root.size = Vector2i(960, 540)
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await wait(0.5)
	await shot("title")
	main.nick_edit.text = "Tester"
	main._go_cpu()
	await wait(0.3)
	main.sel.me = "bubbles"; main._render_select()
	await shot("select")
	main._on_ready()
	await wait(1.2)
	await shot("vs")
	await wait(2.4)
	main.game.F[0].x = 420.0; main.game.F[1].x = 500.0
	main.cpu = null
	main.cpu = CpuBrain.new()
	for b in ["p", "p", "k"]:
		main.input.press(b); await wait(0.11)
	await shot("combo")
	await wait(1.5)
	main.game.F[0].x = 300.0; main.game.F[1].x = 660.0; main.game.F[0].m = 100
	main.cpu = CpuBrain.new(); main.cpu.hold = 9999
	await wait(0.4)
	main.input.dir_keys = Sim.DIR_D; main.input.press("s"); await wait(0.1); main.input.dir_keys = 0
	await wait(0.3)
	await shot("super")
	await wait(0.6)
	await shot("super2")
	main.game.F[0].wins = 2; main.game.F[1].hp = 0
	await wait(7.0)
	await shot("result")
	print("ph=", main.game.get("ph"), " wins=", main.game.F[0].wins, "-", main.game.F[1].wins, " screen=", main.screens.result.visible)
	quit()
