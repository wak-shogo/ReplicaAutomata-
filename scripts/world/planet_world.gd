extends Node2D
class_name PlanetWorld

# Full 360-degree Spherical Open-World Planet (R_SURFACE = 6400px, 10x scale),
# organic subterranean caverns with HD-2D textured regolith/basalt/magma strata,
# glowing crystal veins, multi-body Newtonian gravity, orbiting moons & asteroid belt.

const SECTORS: int = 360
const LAYERS: int = 40
const R_CORE: float = 1600.0
const R_SURFACE: float = 6400.0
const R_ATMOS: float = 9600.0
const LAYER_THICK: float = (R_SURFACE - R_CORE) / float(LAYERS) # 120.0px
const DA: float = TAU / float(SECTORS)
const SPAWN_SECTOR: int = 270 # North Pole (-PI/2)

# Origin-Prime gravity constant: G_M / R_SURFACE^2 = 220 px/s^2 (~1.00 G at surface)
const GRAV_SURF: float = 220.0
const ORIGIN_GM: float = GRAV_SURF * R_SURFACE * R_SURFACE

# Terrain flat arrays [layer * SECTORS + sector]
var cell_hp: PackedFloat32Array
var cell_max_hp: PackedFloat32Array
var cell_ore: PackedStringArray
var cell_cavern: PackedByteArray # 1 if originally hollow cave or mined -> draws cave backwall

# Sun / day-night cycle
var sun_angle: float = -PI * 0.42 # Starts in bright late-morning sun over North Pole!
var anim_time: float = 0.0

# Orbiting Moons & Natural Asteroid Belt
var factory: Node2D = null
var moons: Array[Dictionary] = []
var asteroids: Array[Dictionary] = []

# Lightweight world VFX (sparks, smoke, popups)
var sparks: Array[Dictionary] = []
var smokes: Array[Dictionary] = []
var popups: Array[Dictionary] = []

func _ready() -> void:
	z_index = 0
	generate_world()

