extends SceneTree

func _init() -> void:
	print("SCREENSHOT RUNNER STARTED")

func _process(_delta: float) -> bool:
	var frame = get_frame()
	if frame == 30:
		print("CAPTURING FRAME 30...")
		var viewport = root.get_viewport()
		var img = viewport.get_texture().get_image()
		var out_path = "res://docs/art/ingame_screenshot.png"
		var err = img.save_png(out_path)
		print("SAVED SCREENSHOT: ", out_path, " ERR: ", err)
		quit(0)
		return true
	return false
