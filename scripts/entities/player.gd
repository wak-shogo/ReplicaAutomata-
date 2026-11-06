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

# スマホ・タッチ操作盤連携
var touch_thrust_vec: Vector2 = Vector2.ZERO
var touch_mining_active: bool = false
var touch_braking_active: bool = false

# ストーリー進行＆アニメーション・造形エフェクト
var moved_dist_accum: float = 0.0
var sensor_pulse_timer: float = 0.0
var sensor_pulse_radius: float = 0.0
var drone_fabrication_timer: float = 0.0
var replicate_text_timer: float = 0.0
var wake_pulse_timer: float = 0.0

var drone_rot_angle: float = 0.0
var anim_time: float = 0.0
var is_reentry: bool = false
var reentry_intensity: float = 0.0
var is_warp_jumping: bool = false
var grid_manager: Node2D = null
var current_orbit_info: Dictionary = {}

# スラスター・イオン排気パーティクル
var thruster_particles: Array[Dictionary] = []

# 自機横の累積資源ポップアップ (Floating Resource Popup)
var floating_res_count: int = 0
var floating_res_type: String = ""
var floating_res_timer: float = 0.0
var floating_res_scale: float = 1.0

var player_sheet: Texture2D
var drone_sheet: Texture2D

func _ready() -> void:
	grid_manager = get_parent().get_node_or_null("GridManager")
	# 母星の地表（北極付近）から安全・確実にスタート
	if grid_manager and grid_manager.has_method("surface_pos_at"):
		position = grid_manager.surface_pos_at(0.0, 16.0)
	else:
		position = Vector2(800.0, 634.0)
	velocity = Vector2(0.0, 0.0)
	player_sheet = load("res://assets/sprites/player_core_sheet.png")
	drone_sheet = load("res://assets/sprites/fabricator_drone_sheet.png")
	GameState.drone_attached.connect(_on_drone_attached)

func _on_drone_attached(_count: int) -> void:
	drone_fabrication_timer = 1.4
	replicate_text_timer = 2.4
	AudioSynth.play_synth("victory")
	var mn = get_parent()
	if mn and mn.has_method("shake_camera"):
		mn.shake_camera(2.5, 0.25)
	GameState.add_log("SELF-REPLICATION MILESTONE: SUB-UNIT %02d FABRICATED! HARVEST & BUILD POWER MULTIPLIED." % _count)

func wake_up_probe() -> void:
	if GameState.story_phase == GameState.StoryPhase.DORMANT:
		GameState.set_story_phase(GameState.StoryPhase.MOVE)
		wake_pulse_timer = 1.2
		sensor_pulse_radius = 5.0
		AudioSynth.play_synth("launch")
		var mn = get_parent()
		if mn and mn.has_method("shake_camera"):
			mn.shake_camera(2.5, 0.3)
		GameState.add_log("AUTOMA CORE REBOOTED: UNCHARTED PLANET DETECTED. COMMENCING AUTONOMOUS SELF-REPLICATION.")

