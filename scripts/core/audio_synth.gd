extends Node

# ==============================================================================
# STAR REPLICA: AUTOMA - HI-FI PROCEDURAL AUDIO SYNTHESIZER
# 16-Bit / 44.1kHz Pure Mathematical Waveform & FM Synthesis Engine
# Zero external assets, zero square wave harshness, zero quantization noise.
# ==============================================================================

var players: Array[AudioStreamPlayer] = []
var max_polyphony: int = 12
var current_player: int = 0

# 環境音・持続音専用プレイヤー
var ambient_sun: AudioStreamPlayer
var ambient_space: AudioStreamPlayer
var ambient_blackhole: AudioStreamPlayer
var ambient_thruster: AudioStreamPlayer

# 事前ベイクされた高音質 16-bit オーディオストリームキャッシュ
var cached_streams: Dictionary = {}
var volume_levels: Dictionary = {}

var is_muted: bool = false

func _ready() -> void:
	# 1. ポリフォニー再生プレイヤーの初期化
	for i in range(max_polyphony):
		var p = AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
		
	# 2. 全SEプリセットの事前ベイク（実行時GCゼロ・低遅延・高音質）
	_bake_all_sound_effects()
	
	# 3. 宇宙・天体アンビエント持続音の初期化
	ambient_space = _create_looping_stream_player("space_drone", 48.0, 1.8, 0.08)
	ambient_sun = _create_looping_stream_player("sun_plasma", 40.0, 1.4, 0.0)
	ambient_blackhole = _create_looping_stream_player("bh_warp", 28.0, 2.0, 0.0)
	ambient_thruster = _create_looping_stream_player("thruster", 60.0, 1.0, 0.0)

# ==============================================================================
# SE プリセット事前合成 (16-bit 44.1kHz High-Fidelity Waveforms)
# ==============================================================================
func _bake_all_sound_effects() -> void:
	# 各効果音の音響設計（音色・持続時間・音量オフセット）
	_bake_preset("click", 0.05, -14.0)
	_bake_preset("select", 0.08, -12.0)
	_bake_preset("mine", 0.12, -15.0)
	_bake_preset("laser", 0.16, -11.0)
	_bake_preset("craft", 0.28, -10.0)
	_bake_preset("build", 0.24, -11.0)
	_bake_preset("replicate", 0.36, -9.0)
	_bake_preset("launch", 0.38, -9.0)
	_bake_preset("alert", 0.24, -10.0)
	_bake_preset("error", 0.16, -12.0)
	_bake_preset("pop", 0.12, -12.0)
	_bake_preset("victory", 0.70, -8.0)
	_bake_preset("mega", 0.40, -10.0)
	_bake_preset("explosion", 0.32, -9.0)
	_bake_preset("pulsar_pulse", 0.22, -11.0)
	_bake_preset("wormhole_warp", 0.45, -10.0)
	_bake_preset("celestial_depleted", 0.22, -11.0)

