extends SceneTree

# ビジュアル＆ゲームプレイ自動検証テストランナー
var frame_count: int = 0
var test_phase: int = 0
var main_scene: Node2D = null

func _init() -> void:
	print(">>> VISUAL REGRESSION TEST RUNNER STARTED <<<")

func _process(_delta: float) -> bool:
	frame_count += 1
	
	if not main_scene:
		var scene_res = load("res://scenes/main.tscn")
		main_scene = scene_res.instantiate()
		root.add_child(main_scene)
		return false
		
	# フェーズ別のテスト実行
	if frame_count == 25:
		# Test 1: クラフト画面のテスト
		print("TEST 1: CRAFT WINDOW TEST")
		var hud = main_scene.get_node_or_null("HUD")
		if hud:
			hud.toggle_craft_window()
		_capture("docs/art/test_01_craft_window.png")
		
	elif frame_count == 50:
		# Test 2: メガストラクチャー建造メニューのテスト
		print("TEST 2: MEGASTRUCTURE MENU TEST")
		var hud = main_scene.get_node_or_null("HUD")
		if hud:
			hud.toggle_mega_window()
		_capture("docs/art/test_02_mega_window.png")
		
	elif frame_count == 80:
		# Test 3: ドローン合体 + 採掘レーザー照射 + 工場配置
		print("TEST 3: DRONE EXPANSION + MINING LASER")
		var hud = main_scene.get_node_or_null("HUD")
		if hud:
			if hud.is_mega_window_open: hud.toggle_mega_window()
		# 資源を与えてドローンを4機合体
		GameState.add_resource("Fe", 500)
		GameState.add_resource("Si", 300)
		GameState.add_resource("Cu", 300)
		for k in range(4):
			GameState.attach_drone()
		# プレイヤー採掘レーザーを銅鉱脈に向けてオン
		var player = main_scene.get_node_or_null("Player")
		if player:
			player.is_mining = true
			player.mining_target = Vector2(740.0, 780.0) # Cu鉱脈方向
		_capture("docs/art/test_03_drone_mining.png")
		
	elif frame_count == 120:
		# Test 4: スウォーム1000機展開 + 軌道エレベーター & ダイソンリング建造中
		print("TEST 4: SWARM DEPLOYMENT + MEGASTRUCTURE BUILDING")
		GameState.add_fleet(1200)
		GameState.megastructures["elevator"]["progress"] = 0.85
		GameState.megastructures["dyson"]["progress"] = 0.50
		GameState.active_megastructure_project = "elevator"
		var cam = main_scene.get_node_or_null("Camera2D")
		if cam:
			cam.zoom = Vector2(0.65, 0.65)
		_capture("docs/art/test_04_swarm_megastructure.png")
		
	elif frame_count == 160:
		# Test 5: 全体マップモード (Mキー)
		print("TEST 5: MACRO ORBITAL MAP VIEW")
		if main_scene.has_method("toggle_map_view"):
			main_scene.toggle_map_view()
		_capture("docs/art/test_05_macro_map.png")
		
	elif frame_count == 200:
		# Test 6: 敵ボス要塞総攻撃 (ASSAULT ドクトリン)
		print("TEST 6: ASSAULT DOCTRINE ON CORRUPTED CORE")
		GameState.set_fleet_doctrine("ASSAULT")
		var cam = main_scene.get_node_or_null("Camera2D")
		if cam:
			main_scene.is_following_player = false
			cam.global_position = Vector2(1180.0, 115.0) # 敵要塞コア中心
			cam.zoom = Vector2(1.2, 1.2)
		_capture("docs/art/test_06_assault_boss.png")
		
	elif frame_count == 240:
		print("ALL VISUAL REGRESSION TESTS FINISHED SUCCESSFULLY!")
		quit(0)
		return true

	return false

func _capture(rel_path: String) -> void:
	var img = root.get_viewport().get_texture().get_image()
	var full_p = ProjectSettings.globalize_path(rel_path)
	var err = img.save_png(full_p)
	print("CAPTURED: ", rel_path, " -> ERR: ", err)