func generate_world() -> void:
	var total := SECTORS * LAYERS
	cell_hp.resize(total)
	cell_max_hp.resize(total)
	cell_ore.resize(total)
	cell_cavern.resize(total)
	sparks.clear()
	smokes.clear()
	popups.clear()

	var rng := RandomNumberGenerator.new()
	rng.seed = 4202611

	for l in range(LAYERS):
		var depth_f := float(LAYERS - 1 - l) / float(LAYERS)
		var base_hp := 10.0 + depth_f * 26.0
		for s in range(SECTORS):
			var idx := l * SECTORS + s
			var ang := float(s) * DA
			# Natural organic caverns between layer 4 and layer 34 (leaving solid surface crust 35..39)
			var cave_n := (
				sin(ang * 14.0 + float(l) * 0.42) * 0.45
				+ cos(ang * 29.0 - float(l) * 0.65) * 0.35
				+ sin(ang * 7.0 + float(l) * 0.25) * 0.20
			)
			var is_cave := (l >= 4 and l <= 34 and cave_n > 0.46)
			if is_cave:
				cell_hp[idx] = 0.0
				cell_max_hp[idx] = base_hp
				cell_ore[idx] = ""
				cell_cavern[idx] = 1
			else:
				cell_hp[idx] = base_hp
				cell_max_hp[idx] = base_hp
				cell_ore[idx] = ""
				cell_cavern[idx] = 0

	# Keep North Pole landing crust (top 2 regolith layers) solid for clean factory building,
	# while carving dramatic visible starter caverns right below (layers 35..37) like concept art!
	for ds in range(-18, 19):
		var ws := wrap_sector(SPAWN_SECTOR + ds)
		for l in range(LAYERS - 2, LAYERS):
			var idx := l * SECTORS + ws
			cell_hp[idx] = 10.0
			cell_max_hp[idx] = 10.0
			cell_cavern[idx] = 0
	for ds in [-5, -4, -3, 2, 3, 4]:
		var ws := wrap_sector(SPAWN_SECTOR + int(ds))
		for l in [36, 37]:
			var idx: int = int(l) * SECTORS + ws
			cell_hp[idx] = 0.0
			cell_ore[idx] = ""
			cell_cavern[idx] = 1

	# Natural global surface crust Fe/Cu outcrops around the entire 360-degree planet
	for s in range(SECTORS):
		if s == SPAWN_SECTOR:
			continue
		var wave := sin(float(s) * 0.42) + cos(float(s) * 0.91) * 0.6
		if wave > 0.15:
			var top_i := (LAYERS - 1) * SECTORS + s
			cell_ore[top_i] = "cu" if (int(floor(float(s) * 0.5)) % 2 == 0) else "fe"
			cell_hp[top_i] = 7.0
			cell_max_hp[top_i] = 7.0

	# Guaranteed rich starter Fe & Cu crust veins symmetrically around North Pole
	for ds in [-13, -12, -10, -9, -8, -5, -4, -2, 2, 3, 5, 6, 8, 9, 11, 12, 13]:
		var ws := wrap_sector(SPAWN_SECTOR + int(ds))
		var top_idx: int = (LAYERS - 1) * SECTORS + ws
		cell_ore[top_idx] = "cu" if (ds in [-10, -9, -5, -4, 3, 5, 6, 11, 12]) else "fe"
		cell_hp[top_idx] = 7.0
		cell_max_hp[top_idx] = 7.0

	# Glowing cyan Si quartz & crimson Fe crystal pockets bordering the starter caverns!
	_paint_vein(rng, SPAWN_SECTOR - 2, 37, "si", 1, 1, 9.0)
	_paint_vein(rng, SPAWN_SECTOR + 5, 37, "si", 1, 1, 9.0)
	_paint_vein(rng, SPAWN_SECTOR - 7, 36, "fe", 2, 1, 8.0)
	_paint_vein(rng, SPAWN_SECTOR + 1, 36, "cu", 1, 1, 8.0)
	_paint_vein(rng, SPAWN_SECTOR, 34, "si", 2, 1, 10.0)
	_paint_vein(rng, SPAWN_SECTOR, 24, "ti", 3, 2, 15.0)

	# Distributed planetary ore veins across all 360 degrees
	for _i in range(110):
		_paint_vein(rng, rng.randi_range(0, SECTORS - 1), rng.randi_range(24, LAYERS - 2), "fe", 2, 2, 10.0)
	for _i in range(88):
		_paint_vein(rng, rng.randi_range(0, SECTORS - 1), rng.randi_range(18, LAYERS - 2), "cu", 2, 2, 10.0)
	for _i in range(72):
		_paint_vein(rng, rng.randi_range(0, SECTORS - 1), rng.randi_range(8, 34), "si", 2, 2, 12.0)
	for _i in range(52):
		_paint_vein(rng, rng.randi_range(0, SECTORS - 1), rng.randi_range(2, 24), "ti", 2, 2, 16.0)

	# 3 Natural Orbiting Moons (real multi-body gravity wells!)
	moons = [
		{
			"name": "LUNA-PRIME", "tex": "luna", "ore": "ti",
			"orbit_r": 16800.0, "ang": -PI * 0.68, "ang_spd": 0.0085,
			"radius": 620.0, "gm": 95.0 * 620.0 * 620.0,
			"pos": Vector2.ZERO,
		},
		{
			"name": "IGNIS-IX", "tex": "ignis", "ore": "fe",
			"orbit_r": 21200.0, "ang": -PI * 0.28, "ang_spd": -0.0062,
			"radius": 540.0, "gm": 80.0 * 540.0 * 540.0,
			"pos": Vector2.ZERO,
		},
		{
			"name": "CRYO-IV", "tex": "cryo", "ore": "ice",
			"orbit_r": 24800.0, "ang": PI * 0.45, "ang_spd": 0.0048,
			"radius": 580.0, "gm": 85.0 * 580.0 * 580.0,
			"pos": Vector2.ZERO,
		},
	]
	_update_moons(0.0)

	# Natural Orbital Asteroid Belt outside atmosphere (dense near-orbit ring + outer belt)
	asteroids.clear()
	var cycle: Array[String] = ["si", "cu", "fe", "ti"]
	for i in range(160):
		var ang := (-PI * 0.5 + float(i - 6) * 0.035) if i < 14 else (
			(-PI * 0.5 + float(i - 26) * 0.072 + rng.randf_range(-0.02, 0.02)) if i < 46 else rng.randf_range(0.0, TAU)
		)
		var dist := rng.randf_range(R_ATMOS + 350.0, R_ATMOS + 1100.0) if i < 14 else (
			rng.randf_range(R_ATMOS + 450.0, R_ATMOS + 2400.0) if i < 46 else rng.randf_range(R_ATMOS + 900.0, 26000.0)
		)
		var ot: String = cycle[i % cycle.size()]
		asteroids.append({
			"pos": Vector2(cos(ang), sin(ang)) * dist,
			"ore": ot,
			"hp": 80.0,
			"max_hp": 80.0,
			"radius": rng.randf_range(40.0, 68.0),
			"ang": ang,
			"dist": dist,
			"orbit_spd": rng.randf_range(0.0022, 0.0052) * (1.0 if i % 2 == 0 else -1.0),
			"rot": rng.randf_range(0.0, TAU),
		})
	queue_redraw()

func _paint_vein(rng: RandomNumberGenerator, sc: int, lc: int, ore: String, rs: int, rl: int, hp_v: float) -> void:
	for dl in range(-rl, rl + 1):
		var l := lc + dl
		if l < 1 or l >= LAYERS:
			continue
		for ds in range(-rs, rs + 1):
			if absf(float(ds)) / maxf(1.0, float(rs)) + absf(float(dl)) / maxf(1.0, float(rl)) > 1.45:
				continue
			var ws := wrap_sector(sc + ds)
			var idx := l * SECTORS + ws
			if cell_hp[idx] > 0.0:
				cell_ore[idx] = ore
				cell_hp[idx] = minf(cell_hp[idx], hp_v)
				cell_max_hp[idx] = minf(cell_max_hp[idx], hp_v)

