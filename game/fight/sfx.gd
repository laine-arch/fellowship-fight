class_name Sfx
extends Node
## Tiny synthesized sound kit (no audio files needed). Sounds are generated once at startup.

var _streams := {}
var _players: Array[AudioStreamPlayer] = []
const RATE := 22050


func _ready() -> void:
	_streams.hit = _make(0.14, 900, 0.5, 160, 60, 0.15)
	_streams.big = _make(0.25, 500, 0.7, 120, 40, 0.25)
	_streams.block = _make(0.08, 2500, 0.3, 0, 0, 0)
	_streams.whiff = _make(0.09, 1800, 0.12, 0, 0, 0)
	_streams.proj = _make(0.18, 0, 0, 500, 900, 0.18)
	_streams.wave = _make(0.3, 0, 0, 140, 90, 0.14)
	_streams.super = _make(0.5, 0, 0, 200, 1200, 0.15)
	_streams.ko = _make(0.9, 300, 0.5, 300, 50, 0.25)
	_streams.bell = _make(0.6, 0, 0, 880, 860, 0.25)
	for i in 6:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


func play(kind: String) -> void:
	if not _streams.has(kind): return
	for p in _players:
		if not p.playing:
			p.stream = _streams[kind]; p.play(); return


## noise burst (crude band-pass by smoothing) + pitch-swept square/sine tone, with a decay envelope
func _make(dur: float, noise_hz: float, noise_vol: float, f0: float, f1: float, tone_vol: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(dur * 1000 + f0)
	var lp := 0.0
	var phase := 0.0
	var a := clampf(noise_hz / RATE * 6.0, 0.02, 1.0)
	for i in n:
		var env := 1.0 - float(i) / n
		var v := 0.0
		if noise_vol > 0:
			lp += (rng.randf_range(-1, 1) - lp) * a
			v += lp * noise_vol * env * 2.0
		if tone_vol > 0:
			var f := f0 * pow(f1 / f0, float(i) / n)
			phase += f / RATE
			v += (1.0 if fmod(phase, 1.0) < 0.5 else -1.0) * tone_vol * env * env
		data.encode_s16(i * 2, int(clampf(v, -1, 1) * 32000))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.data = data
	return s
