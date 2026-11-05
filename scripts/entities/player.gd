extends CharacterBody2D

# プレイヤー機体 (Seed Unit) ＆ 万有引力軌道力学 ＆ 鉱脈自動判定採掘 ＆ ドローン合体
@export var thrust_accel: float = 340.0
var mining_target: Vector2 = Vector2.ZERO
var is_mining: bool = false
var mining_laser_timer: float = 0.0
var current_mining_ore: String = "Fe"
var current_mining_color: Color = Color(0.0, 1.0, 0.9, 0.9)
var current_mining_source: String = ""
var is_inertial_braking: bool = false
var thrusting_dir: Vector2 = Vector2.ZERO
var ship_rotation: float = 0.0
var angular_velocity: float = 0.0
var angular_damping: float = 9.0

var drone_rot_angle: float = 0.0
var anim_time: float = 0.0
var grid_manager: Node2D = null
var current_orbit_info: Dictionary = {}

var player_sheet: Texture2D
var drone_sheet: Texture2D

func _ready() -> void:
	# 母星の地表付近からスタート
	position = Vector2(780.0, 520.0)
	velocity = Vector2(0.0, 0.0)
	player_sheet = load("res://assets/sprites/player_core_sheet.png")
	drone_sheet = load("res://assets/sprites/fabricator_drone_sheet.png")
	grid_manager = get_parent().get_node_or_null("GridManager")

