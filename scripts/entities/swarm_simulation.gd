extends Node2D

# 10,000体自己複製艦隊シミュレータ (GPU MultiMesh2D 高速シミュレーション)
# ドクトリン対応: HARVEST (資源回収), MULTIPLY (宇宙自己増殖), ASSAULT (敵要塞総攻撃)
const MAX_UNITS: int = 10000

var friendly_multimesh: MultiMeshInstance2D
var hostile_multimesh: MultiMeshInstance2D

# ユニットデータ（連続メモリ配列）
var friendly_positions: PackedVector2Array = []
var friendly_velocities: PackedVector2Array = []
var friendly_active_count: int = 0

var hostile_positions: PackedVector2Array = []
var hostile_velocities: PackedVector2Array = []
var hostile_active_count: int = 800

# 敵要塞コア＆巡洋艦 (太陽系外縁深宇宙セクター)
var boss_core_pos: Vector2 = Vector2(8400.0, -2050.0)
var tex_boss_core: Texture2D
var tex_boss_cruiser: Texture2D

# レーザー・戦闘・建造・自己複製エフェクト
var laser_lines: Array[Dictionary] = [] # [{from, to, color, timer}]
var explosions: Array[Dictionary] = [] # [{pos, radius, timer}]
var replication_rings: Array[Dictionary] = [] # [{pos, radius, max_r, color, timer, duration}]
var boss_shockwaves: Array[Dictionary] = [] # [{pos, radius, timer}]
var cargo_packets: Array[Dictionary] = [] # [{pos, target, speed, res, color, timer}]
var boss_defeated: bool = false
var multiply_timer: float = 0.0

var current_doctrine: String = "HARVEST"
var anim_time: float = 0.0

func _ready() -> void:
	tex_boss_core = load("res://assets/sprites/corrupted_core_hub.png")
	tex_boss_cruiser = load("res://assets/sprites/corrupted_cruiser.png")
	
	setup_multimeshes()
	init_units()
	GameState.fleet_changed.connect(_on_fleet_changed)
	GameState.doctrine_changed.connect(set_doctrine)

func setup_multimeshes() -> void:
	var friendly_tex = load("res://assets/sprites/fleet_fighter.png")
	var hostile_tex = load("res://assets/sprites/hostile_fighter.png")

	# 味方（黄色/金色スプライト）MultiMesh2D
	friendly_multimesh = MultiMeshInstance2D.new()
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.instance_count = MAX_UNITS
	
	var qmesh = QuadMesh.new()
	qmesh.size = Vector2(14, 14)
	mm.mesh = qmesh
	friendly_multimesh.multimesh = mm
	friendly_multimesh.texture = friendly_tex
	add_child(friendly_multimesh)

	# 敵（赤色スプライト）MultiMesh2D
	hostile_multimesh = MultiMeshInstance2D.new()
	var hmm = MultiMesh.new()
	hmm.transform_format = MultiMesh.TRANSFORM_2D
	hmm.use_colors = true
	hmm.instance_count = 3000
	
	var hqmesh = QuadMesh.new()
	hqmesh.size = Vector2(14, 14)
	hmm.mesh = hqmesh
	hostile_multimesh.multimesh = hmm
	hostile_multimesh.texture = hostile_tex
	add_child(hostile_multimesh)

