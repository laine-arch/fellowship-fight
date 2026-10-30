class_name Rollback
extends RefCounted
## Rollback netcode (ported from the web version). Both phones run Sim with the same inputs.
## The opponent's input is predicted by holding their last known one; when the real input
## arrives and differs, we restore the saved state from that frame and re-simulate.

const DELAY := 2      # local input delay in frames: fewer, smaller corrections
const MAXRB := 14     # never run further ahead of the opponent than this
const STEP := 1.0 / 60.0

var game: Dictionary
var me := 0
var f := 0                      # next frame to simulate
var li := {}                    # local inputs by frame (encoded)
var ri := {}                    # remote inputs by frame
var rmax := DELAY - 1           # highest contiguous remote frame we have
var pred := {}                  # remote input used when each frame was simulated
var states := {}                # saved state before each frame (for rewinding)
var acc := 0.0
var pend := -1
var remote_f := 0
var remote_adv := 0
var remote_ack := -1
var skip := 0
var last_skip := 0
var ping := 0.0
var r_ts := 0
var r_ts_at := 0
var my_hash := {}
var their_hash := {}
var hashed_to := 0
var sync_id := 0
var seen_sync := 0
var last_sync := -999
var stall := 0.0
var desyncs := 0


static func enc(o: Dictionary) -> int:
	return (o.b & 15) | ((o.p & 15) << 4) | ((o.k & 15) << 8) | ((o.s & 15) << 12)


static func dec(n: int) -> Dictionary:
	return {"b": n & 15, "p": (n >> 4) & 15, "k": (n >> 8) & 15, "s": (n >> 12) & 15}


func _init(g: Dictionary, my_idx: int) -> void:
	game = g; me = my_idx
	for i in DELAY:
		li[i] = 0; ri[i] = 0


func _sim_frame(fr: int) -> void:
	states[fr] = game.duplicate(true)
	var r_in: int = ri[fr] if fr <= rmax else ri[rmax]
	pred[fr] = r_in
	var l := dec(li.get(fr, 0))
	var r := dec(r_in)
	Sim.step(game, [l, r] if me == 0 else [r, l])


## A message from the opponent (relayed by the lobby server).
func receive(m: Dictionary) -> void:
	var now := Time.get_ticks_msec()
	if m.has("a"):
		var s := int(m.s)
		var a: Array = m.a
		for j in a.size():
			var fr := s + j
			if fr != rmax + 1: continue
			var v := int(a[j])
			ri[fr] = v; rmax = fr
			if fr < f and pred.get(fr, v) != v and (pend < 0 or fr < pend): pend = fr
		remote_f = int(m.get("f", remote_f)); remote_adv = int(m.get("adv", 0)); remote_ack = int(m.get("ack", remote_ack))
		var ts := int(m.get("ts", 0))
		if ts and ts != r_ts:
			r_ts = ts; r_ts_at = now
		var e = m.get("e")
		if e is Array and e.size() == 2 and int(e[0]) > 0:
			var rtt := now - int(e[0]) - int(e[1])
			if rtt > 0 and rtt < 5000: ping = rtt if ping == 0 else ping * 0.85 + rtt * 0.15
		# frame-advantage balancing: if we're running ahead, wait a frame or two
		var diff := (f - remote_f) - remote_adv
		if diff >= 2 and skip == 0 and f - last_skip > 20:
			skip = mini(3, diff >> 1); last_skip = f
	if m.get("h") is Array:
		their_hash[int(m.h[0])] = int(m.h[1])
	var sy = m.get("sync")
	if sy is Dictionary and me == 1 and int(sy.id) != seen_sync:
		seen_sync = int(sy.id)
		_apply_sync(int(sy.fr), Marshalls.base64_to_variant(sy.st))


func _apply_sync(fr: int, st: Variant) -> void:
	if not st is Dictionary or fr > rmax + 1: return
	game = st; game.ev = []
	for k in states.keys():
		if k >= fr: states.erase(k)
	if fr > f:
		for i in range(f + DELAY, fr + DELAY):
			if not li.has(i): li[i] = li.get(i - 1, 0)
		f = fr
	else:
		var to := f
		f = fr
		while f < to:
			_sim_frame(f); f += 1
	for k in my_hash.keys():
		if k >= fr: my_hash.erase(k)
	hashed_to = int(ceil(fr / 60.0)) * 60 - 60
	pend = -1


## Advance local time; returns the message to send to the opponent this frame.
func tick(delta: float, local_input: Dictionary) -> Dictionary:
	var now := Time.get_ticks_msec()
	if pend >= 0:
		if states.has(pend):
			game = states[pend].duplicate(true)
			var to := f
			var fr := pend
			while fr < to:
				_sim_frame(fr); fr += 1
		pend = -1
	acc = minf(acc + delta, STEP * 8)
	var stalled := false
	while acc >= STEP:
		if f - rmax > MAXRB:
			stalled = true
			break
		acc -= STEP
		if skip > 0:
			skip -= 1
			continue
		li[f + DELAY] = enc(local_input)
		_sim_frame(f); f += 1
	stall = stall + delta if stalled else 0.0
	# forget what nobody can roll back to any more
	for k in states.keys():
		if k < rmax - 1: states.erase(k)
	for k in li.keys():  # keep what the opponent may still need and what a rewind may replay
		if k < mini(remote_ack, rmax) - 1: li.erase(k)
	for k in pred.keys():
		if k < rmax - 1: pred.erase(k)
	for k in ri.keys():
		if k < rmax - 1: ri.erase(k)
	# desync check every second of confirmed play
	var h = null
	var conf := mini(rmax + 1, f)
	while hashed_to + 60 <= conf:
		hashed_to += 60
		if states.has(hashed_to):
			my_hash[hashed_to] = Sim.hash_state(states[hashed_to])
			h = [hashed_to, my_hash[hashed_to]]
	var out := {"t": "in"}
	for fr in their_hash.keys():
		if not my_hash.has(fr): continue
		if my_hash[fr] != their_hash[fr] and me == 0 and f - last_sync > 45:
			last_sync = f
			var st = states.get(conf, game if conf == f else null)
			if st != null:
				var g2: Dictionary = st.duplicate(true); g2.ev = []
				sync_id += 1
				out.sync = {"id": sync_id, "fr": conf, "st": Marshalls.variant_to_base64(g2)}
			desyncs += 1
		their_hash.erase(fr)
	for k in my_hash.keys():
		if k < hashed_to - 240: my_hash.erase(k)
	var hi := f + DELAY
	var lo := maxi(remote_ack + 1, hi - 60)
	lo = maxi(lo, 0)
	var a := []
	for i in range(lo, hi): a.append(li.get(i, 0))
	out.s = lo; out.a = a; out.f = f; out.adv = f - remote_f; out.ack = rmax; out.ts = now
	out.e = [r_ts, now - r_ts_at] if r_ts else null
	if h != null: out.h = h
	return out


## The match is over on a confirmed frame (never end on a prediction).
func over_confirmed() -> bool:
	var cs = game if rmax + 1 >= f else states.get(rmax + 1)
	return cs != null and cs.ph == "over" and cs.pt > 60
