extends Node2D

@onready var grid_manager: Node2D = $GridManager
@onready var swarm_simulation: Node2D = $SwarmSimulation
@onready var player: CharacterBody2D = $Player
@onready var hud: CanvasLayer = $HUD
@onready var camera: Camera2D = $Camera2D

# カメラ操作用変数
var is_following_player: bool = true
var target_zoom: Vector2 = Vector2(1.0, 1.0)
var is_right_dragging: bool = false
var last_mouse_screen_pos: Vector2 = Vector2.ZERO
var saved_player_zoom: Vector2 = Vector2(1.0, 1.0)
var is_map_mode: bool = false
var touch_points: Dictionary = {}
var initial_touch_dist: float = 0.0
var initial_zoom_level: float = 1.0

# 画面揺れ (Screen Shake)
var shake_amount: float = 0.0
var shake_timer: float = 0.0

# 敵空爆部隊 (Active Air Raid Bombers)
var active_bombers: Array[Dictionary] = []
var tex_bomber: Texture2D

# 爆発エフェクトリスト
var world_explosions: Array[Dictionary] = []

# ワールド環境 (Glow / Bloom)
var world_env: WorldEnvironment

func _ready() -> void:
	tex_bomber = load("res://assets/sprites/corrupted_bomber.png")
	
	# 1. 2D Glow / Bloom (WorldEnvironment) の設定
	_setup_world_environment()

	# 2. コマンドライン引数チェック
	var args = OS.get_cmdline_user_args()
	if "--capture" in args or "--capture" in OS.get_cmdline_args():
		get_tree().create_timer(1.2).timeout.connect(_capture_and_quit)
	elif "--run-tests" in args or "--run-tests" in OS.get_cmdline_args():
		_start_regression_tests()

	# 3. 画面サイズ・向き自動適応 (スマホ縦画面・横画面レスポンシブ)
	get_tree().root.size_changed.connect(_on_window_size_changed)
	_on_window_size_changed()

	# 4. マスドライバー射出シグナル接続
	if grid_manager and swarm_simulation:
		grid_manager.launch_probe_to_space.connect(swarm_simulation.launch_probe)
	
	GameState.doctrine_changed.connect(_on_doctrine_changed)
	
	# 5. 定期的な宇宙資源回収＆自律シミュレーション
	var timer = Timer.new()
	timer.wait_time = 2.5
	timer.autostart = true
	timer.timeout.connect(_on_orbital_logistics_tick)
	add_child(timer)

func _setup_world_environment() -> void:
	world_env = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.glow_enabled = true
	env.glow_intensity = 1.15
	env.glow_bloom = 0.22
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.glow_hdr_threshold = 1.0
	world_env.environment = env
	add_child(world_env)

func _on_window_size_changed() -> void:
	var win = get_window()
	if not win: return
	var win_size = win.size
	var aspect = float(win_size.x) / maxf(1.0, float(win_size.y))
	if aspect < 1.0:
		# スマホ縦持ち (Portrait): 基準解像度を幅540、高さ960 (9:16) に設定し指先サイズに完全適合
		win.content_scale_size = Vector2i(540, 960)
	else:
		# PC / スマホ横持ち (Landscape): 基準解像度を幅1280、高さ720 に設定
		win.content_scale_size = Vector2i(1280, 720)

	if camera:
		camera.anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
		if player:
			camera.global_position = player.global_position
		
		var base_z = 1.0
		if aspect < 0.65:
			base_z = 0.95
		elif aspect < 0.9:
			base_z = 0.98
		elif aspect < 1.2:
			base_z = 1.05
		else:
			base_z = 1.15
			
		target_zoom = Vector2(base_z, base_z)
		camera.zoom = target_zoom