func _bake_preset(type: String, duration: float, vol_db: float) -> void:
	var sample_rate = 44100
	var num_samples = int(sample_rate * duration)
	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	
	var data = PackedByteArray()
	data.resize(num_samples * 2)
	
	for i in range(num_samples):
		var t = float(i) / float(sample_rate)
		var progress = t / duration
		var val = 0.0
		
		match type:
			"click":
				# [CLICK] 洗練された触覚的ハイテック・マイクロポップ（純サイン波＋超急峻指数減衰）
				# 矩形波のようなガリ音ゼロ
				var freq = 1200.0 - progress * 400.0
				val = sin(t * freq * TAU) * exp(-progress * 14.0)
				
			"select":
				# [SELECT] 繊細なクリスタル調グラス・デュオトーン（C6 1046Hz -> E6 1318Hz）
				if progress < 0.45:
					var env = exp(-progress * 12.0)
					val = (sin(t * 1046.50 * TAU) + sin(t * 2093.0 * TAU) * 0.18) * env
				else:
					var p2 = (progress - 0.45) / 0.55
					var env2 = exp(-p2 * 10.0)
					val = (sin(t * 1318.51 * TAU) + sin(t * 2637.0 * TAU) * 0.18) * env2
				
			"mine":
				# [MINE] 採掘レーザーの心地よい共鳴エネルギー（完全ハーモニックサイン波）
				# ホワイトノイズの耳障りなジャリジャリ音を撤廃し、上品なプラズマ共鳴音へ刷新
				var f1 = 360.0
				var f2 = 540.0 # 完全5度の心地よい和声
				var tremolo = 0.85 + 0.15 * sin(t * 18.0 * TAU)
				var env = (sin(progress * PI) if progress < 0.15 else exp(-(progress - 0.15) * 4.5))
				val = (sin(t * f1 * TAU) * 0.65 + sin(t * f2 * TAU) * 0.35) * tremolo * env
				
			"laser":
				# [LASER] 防衛タレット・艦隊迎撃パルスレーザー
				# 矩形波を完全排除し、美しい滑らかなサイン波周波数スイープ（820Hz -> 200Hz）
				var freq = 200.0 + 620.0 * exp(-progress * 7.5)
				var env = exp(-progress * 6.5)
				val = (sin(t * freq * TAU) + sin(t * freq * 2.0 * TAU) * 0.15) * env
				
			"craft", "build":
				# [CRAFT / BUILD] 設備建造・確定の未来的メジャーコード・アルペジオ
				# A4 (440) -> C#5 (554.37) -> E5 (659.25) の温かみのある三重奏
				var step = clampi(int(progress * 3.0), 0, 2)
				var freqs = [440.0, 554.37, 659.25]
				var f_cur = freqs[step]
				var env = exp(-fmod(progress * 3.0, 1.0) * 4.5) * (1.0 - progress * 0.3)
				val = (sin(t * f_cur * TAU) + sin(t * f_cur * 2.0 * TAU) * 0.2) * env
				
			"replicate":
				# [REPLICATE] 自己複製ドローン合体アルペジオ（C5 -> E5 -> G5 -> C6）
				# 澄み切ったクリスタルベルの豊かな余韻
				var step = clampi(int(progress * 4.0), 0, 3)
				var freqs = [523.25, 659.25, 783.99, 1046.50]
				var f_cur = freqs[step]
				var env = exp(-fmod(progress * 4.0, 1.0) * 3.8) * (1.0 - progress * 0.25)
				val = (sin(t * f_cur * TAU) + sin(t * f_cur * 2.0 * TAU) * 0.15 + sin(t * f_cur * 3.0 * TAU) * 0.05) * env
				
			"launch":
				# [LAUNCH] マスドライバー射出・プローブ離陸の重低音サブベース
				# 50Hz から 160Hz への力強くも柔らかなサイン波共鳴スイープ
				var freq = 50.0 + progress * 110.0
				var env = sin(progress * PI) if progress < 0.2 else (1.0 - (progress - 0.2) / 0.8)
				val = (sin(t * freq * TAU) + sin(t * freq * 1.5 * TAU) * 0.25) * env
				
			"alert":
				# [ALERT] 警告音（太陽放射・空爆アラート）
				# 耳を刺す不快な矩形波ブザーを廃止し、スマートな2音サイン波HUDチャイム（D5 587Hz -> F#5 740Hz）
				var is_high = (fmod(progress, 0.45) > 0.22)
				var f_cur = 739.99 if is_high else 587.33
				var sub_env = exp(-fmod(progress, 0.225) * 8.0)
				val = (sin(t * f_cur * TAU) + sin(t * f_cur * 2.0 * TAU) * 0.12) * sub_env * (1.0 - progress * 0.3)
				
			"error":
				# [ERROR] 資源不足・操作無効時
				# 鋭利なソートゥースノイズを廃止し、丸みのある低音ダンプド・シンセタップ（120Hz -> 70Hz）
				var freq = 70.0 + 50.0 * exp(-progress * 15.0)
				var env = exp(-progress * 14.0)
				val = sin(t * freq * TAU) * env
				
			"pop":
				# [POP] 敵ドローン撃破・破砕音
				var freq = 80.0 + 260.0 * exp(-progress * 22.0)
				var env = exp(-progress * 16.0)
				val = (sin(t * freq * TAU) + sin(t * freq * 2.0 * TAU) * 0.2) * env
				
			"victory":
				# [VICTORY] マイルストーン達成・星系解放の壮大なメジャー9thシンセ和音
				# C5(523.25) + E5(659.25) + G5(783.99) + B5(987.77) + D6(1174.66)
				var env = (sin(progress * PI * 0.5) if progress < 0.1 else exp(-(progress - 0.1) * 3.0))
				var s1 = sin(t * 523.25 * TAU) * 0.30
				var s2 = sin(t * 659.25 * TAU) * 0.25
				var s3 = sin(t * 783.99 * TAU) * 0.22
				var s4 = sin(t * 987.77 * TAU) * 0.15
				var s5 = sin(t * 1174.66 * TAU) * 0.08
				val = (s1 + s2 + s3 + s4 + s5) * env
				
			"mega":
				# [MEGA] メガストラクチャー建造パルス（温かみのある深層サイン波）
				var freq = 55.0 + sin(t * 6.0) * 12.0
				var env = sin(progress * PI)
				val = (sin(t * freq * TAU) + sin(t * freq * 2.0 * TAU) * 0.15) * env
				
			"explosion":
				# [EXPLOSION] 柔らかな深層爆破音（低音フィルタード・ランブル）
				var rumble = sin(t * (42.0 + (1.0 - progress) * 60.0) * TAU)
				var soft_noise = (randf() * 2.0 - 1.0) * exp(-progress * 8.0) * 0.35
				var env = exp(-progress * 5.0)
				val = (rumble * 0.65 + soft_noise) * env
				
			"pulsar_pulse":
				# [PULSAR] パルサーの繊細な高周波ビート
				var freq = 1100.0 * exp(-progress * 18.0) + 120.0
				val = sin(t * freq * TAU) * exp(-progress * 22.0)
				
			"wormhole_warp":
				# [WARP] ワームホール跳躍音
				var freq = 45.0 + progress * 320.0 + sin(t * 24.0) * 35.0
				var env = sin(progress * PI)
				val = (sin(t * freq * TAU) + sin(t * freq * 1.5 * TAU) * 0.2) * env
				
			"celestial_depleted":
				# [DEPLETED] 資源枯渇アナウンス（柔らかく減衰するマイナートーン）
				var is_high = (progress < 0.5)
				var f_cur = 440.0 if is_high else 349.23
				var p_sub = fmod(progress, 0.5) * 2.0
				var env = exp(-p_sub * 7.0)
				val = (sin(t * f_cur * TAU) + sin(t * f_cur * 2.0 * TAU) * 0.15) * env
				
			_:
				val = sin(t * 440.0 * TAU) * (1.0 - progress)
		
		# ゼロクロス端のフェード（ポップノイズ完全防止）
		var fade_len = 64
		if i < fade_len:
			val *= float(i) / float(fade_len)
		elif i > num_samples - fade_len:
			val *= float(num_samples - i) / float(fade_len)
			
		# ソフトサチュレーション（クリッピング完全防止）
		val = tanh(val * 0.85)
		
		# 16-bit 有符号整数 (-32768 .. 32767)
		var s16 = clampi(int(val * 32767.0 * 0.75), -32768, 32767)
		data.encode_s16(i * 2, s16)
		
	stream.data = data
	cached_streams[type] = stream
	volume_levels[type] = vol_db

