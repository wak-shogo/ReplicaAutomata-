extends Node2D

# STAR REPLICA: AUTOMA - ブループリント建築 ＆ 自律建築ドローン ＆ 実体物流 ＆ ケプラー公転天体物理
signal launch_probe_to_space(origin: Vector2, velocity: Vector2)
signal turret_fired(from_pos: Vector2, target_pos: Vector2)

# 1. 恒星 (太陽 Helios-Prime: 星系の不動の重力中心 ＆ 圧倒的巨大恒星)
const SUN_POS: Vector2 = Vector2(800.0, -850.0)
const SUN_RADIUS: float = 1100.0       # 太陽の圧倒的巨躯 (旧220pxから5倍拡大！)
const SUN_SURFACE_G: float = 320.0     # 恒星重力
const SUN_INFLUENCE: float = 5200.0    # 恒星重力圏

# 2. 母星 (Origin-Prime: 太陽の周りを滑らかに公転する生命の惑星)
const HOME_RADIUS: float = 420.0       # 母星半径 (太陽1100pxに対して適正な比率、周長約2640px)
const HOME_SURFACE_G: float = 165.0
const SECTOR_SIZE: float = 3200.0

var home_orbit_radius: float = 2400.0
var home_orbit_angle: float = PI * 0.5
var home_orbit_speed: float = 0.012    # 公転角速度 (約8.7分で太陽を1周)
var HOME_CENTER: Vector2 = SUN_POS + Vector2(cos(PI * 0.5), sin(PI * 0.5)) * 2400.0
var home_prev_pos: Vector2 = HOME_CENTER
var home_delta_pos: Vector2 = Vector2.ZERO

# 鉱脈データ (母星半径420pxに合わせた地下深度)
var ore_veins: Array[Dictionary] = [
	{"name": "Fe", "angle_off": -0.52, "depth_r": 315.0, "color": Color(0.3, 0.75, 1.0)},
	{"name": "Cu", "angle_off": -0.18, "depth_r": 285.0, "color": Color(0.95, 0.55, 0.2)},
	{"name": "Ti", "angle_off": +0.18, "depth_r": 305.0, "color": Color(0.8, 0.4, 1.0)},
	{"name": "Si", "angle_off": +0.50, "depth_r": 295.0, "color": Color(0.2, 0.95, 0.7)}
]

# 星系内各惑星の公転パラメータ
var vulcan_orbit_angle: float = -PI * 0.25
var vulcan_orbit_radius: float = 1800.0
var vulcan_orbit_speed: float = 0.024   # 内惑星：高速公転

var crystal_orbit_angle: float = PI * 0.85
var crystal_orbit_radius: float = 3300.0
var crystal_orbit_speed: float = 0.008  # 外惑星：低速公転

var aether_orbit_angle: float = PI * 0.15
var aether_orbit_radius: float = 2850.0
var aether_orbit_speed: float = 0.010

# 実体配置施設
var placed_buildings: Array[Dictionary] = []

# 建築予定ホログラム (Blueprints Queue)
# [{id: int, type: String, angle_off: float, alt: float, target_ore: String, progress: float, is_demolish: bool}]
var blueprints: Array[Dictionary] = []
var next_bp_id: int = 1

# 自律建築ドローン群 (Fabricator Drones)
# [{pos: Vector2, vel: Vector2, target_bp_id: int, state: "idle"|"flying"|"building"|"returning", work_timer: float}]
var construction_drones: Array[Dictionary] = []
var max_active_drones: int = 4

# コンベア上を流れる実体アイテム
var conveyor_items: Array[Dictionary] = []
var smoke_particles: Array[Dictionary] = []
var turret_lasers: Array[Dictionary] = []
var build_sparks: Array[Dictionary] = []

# ビルドモード制御
var is_build_mode: bool = false
var selected_tool: String = "none"
var is_drag_placing: bool = false
var last_placed_angle: float = -999.0
var last_input_was_gamepad: bool = false
var gamepad_cursor_pos: Vector2 = Vector2.ZERO
var gamepad_place_cooldown: float = 0.0

var anim_time: float = 0.0

# セクター惑星・宇宙天体管理 (公転物理演算・彗星・ブラックホール・恒星・中性子星・小惑星帯)
var generated_sectors: Dictionary = {}
var active_planets: Array[Dictionary] = []
var asteroid_belt: Array[Dictionary] = []
var comet_body: Dictionary = {}
var moon_body: Dictionary = {}

# テクスチャリソース
var tex_home_cross: Texture2D
var tex_planet_blue: Texture2D
var tex_planet_volcanic: Texture2D
var tex_planet_crystal: Texture2D
var tex_moon: Texture2D
var tex_celestial_sun: Texture2D
var tex_celestial_blackhole: Texture2D
var tex_celestial_comet: Texture2D
var tex_celestial_pulsar: Texture2D
var tex_celestial_asteroid: Texture2D
var tex_container: Texture2D
var tex_factory_sheet: Texture2D
var tex_drill_sheet: Texture2D
var tex_mass_driver_sheet: Texture2D
var tex_turret: Texture2D
var tex_solar: Texture2D
var tex_geothermal: Texture2D
var tex_drone: Texture2D
var tex_ores: Dictionary = {}

# メガストラクチャー
var tex_ms_elevator: Texture2D
var tex_ms_dyson: Texture2D
var tex_ms_citadel: Texture2D
var tex_ms_warpgate: Texture2D

func _ready() -> void:
	tex_home_cross = load("res://assets/environment/home_planet_cross_section.png")
	tex_planet_blue = load("res://assets/environment/planet_large.png")
	tex_planet_volcanic = load("res://assets/environment/planet_volcanic.png")
	tex_planet_crystal = load("res://assets/environment/planet_crystal.png")
	tex_moon = load("res://assets/environment/moon_asteroid.png")
	tex_container = load("res://assets/sprites/container_depot.png")
	tex_factory_sheet = load("res://assets/sprites/factory_hall_sheet.png")
	tex_drill_sheet = load("res://assets/sprites/mining_drill_sheet.png")
	tex_mass_driver_sheet = load("res://assets/sprites/mass_driver_sheet.png")
	tex_turret = load("res://assets/sprites/defense_turret.png")
	tex_solar = load("res://assets/sprites/solar_array.png")
	tex_geothermal = load("res://assets/sprites/geothermal_plant.png")
	tex_drone = load("res://assets/sprites/fabricator_drone.png")
	
	tex_ores["Fe"] = load("res://assets/environment/ore_fe.png")
	tex_ores["Cu"] = load("res://assets/environment/ore_cu.png")
	tex_ores["Ti"] = load("res://assets/environment/ore_ti.png")
	tex_ores["Si"] = load("res://assets/environment/ore_si.png")
	
	tex_ms_elevator = load("res://assets/sprites/megastructure_elevator.png")
	tex_ms_dyson = load("res://assets/sprites/megastructure_dyson.png")
	tex_ms_citadel = load("res://assets/sprites/megastructure_citadel.png")
	tex_ms_warpgate = load("res://assets/sprites/megastructure_warpgate.png")
	
	tex_celestial_sun = load("res://assets/environment/celestial_sun.png")
	tex_celestial_blackhole = load("res://assets/environment/celestial_blackhole.png")
	tex_celestial_comet = load("res://assets/environment/celestial_comet.png")
	tex_celestial_pulsar = load("res://assets/environment/celestial_pulsar.png")
	tex_celestial_asteroid = load("res://assets/environment/celestial_asteroid.png")
	
	init_starter_base()
	_init_celestial_system()
	ensure_sectors_around(Vector2(800, 450))