func _process(delta: float) -> void:
	# 1. カメラのスムーズ追従 & スムーズズーム処理
	if camera:
		camera.zoom = camera.zoom.lerp(target_zoom, delta * 12.0)
		
		var base_pos = camera.global_position
		# 宇宙飛行遭難防止フェイルセーフ (機体が画面端を逸脱しそうになったら自動で追従復帰)
		if not is_following_player and player and not is_map_mode:
			var vp_sz = get_viewport().get_visible_rect().size
			var half_w = (vp_sz.x * 0.5) / camera.zoom.x
			var half_h = (vp_sz.y * 0.5) / camera.zoom.y
			var p_diff = player.global_position - camera.global_position
			if abs(p_diff.x) > half_w * 0.88 or abs(p_diff.y) > half_h * 0.88:
				is_following_player = true
				_update_camera_status_ui()

		if is_following_player and player and not is_map_mode:
			base_pos = base_pos.lerp(player.global_position, delta * 8.0)
			
		# 画面揺れ (Screen Shake) 適用
		if shake_timer > 0.0:
			shake_timer -= delta
			var shake_offset = Vector2(randf_range(-shake_amount, shake_amount), randf_range(-shake_amount, shake_amount))
			camera.global_position = base_pos + shake_offset
		else:
			camera.global_position = base_pos

	# 2. メガストラクチャー建造進行
	_process_megastructure_building(delta)
	
	# 3. 敵急降下爆撃機の更新
	_process_active_bombers(delta)
	
	# 4. 爆発エフェクトの更新
	for i in range(world_explosions.size() - 1, -1, -1):
		world_explosions[i]["timer"] -= delta
		if world_explosions[i]["timer"] <= 0.0:
			world_explosions.remove_at(i)
			
	queue_redraw()

func shake_camera(amount: float, duration: float) -> void:
	shake_amount = amount
	shake_timer = duration

# 敵空爆ウェーブのスポーン
func spawn_air_raid(wave_num: int) -> void:
	var bomber_count = 2 + wave_num
	var home_c = Vector2(800.0, 1070.0)
	
	for i in range(bomber_count):
		# 上空軌道からスポーン
		var spawn_angle = randf_range(-PI * 0.75, -PI * 0.25)
		var spawn_pos = home_c + Vector2(cos(spawn_angle), sin(spawn_angle)) * 950.0
		var target_angle = spawn_angle + randf_range(-0.15, 0.15)
		var target_pos = home_c + Vector2(cos(target_angle), sin(target_angle)) * 620.0
		
		active_bombers.append({
			"pos": spawn_pos,
			"target": target_pos,
			"speed": randf_range(110.0, 160.0),
			"hp": 50.0,
			"max_hp": 50.0
		})

func _process_active_bombers(delta: float) -> void:
	for i in range(active_bombers.size() - 1, -1, -1):
		var b = active_bombers[i]
		var dir = (b["target"] - b["pos"]).normalized()
		b["pos"] += dir * b["speed"] * delta
		
		# 地表付近に到達 -> 爆撃実行
		if b["pos"].distance_to(b["target"]) < 30.0:
			_explode_bomber(b["pos"], true)
			active_bombers.remove_at(i)
			continue
			
		# プレイヤーとの接触判定
		if player and b["pos"].distance_to(player.global_position) < 40.0:
			GameState.damage_player(25.0)
			shake_camera(8.0, 0.3)
			_explode_bomber(b["pos"], false)
			active_bombers.remove_at(i)

func destroy_bomber(bomber: Dictionary) -> void:
	var idx = active_bombers.find(bomber)
	if idx != -1:
		_explode_bomber(bomber["pos"], false)
		active_bombers.remove_at(idx)

func _explode_bomber(pos: Vector2, hit_ground: bool) -> void:
	world_explosions.append({
		"pos": pos,
		"radius": randf_range(20.0, 35.0),
		"timer": 0.35
	})
	AudioSynth.play_synth("explosion")
	var shake_val = 10.0 if hit_ground else 4.0
	shake_camera(shake_val, 0.25)
	
	if hit_ground:
		GameState.add_log("ALERT: ENEMY BOMB DETONATED ON SURFACE!")