# ==============================================================================
# アンビエントループプレイヤーの生成 (16-bit 44.1kHz)
# ==============================================================================
func _create_looping_stream_player(preset: String, base_freq: float, duration: float, initial_volume_db: float) -> AudioStreamPlayer:
	var player = AudioStreamPlayer.new()
	add_child(player)
	
	var sample_rate = 44100
	var num_samples = int(sample_rate * duration)
	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = num_samples
	
	var data = PackedByteArray()
	data.resize(num_samples * 2)
	
	for i in range(num_samples):
		var t = float(i) / float(sample_rate)
		var val = 0.0
		match preset:
			"space_drone":
				# 深宇宙の静謐な真空アンビエント（42Hz基音 + 84Hz倍音、完全純音サイン波）
				val = sin(t * base_freq * TAU) * 0.7 + sin(t * (base_freq * 2.0) * TAU) * 0.25
				val += sin(t * 0.5 * TAU) * 0.05
			"sun_plasma":
				# 恒星プラズマの深遠な低周波共鳴（38Hz）
				val = sin(t * base_freq * TAU + sin(t * 3.5) * 0.6) * 0.75
			"bh_warp":
				# ブラックホール事象の地平面（28Hz超重低音）
				val = sin(t * base_freq * TAU) * (0.8 + sin(t * 2.0 * PI) * 0.2)
			"thruster":
				# イオン推進の柔らかなサブハミング
				var hum = sin(t * base_freq * TAU) * 0.6
				var sub = sin(t * (base_freq * 1.5) * TAU) * 0.25
				val = hum + sub
		
		# ループ端のクロスフェード平滑化
		var fade_len = int(sample_rate * 0.08)
		if i < fade_len:
			val *= float(i) / float(fade_len)
		elif i > num_samples - fade_len:
			val *= float(num_samples - i) / float(fade_len)
			
		val = tanh(val * 0.6)
		var s16 = clampi(int(val * 32767.0 * 0.5), -32768, 32767)
		data.encode_s16(i * 2, s16)
		
	stream.data = data
	player.stream = stream
	player.volume_db = linear_to_db(initial_volume_db) if initial_volume_db > 0.0 else -80.0
	if is_inside_tree(): player.play()
	return player