func init_starter_base() -> void:
	placed_buildings.clear()
	# 初期スターター
	placed_buildings.append({
		"type": "miner",
		"angle_off": -0.52,
		"alt": 20.0,
		"target_ore": "Fe",
		"timer": 0.0
	})
	placed_buildings.append({
		"type": "smelter",
		"angle_off": -0.38,
		"alt": 32.0,
		"target_ore": "Fe",
		"timer": 0.0
	})
	placed_buildings.append({
		"type": "turret",
		"angle_off": -0.22,
		"alt": 20.0,
		"timer": 0.0
	})
	placed_buildings.append({
		"type": "solar",
		"angle_off": -0.10,
		"alt": 16.0,
		"timer": 0.0
	})
	for i in range(8):
		var ba = lerpf(-0.52, -0.38, float(i) / 7.0)
		placed_buildings.append({
			"type": "belt",
			"angle_off": ba,
			"alt": 4.0,
			"timer": 0.0
		})

func surface_pos_at(angle_off: float, altitude: float = 0.0) -> Vector2:
	var a = -PI * 0.5 + angle_off
	var r = HOME_RADIUS + altitude
	return HOME_CENTER + Vector2(cos(a), sin(a)) * r

func angle_off_from_pos(pos: Vector2) -> float:
	var d = pos - HOME_CENTER
	var a = atan2(d.y, d.x)
	return a - (-PI * 0.5)

func _init_celestial_system() -> void:
	# 1. 月 (Luna-Prime: 母星の周りを完全物理演算で公転・半径64px)
	moon_body = {
		"id": "LUNA-PRIME", "name": "LUNA-PRIME",
		"orbit_parent": "ORIGIN-PRIME",
		"orbit_radius": 880.0,
		"orbit_angle": -PI * 0.35,
		"orbit_speed": 0.058,
		"radius": 64.0,
		"surface_g": 65.0,
		"influence": 280.0,
		"kind": "moon",
		"pos": HOME_CENTER + Vector2(cos(-PI * 0.35), sin(-PI * 0.35)) * 880.0,
		"resource": "He3"
	}
	
	# 2. 彗星 (Neowise-Omega: 恒星を焦点とする超長楕円ケプラー軌道)
	comet_body = {
		"id": "COMET-NEOWISE", "name": "COMET NEOWISE",
		"focus_pos": SUN_POS,
		"a": 2800.0,
		"e": 0.72,
		"tilt": 0.35,
		"theta": 0.0,
		"radius": 28.0,
		"surface_g": 35.0,
		"influence": 180.0,
		"kind": "comet",
		"pos": SUN_POS + Vector2(600.0, 450.0),
		"tail_dir": Vector2(0.8, 0.6).normalized(),
		"resource": "Ice"
	}
	
	# 3. 小惑星帯 (Asteroid Belt: 太陽 Helios-Prime の周りを公転)
	asteroid_belt.clear()
	for i in range(22):
		var ang = (TAU / 22.0) * float(i) + randf_range(-0.06, 0.06)
		var rad = randf_range(2650.0, 2880.0)
		var spd = randf_range(0.014, 0.022)
		var ores = ["Fe", "Si", "Ti"]
		asteroid_belt.append({
			"id": "ASTEROID-%d" % (i + 1),
			"orbit_angle": ang,
			"orbit_radius": rad,
			"orbit_speed": spd,
			"radius": randf_range(14.0, 24.0),
			"pos": SUN_POS + Vector2(cos(ang), sin(ang)) * rad,
			"kind": "asteroid",
			"resource": ores[i % ores.size()]
		})

func _update_celestial_simulation(delta: float) -> void:
	# 0. 母星 Origin-Prime の公転 (太陽の周りを滑らかに公転！)
	home_prev_pos = HOME_CENTER
	home_orbit_angle += home_orbit_speed * delta
	HOME_CENTER = SUN_POS + Vector2(cos(home_orbit_angle), sin(home_orbit_angle)) * home_orbit_radius
	home_delta_pos = HOME_CENTER - home_prev_pos

	# 1. 月の物理公転 (母星の現在位置 HOME_CENTER の周りを二重公転！)
	moon_body["orbit_angle"] += moon_body["orbit_speed"] * delta
	moon_body["pos"] = HOME_CENTER + Vector2(cos(moon_body["orbit_angle"]), sin(moon_body["orbit_angle"])) * moon_body["orbit_radius"]
	
	# 2. 内惑星 Vulcan-IX の公転 (太陽周回)
	vulcan_orbit_angle += vulcan_orbit_speed * delta
	var vulcan_pos = SUN_POS + Vector2(cos(vulcan_orbit_angle), sin(vulcan_orbit_angle)) * vulcan_orbit_radius
	
	# 3. 外惑星 Crystal-IV の公転 (太陽周回)
	crystal_orbit_angle += crystal_orbit_speed * delta
	var crystal_pos = SUN_POS + Vector2(cos(crystal_orbit_angle), sin(crystal_orbit_angle)) * crystal_orbit_radius

	# 4. 彗星のケプラー運動 (Keplerian Orbit: 太陽焦点)
	var e = comet_body["e"]
	var a = comet_body["a"]
	var r = a * (1.0 - e * e) / (1.0 + e * cos(comet_body["theta"]))
	var ang_vel = clampf(520.0 / maxf(180.0, r), 0.06, 0.85)
	comet_body["theta"] += ang_vel * delta
	var comet_ang = comet_body["theta"] + comet_body["tilt"]
	comet_body["pos"] = comet_body["focus_pos"] + Vector2(cos(comet_ang), sin(comet_ang)) * r
	comet_body["tail_dir"] = (comet_body["pos"] - comet_body["focus_pos"]).normalized()
	
	# 5. 小惑星帯の公転 (太陽周回)
	for ast in asteroid_belt:
		ast["orbit_angle"] += ast["orbit_speed"] * delta
		ast["pos"] = SUN_POS + Vector2(cos(ast["orbit_angle"]), sin(ast["orbit_angle"])) * ast["orbit_radius"]

	# active_planets 内の天体座標を同期
	for p in active_planets:
		match p["id"]:
			"ORIGIN-PRIME":
				p["pos"] = HOME_CENTER
			"LUNA-PRIME":
				p["pos"] = moon_body["pos"]
			"COMET-NEOWISE":
				p["pos"] = comet_body["pos"]
			"VULCAN-IX":
				p["pos"] = vulcan_pos
			"CRYSTAL-IV":
				p["pos"] = crystal_pos

func ensure_sectors_around(world_pos: Vector2) -> void:
	var cx = int(floor(world_pos.x / SECTOR_SIZE))
	var cy = int(floor(world_pos.y / SECTOR_SIZE))
	active_planets.clear()
	
	active_planets.append({
		"id": "ORIGIN-PRIME",
		"name": "ORIGIN-PRIME",
		"pos": HOME_CENTER,
		"radius": HOME_RADIUS,
		"surface_g": HOME_SURFACE_G,
		"influence": HOME_RADIUS * 4.2,
		"kind": "home"
	})
	
	for sy in range(cy - 2, cy + 3):
		for sx in range(cx - 2, cx + 3):
			var cell = Vector2i(sx, sy)
			if not generated_sectors.has(cell):
				generated_sectors[cell] = _generate_sector_planets(cell)
			for p in generated_sectors[cell]:
				active_planets.append(p)