func _physics_process(delta: float) -> void:
	anim_time += delta
	var input_vec = Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		input_vec.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		input_vec.y += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		input_vec.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		input_vec.x += 1.0

	# ゲームパッド (Joypad 0) 左スティック & D-Pad
	var joy_lx = Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
	var joy_ly = Input.get_joy_axis(0, JOY_AXIS_LEFT_Y)
	if abs(joy_lx) > 0.18: input_vec.x = joy_lx
	if abs(joy_ly) > 0.18: input_vec.y = joy_ly
	if Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_UP): input_vec.y -= 1.0
	if Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_DOWN): input_vec.y += 1.0
	if Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_LEFT): input_vec.x -= 1.0
	if Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_RIGHT): input_vec.x += 1.0

	if grid_manager and grid_manager.has_method("compute_gravity_and_orbit"):
		grid_manager.ensure_sectors_around(global_position)
		current_orbit_info = grid_manager.compute_gravity_and_orbit(global_position, velocity)
		var g_acc: Vector2 = current_orbit_info["acc"]
		var alt: float = current_orbit_info["altitude"]
		
		if alt > 8.0:
			# 宇宙空間：完全な等速直線運動（無抵抗慣性）＆万有引力軌道運動 + スラスター推力 + 手動ブレーキ
			var is_brake_key = Input.is_key_pressed(KEY_SHIFT) or Input.is_key_pressed(KEY_C) or Input.is_joy_button_pressed(0, JOY_BUTTON_B)
			is_inertial_braking = is_brake_key
			thrusting_dir = input_vec.normalized()
			
			if is_inertial_braking:
				# 手動操作による緊急アクティブ逆噴射ブレーキ (Shift / C / Joypad B)
				velocity = velocity.move_toward(Vector2.ZERO, 380.0 * delta)
				velocity += g_acc * delta
			elif input_vec.length_squared() > 0.01:
				velocity += (g_acc + input_vec.normalized() * thrust_accel) * delta
			else:
				# スラスター無入力時：自動減衰ダンパーなし。宇宙本来の完全な等速直線運動を維持
				velocity += g_acc * delta
		else:
			is_inertial_braking = false
			thrusting_dir = input_vec.normalized()
			# 地表・地下：地殻ホバリング制御で軽快に採掘移動
			if input_vec.length_squared() > 0.01:
				velocity = velocity.lerp(input_vec.normalized() * 240.0, delta * 8.0)
			else:
				velocity = velocity.lerp(g_acc * 0.15, delta * 6.0)
	else:
		velocity = input_vec.normalized() * 240.0
		
	move_and_slide()
	
	# マウス ＆ ゲームパッド採掘操作（建築ツール非選択時のみ）
	var is_building = (grid_manager and grid_manager.selected_tool != "none")
	var is_gamepad_mining = (Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) > 0.35) or (Input.is_joy_button_pressed(0, JOY_BUTTON_A) and not is_building)
	var is_mouse_mining = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not is_building

	if (is_mouse_mining or is_gamepad_mining) and not is_building:
		if is_mouse_mining:
			var raw_target = get_global_mouse_position()
			mining_target = _snap_target_to_celestial_or_vein(raw_target)
		else:
			# ゲームパッド：右スティックエイム、未入力なら最も近い鉱脈/天体へ自動照準！
			var joy_rx = Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
			var joy_ry = Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
			if Vector2(joy_rx, joy_ry).length() > 0.25:
				var raw_gp = global_position + Vector2(joy_rx, joy_ry).normalized() * 180.0
				mining_target = _snap_target_to_celestial_or_vein(raw_gp)
			else:
				mining_target = _get_auto_aim_target()
				
		is_mining = true
		mining_laser_timer += delta
		
		# マウス・照準位置がどの鉱脈に近いかを判定
		_detect_nearest_ore(mining_target)
		
		if mining_laser_timer >= 0.16:
			mining_laser_timer = 0.0
			AudioSynth.play_synth("mine")
			var amount = 1 + GameState.attached_drones
			GameState.add_resource(current_mining_ore, amount)
			
			# レーザーで敵爆撃機を迎撃判定
			var main_n = get_parent()
			if main_n and main_n.get("active_bombers"):
				for b in main_n.active_bombers:
					if mining_target.distance_to(b["pos"]) < 36.0:
						b["hp"] -= 30.0 * (1 + GameState.attached_drones)
						AudioSynth.play_synth("laser")
						if b["hp"] <= 0.0:
							main_n.destroy_bomber(b)
							GameState.add_log("MANUAL INTERCEPTION: BOMBER ANNIHILATED BY LASER")
						break
	else:
		is_mining = false
		mining_laser_timer = 0.0

	# 機体姿勢角（Rotation）のトルク制御 ＆ リアクションホイール角速度減衰 (Angular Damping)
	var has_rot_target = false
	var target_angle = ship_rotation
	
	if is_mining:
		# 採掘中：採掘ターゲットへ機首を向ける
		target_angle = (mining_target - global_position).angle()
		has_rot_target = true
	elif thrusting_dir != Vector2.ZERO:
		# スラスター噴射中：推進方向へ機首を向ける
		target_angle = thrusting_dir.angle()
		has_rot_target = true
	elif velocity.length_squared() > 100.0 and current_orbit_info.get("altitude", 0.0) <= 8.0:
		# 地表付近：進行方向へ緩やかに向く
		target_angle = velocity.angle()
		has_rot_target = true

	if has_rot_target:
		var angle_diff = wrapf(target_angle - ship_rotation, -PI, PI)
		angular_velocity += angle_diff * 35.0 * delta

	# リアクションホイールによる姿勢角速度減衰（回転の減衰）
	angular_velocity = lerpf(angular_velocity, 0.0, angular_damping * delta)
	ship_rotation += angular_velocity * delta

	drone_rot_angle += delta * 1.6
	queue_redraw()

func _snap_target_to_celestial_or_vein(raw_pos: Vector2) -> Vector2:
	if not grid_manager:
		return raw_pos
	# 宇宙天体へのスナップ判定
	if grid_manager.get("active_planets"):
		for p in grid_manager.active_planets:
			if p.get("kind", "") == "home": continue
			var ppos: Vector2 = p.get("pos", Vector2.ZERO)
			var prad: float = p.get("radius", 50.0)
			if raw_pos.distance_to(ppos) <= prad + 140.0:
				return ppos
	# 小惑星帯へのスナップ判定
	if grid_manager.get("asteroid_belt"):
		for ast in grid_manager.asteroid_belt:
			if raw_pos.distance_to(ast["pos"]) <= ast.get("radius", 20.0) + 70.0:
				return ast["pos"]
	return raw_pos