func _physics_process(delta: float) -> void:
	anim_time += delta
	
	if wake_pulse_timer > 0.0:
		wake_pulse_timer -= delta
	if sensor_pulse_timer > 0.0:
		sensor_pulse_timer -= delta
		sensor_pulse_radius += delta * 360.0
	if drone_fabrication_timer > 0.0:
		drone_fabrication_timer -= delta
	if replicate_text_timer > 0.0:
		replicate_text_timer -= delta
	if floating_res_timer > 0.0:
		floating_res_timer -= delta
		floating_res_scale = lerpf(floating_res_scale, 1.0, delta * 14.0)
		if floating_res_timer <= 0.0:
			floating_res_count = 0

	# 休眠フェーズ判定（操作・推力はオフ）
	if GameState.story_phase == GameState.StoryPhase.DORMANT:
		velocity = Vector2.ZERO
		is_mining = false
		thrusting_dir = Vector2.ZERO
		# 休眠中も母星の公転に追従
		if grid_manager and grid_manager.get("home_delta_pos"):
			global_position += grid_manager.home_delta_pos
		queue_redraw()
		return

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

	# スマホ・バーチャルジョイスティック入力の合成
	if touch_thrust_vec.length_squared() > 0.01:
		input_vec = touch_thrust_vec

	var is_precision_mode: bool = is_mining or (grid_manager and grid_manager.selected_tool != "none")
	var target_cruise_speed: float = 100.0 if is_precision_mode else (160.0 + float(GameState.attached_drones) * 12.0)

	if grid_manager and grid_manager.has_method("compute_gravity_and_orbit"):
		grid_manager.ensure_sectors_around(global_position)
		current_orbit_info = grid_manager.compute_gravity_and_orbit(global_position, velocity)
		var g_acc: Vector2 = current_orbit_info["acc"]
		var alt: float = current_orbit_info["altitude"]
		
		# 大気圏・低空探査領域判定（高度 350px 未満）
		var in_atmosphere: bool = (alt < 350.0)
		
		if not in_atmosphere:
			# 深宇宙空間（高度 350px 以上）：完全な等速直線運動（無抵抗慣性）＆万有引力軌道運動 + スラスター推力 + 手動ブレーキ
			var is_brake_key = Input.is_key_pressed(KEY_SHIFT) or Input.is_key_pressed(KEY_C) or Input.is_joy_button_pressed(0, JOY_BUTTON_B) or touch_braking_active
			is_inertial_braking = is_brake_key
			thrusting_dir = input_vec.normalized()
			
			if is_inertial_braking:
				# 手動操作による緊急アクティブ逆噴射ブレーキ (Shift / C / Joypad B / スマホブレーキ)
				velocity = velocity.move_toward(Vector2.ZERO, 480.0 * delta)
				velocity += g_acc * delta
			elif input_vec.length_squared() > 0.01:
				var cur_thrust = thrust_accel + float(GameState.attached_drones) * 35.0
				velocity += (g_acc + input_vec.normalized() * cur_thrust) * delta
			else:
				# スラスター無入力時：宇宙本来の等速直線運動を維持
				velocity += g_acc * delta
		else:
			# 大気圏・地表低空領域：強力オートスタビライザー（指を離せばピタッと静止して通り過ぎない）
			is_inertial_braking = false
			thrusting_dir = input_vec.normalized()
			
			if input_vec.length_squared() > 0.01:
				velocity = velocity.lerp(input_vec.normalized() * target_cruise_speed, delta * 10.0)
			else:
				var stop_friction: float = 18.0 if is_precision_mode else 12.0
				velocity = velocity.lerp(Vector2.ZERO, delta * stop_friction)
				if velocity.length_squared() < 6.0:
					velocity = Vector2.ZERO
	else:
		velocity = input_vec.normalized() * 160.0
		
	move_and_slide()

	# ========================================================
	# 全天体共通：地表めり込み完全防止 ＆ 接地力学 (Surface Clamping)
	# ========================================================
	if grid_manager and not current_orbit_info.is_empty():
		var prim = current_orbit_info["primary"]
		var prim_pos: Vector2 = prim.get("pos", grid_manager.HOME_CENTER)
		var prim_rad: float = prim.get("radius", 420.0)
		var prim_kind: String = prim.get("kind", "")
		
		# 機体の物理半径 (16px)
		var r_ship: float = 16.0
		var min_radius: float = prim_rad + r_ship
		var to_ship: Vector2 = global_position - prim_pos
		var cur_r: float = to_ship.length()
		var normal: Vector2 = to_ship / cur_r if cur_r > 0.001 else Vector2.UP
		
		# 地表より内側にめり込んでいる場合
		if cur_r < min_radius:
			# 1. 物理位置を地表面に完全ハードクランプ (位置押し出し)
			global_position = prim_pos + normal * min_radius
			
			# 2. 地面に向かう法線速度成分をゼロ化 (地面に衝突して停止)
			var v_in = velocity.dot(normal)
			if v_in < -40.0:
				AudioSynth.play_synth("click")
				var mn = get_parent()
				if mn and mn.has_method("shake_camera"):
					mn.shake_camera(clampf(abs(v_in) * 0.02, 1.0, 5.0), 0.15)
			if v_in < 0.0:
				velocity -= normal * v_in
			
			# 3. 接地中の入力制御: 水平移動と上空への離陸
			var tangent = Vector2(-normal.y, normal.x)
			var t_input = input_vec.dot(tangent)
			var up_input = maxf(0.0, input_vec.dot(normal))
			if input_vec.length_squared() > 0.01:
				var target_v = (tangent * t_input * target_cruise_speed) + (normal * up_input * 260.0)
				velocity = velocity.lerp(target_v, delta * 14.0)
			else:
				velocity = velocity.move_toward(Vector2.ZERO, 900.0 * delta)

		# 3.5 母星大気圏再突入力学 (Atmospheric Re-entry Aerodynamic Drag & Heat Cone)
		is_reentry = false
		reentry_intensity = 0.0
		if prim_kind == "home" and cur_r > min_radius + 4.0 and cur_r < prim_rad + 150.0:
			var alt_ratio = 1.0 - clampf((cur_r - min_radius) / 150.0, 0.0, 1.0)
			var spd = velocity.length()
			var v_down = -velocity.dot(normal)
			if spd > 220.0 or v_down > 120.0:
				is_reentry = true
				reentry_intensity = clampf((spd - 200.0) / 250.0, 0.2, 1.0) * alt_ratio
				var drag_force = -velocity.normalized() * (spd * spd * 0.0008 * alt_ratio)
				velocity += drag_force * delta

		# 4. 全天体共通：公転座標系自動追従 (Celestial Co-moving Reference Frame)
		var p_delta = current_orbit_info.get("primary_delta_pos", Vector2.ZERO)
		if p_delta.length_squared() > 0.0001 and cur_r < prim_rad * 2.8:
			global_position += p_delta

		# 5. 恒星プラズマ過熱 ＆ スイングバイ熱放射 (Solar Heat Flux & Radiation Hazard)
		var sun_p = grid_manager.SUN_POS
		var sun_r = grid_manager.SUN_RADIUS
		var d_sun = global_position - sun_p
		var dist_sun = d_sun.length()
		
		if dist_sun < sun_r * 1.4:
			# コロナ過熱圏突入：シールド蒸発 ＆ 熱ダメージ
			var heat_ratio = clampf((sun_r * 1.4 - dist_sun) / (sun_r * 0.4), 0.0, 1.0)
			GameState.damage_player(35.0 * heat_ratio * delta)
			
			# 太陽表面突入時：固体激突ではなく強烈なプラズマ熱衝撃波で外側へ吹き飛ばし
			if dist_sun < sun_r:
				var push_n = d_sun.normalized() if dist_sun > 0.1 else Vector2.UP
				global_position = sun_p + push_n * (sun_r + 4.0)
				velocity = push_n * 650.0
				AudioSynth.play_synth("alert")
				GameState.add_log("SOLAR CORONA DEFLECTION: EXTREME THERMAL REPULSION!")

		# 6. ブラックホール事象の地平面 ＆ 潮汐破壊・時空ワープ (Singularity Tidal Disruption)
		if prim_kind == "blackhole":
			if cur_r < prim_rad * 1.2:
				# 事象の地平面突入：超重力潮汐力によるシールド浸食
				GameState.damage_player(55.0 * delta)
				# 降着円盤スイングバイ加速
				var spin_tangent = Vector2(-normal.y, normal.x)
				velocity += spin_tangent * (480.0 * delta)
				
				# 特異点到達時：緊急時空ワームホール排出
				if cur_r < 28.0:
					var eject_dir = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
					global_position = prim_pos + eject_dir * (prim_rad * 2.2)
					velocity = eject_dir * 780.0
					AudioSynth.play_synth("wormhole_warp")
					GameState.add_log("EVENT HORIZON WARP: QUANTUM EJECTION FROM SINGULARITY!")

		# 7. パルサー極ジェット直撃 ＆ 相対論的放射圧加速 (Relativistic Jet Radiation Propulsion)
		if prim_kind == "pulsar" and cur_r < 980.0:
			var p_rot = grid_manager.anim_time * 6.5
			var b_vec = Vector2(cos(p_rot), sin(p_rot))
			# 自機がビーム直線（双極）上と交差しているかを外積で判定
			if abs(normal.cross(b_vec)) < 0.14:
				velocity += normal * (750.0 * delta)
				GameState.damage_player(18.0 * delta)
				AudioSynth.play_synth("pulsar_pulse")
				var mn = get_parent()
				if mn and mn.has_method("shake_camera"):
					mn.shake_camera(2.5, 0.08)

		# 8. 星間超大型レールガン・ワープゲート突入 ＆ 恒星間跳躍エンディング
		if GameState.megastructures.get("warpgate", {}).get("built", false):
			var wg_pos = grid_manager.SUN_POS + Vector2(9800.0, 3200.0)
			if global_position.distance_to(wg_pos) < 120.0 and not is_warp_jumping:
				is_warp_jumping = true
				AudioSynth.play_synth("victory")
				velocity = Vector2(1.0, 0.35).normalized() * 2500.0
				GameState.add_log("★ HYPERDRIVE ENGAGED: INTERSTELLAR EXPEDITION INITIATED ★")
				var hud = get_parent().get_node_or_null("HUD")
				if hud and hud.has_method("_trigger_milestone_banner"):
					hud._trigger_milestone_banner("★ VICTORY: STELLAR ACCELERATOR LAUNCH ★")

		# リアルタイム天体音響・スラスターアンビエント合成
		var sun_proximity = clampf((sun_r * 2.5 - dist_sun) / (sun_r * 1.8), 0.0, 1.0)
		var bh_proximity = 0.0
		if prim_kind == "blackhole":
			bh_proximity = clampf((prim_rad * 3.0 - cur_r) / (prim_rad * 2.2), 0.0, 1.0)
		var thrust_power = clampf(input_vec.length(), 0.0, 1.0)
		AudioSynth.update_celestial_ambience(sun_proximity, bh_proximity, thrust_power)

	# MOVEフェーズでの移動距離検知 ＆ 地質センサー波発信
	if GameState.story_phase == GameState.StoryPhase.MOVE:
		moved_dist_accum += velocity.length() * delta
		if moved_dist_accum >= 60.0:
			sensor_pulse_timer = 1.4
			sensor_pulse_radius = 12.0
			GameState.set_story_phase(GameState.StoryPhase.MINE)
			AudioSynth.play_synth("alert")
	
	# マウス ＆ ゲームパッド ＆ スマホタッチ採掘操作（建築ツール非選択時のみ）
	# ※ スマホやWebブラウザでは画面タップでのビーム誤爆を完全防止！
	var can_mine_phase = (GameState.story_phase >= GameState.StoryPhase.MINE)
	var is_building = (grid_manager and grid_manager.selected_tool != "none")
	var is_gamepad_mining = (Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) > 0.35) or (Input.is_joy_button_pressed(0, JOY_BUTTON_A) and not is_building)
	var is_touch_mining = touch_mining_active and not is_building

	var is_touch_dev = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile") or OS.has_feature("web")
	var is_mouse_mining = false
	if not is_touch_dev and not is_building:
		# PC環境でのみマウスクリックまたはスペースキー長押しで採掘可能
		is_mouse_mining = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_key_pressed(KEY_SPACE)

	if can_mine_phase and (is_touch_mining or is_gamepad_mining or is_mouse_mining) and not is_building:
		if is_touch_mining or is_gamepad_mining:
			if is_touch_mining:
				mining_target = _get_auto_aim_target()
			else:
				var joy_rx = Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
				var joy_ry = Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
				if Vector2(joy_rx, joy_ry).length() > 0.25:
					var raw_gp = global_position + Vector2(joy_rx, joy_ry).normalized() * 180.0
					mining_target = _snap_target_to_celestial_or_vein(raw_gp)
				else:
					mining_target = _get_auto_aim_target()
		else:
			var raw_target = get_global_mouse_position()
			mining_target = _snap_target_to_celestial_or_vein(raw_target)
				
		is_mining = true
		mining_laser_timer += delta
		
		# マウス・照準位置がどの鉱脈に近いかを判定
		_detect_nearest_ore(mining_target)
		
		if mining_laser_timer >= 0.16:
			mining_laser_timer = 0.0
			AudioSynth.play_synth("mine")
			var amount = 1 + GameState.attached_drones
			if current_mining_source != "" and current_mining_source != "Crust":
				# 宇宙天体有限埋蔵量からの抽出
				GameState.mine_celestial_resource(current_mining_source, current_mining_ore, amount)
			else:
				# 母星地表鉱脈
				GameState.add_resource(current_mining_ore, amount)
			
			# 自機横の累積ポップアップ更新
			if floating_res_type != current_mining_ore and floating_res_timer > 0.0:
				floating_res_count = amount
			else:
				floating_res_count += amount
			floating_res_type = current_mining_ore
			floating_res_timer = 1.35
			floating_res_scale = 1.35
			
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

	# スラスター噴煙・プラズマパーティクルの生成
	if thrusting_dir != Vector2.ZERO:
		var back_dir = -thrusting_dir
		for i in range(2):
			var spread = randf_range(-0.45, 0.45)
			var p_vel = back_dir.rotated(spread) * randf_range(90.0, 220.0)
			var spawn_offset = back_dir * 18.0 + Vector2(-back_dir.y, back_dir.x) * randf_range(-6.0, 6.0)
			thruster_particles.append({
				"pos": spawn_offset,
				"vel": p_vel,
				"life": 0.4,
				"max_life": 0.4,
				"color": Color(0.1, 1.8, 2.8, 0.9) if randf() > 0.3 else Color(2.0, 2.0, 2.5, 1.0),
				"size": randf_range(2.5, 5.0)
			})
	elif is_inertial_braking:
		# RCS逆噴射パフ
		var rcs_dirs = [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]
		for rd in rcs_dirs:
			thruster_particles.append({
				"pos": rd * 16.0,
				"vel": rd * randf_range(60.0, 140.0),
				"life": 0.25,
				"max_life": 0.25,
				"color": Color(0.2, 2.2, 2.8, 0.8),
				"size": randf_range(1.5, 3.5)
			})
	
	# 地表ホバリング砂塵（Surface Dust Kickup）
	if current_orbit_info.get("altitude", 99.0) <= 12.0 and velocity.length() > 20.0:
		var ground_dir = (global_position - grid_manager.HOME_CENTER).normalized() if grid_manager else Vector2.DOWN
		var dust_spread = Vector2(-ground_dir.y, ground_dir.x) * randf_range(-1.0, 1.0)
		thruster_particles.append({
			"pos": ground_dir * 14.0 + dust_spread * 12.0,
			"vel": dust_spread * randf_range(25.0, 70.0) - ground_dir * randf_range(5.0, 18.0),
			"life": 0.35,
			"max_life": 0.35,
			"color": Color(0.35, 0.65, 0.85, 0.45),
			"size": randf_range(2.0, 4.0)
		})
	
	# パーティクルの更新と寿命判定
	var alive_particles: Array[Dictionary] = []
	for p in thruster_particles:
		p["life"] -= delta
		if p["life"] > 0.0:
			p["pos"] += p["vel"] * delta
			p["vel"] *= 0.94
			alive_particles.append(p)
	thruster_particles = alive_particles

	drone_rot_angle += delta * 1.6
	queue_redraw()