func _generate_sector_planets(cell: Vector2i) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	if cell == Vector2i(0, 0):
		# 1. 恒星 (Sun / Helios-Prime: 圧倒的巨躯の太陽プラズマ源)
		list.append({
			"id": "HELIOS-PRIME", "name": "HELIOS-PRIME",
			"pos": SUN_POS, "radius": SUN_RADIUS, "surface_g": SUN_SURFACE_G, "influence": SUN_INFLUENCE,
			"kind": "sun", "resource": "Plasma"
		})
		# 2. 月 (Luna-Prime: 母星を物理公転する衛星・ヘリウム3)
		list.append({
			"id": "LUNA-PRIME", "name": "LUNA-PRIME",
			"pos": moon_body["pos"], "radius": moon_body["radius"], "surface_g": moon_body["surface_g"], "influence": moon_body["influence"],
			"kind": "moon", "resource": "He3"
		})
		# 3. 彗星 (Neowise-Omega: 楕円ケプラー軌道・重水素氷)
		list.append({
			"id": "COMET-NEOWISE", "name": "COMET NEOWISE",
			"pos": comet_body["pos"], "radius": comet_body["radius"], "surface_g": comet_body["surface_g"], "influence": comet_body["influence"],
			"kind": "comet", "resource": "Ice"
		})
		# 4. ブラックホール (Gargantua-Zero: 超高重力特異点・暗黒物質)
		list.append({
			"id": "GARGANTUA-ZERO", "name": "GARGANTUA-ZERO",
			"pos": SUN_POS + Vector2(3800.0, -1800.0), "radius": 80.0, "surface_g": 480.0, "influence": 1200.0,
			"kind": "blackhole", "resource": "DarkMatter"
		})
		# 5. 中性子星 / パルサー (Pulsar-X: 高速回転極ジェット・中性子縮退物質)
		list.append({
			"id": "PULSAR-X", "name": "PULSAR-X",
			"pos": SUN_POS + Vector2(-3600.0, -1400.0), "radius": 36.0, "surface_g": 220.0, "influence": 600.0,
			"kind": "pulsar", "resource": "Neutronium"
		})
		# 6. 小惑星帯 (Asteroid Belt)
		for ast in asteroid_belt:
			list.append({
				"id": ast["id"], "name": ast["id"],
				"pos": ast["pos"], "radius": ast["radius"], "surface_g": 25.0, "influence": 80.0,
				"kind": "asteroid", "resource": ast["resource"]
			})
		# 7. 星系内惑星 (Vulcan-IX, Crystal-IV)
		var v_init_pos = SUN_POS + Vector2(cos(vulcan_orbit_angle), sin(vulcan_orbit_angle)) * vulcan_orbit_radius
		var c_init_pos = SUN_POS + Vector2(cos(crystal_orbit_angle), sin(crystal_orbit_angle)) * crystal_orbit_radius
		list.append({"id": "VULCAN-IX", "name": "VULCAN-IX", "pos": v_init_pos, "radius": 160.0, "surface_g": 140.0, "influence": 450.0, "kind": "volcanic", "scale": 1.0, "resource": "Cu"})
		list.append({"id": "CRYSTAL-IV", "name": "CRYSTAL-IV", "pos": c_init_pos, "radius": 130.0, "surface_g": 110.0, "influence": 400.0, "kind": "crystal", "scale": 1.0, "resource": "Si"})
		return list

	var rng = RandomNumberGenerator.new()
	rng.seed = int(abs((cell.x * 73856093) ^ (cell.y * 19349663) ^ 918273645))
	var count = rng.randi_range(3, 6)
	var kinds = ["blue", "volcanic", "crystal", "moon"]
	var syllables = ["AL", "VE", "KAI", "ZEN", "DRA", "SOL", "NEX", "OR", "TAL", "MIR"]
	
	for i in range(count):
		var px = float(cell.x) * SECTOR_SIZE + rng.randf_range(350.0, SECTOR_SIZE - 350.0)
		var py = float(cell.y) * SECTOR_SIZE + rng.randf_range(350.0, SECTOR_SIZE - 350.0)
		var k = kinds[rng.randi() % kinds.size()]
		var sc = rng.randf_range(0.75, 1.45)
		var base_r = 110.0 if k == "blue" else (72.0 if k in ["volcanic", "crystal"] else 45.0)
		var rad = base_r * sc
		var pname = "%s-%s %d" % [syllables[rng.randi() % syllables.size()], syllables[rng.randi() % syllables.size()], i + 1]
		list.append({"id": pname, "name": pname, "pos": Vector2(px, py), "radius": rad, "surface_g": rng.randf_range(60.0, 140.0) * sc, "influence": rad * 4.2, "kind": k, "scale": sc})
	return list

func compute_gravity_and_orbit(pos: Vector2, vel: Vector2 = Vector2.ZERO) -> Dictionary:
	var total_acc = Vector2.ZERO
	var primary: Dictionary = active_planets[0] if not active_planets.is_empty() else {}
	var best_weight: float = -1.0
	
	for p in active_planets:
		var d: Vector2 = pos - p["pos"]
		var r_sq: float = maxf(1.0, d.length_squared())
		var r: float = sqrt(r_sq)
		var rp: float = p["radius"]
		var inf: float = p["influence"]
		if r > inf: continue
		var g_mag: float = 0.0
		if r >= rp:
			var ratio = rp / r
			g_mag = p["surface_g"] * (ratio * ratio)
		else:
			g_mag = p["surface_g"] * (r / maxf(1.0, rp))
		total_acc += (-d / r) * g_mag
		
		var w = g_mag * (2.5 if r < rp * 1.8 else 1.0)
		if w > best_weight:
			best_weight = w
			primary = p
			
	var d_prim = pos - primary.get("pos", HOME_CENTER)
	var r_prim = maxf(1.0, d_prim.length())
	var rp_prim = primary.get("radius", HOME_RADIUS)
	var g0_prim = primary.get("surface_g", HOME_SURFACE_G)
	var g_local = g0_prim * pow(rp_prim / maxf(r_prim, rp_prim), 2.0)
	var v_circular = sqrt(g_local * maxf(r_prim, rp_prim))
	var v_escape = sqrt(2.0) * v_circular
	var speed = vel.length()
	
	var state_str = "SUB-ORBITAL"
	if r_prim <= rp_prim + 10.0:
		state_str = "SURFACE"
	elif speed >= v_escape * 0.98:
		state_str = "ESCAPE"
	elif speed >= v_circular * 0.78:
		state_str = "ORBIT"
	else:
		state_str = "FREEFALL"
		
	return {
		"acc": total_acc,
		"primary": primary,
		"v_circular": v_circular,
		"v_escape": v_escape,
		"altitude": r_prim - rp_prim,
		"orbit_state": state_str
	}

# ツール選択
func select_tool(tool_id: String) -> void:
	if selected_tool == tool_id:
		selected_tool = "none"
		is_build_mode = false
	else:
		selected_tool = tool_id
		is_build_mode = true
	AudioSynth.play_synth("click")

func get_target_cursor_pos() -> Vector2:
	var joy_rx = Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var joy_ry = Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	var joy_vec = Vector2(joy_rx, joy_ry)
	
	var player = get_parent().get_node_or_null("Player")
	var ppos = player.global_position if player else HOME_CENTER + Vector2(0, HOME_RADIUS)
	
	if joy_vec.length() > 0.25:
		last_input_was_gamepad = true
		gamepad_cursor_pos = ppos + joy_vec.normalized() * 160.0
		return gamepad_cursor_pos
	elif last_input_was_gamepad:
		var ang = angle_off_from_pos(ppos)
		gamepad_cursor_pos = surface_pos_at(ang, 20.0)
		return gamepad_cursor_pos
	else:
		return get_global_mouse_position()

# ========================================================
# 採掘判定 (母星地下鉱脈 or 宇宙天体固有資源)
# ========================================================
func get_mining_info_at(target_p: Vector2) -> Dictionary:
	# 1. 宇宙天体 (恒星・ブラックホール・月・彗星・パルサー・小惑星・惑星)
	for p in active_planets:
		if p["kind"] == "home": continue
		var ppos: Vector2 = p["pos"]
		var prad: float = p["radius"]
		var d = target_p.distance_to(ppos)
		if d <= prad + 120.0:
			var res_type = p.get("resource", "Fe")
			var beam_c = Color(0.0, 2.5, 3.0)
			match res_type:
				"Plasma": beam_c = Color(1.5, 0.8, 0.1)
				"DarkMatter": beam_c = Color(1.2, 0.2, 1.5)
				"Ice": beam_c = Color(0.2, 1.0, 1.5)
				"He3": beam_c = Color(0.0, 2.2, 2.8)
				"Neutronium": beam_c = Color(0.1, 2.8, 1.8)
			return {
				"type": res_type,
				"name": p["name"],
				"is_celestial": true,
				"color": beam_c
			}

	# 2. 小惑星帯個別チェック
	for ast in asteroid_belt:
		if target_p.distance_to(ast["pos"]) <= ast["radius"] + 50.0:
			return {
				"type": ast["resource"],
				"name": ast["id"],
				"is_celestial": true,
				"color": Color(0.5, 0.9, 1.0)
			}

	# 3. 母星地下鉱脈
	var nearest_dist = 9999.0
	var chosen_ore = "Fe"
	var ore_col = Color(0.3, 0.75, 1.0)
	for v in ore_veins:
		var a = -PI * 0.5 + v["angle_off"]
		var vpos = HOME_CENTER + Vector2(cos(a), sin(a)) * v["depth_r"]
		var d = target_p.distance_to(vpos)
		if d < nearest_dist:
			nearest_dist = d
			chosen_ore = v["name"]
			ore_col = v["color"]
			
	if nearest_dist < 280.0:
		return {"type": chosen_ore, "name": chosen_ore, "is_celestial": false, "color": ore_col}
	return {"type": "Fe", "name": "Crust", "is_celestial": false, "color": Color(0.3, 0.75, 1.0)}

