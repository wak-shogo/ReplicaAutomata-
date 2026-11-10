extends SceneTree

func _init() -> void:
	print("VERIFYING HI-FI AUDIO SYNTHESIZER...")
	var audio_script = load("res://scripts/core/audio_synth.gd")
	var synth = audio_script.new()
	root.add_child(synth)
	synth._ready()
	
	var presets = [
		"click", "select", "mine", "laser", "craft", "build",
		"replicate", "launch", "alert", "error", "pop", "victory",
		"mega", "explosion", "pulsar_pulse", "wormhole_warp", "celestial_depleted"
	]
	
	for p in presets:
		assert(synth.cached_streams.has(p), "Missing cached preset: " + p)
		var st: AudioStreamWAV = synth.cached_streams[p]
		assert(st.format == AudioStreamWAV.FORMAT_16_BITS, "Not 16-bit format: " + p)
		assert(st.mix_rate == 44100, "Not 44.1kHz: " + p)
		assert(st.data.size() > 0, "Empty stream data: " + p)
		synth.play_synth(p)
		print("PRESET VERIFIED [16-BIT 44.1kHz]: ", p, " (Size: ", st.data.size(), " bytes, Vol: ", synth.volume_levels[p], " dB)")
		
	print(">>> ALL 17 HI-FI PROCEDURAL SOUND PRESETS VERIFIED 100% SUCCESS! <<<")
	quit(0)
