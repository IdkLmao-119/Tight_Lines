class_name FishingSFX
extends Node

## Lightweight procedural SFX player for 3D fishing scenes.
## Generates crisp, low-footprint AudioStreamWAV clips at startup so fishing has
## immediate audio feedback even without external audio files. Any clip can be
## overridden by assigning a custom AudioStream via set_override().

const SAMPLE_RATE := 22050
const BUS_SFX := "SFX"

var _clips: Dictionary = {}
var _overrides: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next_player := 0
const POOL_SIZE := 6


func _ready() -> void:
	_build_pool()
	_build_default_clips()


func set_override(clip_name: String, stream: AudioStream) -> void:
	if stream == null:
		_overrides.erase(clip_name)
	else:
		_overrides[clip_name] = stream


func has_clip(clip_name: String) -> bool:
	return _overrides.has(clip_name) or _clips.has(clip_name)


func play(clip_name: String, volume_db: float = -4.0, pitch_scale: float = 1.0) -> bool:
	var stream: AudioStream = _overrides.get(clip_name, _clips.get(clip_name))
	if stream == null or _players.is_empty():
		return false
	var player := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = maxf(pitch_scale, 0.25)
	player.play()
	return true


func _build_pool() -> void:
	var target_bus := BUS_SFX if AudioServer.get_bus_index(BUS_SFX) != -1 else "Master"
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = target_bus
		add_child(p)
		_players.append(p)


func _build_default_clips() -> void:
	_clips["cast"] = _gen_cast_whoosh()
	_clips["splash"] = _gen_water_splash(0.32, 1.0)
	_clips["surge_splash"] = _gen_water_splash(0.22, 0.75)
	_clips["bite"] = _gen_bite_chime()
	_clips["reel_tick"] = _gen_reel_tick()
	_clips["snap"] = _gen_line_snap()
	_clips["catch"] = _gen_catch_fanfare()
	_clips["knot_tied"] = _gen_knot_tied()


static func _make_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var s := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		bytes[i * 2] = s & 0xFF
		bytes[i * 2 + 1] = (s >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = bytes
	return wav


static func _gen_cast_whoosh() -> AudioStreamWAV:
	var dur := 0.28
	var n := int(SAMPLE_RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 101
	for i in n:
		var t := float(i) / float(n)
		var env := sin(t * PI) * (1.0 - t * 0.35)
		var noise := rng.randf_range(-1.0, 1.0)
		var alpha := lerpf(0.08, 0.35, sin(t * PI))
		lp = lp + alpha * (noise - lp)
		var whistle := sin(TAU * lerpf(280.0, 720.0, t) * float(i) / float(SAMPLE_RATE)) * 0.18
		out[i] = (lp * 0.85 + whistle) * env * 0.65
	return _make_wav(out)


static func _gen_water_splash(dur: float, gain: float) -> AudioStreamWAV:
	var n := int(SAMPLE_RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 202
	for i in n:
		var t := float(i) / float(n)
		var env := exp(-t * 6.5)
		var noise := rng.randf_range(-1.0, 1.0)
		lp = lp + 0.25 * (noise - lp)
		# Bubble plop pitch sweep at the start
		var plop_freq := lerpf(220.0, 520.0, minf(t * 5.0, 1.0))
		var plop := sin(TAU * plop_freq * float(i) / float(SAMPLE_RATE)) * exp(-t * 18.0) * 0.55
		out[i] = (lp * 0.75 + plop) * env * 0.75 * gain
	return _make_wav(out)


static func _gen_bite_chime() -> AudioStreamWAV:
	var dur := 0.36
	var n := int(SAMPLE_RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / float(SAMPLE_RATE)
		var f := 784.0 if t < 0.12 else 1174.66 # G5 -> D6 alert
		var local_t := t if t < 0.12 else (t - 0.12)
		var env := exp(-local_t * 14.0)
		out[i] = (sin(TAU * f * t) * 0.7 + sin(TAU * f * 2.0 * t) * 0.2) * env * 0.6
	return _make_wav(out)


static func _gen_reel_tick() -> AudioStreamWAV:
	var dur := 0.04
	var n := int(SAMPLE_RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / float(n)
		var env := exp(-t * 14.0)
		var click := sin(TAU * 1650.0 * float(i) / float(SAMPLE_RATE)) * 0.65
		var body := sin(TAU * 620.0 * float(i) / float(SAMPLE_RATE)) * 0.35
		out[i] = (click + body) * env * 0.35
	return _make_wav(out)


static func _gen_line_snap() -> AudioStreamWAV:
	var dur := 0.22
	var n := int(SAMPLE_RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	for i in n:
		var t := float(i) / float(n)
		var env := exp(-t * 12.0)
		var twang_freq := lerpf(900.0, 140.0, t)
		var twang := sin(TAU * twang_freq * float(i) / float(SAMPLE_RATE)) * 0.6
		var crack := rng.randf_range(-1.0, 1.0) * exp(-t * 35.0) * 0.8
		out[i] = (twang + crack) * env * 0.75
	return _make_wav(out)


static func _gen_catch_fanfare() -> AudioStreamWAV:
	var notes := [523.25, 659.25, 783.99, 1046.50] # C5, E5, G5, C6
	var note_dur := 0.11
	var total_dur := note_dur * notes.size() + 0.25
	var n := int(SAMPLE_RATE * total_dur)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / float(SAMPLE_RATE)
		var idx := mini(int(t / note_dur), notes.size() - 1)
		var local_t := t - float(idx) * note_dur
		var f: float = notes[idx]
		var decay := 5.0 if idx == notes.size() - 1 else 10.0
		var env := minf(local_t * 80.0, 1.0) * exp(-local_t * decay)
		out[i] = (sin(TAU * f * t) * 0.7 + sin(TAU * f * 1.5 * t) * 0.2) * env * 0.55
	return _make_wav(out)


static func _gen_knot_tied() -> AudioStreamWAV:
	# Short rope cinch zip followed by a crisp two-note confirmation chime
	var dur := 0.34
	var n := int(SAMPLE_RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / float(SAMPLE_RATE)
		if t < 0.10:
			var u := t / 0.10
			var f := lerpf(320.0, 740.0, u)
			var env := sin(u * PI)
			out[i] = sin(TAU * f * t) * env * 0.40
		else:
			var lt := t - 0.10
			var f := 659.25 if lt < 0.09 else 987.77 # E5 -> B5
			var note_t := lt if lt < 0.09 else (lt - 0.09)
			var env := minf(note_t * 90.0, 1.0) * exp(-note_t * 12.0)
			out[i] = (sin(TAU * f * t) * 0.7 + sin(TAU * f * 2.0 * t) * 0.18) * env * 0.55
	return _make_wav(out)