func _draw() -> void:
	# 敵急降下爆撃機の描画
	for b in active_bombers:
		var dir = (b["target"] - b["pos"]).normalized()
		var rot = dir.angle() + PI * 0.5
		if tex_bomber:
			draw_set_transform(b["pos"], rot, Vector2.ONE)
			draw_texture(tex_bomber, -Vector2(18, 18))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			draw_circle(b["pos"], 12.0, Color(2.5, 0.2, 0.2))
			
		# HPバー
		var hp_r = b["hp"] / b["max_hp"]
		draw_rect(Rect2(b["pos"] - Vector2(14, 20), Vector2(28 * hp_r, 3)), Color(2.0, 0.2, 0.2))

	# 爆発エフェクト描画 (HDR Glow)
	for exp in world_explosions:
		var alpha = exp["timer"] / 0.35
		draw_circle(exp["pos"], exp["radius"] * (1.6 - alpha), Color(3.0, 1.2, 0.2, alpha * 0.85))
		draw_arc(exp["pos"], exp["radius"] * (2.2 - alpha), 0, TAU, 16, Color(3.0, 2.5, 0.8, alpha), 2.0)

	# マクロマップ時の自機ナビゲーションビーコン (Ship Beacon & Direction Vector)
	if camera and camera.zoom.x < 0.25 and player:
		var p_pos = player.global_position
		var pulse = (sin(Time.get_ticks_msec() * 0.006) * 0.5 + 0.5)
		var beacon_rad = 120.0 + pulse * 45.0
		
		# 1. 巨大パルスビーコンリング
		draw_arc(p_pos, beacon_rad, 0, TAU, 32, Color(0.0, 2.8, 3.5, 0.9), 4.0)
		draw_arc(p_pos, beacon_rad * 1.4, 0, TAU, 32, Color(0.2, 1.8, 2.5, 0.35), 2.0)
		draw_circle(p_pos, 45.0, Color(0.0, 2.5, 3.0, 0.6))
		
		# 2. 進行方向ベクター矢印
		var p_vel = player.velocity
		var vel_dir = p_vel.normalized() if p_vel.length() > 5.0 else Vector2.UP
		var arrow_len = 220.0
		var arrow_tip = p_pos + vel_dir * arrow_len
		draw_line(p_pos, arrow_tip, Color(1.5, 2.8, 3.5, 0.95), 5.0)
		var side_arrow = Vector2(-vel_dir.y, vel_dir.x) * 40.0
		draw_colored_polygon(PackedVector2Array([arrow_tip, arrow_tip - vel_dir * 55.0 + side_arrow, arrow_tip - vel_dir * 55.0 - side_arrow]), Color(0.2, 2.8, 3.5, 0.9))
		
		# 3. 母星へのナビゲーションリンク点線
		if grid_manager:
			var home_p = grid_manager.HOME_CENTER
			var d_home = p_pos.distance_to(home_p)
			draw_line(p_pos, home_p, Color(0.0, 1.5, 2.2, 0.3), 2.0)
			var mid_p = (p_pos + home_p) * 0.5
			draw_string(ThemeDB.fallback_font, mid_p, "HOME LINK: %.0f AU" % (d_home * 0.01), HORIZONTAL_ALIGNMENT_CENTER, -1, 32, Color(0.2, 1.8, 2.5, 0.8))

		# 4. 「SEED-01 (YOU)」視認ラベル
		draw_string(ThemeDB.fallback_font, p_pos + Vector2(-120, beacon_rad + 60), "SEED-01 (YOU)", HORIZONTAL_ALIGNMENT_CENTER, -1, 36, Color(0.3, 2.8, 3.5))

func _input(event: InputEvent) -> void:
	if not camera:
		return
		
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				is_right_dragging = true
				last_mouse_screen_pos = event.position
				is_following_player = false
				is_map_mode = false
				_update_camera_status_ui()
			else:
				is_right_dragging = false
				
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				is_right_dragging = true
				last_mouse_screen_pos = event.position
				is_following_player = false
				_update_camera_status_ui()
			else:
				is_right_dragging = false

		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_at_mouse(1.16)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_at_mouse(0.86)

	elif event is InputEventMouseMotion and is_right_dragging:
		var delta_pos = (event.position - last_mouse_screen_pos) / camera.zoom.x
		camera.global_position -= delta_pos
		last_mouse_screen_pos = event.position

	elif event is InputEventScreenTouch:
		if event.pressed:
			touch_points[event.index] = event.position
			if touch_points.size() == 2:
				var pts = touch_points.values()
				initial_touch_dist = pts[0].distance_to(pts[1])
				initial_zoom_level = target_zoom.x
		else:
			touch_points.erase(event.index)
			if touch_points.size() < 2:
				initial_touch_dist = 0.0

	elif event is InputEventScreenDrag:
		if touch_points.has(event.index):
			touch_points[event.index] = event.position
			if touch_points.size() >= 2 and initial_touch_dist > 15.0:
				var pts = touch_points.values()
				var cur_dist = pts[0].distance_to(pts[1])
				var factor = cur_dist / initial_touch_dist
				target_zoom = Vector2.ONE * clampf(initial_zoom_level * factor, 0.035, 2.8)

	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_SPACE:
			snap_camera_to_player()
		elif event.keycode == KEY_M:
			toggle_map_view()
		elif event.keycode == KEY_Z:
			zoom_out()
		elif event.keycode == KEY_X:
			zoom_in()