# ==============================================================================
# 天体接近度・スラスター出力に応じた環境音ブレンド
# ==============================================================================
func update_celestial_ambience(near_sun_ratio: float, near_bh_ratio: float, thruster_power: float) -> void:
	if not ambient_sun or not ambient_blackhole or not ambient_thruster: return
	
	# 太陽接近度（穏やかな低音ハミング）
	var target_sun_vol = clampf(near_sun_ratio, 0.0, 1.0) * 0.28
	ambient_sun.volume_db = linear_to_db(maxf(0.001, target_sun_vol)) if target_sun_vol > 0.01 else -80.0
	
	# ブラックホール接近度
	var target_bh_vol = clampf(near_bh_ratio, 0.0, 1.0) * 0.32
	ambient_blackhole.volume_db = linear_to_db(maxf(0.001, target_bh_vol)) if target_bh_vol > 0.01 else -80.0
	
	# スラスター噴射音（耳障りなノイズではなく、滑らかなイオン推進低周波音）
	var target_thrust_vol = clampf(thruster_power, 0.0, 1.0) * 0.22
	ambient_thruster.volume_db = linear_to_db(maxf(0.001, target_thrust_vol)) if target_thrust_vol > 0.01 else -80.0

# ==============================================================================
# SE 再生インターフェース
# ==============================================================================
func play_synth(type: String) -> void:
	if is_muted or not is_inside_tree(): return
	
	var stream: AudioStreamWAV = cached_streams.get(type, null)
	if not stream:
		# フォールバック
		stream = cached_streams.get("click", null)
		if not stream: return
		
	var player = players[current_player]
	current_player = (current_player + 1) % max_polyphony
	
	player.stream = stream
	player.volume_db = volume_levels.get(type, -10.0)
	player.play()

func toggle_mute() -> bool:
	is_muted = not is_muted
	AudioServer.set_bus_mute(0, is_muted)
	return is_muted
