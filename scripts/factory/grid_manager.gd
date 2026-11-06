extends Node2D

# STAR REPLICA: AUTOMA - ブループリント建築 ＆ 自律建築ドローン ＆ 実体物流 ＆ ケプラー公転天体物理
signal launch_probe_to_space(origin: Vector2, velocity: Vector2)
signal turret_fired(from_pos: Vector2, target_pos: Vector2)

# 1. 恒星 (太陽 Helios-Prime: 星系の不動の重力中心 ＆ 圧倒的巨大恒星)
const SUN_POS: Vector2 = Vector2(800.0, -850.0)
const SUN_RADIUS: float = 1200.0       # 太陽の圧倒的巨躯 (雄大な恒星コア)
const SUN_SURFACE_G: float = 380.0     # 恒星重力
const SUN_INFLUENCE: float = 16000.0   # 太陽系全域に及ぶ重力圏

# 2. 母星 (Origin-Prime: 太陽の周りを滑らかに公転する生命の惑星)
const HOME_RADIUS: float = 420.0       # 母星半径 (周長約2640px)
const HOME_SURFACE_G: float = 175.0
const SECTOR_SIZE: float = 4000.0

var home_orbit_radius: float = 7200.0  # 太陽から適度に離れたハビタブルゾーン (旧2400pxから3倍拡大！)
var home_orbit_angle: float = PI * 0.5
var home_orbit_speed: float = 0.006    # 公転角速度 (滑らかで壮大な公転)
var HOME_CENTER: Vector2 = SUN_POS + Vector2(cos(PI * 0.5), sin(PI * 0.5)) * 7200.0
var home_prev_pos: Vector2 = HOME_CENTER
var home_delta_pos: Vector2 = Vector2.ZERO

# 鉱脈データ (母星半径420pxに合わせた地下深度)
var ore_veins: Array[Dictionary] = [
	{"name": "Fe", "angle_off": -0.52, "depth_r": 315.0, "color": Color(0.3, 0.75, 1.0)},
	{"name": "Cu", "angle_off": -0.18, "depth_r": 285.0, "color": Color(0.95, 0.55, 0.2)},
	{"name": "Ti", "angle_off": +0.18, "depth_r": 305.0, "color": Color(0.8, 0.4, 1.0)},
	{"name": "Si", "angle_off": +0.50, "depth_r": 295.0, "color": Color(0.2, 0.95, 0.7)}
]

# 星系内各惑星の公転パラメータ (太陽系スケールへ調和配置)
var vulcan_orbit_angle: float = -PI * 0.25
var vulcan_orbit_radius: float = 3400.0 # 灼熱の内惑星
var vulcan_orbit_speed: float = 0.016

var crystal_orbit_angle: float = PI * 0.85
var crystal_orbit_radius: float = 11400.0 # 極寒の外惑星
var crystal_orbit_speed: float = 0.0035

var aether_orbit_angle: float = PI * 0.15
var aether_orbit_radius: float = 8400.0
var aether_orbit_speed: float = 0.005

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

# 建築コスト定義 (Building Resource Costs)
const BUILD_COSTS: Dictionary = {
	"miner": {"Fe": 20, "Cu": 10},
	"smelter": {"Fe": 30, "Cu": 15},
	"belt": {"Fe": 6},
	"assembler": {"Fe": 40, "Cu": 20, "Si": 10},
	"solar": {"Si": 15, "Cu": 10},
	"geothermal": {"Fe": 60, "Ti": 20},
	"turret": {"Fe": 30, "Ti": 15},
	"depot": {"Fe": 25},
	"mass_driver": {"Fe": 80, "Ti": 40, "Si": 30}
}

# 設置可能場所の青いバーチャル施設ゴースト (Available Blueprint Slots)
# [{ pos: Vector2, angle_off: float, alt: float, type: String, target_ore: String }]
var available_ghost_slots: Array[Dictionary] = []
var ghost_refresh_timer: float = 0.0

# 不足資源の地点直接赤文字ポップアップ (Floating Error Labels)
# [{ pos: Vector2, text: String, timer: float, y_offset: float }]
var floating_error_labels: Array[Dictionary] = []