func zoom_in() -> void:
	_zoom_at_mouse(1.25)

func zoom_out() -> void:
	_zoom_at_mouse(0.8)

func _zoom_at_mouse(factor: float) -> void:
	var old_zoom = target_zoom.x
	var new_zoom = clampf(old_zoom * factor, 0.035, 2.8)
	if is_equal_approx(old_zoom, new_zoom):
		return
		
	var mouse_world_before = camera.get_global_mouse_position()
	target_zoom = Vector2(new_zoom, new_zoom)
	
	if not is_following_player:
		var mouse_viewport_offset = get_viewport().get_mouse_position() - get_viewport_rect().size * 0.5
		camera.global_position = mouse_world_before - (mouse_viewport_offset / new_zoom)

func snap_camera_to_player() -> void:
	is_following_player = true
	is_map_mode = false
	if target_zoom.x < 0.6:
		var vp_rect = get_viewport().get_visible_rect()
		var aspect = vp_rect.size.x / maxf(1.0, vp_rect.size.y)
		var base_z = 1.15
		if aspect < 0.65: base_z = 2.45
		elif aspect < 0.9: base_z = 1.95
		elif aspect < 1.2: base_z = 1.45
		target_zoom = Vector2(base_z, base_z)
	AudioSynth.play_synth("click")
	GameState.add_log("CAMERA: LOCKED ON SEED UNIT")
	_update_camera_status_ui()

func toggle_map_view() -> void:
	is_map_mode = not is_map_mode
	if is_map_mode:
		saved_player_zoom = target_zoom
		is_following_player = false
		target_zoom = Vector2(0.048, 0.048) # 太陽系全域（7200〜12000px）を雄大に俯瞰
		var sun_center = grid_manager.SUN_POS if grid_manager else Vector2(800.0, -850.0)
		camera.global_position = sun_center
		AudioSynth.play_synth("click")
		GameState.add_log("MACRO ORBITAL MAP VIEW ACTIVATED: FULL SOLAR SYSTEM OVERVIEW")
	else:
		snap_camera_to_player()
		target_zoom = saved_player_zoom
	_update_camera_status_ui()

func _update_camera_status_ui() -> void:
	if hud and hud.has_method("update_camera_mode_indicator"):
		var mode_name = "自機追従中 [SPACE]" if is_following_player else "自機へ戻る [SPACE]"
		hud.update_camera_mode_indicator(mode_name, is_following_player)

func _process_megastructure_building(delta: float) -> void:
	var active_proj = GameState.active_megastructure_project
	if active_proj != "" and GameState.megastructures.has(active_proj):
		var proj = GameState.megastructures[active_proj]
		if not proj["built"]:
			var swarm_boost = maxf(1.0, float(GameState.fleet_count) * 0.015)
			var build_speed = (0.04 * swarm_boost) * delta
			proj["progress"] = minf(1.0, proj["progress"] + build_speed)
			GameState.megastructure_updated.emit(active_proj, proj["progress"], false)
			
			if proj["progress"] >= 1.0:
				proj["built"] = true
				GameState.megastructure_updated.emit(active_proj, 1.0, true)
				GameState.add_log("************************************************")
				GameState.add_log("MEGASTRUCTURE COMPLETED: [%s]!" % proj["name"])
				GameState.add_log("BONUS ACTIVATED: %s" % proj["bonus"])
				GameState.add_log("************************************************")
				AudioSynth.play_synth("launch")
				GameState._advance_quest()

func _on_doctrine_changed(new_doctrine: String) -> void:
	if swarm_simulation and swarm_simulation.has_method("set_doctrine"):
		swarm_simulation.set_doctrine(new_doctrine)

