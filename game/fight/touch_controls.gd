class_name TouchControls
extends Control
## On-screen controls for phones: drag anywhere on the left side for a floating joystick,
## big PUNCH / KICK / SPECIAL buttons on the right. Multi-touch safe.

var input: LocalInput
var _joy_id := -1
var _joy_origin := Vector2.ZERO
var _joy_pos := Vector2.ZERO
var _down := {}  # touch index -> button

const BTN := [
	{"b": "p", "label": "PUNCH", "color": Color(0.18, 0.49, 0.98, 0.85), "pos": Vector2(-178, -66)},
	{"b": "k", "label": "KICK", "color": Color(1.0, 0.3, 0.24, 0.85), "pos": Vector2(-62, -96)},
	{"b": "s", "label": "SPECIAL", "color": Color(1.0, 0.69, 0.13, 0.9), "pos": Vector2(-118, -190)},
]
const R := 40.0
var font: Font


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	font = load("res://art/fonts/LuckiestGuy-Regular.ttf")


func _btn_center(i: int) -> Vector2:
	return size + BTN[i].pos


func _gui_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed:
			for i in BTN.size():
				if e.position.distance_to(_btn_center(i)) < R * 1.25:
					_down[e.index] = BTN[i].b
					input.press(BTN[i].b)
					Input.vibrate_handheld(12)
					queue_redraw(); accept_event(); return
			if _joy_id < 0 and e.position.x < size.x * 0.5 and e.position.y > size.y * 0.18:
				_joy_id = e.index; _joy_origin = e.position; _joy_pos = e.position
				_update_dir(); accept_event()
		else:
			_down.erase(e.index)
			if e.index == _joy_id:
				_joy_id = -1; input.dir_touch = 0
			queue_redraw()
	elif e is InputEventScreenDrag and e.index == _joy_id:
		_joy_pos = e.position
		_update_dir(); accept_event()


func _update_dir() -> void:
	var d := _joy_pos - _joy_origin
	var b := 0
	if d.length() > 16:
		var s8 := int(round(d.angle() / (PI / 4)))
		match s8:
			0: b = Sim.DIR_R
			1: b = Sim.DIR_R | Sim.DIR_D
			2: b = Sim.DIR_D
			3: b = Sim.DIR_L | Sim.DIR_D
			4, -4: b = Sim.DIR_L
			-3: b = Sim.DIR_L | Sim.DIR_U
			-2: b = Sim.DIR_U
			-1: b = Sim.DIR_R | Sim.DIR_U
	input.dir_touch = b
	queue_redraw()


func _draw() -> void:
	if _joy_id >= 0:
		draw_circle(_joy_origin, 62, Color(1, 1, 1, 0.08))
		draw_arc(_joy_origin, 62, 0, TAU, 48, Color(1, 1, 1, 0.3), 2)
		var k := (_joy_pos - _joy_origin).limit_length(48)
		draw_circle(_joy_origin + k, 28, Color(1, 1, 1, 0.35))
	else:
		var c := Vector2(80, size.y - 80)
		draw_arc(c, 52, 0, TAU, 48, Color(1, 1, 1, 0.22), 2)
		draw_string(font, c + Vector2(-30, 6), "MOVE", HORIZONTAL_ALIGNMENT_CENTER, 60, 14, Color(1, 1, 1, 0.35))
	for i in BTN.size():
		var c := _btn_center(i)
		var pressed: bool = BTN[i].b in _down.values()
		var r := R * (0.92 if pressed else 1.0)
		draw_circle(c + Vector2(0, 4), r, Color(0, 0, 0, 0.35))
		draw_circle(c, r, BTN[i].color.lightened(0.25) if pressed else BTN[i].color)
		draw_arc(c, r, 0, TAU, 48, Color(1, 1, 1, 0.55), 3)
		var fs := 13 if BTN[i].label.length() > 5 else 16
		draw_string_outline(font, c + Vector2(-R, fs * 0.35), BTN[i].label, HORIZONTAL_ALIGNMENT_CENTER, R * 2, fs, 4, Color(0.11, 0.06, 0.09))
		draw_string(font, c + Vector2(-R, fs * 0.35), BTN[i].label, HORIZONTAL_ALIGNMENT_CENTER, R * 2, fs, Color.WHITE)