func _update_moons(delta: float) -> void:
	for m in moons:
		m["ang"] = float(m["ang"]) + float(m["ang_spd"]) * delta
		var a := float(m["ang"])
		var r := float(m["orbit_r"])
		m["pos"] = Vector2(cos(a), sin(a)) * r

func _process(delta: float) -> void:
	anim_time += delta
	sun_angle = wrapf(sun_angle + 0.0016 * delta, -PI, PI)
	_update_moons(delta)

	for ast in asteroids:
		ast["ang"] = float(ast["ang"]) + float(ast["orbit_spd"]) * delta
		ast["rot"] = float(ast["rot"]) + 0.18 * delta
		var a := float(ast["ang"])
		ast["pos"] = Vector2(cos(a), sin(a)) * float(ast["dist"])

	for i in range(sparks.size() - 1, -1, -1):
		var sp := sparks[i]
		sp["pos"] += sp["vel"] * delta
		sp["vel"] += compute_gravity_at(sp["pos"]) * delta * 0.25
		sp["life"] -= delta
		if sp["life"] <= 0.0:
			sparks.remove_at(i)

	for i in range(smokes.size() - 1, -1, -1):
		var sm := smokes[i]
		sm["pos"] += sm["vel"] * delta
		sm["rad"] += 14.0 * delta
		sm["life"] -= delta
		if sm["life"] <= 0.0:
			smokes.remove_at(i)

	for i in range(popups.size() - 1, -1, -1):
		var pp := popups[i]
		pp["pos"] += pp["vel"] * delta
		pp["life"] -= delta
		if pp["life"] <= 0.0:
			popups.remove_at(i)

	queue_redraw()

# ------------------------------------------------------------------------------
# POLAR / SPHERICAL COORDINATE UTILITIES
# ------------------------------------------------------------------------------
static func wrap_sector(s: int) -> int:
	return ((s % SECTORS) + SECTORS) % SECTORS

static func sector_center_angle(s: int) -> float:
	return (float(wrap_sector(s)) + 0.5) * DA

static func layer_inner_r(l: int) -> float:
	return R_CORE + float(l) * LAYER_THICK

static func layer_outer_r(l: int) -> float:
	return R_CORE + float(l + 1) * LAYER_THICK

func polar_to_world(ang: float, r: float) -> Vector2:
	return Vector2(cos(ang) * r, sin(ang) * r)

func world_to_polar(pos: Vector2) -> Vector2:
	var a := atan2(pos.y, pos.x)
	if a < 0.0:
		a += TAU
	return Vector2(a, pos.length())

func world_to_cell(pos: Vector2) -> Vector2i:
	var p := world_to_polar(pos)
	var s := wrap_sector(int(floor(p.x / DA)))
	var l := int(floor((p.y - R_CORE) / LAYER_THICK))
	return Vector2i(s, l)

func cell_center(s: int, l: int) -> Vector2:
	var a := sector_center_angle(s)
	var r := R_CORE + (float(l) + 0.5) * LAYER_THICK
	return polar_to_world(a, r)

func is_cell_solid(s: int, l: int) -> bool:
	if l < 0:
		return true # Molten core solid boundary
	if l >= LAYERS:
		return false
	return cell_hp[l * SECTORS + wrap_sector(s)] > 0.0

func get_ore(s: int, l: int) -> String:
	if l < 0 or l >= LAYERS:
		return ""
	return cell_ore[l * SECTORS + wrap_sector(s)]

func get_surface_layer(s: int) -> int:
	var ws := wrap_sector(s)
	for l in range(LAYERS - 1, -1, -1):
		if cell_hp[l * SECTORS + ws] > 0.0:
			return l
	return 0

func get_surface_pose(s: int, l_override: int = -1, y_offset: float = 0.0) -> Dictionary:
	var ws := wrap_sector(s)
	var top_l := l_override if l_override >= 0 else (get_surface_layer(ws) + 1)
	var a := sector_center_angle(ws)
	var r := layer_inner_r(top_l) + y_offset
	var normal := Vector2(cos(a), sin(a))
	return {
		"sec": ws,
		"layer": top_l,
		"ang": a,
		"r": r,
		"pos": normal * r,
		"normal": normal,
		"rot": a + PI * 0.5,
	}