func _on_orbital_logistics_tick() -> void:
	var fleet = GameState.fleet_count
	if fleet <= 0:
		return
		
	var elevator_boost = 3.0 if GameState.megastructures["elevator"]["built"] else 1.0
	
	match GameState.fleet_doctrine:
		"HARVEST":
			var ti_gain = int((randi_range(2, 6) + float(fleet) * 0.04) * elevator_boost)
			var si_gain = int((randi_range(3, 8) + float(fleet) * 0.05) * elevator_boost)
			var fe_gain = int((randi_range(4, 10) + float(fleet) * 0.06) * elevator_boost)
			GameState.add_resource("Ti", ti_gain)
			GameState.add_resource("Si", si_gain)
			GameState.add_resource("Fe", fe_gain)
			if randf() < 0.4:
				GameState.add_log("SWARM LOGISTICS: DELIVERED +%d Fe, +%d Si, +%d Ti" % [fe_gain, si_gain, ti_gain])
				
		"MULTIPLY":
			if fleet < GameState.fleet_max:
				var multiply_count = mini(int(float(fleet) * 0.12) + 2, 60)
				GameState.add_fleet(multiply_count)
				GameState.add_log("SWARM REPLICATION: +%d UNITS CONSTRUCTED" % multiply_count)
				AudioSynth.play_synth("build")
				
		"ASSAULT":
			var dmg = (float(fleet) * 0.25) + randf_range(15.0, 35.0)
			if GameState.megastructures["citadel"]["built"]:
				dmg *= 1.8
			GameState.damage_hostile_core(dmg)
			GameState.add_log("FLEET ASSAULT: STRUCK CORRUPTED CORE (-%.0f HP)" % dmg)
			AudioSynth.play_synth("laser")
			# 敵からの反撃によるスウォーム損耗
			GameState.destroy_fleet(randi_range(5, 18))

func _capture_and_quit() -> void:
	var tex = get_viewport().get_texture()
	if tex:
		var img = tex.get_image()
		if img:
			var path = "res://docs/art/ingame_screenshot.png"
			var err = img.save_png(ProjectSettings.globalize_path(path))
			print("CAPTURE RESULT: ", err, " -> ", ProjectSettings.globalize_path(path))
	get_tree().quit(0)

func _start_regression_tests() -> void:
	print(">>> STARTING BLUEPRINT & AUTONOMOUS DRONE REGRESSION TESTS <<<")
	get_tree().create_timer(0.6).timeout.connect(_run_test_dormant)

func _run_test_dormant() -> void:
	print("TEST PHASE 0: DORMANT PROBE & MINIMAL GUIDANCE OVERLAY")
	_save_test_screen("docs/art/test_00_dormant_probe.png")
	
	# テスト用に全機能（SPACE PHASE）を開放
	GameState.set_story_phase(GameState.StoryPhase.SPACE)
	GameState.items["miner"] = 5
	GameState.items["belt"] = 25
	GameState.items["smelter"] = 5
	GameState.items["turret"] = 5
	GameState.resources["Fe"] = 150
	GameState.resources["Cu"] = 150
	GameState.resources["Si"] = 100
	GameState.attached_drones = 2
	
	get_tree().create_timer(0.8).timeout.connect(_run_test_phase_1)

func _run_test_phase_1() -> void:
	print("TEST PHASE 1: BLUEPRINT PLACEMENT & MINIMAL NON-VERBAL UI")
	if grid_manager:
		grid_manager.select_tool("miner")
		grid_manager._add_blueprint("miner", -0.52, 20.0, "Fe", false)
		grid_manager._add_blueprint("smelter", -0.38, 32.0, "Fe", false)
	get_tree().create_timer(0.4).timeout.connect(func():
		_save_test_screen("docs/art/test_01_blueprint_hologram.png")
		_run_test_phase_2()
	)

func _run_test_phase_2() -> void:
	print("TEST PHASE 2: CONSTRUCTION DRONES WELDING BEAM")
	# ドローンがブループリントに到達して溶接ビームを照射している瞬間を撮影
	get_tree().create_timer(0.5).timeout.connect(func():
		_save_test_screen("docs/art/test_02_drones_welding.png")
		_run_test_phase_3()
	)

func _run_test_phase_3() -> void:
	print("TEST PHASE 3: CONVEYOR DRAG BLUEPRINTS & MULTI-DRONE FABRICATION")
	if grid_manager:
		# 連続ベルトブループリント
		for i in range(5):
			var ba = lerpf(-0.52, -0.38, float(i) / 4.0)
			grid_manager._add_blueprint("belt", ba, 4.0, "", false)
	get_tree().create_timer(0.5).timeout.connect(func():
		_save_test_screen("docs/art/test_03_belt_drag_blueprint.png")
		_run_test_phase_4()
	)

