extends SceneTree

func _init() -> void:
	var arr = PackedByteArray()
	arr.resize(4)
	arr.encode_s16(0, 12345)
	var read_val = arr.decode_s16(0)
	print("ENCODE S16 TEST: ", read_val)
	quit(0 if read_val == 12345 else 1)