# ------------------------------------------------------------------------------
# MULTI-BODY GRAVITY, ATMOSPHERE & SUNLIGHT PHYSICS
# ------------------------------------------------------------------------------
func compute_gravity_at(pos: Vector2) -> Vector2:
	var r := pos.length()
	var acc := Vector2.ZERO
	if r > 60.0:
		# Real Newton's Shell Theorem: linear decrease inside solid planet, inverse-square outside!
		var g_mag := (GRAV_SURF * (r / R_SURFACE)) if r < R_SURFACE else (ORIGIN_GM / (r * r))
		if r > 28000.0:
			g_mag *= clampf(1.0 - (r - 28000.0) / 8000.0, 0.0, 1.0)
		acc += (-pos / r) * g_mag
	for m in moons:
		var dvec: Vector2 = m["pos"] - pos
		var d := dvec.length()
		var mr := float(m["radius"])
		if d > mr * 0.8 and d < mr * 9.0:
			acc += (dvec / d) * (float(m["gm"]) / (d * d))
	return acc

func get_atmos_density(pos: Vector2) -> float:
	var r := pos.length()
	if r >= R_ATMOS:
		return 0.0 # Strictly zero drag in vacuum space!
	var alt := maxf(0.0, r - R_SURFACE)
	return clampf(1.0 - alt / (R_ATMOS - R_SURFACE), 0.0, 1.0)

func get_sunlight_at(pos: Vector2) -> float:
	var sun_dir := Vector2(cos(sun_angle), sin(sun_angle))
	var up := pos.normalized() if pos.length() > 1.0 else Vector2.UP
	var d := up.dot(sun_dir)
	return clampf((d + 0.18) / 0.88, 0.0, 1.0)

func check_moon_collision(pos: Vector2, ship_r: float = 20.0) -> Dictionary:
	for m in moons:
		var mp: Vector2 = m["pos"]
		var mr := float(m["radius"]) + ship_r
		var diff := pos - mp
		var d := diff.length()
		if d < mr and d > 0.1:
			return {"hit": true, "normal": diff / d, "push_pos": mp + (diff / d) * mr, "moon": m}
	return {"hit": false}

# ------------------------------------------------------------------------------
# MINING (TERRAIN + ASTEROIDS + MOONS)
# ------------------------------------------------------------------------------
func find_nearest_mine_target(pos: Vector2, aim_dir: Vector2, max_range: float = 240.0, prefer_sideways: bool = true) -> Dictionary:
	var r := pos.length()
	# 1. Space asteroids & moons
	if r > R_SURFACE + 300.0:
		var best_a := -1
		var best_d := max_range + 160.0
		for i in range(asteroids.size()):
			var d := pos.distance_to(asteroids[i]["pos"]) - float(asteroids[i]["radius"])
			if d < best_d:
				best_d = d
				best_a = i
		if best_a >= 0:
			return {"kind": "asteroid", "idx": best_a, "pos": asteroids[best_a]["pos"], "ore": asteroids[best_a]["ore"]}
		for i in range(moons.size()):
			var d := pos.distance_to(moons[i]["pos"]) - float(moons[i]["radius"])
			if d < max_range + 140.0:
				var mp: Vector2 = moons[i]["pos"]
				var hit_p := mp + (pos - mp).normalized() * float(moons[i]["radius"])
				return {"kind": "moon", "idx": i, "pos": hit_p, "ore": moons[i]["ore"]}
		return {}

	# 2. Planetary crust & cavern blocks
	var pc := world_to_cell(pos)
	var up := pos.normalized()
	var near_surf_band := (r >= R_SURFACE - 150.0)
	var best_score := 1e9
	var best_cell := Vector2i(-1, -1)
	var best_pos := Vector2.ZERO

	for dl in range(-3, 3):
		var l := pc.y + dl
		if l < 1 or l >= LAYERS:
			continue
		# Surface strip-mining guard: never punch down into subterranean caverns unless player aims downward!
		if prefer_sideways and near_surf_band and l < LAYERS - 1:
			continue
		for ds in range(-3, 4):
			var ws := wrap_sector(pc.x + ds)
			if not is_cell_solid(ws, l):
				continue
			# Never mine foundation block directly supporting a built factory structure!
			if factory != null and factory.is_occupied(ws, l + 1):
				continue
			var cp := cell_center(ws, l)
			var to_c := cp - pos
			var d := to_c.length()
			if d > max_range or d < 1.0:
				continue
			var dir_c := to_c / d
			var down_dot := dir_c.dot(up)
			# Prevent digging straight down underfoot when walking on surface crust
			if prefer_sideways and near_surf_band and down_dot < -0.68:
				continue
			var score := d
			var ore := get_ore(ws, l)
			if ore != "":
				score -= 48.0
			if aim_dir.length() > 0.2:
				score -= dir_c.dot(aim_dir.normalized()) * 65.0
			if prefer_sideways and down_dot < -0.45:
				score += 140.0
			if score < best_score:
				best_score = score
				best_cell = Vector2i(ws, l)
				best_pos = cp

	if best_cell.x >= 0:
		return {"kind": "cell", "sec": best_cell.x, "layer": best_cell.y, "pos": best_pos, "ore": get_ore(best_cell.x, best_cell.y)}
	return {}