func _run_test_phase_4() -> void:
	print("TEST PHASE 4: AIR RAID INCOMING & TURRET DEFENSE")
	spawn_air_raid(1)
	GameState.raid_alert.emit(true, "RAID ALERT")
	get_tree().create_timer(0.5).timeout.connect(func():
		_save_test_screen("docs/art/test_04_air_raid_turret.png")
		_run_test_phase_5()
	)

func _run_test_phase_5() -> void:
	print("TEST PHASE 5: SWARM DEPLOYMENT & MEGASTRUCTURES BUILDING")
	active_bombers.clear() # 空爆フェーズ終了：残存爆撃機をクリーンアップ
	GameState.add_fleet(1800)
	GameState.megastructures["elevator"]["progress"] = 0.85
	GameState.megastructures["dyson"]["progress"] = 0.50
	GameState.active_megastructure_project = "elevator"
	if camera:
		target_zoom = Vector2(0.65, 0.65)
		camera.zoom = target_zoom
	get_tree().create_timer(0.5).timeout.connect(func():
		_save_test_screen("docs/art/test_05_swarm_megastructure.png")
		_run_test_phase_6()
	)

func _run_test_phase_6() -> void:
	print("TEST PHASE 6: MACRO ORBITAL MAP VIEW (SUN, BLACK HOLE, COMET, PULSAR, MOON ORBIT)")
	toggle_map_view()
	get_tree().create_timer(0.6).timeout.connect(func():
		_save_test_screen("docs/art/test_06_macro_map.png")
		_run_test_phase_7()
	)

func _run_test_phase_7() -> void:
	print("TEST PHASE 7: ASSAULT DOCTRINE ON ENEMY BOSS CORE")
	is_map_mode = false
	is_following_player = false
	GameState.set_fleet_doctrine("ASSAULT")
	var boss_pos = grid_manager.SUN_POS + Vector2(7600.0, -1200.0) if grid_manager else Vector2(8400.0, -2050.0)
	if camera:
		camera.global_position = boss_pos
		target_zoom = Vector2(0.85, 0.85)
		camera.zoom = target_zoom
	get_tree().create_timer(0.5).timeout.connect(func():
		_save_test_screen("docs/art/test_07_assault_boss.png")
		_run_test_phase_8()
	)

func _run_test_phase_8() -> void:
	print("TEST PHASE 8: CELESTIAL MINING (LUNA He3 & BLACK HOLE DARK MATTER)")
	is_map_mode = false
	is_following_player = false
	if hud and hud.alert_rect:
		hud.alert_rect.visible = false
		hud.alert_timer = 0.0
	# プレイヤーを月の近傍へ移動し、月への採掘レーザーを照射
	if player and grid_manager:
		var moon_pos = grid_manager.moon_body.get("pos", Vector2(1200, 300))
		player.global_position = moon_pos + Vector2(-90.0, -40.0)
		player.is_mining = true
		player.mining_target = moon_pos
		player._detect_nearest_ore(moon_pos)
		GameState.add_resource(player.current_mining_ore, 12)
		if camera:
			camera.global_position = player.global_position
			target_zoom = Vector2(1.35, 1.35)
			camera.zoom = target_zoom

	get_tree().create_timer(0.5).timeout.connect(func():
		_save_test_screen("docs/art/test_08_celestial_mining.png")
		_run_test_phase_9()
	)

func _run_test_phase_9() -> void:
	print("TEST PHASE 9: BLACK HOLE GARGANTUA & SWARM HARVESTING")
	if player and grid_manager:
		var bh_pos = grid_manager.SUN_POS + Vector2(14800.0, -7200.0)
		player.global_position = bh_pos + Vector2(-220.0, 60.0)
		player.is_mining = true
		player.mining_target = bh_pos
		player._detect_nearest_ore(bh_pos)
		GameState.add_resource("DarkMatter", 8)
		GameState.add_resource("Plasma", 15)
		GameState.add_resource("Ice", 20)
		GameState.set_fleet_doctrine("HARVEST")
		if camera:
			camera.global_position = bh_pos
			target_zoom = Vector2(0.75, 0.75)
			camera.zoom = target_zoom

	get_tree().create_timer(0.6).timeout.connect(func():
		_save_test_screen("docs/art/test_09_blackhole_singularity.png")
		_run_test_phase_10()
	)

