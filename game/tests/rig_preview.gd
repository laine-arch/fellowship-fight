extends SceneTree
## Renders a contact sheet of fighter poses to user://rig_preview.png (needs a display, e.g. xvfb-run).

const SHOTS := [["idle", 0.2], ["walk", 0.25], ["jab", 0.08], ["cross", 0.12], ["round", 0.18], ["kick", 0.17],
	["spin", 0.2], ["sweep", 0.18], ["upper", 0.12], ["proj", 0.25], ["hit_big", 0.05], ["down", 0.2]]

func _init() -> void:
	root.size = Vector2i(1500, 640)
	var bg := ColorRect.new(); bg.color = Color(0.55, 0.75, 0.6); bg.size = Vector2(1500, 640); root.add_child(bg)
	var i := 0
	for id in ["bubbles", "preacher"]:
		for s in SHOTS:
			var f: Node2D = load("res://fighters/%s.tscn" % id).instantiate()
			root.add_child(f)
			f.position = Vector2(70 + (i % 12) * 120, 290 + int(i / 12) * 320)
			f.scale = Vector2(0.48, 0.48)
			var a: AnimationPlayer = f.get_node("Anim")
			a.play(s[0]); a.seek(s[1], true); a.pause()
			var l := Label.new(); l.text = s[0]; l.position = f.position + Vector2(-30, 10); root.add_child(l)
			i += 1
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/rig_preview.png")
	quit()