# ========================================================
# ブループリント配置 ＆ コンベアドラッグ入力
# ========================================================
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		last_input_was_gamepad = false
		var mouse_pos = get_global_mouse_position()
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if selected_tool != "none":
					is_drag_placing = true
					last_placed_angle = -999.0
					_place_blueprint_at_mouse(mouse_pos)
			else:
				is_drag_placing = false
				last_placed_angle = -999.0
				
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if selected_tool != "none":
				selected_tool = "none"
				is_build_mode = false
				is_drag_placing = false
				AudioSynth.play_synth("click")
				
	elif event is InputEventMouseMotion and is_drag_placing:
		last_input_was_gamepad = false
		# コンベア等の連続ドラッグ敷設
		if selected_tool == "belt":
			var mouse_pos = get_global_mouse_position()
			var ang_off = angle_off_from_pos(mouse_pos)
			if abs(ang_off - last_placed_angle) > 0.035:
				_place_blueprint_at_mouse(mouse_pos)

	elif event is InputEventJoypadButton and event.pressed:
		last_input_was_gamepad = true
		if event.button_index == JOY_BUTTON_B:
			if selected_tool != "none":
				selected_tool = "none"
				is_build_mode = false
				is_drag_placing = false
				AudioSynth.play_synth("click")

func _place_blueprint_at_mouse(mouse_pos: Vector2) -> void:
	var dist = mouse_pos.distance_to(HOME_CENTER)
	var ang_off = angle_off_from_pos(mouse_pos)
	
	# 解体ブループリント
	if selected_tool == "demolish":
		for b in placed_buildings:
			var bpos = surface_pos_at(b["angle_off"], b.get("alt", 0.0))
			if mouse_pos.distance_to(bpos) < 32.0:
				_add_blueprint(b["type"], b["angle_off"], b.get("alt", 0.0), "", true)
				AudioSynth.play_synth("click")
				return
		return
		
	var is_geothermal = (selected_tool == "geothermal")
	if is_geothermal:
		if dist < 360.0 or dist > 540.0: return
	else:
		if dist < 500.0 or dist > 760.0: return
		
	# 既存ブループリントとの重複防止
	for bp in blueprints:
		if abs(bp["angle_off"] - ang_off) < 0.02 and bp["type"] == selected_tool:
			return

	# 素材在庫・クラフト可能チェック
	var has_stock = GameState.items.get(selected_tool, 0) > 0
	if not has_stock:
		var hud = get_parent().get_node_or_null("HUD")
		if selected_tool == "miner" and (GameState.resources.get("Fe", 0) < 20 or GameState.resources.get("Cu", 0) < 10):
			if hud and hud.has_method("show_missing_res_alert"): hud.show_missing_res_alert("20 Fe + 10 Cu")
			return
		elif selected_tool == "belt" and GameState.resources.get("Fe", 0) < 6:
			if hud and hud.has_method("show_missing_res_alert"): hud.show_missing_res_alert("6 Fe")
			return
		elif selected_tool == "smelter" and (GameState.resources.get("Fe", 0) < 30 or GameState.resources.get("Cu", 0) < 15):
			if hud and hud.has_method("show_missing_res_alert"): hud.show_missing_res_alert("30 Fe + 15 Cu")
			return

	var alt = 4.0
	var target_ore = ""
	match selected_tool:
		"miner":
			alt = 20.0
			var nearest_vein = ore_veins[0]
			var min_adiff = 999.0
			for v in ore_veins:
				var diff = abs(v["angle_off"] - ang_off)
				if diff < min_adiff:
					min_adiff = diff
					nearest_vein = v
			target_ore = nearest_vein["name"]
			ang_off = nearest_vein["angle_off"]
		"smelter": alt = 32.0
		"assembler": alt = 34.0
		"mass_driver": alt = 48.0
		"depot": alt = 26.0
		"turret": alt = 20.0
		"solar": alt = 16.0
		"geothermal": alt = -160.0
		"belt": alt = 4.0

	last_placed_angle = ang_off
	_add_blueprint(selected_tool, ang_off, alt, target_ore, false)
	AudioSynth.play_synth("click")

func _add_blueprint(type_str: String, ang: float, alt: float, ore: String, is_demo: bool) -> void:
	blueprints.append({
		"id": next_bp_id,
		"type": type_str,
		"angle_off": ang,
		"alt": alt,
		"target_ore": ore,
		"progress": 0.0,
		"is_demolish": is_demo
	})
	next_bp_id += 1

# ========================================================
# 自律建築ドローン (Fabricator Drones) のAI＆溶接シミュレーション
# ========================================================
func _process(delta: float) -> void:
	anim_time += delta
	_update_celestial_simulation(delta)
	_update_power_grid()
	
	# ゲームパッド配置判定 (RTトリガー or Aボタン)
	if selected_tool != "none":
		gamepad_place_cooldown -= delta
		var is_gp_press = (Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) > 0.35) or Input.is_joy_button_pressed(0, JOY_BUTTON_A)
		if is_gp_press:
			last_input_was_gamepad = true
			var cpos = get_target_cursor_pos()
			var ang_off = angle_off_from_pos(cpos)
			if selected_tool == "belt":
				if abs(ang_off - last_placed_angle) > 0.035:
					_place_blueprint_at_mouse(cpos)
			elif gamepad_place_cooldown <= 0.0:
				_place_blueprint_at_mouse(cpos)
				gamepad_place_cooldown = 0.25

	# 自律建築ドローンの同期＆作業
	_update_construction_drones(delta)
	
	# 各施設の稼働
	_update_placed_buildings(delta)
	
	# コンベアアイテムの移動 ＆ 近接施設へのスマート自動吸着投入
	for i in range(conveyor_items.size() - 1, -1, -1):
		var item = conveyor_items[i]
		item["angle_off"] += item["speed"] * delta
		var ipos = surface_pos_at(item["angle_off"], 6.0)
		
		# 近接施設（精錬炉・組立機・マスドライバー・デポ）へスマート自動投入！
		var absorbed = false
		for b in placed_buildings:
			var bpos = surface_pos_at(b["angle_off"], b.get("alt", 0.0))
			if ipos.distance_to(bpos) < 32.0:
				match b["type"]:
					"smelter":
						if item["type"] in ["Fe", "Cu", "Si"]:
							absorbed = true
					"assembler":
						if item["type"] in ["plate_fe", "wire_cu", "silicon_wafer", "circuit"]:
							absorbed = true
					"mass_driver":
						if item["type"] == "drone_unit":
							absorbed = true
							_fire_mass_driver_at(b["angle_off"], b["alt"])
					"depot":
						absorbed = true
				if absorbed: break
				
		if absorbed:
			conveyor_items.remove_at(i)
			continue

		if item["angle_off"] > 0.65:
			conveyor_items.remove_at(i)
			
	# スモーク・火花・タレット更新
	for i in range(smoke_particles.size() - 1, -1, -1):
		var p = smoke_particles[i]
		p["pos"] += p["vel"] * delta
		p["radius"] += delta * 4.0
		p["life"] -= delta
		if p["life"] <= 0.0: smoke_particles.remove_at(i)
		
	for i in range(build_sparks.size() - 1, -1, -1):
		var s = build_sparks[i]
		s["pos"] += s["vel"] * delta
		s["life"] -= delta
		if s["life"] <= 0.0: build_sparks.remove_at(i)
		
	for i in range(turret_lasers.size() - 1, -1, -1):
		turret_lasers[i]["timer"] -= delta
		if turret_lasers[i]["timer"] <= 0.0: turret_lasers.remove_at(i)
		
	queue_redraw()

