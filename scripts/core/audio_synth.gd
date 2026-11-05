extends Node

# 外部アセット不要のリアルタイム数学的波形合成オーディオマネージャー
var players: Array[AudioStreamPlayer] = []
var max_polyphony: int = 8
var current_player: int = 0

func _ready() -> void:
	for i in range(max_polyphony):
		var p = AudioStreamPlayer.new()
		add_child(p)
		players.append(p)

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
			_:
				val = sin(t * 440.0 * TAU) * 0.5
		
		# 8-bit unsigned (0..255, center 128)
		var b = clampi(int((val * 0.4 + 0.5) * 255.0), 0, 255)
		data[i] = b
		
	stream.data = data
	player.stream = stream
	player.play()