# ブループリント設置時のパルス波紋演出 (Placement Shockwave Ripples)
# [{ pos: Vector2, radius: float, max_radius: float, timer: float, max_time: float, color: Color }]
var placement_ripples: Array[Dictionary] = []

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
	# 完全ゼロベース：初期状態の大地には人工物は一切存在しない。
	# プレイヤー探査機自身が手動採掘し、自己複製ドローンを産み出し、
	# ゼロから施設を建造して文明を拓く。

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
		"a": 7800.0,
		"e": 0.74,
		"tilt": 0.42,
		"theta": 0.0,
		"radius": 34.0,
		"surface_g": 38.0,
		"influence": 220.0,
		"kind": "comet",
		"pos": SUN_POS + Vector2(1800.0, 1200.0),
		"tail_dir": Vector2(0.8, 0.6).normalized(),
		"resource": "Ice"
	}
	
	# 3. 小惑星帯 (Asteroid Belt: 太陽 Helios-Prime の周りを公転)
	asteroid_belt.clear()
	for i in range(28):
		var ang = (TAU / 28.0) * float(i) + randf_range(-0.06, 0.06)
		var rad = randf_range(8800.0, 9400.0)
		var spd = randf_range(0.005, 0.008)
		var ores = ["Fe", "Si", "Ti"]
		asteroid_belt.append({
			"id": "ASTEROID-%d" % (i + 1),
			"orbit_angle": ang,
			"orbit_radius": rad,
			"orbit_speed": spd,
			"radius": randf_range(16.0, 28.0),
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
	var moon_prev = moon_body.get("pos", HOME_CENTER)
	moon_body["orbit_angle"] += moon_body["orbit_speed"] * delta
	moon_body["pos"] = HOME_CENTER + Vector2(cos(moon_body["orbit_angle"]), sin(moon_body["orbit_angle"])) * moon_body["orbit_radius"]
	var moon_delta = moon_body["pos"] - moon_prev
	
	# 2. 内惑星 Vulcan-IX の公転 (太陽周回)
	vulcan_orbit_angle += vulcan_orbit_speed * delta
	var vulcan_pos = SUN_POS + Vector2(cos(vulcan_orbit_angle), sin(vulcan_orbit_angle)) * vulcan_orbit_radius
	
	# 3. 外惑星 Crystal-IV の公転 (太陽周回)
	crystal_orbit_angle += crystal_orbit_speed * delta
	var crystal_pos = SUN_POS + Vector2(cos(crystal_orbit_angle), sin(crystal_orbit_angle)) * crystal_orbit_radius

	# 4. 彗星のケプラー運動 (Keplerian Orbit: 太陽焦点)
	var comet_prev = comet_body.get("pos", SUN_POS)
	var e = comet_body["e"]
	var a = comet_body["a"]
	var r = a * (1.0 - e * e) / (1.0 + e * cos(comet_body["theta"]))
	var ang_vel = clampf(520.0 / maxf(180.0, r), 0.06, 0.85)
	comet_body["theta"] += ang_vel * delta
	var comet_ang = comet_body["theta"] + comet_body["tilt"]
	comet_body["pos"] = comet_body["focus_pos"] + Vector2(cos(comet_ang), sin(comet_ang)) * r
	comet_body["tail_dir"] = (comet_body["pos"] - comet_body["focus_pos"]).normalized()
	var comet_delta = comet_body["pos"] - comet_prev
	
	# 5. 小惑星帯の公転 (太陽周回)
	for ast in asteroid_belt:
		ast["orbit_angle"] += ast["orbit_speed"] * delta
		ast["pos"] = SUN_POS + Vector2(cos(ast["orbit_angle"]), sin(ast["orbit_angle"])) * ast["orbit_radius"]

	# active_planets 内の天体座標および公転変位ベクトル (delta_pos) を同期
	for p in active_planets:
		var p_prev = p.get("pos", Vector2.ZERO)
		match p["id"]:
			"ORIGIN-PRIME":
				p["pos"] = HOME_CENTER
				p["delta_pos"] = home_delta_pos
			"LUNA-PRIME":
				p["pos"] = moon_body["pos"]
				p["delta_pos"] = moon_delta
			"COMET-NEOWISE":
				p["pos"] = comet_body["pos"]
				p["delta_pos"] = comet_delta
			"VULCAN-IX":
				p["delta_pos"] = vulcan_pos - p_prev
				p["pos"] = vulcan_pos
			"CRYSTAL-IV":
				p["delta_pos"] = crystal_pos - p_prev
				p["pos"] = crystal_pos

func ensure_sectors_around(world_pos: Vector2) -> void:
	var cx = int(floor(world_pos.x / SECTOR_SIZE))
	var cy = int(floor(world_pos.y / SECTOR_SIZE))
	active_planets.clear()
	
	# 1. 太陽系恒久主要天体 (Persistent Major Celestial Bodies: 座標を問わず常時アクティブ)
	var major_bodies = _get_persistent_solar_system_bodies()
	for b in major_bodies:
		active_planets.append(b)
	
	# 2. プロシージャル・ディープスペース遠方惑星セクター
	for sy in range(cy - 2, cy + 3):
		for sx in range(cx - 2, cx + 3):
			var cell = Vector2i(sx, sy)
			if cell == Vector2i(0, 0): continue # 太陽系コア領域は主要天体でカバー
			if not generated_sectors.has(cell):
				generated_sectors[cell] = _generate_sector_planets(cell)
			for p in generated_sectors[cell]:
				active_planets.append(p)

func _get_persistent_solar_system_bodies() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	# 0. 母星 Origin-Prime
	list.append({
		"id": "ORIGIN-PRIME", "name": "ORIGIN-PRIME",
		"pos": HOME_CENTER, "radius": HOME_RADIUS, "surface_g": HOME_SURFACE_G, "influence": HOME_RADIUS * 4.2,
		"kind": "home"
	})
	# 1. 恒星 (Sun / Helios-Prime: 動的プラズマ恒星)
	list.append({
		"id": "HELIOS-PRIME", "name": "HELIOS-PRIME",
		"pos": SUN_POS, "radius": SUN_RADIUS, "surface_g": SUN_SURFACE_G, "influence": SUN_INFLUENCE,
		"kind": "sun", "resource": "Plasma"
	})
	# 2. 月 (Luna-Prime: 母星周回衛星)
	list.append({
		"id": "LUNA-PRIME", "name": "LUNA-PRIME",
		"pos": moon_body.get("pos", HOME_CENTER), "radius": moon_body.get("radius", 64.0), "surface_g": moon_body.get("surface_g", 65.0), "influence": moon_body.get("influence", 280.0),
		"kind": "moon", "resource": "He3"
	})
	# 3. 彗星 (Neowise-Omega: 楕円ケプラー軌道)
	list.append({
		"id": "COMET-NEOWISE", "name": "COMET NEOWISE",
		"pos": comet_body.get("pos", SUN_POS), "radius": comet_body.get("radius", 34.0), "surface_g": comet_body.get("surface_g", 38.0), "influence": comet_body.get("influence", 220.0),
		"kind": "comet", "resource": "Ice"
	})
	# 4. ブラックホール (Gargantua-Zero: 特異点)
	list.append({
		"id": "GARGANTUA-ZERO", "name": "GARGANTUA-ZERO",
		"pos": SUN_POS + Vector2(14800.0, -7200.0), "radius": 140.0, "surface_g": 680.0, "influence": 3200.0,
		"kind": "blackhole", "resource": "DarkMatter"
	})
	# 5. 中性子星 / パルサー (Pulsar-X)
	list.append({
		"id": "PULSAR-X", "name": "PULSAR-X",
		"pos": SUN_POS + Vector2(-13600.0, -6400.0), "radius": 54.0, "surface_g": 360.0, "influence": 1600.0,
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
	var v_pos = SUN_POS + Vector2(cos(vulcan_orbit_angle), sin(vulcan_orbit_angle)) * vulcan_orbit_radius
	var c_pos = SUN_POS + Vector2(cos(crystal_orbit_angle), sin(crystal_orbit_angle)) * crystal_orbit_radius
	list.append({"id": "VULCAN-IX", "name": "VULCAN-IX", "pos": v_pos, "radius": 160.0, "surface_g": 140.0, "influence": 450.0, "kind": "volcanic", "scale": 1.0, "resource": "Cu"})
	list.append({"id": "CRYSTAL-IV", "name": "CRYSTAL-IV", "pos": c_pos, "radius": 130.0, "surface_g": 110.0, "influence": 400.0, "kind": "crystal", "scale": 1.0, "resource": "Si"})
	return list

func _generate_sector_planets(cell: Vector2i) -> Array[Dictionary]:
	var list: Array[Dictionary] = []

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
	# 1. 最も支配的な天体 (Primary Celestial Body) の選定
	var primary: Dictionary = active_planets[0] if not active_planets.is_empty() else {}
	var best_weight: float = -1.0
	
	for p in active_planets:
		var d_cand: Vector2 = pos - p["pos"]
		var r_cand: float = maxf(1.0, d_cand.length())
		var rp_cand: float = p["radius"]
		var inf_cand: float = p["influence"]
		if r_cand > inf_cand: continue
		
		var g_cand: float = p["surface_g"] * pow(rp_cand / maxf(r_cand, rp_cand), 2.0)
		# 局所重力圏（高度2倍以内）の天体を最優先
		var weight = g_cand * (4.0 if r_cand < rp_cand * 2.5 else 1.0)
		if weight > best_weight:
			best_weight = weight
			primary = p

	# 2. ヒル球（Hill Sphere / 局所重力支配圏）物理演算
	# 主星以外の天体（母星・月・他惑星）の重力圏内にいる場合、太陽の引力は公転慣性系により相殺（等価原理）
	var is_in_local_hill_sphere: bool = false
	var hill_body_pos: Vector2 = Vector2.ZERO
	if not primary.is_empty() and primary.get("kind", "") != "sun":
		var dist_to_prim = (pos - primary["pos"]).length()
		if dist_to_prim < primary["radius"] * 3.5:
			is_in_local_hill_sphere = true
			hill_body_pos = primary["pos"]

	var total_acc = Vector2.ZERO
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
		var a_vec = (-d / r) * g_mag
		
		# 局所ヒル球内での太陽重力の潮汐力補正 (吸い込みの完全根絶)
		if is_in_local_hill_sphere and p.get("kind", "") == "sun":
			# 太陽が母星中心に及ぼす加速度
			var d_sun_planet = hill_body_pos - p["pos"]
			var r_sp = maxf(1.0, d_sun_planet.length())
			var a_sun_planet = (-d_sun_planet / r_sp) * (p["surface_g"] * pow(rp / r_sp, 2.0))
			# 正味の力は潮汐力（差分）のみ
			var tidal_acc = a_vec - a_sun_planet
			total_acc += tidal_acc * 0.1 # 潮汐力のみ微弱に反映
		else:
			total_acc += a_vec
			
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
		
	var prim_delta = primary.get("delta_pos", Vector2.ZERO)
	return {
		"acc": total_acc,
		"primary": primary,
		"primary_delta_pos": prim_delta,
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
		var harvest_reach = prad + maxf(140.0, prad * 0.38) # 太陽など超巨大天体のコロナ採掘リーチ対応
		if d <= harvest_reach:
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
	if event is InputEventMouseButton or event is InputEventScreenTouch:
		last_input_was_gamepad = false
		var mouse_pos = get_global_mouse_position()
		var is_pressed = event.pressed
		var is_left_or_touch = true
		if event is InputEventMouseButton:
			is_left_or_touch = (event.button_index == MOUSE_BUTTON_LEFT)
			if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
				if selected_tool != "none":
					selected_tool = "none"
					is_build_mode = false
					is_drag_placing = false
					AudioSynth.play_synth("click")
				return
		if is_left_or_touch:
			if is_pressed:
				if selected_tool != "none":
					# 0. 未完了ブループリントのタップによる即時キャンセル＆資源全額返還
					for bp_i in range(blueprints.size() - 1, -1, -1):
						var bp = blueprints[bp_i]
						var bp_pos = surface_pos_at(bp["angle_off"], bp["alt"])
						if mouse_pos.distance_to(bp_pos) < 36.0 and not bp["is_demolish"]:
							var refund_costs = BUILD_COSTS.get(bp["type"], {})
							for r_k in refund_costs:
								GameState.add_resource(r_k, refund_costs[r_k])
							blueprints.remove_at(bp_i)
							AudioSynth.play_synth("click")
							_update_available_ghost_slots()
							GameState.add_log("BLUEPRINT CANCELLED: RESOURCES REFUNDED (100%)")
							return
							
					# 1. 設置可能場所の青いバーチャル施設ゴーストへの直接タップ判定
					if _try_build_at_ghost_slot(mouse_pos):
						return
					is_drag_placing = true
					last_placed_angle = -999.0
					_place_blueprint_at_mouse(mouse_pos)
			else:
				is_drag_placing = false
				last_placed_angle = -999.0
				
	elif (event is InputEventMouseMotion or event is InputEventScreenDrag) and is_drag_placing:
		last_input_was_gamepad = false
		# コンベア等の連続ドラッグ敷設 (スマホスワイプ・PCドラッグ両対応)
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
	var costs: Dictionary = BUILD_COSTS.get(selected_tool, {})
	var can_afford: bool = true
	var missing_items: Array[String] = []
	for r_type in costs:
		var need: int = costs[r_type]
		var have: int = GameState.resources.get(r_type, 0)
		if have < need:
			can_afford = false
			missing_items.append("%d %s (NEED %d)" % [have, r_type, need])
			
	if not can_afford:
		var err_str = "❌ " + ", ".join(missing_items)
		show_building_cost_error_at(mouse_pos, err_str)
		var hud = get_parent().get_node_or_null("HUD")
		if hud and hud.has_method("show_missing_res_alert"):
			hud.show_missing_res_alert(err_str)
		return

	# 資源消費
	for r_type in costs:
		GameState.consume_resource(r_type, costs[r_type])

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
	var b_pos = surface_pos_at(ang_off, alt)
	placement_ripples.append({
		"pos": b_pos,
		"radius": 12.0,
		"max_radius": 60.0,
		"timer": 0.35,
		"max_time": 0.35,
		"color": Color(0.0, 2.5, 3.0)
	})

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

func show_building_cost_error_at(world_pos: Vector2, missing_text: String) -> void:
	floating_error_labels.append({
		"pos": world_pos,
		"text": missing_text,
		"timer": 1.6,
		"y_offset": 0.0
	})
	AudioSynth.play_synth("error")

func _update_available_ghost_slots() -> void:
	available_ghost_slots.clear()
	var player = get_parent().get_node_or_null("Player")
	var p_pos = player.global_position if player else HOME_CENTER + Vector2(0, -HOME_RADIUS)
	var p_ang = angle_off_from_pos(p_pos)
	
	if selected_tool == "miner":
		# ドリルの場合：母星の鉱脈すべてで未設置のものをゴーストとして投影
		for v in ore_veins:
			var v_ang = v["angle_off"]
			var has_miner = false
			for b in placed_buildings:
				if b["type"] == "miner" and abs(b["angle_off"] - v_ang) < 0.025:
					has_miner = true
					break
			for bp in blueprints:
				if bp["type"] == "miner" and abs(bp["angle_off"] - v_ang) < 0.025:
					has_miner = true
					break
			if not has_miner:
				var spos = surface_pos_at(v_ang, 20.0)
				available_ghost_slots.append({
					"pos": spos,
					"angle_off": v_ang,
					"alt": 20.0,
					"type": "miner",
					"target_ore": v["name"]
				})
	elif selected_tool == "belt":
		# コンベアの場合：プレイヤー周囲の地表グリッド
		var ang_step = 0.035
		for i in range(-5, 6):
			var cand_ang = p_ang + float(i) * ang_step
			var spos = surface_pos_at(cand_ang, 4.0)
			var is_dup = false
			for bp in blueprints:
				if bp["type"] == "belt" and abs(bp["angle_off"] - cand_ang) < 0.015:
					is_dup = true
					break
			for b in placed_buildings:
				if b["type"] == "belt" and abs(b["angle_off"] - cand_ang) < 0.015:
					is_dup = true
					break
			if not is_dup:
				available_ghost_slots.append({
					"pos": spos,
					"angle_off": cand_ang,
					"alt": 4.0,
					"type": "belt",
					"target_ore": ""
				})
	else:
		# その他の建物（smelter, assembler, solar, geothermal, turret, depot, mass_driver）
		var alt = 16.0
		match selected_tool:
			"smelter": alt = 32.0
			"assembler": alt = 34.0
			"mass_driver": alt = 48.0
			"depot": alt = 26.0
			"turret": alt = 20.0
			"solar": alt = 16.0
			"geothermal": alt = -160.0
		
		var ang_step = 0.075 # 約32pxピッチ
		for i in range(-4, 5):
			var cand_ang = p_ang + float(i) * ang_step
			var spos = surface_pos_at(cand_ang, alt)
			var is_occupied = false
			for b in placed_buildings:
				if abs(b["angle_off"] - cand_ang) < 0.035:
					is_occupied = true
					break
			for bp in blueprints:
				if abs(bp["angle_off"] - cand_ang) < 0.035:
					is_occupied = true
					break
			if not is_occupied:
				available_ghost_slots.append({
					"pos": spos,
					"angle_off": cand_ang,
					"alt": alt,
					"type": selected_tool,
					"target_ore": ""
				})

func _try_build_at_ghost_slot(target_pos: Vector2) -> bool:
	if selected_tool == "none" or selected_tool == "demolish":
		return false
		
	var best_slot: Dictionary = {}
	var best_dist: float = 68.0 # モバイル・タッチ操作に最適化した寛容なタップ判定エリア
	for slot in available_ghost_slots:
		var d = target_pos.distance_to(slot["pos"])
		if d < best_dist:
			best_dist = d
			best_slot = slot
			
	if best_slot.is_empty():
		return false
		
	# コストチェック
	var costs: Dictionary = BUILD_COSTS.get(selected_tool, {})
	var can_afford: bool = true
	var missing_items: Array[String] = []
	for r_type in costs:
		var need: int = costs[r_type]
		var have: int = GameState.resources.get(r_type, 0)
		if have < need:
			can_afford = false
			missing_items.append("%d %s (NEED %d)" % [have, r_type, need])
			
	if not can_afford:
		var err_str = "❌ " + ", ".join(missing_items)
		show_building_cost_error_at(best_slot["pos"], err_str)
		var hud = get_parent().get_node_or_null("HUD")
		if hud and hud.has_method("show_missing_res_alert"):
			hud.show_missing_res_alert(err_str)
		return true
		
	# 資源消費
	for r_type in costs:
		GameState.consume_resource(r_type, costs[r_type])
		
	# ブループリント確定配置
	_add_blueprint(best_slot["type"], best_slot["angle_off"], best_slot["alt"], best_slot["target_ore"], false)
	AudioSynth.play_synth("craft")
	
	# タップ地点にSci-Fiパルス波紋ショックウェーブを発生
	placement_ripples.append({
		"pos": best_slot["pos"],
		"radius": 12.0,
		"max_radius": 65.0,
		"timer": 0.4,
		"max_time": 0.4,
		"color": Color(0.0, 2.5, 3.0)
	})
	
	# スロット更新
	_update_available_ghost_slots()
	return true

# ========================================================
# 自律建築ドローン (Fabricator Drones) のAI＆溶接シミュレーション
# ========================================================
func _process(delta: float) -> void:
	anim_time += delta
	_update_celestial_simulation(delta)
	_update_power_grid()
	
	# 不足資源赤文字エラーラベルの更新
	var keep_errs: Array[Dictionary] = []
	for err in floating_error_labels:
		err["timer"] -= delta
		err["y_offset"] += delta * 24.0
		if err["timer"] > 0.0:
			keep_errs.append(err)
	floating_error_labels = keep_errs

	# ブループリント配置パルス波紋の更新
	var keep_ripples: Array[Dictionary] = []
	for rip in placement_ripples:
		rip["timer"] -= delta
		var t_ratio = 1.0 - (rip["timer"] / rip["max_time"])
		rip["radius"] = lerpf(12.0, rip["max_radius"], t_ratio)
		if rip["timer"] > 0.0:
			keep_ripples.append(rip)
	placement_ripples = keep_ripples

	# 設置可能場所の青いバーチャル施設ゴーストの更新
	if selected_tool != "none" and selected_tool != "demolish":
		ghost_refresh_timer -= delta
		if ghost_refresh_timer <= 0.0:
			ghost_refresh_timer = 0.15
			_update_available_ghost_slots()
	else:
		available_ghost_slots.clear()
	
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
	
	# 利用可能な自律建築ドローン数 (自己複製・合体させたドローン数に完全連動！)
	# ※ 最初は何もない単機探査機のため0機！ [DRONE]で自己複製するごとに建築隊が増加する
	var target_drone_count = mini(8, GameState.attached_drones)
	while construction_drones.size() < target_drone_count:
		construction_drones.append({
			"pos": player_pos + Vector2(randf_range(-10, 10), randf_range(-10, 10)),
			"vel": Vector2.ZERO,
			"target_bp_id": -1,
			"state": "idle"
		})
	while construction_drones.size() > target_drone_count:
		construction_drones.pop_back()
		
	# ドローン未保有時：自機自身の手動ナノ溶接フェイルセーフ (初期サバイバル建造)
	if construction_drones.is_empty() and player and not blueprints.is_empty():
		for bp in blueprints:
			var bpos = surface_pos_at(bp["angle_off"], bp["alt"])
			var d_player = player_pos.distance_to(bpos)
			if d_player < 85.0:
				bp["progress"] += delta * 0.55
				if bp["progress"] >= 1.0:
					_finish_blueprint(bp)
					break
		return
		
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
						
						# 隣接コンベアベルトの接続判定
						var has_adjacent_belt = false
						for other in placed_buildings:
							if other["type"] == "belt" and abs(other["angle_off"] - b["angle_off"]) < 0.08:
								has_adjacent_belt = true
								break
								
						if has_adjacent_belt:
							# ベルトへ自動排出
							_spawn_conveyor_item(ore, b["angle_off"])
							GameState.add_resource(ore, 2)
						else:
							# ベルト未接続：内部ストレージに蓄積 (最大50個)
							b["buffer"] = mini(50, b.get("buffer", 0) + 2)
							
					var bpos = surface_pos_at(b["angle_off"], b["alt"])
					smoke_particles.append({"pos": bpos, "vel": (bpos - HOME_CENTER).normalized() * 32.0, "radius": 4.0, "life": 0.7, "max_life": 0.7})
				
				# プレイヤー接近時の手動回収フェイルセーフ
				var miner_pos = surface_pos_at(b["angle_off"], b.get("alt", 20.0))
				var player_obj = get_parent().get_node_or_null("Player")
				if player_obj and b.get("buffer", 0) > 0:
					if player_obj.global_position.distance_to(miner_pos) < 68.0:
						var take_amount = b["buffer"]
						b["buffer"] = 0
						GameState.add_resource(b.get("target_ore", "Fe"), take_amount)
						AudioSynth.play_synth("mine")
						GameState.add_log("COLLECTED: +%d %s FROM MINER BUFFER" % [take_amount, b.get("target_ore", "Fe")])
			"smelter":
				if b["timer"] >= 2.2:
					b["timer"] = 0.0
					var crafted_any = false
					if GameState.consume_resource("Fe", 2):
						GameState.add_item("plate_fe", 1)
						_spawn_conveyor_item("plate_fe", b["angle_off"])
						crafted_any = true
					if GameState.consume_resource("Cu", 2):
						GameState.add_item("wire_cu", 2)
						crafted_any = true
					if GameState.consume_resource("Si", 2):
						GameState.add_item("silicon_wafer", 1)
						crafted_any = true
					if crafted_any:
						AudioSynth.play_synth("build")
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
	var gen = 0.0
	var con = 0.0
	# 自機内蔵リアクター（最低限のサバイバル電力）
	if GameState.story_phase >= GameState.StoryPhase.MOVE:
		gen += 15.0
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
	if con <= 0.0:
		GameState.power_ratio = 1.0
	else:
		GameState.power_ratio = clampf(gen / con, 0.15, 1.0)
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

func is_daylight_at(pos: Vector2) -> bool:
	var norm = (pos - HOME_CENTER).normalized()
	var to_sun = (SUN_POS - HOME_CENTER).normalized()
	return norm.dot(to_sun) > -0.15

func _draw_celestial_bodies() -> void:
	# A. 太陽を中心とする惑星公転軌道ライン群 (Orbit Rails)
	draw_arc(SUN_POS, vulcan_orbit_radius, 0, TAU, 96, Color(1.0, 0.45, 0.2, 0.12), 1.2)
	draw_arc(SUN_POS, home_orbit_radius, 0, TAU, 160, Color(0.2, 0.85, 1.0, 0.16), 1.5)
	draw_arc(SUN_POS, 9100.0, 0, TAU, 160, Color(0.35, 0.45, 0.65, 0.12), 60.0) # 小惑星帯
	draw_arc(SUN_POS, crystal_orbit_radius, 0, TAU, 180, Color(0.2, 1.0, 0.7, 0.12), 1.2)

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
				# 1. 恒星 (Helios-Prime: 圧倒的巨躯の動的プロシージャル太陽)
				var c_pulse = (sin(anim_time * 2.2) * 0.5 + 0.5)
				var fast_pulse = (sin(anim_time * 4.5) * 0.5 + 0.5)
				
				# (1) 希薄コロナ外層＆光芒レイヤー (Solar Rays & Outer Corona)
				for ray_i in range(16):
					var ray_ang = (TAU / 16.0) * float(ray_i) + anim_time * 0.03
					var ray_len = prad * (1.35 + sin(ray_i * 1.7 + anim_time * 2.0) * 0.18 + c_pulse * 0.12)
					var ray_vec = Vector2(cos(ray_ang), sin(ray_ang))
					draw_line(ppos + ray_vec * (prad * 0.95), ppos + ray_vec * ray_len, Color(1.0, 0.45, 0.08, 0.22), 18.0)
					draw_line(ppos + ray_vec * (prad * 0.98), ppos + ray_vec * (ray_len * 0.85), Color(1.0, 0.85, 0.25, 0.35), 6.0)

				# (2) 多重コロナ脈動リング (HDR Glow Aura)
				draw_arc(ppos, prad * 1.45 + c_pulse * 35.0, 0, TAU, 64, Color(1.0, 0.2, 0.05, 0.08), 24.0)
				draw_arc(ppos, prad * 1.25 + c_pulse * 25.0, 0, TAU, 80, Color(1.0, 0.45, 0.1, 0.18), 16.0)
				draw_arc(ppos, prad * 1.10 + fast_pulse * 15.0, 0, TAU, 96, Color(1.0, 0.75, 0.2, 0.35), 10.0)

				# (3) 巨大プロミネンス（紅炎の磁場ループアーク）
				for prom_i in range(5):
					var base_a = (TAU / 5.0) * float(prom_i) + 0.35 + sin(anim_time * 0.4 + prom_i) * 0.15
					var p_spread = 0.22 + sin(anim_time * 1.8 + prom_i * 2.0) * 0.05
					var p_h = prad * (1.18 + sin(anim_time * 2.5 + prom_i * 1.5) * 0.14)
					var p_start = ppos + Vector2(cos(base_a - p_spread), sin(base_a - p_spread)) * prad
					var p_end = ppos + Vector2(cos(base_a + p_spread), sin(base_a + p_spread)) * prad
					var p_peak = ppos + Vector2(cos(base_a), sin(base_a)) * p_h
					
					# 二次ベジェ近似ラインでループ紅炎を描画
					var prev_pt = p_start
					for b_step in range(1, 9):
						var t_b = float(b_step) / 8.0
						var pt = (1.0 - t_b) * (1.0 - t_b) * p_start + 2.0 * (1.0 - t_b) * t_b * p_peak + t_b * t_b * p_end
						draw_line(prev_pt, pt, Color(1.5, 0.35, 0.05, 0.7), 4.5)
						draw_line(prev_pt, pt, Color(2.5, 1.2, 0.3, 0.85), 1.8)
						prev_pt = pt

				# (4) 太陽風パーティクル (流れる光子プラズマ流)
				for sw_i in range(14):
					var sw_seed = float(sw_i * 97)
					var sw_phase = fmod(anim_time * 0.8 + sw_seed * 0.13, 1.0)
					var sw_a = sw_seed * 0.37
					var sw_r = prad * (1.05 + sw_phase * 1.6)
					var sw_pos = ppos + Vector2(cos(sw_a), sin(sw_a)) * sw_r
					var sw_alpha = (1.0 - sw_phase) * 0.65
					draw_circle(sw_pos, 3.5 * (1.0 - sw_phase * 0.5), Color(1.2, 0.85, 0.3, sw_alpha))

				# (5) 太陽光球・核融合コア (Photosphere & Superheated Core)
				draw_circle(ppos, prad, Color(1.1, 0.55, 0.12, 1.0))
				draw_circle(ppos, prad * 0.90, Color(1.5, 0.85, 0.25, 1.0))
				draw_circle(ppos, prad * 0.70, Color(2.2, 1.6, 0.6, 1.0))
				draw_circle(ppos, prad * 0.42, Color(3.5, 3.0, 1.5, 1.0)) # 白熱する特異核

				# (6) テクスチャブレンド（対流プラズマテクスチャの回転）
				if tex_celestial_sun:
					var sz = Vector2(prad * 2.2, prad * 2.2)
					draw_set_transform(ppos, anim_time * 0.02, Vector2.ONE)
					draw_texture_rect(tex_celestial_sun, Rect2(-sz * 0.5, sz), false)
					draw_set_transform(ppos, -anim_time * 0.015 + 1.2, Vector2.ONE) # 逆回転ブレンド
					draw_texture_rect(tex_celestial_sun, Rect2(-sz * 0.45, sz * 0.9), false)
					draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

				# (7) 動的太陽黒点 (Sunspots)
				for spot_i in range(3):
					var spot_a = anim_time * 0.02 + float(spot_i) * 1.8
					var spot_r = prad * (0.35 + float(spot_i) * 0.2)
					var spot_pos = ppos + Vector2(cos(spot_a), sin(spot_a) * 0.45) * spot_r
					draw_circle(spot_pos, 18.0 + float(spot_i) * 8.0, Color(0.35, 0.12, 0.02, 0.75))
					draw_circle(spot_pos, 10.0 + float(spot_i) * 4.0, Color(0.12, 0.04, 0.01, 0.9))

				# 恒星情報ラベル
				draw_string(ThemeDB.fallback_font, ppos + Vector2(-90, prad + 50), "HELIOS-PRIME [Extreme Plasma / T: 5800K]", HORIZONTAL_ALIGNMENT_CENTER, -1, 15, Color(1.0, 0.85, 0.3))

			"blackhole":
				# 2. ブラックホール (Gargantua-Zero: 相対論的降着円盤 ＆ 事象の地平面)
				var spin = anim_time * 1.8
				
				# (1) アインシュタインリング (重力レンズ光輪)
				draw_arc(ppos, prad * 3.2, 0, TAU, 64, Color(0.85, 0.35, 1.0, 0.18), 1.5)
				draw_arc(ppos, prad * 2.4, 0, TAU, 64, Color(0.2, 1.8, 3.0, 0.28), 2.5)
				
				# (2) 超高速回転アクレッションディスク (Accretion Disk)
				for ad_i in range(8):
					var ad_r = prad * (1.15 + float(ad_i) * 0.18)
					var ad_alpha = 0.55 - float(ad_i) * 0.05
					var ad_col = Color(0.1 + float(ad_i) * 0.1, 0.8 - float(ad_i) * 0.08, 1.5, ad_alpha)
					draw_arc(ppos, ad_r, spin * 0.8 + float(ad_i) * 0.4, spin * 0.8 + float(ad_i) * 0.4 + PI * 1.4, 40, ad_col, 3.0)

				# (3) テクスチャブレンド
				if tex_celestial_blackhole:
					var sz = Vector2(prad * 2.8, prad * 2.8)
					draw_set_transform(ppos, anim_time * 0.6, Vector2.ONE)
					draw_texture_rect(tex_celestial_blackhole, Rect2(-sz * 0.5, sz), false)
					draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
					
				# (4) 完全漆黒の事象の地平面 (Event Horizon: 光すら脱出不能な絶対ブラック)
				draw_circle(ppos, prad * 0.95, Color(0.0, 0.0, 0.0, 1.0))
				draw_arc(ppos, prad * 0.96, 0, TAU, 48, Color(0.0, 2.5, 3.0, 0.8), 1.5)
				
				draw_string(ThemeDB.fallback_font, ppos + Vector2(-65, prad + 28), "GARGANTUA [DarkMatter / Singularity]", HORIZONTAL_ALIGNMENT_CENTER, -1, 11, Color(0.85, 0.45, 1.0))

			"pulsar":
				# 3. 中性子星 / パルサー (Pulsar-X: 相対論的超長距離極ジェット ＆ 放射線パルス)
				var pulse_rot = anim_time * 6.5
				var beam_dir = Vector2(cos(pulse_rot), sin(pulse_rot))
				var jet_len = 980.0
				
				# (1) 極ジェット放射ビーム (Polar Relativistic Jets: 宇宙空間を裂く双極レーザー)
				draw_line(ppos - beam_dir * jet_len, ppos + beam_dir * jet_len, Color(0.0, 2.5, 3.0, 0.45), 10.0)
				draw_line(ppos - beam_dir * jet_len, ppos + beam_dir * jet_len, Color(1.2, 2.8, 3.5, 0.85), 3.0)
				draw_line(ppos - beam_dir * (jet_len * 0.4), ppos + beam_dir * (jet_len * 0.4), Color(3.5, 3.5, 3.5, 1.0), 1.5)
				
				# (2) 磁気圏パルス衝撃波リング (Magnetic Shockwaves)
				for pw_i in range(3):
					var pw_phase = fmod(anim_time * 3.5 + float(pw_i) * 0.33, 1.0)
					var pw_rad = prad * (1.2 + pw_phase * 2.5)
					var pw_alpha = (1.0 - pw_phase) * 0.5
					draw_arc(ppos, pw_rad, 0, TAU, 32, Color(0.1, 2.2, 2.8, pw_alpha), 2.0)

				# (3) 中性子核 (Neutron Degenerate Core)
				draw_circle(ppos, prad * 1.1, Color(0.0, 1.5, 2.2, 0.5))
				draw_circle(ppos, prad * 0.75, Color(2.0, 2.8, 3.5, 1.0))
				draw_circle(ppos, prad * 0.35, Color(3.5, 3.5, 3.5, 1.0))

				if tex_celestial_pulsar:
					var sz = Vector2(prad * 2.4, prad * 2.4)
					draw_set_transform(ppos, pulse_rot, Vector2.ONE)
					draw_texture_rect(tex_celestial_pulsar, Rect2(-sz * 0.5, sz), false)
					draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				draw_string(ThemeDB.fallback_font, ppos + Vector2(-55, prad + 22), "PULSAR-X [Neutronium / Relativistic Jet]", HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color(0.2, 1.2, 1.0))

			"comet":
				# 4. 彗星 (Neowise-Omega: 太陽放射圧による真の反太陽二重尾)
				var tail_d = comet_body.get("tail_dir", Vector2(1, 0))
				var dist_sun = ppos.distance_to(SUN_POS)
				var heat_boost = clampf(9000.0 / maxf(1200.0, dist_sun), 1.0, 3.8)
				var tail_len = 160.0 * heat_boost
				
				# (1) イオンの尾 (Ion Tail: 反太陽方向へ直線的に伸びる超高温青色プラズマ)
				draw_line(ppos, ppos + tail_d * tail_len, Color(0.1, 1.8, 2.5, 0.45 * heat_boost), 12.0)
				draw_line(ppos, ppos + tail_d * tail_len, Color(1.0, 2.5, 3.0, 0.85), 3.0)
				
				# (2) ダストの尾 (Dust Tail: 軌道慣性で微小にカーブする白色ダスト流)
				var curved_d = (tail_d + Vector2(-tail_d.y, tail_d.x) * 0.18).normalized()
				draw_line(ppos, ppos + curved_d * (tail_len * 0.82), Color(1.0, 0.95, 0.7, 0.35 * heat_boost), 8.0)
				
				# (3) 彗星コマ (Coma: 昇華するシアン・エメラルドガス球)
				draw_circle(ppos, prad * 1.6, Color(0.0, 2.0, 1.8, 0.35))
				draw_circle(ppos, prad * 0.9, Color(1.5, 2.5, 2.8, 0.85))

				if tex_celestial_comet:
					var rot = atan2(tail_d.y, tail_d.x) + PI
					var sz = Vector2(prad * 3.2, prad * 1.6)
					draw_set_transform(ppos, rot, Vector2.ONE)
					draw_texture_rect(tex_celestial_comet, Rect2(-sz * 0.5, sz), false)
					draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				draw_string(ThemeDB.fallback_font, ppos + Vector2(-30, prad + 18), "COMET [Ice]", HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color(0.4, 0.9, 1.0))

			"moon":
				# 5. 月 (Luna-Prime: 物理公転中 ＆ 潮汐固定自転)
				draw_arc(ppos, prad * 1.3, 0, TAU, 32, Color(0.2, 0.85, 1.0, 0.22), 1.2)
				if tex_moon:
					var sz = Vector2(prad * 2.0, prad * 2.0)
					var moon_orbit_rot = anim_time * 0.12 # 母星に対する潮汐ロック自転
					draw_set_transform(ppos, moon_orbit_rot, Vector2.ONE)
					draw_texture_rect(tex_moon, Rect2(-sz * 0.5, sz), false)
					draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				draw_string(ThemeDB.fallback_font, ppos + Vector2(-24, prad + 18), "LUNA [He3]", HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color(0.2, 0.8, 1.0))

			"asteroid":
				# 6. 小惑星 (Asteroid: 資源種別カラーティント ＆ 自転 ＆ 結晶きらめき)
				var a_col = Color(0.4, 0.45, 0.55)
				var glint_col = Color(1.0, 1.0, 1.0)
				match pres:
					"Fe":
						a_col = Color(0.25, 0.65, 0.95)
						glint_col = Color(0.3, 0.9, 1.5)
					"Si":
						a_col = Color(0.2, 0.85, 0.6)
						glint_col = Color(0.4, 1.5, 0.9)
					"Ti":
						a_col = Color(0.75, 0.4, 0.95)
						glint_col = Color(1.2, 0.6, 1.5)
				
				# 鉱石の微弱オーラ
				draw_arc(ppos, prad * 1.25, 0, TAU, 16, a_col * Color(1, 1, 1, 0.25), 1.2)
				
				var a_rot = anim_time * 0.25 + ppos.x * 0.01 + ppos.y * 0.01
				if tex_celestial_asteroid:
					var sz = Vector2(prad * 2.0, prad * 2.0)
					draw_set_transform(ppos, a_rot, Vector2.ONE)
					draw_texture_rect(tex_celestial_asteroid, Rect2(-sz * 0.5, sz), false, a_col * 0.75 + Color(0.25, 0.25, 0.25))
					draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				else:
					draw_circle(ppos, prad, a_col)
					
				# 周期的な結晶グリント (きらめき光芒)
				var glint_phase = sin(anim_time * 4.0 + ppos.x * 0.05 + ppos.y * 0.05)
				if glint_phase > 0.65:
					var g_sz = (glint_phase - 0.65) * 18.0
					draw_line(ppos - Vector2(g_sz, 0), ppos + Vector2(g_sz, 0), glint_col, 1.2)
					draw_line(ppos - Vector2(0, g_sz), ppos + Vector2(0, g_sz), glint_col, 1.2)
					
				if pres != "":
					draw_string(ThemeDB.fallback_font, ppos + Vector2(-12, prad + 14), pres, HORIZONTAL_ALIGNMENT_CENTER, -1, 9, glint_col)

			_:
				# その他惑星 (Aether, Vulcan, Crystal: 固有自転)
				draw_arc(ppos, prad * 1.35, 0, TAU, 48, Color(0.0, 0.85, 1.0, 0.18), 1.5)
				var ptex = tex_planet_blue
				var spin_speed = 0.08
				if pkind == "volcanic": 
					ptex = tex_planet_volcanic
					spin_speed = 0.05
				elif pkind == "crystal": 
					ptex = tex_planet_crystal
					spin_speed = 0.12
				
				if ptex:
					var sc = (prad * 2.0) / float(ptex.get_width())
					var sz = Vector2(ptex.get_width(), ptex.get_height()) * sc
					var prot = anim_time * spin_speed + ppos.x * 0.005
					draw_set_transform(ppos, prot, Vector2.ONE)
					draw_texture_rect(ptex, Rect2(-sz * 0.5, sz), false)
					draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
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

	# 2. 母星円形断面 (半径420pxに完全一致 ＆ 太陽光デイ・ナイト大気圏グロー)
	var sun_to_home_dir = (SUN_POS - HOME_CENTER).normalized()
	var sun_angle = atan2(sun_to_home_dir.y, sun_to_home_dir.x)
	
	# (1) 基礎大気圏グロー
	draw_arc(HOME_CENTER, HOME_RADIUS + 6.0, 0, TAU, 96, Color(0.2, 0.75, 1.0, 0.45), 3.0)
	draw_arc(HOME_CENTER, HOME_RADIUS + 18.0, 0, TAU, 80, Color(0.0, 1.2, 2.2, 0.15), 10.0)
	
	# (2) 太陽光・昼半球大気散乱リム (Daylight Atmospheric Scatter)
	# 太陽を向いている側の半周アークに強烈な昼光グローを描画
	draw_arc(HOME_CENTER, HOME_RADIUS + 8.0, sun_angle - PI * 0.45, sun_angle + PI * 0.45, 48, Color(1.2, 1.0, 0.6, 0.65), 5.0)
	draw_arc(HOME_CENTER, HOME_RADIUS + 22.0, sun_angle - PI * 0.35, sun_angle + PI * 0.35, 40, Color(1.0, 0.8, 0.3, 0.35), 12.0)
	
	# (3) 母星本体の描画
	if tex_home_cross:
		var d_sz = Vector2(HOME_RADIUS * 2.0, HOME_RADIUS * 2.0)
		draw_texture_rect(tex_home_cross, Rect2(HOME_CENTER - d_sz * 0.5, d_sz), false)
	else:
		draw_circle(HOME_CENTER, HOME_RADIUS, Color(0.08, 0.16, 0.28))
		
	# (3.5) 地殻稜線・山脈クレーターディテール (Crust Terrain Elevation & Mineral Highlights)
	var terrain_pts: PackedVector2Array = []
	var num_terrain_steps = 128
	for t_i in range(num_terrain_steps + 1):
		var ta = (TAU / float(num_terrain_steps)) * float(t_i)
		var h_elev = sin(ta * 14.0) * 2.5 + sin(ta * 32.0) * 1.2 + sin(ta * 64.0) * 0.6
		var tr = HOME_RADIUS + h_elev
		terrain_pts.append(HOME_CENTER + Vector2(cos(ta), sin(ta)) * tr)
	draw_polyline(terrain_pts, Color(0.15, 0.55, 0.75, 0.45), 1.5)

	# (4) 夜半球の惑星シャドウ (Night Shadow Hemispheric Occlusion)
	var night_angle = sun_angle + PI
	# 反太陽側の夜半球に柔らかな漆黒の影をオーバーレイ
	var shadow_pts: PackedVector2Array = []
	shadow_pts.append(HOME_CENTER)
	for s_i in range(25):
		var s_a = night_angle - PI * 0.5 + (PI / 24.0) * float(s_i)
		shadow_pts.append(HOME_CENTER + Vector2(cos(s_a), sin(s_a)) * (HOME_RADIUS + 2.0))
	draw_colored_polygon(shadow_pts, Color(0.01, 0.02, 0.05, 0.42))

	# 3. 地下鉱脈 ＆ 地殻露頭ホログラム (Subsurface Ore Deposits & Surface Outcrops)
	for vein in ore_veins:
		var a = -PI * 0.5 + vein["angle_off"]
		var radial = Vector2(cos(a), sin(a))
		var vpos = HOME_CENTER + radial * vein["depth_r"]
		var surf_p = HOME_CENTER + radial * (HOME_RADIUS - 12.0)
		var rot = vein["angle_off"]
		var v_col: Color = vein["color"]
		var vname = vein["name"]
		
		# (1) 地殻浸透ボーリングライン
		draw_line(surf_p, vpos, v_col * Color(1, 1, 1, 0.4), 2.5)
		
		# (2) 地下鉱床コア ＆ 脈動オーラ
		var pulse = (sin(anim_time * 4.0 + float(vein["depth_r"]) * 0.05) * 0.5 + 0.5)
		draw_circle(vpos, 16.0 + pulse * 4.0, v_col * Color(1, 1, 1, 0.25))
		draw_arc(vpos, 22.0 + pulse * 6.0, 0, TAU, 24, v_col * Color(1.5, 1.5, 1.5, 0.5), 1.5)
		
		if tex_ores.has(vname) and tex_ores[vname]:
			draw_sheet_frame_rotated(tex_ores[vname], 0, 1, vpos, rot)
		var res_val = GameState.vein_reserves.get(vname, 0)
		draw_string(ThemeDB.fallback_font, vpos + radial * 44.0 - Vector2(18, 0), "%s:%d" % [vname, res_val], HORIZONTAL_ALIGNMENT_CENTER, -1, 11, v_col)
		
		# (3) 地表露頭マーカー (Surface Outcrop Marker)
		draw_circle(surf_p, 5.0, v_col)
		draw_arc(surf_p, 9.0 + pulse * 3.0, 0, TAU, 16, v_col * Color(1.5, 1.5, 1.5, 0.8), 1.5)
		draw_string(ThemeDB.fallback_font, surf_p + radial * 14.0 - Vector2(25, 0), "[ %s ]" % vname, HORIZONTAL_ALIGNMENT_CENTER, 50, 9, v_col * Color(1.5, 1.5, 1.5))
		
		# (4) 初回手動採掘ガイダンスビーコン (MOVE / MINEフェーズ時のFe鉱脈ターゲット)
		if (GameState.story_phase == GameState.StoryPhase.MOVE or GameState.story_phase == GameState.StoryPhase.MINE) and vname == "Fe":
			var guide_pulse = (sin(anim_time * 8.0) * 0.5 + 0.5)
			var beacon_surf = HOME_CENTER + radial * (HOME_RADIUS + 32.0)
			var beacon_tip = HOME_CENTER + radial * (HOME_RADIUS + 8.0)
			draw_line(beacon_surf, beacon_tip, Color(0.2, 2.5, 3.0, 0.95), 3.5)
			draw_arc(beacon_surf, 16.0 + guide_pulse * 6.0, 0, TAU, 24, Color(0.0, 2.8, 3.5, 0.85), 2.0)
			var guide_tag = "[ HOLD MINE ]" if GameState.story_phase == GameState.StoryPhase.MINE else "[ ▼ Fe ORE VEIN ]"
			draw_string(ThemeDB.fallback_font, beacon_surf + Vector2(-60, -18), guide_tag, HORIZONTAL_ALIGNMENT_CENTER, 120, 12, Color(0.2, 2.8, 3.5))

	# 4. 配置済み実体施設
	var drill_frame = int(anim_time * 12.0) % 4
	var fact_frame = int(anim_time * 6.0) % 4
	for b in placed_buildings:
		var bpos = surface_pos_at(b["angle_off"], b.get("alt", 0.0))
		var rot = b["angle_off"]
		var is_power_short = (GameState.power_generated < GameState.power_consumed)
		
		match b["type"]:
			"miner": 
				draw_sheet_frame_rotated(tex_drill_sheet, drill_frame, 4, bpos, rot)
				# 稼働ステータスLED (Cyan Neon)
				draw_circle(bpos + Vector2(0, -14), 2.2, Color(0.1, 0.95, 1.0, 0.95))
				var buf = b.get("buffer", 0)
				if buf > 0:
					draw_string(ThemeDB.fallback_font, bpos + Vector2(-22, -28), "[%s: %d]" % [b.get("target_ore", "Fe"), buf], HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color(0.2, 2.5, 1.2))
				# 排出ポート（Output Port）の動的インジケータ
				var out_tangent = Vector2(-sin(-PI * 0.5 + rot), cos(-PI * 0.5 + rot))
				var out_pos = bpos + out_tangent * 18.0
				draw_circle(out_pos, 2.2, Color(0.2, 2.2, 2.8, 0.85))
				draw_line(bpos, out_pos, Color(0.2, 2.0, 2.8, 0.4), 1.0)
				if is_power_short:
					draw_string(ThemeDB.fallback_font, bpos + Vector2(-20, -38), "⚡ LOW", HORIZONTAL_ALIGNMENT_CENTER, -1, 9, Color(1.0, 0.9, 0.2, 0.7 + 0.3 * sin(anim_time * 6.0)))
			"smelter": 
				draw_sheet_frame_rotated(tex_factory_sheet, fact_frame, 4, bpos, rot)
				# 精錬炉の赤熱サーマルパルス (Furnace Thermal Glow)
				var heat_pulse = (sin(anim_time * 8.0) * 0.5 + 0.5)
				draw_circle(bpos, 7.0 + heat_pulse * 3.0, Color(2.8, 1.2, 0.1, 0.45 + heat_pulse * 0.35))
				draw_circle(bpos, 3.5, Color(3.5, 2.5, 1.0, 0.9))
				if is_power_short:
					draw_string(ThemeDB.fallback_font, bpos + Vector2(-20, -32), "⚡ LOW", HORIZONTAL_ALIGNMENT_CENTER, -1, 9, Color(1.0, 0.9, 0.2, 0.7 + 0.3 * sin(anim_time * 6.0)))
			"assembler": 
				draw_sheet_frame_rotated(tex_factory_sheet, (fact_frame + 2) % 4, 4, bpos, rot, Vector2(1.15, 1.15))
				draw_circle(bpos + Vector2(0, -16), 2.5, Color(0.2, 1.0, 0.4, 0.95))
				if is_power_short:
					draw_string(ThemeDB.fallback_font, bpos + Vector2(-20, -32), "⚡ LOW", HORIZONTAL_ALIGNMENT_CENTER, -1, 9, Color(1.0, 0.9, 0.2, 0.7 + 0.3 * sin(anim_time * 6.0)))
			"mass_driver": 
				draw_sheet_frame_rotated(tex_mass_driver_sheet, int(anim_time * 4.0) % 4, 4, bpos, rot)
				draw_arc(bpos, 16.0, 0, TAU, 16, Color(0.2, 0.8, 1.0, 0.4 + 0.4 * sin(anim_time * 5.0)), 1.5)
			"depot": 
				draw_sheet_frame_rotated(tex_container, 0, 1, bpos, rot)
				draw_circle(bpos + Vector2(0, -12), 2.0, Color(1.0, 0.85, 0.2, 0.9))
			"turret": 
				if tex_turret: draw_texture(tex_turret, bpos - Vector2(16, 16))
				# 旋回警戒スキャンアイ (Red Sentinel Eye)
				var eye_off = Vector2(cos(anim_time * 3.5), sin(anim_time * 3.5)) * 5.0
				draw_circle(bpos + eye_off, 1.8, Color(1.0, 0.2, 0.2, 0.95))
				# 防衛ドームリング表示 (敵襲中 または タレット選択時)
				if GameState.is_raid_active or selected_tool == "turret":
					draw_arc(bpos, 650.0, 0, TAU, 40, Color(0.1, 0.8, 1.0, 0.18), 1.2)
			"solar": 
				if tex_solar: draw_texture(tex_solar, bpos - Vector2(22, 12))
				# 蓄電パネルインジケータ (昼: Cyan / 夜: Amber)
				var day_light = is_daylight_at(bpos)
				var sol_col = Color(0.1, 0.9, 1.0, 0.85) if day_light else Color(1.0, 0.6, 0.1, 0.5)
				draw_circle(bpos + Vector2(0, -10), 2.0, sol_col)
			"geothermal": 
				if tex_geothermal: draw_texture(tex_geothermal, bpos - Vector2(20, 24))
				draw_circle(bpos + Vector2(0, -20), 2.5, Color(1.0, 0.3, 0.1, 0.8 + 0.2 * sin(anim_time * 6.0)))
			"belt":
				# コンベア基盤トラック ＆ 動的シェブロンパルス (>>>)
				draw_circle(bpos, 6.0, Color(0.12, 0.18, 0.28, 1.0))
				draw_circle(bpos, 4.0, Color(0.0, 1.8, 2.5, 0.95))
				var chev_phase = fmod(anim_time * 4.0 + b["angle_off"] * 8.0, 1.0)
				var chev_tangent = Vector2(-sin(-PI * 0.5 + rot), cos(-PI * 0.5 + rot))
				var arrow_p = bpos + chev_tangent * (chev_phase * 10.0 - 5.0)
				draw_circle(arrow_p, 2.0, Color(2.5, 2.5, 3.0, 0.9))

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
		
		# パーセンテージ表示 & キャンセル案内 (Progress & Refund Indicator)
		var pct_txt = "%s %d%%" % [bp["type"].to_upper(), int(prog * 100.0)]
		draw_string(ThemeDB.fallback_font, bpos + Vector2(-35, -26), pct_txt, HORIZONTAL_ALIGNMENT_CENTER, 70, 9, Color(0.2, 2.8, 1.8))
		if prog < 0.35 and bp["type"] != "belt":
			draw_string(ThemeDB.fallback_font, bpos + Vector2(-45, 28), "[ RE-TAP: REFUND ]", HORIZONTAL_ALIGNMENT_CENTER, 90, 8, Color(0.6, 0.8, 0.9, 0.75))

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

	# 8. 実体コンベアアイテム (HDR Glow物流パルス)
	for item in conveyor_items:
		var ipos = surface_pos_at(item["angle_off"], 6.0)
		var icol: Color = item["color"]
		# 外側発光オーラ (遠目からでも鮮明に物流の流れが見える)
		draw_circle(ipos, 6.0, icol * Color(1.0, 1.0, 1.0, 0.35))
		draw_rect(Rect2(ipos - Vector2(3.5, 3.5), Vector2(7, 7)), icol * Color(1.5, 1.5, 1.5))
		draw_rect(Rect2(ipos - Vector2(1.5, 1.5), Vector2(3, 3)), Color(2.5, 2.5, 2.5, 0.9))

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

	# 12.5 設置可能場所の青いバーチャル施設ゴースト ＆ 不足資源赤文字エラー警告 ＆ 設置確定パルス波紋
	_draw_available_ghost_slots()
	_draw_floating_error_labels()
	_draw_placement_ripples()

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
			beacon_p = SUN_POS + Vector2(14800.0, -7200.0)
			b_col = Color(1.2, 0.4, 2.5, 0.9)
			name_tag = "SINGULARITY"
		"boss":
			beacon_p = SUN_POS + Vector2(7600.0, -1200.0)
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
	# 5. メガストラクチャー (動的公転座標系完全追従 ＆ ホログラム建設進捗)
	var ms_elev = GameState.megastructures["elevator"]
	if ms_elev["built"] or ms_elev["progress"] > 0.0:
		var ground_pos = surface_pos_at(0.0, 10.0)
		var elev_pos = surface_pos_at(0.0, 360.0) # 母星真上360pxの静止軌道ターミナル
		var cur_reach = ground_pos.lerp(elev_pos, ms_elev["progress"])
		draw_line(ground_pos, cur_reach, Color(0.0, 2.0, 2.8, 0.9), 3.0)
		draw_line(ground_pos, cur_reach, Color(2.5, 2.5, 2.5, 1.0), 1.0)
		if tex_ms_elevator:
			draw_texture(tex_ms_elevator, cur_reach - Vector2(48, 80), Color(1, 1, 1, 0.5 + 0.5 * ms_elev["progress"]))
		if not ms_elev["built"]:
			# 建設中ホログラムフレーム＆進捗
			draw_line(cur_reach, elev_pos, Color(0.1, 0.6, 0.9, 0.35), 1.5)
			draw_string(ThemeDB.fallback_font, cur_reach + Vector2(25, -10), "ELEVATOR: %d%%" % int(ms_elev["progress"] * 100.0), HORIZONTAL_ALIGNMENT_LEFT, 120, 10, Color(0.2, 1.0, 0.9))

	var ms_dyson = GameState.megastructures["dyson"]
	if ms_dyson["built"] or ms_dyson["progress"] > 0.0:
		var dyson_pos = SUN_POS + Vector2(0, -SUN_RADIUS - 200.0)
		var ring_span = PI * 0.4 * (ms_dyson["progress"] if not ms_dyson["built"] else 1.0)
		draw_arc(SUN_POS, SUN_RADIUS + 200.0, -ring_span, ring_span, 64, Color(0.2, 1.2, 2.5, 0.7 * ms_dyson["progress"]), 4.0)
		if tex_ms_dyson:
			draw_texture(tex_ms_dyson, dyson_pos - Vector2(90, 55), Color(1, 1, 1, 0.5 + 0.5 * ms_dyson["progress"]))
		if not ms_dyson["built"]:
			draw_string(ThemeDB.fallback_font, dyson_pos + Vector2(-50, -25), "DYSON RING: %d%%" % int(ms_dyson["progress"] * 100.0), HORIZONTAL_ALIGNMENT_CENTER, 100, 10, Color(1.0, 0.9, 0.3))

	var ms_cit = GameState.megastructures["citadel"]
	if ms_cit["built"] or ms_cit["progress"] > 0.0:
		var cit_pos = surface_pos_at(PI * 0.35, 480.0)
		if tex_ms_citadel:
			draw_texture(tex_ms_citadel, cit_pos - Vector2(64, 64), Color(1, 1, 1, 0.5 + 0.5 * ms_cit["progress"]))
		if not ms_cit["built"]:
			draw_arc(cit_pos, 75.0, 0, TAU, 24, Color(0.3, 0.8, 1.0, 0.4 * (0.6 + 0.4 * sin(anim_time * 4.0))), 1.5)
			draw_string(ThemeDB.fallback_font, cit_pos + Vector2(-50, -45), "CITADEL: %d%%" % int(ms_cit["progress"] * 100.0), HORIZONTAL_ALIGNMENT_CENTER, 100, 10, Color(0.4, 0.9, 1.0))

	var ms_wg = GameState.megastructures["warpgate"]
	if ms_wg["built"] or ms_wg["progress"] > 0.0:
		var wg_pos = SUN_POS + Vector2(9800.0, 3200.0)
		if tex_ms_warpgate:
			draw_texture(tex_ms_warpgate, wg_pos - Vector2(65, 65), Color(1, 1, 1, 0.5 + 0.5 * ms_wg["progress"]))
		if not ms_wg["built"]:
			draw_string(ThemeDB.fallback_font, wg_pos + Vector2(-60, -50), "ACCELERATOR: %d%%" % int(ms_wg["progress"] * 100.0), HORIZONTAL_ALIGNMENT_CENTER, 120, 10, Color(1.0, 0.4, 0.4))

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
	if selected_tool == "turret":
		draw_arc(snap_pos, 650.0, 0, TAU, 48, Color(0.1, 0.8, 1.0, 0.25), 1.5)
		draw_arc(snap_pos, 650.0, anim_time * 2.0, anim_time * 2.0 + PI * 0.5, 24, Color(0.2, 1.0, 0.5, 0.5), 2.0)

func _draw_available_ghost_slots() -> void:
	if selected_tool == "none" or selected_tool == "demolish":
		return
	var mpos = get_target_cursor_pos()
	for slot in available_ghost_slots:
		var spos = slot["pos"]
		var rot = slot["angle_off"]
		var is_hover = (mpos.distance_to(spos) < 44.0)
		var pulse = (sin(anim_time * 5.0 + slot["angle_off"] * 4.0) * 0.5 + 0.5)
		var g_col = Color(0.1, 1.8, 2.5, 0.85) if is_hover else Color(0.0, 1.4, 2.2, 0.35 + pulse * 0.25)
		
		# 1. 青いバーチャルリング＆回転スキャン枠
		draw_set_transform(spos, rot, Vector2.ONE)
		draw_rect(Rect2(-16, -16, 32, 32), g_col, false, 1.5 if is_hover else 1.0)
		draw_line(Vector2(-16, -16), Vector2(16, 16), g_col * Color(1, 1, 1, 0.25), 1.0)
		draw_line(Vector2(-16, 16), Vector2(16, -16), g_col * Color(1, 1, 1, 0.25), 1.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		
		# 2. 円形脈動リング (青いバーチャル施設)
		draw_arc(spos, 22.0, 0, TAU, 24, g_col * Color(1, 1, 1, 0.6), 1.2)
		if is_hover:
			draw_arc(spos, 26.0, anim_time * 3.0, anim_time * 3.0 + PI * 1.5, 24, Color(2.5, 2.5, 3.0, 0.9), 2.0)
			
		# 3. 頭上のタップ案内
		var label_text = "[ TAP TO BUILD ]" if is_hover else "[ + ]"
		var label_col = Color(2.5, 2.5, 3.0, 0.95) if is_hover else g_col
		draw_string(ThemeDB.fallback_font, spos + Vector2(-35, -28), label_text, HORIZONTAL_ALIGNMENT_CENTER, 70, 9, label_col)

func _draw_floating_error_labels() -> void:
	for err in floating_error_labels:
		var epos = err["pos"] + Vector2(0, -err["y_offset"])
		var e_alpha = clampf(err["timer"] / 0.4, 0.0, 1.0)
		var e_col = Color(2.5, 0.3, 0.3, e_alpha)
		var text = err["text"]
		# 背景の暗赤色警告プレート（太めの境界線）
		draw_rect(Rect2(epos.x - 90, epos.y - 14, 180, 22), Color(0.18, 0.02, 0.02, 0.88 * e_alpha))
		draw_rect(Rect2(epos.x - 90, epos.y - 14, 180, 22), Color(2.2, 0.2, 0.2, 0.85 * e_alpha), false, 1.5)
		draw_string(ThemeDB.fallback_font, Vector2(epos.x - 86, epos.y + 2), text, HORIZONTAL_ALIGNMENT_CENTER, 172, 11, e_col)

func _draw_placement_ripples() -> void:
	for rip in placement_ripples:
		var rpos = rip["pos"]
		var rad = rip["radius"]
		var alpha = clampf(rip["timer"] / rip["max_time"], 0.0, 1.0)
		var c_ring1 = Color(0.0, 2.5, 3.0, alpha * 0.95)
		var c_ring2 = Color(1.0, 2.5, 3.0, alpha * 0.6)
		# 外側に広がる二重Sci-Fiパルスリング
		draw_arc(rpos, rad, 0, TAU, 32, c_ring1, 2.5)
		if rad > 16.0:
			draw_arc(rpos, rad * 0.65, 0, TAU, 24, c_ring2, 1.5)
		# 中心パルス閃光
		if rip["timer"] > rip["max_time"] * 0.6:
			var flash_a = (rip["timer"] - rip["max_time"] * 0.6) / (rip["max_time"] * 0.4)
			draw_circle(rpos, 10.0 * flash_a, Color(1.0, 2.8, 3.0, flash_a * 0.8))