func init_units() -> void:
	friendly_positions.resize(MAX_UNITS)
	friendly_velocities.resize(MAX_UNITS)
	friendly_active_count = GameState.fleet_count
	
	# 初期状態では画面外に配置
	for i in range(MAX_UNITS):
		friendly_positions[i] = Vector2(-9999, -9999)
		friendly_velocities[i] = Vector2.ZERO
		var t = Transform2D(0.0, Vector2(-9999, -9999))
		friendly_multimesh.multimesh.set_instance_transform_2d(i, t)
		friendly_multimesh.multimesh.set_instance_color(i, Color(1.0, 0.92, 0.35, 0.95))

	# 敵性レプリカ艦隊（CRYSTAL-IV周辺の要塞を守備）
	hostile_positions.resize(3000)
	hostile_velocities.resize(3000)
	for i in range(3000):
		var hr = randf_range(50.0, 220.0)
		var a = randf() * TAU
		var pos = boss_core_pos + Vector2(cos(a), sin(a)) * hr
		var tang = Vector2(sin(a), -cos(a))
		var vel = tang * randf_range(40.0, 85.0)
		hostile_positions[i] = pos
		hostile_velocities[i] = vel
		
		var transform = Transform2D(vel.angle() + PI * 0.5, pos)
		if i >= hostile_active_count:
			transform.origin = Vector2(-9999, -9999)
		hostile_multimesh.multimesh.set_instance_transform_2d(i, transform)
		hostile_multimesh.multimesh.set_instance_color(i, Color(1.0, 0.25, 0.25, 0.9))

func set_doctrine(new_doctrine: String) -> void:
	current_doctrine = new_doctrine

func _on_fleet_changed(current: int, _max_val: int) -> void:
	var old_count = friendly_active_count
	friendly_active_count = mini(MAX_UNITS, current)
	
	# 新たに追加された機体を軌道上へスポーン
	if friendly_active_count > old_count:
		var home_c = Vector2(800.0, 1070.0)
		var home_r = 620.0
		var home_g = 165.0
		for i in range(old_count, friendly_active_count):
			var alt = randf_range(95.0, 320.0)
			var orb_r = home_r + alt
			var a = randf_range(-PI * 0.88, -PI * 0.12)
			var pos = home_c + Vector2(cos(a), sin(a)) * orb_r
			var v_circ = sqrt(home_g * home_r * home_r / orb_r)
			var dir_sign = -1.0 if (i % 4 != 0) else 1.0
			var tang = Vector2(-sin(a), cos(a)) * dir_sign
			var vel = tang * (v_circ * randf_range(0.96, 1.06))
			
			friendly_positions[i] = pos
			friendly_velocities[i] = vel

# マスドライバーから射出された機体を受け入れ
func launch_probe(from_pos: Vector2, launch_velocity: Vector2) -> void:
	if friendly_active_count < MAX_UNITS:
		var idx = friendly_active_count
		friendly_positions[idx] = from_pos
		friendly_velocities[idx] = launch_velocity
		friendly_active_count += 1
		GameState.fleet_count = friendly_active_count
		GameState.fleet_changed.emit(friendly_active_count, MAX_UNITS)
		
		# 射出光線
		laser_lines.append({
			"from": from_pos,
			"to": from_pos + launch_velocity.normalized() * 120.0,
			"color": Color(0.3, 1.0, 1.0, 0.9),
			"timer": 0.25
		})

func _physics_process(delta: float) -> void:
	anim_time += delta
	update_friendly_swarm(delta)
	update_hostile_swarm(delta)
	update_combat_and_doctrines(delta)
	queue_redraw()

