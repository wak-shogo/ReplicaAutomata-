extends Node

# Warm, refined 16-bit 44.1kHz procedural audio synthesizer.
# Zero harsh raw square waves; uses soft harmonic sine/FM synthesis & LP-filtered transients.

const SAMPLE_RATE: int = 44100
const POOL_SIZE: int = 8

var muted: bool = false
var _streams: Dictionary = {}
var _volumes: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _cursor: int = 0
var _last_play_ms: Dictionary = {}

func _ready() -> void:
	for i in range(POOL_SIZE):
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)
	_build_presets()

func _build_presets() -> void:
	_reg("click",     _gen_tone(0.055, [520.0, 780.0], 0.85, 0.004, 0.045, 0.0, 0.14), -14.0)
	_reg("select",    _gen_chord(0.11, [440.0, 659.25], 0.006, 0.09, 0.18), -12.0)
	_reg("mine",      _gen_chime(0.13, 330.0, 495.0, 0.14), -15.0)
	_reg("laser",     _gen_tone(0.16, [240.0, 480.0], 0.65, 0.01, 0.13, 0.12, 0.15), -13.0)
	_reg("build",     _gen_thump_chime(0.22, 115.0, 392.0, 0.22), -11.0)
	_reg("wire",      _gen_chord(0.18, [523.25, 783.99, 1046.5], 0.008, 0.15, 0.17), -12.0)
	_reg("craft",     _gen_arpeggio(0.32, [392.0, 493.88, 587.33, 783.99], 0.18), -10.0)
	_reg("research",  _gen_arpeggio(0.45, [440.0, 554.37, 659.25, 880.0], 0.20), -9.0)
	_reg("launch",    _gen_launch_whoosh(0.55), -9.0)
	_reg("pop",       _gen_tone(0.08, [340.0, 510.0], 1.35, 0.003, 0.065, 0.0, 0.16), -13.0)
	_reg("error",     _gen_tone(0.18, [195.0, 155.0], 0.78, 0.008, 0.15, 0.0, 0.16), -12.0)
	_reg("alert",     _gen_chord(0.26, [311.13, 370.0], 0.015, 0.22, 0.16), -11.0)
	_reg("explosion", _gen_deep_boom(0.46), -9.0)
	_reg("victory",   _gen_arpeggio(0.85, [523.25, 659.25, 783.99, 1046.5, 1318.5], 0.22), -8.0)

func _reg(key: String, wav: AudioStreamWAV, db: float) -> void:
	_streams[key] = wav
	_volumes[key] = db

func play_sfx(key: String, pitch_jitter: float = 0.04) -> void:
	if muted or not _streams.has(key):
		return
	var now = Time.get_ticks_msec()
	var prev = int(_last_play_ms.get(key, 0))
	if now - prev < 55:
		return
	_last_play_ms[key] = now
	var p: AudioStreamPlayer = _players[_cursor]
	_cursor = (_cursor + 1) % POOL_SIZE
	p.stop()
	p.stream = _streams[key]
	p.volume_db = float(_volumes.get(key, -12.0))
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()

func get_preset_names() -> Array:
	return _streams.keys()