func _update_construction_drones(delta: float) -> void:
	var player = get_parent().get_node_or_null("Player")
	var player_pos = player.global_position if player else Vector2(800, 520)
	
	# 利用可能なドローン数 (最低2機、合体ドローン数に応じて最大8機)
	var target_drone_count = maxi(2, mini(8, GameState.attached_drones + 2))
	while construction_drones.size() < target_drone_count:
		construction_drones.append({
			"pos": player_pos + Vector2(randf_range(-20, 20), randf_range(-20, 20)),
			"vel": Vector2.ZERO,
			"target_bp_id": -1,
			"state": "idle"
		})
	while construction_drones.size() > target_drone_count:
		construction_drones.pop_back()
		
	for drone in construction_drones:
		# ターゲットのブループリントを割り当て
		if drone["target_bp_id"] == -1 and not blueprints.is_empty():
			for bp in blueprints:
				var is_claimed = false
				for other in construction_drones:
					if other["target_bp_id"] == bp["id"]:
						is_claimed = true
						break
				if not is_claimed:
					drone["target_bp_id"] = bp["id"]
					drone["state"] = "flying"
					break
					
		# 対象ブループリントの取得
		var current_bp: Dictionary = {}
		for bp in blueprints:
			if bp["id"] == drone["target_bp_id"]:
				current_bp = bp
				break
				
		if current_bp.is_empty():
			# 作業完了 -> 自機へ帰還
			drone["target_bp_id"] = -1
			drone["state"] = "returning"
			var d_home = player_pos - drone["pos"]
			if d_home.length() > 30.0:
				drone["vel"] = drone["vel"].lerp(d_home.normalized() * 320.0, delta * 8.0)
			else:
				drone["vel"] = drone["vel"].lerp(Vector2.ZERO, delta * 10.0)
				drone["state"] = "idle"
			drone["pos"] += drone["vel"] * delta
			continue
			
		# ブループリント現場へ向かう
		var dest_pos = surface_pos_at(current_bp["angle_off"], current_bp["alt"] + 18.0)
		var d_dest = dest_pos - drone["pos"]
		
		if d_dest.length() > 35.0:
			drone["state"] = "flying"
			drone["vel"] = drone["vel"].lerp(d_dest.normalized() * 360.0, delta * 9.0)
			drone["pos"] += drone["vel"] * delta
		else:
			# 現場到着 -> ナノ溶接レーザー照射＆建設進行！
			drone["state"] = "building"
			drone["vel"] = drone["vel"].lerp(Vector2.ZERO, delta * 12.0)
			drone["pos"] += drone["vel"] * delta
			
			# 建設進行 (進捗アップ)
			var build_speed = 0.85 * delta
			current_bp["progress"] += build_speed
			
			# スパーク火花エフェクト
			if randf() < 0.65:
				build_sparks.append({
					"pos": dest_pos + Vector2(randf_range(-10, 10), randf_range(-10, 10)),
					"vel": Vector2(randf_range(-40, 40), randf_range(-40, 40)),
					"life": 0.25
				})
				
			if current_bp["progress"] >= 1.0:
				# 建設または解体完了！
				_finish_blueprint(current_bp)
				drone["target_bp_id"] = -1

func _finish_blueprint(bp: Dictionary) -> void:
	if bp["is_demolish"]:
		# 解体
		for i in range(placed_buildings.size() - 1, -1, -1):
			var b = placed_buildings[i]
			if abs(b["angle_off"] - bp["angle_off"]) < 0.02 and b["type"] == bp["type"]:
				GameState.add_item(b["type"], 1)
				placed_buildings.remove_at(i)
				AudioSynth.play_synth("mine")
				break
	else:
		# 建設完了 -> 実体施設を配置
		var has_stock = GameState.items.get(bp["type"], 0) > 0
		if has_stock:
			GameState.consume_item(bp["type"], 1)
		else:
			GameState.craft_item(bp["type"])
			
		placed_buildings.append({
			"type": bp["type"],
			"angle_off": bp["angle_off"],
			"alt": bp["alt"],
			"target_ore": bp["target_ore"],
			"timer": 0.0
		})
		AudioSynth.play_synth("build")
		GameState.notify_building_constructed(bp["type"])
		
	# ブループリントキューから削除
	var idx = blueprints.find(bp)
	if idx != -1:
		blueprints.remove_at(idx)

func _update_placed_buildings(delta: float) -> void:
	var speed_mult = GameState.power_ratio
	if GameState.megastructures["dyson"]["built"]:
		speed_mult *= 2.0

	for b in placed_buildings:
		b["timer"] = b.get("timer", 0.0) + delta * speed_mult
		match b["type"]:
			"miner":
				if b["timer"] >= 1.6:
					b["timer"] = 0.0
					var ore = b.get("target_ore", "Fe")
					if GameState.vein_reserves.get(ore, 0) > 0:
						GameState.vein_reserves[ore] -= 2
						GameState.add_resource(ore, 2)
						_spawn_conveyor_item(ore, b["angle_off"])
					var bpos = surface_pos_at(b["angle_off"], b["alt"])
					smoke_particles.append({"pos": bpos, "vel": (bpos - HOME_CENTER).normalized() * 32.0, "radius": 4.0, "life": 0.7, "max_life": 0.7})
			"smelter":
				if b["timer"] >= 2.2:
					b["timer"] = 0.0
					if GameState.consume_resource("Fe", 2):
						GameState.add_item("plate_fe", 1)
						_spawn_conveyor_item("plate_fe", b["angle_off"])
					if GameState.consume_resource("Cu", 2):
						GameState.add_item("wire_cu", 2)
					if GameState.consume_resource("Si", 2):
						GameState.add_item("silicon_wafer", 1)
					var bpos = surface_pos_at(b["angle_off"], b["alt"] + 24.0)
					smoke_particles.append({"pos": bpos, "vel": (bpos - HOME_CENTER).normalized() * 38.0 + Vector2(randf_range(-5, 5), 0), "radius": 5.0, "life": 1.2, "max_life": 1.2})
			"assembler":
				if b["timer"] >= 2.8:
					b["timer"] = 0.0
					if GameState.items.get("plate_fe", 0) >= 1 and GameState.items.get("wire_cu", 0) >= 1:
						GameState.consume_item("plate_fe", 1)
						GameState.consume_item("wire_cu", 1)
						GameState.add_item("drone_unit", 1)
						_spawn_conveyor_item("drone_unit", b["angle_off"])
			"mass_driver":
				if b["timer"] >= 1.8:
					b["timer"] = 0.0
					var has_unit = GameState.consume_item("drone_unit", 1)
					if has_unit or randf() < 0.35:
						_fire_mass_driver_at(b["angle_off"], b["alt"])
			"turret":
				if b["timer"] >= 0.8:
					b["timer"] = 0.0
					_turret_scan_and_fire(b)

func _update_power_grid() -> void:
	var gen = 40.0
	var con = 10.0
	if GameState.megastructures["dyson"]["built"]: gen += 99999.0
	for b in placed_buildings:
		match b["type"]:
			"solar": gen += 35.0
			"geothermal": gen += 130.0
			"miner": con += 15.0
			"smelter": con += 22.0
			"assembler": con += 28.0
			"mass_driver": con += 35.0
			"turret": con += 12.0
	GameState.power_generated = gen
	GameState.power_consumed = con
	GameState.power_ratio = clampf(gen / maxf(1.0, con), 0.25, 1.0)
	GameState.resources["Energy"] = GameState.power_ratio * 100.0