func update_friendly_swarm(delta: float) -> void:
	if friendly_active_count <= 0:
		return
		
	var home_c = Vector2(800.0, 1070.0)
	var home_gm = 165.0 * 620.0 * 620.0
	var mm = friendly_multimesh.multimesh
	
	# ドクトリンに応じたターゲット
	var target_dest = Vector2.ZERO
	match current_doctrine:
		"ASSAULT":
			target_dest = boss_core_pos # 敵要塞へ突入
		"MULTIPLY":
			target_dest = Vector2(680.0, 140.0) # AETHER-II 宇宙空間
		"HARVEST":
			target_dest = Vector2(800.0, 350.0) # 母星上空軌道
			
	# メガストラクチャー建造中の場合は一部が建造現場へ向かう
	var is_building_mega = (GameState.active_megastructure_project != "")
	var mega_pos = Vector2(800.0, 310.0) # デフォルトは軌道エレベーター位置
	if GameState.active_megastructure_project == "dyson":
		mega_pos = Vector2(520.0, 90.0)
	elif GameState.active_megastructure_project == "citadel":
		mega_pos = Vector2(1060.0, 240.0)
	elif GameState.active_megastructure_project == "warpgate":
		mega_pos = Vector2(1480.0, 80.0)

	for i in range(friendly_active_count):
		var pos = friendly_positions[i]
		var vel = friendly_velocities[i]
		
		# 1. 重力運動
		var d_home = pos - home_c
		var r2_home = maxf(40000.0, d_home.length_squared())
		var r_home = sqrt(r2_home)
		var acc = (-d_home / r_home) * (home_gm / r2_home)
		
		# 2. ドクトリン推進力
		if current_doctrine == "ASSAULT":
			var d_boss = boss_core_pos - pos
			acc += d_boss.normalized() * 95.0
		elif is_building_mega and (i % 3 == 0):
			var d_mega = mega_pos - pos
			acc += d_mega.normalized() * 85.0
			
		vel += acc * delta
		vel = vel.limit_length(280.0)
		pos += vel * delta
		
		# 軌道リセット
		if r_home < 630.0:
			var n = d_home / r_home
			pos = home_c + n * 645.0
			var tang = Vector2(-n.y, n.x)
			vel = tang * sqrt(home_gm / 645.0)
		elif r_home > 1600.0 or pos.y > 750.0 or pos.x < -300.0 or pos.x > 1900.0:
			var alt = randf_range(110.0, 330.0)
			var orb_r = 620.0 + alt
			var a = randf_range(-PI * 0.88, -PI * 0.12)
			pos = home_c + Vector2(cos(a), sin(a)) * orb_r
			vel = Vector2(-sin(a), cos(a)) * (-1.0 if (i % 4 != 0) else 1.0) * sqrt(home_gm / orb_r)
		
		friendly_positions[i] = pos
		friendly_velocities[i] = vel
		
		var t = Transform2D(vel.angle() + PI * 0.5, pos)
		mm.set_instance_transform_2d(i, t)

func update_hostile_swarm(delta: float) -> void:
	if GameState.hostile_core_health <= 0.0:
		# ボス撃破後は敵残存が散り散りに逃走
		for i in range(hostile_active_count):
			hostile_positions[i] += hostile_velocities[i] * delta * 2.0
		return
		
	var hmm = hostile_multimesh.multimesh
	for i in range(hostile_active_count):
		var pos = hostile_positions[i]
		var vel = hostile_velocities[i]
		
		# ボス拠点周辺を渦巻き旋回
		var d_boss = pos - boss_core_pos
		var dist = d_boss.length()
		var tang = Vector2(-d_boss.y, d_boss.x).normalized()
		var center_pull = -d_boss.normalized() * (dist - 140.0) * 0.8
		
		vel = (tang * 70.0 + center_pull)
		pos += vel * delta
		
		hostile_positions[i] = pos
		hostile_velocities[i] = vel
		
		var t = Transform2D(vel.angle() + PI * 0.5, pos)
		hmm.set_instance_transform_2d(i, t)