func _pack_pcm16(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in range(samples.size()):
		var v = clampi(int(round(clampf(samples[i], -0.96, 0.96) * 32767.0)), -32768, 32767)
		bytes[i * 2] = v & 0xFF
		bytes[i * 2 + 1] = (v >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = bytes
	return wav

func _env(t: float, dur: float, atk: float, dec: float) -> float:
	if t < atk:
		return t / maxf(0.001, atk)
	var rem = maxf(0.0, 1.0 - (t - atk) / maxf(0.001, dur - atk))
	return pow(rem, 1.6) * exp(-maxf(0.0, t - atk) / maxf(0.02, dec))

func _gen_tone(dur: float, freqs: Array, sweep: float, atk: float, dec: float, fm_amt: float, gain: float) -> AudioStreamWAV:
	var n = int(dur * SAMPLE_RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var ph0 := 0.0
	var ph1 := 0.0
	for i in range(n):
		var t = float(i) / float(SAMPLE_RATE)
		var f0 = float(freqs[0]) * lerpf(1.0, sweep, t / dur)
		var f1 = float(freqs[1]) * lerpf(1.0, sweep, t / dur)
		ph0 += TAU * f0 / float(SAMPLE_RATE)
		ph1 += TAU * f1 / float(SAMPLE_RATE)
		var s = sin(ph0 + fm_amt * sin(ph1)) * 0.72 + sin(ph1) * 0.28
		buf[i] = s * _env(t, dur, atk, dec) * gain
	return _pack_pcm16(buf)

func _gen_chord(dur: float, freqs: Array, atk: float, dec: float, gain: float) -> AudioStreamWAV:
	var n = int(dur * SAMPLE_RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var inv = 1.0 / maxf(1.0, float(freqs.size()))
	for i in range(n):
		var t = float(i) / float(SAMPLE_RATE)
		var s = 0.0
		for f in freqs:
			s += sin(TAU * float(f) * t) * 0.8 + sin(TAU * float(f) * 2.0 * t) * 0.2 * exp(-t * 14.0)
		buf[i] = s * inv * _env(t, dur, atk, dec) * gain
	return _pack_pcm16(buf)

func _gen_chime(dur: float, f0: float, f1: float, gain: float) -> AudioStreamWAV:
	var n = int(dur * SAMPLE_RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in range(n):
		var t = float(i) / float(SAMPLE_RATE)
		var s = sin(TAU * f0 * t) * 0.55 + sin(TAU * f1 * t) * 0.32 + sin(TAU * f1 * 2.01 * t) * 0.13 * exp(-t * 18.0)
		buf[i] = s * _env(t, dur, 0.004, dur * 0.7) * gain
	return _pack_pcm16(buf)

func _gen_thump_chime(dur: float, bass_f: float, bell_f: float, gain: float) -> AudioStreamWAV:
	var n = int(dur * SAMPLE_RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var ph_b = 0.0
	for i in range(n):
		var t = float(i) / float(SAMPLE_RATE)
		ph_b += TAU * lerpf(bass_f, bass_f * 0.45, minf(1.0, t * 7.0)) / float(SAMPLE_RATE)
		var thump = sin(ph_b) * exp(-t * 18.0) * 0.65
		var bell = (sin(TAU * bell_f * t) * 0.6 + sin(TAU * bell_f * 1.5 * t) * 0.4) * _env(t, dur, 0.012, dur * 0.8) * 0.55
		buf[i] = (thump + bell) * gain
	return _pack_pcm16(buf)

func _gen_arpeggio(dur: float, notes: Array, gain: float) -> AudioStreamWAV:
	var n = int(dur * SAMPLE_RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var step = dur / float(notes.size())
	for i in range(n):
		var t = float(i) / float(SAMPLE_RATE)
		var s = 0.0
		for k in range(notes.size()):
			var lt = t - float(k) * step * 0.72
			if lt >= 0.0:
				var f = float(notes[k])
				s += (sin(TAU * f * lt) * 0.75 + sin(TAU * f * 2.0 * lt) * 0.25 * exp(-lt * 10.0)) * _env(lt, dur - float(k) * step * 0.6, 0.008, 0.25)
		buf[i] = tanh(s * 0.55) * gain
	return _pack_pcm16(buf)

func _gen_launch_whoosh(dur: float) -> AudioStreamWAV:
	var n = int(dur * SAMPLE_RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var lp := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 9001
	var ph := 0.0
	for i in range(n):
		var t = float(i) / float(SAMPLE_RATE)
		var u = t / dur
		var noise = rng.randf_range(-1.0, 1.0)
		var alpha = lerpf(0.03, 0.14, sin(u * PI))
		lp += (noise - lp) * alpha
		ph += TAU * lerpf(95.0, 540.0, u * u) / float(SAMPLE_RATE)
		var rail = sin(ph) * 0.35 * exp(-absf(u - 0.35) * 4.0)
		var env = sin(u * PI) * exp(-u * 1.4)
		buf[i] = clampf((lp * 1.4 + rail) * env * 0.45, -0.9, 0.9)
	return _pack_pcm16(buf)

func _gen_deep_boom(dur: float) -> AudioStreamWAV:
	var n = int(dur * SAMPLE_RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var lp := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var ph := 0.0
	for i in range(n):
		var t = float(i) / float(SAMPLE_RATE)
		var u = t / dur
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.055
		ph += TAU * lerpf(110.0, 34.0, u) / float(SAMPLE_RATE)
		var env = pow(1.0 - u, 1.8) * minf(1.0, t / 0.01)
		buf[i] = clampf((sin(ph) * 0.55 + lp * 1.3) * env * 0.48, -0.9, 0.9)
	return _pack_pcm16(buf)
