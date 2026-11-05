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

# 敵要塞コア＆巡洋艦
var boss_core_pos: Vector2 = Vector2(1380.0, 150.0) # CRYSTAL-IV 周辺
var tex_boss_core: Texture2D
var tex_boss_cruiser: Texture2D

# レーザー・戦闘・建造エフェクト
var laser_lines: Array[Dictionary] = [] # [{from, to, color, timer}]
var explosions: Array[Dictionary] = [] # [{pos, radius, timer}]

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
			
	if friendly_active_count <= 0:
		return

	# 1. ASSAULT ドクトリン時の激戦
	if current_doctrine == "ASSAULT" and GameState.hostile_core_health > 0.0:
		for k in range(mini(friendly_active_count, 6)):
			var f_idx = randi() % friendly_active_count
			var f_pos = friendly_positions[f_idx]
			if f_pos.distance_to(boss_core_pos) < 550.0:
				laser_lines.append({
					"from": f_pos,
					"to": boss_core_pos + Vector2(randf_range(-25, 25), randf_range(-25, 25)),
					"color": Color(0.1, 0.95, 1.0, 0.95),
					"timer": 0.18
				})
				if randf() < 0.4:
					explosions.append({
						"pos": boss_core_pos + Vector2(randf_range(-35, 35), randf_range(-35, 35)),
						"radius": randf_range(12.0, 28.0),
						"timer": 0.3
					})
					
	# 2. メガストラクチャー建造レーザー演出
	var is_building_mega = (GameState.active_megastructure_project != "")
	if is_building_mega and friendly_active_count > 0:
		var mega_pos = Vector2(800.0, 310.0)
		if GameState.active_megastructure_project == "dyson":
			mega_pos = Vector2(520.0, 90.0)
		elif GameState.active_megastructure_project == "citadel":
			mega_pos = Vector2(1060.0, 240.0)
		elif GameState.active_megastructure_project == "warpgate":
			mega_pos = Vector2(1480.0, 80.0)
			
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

	# 3. HARVEST ドクトリン時の宇宙天体採掘演出 (月・彗星・小惑星・ブラックホール・恒星)
	if current_doctrine == "HARVEST" and friendly_active_count > 0:
		var grid_mgr = get_parent().get_node_or_null("GridManager")
		if grid_mgr and grid_mgr.get("active_planets"):
			var plan_list: Array = grid_mgr.active_planets
			if not plan_list.is_empty():
				for k in range(mini(friendly_active_count, 3)):
					var f_idx = randi() % friendly_active_count
					var f_pos = friendly_positions[f_idx]
					var target_body = plan_list[randi() % plan_list.size()]
					if target_body.get("kind", "") != "home":
						var tpos: Vector2 = target_body.get("pos", Vector2.ZERO)
						if f_pos.distance_to(tpos) < target_body.get("influence", 300.0) * 0.95:
							var res = target_body.get("resource", "Fe")
							laser_lines.append({
								"from": f_pos,
								"to": tpos + Vector2(randf_range(-18, 18), randf_range(-18, 18)),
								"color": Color(0.1, 1.8, 2.5, 0.8),
								"timer": 0.18
							})
							if randf() < 0.25:
								GameState.add_resource(res, 1)

func _draw() -> void:
	# レーザーライン描画
	for laser in laser_lines:
		draw_line(laser["from"], laser["to"], laser["color"], 1.5)
		
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
		draw_string(ThemeDB.fallback_font, bar_pos + Vector2(0, -3), "敵要塞コア: %.0f / %.0f HP" % [GameState.hostile_core_health, GameState.hostile_core_max_health], HORIZONTAL_ALIGNMENT_CENTER, int(bar_w), 10, Color(1.0, 0.6, 0.6))
	else:
		# 撃破完了マーク
		draw_string(ThemeDB.fallback_font, boss_core_pos + Vector2(-60, 0), "★ 敵拠点制圧完了 ★", HORIZONTAL_ALIGNMENT_CENTER, 120, 14, Color(0.2, 1.0, 0.5))