func update_combat_and_doctrines(delta: float) -> void:
	# レーザータイマー更新
	for i in range(laser_lines.size() - 1, -1, -1):
		laser_lines[i]["timer"] -= delta
		if laser_lines[i]["timer"] <= 0.0:
			laser_lines.remove_at(i)
			
	# 爆発タイマー更新
	for i in range(explosions.size() - 1, -1, -1):
		explosions[i]["timer"] -= delta
		if explosions[i]["timer"] <= 0.0:
			explosions.remove_at(i)

	# ナノ複製リング更新
	for i in range(replication_rings.size() - 1, -1, -1):
		replication_rings[i]["timer"] -= delta
		if replication_rings[i]["timer"] <= 0.0:
			replication_rings.remove_at(i)

	# ボス撃破衝撃波更新
	for i in range(boss_shockwaves.size() - 1, -1, -1):
		boss_shockwaves[i]["timer"] -= delta
		boss_shockwaves[i]["radius"] += delta * 600.0
		if boss_shockwaves[i]["timer"] <= 0.0:
			boss_shockwaves.remove_at(i)

	# 深宇宙光子カーゴパケット輸送更新 (天体採掘 -> 母星ロジスティクス)
	var grid_m_cargo = get_parent().get_node_or_null("GridManager")
	var home_target = grid_m_cargo.surface_pos_at(0.0, 420.0) if grid_m_cargo else Vector2(800.0, 1070.0)
	for i in range(cargo_packets.size() - 1, -1, -1):
		var cp = cargo_packets[i]
		var dir = (home_target - cp["pos"])
		var dist = dir.length()
		var step = cp["speed"] * delta
		if dist <= step or dist < 40.0:
			# 母星到達納品！
			GameState.add_resource(cp["res"], 1)
			AudioSynth.play_synth("pop")
			replication_rings.append({
				"pos": home_target + Vector2(randf_range(-20, 20), randf_range(-20, 20)),
				"radius": 2.0,
				"max_r": 18.0,
				"color": cp["color"],
				"timer": 0.25,
				"duration": 0.25
			})
			cargo_packets.remove_at(i)
		else:
			cp["pos"] += dir.normalized() * step
			
	if friendly_active_count <= 0:
		return

	# 1. ASSAULT ドクトリン時の激戦とボスダメージ
	if current_doctrine == "ASSAULT" and GameState.hostile_core_health > 0.0:
		for k in range(mini(friendly_active_count, 8)):
			var f_idx = randi() % friendly_active_count
			var f_pos = friendly_positions[f_idx]
			if f_pos.distance_to(boss_core_pos) < 650.0:
				if laser_lines.size() < 40:
					laser_lines.append({
						"from": f_pos,
						"to": boss_core_pos + Vector2(randf_range(-35, 35), randf_range(-35, 35)),
						"color": Color(0.1, 0.95, 1.0, 0.95),
						"timer": 0.18
					})
				var dmg = randf_range(6.0, 14.0) * (1.0 + float(friendly_active_count) * 0.0003)
				GameState.damage_hostile_core(dmg)
				if randf() < 0.4 and explosions.size() < 35:
					explosions.append({
						"pos": boss_core_pos + Vector2(randf_range(-40, 40), randf_range(-40, 40)),
						"radius": randf_range(16.0, 36.0),
						"timer": 0.35
					})

	# ボス撃破チェックと全銀河解放演出
	if GameState.hostile_core_health <= 0.0 and not boss_defeated:
		boss_defeated = true
		GameState.add_log("[*] GALAXY LIBERATED: REPLICA SWARM COMPLETE! [*]")
		AudioSynth.play_synth("victory")
		for b in range(30):
			explosions.append({
				"pos": boss_core_pos + Vector2(randf_range(-140, 140), randf_range(-140, 140)),
				"radius": randf_range(40.0, 120.0),
				"timer": randf_range(0.8, 3.0)
			})
		boss_shockwaves.append({
			"pos": boss_core_pos,
			"radius": 20.0,
			"timer": 3.0
		})

	# 2. MULTIPLY ドクトリン: 深宇宙自律自己増殖 (Self-Replication)
	if current_doctrine == "MULTIPLY" and friendly_active_count > 0 and friendly_active_count < MAX_UNITS:
		multiply_timer += delta
		var has_res = (GameState.resources.get("Fe", 0) >= 2 or GameState.resources.get("alloy", 0) >= 1)
		var interval = 0.45 if has_res else 1.6
		if multiply_timer >= interval:
			multiply_timer = 0.0
			if GameState.resources.get("Fe", 0) >= 2:
				GameState.consume_resource("Fe", 2)
			elif GameState.resources.get("alloy", 0) >= 1:
				GameState.consume_resource("alloy", 1)
				
			var parent_idx = randi() % friendly_active_count
			var p_pos = friendly_positions[parent_idx]
			var offset = Vector2(randf_range(-25, 25), randf_range(-25, 25))
			var new_pos = p_pos + offset
			var new_vel = friendly_velocities[parent_idx].rotated(randf_range(-0.35, 0.35))
			
			var new_idx = friendly_active_count
			friendly_positions[new_idx] = new_pos
			friendly_velocities[new_idx] = new_vel
			friendly_active_count += 1
			GameState.fleet_count = friendly_active_count
			GameState.fleet_changed.emit(friendly_active_count, MAX_UNITS)
			
			replication_rings.append({
				"pos": new_pos,
				"radius": 4.0,
				"max_r": 32.0,
				"color": Color(1.0, 0.88, 0.25, 0.95),
				"timer": 0.45,
				"duration": 0.45
			})
			AudioSynth.play_synth("pop")
			
			if friendly_active_count in [50, 100, 250, 500, 1000, 2500, 5000, 10000]:
				GameState.add_log("AUTOMA EXPANSION: SWARM REACHED %d UNITS!" % friendly_active_count)
				AudioSynth.play_synth("victory")
					
	# 3. メガストラクチャー建造レーザー演出 (動的公転座標同期)
	var is_building_mega = (GameState.active_megastructure_project != "")
	if is_building_mega and friendly_active_count > 0:
		var grid_m = get_parent().get_node_or_null("GridManager")
		var mega_pos = grid_m.surface_pos_at(0.0, 360.0) if grid_m else Vector2(800.0, 310.0)
		if GameState.active_megastructure_project == "dyson":
			mega_pos = (grid_m.SUN_POS + Vector2(0, -grid_m.SUN_RADIUS - 200.0)) if grid_m else Vector2(520.0, 90.0)
		elif GameState.active_megastructure_project == "citadel":
			mega_pos = grid_m.surface_pos_at(PI * 0.35, 480.0) if grid_m else Vector2(1060.0, 240.0)
		elif GameState.active_megastructure_project == "warpgate":
			mega_pos = (grid_m.SUN_POS + Vector2(9800.0, 3200.0)) if grid_m else Vector2(1480.0, 80.0)
			
		for k in range(3):
			var f_idx = randi() % friendly_active_count
			var f_pos = friendly_positions[f_idx]
			if f_pos.distance_to(mega_pos) < 300.0:
				laser_lines.append({
					"from": f_pos,
					"to": mega_pos + Vector2(randf_range(-20, 20), randf_range(-20, 20)),
					"color": Color(0.0, 1.0, 0.8, 0.85),
					"timer": 0.15
				})

	# 4. HARVEST ドクトリン時の宇宙天体採掘演出 (月・彗星・小惑星・ブラックホール・恒星)
	if current_doctrine == "HARVEST" and friendly_active_count > 0:
		var grid_mgr = get_parent().get_node_or_null("GridManager")
		if grid_mgr and grid_mgr.get("active_planets"):
			var plan_list: Array = grid_mgr.active_planets
			if not plan_list.is_empty():
				for k in range(mini(friendly_active_count, 4)):
					var f_idx = randi() % friendly_active_count
					var f_pos = friendly_positions[f_idx]
					var target_body = plan_list[randi() % plan_list.size()]
					if target_body.get("kind", "") != "home":
						var tpos: Vector2 = target_body.get("pos", Vector2.ZERO)
						if f_pos.distance_to(tpos) < target_body.get("influence", 300.0) * 0.95:
							var res = target_body.get("resource", "Fe")
							var res_col = Color(0.1, 1.8, 2.5, 0.8)
							if res == "He3": res_col = Color(0.3, 0.9, 1.0)
							elif res == "dark_matter": res_col = Color(0.9, 0.2, 1.0)
							elif res == "Ti": res_col = Color(0.8, 0.9, 1.0)
							elif res == "Cu": res_col = Color(1.0, 0.6, 0.2)
							
							laser_lines.append({
								"from": f_pos,
								"to": tpos + Vector2(randf_range(-18, 18), randf_range(-18, 18)),
								"color": res_col,
								"timer": 0.18
							})
							if randf() < 0.35 and cargo_packets.size() < 40:
								# 深宇宙光子カーゴパケットを母星へ射出
								cargo_packets.append({
									"pos": tpos,
									"speed": randf_range(380.0, 560.0),
									"res": res,
									"color": res_col,
									"timer": 0.0
								})