func _spawn_conveyor_item(item_type: String, start_angle: float) -> void:
	if conveyor_items.size() > 40: return
	var col = Color(0.35, 0.85, 1.0)
	if item_type == "Cu": col = Color(1.0, 0.6, 0.2)
	elif item_type == "plate_fe": col = Color(0.7, 0.85, 1.0)
	elif item_type == "drone_unit": col = Color(1.0, 0.9, 0.3)
	conveyor_items.append({"type": item_type, "angle_off": start_angle, "speed": 0.18, "color": col})

func _turret_scan_and_fire(turret_b: Dictionary) -> void:
	var tpos = surface_pos_at(turret_b["angle_off"], turret_b["alt"])
	var main_node = get_parent()
	if not main_node: return
	var bombers = main_node.get("active_bombers")
	if bombers and not bombers.is_empty():
		var target_bomber = bombers[0]
		var b_pos = target_bomber.get("pos", Vector2.ZERO)
		if tpos.distance_to(b_pos) < 650.0:
			turret_lasers.append({"from": tpos, "to": b_pos, "color": Color(0.0, 1.5, 3.0), "timer": 0.16})
			AudioSynth.play_synth("laser")
			target_bomber["hp"] -= 35.0
			if target_bomber["hp"] <= 0.0:
				main_node.destroy_bomber(target_bomber)

func _fire_mass_driver_at(ang_off: float, alt: float) -> void:
	var launch_pos = surface_pos_at(ang_off, alt + 20.0)
	var radial_dir = (launch_pos - HOME_CENTER).normalized()
	var tangent_dir = Vector2(-radial_dir.y, radial_dir.x)
	var r = launch_pos.distance_to(HOME_CENTER)
	var v_circ = sqrt(HOME_SURFACE_G * HOME_RADIUS * HOME_RADIUS / r)
	var speed_mult = 1.45 if randf() < 0.22 else randf_range(1.02, 1.25)
	var launch_dir = (tangent_dir * 0.88 + radial_dir * 0.46).normalized()
	var launch_vel = launch_dir * (v_circ * speed_mult)
	launch_probe_to_space.emit(launch_pos, launch_vel)
	AudioSynth.play_synth("launch")
	GameState.add_fleet(10)
	var main_node = get_parent()
	if main_node and main_node.has_method("shake_camera"):
		main_node.shake_camera(6.0, 0.25)

func draw_sheet_frame_rotated(tex: Texture2D, frame_idx: int, total_frames: int, world_pos: Vector2, rot: float, sc: Vector2 = Vector2.ONE) -> void:
	if not tex: return
	var fw = tex.get_width() / float(total_frames)
	var fh = float(tex.get_height())
	var src_rect = Rect2(fw * float(frame_idx), 0.0, fw, fh)
	var dst_rect = Rect2(-fw * 0.5 * sc.x, -fh * 0.5 * sc.y, fw * sc.x, fh * sc.y)
	draw_set_transform(world_pos, rot, Vector2.ONE)
	draw_texture_rect_region(tex, dst_rect, src_rect)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_celestial_bodies() -> void:
	# A. 太陽を中心とする惑星公転軌道ライン群 (Orbit Rails)
	draw_arc(SUN_POS, vulcan_orbit_radius, 0, TAU, 96, Color(1.0, 0.45, 0.2, 0.12), 1.2)
	draw_arc(SUN_POS, home_orbit_radius, 0, TAU, 128, Color(0.2, 0.85, 1.0, 0.16), 1.5)
	draw_arc(SUN_POS, 2760.0, 0, TAU, 128, Color(0.35, 0.45, 0.65, 0.08), 40.0) # 小惑星帯
	draw_arc(SUN_POS, crystal_orbit_radius, 0, TAU, 128, Color(0.2, 1.0, 0.7, 0.12), 1.2)

	# B. 月の母星周回軌道ライン
	if not moon_body.is_empty():
		draw_arc(HOME_CENTER, moon_body["orbit_radius"], 0, TAU, 72, Color(0.2, 0.8, 1.0, 0.18), 1.2)

	# C. 各天体の描画
	for p in active_planets:
		if p["kind"] == "home": continue
		var ppos: Vector2 = p["pos"]
		var prad: float = p["radius"]
		var pkind: String = p.get("kind", "")
		var pres: String = p.get("resource", "")

		match pkind:
			"sun":
				# 1. 恒星 (Helios-Prime: 圧倒的巨躯の太陽)
				# 巨大コロナ脈動リング (HDR Glow)
				var c_pulse = (sin(anim_time * 2.5) * 0.5 + 0.5)
				draw_arc(ppos, prad * 1.08 + c_pulse * 30.0, 0, TAU, 96, Color(1.0, 0.7, 0.1, 0.35), 8.0)
				draw_arc(ppos, prad * 1.22 + c_pulse * 45.0, 0, TAU, 80, Color(1.0, 0.3, 0.1, 0.20), 12.0)
				# 太陽核
				draw_circle(ppos, prad, Color(1.2, 0.8, 0.2, 1.0))
				draw_circle(ppos, prad * 0.75, Color(2.5, 2.0, 0.8, 1.0))
				if tex_celestial_sun:
					var sz = Vector2(prad * 2.4, prad * 2.4)
					draw_set_transform(ppos, anim_time * 0.04, Vector2.ONE)
					draw_texture_rect(tex_celestial_sun, Rect2(-sz * 0.5, sz), false)
					draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				draw_string(ThemeDB.fallback_font, ppos + Vector2(-60, prad + 45), "HELIOS-PRIME [Plasma]", HORIZONTAL_ALIGNMENT_CENTER, -1, 16, Color(1.0, 0.85, 0.3))

			"blackhole":
				# 2. ブラックホール (Gargantua-Zero)
				draw_arc(ppos, prad * 1.8, 0, TAU, 48, Color(0.0, 2.0, 3.0, 0.35), 2.0)
				# 重力歪みアーク
				draw_arc(ppos, prad * 2.8, 0, TAU, 48, Color(0.8, 0.2, 1.0, 0.15), 1.0)
				if tex_celestial_blackhole:
					var sz = Vector2(prad * 2.8, prad * 2.8)
					draw_set_transform(ppos, anim_time * 0.6, Vector2.ONE)
					draw_texture_rect(tex_celestial_blackhole, Rect2(-sz * 0.5, sz), false)
					draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				draw_string(ThemeDB.fallback_font, ppos + Vector2(-45, prad + 24), "SINGULARITY [DarkMatter]", HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color(0.8, 0.4, 1.0))

			"pulsar":
				# 3. 中性子星 / パルサー (Pulsar-X)
				var pulse_rot = anim_time * 5.5
				# 回転パルスビーム
				var beam_dir = Vector2(cos(pulse_rot), sin(pulse_rot))
				draw_line(ppos - beam_dir * 180.0, ppos + beam_dir * 180.0, Color(0.0, 2.5, 3.0, 0.7), 2.5)
				draw_line(ppos - beam_dir * 180.0, ppos + beam_dir * 180.0, Color(2.5, 2.5, 2.5, 0.9), 1.0)
				if tex_celestial_pulsar:
					var sz = Vector2(prad * 2.4, prad * 2.4)
					draw_set_transform(ppos, pulse_rot, Vector2.ONE)
					draw_texture_rect(tex_celestial_pulsar, Rect2(-sz * 0.5, sz), false)
					draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				draw_string(ThemeDB.fallback_font, ppos + Vector2(-36, prad + 20), "PULSAR [Neutronium]", HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color(0.2, 1.0, 0.8))

			"comet":
				# 4. 彗星 (Neowise-Omega)
				var tail_d = comet_body.get("tail_dir", Vector2(1, 0))
				# イオン＆ダストの尾
				draw_line(ppos, ppos + tail_d * 140.0, Color(0.2, 0.8, 1.0, 0.6), 8.0)
				draw_line(ppos, ppos + tail_d * 140.0, Color(1.0, 1.0, 1.0, 0.8), 2.0)
				if tex_celestial_comet:
					var rot = atan2(tail_d.y, tail_d.x) + PI
					var sz = Vector2(prad * 3.2, prad * 1.6)
					draw_set_transform(ppos, rot, Vector2.ONE)
					draw_texture_rect(tex_celestial_comet, Rect2(-sz * 0.5, sz), false)
					draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				draw_string(ThemeDB.fallback_font, ppos + Vector2(-30, prad + 18), "COMET [Ice]", HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color(0.4, 0.9, 1.0))

			"moon":
				# 5. 月 (Luna-Prime: 物理公転中)
				draw_arc(ppos, prad * 1.3, 0, TAU, 32, Color(0.2, 0.85, 1.0, 0.22), 1.2)
				if tex_moon:
					var sz = Vector2(prad * 2.0, prad * 2.0)
					draw_texture_rect(tex_moon, Rect2(ppos - sz * 0.5, sz), false)
				draw_string(ThemeDB.fallback_font, ppos + Vector2(-24, prad + 18), "LUNA [He3]", HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color(0.2, 0.8, 1.0))

			"asteroid":
				# 6. 小惑星 (Asteroid)
				if tex_celestial_asteroid:
					var sz = Vector2(prad * 2.0, prad * 2.0)
					draw_texture_rect(tex_celestial_asteroid, Rect2(ppos - sz * 0.5, sz), false)
				else:
					draw_circle(ppos, prad, Color(0.4, 0.45, 0.55))

			_:
				# その他惑星 (Aether, Vulcan, Crystal)
				draw_arc(ppos, prad * 1.35, 0, TAU, 48, Color(0.0, 0.85, 1.0, 0.18), 1.5)
				var ptex = tex_planet_blue
				if pkind == "volcanic": ptex = tex_planet_volcanic
				elif pkind == "crystal": ptex = tex_planet_crystal
				if ptex:
					var sc = (prad * 2.0) / float(ptex.get_width())
					var sz = Vector2(ptex.get_width(), ptex.get_height()) * sc
					draw_texture_rect(ptex, Rect2(ppos - sz * 0.5, sz), false)
				if pres != "":
					draw_string(ThemeDB.fallback_font, ppos + Vector2(-20, prad + 16), "[%s]" % pres, HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color(0.7, 0.9, 1.0))