func damage_mine_target(tgt: Dictionary, dmg: float) -> bool:
	if tgt.is_empty():
		return false
	var kind := String(tgt["kind"])
	if kind == "cell":
		var s := int(tgt["sec"])
		var l := int(tgt["layer"])
		var idx := l * SECTORS + wrap_sector(s)
		if cell_hp[idx] <= 0.0:
			return false
		cell_hp[idx] -= dmg
		if randf() < 0.35:
			spawn_spark_burst(tgt["pos"], _ore_color(String(tgt["ore"])), 3)
		if cell_hp[idx] <= 0.0:
			cell_hp[idx] = 0.0
			cell_cavern[idx] = 1
			var ore := cell_ore[idx]
			cell_ore[idx] = ""
			var give := 6 if ore != "" else 2
			var res_id := ore if ore != "" else "fe"
			GameState.add_res(res_id, give)
			AudioSynth.play_sfx("mine")
			spawn_spark_burst(tgt["pos"], _ore_color(res_id), 9)
			spawn_popup(tgt["pos"], "+%d %s" % [give, res_id.to_upper()], _ore_color(res_id))
			return true
		return false
	elif kind == "asteroid":
		var i := int(tgt["idx"])
		if i < 0 or i >= asteroids.size():
			return false
		var ast := asteroids[i]
		ast["hp"] = float(ast["hp"]) - dmg
		if randf() < 0.35:
			spawn_spark_burst(ast["pos"], _ore_color(String(ast["ore"])), 3)
		if float(ast["hp"]) <= 0.0:
			var ore := String(ast["ore"])
			var give := 24
			GameState.add_res(ore, give)
			AudioSynth.play_sfx("mine")
			spawn_spark_burst(ast["pos"], _ore_color(ore), 14)
			spawn_popup(ast["pos"], "+%d %s" % [give, ore.to_upper()], _ore_color(ore))
			asteroids.remove_at(i)
			return true
		return false
	elif kind == "moon":
		var m := moons[int(tgt["idx"])]
		var ore := String(m["ore"])
		if randf() < dmg * 0.045:
			GameState.add_res(ore, 3)
			AudioSynth.play_sfx("mine")
			spawn_spark_burst(tgt["pos"], _ore_color(ore), 6)
			spawn_popup(tgt["pos"], "+3 %s" % ore.to_upper(), _ore_color(ore))
			return true
	return false

func find_nearest_asteroid(pos: Vector2) -> Dictionary:
	var best_d := 1e9
	var best: Dictionary = {}
	for ast in asteroids:
		var d := pos.distance_to(ast["pos"])
		if d < best_d:
			best_d = d
			best = {"x": int(ast["pos"].x), "y": int(ast["pos"].y), "d": int(d), "ore": ast["ore"]}
	return best

static func _ore_color(ore: String) -> Color:
	match ore:
		"fe": return Color(0.95, 0.38, 0.36)
		"cu": return Color(0.98, 0.68, 0.25)
		"si": return Color(0.32, 0.88, 1.0)
		"ti": return Color(0.76, 0.46, 1.0)
		"ice": return Color(0.65, 0.92, 1.0)
		_: return Color(0.72, 0.78, 0.88)

# ------------------------------------------------------------------------------
# VFX HELPERS
# ------------------------------------------------------------------------------
func spawn_spark_burst(pos: Vector2, col: Color, count: int = 8) -> void:
	for _i in range(count):
		var a := randf_range(0.0, TAU)
		var spd := randf_range(40.0, 175.0)
		sparks.append({
			"pos": pos,
			"vel": Vector2(cos(a), sin(a)) * spd,
			"col": col,
			"life": randf_range(0.22, 0.55),
			"max_life": 0.55,
			"sz": randf_range(2.0, 4.0),
		})
	if sparks.size() > 260:
		sparks = sparks.slice(sparks.size() - 260)

func spawn_smoke(pos: Vector2, normal: Vector2, col: Color = Color(0.76, 0.80, 0.86, 0.38)) -> void:
	smokes.append({
		"pos": pos,
		"vel": normal * randf_range(22.0, 46.0) + Vector2(-normal.y, normal.x) * randf_range(-16.0, 16.0),
		"col": col,
		"rad": randf_range(7.0, 12.0),
		"life": randf_range(1.1, 2.0),
		"max_life": 2.0,
	})
	if smokes.size() > 90:
		smokes.pop_front()

func spawn_popup(pos: Vector2, txt: String, col: Color) -> void:
	var up := pos.normalized() if pos.length() > 1.0 else Vector2.UP
	popups.append({
		"pos": pos + up * 16.0,
		"vel": up * 34.0,
		"txt": txt,
		"col": col,
		"life": 1.15,
	})
	if popups.size() > 36:
		popups.pop_front()