func _snap_target_to_celestial_or_vein(raw_pos: Vector2) -> Vector2:
	if not grid_manager:
		return raw_pos
	# 宇宙天体へのスナップ判定 (天体中心ではなく、自機に近い天体表面へスナップ！)
	if grid_manager.get("active_planets"):
		for p in grid_manager.active_planets:
			if p.get("kind", "") == "home": continue
			var ppos: Vector2 = p.get("pos", Vector2.ZERO)
			var prad: float = p.get("radius", 50.0)
			var reach = prad + maxf(160.0, prad * 0.4)
			if raw_pos.distance_to(ppos) <= reach:
				var to_ship = (global_position - ppos).normalized() if global_position != ppos else Vector2.UP
				return ppos + to_ship * prad
	# 小惑星帯へのスナップ判定
	if grid_manager.get("asteroid_belt"):
		for ast in grid_manager.asteroid_belt:
			if raw_pos.distance_to(ast["pos"]) <= ast.get("radius", 20.0) + 70.0:
				return ast["pos"]
	return raw_pos

func _get_auto_aim_target() -> Vector2:
	if not grid_manager:
		return global_position + Vector2(0, 80)
		
	# 1. 宇宙空間にいる場合：最も近い宇宙天体表面へオートエイム
	var d_home = global_position.distance_to(grid_manager.HOME_CENTER)
	if d_home > grid_manager.HOME_RADIUS + 70.0:
		var best_cel_dist = 99999.0
		var best_cel_pos = global_position + Vector2(0, -100.0)
		if grid_manager.get("active_planets"):
			for p in grid_manager.active_planets:
				if p.get("kind", "") == "home": continue
				var ppos: Vector2 = p.get("pos", Vector2.ZERO)
				var prad: float = p.get("radius", 50.0)
				var d = global_position.distance_to(ppos) - prad
				if d < best_cel_dist:
					best_cel_dist = d
					var to_ship = (global_position - ppos).normalized() if global_position != ppos else Vector2.UP
					best_cel_pos = ppos + to_ship * prad
					
		# 小惑星帯の個別アステロイドもオートエイム対象に含める
		if grid_manager.get("asteroid_belt"):
			for ast in grid_manager.asteroid_belt:
				var apos: Vector2 = ast.get("pos", Vector2.ZERO)
				var arad: float = ast.get("radius", 18.0)
				var d_ast = global_position.distance_to(apos) - arad
				if d_ast < best_cel_dist:
					best_cel_dist = d_ast
					best_cel_pos = apos
					
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
	# 休眠探査機の再起動タップ検知
	if GameState.story_phase == GameState.StoryPhase.DORMANT:
		if (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed) or (event is InputEventKey and event.pressed):
			wake_up_probe()
			return

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
	# 0. 起動パルス ＆ 地質探査センサー波エフェクト (広がるリング波紋)
	if wake_pulse_timer > 0.0:
		var w_r = (1.2 - wake_pulse_timer) * 120.0
		var w_a = wake_pulse_timer / 1.2
		draw_arc(Vector2.ZERO, w_r, 0, TAU, 32, Color(0.0, 2.5, 3.0, w_a * 0.8), 2.5)

	if sensor_pulse_timer > 0.0:
		var p_alpha = sensor_pulse_timer / 1.4
		draw_arc(Vector2.ZERO, sensor_pulse_radius, 0, TAU, 48, Color(0.2, 2.2, 0.8, p_alpha * 0.85), 3.0)
		draw_arc(Vector2.ZERO, maxf(1.0, sensor_pulse_radius - 12.0), 0, TAU, 36, Color(0.0, 1.8, 2.8, p_alpha * 0.5), 1.5)

	# 1. 休眠状態の描画 (DORMANT)
	if GameState.story_phase == GameState.StoryPhase.DORMANT:
		var stand_pulse = (sin(anim_time * 4.0) * 0.5 + 0.5)
		# 待機リング波紋
		draw_arc(Vector2.ZERO, 32.0 + stand_pulse * 6.0, 0, TAU, 32, Color(0.0, 1.5, 2.0, 0.3 + stand_pulse * 0.3), 1.5)
		# 消灯した本体コア
		if player_sheet:
			draw_texture_rect_region(player_sheet, Rect2(Vector2(-24, -24), Vector2(48, 48)), Rect2(0.0, 0.0, 48.0, 48.0), Color(0.35, 0.4, 0.45, 0.85))
		# 赤い微弱待機ランプ
		draw_circle(Vector2.ZERO, 4.0, Color(1.8, 0.2, 0.2, 0.6 + stand_pulse * 0.4))
		return

	# 2. 重力軌道予測ライン
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
	
	# 3. アタッチされた小型プリントドローン群の美麗描画 (四角形枠の排除・サイバー子機)
	if drones > 0:
		var step = TAU / float(drones)
		var orbit_dist = base_radius + 22.0
		# 薄いホログラム公転軌道リング
		draw_arc(Vector2.ZERO, orbit_dist, 0, TAU, 40, Color(0.0, 1.8, 2.5, 0.3), 1.0)

		for i in range(drones):
			var a = drone_rot_angle + step * float(i)
			var d_pos = Vector2(cos(a), sin(a)) * orbit_dist
			
			# 自機とドローンを結ぶ光のエナジーテザー
			draw_line(Vector2.ZERO, d_pos, Color(0.0, 1.8, 2.8, 0.45), 1.2)
			
			# ドローン本体のサイバーウィング幾何学描画 (六角形コア ＋ デルタ翼)
			var wing_dir = Vector2(-sin(a), cos(a)) # 進行方向
			var tip = d_pos + wing_dir * 10.0
			var left_w = d_pos - wing_dir * 7.0 + Vector2(-wing_dir.y, wing_dir.x) * 8.0
			var right_w = d_pos - wing_dir * 7.0 - Vector2(-wing_dir.y, wing_dir.x) * 8.0
			var pts = PackedVector2Array([tip, left_w, d_pos - wing_dir * 4.0, right_w])
			
			draw_colored_polygon(pts, Color(0.04, 0.12, 0.2, 0.95))
			draw_polyline(pts, Color(0.0, 2.4, 3.0, 0.9), 1.5)
			# ドローン中心の発光コア
			draw_circle(d_pos, 3.5, Color(0.2, 2.5, 2.5, 1.0))
			draw_arc(d_pos, 6.0, 0, TAU, 16, Color(2.5, 2.5, 2.5, 0.8), 1.0)

			# スプライトシートがあれば加算合成
			if drone_sheet:
				var d_frame = (p_frame + i) % 4
				draw_texture_rect_region(drone_sheet, Rect2(d_pos - Vector2(10, 10), Vector2(20, 20)), Rect2(24.0 * d_frame, 0.0, 24.0, 24.0), Color(1.0, 1.2, 1.5, 0.7))

	# 4. ドローン造形シーケンス演出 (3Dプリント溶接サークル ＆ スパーク)
	if drone_fabrication_timer > 0.0:
		var f_progress = 1.0 - (drone_fabrication_timer / 1.4)
		var f_rad = base_radius + 22.0
		# 回転する溶接ホログラムリング
		draw_arc(Vector2.ZERO, f_rad, 0, TAU * f_progress, 36, Color(0.0, 2.5, 3.0, 0.95), 2.5)
		draw_arc(Vector2.ZERO, f_rad + 6.0, anim_time * 6.0, anim_time * 6.0 + PI, 24, Color(2.5, 1.8, 0.3, 0.8), 2.0)
		
		# 溶接火花パーティクル
		for s in range(8):
			var sa = anim_time * 12.0 + float(s) * (TAU / 8.0)
			var sp_pos = Vector2(cos(sa), sin(sa)) * (f_rad + randf_range(-4.0, 4.0))
			draw_circle(sp_pos, randf_range(1.5, 3.0), Color(2.8, 2.2, 0.6, 0.9))

	# 4.5 前方探査サーチライト (Night Exploration Headlight Beam)
	if GameState.story_phase >= GameState.StoryPhase.MOVE:
		var forward_dir = Vector2(cos(ship_rotation), sin(ship_rotation))
		var light_len = 260.0
		var cone_half_a = deg_to_rad(32.0)
		var l_tip1 = forward_dir.rotated(cone_half_a) * light_len
		var l_tip2 = forward_dir.rotated(-cone_half_a) * light_len
		
		# 扇形ライトポリゴン (柔らかなシアン発光)
		var light_pts = PackedVector2Array([Vector2.ZERO, l_tip1, forward_dir * (light_len * 1.05), l_tip2])
		draw_colored_polygon(light_pts, Color(0.2, 0.8, 1.2, 0.08))
		# コア光芒
		var core_pts = PackedVector2Array([Vector2.ZERO, forward_dir.rotated(cone_half_a * 0.4) * (light_len * 0.7), forward_dir.rotated(-cone_half_a * 0.4) * (light_len * 0.7)])
		draw_colored_polygon(core_pts, Color(0.6, 1.8, 2.5, 0.12))
		# 自機周囲アンビエント照明
		draw_circle(Vector2.ZERO, 38.0, Color(0.1, 0.6, 1.0, 0.14))

	# 5. プレイヤー中央コア（Seed Unit: 48x48）
	# スラスター・プラズマ排気パーティクルの描画
	for p in thruster_particles:
		var a_ratio = p["life"] / p["max_life"]
		var p_col: Color = p["color"]
		p_col.a *= a_ratio
		var p_sz: float = p["size"] * a_ratio
		draw_circle(p["pos"], p_sz, p_col)

	# メインスラスター噴射炎 ＆ ショックダイヤモンド
	if thrusting_dir != Vector2.ZERO:
		var back_dir = -thrusting_dir
		var side_n = Vector2(-back_dir.y, back_dir.x)
		var flame_len = 24.0 + sin(anim_time * 38.0) * 6.0
		var flame_tip = back_dir * (18.0 + flame_len)
		
		# (1) 外層プラズマコーン（シアン発光）
		var p1 = back_dir * 18.0 + side_n * 6.0
		var p2 = back_dir * 18.0 - side_n * 6.0
		draw_colored_polygon(PackedVector2Array([p1, flame_tip, p2]), Color(0.1, 1.6, 2.8, 0.75))
		
		# (2) 内層白熱コア（極高熱ホワイトプラズマ）
		var c1 = back_dir * 18.0 + side_n * 2.5
		var c2 = back_dir * 18.0 - side_n * 2.5
		var core_tip = back_dir * (18.0 + flame_len * 0.65)
		draw_colored_polygon(PackedVector2Array([c1, core_tip, c2]), Color(2.5, 2.5, 3.0, 0.95))
		
		# (3) ショックダイヤモンド（超音速排気波）
		var sd_pos = back_dir * (18.0 + flame_len * 0.38)
		draw_circle(sd_pos, 2.8, Color(3.0, 3.0, 3.5, 1.0))
		
		# (4) 左右補助ノズル微小炎
		draw_line(back_dir * 16.0 + side_n * 8.0, back_dir * (16.0 + flame_len * 0.4) + side_n * 8.0, Color(0.2, 1.8, 3.0, 0.8), 2.0)
		draw_line(back_dir * 16.0 - side_n * 8.0, back_dir * (16.0 + flame_len * 0.4) - side_n * 8.0, Color(0.2, 1.8, 3.0, 0.8), 2.0)

	# 大気圏再突入プラズマ熱衝撃波 (Atmospheric Re-entry Bow Shock)
	if is_reentry and velocity.length_squared() > 100.0:
		var fwd = velocity.normalized()
		var bow_r = 26.0
		var bow_a = fwd.angle()
		draw_arc(fwd * 6.0, bow_r, bow_a - PI * 0.45, bow_a + PI * 0.45, 20, Color(1.0, 0.45, 0.1, 0.9 * reentry_intensity), 3.0)
		draw_arc(fwd * 6.0, bow_r - 3.0, bow_a - PI * 0.35, bow_a + PI * 0.35, 16, Color(1.0, 0.9, 0.5, 0.95 * reentry_intensity), 1.5)
		for sp in range(5):
			var sp_ang = bow_a + (PI if sp % 2 == 0 else -PI) * 0.4 + randf_range(-0.15, 0.15)
			var sp_start = fwd * 6.0 + Vector2(cos(sp_ang), sin(sp_ang)) * bow_r
			var sp_len = randf_range(16.0, 38.0) * reentry_intensity
			draw_line(sp_start, sp_start - fwd * sp_len, Color(1.0, 0.5, 0.1, 0.7 * reentry_intensity), 1.5)

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

	# 6. 採掘レーザービーム描画 (宇宙天体固有カラー ＆ HDR Glow)
	if is_mining:
		var local_target = to_local(mining_target)
		var beam_col = current_mining_color
		
		draw_line(Vector2.ZERO, local_target, beam_col, 3.5)
		draw_line(Vector2.ZERO, local_target, Color(2.5, 2.5, 2.5, 1.0), 1.2)
		draw_circle(local_target, 7.0, beam_col)
		
		# ドローンからのマルチ支援ビーム (採掘効率アップが視覚的に実感できる)
		if drones > 0:
			var step = TAU / float(drones)
			var orbit_dist = base_radius + 22.0
			for i in range(mini(drones, 4)):
				var a = drone_rot_angle + step * float(i)
				var d_pos = Vector2(cos(a), sin(a)) * orbit_dist
				draw_line(d_pos, local_target, beam_col * Color(1.2, 1.2, 1.5, 0.75), 1.8)
				draw_circle(d_pos, 4.0, Color(2.5, 2.5, 2.5, 0.9))

	# 7. シールドリング＆自機耐久値バー描画 (HDR Glow)
	if GameState.player_shield > 0.0:
		var s_alpha = GameState.player_shield / GameState.player_max_shield
		draw_arc(Vector2.ZERO, 30.0, 0, TAU, 32, Color(0.0, 2.0, 3.0, s_alpha * 0.7), 1.5)
		
	# 自機HP/シールドバー（自機頭上に小さく表示）
	var hp_r = GameState.player_hp / GameState.player_max_hp
	var sh_r = GameState.player_shield / GameState.player_max_shield
	draw_rect(Rect2(-18, -34, 36, 3), Color(0.1, 0.1, 0.1, 0.8))
	draw_rect(Rect2(-18, -34, 36 * hp_r, 3), Color(0.2, 2.0, 0.5))
	draw_rect(Rect2(-18, -30, 36 * sh_r, 2), Color(0.0, 1.8, 2.8))

	# 7.5 飛行テレメトリ表示 (Altitude & Speed HUD)
	var alt = current_orbit_info.get("altitude", 0.0)
	if alt > 30.0 and GameState.story_phase >= GameState.StoryPhase.MOVE:
		var spd = velocity.length()
		var telem_txt = "ALT: %.0f | SPD: %.0f" % [alt, spd]
		draw_string(ThemeDB.fallback_font, Vector2(-45, 36), telem_txt, HORIZONTAL_ALIGNMENT_CENTER, 90, 8, Color(0.2, 0.8, 1.0, 0.75))

	# 8. 自己複製達成ポップアップ (Self-Replication Feedback)
	if replicate_text_timer > 0.0:
		var txt_alpha = clampf(replicate_text_timer / 1.0, 0.0, 1.0)
		var txt_y_off = -46.0 - (2.2 - replicate_text_timer) * 16.0
		draw_string(ThemeDB.fallback_font, Vector2(-95, txt_y_off), "+1 REPLICATED SUB-UNIT", HORIZONTAL_ALIGNMENT_CENTER, -1, 14, Color(1.5, 2.2, 0.4, txt_alpha))

	# 9. 地殻鉱脈探査コンパス (Subsurface Mineral Compass - 地表探索HUD)
	if current_orbit_info.get("altitude", 99.0) <= 30.0 and grid_manager and grid_manager.get("ore_veins"):
		draw_arc(Vector2.ZERO, 34.0, 0, TAU, 32, Color(0.1, 0.4, 0.6, 0.25), 1.0)
		for v in grid_manager.ore_veins:
			var va = -PI * 0.5 + v["angle_off"]
			var vpos = grid_manager.HOME_CENTER + Vector2(cos(va), sin(va)) * grid_manager.HOME_RADIUS
			var to_vein = vpos - global_position
			var d_vein = to_vein.length()
			var pip_dir = to_vein.normalized()
			var pip_pos = pip_dir * 34.0
			var v_col: Color = v["color"]
			draw_circle(pip_pos, 2.5, v_col)
			if d_vein < 320.0:
				draw_string(ThemeDB.fallback_font, pip_pos + pip_dir * 12.0 - Vector2(10, -4), "%s:%.0fm" % [v["name"], d_vein * 0.1], HORIZONTAL_ALIGNMENT_CENTER, -1, 9, v_col)

	# 10. 累積資源ポップアップ (Floating Accumulated Resource HUD)
	if floating_res_timer > 0.0 and floating_res_count > 0:
		var f_alpha = clampf(floating_res_timer / 0.35, 0.0, 1.0)
		var float_y = -14.0 - (1.35 - floating_res_timer) * 14.0
		var r_col = Color(0.3, 1.8, 2.5)
		match floating_res_type:
			"Fe": r_col = Color(0.3, 1.8, 2.5)
			"Cu": r_col = Color(2.5, 1.2, 0.3)
			"Ti": r_col = Color(0.3, 2.5, 1.2)
			"Si": r_col = Color(2.5, 2.2, 0.4)
			"He3": r_col = Color(0.4, 1.8, 2.8)
			"Plasma": r_col = Color(2.5, 0.8, 0.2)
			"Ice": r_col = Color(1.8, 2.5, 2.8)
			"DarkMatter": r_col = Color(2.0, 0.4, 2.5)
			"Neutronium": r_col = Color(2.5, 0.2, 0.8)
		r_col.a = f_alpha
		var f_text = "+%d %s" % [floating_res_count, floating_res_type]
		var f_size = int(round(13.0 * floating_res_scale))
		# 背景ミニバッジ（半透明黒角丸＋ネオン境界線）
		draw_rect(Rect2(24, float_y - 12, 64, 18), Color(0.04, 0.08, 0.14, 0.75 * f_alpha))
		draw_rect(Rect2(24, float_y - 12, 64, 18), r_col * Color(1, 1, 1, 0.65 * f_alpha), false, 1.2)
		draw_string(ThemeDB.fallback_font, Vector2(30, float_y + 1), f_text, HORIZONTAL_ALIGNMENT_LEFT, -1, f_size, r_col)