func _get_auto_aim_target() -> Vector2:
	if not grid_manager:
		return global_position + Vector2(0, 80)
		
	# 1. 宇宙空間にいる場合：最も近い宇宙天体へオートエイム
	var d_home = global_position.distance_to(grid_manager.HOME_CENTER)
	if d_home > grid_manager.HOME_RADIUS + 70.0:
		var best_cel_dist = 99999.0
		var best_cel_pos = global_position + Vector2(0, -100.0)
		if grid_manager.get("active_planets"):
			for p in grid_manager.active_planets:
				if p.get("kind", "") == "home": continue
				var ppos: Vector2 = p.get("pos", Vector2.ZERO)
				var d = global_position.distance_to(ppos)
				if d < best_cel_dist:
					best_cel_dist = d
					best_cel_pos = ppos
		return best_cel_pos

	# 2. 地表付近にいる場合：最も近い地下鉱脈へオートエイム
	var best_vein_dist = 99999.0
	var best_vein_pos = global_position + Vector2(0, 80.0)
	if grid_manager.get("ore_veins"):
		for v in grid_manager.ore_veins:
			var a = -PI * 0.5 + v["angle_off"]
			var vpos = grid_manager.HOME_CENTER + Vector2(cos(a), sin(a)) * v["depth_r"]
			var d = global_position.distance_to(vpos)
			if d < best_vein_dist:
				best_vein_dist = d
				best_vein_pos = vpos
	return best_vein_pos

func _detect_nearest_ore(target_pos: Vector2) -> void:
	if not grid_manager or not grid_manager.has_method("get_mining_info_at"):
		current_mining_ore = "Fe"
		current_mining_color = Color(0.0, 1.0, 0.9, 0.9)
		current_mining_source = "Crust"
		return

	var info = grid_manager.get_mining_info_at(target_pos)
	if not info.is_empty():
		current_mining_ore = info["type"]
		current_mining_color = info["color"]
		current_mining_source = info["name"]
	else:
		current_mining_ore = "Fe"
		current_mining_color = Color(0.0, 1.0, 0.9, 0.9)

func _cycle_tool(dir: int) -> void:
	if not grid_manager:
		return
	var tool_list = ["miner", "belt", "smelter", "assembler", "mass_driver", "depot", "turret", "solar", "geothermal", "demolish"]
	var cur_idx = tool_list.find(grid_manager.selected_tool)
	if cur_idx == -1:
		cur_idx = 0 if dir > 0 else tool_list.size() - 1
	else:
		cur_idx = (cur_idx + dir + tool_list.size()) % tool_list.size()
	grid_manager.select_tool(tool_list[cur_idx])

