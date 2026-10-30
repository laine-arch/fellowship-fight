extends SceneTree
## Builds res://fighters/<id>.tscn for every fighter: a cut-out rig (Node2D joints + Sprite2D parts)
## with an AnimationPlayer holding every move, generated from res://data/anims.json.
## Run: godot --headless --path game -s res://tools/build_fighters.gd
## After that the scenes are normal Godot scenes: open them in the editor to tweak poses,
## retime moves or swap part art. Re-running this script overwrites them.

const FIGHTERS := ["bubbles", "preacher"]
const BACK_TINT := Color(0.78, 0.72, 0.84)
const TOR := 74.0

var anims: Dictionary


func _init() -> void:
	anims = JSON.parse_string(FileAccess.get_file_as_string("res://data/anims.json"))
	DirAccess.make_dir_recursive_absolute("res://fighters")
	for id in FIGHTERS:
		_build(id)
	quit()


func _part(name: String, tex_path: String, meta: Dictionary, tint := Color.WHITE) -> Sprite2D:
	var s := Sprite2D.new()
	s.name = name
	s.texture = load(tex_path)
	s.centered = false
	var piv: Array = meta.pivot
	var k: float = 1.0 / meta.get("render_scale", 2.0)
	s.scale = Vector2(k, k)
	s.offset = Vector2(-piv[0] / k, -piv[1] / k)
	s.self_modulate = tint
	return s


func _joint(name: String, pos: Vector2, z := 0) -> Node2D:
	var n := Node2D.new()
	n.name = name
	n.position = pos
	n.z_index = z
	return n


func _own(n: Node, owner: Node) -> void:
	n.owner = owner
	for c in n.get_children():
		_own(c, owner)


func _build(id: String) -> void:
	var dir := "res://art/fighters/%s/" % id
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dir + "parts.json"))
	var P: Dictionary = meta.parts
	var root := Node2D.new()
	root.name = id.capitalize().replace(" ", "")
	root.set_script(load("res://fight/fighter_rig.gd"))
	var body := _joint("Body", Vector2.ZERO)
	root.add_child(body)

	for side in ["B", "F"]:
		var back: bool = side == "B"
		var tint := BACK_TINT if back else Color.WHITE
		var leg := _joint("Leg" + side, Vector2(-9 if back else 9, 0), -2 if back else 1)
		# children draw in order: shoe under shin, shin under thigh (like the web version)
		var knee := _joint("Knee", Vector2(0, 50))
		var ankle := _joint("Ankle", Vector2(0, 52))
		ankle.add_child(_part("Shoe", dir + "shoe.png", P.shoe, tint))
		knee.add_child(ankle)
		knee.add_child(_part("Shin", dir + "shin.png", P.shin, tint))
		leg.add_child(knee)
		leg.add_child(_part("Thigh", dir + "thigh.png", P.thigh, tint))
		body.add_child(leg)

	var torso := _joint("Torso", Vector2.ZERO)
	torso.add_child(_part("Chest", dir + "torso.png", P.torso))
	body.add_child(torso)

	var head := _joint("Head", Vector2(0, -TOR + 2), 2)
	var hs := Sprite2D.new()
	hs.name = "Face"
	hs.texture = load(dir + "head.webp")
	hs.centered = false
	var k: float = float(meta.headH) / hs.texture.get_height()
	hs.scale = Vector2(k, k)
	hs.offset = Vector2(-meta.headAnchor[0], -meta.headAnchor[1])
	head.add_child(hs)
	torso.add_child(head)

	for side in ["B", "F"]:
		var back: bool = side == "B"
		var tint := BACK_TINT if back else Color.WHITE
		var arm := _joint("Arm" + side, Vector2(-12 if back else 10, -TOR * 0.84 + 6), -3 if back else 3)
		# forearm under the upper arm, fist on top of the forearm
		var elbow := _joint("Elbow", Vector2(0, 38))
		elbow.add_child(_part("Forearm", dir + "forearm.png", P.forearm, tint))
		var wrist := _joint("Wrist", Vector2(0, 35))
		wrist.add_child(_part("Fist", dir + "fist.png", P.fist, tint))
		elbow.add_child(wrist)
		arm.add_child(elbow)
		arm.add_child(_part("Upper", dir + "upper_arm.png", P.upper_arm, tint))
		torso.add_child(arm)

	var player := AnimationPlayer.new()
	player.name = "Anim"
	root.add_child(player)
	var lib := AnimationLibrary.new()
	for aname in anims:
		lib.add_animation(aname, _make_anim(anims[aname]))
	player.add_animation_library("", lib)
	_own(body, root)
	player.owner = root

	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err == OK:
		err = ResourceSaver.save(packed, "res://fighters/%s.tscn" % id)
	print("built %s: %s" % [id, error_string(err)])
	root.free()


const TRACKS := {
	"Body:position": "root_pos", "Body:rotation": "root_rot", "Body/Torso:rotation": "torso",
	"Body/Torso/Head:rotation": "head",
	"Body/Torso/ArmF:rotation": "fa_u", "Body/Torso/ArmF/Elbow:rotation": "fa_l",
	"Body/Torso/ArmB:rotation": "ba_u", "Body/Torso/ArmB/Elbow:rotation": "ba_l",
	"Body/LegF:rotation": "fl_u", "Body/LegF/Knee:rotation": "fl_l",
	"Body/LegB:rotation": "bl_u", "Body/LegB/Knee:rotation": "bl_l",
}


func _make_anim(a: Dictionary) -> Animation:
	var anim := Animation.new()
	anim.length = maxf(1.0, a.len) / 60.0
	anim.loop_mode = Animation.LOOP_LINEAR if a.loop else Animation.LOOP_NONE
	for path in TRACKS:
		var key: String = TRACKS[path]
		var t := anim.add_track(Animation.TYPE_VALUE)
		anim.track_set_path(t, NodePath(path))
		anim.value_track_set_update_mode(t, Animation.UPDATE_CONTINUOUS)
		anim.track_set_interpolation_type(t, Animation.INTERPOLATION_LINEAR)
		for k in a.keys:
			var rig: Dictionary = k.rig
			var v: Variant
			if key == "root_pos": v = Vector2(rig.root[0], rig.root[1])
			elif key == "root_rot": v = float(rig.root[2])
			else: v = float(rig[key])
			anim.track_insert_key(t, k.f / 60.0, v, float(k.tr))
	return anim
