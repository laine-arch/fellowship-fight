class_name CpuBrain
extends RefCounted
## Practice opponent. Produces the same kind of input a player does. Uses randf(), so it is
## only for offline CPU matches (never in online play, where everything must be deterministic).

var st := {"b": 0, "p": 0, "k": 0, "s": 0}
var wait := 0
var hold := 0


func _bump(key: String) -> void:
	st[key] = (st[key] + 1) % 16


func think(g: Dictionary, me: Dictionary, op: Dictionary) -> Dictionary:
	if g.ph != "fight":
		st.b = 0
		return st
	var dx: float = op.x - me.x
	var dist := absf(dx)
	var toward := Sim.DIR_R if dx > 0 else Sim.DIR_L
	var away := Sim.DIR_L if dx > 0 else Sim.DIR_R
	var op_atk: bool = op.st == "atk"
	for p in g.proj:
		if p.o == op.i and absf(p.x - me.x) < 260: op_atk = true
	if hold > 0:
		hold -= 1
		return st
	if wait > 0: wait -= 1
	var R := randf()
	if op_atk and dist < 230 and R < 0.55 and me.st != "atk":
		st.b = away | (Sim.DIR_D if op.mv == "sweep" or op.mv == "lowP" else 0); hold = 10
		return st
	if op.y > 40 and dist < 170 and R < 0.08 and me.st != "atk":
		st.b = Sim.DIR_U; _bump("s"); hold = 3; wait = 20
		return st
	if wait > 0: return st
	if me.st == "atk" and me.contact:
		if R < 0.5: _bump("p")
		elif R < 0.7: _bump("k")
		elif R < 0.8: _bump("s")
		wait = 6
		return st
	if dist > 330:
		if R < 0.025: st.b = 0; _bump("s"); wait = 30
		else: st.b = toward; wait = 6
	elif dist > 130:
		if R < 0.04: st.b = toward | Sim.DIR_U; hold = 4; wait = 8
		elif R < 0.06: st.b = toward; _bump("s"); wait = 30
		else: st.b = toward; wait = 5
	else:
		if R < 0.3: st.b = 0; _bump("p"); wait = 10
		elif R < 0.45: st.b = 0; _bump("k"); wait = 14
		elif R < 0.55: st.b = Sim.DIR_D; _bump("k"); hold = 4; wait = 18
		elif R < 0.62 and me.m >= 100: st.b = Sim.DIR_D; _bump("s"); hold = 3; wait = 40
		elif R < 0.75: st.b = away; wait = 14
		else: st.b = 0; wait = 8
	return st