func _draw() -> void:
	# レーザーライン描画
	for laser in laser_lines:
		draw_line(laser["from"], laser["to"], laser["color"], 1.5)

	# 深宇宙光子カーゴパケット描画
	for cp in cargo_packets:
		var col = cp["color"]
		draw_circle(cp["pos"], 3.5, Color(col.r, col.g, col.b, 0.95))
		draw_circle(cp["pos"], 6.0, Color(col.r, col.g, col.b, 0.4))

	# ナノ自己複製リング描画
	for r in replication_rings:
		var progress = 1.0 - (r["timer"] / r["duration"])
		var curr_r = lerpf(r["radius"], r["max_r"], progress)
		var a = 1.0 - progress
		draw_arc(r["pos"], curr_r, 0, TAU, 18, Color(r["color"].r, r["color"].g, r["color"].b, a), 1.8)
		draw_circle(r["pos"], curr_r * 0.35, Color(r["color"].r, r["color"].g, r["color"].b, a * 0.5))

	# ボス撃破衝撃波描画
	for sw in boss_shockwaves:
		var alpha = sw["timer"] / 3.0
		draw_arc(sw["pos"], sw["radius"], 0, TAU, 32, Color(0.2, 0.9, 1.0, alpha * 0.9), 3.0)
		draw_arc(sw["pos"], sw["radius"] * 0.8, 0, TAU, 28, Color(1.0, 0.9, 0.3, alpha * 0.7), 2.0)
		
	# 爆発描画
	for exp in explosions:
		var alpha = exp["timer"] / 0.3
		draw_circle(exp["pos"], exp["radius"] * (1.5 - alpha), Color(1.0, 0.4, 0.1, alpha * 0.8))
		draw_arc(exp["pos"], exp["radius"] * (2.0 - alpha), 0, TAU, 12, Color(1.0, 0.9, 0.3, alpha), 1.5)
		
	# 敵ボス要塞コア（Corrupted Core Hub）の描画
	if GameState.hostile_core_health > 0.0:
		if tex_boss_core:
			draw_texture(tex_boss_core, boss_core_pos - Vector2(60, 60))
		else:
			draw_circle(boss_core_pos, 45.0, Color(0.8, 0.1, 0.2))
			
		# ボス巡洋艦（護衛艦）描画
		if tex_boss_cruiser:
			for i in range(3):
				var ca = anim_time * 0.8 + float(i) * (TAU / 3.0)
				var cpos = boss_core_pos + Vector2(cos(ca), sin(ca)) * 95.0
				draw_texture(tex_boss_cruiser, cpos - Vector2(24, 24))
				
		# ボスHPバー表示（ボスの頭上に配置し、下の惑星名との重なりを防止）
		var hp_ratio = GameState.hostile_core_health / GameState.hostile_core_max_health
		var bar_w = 140.0
		var bar_pos = boss_core_pos + Vector2(-bar_w * 0.5, -75.0)
		draw_rect(Rect2(bar_pos - Vector2(4, 16), Vector2(bar_w + 8, 30)), Color(0.04, 0.06, 0.1, 0.85))
		draw_rect(Rect2(bar_pos, Vector2(bar_w, 8)), Color(0.1, 0.1, 0.1, 0.9))
		draw_rect(Rect2(bar_pos, Vector2(bar_w * hp_ratio, 8)), Color(1.0, 0.2, 0.2, 0.95))
		draw_rect(Rect2(bar_pos, Vector2(bar_w, 8)), Color(0.8, 0.3, 0.3, 1.0), false, 1.0)
		draw_string(ThemeDB.fallback_font, bar_pos + Vector2(0, -3), "ENEMY CORE: %.0f / %.0f HP" % [GameState.hostile_core_health, GameState.hostile_core_max_health], HORIZONTAL_ALIGNMENT_CENTER, int(bar_w), 10, Color(1.0, 0.6, 0.6))
	else:
		# 撃破完了マーク
		draw_string(ThemeDB.fallback_font, boss_core_pos + Vector2(-90, 0), "[*] SYSTEM LIBERATED [*]", HORIZONTAL_ALIGNMENT_CENTER, 180, 16, Color(0.2, 1.0, 0.5))