# ========================================================
# 描画ループ (ブループリントホログラム ＆ 建築ドローン)
# ========================================================
func _draw() -> void:
	draw_rect(Rect2(-8000, -8000, 18000, 18000), Color(0.012, 0.016, 0.032, 1.0))
	
	# ビルドモード時のホログラフィック・グリッドリング
	if is_build_mode:
		draw_arc(HOME_CENTER, HOME_RADIUS, -PI * 0.95, -PI * 0.05, 96, Color(0.0, 1.8, 2.5, 0.25), 1.5)
		draw_arc(HOME_CENTER, HOME_RADIUS + 32.0, -PI * 0.95, -PI * 0.05, 96, Color(0.0, 1.2, 2.0, 0.15), 1.0)
		draw_arc(HOME_CENTER, HOME_RADIUS - 160.0, -PI * 0.95, -PI * 0.05, 96, Color(2.0, 0.8, 0.2, 0.15), 1.0)

	# 1. 宇宙天体・軌道・惑星物理描画 (恒星・月・彗星・ブラックホール・パルサー・小惑星帯)
	_draw_celestial_bodies()

	# 2. 母星円形断面 (半径420pxに完全一致 ＆ 美麗大気圏グロー)
	draw_arc(HOME_CENTER, HOME_RADIUS + 6.0, 0, TAU, 96, Color(0.2, 0.75, 1.0, 0.45), 3.0)
	draw_arc(HOME_CENTER, HOME_RADIUS + 16.0, 0, TAU, 80, Color(0.0, 1.5, 2.5, 0.20), 8.0)
	if tex_home_cross:
		var d_sz = Vector2(HOME_RADIUS * 2.0, HOME_RADIUS * 2.0)
		draw_texture_rect(tex_home_cross, Rect2(HOME_CENTER - d_sz * 0.5, d_sz), false)
	else:
		draw_circle(HOME_CENTER, HOME_RADIUS, Color(0.08, 0.16, 0.28))

	# 3. 地下鉱脈
	for vein in ore_veins:
		var a = -PI * 0.5 + vein["angle_off"]
		var radial = Vector2(cos(a), sin(a))
		var vpos = HOME_CENTER + radial * vein["depth_r"]
		var surf_p = HOME_CENTER + radial * (HOME_RADIUS - 12.0)
		var rot = vein["angle_off"]
		draw_line(surf_p, vpos, Color(0.35, 0.5, 0.68, 0.6), 3.0)
		var vname = vein["name"]
		if tex_ores.has(vname) and tex_ores[vname]:
			draw_sheet_frame_rotated(tex_ores[vname], 0, 1, vpos, rot)
		var res_val = GameState.vein_reserves.get(vname, 0)
		draw_string(ThemeDB.fallback_font, vpos + radial * 44.0 - Vector2(18, 0), "%s:%d" % [vname, res_val], HORIZONTAL_ALIGNMENT_CENTER, -1, 11, vein["color"])

	# 4. 配置済み実体施設
	var drill_frame = int(anim_time * 12.0) % 4
	var fact_frame = int(anim_time * 6.0) % 4
	for b in placed_buildings:
		var bpos = surface_pos_at(b["angle_off"], b.get("alt", 0.0))
		var rot = b["angle_off"]
		match b["type"]:
			"miner": draw_sheet_frame_rotated(tex_drill_sheet, drill_frame, 4, bpos, rot)
			"smelter": draw_sheet_frame_rotated(tex_factory_sheet, fact_frame, 4, bpos, rot)
			"assembler": draw_sheet_frame_rotated(tex_factory_sheet, (fact_frame + 2) % 4, 4, bpos, rot, Vector2(1.15, 1.15))
			"mass_driver": draw_sheet_frame_rotated(tex_mass_driver_sheet, int(anim_time * 4.0) % 4, 4, bpos, rot)
			"depot": draw_sheet_frame_rotated(tex_container, 0, 1, bpos, rot)
			"turret": if tex_turret: draw_texture(tex_turret, bpos - Vector2(16, 16))
			"solar": if tex_solar: draw_texture(tex_solar, bpos - Vector2(22, 12))
			"geothermal": if tex_geothermal: draw_texture(tex_geothermal, bpos - Vector2(20, 24))
			"belt":
				draw_circle(bpos, 5.0, Color(0.14, 0.22, 0.32, 1.0))
				draw_circle(bpos, 3.0, Color(0.0, 1.8, 2.5, 0.95))

	# 5. ブループリントホログラム (建設予定ゴースト) の描画
	for bp in blueprints:
		var bpos = surface_pos_at(bp["angle_off"], bp["alt"])
		var rot = bp["angle_off"]
		var prog = bp["progress"]
		var bp_col = Color(0.0, 2.2, 3.0, 0.75) if not bp["is_demolish"] else Color(2.5, 0.2, 0.2, 0.8)
		
		# ホログラム枠＆ワイヤーフレーム
		draw_set_transform(bpos, rot, Vector2.ONE)
		draw_rect(Rect2(-16, -16, 32, 32), bp_col, false, 1.5)
		draw_line(Vector2(-16, -16), Vector2(16, 16), bp_col * Color(1, 1, 1, 0.3), 1.0)
		draw_line(Vector2(-16, 16), Vector2(16, -16), bp_col * Color(1, 1, 1, 0.3), 1.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		
		# 円形プログレスアーク (0% -> 100%)
		draw_arc(bpos, 22.0, -PI * 0.5, -PI * 0.5 + TAU * prog, 24, Color(0.2, 2.8, 1.5), 2.5)

	# 6. 自律建築ドローン (Fabricator Drones) ＆ 溶接ナノビーム
	for drone in construction_drones:
		var dpos = drone["pos"]
		if tex_drone:
			draw_texture(tex_drone, dpos - Vector2(12, 12))
		else:
			draw_circle(dpos, 6.0, Color(0.2, 2.0, 2.8))
			
		# 溶接ビーム照射
		if drone["state"] == "building":
			var bp_id = drone["target_bp_id"]
			for bp in blueprints:
				if bp["id"] == bp_id:
					var target_pos = surface_pos_at(bp["angle_off"], bp["alt"])
					# HDR ナノ溶接レーザー
					draw_line(dpos, target_pos, Color(0.0, 2.5, 3.0, 0.9), 2.5)
					draw_line(dpos, target_pos, Color(3.0, 3.0, 3.0, 1.0), 1.0)
					draw_circle(target_pos, 4.0, Color(3.0, 3.0, 1.5))
					break

	# 7. 溶接火花スパーク (HDR Glow)
	for s in build_sparks:
		draw_circle(s["pos"], 2.0, Color(3.0, 2.2, 0.5))

	# 8. 実体コンベアアイテム
	for item in conveyor_items:
		var ipos = surface_pos_at(item["angle_off"], 6.0)
		draw_rect(Rect2(ipos - Vector2(3, 3), Vector2(6, 6)), item["color"])
		draw_rect(Rect2(ipos - Vector2(4, 4), Vector2(8, 8)), item["color"] * Color(1.5, 1.5, 1.5, 0.4), false, 1.0)

	# 9. タレットレーザー
	for tl in turret_lasers:
		draw_line(tl["from"], tl["to"], tl["color"], 2.5)
		draw_line(tl["from"], tl["to"], Color(2.0, 2.0, 2.0), 1.0)

	# 10. 煙
	for p in smoke_particles:
		draw_circle(p["pos"], p["radius"], Color(0.6, 0.66, 0.72, (p["life"] / p["max_life"]) * 0.45))

	# 11. メガストラクチャー
	_draw_megastructures()

	# 12. マウスカーソルのホログラム設置プレビュー
	_draw_placement_preview()

	# 13. 現在の目標地点ナビゲーション光輪 (Mission Waypoint Beacon)
	_draw_mission_waypoint_beacon()

func get_current_mission_waypoint_info() -> Dictionary:
	if GameState.quest_index >= GameState.quest_list.size():
		return {}
	var q = GameState.quest_list[GameState.quest_index]
	var wp = q.get("waypoint", "")
	var beacon_p = Vector2.ZERO
	var b_col = Color(0.0, 2.5, 3.0, 0.8)
	var name_tag = q.get("short", "OBJECTIVE")
	
	match wp:
		"vein_Fe":
			beacon_p = surface_pos_at(-0.52, 24.0)
			name_tag = "Fe VEIN"
		"surface":
			beacon_p = surface_pos_at(-0.35, 24.0)
			name_tag = "BUILD SITE"
		"LUNA-PRIME":
			beacon_p = moon_body.get("pos", Vector2.ZERO)
			b_col = Color(0.3, 2.5, 3.0, 0.9)
			name_tag = "LUNA"
		"HELIOS-PRIME":
			beacon_p = SUN_POS
			b_col = Color(1.5, 1.0, 0.2, 0.9)
			name_tag = "HELIOS"
		"GARGANTUA-ZERO":
			beacon_p = Vector2(2300.0, -350.0)
			b_col = Color(1.2, 0.4, 2.5, 0.9)
			name_tag = "SINGULARITY"
		"boss":
			beacon_p = Vector2(1380.0, 150.0)
			b_col = Color(2.5, 0.3, 0.3, 0.9)
			name_tag = "BOSS CITADEL"
			
	if beacon_p != Vector2.ZERO:
		return {"pos": beacon_p, "color": b_col, "name": name_tag}
	return {}

func _draw_mission_waypoint_beacon() -> void:
	var wp_info = get_current_mission_waypoint_info()
	if wp_info.is_empty():
		return
	var beacon_p: Vector2 = wp_info["pos"]
	var b_col: Color = wp_info["color"]
	var pulse = (sin(anim_time * 4.0) * 0.5 + 0.5)
	var rad = 28.0 + pulse * 14.0
	draw_arc(beacon_p, rad, 0, TAU, 32, b_col * Color(1, 1, 1, 0.8 - pulse * 0.4), 2.0)
	draw_line(beacon_p - Vector2(10, 0), beacon_p + Vector2(10, 0), b_col, 1.5)
	draw_line(beacon_p - Vector2(0, 10), beacon_p + Vector2(0, 10), b_col, 1.5)

func _draw_megastructures() -> void:
	var ms_elev = GameState.megastructures["elevator"]
	if ms_elev["built"] or ms_elev["progress"] > 0.0:
		var elev_pos = Vector2(800.0, 310.0)
		var ground_pos = surface_pos_at(0.0, 10.0)
		var cur_reach = ground_pos.lerp(elev_pos, ms_elev["progress"])
		draw_line(ground_pos, cur_reach, Color(0.0, 2.0, 2.8, 0.9), 3.0)
		draw_line(ground_pos, cur_reach, Color(2.5, 2.5, 2.5, 1.0), 1.0)
		if tex_ms_elevator:
			draw_texture(tex_ms_elevator, elev_pos - Vector2(48, 80), Color(1, 1, 1, 0.5 + 0.5 * ms_elev["progress"]))

	var ms_dyson = GameState.megastructures["dyson"]
	if ms_dyson["built"] or ms_dyson["progress"] > 0.0:
		var dyson_pos = Vector2(520.0, 90.0)
		if tex_ms_dyson:
			draw_texture(tex_ms_dyson, dyson_pos - Vector2(90, 55), Color(1, 1, 1, 0.5 + 0.5 * ms_dyson["progress"]))

	var ms_cit = GameState.megastructures["citadel"]
	if ms_cit["built"] or ms_cit["progress"] > 0.0:
		var cit_pos = Vector2(1060.0, 240.0)
		if tex_ms_citadel:
			draw_texture(tex_ms_citadel, cit_pos - Vector2(64, 64), Color(1, 1, 1, 0.5 + 0.5 * ms_cit["progress"]))

	var ms_wg = GameState.megastructures["warpgate"]
	if ms_wg["built"] or ms_wg["progress"] > 0.0:
		var wg_pos = Vector2(1480.0, 80.0)
		if tex_ms_warpgate:
			draw_texture(tex_ms_warpgate, wg_pos - Vector2(65, 65), Color(1, 1, 1, 0.5 + 0.5 * ms_wg["progress"]))

func _draw_placement_preview() -> void:
	if not is_build_mode or selected_tool == "none":
		return
	var mouse_pos = get_target_cursor_pos()
	var dist = mouse_pos.distance_to(HOME_CENTER)
	var ang_off = angle_off_from_pos(mouse_pos)
	
	var is_valid = false
	if selected_tool == "geothermal":
		is_valid = (dist >= 360.0 and dist <= 540.0)
	else:
		is_valid = (dist >= 500.0 and dist <= 760.0)
		
	var ghost_col = Color(0.0, 2.5, 2.8, 0.75) if is_valid else Color(2.5, 0.3, 0.3, 0.75)
	var snap_alt = 24.0 if selected_tool != "geothermal" else -160.0
	var snap_pos = surface_pos_at(ang_off, snap_alt)
	
	if selected_tool == "demolish":
		draw_circle(mouse_pos, 22.0, Color(2.0, 0.2, 0.2, 0.4))
		draw_line(mouse_pos - Vector2(14, 14), mouse_pos + Vector2(14, 14), Color(2.5, 0.2, 0.2), 3.0)
		draw_line(mouse_pos - Vector2(-14, 14), mouse_pos + Vector2(-14, 14), Color(2.5, 0.2, 0.2), 3.0)
		return
		
	draw_line(mouse_pos, snap_pos, Color(0.0, 1.8, 2.5, 0.4), 1.5)
	draw_arc(snap_pos, 20.0, 0, TAU, 16, ghost_col, 2.0)
	draw_circle(snap_pos, 5.0, ghost_col)
