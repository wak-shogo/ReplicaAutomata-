extends Node

# STAR REPLICA: AUTOMA - セーブ＆ロード・オートセーブマネージャー
const SAVE_PATH: String = "user://star_replica_save.json"
const AUTO_SAVE_INTERVAL: float = 180.0 # 3分間隔

var auto_save_timer: float = 0.0

func _ready() -> void:
	print("[SaveManager] Initialized. Save file path: ", OS.get_user_data_dir())

func _process(delta: float) -> void:
	auto_save_timer += delta
	if auto_save_timer >= AUTO_SAVE_INTERVAL:
		auto_save_timer = 0.0
		save_game(true)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		# F5: クイックセーブ
		if event.keycode == KEY_F5:
			save_game(false)
		# F9: クイックロード
		elif event.keycode == KEY_F9:
			load_game()

func save_game(is_auto: bool = false) -> bool:
	var root_node = get_tree().current_scene
	if not root_node:
		return false
		
	var player = root_node.get_node_or_null("Player")
	var grid = root_node.get_node_or_null("GridManager")
	
	var data = {
		"version": 1,
		"timestamp": Time.get_datetime_string_from_system(),
		"player": {
			"x": player.global_position.x if player else 780.0,
			"y": player.global_position.y if player else 520.0,
			"vx": player.velocity.x if player else 0.0,
			"vy": player.velocity.y if player else 0.0
		},
		"story_phase": GameState.story_phase,
		"unlocked_tools": GameState.unlocked_tools.duplicate(),
		"resources": GameState.resources.duplicate(),
		"items": GameState.items.duplicate(),
		"fleet_count": GameState.fleet_count,
		"fleet_doctrine": GameState.fleet_doctrine,
		"attached_drones": GameState.attached_drones,
		"quest_index": GameState.quest_index,
		"hostile_core_health": GameState.hostile_core_health,
		"liberation_progress": GameState.liberation_progress,
		"megastructures": GameState.megastructures.duplicate(true),
		"active_megastructure_project": GameState.active_megastructure_project,
		"placed_buildings": grid.placed_buildings.duplicate(true) if grid else []
	}
	
	var json_str = JSON.stringify(data, "\t")
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if not file:
		GameState.add_log("SAVE ERROR: CANNOT OPEN FILE FOR WRITING")
		return false
		
	file.store_string(json_str)
	file.close()
	
	AudioSynth.play_synth("click")
	if is_auto:
		GameState.add_log("AUTOSAVE COMPLETED [PROGRESS SECURED]")
	else:
		GameState.add_log("QUICK SAVE COMPLETED [F5] -> SLOT SAVED")
	print("[SaveManager] Game saved to: ", SAVE_PATH)
	return true

func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		GameState.add_log("LOAD FAILED: NO SAVE FILE FOUND")
		return false
		
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		GameState.add_log("LOAD ERROR: CANNOT OPEN SAVE FILE")
		return false
		
	var json_str = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var parse_result = json.parse(json_str)
	if parse_result != OK:
		GameState.add_log("LOAD ERROR: CORRUPTED SAVE JSON")
		return false
		
	var data = json.get_data()
	if not data is Dictionary:
		return false
		
	var root_node = get_tree().current_scene
	var player = root_node.get_node_or_null("Player")
	var grid = root_node.get_node_or_null("GridManager")
	var swarm = root_node.get_node_or_null("SwarmSimulation")
	
	# プレイヤー復元
	if player and data.has("player"):
		player.global_position = Vector2(data["player"]["x"], data["player"]["y"])
		player.velocity = Vector2(data["player"]["vx"], data["player"]["vy"])

	# ストーリーフェーズ ＆ 技術ツリー復元
	if data.has("story_phase"):
		GameState.set_story_phase(int(data["story_phase"]))
	if data.has("unlocked_tools"):
		for t_name in data["unlocked_tools"].keys():
			if data["unlocked_tools"][t_name]:
				GameState.unlock_tool(t_name)
		
	# リソース＆アイテム復元
	if data.has("resources"):
		for k in data["resources"].keys():
			GameState.resources[k] = data["resources"][k]
			GameState.resource_changed.emit(k, GameState.resources[k])
			
	if data.has("items"):
		for k in data["items"].keys():
			GameState.items[k] = data["items"][k]
			GameState.item_changed.emit(k, GameState.items[k])
			
	# 艦隊復元
	if data.has("fleet_count"):
		GameState.fleet_count = int(data["fleet_count"])
		GameState.fleet_changed.emit(GameState.fleet_count, GameState.fleet_max)
		if swarm:
			swarm.friendly_active_count = GameState.fleet_count
			
	if data.has("fleet_doctrine"):
		GameState.set_fleet_doctrine(data["fleet_doctrine"])
		
	if data.has("attached_drones"):
		GameState.attached_drones = int(data["attached_drones"])
		GameState.drone_attached.emit(GameState.attached_drones)
		
	if data.has("quest_index"):
		GameState.quest_index = int(data["quest_index"])
		if GameState.quest_index < GameState.quest_list.size():
			GameState.quest_updated.emit(GameState.quest_index, GameState.quest_list[GameState.quest_index])
			
	if data.has("hostile_core_health"):
		GameState.hostile_core_health = float(data["hostile_core_health"])
		GameState.liberation_progress = float(data.get("liberation_progress", 0.0))
		GameState.enemy_damaged.emit(GameState.hostile_core_health, GameState.hostile_core_max_health)
		
	if data.has("megastructures"):
		GameState.megastructures = data["megastructures"]
		GameState.active_megastructure_project = data.get("active_megastructure_project", "")
		for m_id in GameState.megastructures.keys():
			var m = GameState.megastructures[m_id]
			GameState.megastructure_updated.emit(m_id, m["progress"], m["built"])
			
	if grid and data.has("placed_buildings"):
		grid.placed_buildings = data["placed_buildings"]
		
	AudioSynth.play_synth("click")
	GameState.add_log("QUICK LOAD COMPLETED [F9] -> GAME RESTORED")
	print("[SaveManager] Game loaded successfully")
	return true

func reset_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	GameState.add_log("SYSTEM RESET: SAVE DATA PURGED FOR NEW EXPEDITION")
	AudioSynth.play_synth("alert")
	GameState.story_phase = GameState.StoryPhase.DORMANT
	GameState.attached_drones = 0
	GameState.quest_index = 0
	GameState.fleet_count = 0
	GameState.hostile_core_health = GameState.hostile_core_max_health
	for t in GameState.unlocked_tools.keys():
		GameState.unlocked_tools[t] = false
	for r in GameState.resources.keys():
		GameState.resources[r] = 0
	for it in GameState.items.keys():
		GameState.items[it] = 0
	get_tree().reload_current_scene()
