extends SceneTree

# Test audio synth generation in 16-bit format
func _init() -> void:
	print("TESTING 16-BIT AUDIO STREAM CREATION")
	var sample_rate = 44100
	var duration = 0.2
	var num_samples = int(sample_rate * duration)
	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	
	var data = PackedByteArray()
	data.resize(num_samples * 2)
	
	for i in range(num_samples):
		var t = float(i) / float(sample_rate)
		var val = sin(t * 440.0 * TAU) * exp(-t * 15.0)
		var s16 = clampi(int(val * 32767.0 * 0.5), -32768, 32767)
		data.encode_s16(i * 2, s16)
		
	stream.data = data
	print("STREAM DATA SIZE: ", stream.data.size(), " (Expected: ", num_samples * 2, ")")
	assert(stream.data.size() == num_samples * 2, "Data size mismatch!")
	print("AUDIO SYNTH TEST PASSED 100%")
	quit(0)