func _input(event: InputEvent) -> void:
	# ゲームパッド (Joypad 0) ボタン操作
	if event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_X:
				# Xボタン: 小型ドローン合体 (Bキー)
				if GameState.attach_drone():
					AudioSynth.play_synth("build")
			JOY_BUTTON_Y:
				# Yボタン: ビルドモード切替 (Tabキー)
				var main_hud = get_parent().get_node_or_null("HUD")
				if main_hud and main_hud.has_method("toggle_build_mode"):
					main_hud.toggle_build_mode()
			JOY_BUTTON_LEFT_SHOULDER:
				# LB: 前のツールスロットへ
				_cycle_tool(-1)
			JOY_BUTTON_RIGHT_SHOULDER:
				# RB: 次のツールスロットへ
				_cycle_tool(1)
			JOY_BUTTON_LEFT_STICK, JOY_BUTTON_RIGHT_STICK:
				# L3/R3: 自機追従カメラリセット (Spaceキー)
				var cam = get_parent().get_node_or_null("FreeCamera")
				if cam and cam.has_method("reset_to_player"):
					cam.reset_to_player()
			JOY_BUTTON_BACK:
				# Back/Select: 全体マップトグル (Mキー)
				var cam = get_parent().get_node_or_null("FreeCamera")
				if cam and cam.has_method("toggle_macro_map"):
					cam.toggle_macro_map()
			JOY_BUTTON_START:
				# Start/Menu: クイックセーブ (F5)
				SaveManager.save_game()
				GameState.add_log("SYSTEM: QUICK SAVE COMPLETED (JOYPAD)")
			JOY_BUTTON_DPAD_UP:
				GameState.swarm_doctrine = "assault"
				GameState.add_log("DOCTRINE: ASSAULT (ATTACK ENEMY CORE)")
				AudioSynth.play_synth("alert")
			JOY_BUTTON_DPAD_DOWN:
				GameState.swarm_doctrine = "harvest"
				GameState.add_log("DOCTRINE: HARVEST (COLLECT RESOURCES)")
				AudioSynth.play_synth("click")
			JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT:
				GameState.swarm_doctrine = "multiply"
				GameState.add_log("DOCTRINE: MULTIPLY (REPLICATE FLEET)")
				AudioSynth.play_synth("build")

	if event is InputEventKey and event.pressed:
		# Bキー: 小型プリントドローン合体（Chassis Expansion）
		if event.keycode == KEY_B:
			if GameState.attach_drone():
				AudioSynth.play_synth("build")
		# Oキー: 第一宇宙速度（衛星軌道投入）
		elif event.keycode == KEY_O and not current_orbit_info.is_empty():
			var prim = current_orbit_info["primary"]
			var radial = (global_position - prim["pos"]).normalized()
			if current_orbit_info["altitude"] < 40.0:
				global_position = prim["pos"] + radial * (prim["radius"] + 150.0)
				current_orbit_info = grid_manager.compute_gravity_and_orbit(global_position, velocity)
			var tang = Vector2(-radial.y, radial.x)
			velocity = tang * current_orbit_info["v_circular"]
			AudioSynth.play_synth("launch")
			GameState.add_log("ORBITAL INJECTION: SATELLITE VELOCITY %.0f px/s ACHIEVED" % velocity.length())
		# Eキー: 第二宇宙速度（脱出速度）
		elif event.keycode == KEY_E and not current_orbit_info.is_empty():
			var prim = current_orbit_info["primary"]
			var radial = (global_position - prim["pos"]).normalized()
			var tang = Vector2(-radial.y, radial.x)
			velocity = (tang * 0.75 + radial * 0.66).normalized() * (current_orbit_info["v_escape"] * 1.08)
			AudioSynth.play_synth("launch")
			GameState.add_log("ESCAPE VELOCITY REACHED: %.0f px/s -> INTERPLANETARY FLIGHT!" % velocity.length())

