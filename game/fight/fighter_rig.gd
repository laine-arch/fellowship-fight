extends Node2D
## Drives a cut-out fighter rig from the simulation state. Purely visual: the animation is
## sought to a time computed from the fight state each frame, never advanced on its own,
## so both phones show the same pose for the same state.

const MOVE_ANIMS := ["jab", "cross", "round", "kick", "spin", "lowP", "sweep", "airP", "airK", "proj", "rush", "upper", "super"]
## Which limb lands each move (used for motion streaks).
const STRIKE := {"jab": "F", "cross": "B", "round": "LF", "kick": "LF", "spin": "LB", "lowP": "F", "sweep": "LF",
	"airP": "F", "airK": "LF", "rush": "F", "upper": "F", "proj": "F", "super": "F"}

@onready var anim: AnimationPlayer = $Anim
var _face := 1
var _flip_t := 0.0


func _ready() -> void:
	anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL


## F: fighter dictionary from Sim. frame: global sim frame (for looping idle/walk).
func show_state(F: Dictionary, frame: int, char_scale: float, delta: float, hitstop: bool) -> void:
	var t: float = F.t
	var a := "idle"
	var time := 0.0
	match F.st:
		"idle":
			a = "idle"; time = (frame + F.i * 37) / 60.0
		"walk":
			a = "walk" if F.vx * F.f >= 0 else "walk_back"; time = (frame + F.i * 37) / 60.0
		"crouch":
			a = "crouch"; time = t / 60.0
		"jump":
			a = "jump"; time = clampf((17.5 - F.vy) / 35.0, 0.0, 1.0) if t > 3 else t / 4.0 * (8.0 / 60.0)
		"land":
			a = "land"; time = clampf(t / (F.landLag + 5.0), 0.0, 1.0)
		"atk":
			a = F.mv if F.mv in MOVE_ANIMS else "idle"; time = t / 60.0
		"hit":
			a = "hit_low" if F.cb else ("hit_big" if F.stun > 22 or F.combo > 2 else "hit"); time = t / 60.0
		"block":
			a = "cblock" if F.cb else "block"; time = t / 60.0
		"fly":
			a = "fly"; time = t / 60.0
		"down", "ko":
			a = "down"; time = t / 60.0
		"getup":
			a = "getup"; time = t / 60.0
		"win":
			a = "win"; time = frame / 60.0
	if anim.current_animation != a:
		anim.play(a)
	var length := anim.get_animation(a).length
	if anim.get_animation(a).loop_mode != Animation.LOOP_NONE:
		time = fmod(time, length)
	anim.seek(minf(time, length), true)
	# quick turn-around instead of an instant flip
	if F.f != _face:
		_face = F.f; _flip_t = 0.1
	var fx := 1.0
	if _flip_t > 0:
		fx = 0.35 + 0.65 * (1.0 - _flip_t / 0.1); _flip_t -= delta
	var sq := _squash(F)
	var jit := 0.0
	if hitstop and F.flash > 0:
		jit = 3.5 if int(Time.get_ticks_msec() / 30) % 2 else -3.5
	position.x += jit
	scale = Vector2(F.f * char_scale * sq.x * fx, char_scale * sq.y)
	modulate = Color(1.6, 1.6, 1.6) if F.flash > 0 and F.flash % 2 else Color.WHITE


func _squash(F: Dictionary) -> Vector2:
	var t: float = F.t
	if F.st == "jump" and t < 6: return Vector2(1 - 0.05 * (1 - t / 6), 1 + 0.08 * (1 - t / 6))
	if F.st == "land" and t < 6: return Vector2(1 + 0.07 * (1 - t / 6), 1 - 0.09 * (1 - t / 6))
	if F.st == "hit" and t < 4: return Vector2(1.05, 0.96)
	if F.st == "atk" and (F.mv == "cross" or F.mv == "rush") and t >= 6 and t < 10: return Vector2(1.04, 0.98)
	return Vector2.ONE


## Global position of the fist/foot that lands the current move, or null.
func strike_point(F: Dictionary) -> Variant:
	if F.st != "atk" or not STRIKE.has(F.mv): return null
	var M: Dictionary = Sim.MOVES[F.mv]
	if F.t < M.su - 1 or F.t > M.su + maxi(M.act, 3) + 1: return null
	match STRIKE[F.mv]:
		"F": return $Body/Torso/ArmF/Elbow/Wrist.global_position
		"B": return $Body/Torso/ArmB/Elbow/Wrist.global_position
		"LF": return $Body/LegF/Knee/Ankle.global_position
		"LB": return $Body/LegB/Knee/Ankle.global_position
	return null
