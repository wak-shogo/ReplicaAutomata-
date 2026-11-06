extends Node

# 外部アセット不要のリアルタイム数学的波形合成オーディオマネージャー
var players: Array[AudioStreamPlayer] = []
var max_polyphony: int = 8
var current_player: int = 0

# 環境音・持続音専用プレイヤー
var ambient_sun: AudioStreamPlayer
var ambient_space: AudioStreamPlayer
var ambient_blackhole: AudioStreamPlayer
var ambient_thruster: AudioStreamPlayer

var cur_ambient_type: String = "space"

func _ready() -> void:
	for i in range(max_polyphony):
		var p = AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
		
	# 環境音プレイヤー初期化
	ambient_space = _create_looping_synth_player("space_drone", 55.0, 1.2, 0.15)
	ambient_sun = _create_looping_synth_player("sun_plasma", 42.0, 1.0, 0.0)
	ambient_blackhole = _create_looping_synth_player("bh_warp", 32.0, 1.5, 0.0)
	ambient_thruster = _create_looping_synth_player("thruster", 110.0, 0.8, 0.0)

func _create_looping_synth_player(preset: String, base_freq: float, duration: float, initial_volume_db: float) -> AudioStreamPlayer:
	var player = AudioStreamPlayer.new()
	add_child(player)
	
	var sample_rate = 22050
	var num_samples = int(sample_rate * duration)
	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_8_BITS
	stream.mix_rate = sample_rate
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = num_samples
	
	var data = PackedByteArray()
	data.resize(num_samples)
	
	for i in range(num_samples):
		var t = float(i) / float(sample_rate)
		var val = 0.0
		match preset:
			"space_drone":
				# 深宇宙の静寂とサイン波ドローン（55Hz + 110Hz + わずかなFM変調）
				val = sin(t * base_freq * TAU) * 0.6 + sin(t * (base_freq * 2.01) * TAU) * 0.3
				val += sin(t * 1.5 * TAU) * 0.1
			"sun_plasma":
				# 太陽の超低周波ゴロゴロ音＋ランダムノイズ乱流
				var sub = sin(t * base_freq * TAU + sin(t * 8.0) * 1.5)
				var noise = (randf() * 2.0 - 1.0) * 0.35
				val = sub * 0.65 + noise
			"bh_warp":
				# 事象の地平面の重力うなり（32Hz重低音＋うなり周期）
				val = sin(t * base_freq * TAU) * (0.7 + sin(t * 3.14 * 2.0) * 0.3)
			"thruster":
				# イオン・プラズマ推進のホワイトノイズ＋110Hzハミング
				var hum = sin(t * base_freq * TAU) * 0.4
				var noise = (randf() * 2.0 - 1.0) * 0.6
				val = hum + noise
		
		# ゼロクロス付近の平滑化（ループ時のクリックノイズ防止）
		var edge_fade = 1.0
		var fade_len = int(sample_rate * 0.05)
		if i < fade_len:
			edge_fade = float(i) / float(fade_len)
		elif i > num_samples - fade_len:
			edge_fade = float(num_samples - i) / float(fade_len)
		val *= edge_fade
		
		var b = clampi(int((val * 0.35 + 0.5) * 255.0), 0, 255)
		data[i] = b
		
	stream.data = data
	player.stream = stream
	player.volume_db = linear_to_db(initial_volume_db) if initial_volume_db > 0.0 else -80.0
	player.play()
	return player

# プレイヤーの飛行状態・天体近接状態に応じてリアルタイム音響ブレンド
func update_celestial_ambience(near_sun_ratio: float, near_bh_ratio: float, thruster_power: float) -> void:
	# 太陽接近度（0.0 〜 1.0）
	var target_sun_vol = clampf(near_sun_ratio, 0.0, 1.0) * 0.6
	ambient_sun.volume_db = linear_to_db(maxf(0.001, target_sun_vol)) if target_sun_vol > 0.01 else -80.0
	
	# ブラックホール接近度（0.0 〜 1.0）
	var target_bh_vol = clampf(near_bh_ratio, 0.0, 1.0) * 0.7
	ambient_blackhole.volume_db = linear_to_db(maxf(0.001, target_bh_vol)) if target_bh_vol > 0.01 else -80.0
	
	# スラスター音
	var target_thrust_vol = clampf(thruster_power, 0.0, 1.0) * 0.45
	ambient_thruster.volume_db = linear_to_db(maxf(0.001, target_thrust_vol)) if target_thrust_vol > 0.01 else -80.0

func play_synth(type: String) -> void:
	var player = players[current_player]
	current_player = (current_player + 1) % max_polyphony
	
	var sample_rate = 22050
	var duration = 0.25
	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_8_BITS
	stream.mix_rate = sample_rate
	
	var data = PackedByteArray()
	var num_samples = int(sample_rate * duration)
	data.resize(num_samples)
	
	for i in range(num_samples):
		var t = float(i) / float(sample_rate)
		var val = 0.0
		match type:
			"launch": # マスドライバー射出（急速に周波数が上がるスイープ）
				var freq = 120.0 + (t / duration) * 880.0
				val = sin(t * freq * TAU) * (1.0 - t / duration)
			"laser": # パルスレーザー
				var freq = 900.0 - (t / duration) * 500.0
				val = (0.5 if sin(t * freq * TAU) > 0.0 else -0.5) * (1.0 - t / duration)
			"mine": # 採掘火花
				val = (randf() * 2.0 - 1.0) * 0.4 * (1.0 - t / duration)
			"click": # UIクリック音
				var freq = 1200.0
				val = sin(t * freq * TAU) * pow(1.0 - t / duration, 4.0) * 0.4
			"victory": # 勝利ファンファーレ和音
				var f1 = 523.25 # C5
				var f2 = 659.25 # E5
				var f3 = 783.99 # G5
				val = (sin(t * f1 * TAU) + sin(t * f2 * TAU) + sin(t * f3 * TAU)) * 0.33 * (1.0 - t / duration)
			"mega": # メガストラクチャー重低音パルス
				var freq = 65.0 + sin(t * 12.0) * 20.0
				val = sin(t * freq * TAU) * (1.0 - t / duration) * 0.8
			"build": # 建設カシャーン音
				var freq = 440.0 + sin(t * 50.0) * 100.0
				val = sin(t * freq * TAU) * (1.0 - t / duration)
			"explosion": # 爆発音
				val = (randf() * 2.0 - 1.0) * pow(1.0 - t / duration, 2.0)
			"pulsar_pulse": # パルサーの鋭い放射線ビート
				var freq = 1800.0 * (1.0 - t / duration)
				val = sin(t * freq * TAU) * exp(-t * 25.0)
			"wormhole_warp": # 重力ワームホール跳躍音
				var freq = 40.0 + sin(t * 80.0) * 120.0 + (t / duration) * 600.0
				val = sin(t * freq * TAU) * (1.0 - t / duration)
			"celestial_depleted": # 天体埋蔵量枯渇ワーニング
				var freq = 330.0 if fmod(t, 0.08) < 0.04 else 220.0
				val = (0.4 if sin(t * freq * TAU) > 0.0 else -0.4) * (1.0 - t / duration)
			_:
				val = sin(t * 440.0 * TAU) * 0.5
		
		# 8-bit unsigned (0..255, center 128)
		var b = clampi(int((val * 0.4 + 0.5) * 255.0), 0, 255)
		data[i] = b
		
	stream.data = data
	player.stream = stream
	player.play()

var is_muted: bool = false
func toggle_mute() -> bool:
	is_muted = not is_muted
	AudioServer.set_bus_mute(0, is_muted)
	return is_muted