# ------------------------------------------------------------------------------
# HD-2D PIXEL-ART SPHERICAL PLANET CROSS-SECTION RENDERING
# ------------------------------------------------------------------------------
func _draw() -> void:
	var cam := get_viewport().get_camera_2d()
	var cpos := cam.global_position if cam else Vector2(0.0, -R_SURFACE)
	var vp := get_viewport_rect().size
	var z := cam.zoom.x if cam else 1.0
	var half_span := (vp * 0.5) / maxf(0.02, z) + Vector2(360.0, 360.0)
	var view_rect := Rect2(cpos - half_span, half_span * 2.0)

	# 1. Atmospheric Rayleigh Scattering Halo around Origin-Prime
	var atmos_bands := 6
	for b in range(atmos_bands):
		var t := float(b) / float(atmos_bands)
		var rr := lerpf(R_SURFACE, R_ATMOS, 1.0 - t)
		var col := Color(0.11, 0.25, 0.48, 0.075 + t * 0.055)
		draw_circle(Vector2.ZERO, rr, col)
	# Crisp thin cyan atmospheric horizon line
	draw_arc(Vector2.ZERO, R_ATMOS, 0.0, TAU, 128, Color(0.24, 0.56, 0.88, 0.22), 3.0 / maxf(0.04, z))

	# 2. Planetary Crust & Subterranean Caverns
	if z < 0.22:
		_draw_planet_macro_lod(z)
	else:
		_draw_planet_detailed_tiles(view_rect, cpos)

	# 3. Incandescent Molten Magma Core
	var magma_tex := ArtRegistry.get_tex("terrain_magma")
	var glow_tex := ArtRegistry.get_tex("glow_soft")
	if view_rect.intersects(Rect2(-R_CORE - 600, -R_CORE - 600, (R_CORE + 600) * 2.0, (R_CORE + 600) * 2.0)):
		if glow_tex:
			var gr := R_CORE * 1.48
			draw_texture_rect(glow_tex, Rect2(-gr, -gr, gr * 2.0, gr * 2.0), false, Color(1.0, 0.42, 0.08, 0.36))
		if magma_tex:
			var pts := PackedVector2Array()
			var uvs := PackedVector2Array()
			var segs := 64
			var shift := anim_time * 0.05
			for i in range(segs):
				var a := float(i) / float(segs) * TAU
				var p := Vector2(cos(a), sin(a)) * R_CORE
				pts.append(p)
				uvs.append(Vector2(cos(a) * 6.0 + shift, sin(a) * 6.0 - shift * 0.6))
			draw_polygon(pts, PackedColorArray([Color.WHITE]), uvs, magma_tex)
		else:
			draw_circle(Vector2.ZERO, R_CORE, Color(1.0, 0.48, 0.12))
		draw_arc(Vector2.ZERO, R_CORE, 0.0, TAU, 96, Color(1.0, 0.86, 0.38, 0.85), 10.0)

	# 4. Orbiting Moons (Shaded Pixel Art)
	for m in moons:
		var mp: Vector2 = m["pos"]
		var mr := float(m["radius"])
		if not view_rect.intersects(Rect2(mp.x - mr - 120, mp.y - mr - 120, (mr + 120) * 2.0, (mr + 120) * 2.0)):
			continue
		if glow_tex:
			draw_texture_rect(glow_tex, Rect2(mp.x - mr * 1.45, mp.y - mr * 1.45, mr * 2.9, mr * 2.9), false, Color(0.45, 0.72, 1.0, 0.16))
		var mtex := ArtRegistry.get_tex(String(m["tex"]))
		if mtex:
			draw_texture_rect(mtex, Rect2(mp.x - mr, mp.y - mr, mr * 2.0, mr * 2.0), false)
		else:
			draw_circle(mp, mr, Color(0.55, 0.62, 0.76))
		if z < 0.35:
			var fnt := ThemeDB.fallback_font
			draw_string(fnt, mp + Vector2(-mr * 0.6, -mr - 35.0 / maxf(0.05, z)), String(m["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(14.0 / maxf(0.08, z)), Color(0.75, 0.90, 1.0, 0.85))

	# 5. Orbital Asteroids
	for ast in asteroids:
		var ap: Vector2 = ast["pos"]
		var ar := float(ast["radius"])
		if not view_rect.has_point(ap):
			continue
		var atex := ArtRegistry.get_tex("ast_" + String(ast["ore"]))
		if atex:
			draw_set_transform(ap, float(ast["rot"]), Vector2.ONE)
			draw_texture_rect(atex, Rect2(-ar, -ar, ar * 2.0, ar * 2.0), false)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			draw_circle(ap, ar, _ore_color(String(ast["ore"])))

	# 6. Smoke Plumes, Sparks & Floating Popups
	for sm in smokes:
		var a := clampf(float(sm["life"]) / float(sm["max_life"]), 0.0, 1.0)
		var col: Color = sm["col"]
		col.a *= a
		if glow_tex:
			var r := float(sm["rad"]) * 1.6
			draw_texture_rect(glow_tex, Rect2(sm["pos"].x - r, sm["pos"].y - r, r * 2.0, r * 2.0), false, col)
		else:
			draw_circle(sm["pos"], float(sm["rad"]), col)

	for sp in sparks:
		var a := clampf(float(sp["life"]) / float(sp["max_life"]), 0.0, 1.0)
		var col: Color = sp["col"]
		col.a = a
		var sz := float(sp["sz"])
		draw_rect(Rect2(sp["pos"] - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), col)

	var font := ThemeDB.fallback_font
	for pp in popups:
		var a := clampf(float(pp["life"]) / 1.15, 0.0, 1.0)
		var col: Color = pp["col"]
		col.a = a
		draw_string(font, pp["pos"], String(pp["txt"]), HORIZONTAL_ALIGNMENT_CENTER, -1, 15, col)

func _draw_planet_macro_lod(z: float) -> void:
	# Clean high-speed full-planet view when zoomed out into space!
	draw_circle(Vector2.ZERO, R_SURFACE, Color(0.08, 0.11, 0.16, 1.0))
	draw_arc(Vector2.ZERO, R_SURFACE - 60.0, 0.0, TAU, 144, Color(0.66, 0.50, 0.34, 0.95), 140.0)
	draw_arc(Vector2.ZERO, R_SURFACE, 0.0, TAU, 144, Color(0.88, 0.74, 0.52, 0.9), 28.0)
	# Render luminous vein dots across the cross-section
	for l in range(2, LAYERS, 2):
		var r := R_CORE + (float(l) + 0.5) * LAYER_THICK
		for s in range(0, SECTORS, 2):
			var idx := l * SECTORS + s
			var ore := cell_ore[idx]
			if ore != "" and cell_hp[idx] > 0.0:
				var p := polar_to_world(sector_center_angle(s), r)
				draw_circle(p, 58.0, _ore_color(ore))
	# Day/night shadow hemisphere
	var night_a := sun_angle + PI
	var shadow_pts := PackedVector2Array([Vector2.ZERO])
	for i in range(25):
		var a := night_a - PI * 0.5 + float(i) / 24.0 * PI
		shadow_pts.append(Vector2(cos(a), sin(a)) * (R_SURFACE + 40.0))
	draw_polygon(shadow_pts, PackedColorArray([Color(0.01, 0.015, 0.035, 0.45)]))
	# Draw moon orbit rings faintly in macro view
	for m in moons:
		draw_arc(Vector2.ZERO, float(m["orbit_r"]), 0.0, TAU, 96, Color(0.32, 0.52, 0.78, 0.16), 2.0 / maxf(0.02, z))

func _draw_planet_detailed_tiles(view_rect: Rect2, cpos: Vector2) -> void:
	var reg_tex := ArtRegistry.get_tex("terrain_regolith")
	var bas_tex := ArtRegistry.get_tex("terrain_basalt")
	var bw_tex := ArtRegistry.get_tex("terrain_backwall")
	var glow_tex := ArtRegistry.get_tex("glow_soft")

	# Determine angular window of sectors visible in view_rect
	var c_dist := cpos.length()
	var half_diag := view_rect.size.length() * 0.52
	if c_dist - half_diag > R_SURFACE + 200.0:
		return

	var center_a := atan2(cpos.y, cpos.x)
	if center_a < 0.0:
		center_a += TAU
	var ang_span := PI if c_dist < half_diag + 400.0 else minf(PI, asin(clampf(half_diag / maxf(1.0, c_dist), 0.0, 1.0)) + 0.22)
	var min_s := int(floor((center_a - ang_span) / DA)) - 1
	var max_s := int(ceil((center_a + ang_span) / DA)) + 1

	var r_min := maxf(R_CORE, c_dist - half_diag - LAYER_THICK)
	var r_max := minf(R_SURFACE, c_dist + half_diag + LAYER_THICK)
	var l_min := clampi(int(floor((r_min - R_CORE) / LAYER_THICK)) - 1, 0, LAYERS - 1)
	var l_max := clampi(int(ceil((r_max - R_CORE) / LAYER_THICK)) + 1, 0, LAYERS - 1)

	for s_raw in range(min_s, max_s + 1):
		var s := wrap_sector(s_raw)
		var a0 := float(s) * DA
		var a1 := float(s + 1) * DA
		var ca0 := cos(a0); var sa0 := sin(a0)
		var ca1 := cos(a1); var sa1 := sin(a1)
		var mid_a := (a0 + a1) * 0.5
		var sun_lit := lerpf(0.42, 1.05, get_sunlight_at(Vector2(cos(mid_a), sin(mid_a)) * R_SURFACE))

		for l in range(l_min, l_max + 1):
			var idx := l * SECTORS + s
			var hp_v := cell_hp[idx]
			var r0 := R_CORE + float(l) * LAYER_THICK
			var r1 := r0 + LAYER_THICK
			var p00 := Vector2(ca0 * r0, sa0 * r0)
			var p10 := Vector2(ca1 * r0, sa1 * r0)
			var p11 := Vector2(ca1 * r1, sa1 * r1)
			var p01 := Vector2(ca0 * r1, sa0 * r1)
			var quad := PackedVector2Array([p00, p10, p11, p01])
			# Seamless continuous polar UVs (eliminates boxy grid tiling!)
			var u0 := float(s) * 0.58
			var u1 := float(s + 1) * 0.58
			var v0 := float(LAYERS - l) * 0.58
			var v1 := float(LAYERS - (l + 1)) * 0.58
			var uvs := PackedVector2Array([Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)])

			if hp_v <= 0.0:
				# Hollow subterranean cave / mined tunnel -> moody parallax cave backwall!
				if cell_cavern[idx] == 1 and l < LAYERS - 1:
					var bw_tint := Color(0.86, 0.90, 1.0, 1.0)
					if l < 7:
						bw_tint = bw_tint.lerp(Color(1.0, 0.55, 0.30, 1.0), float(7 - l) / 10.0)
					if bw_tex:
						draw_polygon(quad, PackedColorArray([bw_tint]), uvs, bw_tex)
					else:
						draw_polygon(quad, PackedColorArray([Color(0.06, 0.08, 0.12)]))
				continue

			var is_regolith := (l >= LAYERS - 2)
			var tile_tex := reg_tex if is_regolith else bas_tex
			var shade := sun_lit if is_regolith else lerpf(0.78, 1.0, float(l) / float(LAYERS))
			var tint := Color(shade, shade, shade, 1.0)
			# Magma under-glow near core layers
			if l < 6:
				tint = tint.lerp(Color(1.2, 0.62, 0.34, 1.0), float(6 - l) / 8.0)

			if tile_tex:
				draw_polygon(quad, PackedColorArray([tint]), uvs, tile_tex)
			else:
				draw_polygon(quad, PackedColorArray([Color(0.55, 0.42, 0.28) if is_regolith else Color(0.18, 0.22, 0.30)]))

			# Crisp surface horizon rim & cavern contour bevels!
			if not is_cell_solid(s, l + 1):
				var rim_col := Color(0.95, 0.85, 0.62, 0.96) * sun_lit if is_regolith else Color(0.36, 0.44, 0.56, 0.9)
				draw_line(p01, p11, rim_col, 5.5)
				draw_line(p01, p11, Color(0.06, 0.08, 0.12, 0.92), 2.0)
			if l > 0 and not is_cell_solid(s, l - 1):
				draw_line(p00, p10, Color(0.04, 0.06, 0.09, 0.96), 5.0)
			if not is_cell_solid(s - 1, l):
				draw_line(p00, p01, Color(0.05, 0.07, 0.10, 0.94), 4.0)
			if not is_cell_solid(s + 1, l):
				draw_line(p10, p11, Color(0.05, 0.07, 0.10, 0.94), 4.0)

			# Organic Ore / Crystal cluster sprite + HD-2D glow halo
			var ore := cell_ore[idx]
			if ore != "":
				var jitter_t := sin(float(idx) * 12.9898) * 14.0
				var jitter_r := cos(float(idx) * 78.233) * 10.0
				var nrm := Vector2(cos(mid_a), sin(mid_a))
				var tng := Vector2(-nrm.y, nrm.x)
				var cp := (p00 + p10 + p11 + p01) * 0.25 + tng * jitter_t + nrm * jitter_r
				var sc_o := 0.86 + 0.30 * absf(sin(float(idx) * 3.17))
				if glow_tex:
					var gc := _ore_color(ore)
					gc.a = 0.34 if ore == "si" else 0.24
					var gr_o := 48.0 * sc_o
					draw_texture_rect(glow_tex, Rect2(cp.x - gr_o, cp.y - gr_o, gr_o * 2.0, gr_o * 2.0), false, gc)
				var otex := ArtRegistry.get_tex("ore_" + ore)
				if otex:
					var sz_o := 54.0 * sc_o
					draw_set_transform(cp, mid_a + PI * 0.5, Vector2.ONE)
					draw_texture_rect(otex, Rect2(-sz_o * 0.5, -sz_o * 0.5, sz_o, sz_o), false)
					draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

			# Damage crack indicator while being mined
			if hp_v < cell_max_hp[idx] * 0.95:
				var dmg_f := 1.0 - (hp_v / maxf(1.0, cell_max_hp[idx]))
				var cp := (p00 + p10 + p11 + p01) * 0.25
				draw_circle(cp, 14.0 + dmg_f * 26.0, Color(1.0, 0.85, 0.45, 0.22 * dmg_f))