func _draw() -> void:
	# 1. 重力軌道予測ライン
	if grid_manager and velocity.length() > 15.0:
		var sim_p = global_position
		var sim_v = velocity
		var sim_dt = 0.08
		var prev_local = Vector2.ZERO
		var traj_col = Color(0.2, 1.0, 0.7, 0.55) if "SATELLITE" in current_orbit_info.get("orbit_state", "") else Color(0.0, 0.85, 1.0, 0.45)
		for step in range(28):
			var gi = grid_manager.compute_gravity_and_orbit(sim_p, sim_v)
			sim_v += gi["acc"] * sim_dt
			sim_p += sim_v * sim_dt
			var cur_local = to_local(sim_p)
			if step % 2 == 0:
				draw_line(prev_local, cur_local, traj_col, 1.5)
			prev_local = cur_local

	var drones = GameState.attached_drones
	var base_radius = 24.0
	var p_frame = int(anim_time * 8.0) % 4
	
	# 2. アタッチされた小型プリントドローン群の描画
	if drones > 0:
		var step = TAU / float(drones)
		var orbit_dist = base_radius + 20.0
		for i in range(drones):
			var a = drone_rot_angle + step * float(i)
			var d_pos = Vector2(cos(a), sin(a)) * orbit_dist
			draw_line(Vector2.ZERO, d_pos, Color(0.0, 0.9, 1.0, 0.7), 2.0)
			if drone_sheet:
				var d_frame = (p_frame + i) % 4
				draw_texture_rect_region(drone_sheet, Rect2(d_pos - Vector2(12, 12), Vector2(24, 24)), Rect2(24.0 * d_frame, 0.0, 24.0, 24.0))

	# 3. プレイヤー中央コア（Seed Unit: 48x48）
	# スラスター噴射 ＆ 逆噴射ブレーキ (RCS)
	if thrusting_dir != Vector2.ZERO:
		var flame_len = 16.0 + sin(anim_time * 30.0) * 4.0
		var flame_p = -thrusting_dir * (20.0 + flame_len)
		draw_line(-thrusting_dir * 18.0, flame_p, Color(0.2, 2.0, 3.0, 0.9), 4.0)
		draw_line(-thrusting_dir * 18.0, flame_p * 0.7, Color(2.5, 2.5, 2.5, 1.0), 2.0)
	if is_inertial_braking:
		var rcs_pulse = (sin(anim_time * 25.0) * 0.5 + 0.5)
		var rcs_len = 12.0 + rcs_pulse * 6.0
		var rcs_dirs = [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1), Vector2(0.707, 0.707), Vector2(-0.707, 0.707), Vector2(0.707, -0.707), Vector2(-0.707, -0.707)]
		for rd in rcs_dirs:
			draw_line(rd * 20.0, rd * (20.0 + rcs_len), Color(0.3, 2.5, 2.8, 0.85), 2.0)

	if player_sheet:
		draw_set_transform(Vector2.ZERO, ship_rotation, Vector2.ONE)
		draw_texture_rect_region(player_sheet, Rect2(Vector2(-24, -24), Vector2(48, 48)), Rect2(48.0 * p_frame, 0.0, 48.0, 48.0))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 4. 採掘レーザービーム描画 (宇宙天体固有カラー ＆ HDR Glow)
	if is_mining:
		var local_target = to_local(mining_target)
		var beam_col = current_mining_color
		
		draw_line(Vector2.ZERO, local_target, beam_col, 3.5)
		draw_line(Vector2.ZERO, local_target, Color(2.5, 2.5, 2.5, 1.0), 1.2)
		draw_circle(local_target, 7.0, beam_col)
		
		# ドローンからの支援ビーム
		if drones > 0:
			var step = TAU / float(drones)
			var orbit_dist = base_radius + 20.0
			for i in range(mini(drones, 4)):
				var a = drone_rot_angle + step * float(i)
				var d_pos = Vector2(cos(a), sin(a)) * orbit_dist
				draw_line(d_pos, local_target, beam_col * Color(1, 1, 1, 0.5), 1.5)

	# 5. シールドリング＆自機耐久値バー描画 (HDR Glow)
	if GameState.player_shield > 0.0:
		var s_alpha = GameState.player_shield / GameState.player_max_shield
		draw_arc(Vector2.ZERO, 30.0, 0, TAU, 32, Color(0.0, 2.0, 3.0, s_alpha * 0.7), 1.5)
		
	# 自機HP/シールドバー（自機頭上に小さく表示）
	var hp_r = GameState.player_hp / GameState.player_max_hp
	var sh_r = GameState.player_shield / GameState.player_max_shield
	draw_rect(Rect2(-18, -34, 36, 3), Color(0.1, 0.1, 0.1, 0.8))
	draw_rect(Rect2(-18, -34, 36 * hp_r, 3), Color(0.2, 2.0, 0.5))
	draw_rect(Rect2(-18, -30, 36 * sh_r, 2), Color(0.0, 1.8, 2.8))
