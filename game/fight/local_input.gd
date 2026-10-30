class_name LocalInput
extends Node
## This player's controls, as the simulation wants them: direction bits plus press counters
## (a press is a counter change, so a quick tap between two frames is never lost).
## Fed by the keyboard here and by TouchControls.

var dir_touch := 0
var dir_keys := 0
var p := 0
var k := 0
var s := 0

const KEYS := {KEY_LEFT: Sim.DIR_L, KEY_A: Sim.DIR_L, KEY_RIGHT: Sim.DIR_R, KEY_D: Sim.DIR_R,
	KEY_UP: Sim.DIR_U, KEY_W: Sim.DIR_U, KEY_DOWN: Sim.DIR_D, KEY_S: Sim.DIR_D}
const BUTTONS := {KEY_J: "p", KEY_Z: "p", KEY_K: "k", KEY_X: "k", KEY_L: "s", KEY_C: "s"}


func reset_counters() -> void:
	p = 0; k = 0; s = 0


func press(button: String) -> void:
	match button:
		"p": p = (p + 1) % 16
		"k": k = (k + 1) % 16
		"s": s = (s + 1) % 16


func bits() -> int:
	var b := dir_touch | dir_keys
	if b & 3 == 3: b &= ~3
	if b & 12 == 12: b &= ~12
	return b


func snapshot() -> Dictionary:
	return {"b": bits(), "p": p, "k": k, "s": s}


func _unhandled_key_input(e: InputEvent) -> void:
	var ek := e as InputEventKey
	if ek == null or ek.echo: return
	var code := ek.physical_keycode
	if KEYS.has(code):
		if ek.pressed: dir_keys |= KEYS[code]
		else: dir_keys &= ~KEYS[code]
	elif BUTTONS.has(code) and ek.pressed:
		press(BUTTONS[code])


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		dir_keys = 0; dir_touch = 0
