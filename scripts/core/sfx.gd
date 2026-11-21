extends Node

# Refined 16-bit 44.1kHz warm harmonic audio synthesizer (zero harsh square waves).

const SR: int = 44100
const POOL: int = 8

var muted: bool = false
var _bank: Dictionary = {}
var _vols: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _idx: int = 0
var _last_ms: Dictionary = {}

func _ready() -> void:
	for _i in range(POOL):
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_reg("click",    _tone(0.055, 520.0, 740.0, 0.85, 0.14), -14.0)
	_reg("select",   _chord(0.11, [440.0, 659.25], 0.17), -12.0)
	_reg("mine",     _chord(0.13, [329.63, 493.88], 0.14), -15.0)
	_reg("build",    _thump_chime(0.22, 118.0, 392.0, 0.22), -11.0)
	_reg("wire",     _chord(0.17, [523.25, 783.99, 1046.5], 0.16), -12.0)
	_reg("dock",     _arpeggio(0.28, [349.23, 440.0, 523.25, 698.46], 0.19), -10.0)
	_reg("research", _arpeggio(0.44, [440.0, 554.37, 659.25, 880.0], 0.20), -9.0)
	_reg("launch",   _whoosh(0.56), -9.0)
	_reg("laser",    _tone(0.15, 240.0, 480.0, 0.65, 0.14), -13.0)
	_reg("pop",      _tone(0.08, 350.0, 525.0, 1.32, 0.15), -13.0)
	_reg("error",    _tone(0.18, 192.0, 154.0, 0.78, 0.15), -12.0)
	_reg("boom",     _boom(0.48), -9.0)
	_reg("victory",  _arpeggio(0.86, [523.25, 659.25, 783.99, 1046.5, 1318.5], 0.22), -8.0)

func _reg(k: String, w: AudioStreamWAV, db: float) -> void:
	_bank[k] = w
	_vols[k] = db

func play(k: String, jitter: float = 0.04) -> void:
	if muted or not _bank.has(k):
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_ms.get(k, 0)) < 55:
		return
	_last_ms[k] = now
	var p: AudioStreamPlayer = _players[_idx]
	_idx = (_idx + 1) % POOL
	p.stop()
	p.stream = _bank[k]
	p.volume_db = float(_vols.get(k, -12.0))
	p.pitch_scale = 1.0 + randf_range(-jitter, jitter)
	p.play()

func preset_count() -> int:
	return _bank.size()

func _pack(buf: PackedFloat32Array) -> AudioStreamWAV:
	var b := PackedByteArray()
	b.resize(buf.size() * 2)
	for i in range(buf.size()):
		var v := clampi(int(round(clampf(buf[i], -0.95, 0.95) * 32767.0)), -32768, 32767)
		b[i * 2] = v & 0xFF
		b[i * 2 + 1] = (v >> 8) & 0xFF
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = SR
	w.stereo = false
	w.data = b
	return w

func _env(t: float, dur: float, atk: float, dec: float) -> float:
	if t < atk:
		return t / maxf(0.001, atk)
	var r := maxf(0.0, 1.0 - (t - atk) / maxf(0.001, dur - atk))
	return pow(r, 1.6) * exp(-maxf(0.0, t - atk) / maxf(0.02, dec))

func _tone(dur: float, f0: float, f1: float, sweep: float, gain: float) -> AudioStreamWAV:
	var n := int(dur * SR)
	var buf := PackedFloat32Array(); buf.resize(n)
	var p0 := 0.0; var p1 := 0.0
	for i in range(n):
		var t := float(i) / float(SR)
		p0 += TAU * f0 * lerpf(1.0, sweep, t / dur) / float(SR)
		p1 += TAU * f1 * lerpf(1.0, sweep, t / dur) / float(SR)
		buf[i] = (sin(p0) * 0.72 + sin(p1) * 0.28) * _env(t, dur, 0.004, dur * 0.75) * gain
	return _pack(buf)

func _chord(dur: float, freqs: Array, gain: float) -> AudioStreamWAV:
	var n := int(dur * SR)
	var buf := PackedFloat32Array(); buf.resize(n)
	var inv := 1.0 / maxf(1.0, float(freqs.size()))
	for i in range(n):
		var t := float(i) / float(SR)
		var s := 0.0
		for f in freqs:
			s += sin(TAU * float(f) * t) * 0.8 + sin(TAU * float(f) * 2.0 * t) * 0.2 * exp(-t * 14.0)
		buf[i] = s * inv * _env(t, dur, 0.005, dur * 0.8) * gain
	return _pack(buf)

func _thump_chime(dur: float, bf: float, cf: float, gain: float) -> AudioStreamWAV:
	var n := int(dur * SR)
	var buf := PackedFloat32Array(); buf.resize(n)
	var pb := 0.0
	for i in range(n):
		var t := float(i) / float(SR)
		pb += TAU * lerpf(bf, bf * 0.45, minf(1.0, t * 7.0)) / float(SR)
		var th := sin(pb) * exp(-t * 18.0) * 0.62
		var ch := (sin(TAU * cf * t) * 0.6 + sin(TAU * cf * 1.5 * t) * 0.4) * _env(t, dur, 0.01, dur * 0.8) * 0.55
		buf[i] = (th + ch) * gain
	return _pack(buf)

func _arpeggio(dur: float, notes: Array, gain: float) -> AudioStreamWAV:
	var n := int(dur * SR)
	var buf := PackedFloat32Array(); buf.resize(n)
	var step := dur / float(notes.size())
	for i in range(n):
		var t := float(i) / float(SR)
		var s := 0.0
		for k in range(notes.size()):
			var lt := t - float(k) * step * 0.72
			if lt >= 0.0:
				var f := float(notes[k])
				s += (sin(TAU * f * lt) * 0.75 + sin(TAU * f * 2.0 * lt) * 0.25 * exp(-lt * 10.0)) * _env(lt, dur - float(k) * step * 0.55, 0.008, 0.26)
		buf[i] = tanh(s * 0.55) * gain
	return _pack(buf)

func _whoosh(dur: float) -> AudioStreamWAV:
	var n := int(dur * SR)
	var buf := PackedFloat32Array(); buf.resize(n)
	var lp := 0.0; var ph := 0.0
	var rng := RandomNumberGenerator.new(); rng.seed = 9001
	for i in range(n):
		var t := float(i) / float(SR)
		var u := t / dur
		lp += (rng.randf_range(-1.0, 1.0) - lp) * lerpf(0.03, 0.14, sin(u * PI))
		ph += TAU * lerpf(90.0, 560.0, u * u) / float(SR)
		buf[i] = clampf((lp * 1.35 + sin(ph) * 0.36 * exp(-absf(u - 0.35) * 4.0)) * sin(u * PI) * exp(-u * 1.3) * 0.44, -0.9, 0.9)
	return _pack(buf)

func _boom(dur: float) -> AudioStreamWAV:
	var n := int(dur * SR)
	var buf := PackedFloat32Array(); buf.resize(n)
	var lp := 0.0; var ph := 0.0
	var rng := RandomNumberGenerator.new(); rng.seed = 4242
	for i in range(n):
		var t := float(i) / float(SR)
		var u := t / dur
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.055
		ph += TAU * lerpf(110.0, 32.0, u) / float(SR)
		buf[i] = clampf((sin(ph) * 0.55 + lp * 1.3) * pow(1.0 - u, 1.8) * minf(1.0, t / 0.01) * 0.48, -0.9, 0.9)
	return _pack(buf)
