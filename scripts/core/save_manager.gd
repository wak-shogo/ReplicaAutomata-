extends Node

# ==============================================================================
# STAR REPLICA: AUTOMA - SAVE MANAGER
# ==============================================================================

const SAVE_PATH: String = "user://star_replica_save_v2.json"

func save_game(world: Node, factory: Node, player: Node2D) -> bool:
	var data = {
		"version": 2,
		"game_state": GameState.to_dict(),
		"player_pos": [player.position.x, player.position.y],
		"factory": factory.to_dict() if factory and factory.has_method("to_dict") else {},
	}
	var f = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if not f:
		GameState.emit_signal("log_event", "Save failed (IO error)", "error")
		return false
	f.store_string(JSON.stringify(data))
	f.close()
	GameState.emit_signal("log_event", "Colony saved cleanly.", "good")
	AudioSynth.play_synth("save")
	return true

func load_game(factory: Node, player: Node2D) -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var f = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not f:
		return false
	var txt = f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	if not (parsed is Dictionary):
		return false
	if parsed.has("game_state"):
		GameState.from_dict(parsed["game_state"])
	if parsed.has("player_pos"):
		var pp = parsed["player_pos"]
		if pp is Array and pp.size() == 2:
			player.position = Vector2(float(pp[0]), float(pp[1]))
			player.velocity = Vector2.ZERO
	if parsed.has("factory") and factory and factory.has_method("from_dict"):
		factory.from_dict(parsed["factory"])
	GameState.emit_signal("log_event", "Loaded saved colony.", "good")
	return true

func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