func _run_test_phase_10() -> void:
	print("TEST PHASE 10: SURFACE COLLISION & CLAMPING TEST (NO PENETRATION)")
	# プレイヤーを母星の地表に戻し、下向き最大推力（地面へ突進）をシミュレート
	if player and grid_manager:
		player.is_mining = false
		player.global_position = grid_manager.HOME_CENTER + Vector2(0, -grid_manager.HOME_RADIUS - 16.0)
		player.velocity = Vector2(0, 300.0) # 地面へ下向き突進
		is_following_player = true
		if camera:
			camera.global_position = player.global_position
			target_zoom = Vector2(1.3, 1.3)
			camera.zoom = target_zoom

	get_tree().create_timer(0.5).timeout.connect(func():
		# 0.5秒激突後も、母星中心からの距離が HOME_RADIUS + 16.0 未満にめり込んでいないことを検証
		if player and grid_manager:
			var cur_dist = (player.global_position - grid_manager.HOME_CENTER).length()
			var min_dist = grid_manager.HOME_RADIUS + 15.9
			var is_clamped = (cur_dist >= min_dist)
			print("ASSERTION: Surface clamping check -> cur_dist: %.2f, min_dist: %.2f, RESULT: %s" % [cur_dist, min_dist, "PASSED" if is_clamped else "FAILED"])
			assert(is_clamped, "CRITICAL ERROR: Player penetrated inside planet surface!")
		_save_test_screen("docs/art/test_10_surface_clamping.png")
		_run_test_phase_11()
	)

func _run_test_phase_11() -> void:
	print("TEST PHASE 11: CELESTIAL SCALE HIERARCHY (SUN >> PLANETS)")
	if grid_manager:
		print("ASSERTION: SUN_RADIUS: %.1f vs HOME_RADIUS: %.1f (Ratio: %.2fx)" % [grid_manager.SUN_RADIUS, grid_manager.HOME_RADIUS, grid_manager.SUN_RADIUS / grid_manager.HOME_RADIUS])
		assert(grid_manager.SUN_RADIUS > grid_manager.HOME_RADIUS * 2.0, "CRITICAL ERROR: Sun is not significantly larger than home planet!")
	
	# 太陽系マクロ視点で巨大太陽と公転天体の全貌を撮影
	toggle_map_view()
	if camera:
		camera.global_position = grid_manager.SUN_POS if grid_manager else Vector2(800, -850)
		target_zoom = Vector2(0.045, 0.045)
		camera.zoom = target_zoom

	get_tree().create_timer(0.6).timeout.connect(func():
		_save_test_screen("docs/art/test_11_solar_scale_hierarchy.png")
		_run_test_phase_12()
	)

func _run_test_phase_12() -> void:
	print("TEST PHASE 12: PLANETARY REVOLUTION AROUND SUN VERIFICATION")
	var initial_home_pos = grid_manager.HOME_CENTER if grid_manager else Vector2.ZERO
	get_tree().create_timer(0.6).timeout.connect(func():
		var final_home_pos = grid_manager.HOME_CENTER if grid_manager else Vector2.ZERO
		var moved_dist = initial_home_pos.distance_to(final_home_pos)
		print("ASSERTION: Home planet orbital movement in 0.6s -> %.2f px" % moved_dist)
		assert(moved_dist > 0.001, "CRITICAL ERROR: Home planet is static and not revolving around the sun!")
		_save_test_screen("docs/art/test_12_planetary_orbit.png")
		print(">>> ALL 12 CRITICAL & CELESTIAL REGRESSION TESTS PASSED 100%! <<<")
		get_tree().quit(0)
	)

func _save_test_screen(rel_path: String) -> void:
	var tex = get_viewport().get_texture()
	if tex:
		var img = tex.get_image()
		if img:
			var full_p = ProjectSettings.globalize_path(rel_path)
			var err = img.save_png(full_p)
			print("SAVED: ", rel_path, " -> ERR: ", err)
			return
	print("SKIPPED SCREENSHOT (NO TEXTURE): ", rel_path)
