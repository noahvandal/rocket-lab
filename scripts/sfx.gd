class_name Sfx
extends Node
## Procedurally generated sounds (no audio assets to download).

const RATE := 22050

var engine: AudioStreamPlayer
var boom_p: AudioStreamPlayer
var beep_p: AudioStreamPlayer
var chime_p: AudioStreamPlayer
var beep_hi: AudioStreamWAV
var beep_lo: AudioStreamWAV

func _ready() -> void:
	engine = _player(_engine_loop(), -80.0)
	boom_p = _player(_boom(), -2.0)
	beep_lo = _tone([660.0], 0.14, 0.4)
	beep_hi = _tone([990.0], 0.35, 0.4)
	beep_p = _player(beep_lo, -8.0)
	chime_p = _player(_tone([523.0, 659.0, 784.0, 1046.0], 0.16, 0.35), -6.0)

func _player(stream: AudioStream, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = db
	add_child(p)
	return p

func set_engine(level: float, pitch: float) -> void:
	if level > 0.01:
		if not engine.playing:
			engine.play()
		engine.volume_db = linear_to_db(clampf(level, 0.0001, 1.0)) - 3.0
		engine.pitch_scale = clampf(pitch, 0.5, 2.0)
	elif engine.playing:
		engine.stop()

func boom() -> void:
	boom_p.play()

func beep(high := false) -> void:
	beep_p.stream = beep_hi if high else beep_lo
	beep_p.play()

func chime() -> void:
	chime_p.play()

func _wav(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var peak := 0.0001
	for v in samples:
		peak = maxf(peak, absf(v))
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i] / peak * 0.9, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w

func _engine_loop() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var n := RATE * 2
	var fade := 2000
	var raw := PackedFloat32Array()
	raw.resize(n)
	var brown := 0.0
	var mid := 0.0
	for i in n:
		var w := rng.randf_range(-1.0, 1.0)
		brown = (brown + 0.02 * w) / 1.02
		mid = mid * 0.85 + w * 0.15
		var crackle := rng.randf_range(-1.0, 1.0) if rng.randf() < 0.004 else 0.0
		raw[i] = brown * 9.0 + mid * 0.5 + crackle * 0.6
	var out := PackedFloat32Array()
	out.resize(n - fade)
	for i in n - fade:
		out[i] = raw[i]
	for i in fade:
		var t := float(i) / fade
		out[i] = raw[i] * t + raw[n - fade + i] * (1.0 - t)
	return _wav(out, true)

func _boom() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var n := int(RATE * 2.6)
	var s := PackedFloat32Array()
	s.resize(n)
	var brown := 0.0
	for i in n:
		var t := float(i) / RATE
		var w := rng.randf_range(-1.0, 1.0)
		brown = (brown + 0.04 * w) / 1.04
		var env := exp(-t * 2.2) * minf(t * 200.0, 1.0)
		s[i] = (brown * 8.0 + w * exp(-t * 14.0) * 0.8) * env
	return _wav(s)

func _tone(freqs: Array, dur: float, gap: float) -> AudioStreamWAV:
	var total := dur * freqs.size() * (1.0 + gap)
	var n := int(RATE * total)
	var s := PackedFloat32Array()
	s.resize(n)
	var step := dur * (1.0 + gap)
	for i in n:
		var t := float(i) / RATE
		var k := mini(int(t / step), freqs.size() - 1)
		var lt := t - k * step
		var env := clampf(lt * 120.0, 0.0, 1.0) * exp(-lt * 9.0)
		s[i] = (sin(TAU * freqs[k] * t) + 0.3 * sin(TAU * freqs[k] * 2.0 * t)) * env
	return _wav(s)
