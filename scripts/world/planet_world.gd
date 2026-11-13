extends Node2D
class_name PlanetWorld

# ==============================================================================
# STAR REPLICA: AUTOMA - 360-DEGREE SPHERICAL PLANET & OPEN-WORLD UNIVERSE
# Zero pre-built orbital stations. True radial terrain excavation, caverns,
# molten core, curved surface slots, asteroid rings, and explorable planets.
# ==============================================================================

const SECTORS: int = 72
const LAYERS: int = 10
const LAYER_THICK: float = 48.0
const R_MAGMA: float = 160.0
const R_SURFACE: float = R_MAGMA + LAYERS * LAYER_THICK # 640.0
const DA: float = TAU / float(SECTORS)
const WORLD_LIMIT_R: float = 7200.0
const SPAWN_SECTOR: int = 54 # Top (north pole, -PI/2 = 270 deg)

enum CellKind { EMPTY, SURFACE, ROCK, MAGMA }

var cell_kind: PackedByteArray = PackedByteArray()
var cell_ore: Array[String] = []
var cell_hp: PackedFloat32Array = PackedFloat32Array()
var cell_max_hp: PackedFloat32Array = PackedFloat32Array()

# Natural Open-World Asteroids & Celestials
var asteroids: Array[Dictionary] = []
var celestials: Array[Dictionary] = []
var stars: Array[Dictionary] = []

# FX & World Popups
var particles: Array[Dictionary] = []
var world_popups: Array[Dictionary] = []

var tex_ores: Dictionary = {}
var tex_celestials: Dictionary = {}
var anim_time: float = 0.0

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_load_textures()
	_init_open_world_cosmos()
	generate_world(42077)

func _load_textures() -> void:
	tex_ores = {
		"fe": load("res://assets/environment/ore_fe.png"),
		"cu": load("res://assets/environment/ore_cu.png"),
		"si": load("res://assets/environment/ore_si.png"),
		"ti": load("res://assets/environment/ore_ti.png"),
	}
	tex_celestials = {
		"sun": load("res://assets/environment/celestial_sun.png"),
		"moon": load("res://assets/environment/moon_asteroid.png"),
		"planet_large": load("res://assets/environment/planet_large.png"),
		"planet_crystal": load("res://assets/environment/planet_crystal.png"),
		"planet_volcanic": load("res://assets/environment/planet_volcanic.png"),
		"asteroid": load("res://assets/environment/celestial_asteroid.png"),
		"blackhole": load("res://assets/environment/celestial_blackhole.png"),
		"pulsar": load("res://assets/environment/celestial_pulsar.png"),
	}

func _init_open_world_cosmos() -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = 90421
	stars.clear()
	for _i in range(640):
		var a = rng.randf_range(0.0, TAU)
		var d = sqrt(rng.randf()) * WORLD_LIMIT_R
		stars.append({
			"pos": Vector2(cos(a), sin(a)) * d,
			"size": 1.5 if rng.randf() < 0.72 else 3.0,
			"phase": rng.randf_range(0.0, TAU),
			"tint": Color(0.82, 0.90, 1.0) if rng.randf() < 0.7 else Color(1.0, 0.88, 0.68),
		})

	# Open-world celestial bodies (all genuinely reachable in open space!)
	celestials = [
		{"tex": "moon", "pos": Vector2(1420.0, -1180.0), "r": 120.0, "ore": "fe", "name": "LUNA-PRIME"},
		{"tex": "planet_crystal", "pos": Vector2(-2450.0, -1720.0), "r": 180.0, "ore": "si", "name": "CRYO-CRYSTAL"},
		{"tex": "planet_volcanic", "pos": Vector2(2650.0, 1520.0), "r": 185.0, "ore": "ti", "name": "IGNIS-IV"},
		{"tex": "planet_large", "pos": Vector2(-2100.0, 2300.0), "r": 240.0, "ore": "cu", "name": "GAIA-MAJOR"},
		{"tex": "sun", "pos": Vector2(4400.0, -3100.0), "r": 320.0, "ore": "", "name": "HELIOS-PRIME"},
		{"tex": "pulsar", "pos": Vector2(-4300.0, -3300.0), "r": 160.0, "ore": "ti", "name": "PULSAR-X"},
		{"tex": "blackhole", "pos": Vector2(3900.0, 3600.0), "r": 250.0, "ore": "", "name": "GARGANTUA-0"},
	]

func generate_world(seed_val: int = 42077) -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_val

	var total = SECTORS * LAYERS
	cell_kind.resize(total)
	cell_hp.resize(total)
	cell_max_hp.resize(total)
	cell_ore.resize(total)

	for l in range(LAYERS):
		for s in range(SECTORS):
			var idx = l * SECTORS + s
			cell_ore[idx] = ""
			if l == 0:
				cell_kind[idx] = CellKind.MAGMA
				cell_hp[idx] = 9999.0
				cell_max_hp[idx] = 9999.0
			elif l == LAYERS - 1:
				cell_kind[idx] = CellKind.SURFACE
				cell_hp[idx] = 12.0
				cell_max_hp[idx] = 12.0
			else:
				cell_kind[idx] = CellKind.ROCK
				var depth_hp = 10.0 + float(LAYERS - l) * 1.8
				cell_hp[idx] = depth_hp
				cell_max_hp[idx] = depth_hp

	# Carve curved subterranean caverns inside middle strata (keeping crust solid at layer 9!)
	var cavs = [
		Vector2i(10, 5), Vector2i(22, 4), Vector2i(35, 6),
		Vector2i(47, 5), Vector2i(62, 6), Vector2i(54, 4),
	]
	for cv in cavs:
		for dl in range(-2, 3):
			for ds in range(-3, 4):
				if abs(dl) + abs(ds) <= 3:
					var l = clampi(cv.y + dl, 1, LAYERS - 2)
					var s = posmod(cv.x + ds, SECTORS)
					var idx = l * SECTORS + s
					cell_kind[idx] = CellKind.EMPTY
					cell_hp[idx] = 0.0

	# Guaranteed rich starter veins right beneath North Pole spawn (SPAWN_SECTOR = 54)
	_paint_vein(rng, 52, 8, "fe", 2, 1, 14)
	_paint_vein(rng, 56, 8, "fe", 2, 1, 14)
	_paint_vein(rng, 50, 7, "cu", 1, 1, 14)
	_paint_vein(rng, 58, 7, "cu", 1, 1, 14)
	_paint_vein(rng, 54, 6, "si", 1, 1, 14)
	_paint_vein(rng, 54, 3, "ti", 2, 1, 18)

	# Distributed planetary ore pockets across 360-degree sphere
	for _i in range(16):
		_paint_vein(rng, rng.randi_range(0, SECTORS - 1), rng.randi_range(5, 8), "fe", 1, 1, 12)
	for _i in range(13):
		_paint_vein(rng, rng.randi_range(0, SECTORS - 1), rng.randi_range(4, 8), "cu", 1, 1, 12)
	for _i in range(10):
		_paint_vein(rng, rng.randi_range(0, SECTORS - 1), rng.randi_range(2, 6), "si", 1, 1, 14)
	for _i in range(8):
		_paint_vein(rng, rng.randi_range(0, SECTORS - 1), rng.randi_range(1, 4), "ti", 1, 1, 18)

	# Natural Orbital Asteroid Rings (no stations!)
	asteroids.clear()
	var ore_cycle = ["fe", "cu", "si", "ti"]
	for i in range(44):
		var ang = rng.randf_range(0.0, TAU)
		var dist = rng.randf_range(960.0, 2900.0)
		var ot = ore_cycle[i % ore_cycle.size()]
		asteroids.append({
			"pos": Vector2(cos(ang), sin(ang)) * dist,
			"ore": ot,
			"hp": 110.0,
			"max_hp": 110.0,
			"radius": rng.randf_range(22.0, 36.0),
			"ang": ang,
			"dist": dist,
			"orbit_spd": rng.randf_range(0.008, 0.022) * (1.0 if i % 2 == 0 else -1.0),
		})
	queue_redraw()

func _paint_vein(rng: RandomNumberGenerator, center_s: int, center_l: int, ore: String, rs: int, rl: int, hp_bonus: int) -> void:
	for dl in range(-rl, rl + 1):
		var l = clampi(center_l + dl, 1, LAYERS - 2)
		for ds in range(-rs, rs + 1):
			if abs(ds) + abs(dl) <= rs + rl - rng.randi_range(0, 1):
				var s = posmod(center_s + ds, SECTORS)
				var idx = l * SECTORS + s
				if cell_kind[idx] == CellKind.ROCK or cell_kind[idx] == CellKind.EMPTY:
					cell_kind[idx] = CellKind.ROCK
					cell_ore[idx] = ore
					cell_max_hp[idx] = float(10 + (LAYERS - l) + hp_bonus)
					cell_hp[idx] = cell_max_hp[idx]

static func wrap_sector(s: int) -> int:
	return posmod(s, SECTORS)

static func sector_center_angle(s: int) -> float:
	return (float(wrap_sector(s)) + 0.5) * DA

static func layer_inner_r(l: int) -> float:
	return R_MAGMA + float(l) * LAYER_THICK

static func layer_outer_r(l: int) -> float:
	return R_MAGMA + float(l + 1) * LAYER_THICK

func polar_to_world(ang: float, radius: float) -> Vector2:
	return Vector2(cos(ang), sin(ang)) * radius

func cell_center(s: int, l: int) -> Vector2:
	var ang = sector_center_angle(s)
	var r = (layer_inner_r(l) + layer_outer_r(l)) * 0.5
	return polar_to_world(ang, r)

func pos_to_cell(pos: Vector2) -> Vector2i:
	var r = pos.length()
	var ang = fposmod(pos.angle(), TAU)
	var s = clampi(int(floor(ang / DA)), 0, SECTORS - 1)
	if r < R_MAGMA:
		return Vector2i(s, -1)
	var l = int(floor((r - R_MAGMA) / LAYER_THICK))
	return Vector2i(s, l)

func is_solid_cell(s: int, l: int) -> bool:
	if l < 0:
		return true # Inner molten core boundary
	if l >= LAYERS:
		return false # Open space!
	var idx = l * SECTORS + wrap_sector(s)
	return cell_kind[idx] != CellKind.EMPTY

func get_kind(s: int, l: int) -> int:
	if l < 0: return CellKind.MAGMA
	if l >= LAYERS: return CellKind.EMPTY
	return cell_kind[l * SECTORS + wrap_sector(s)]

func get_ore(s: int, l: int) -> String:
	if l < 0 or l >= LAYERS: return ""
	return cell_ore[l * SECTORS + wrap_sector(s)]

func is_point_solid(pos: Vector2) -> bool:
	var cell = pos_to_cell(pos)
	return is_solid_cell(cell.x, cell.y)

func damage_cell(s: int, l: int, power: float, track_player_popup: bool = true) -> Dictionary:
	var res = {"hit": false, "destroyed": false, "ore": "", "amount": 0}
	if l < 0 or l >= LAYERS:
		return res
	var ws = wrap_sector(s)
	var idx = l * SECTORS + ws
	if cell_kind[idx] == CellKind.EMPTY or cell_kind[idx] == CellKind.MAGMA:
		return res

	res["hit"] = true
	cell_hp[idx] -= power
	var ore_name = cell_ore[idx]
	var center = cell_center(ws, l)

	if ore_name != "" and randf() < 0.36:
		GameState.add_res(ore_name, 1, track_player_popup)
		res["ore"] = ore_name
		res["amount"] = 1

	spawn_spark_burst(center, _ore_color(ore_name), 3)

	if cell_hp[idx] <= 0.0:
		cell_kind[idx] = CellKind.EMPTY
		res["destroyed"] = true
		if ore_name != "":
			var burst = 5 + (LAYERS - l) / 2
			GameState.add_res(ore_name, burst, track_player_popup)
			res["ore"] = ore_name
			res["amount"] += burst
			cell_ore[idx] = ""
			spawn_world_popup(center, "+%d %s" % [burst, ore_name.to_upper()], _ore_color(ore_name))
		else:
			GameState.add_res("fe", 2, track_player_popup)
			res["ore"] = "fe"
			res["amount"] += 2
			spawn_world_popup(center, "+2 FE", Color(0.55, 0.85, 1.0))
		spawn_spark_burst(center, _ore_color(ore_name), 10)
		queue_redraw()
	return res

func mine_asteroid_at(world_pos: Vector2, power: float, max_dist: float = 180.0) -> Dictionary:
	var best_idx = -1
	var best_d = max_dist
	for i in range(asteroids.size()):
		var a = asteroids[i]
		if a["hp"] <= 0.0: continue
		var d = a["pos"].distance_to(world_pos)
		if d < best_d:
			best_d = d
			best_idx = i
	if best_idx == -1:
		return {"hit": false}
	var ast = asteroids[best_idx]
	ast["hp"] -= power
	var ore_name: String = ast["ore"]
	spawn_spark_burst(ast["pos"], _ore_color(ore_name), 3)
	if randf() < 0.48:
		GameState.add_res(ore_name, 1, true)
	if ast["hp"] <= 0.0:
		var burst = 14
		GameState.add_res(ore_name, burst, true)
		spawn_world_popup(ast["pos"], "+%d %s" % [burst, ore_name.to_upper()], _ore_color(ore_name))
		spawn_spark_burst(ast["pos"], Color(1.0, 0.85, 0.4), 14)
		ast["hp"] = ast["max_hp"]
		ast["ang"] += randf_range(0.6, 2.5)
		ast["pos"] = Vector2(cos(ast["ang"]), sin(ast["ang"])) * ast["dist"]
	return {"hit": true, "pos": ast["pos"], "ore": ore_name}

func find_nearest_mine_target(world_pos: Vector2, max_range: float = 160.0) -> Dictionary:
	# First check orbital asteroids if above atmosphere
	if world_pos.length() > R_SURFACE + 60.0:
		var best_ast = null
		var best_d = max_range * 1.4
		for a in asteroids:
			var d = a["pos"].distance_to(world_pos)
			if d < best_d:
				best_d = d
				best_ast = a
		if best_ast != null:
			return {"type": "asteroid", "pos": best_ast["pos"]}

	# Radial sphere ore/rock search
	var pcell = pos_to_cell(world_pos)
	var best_ore_d = 999999.0
	var best_ore_c = Vector2i(-1, -1)
	var best_rock_d = 999999.0
	var best_rock_c = Vector2i(-1, -1)

	for l in range(maxi(1, pcell.y - 3), mini(LAYERS, pcell.y + 3)):
		for ds in range(-4, 5):
			var s = wrap_sector(pcell.x + ds)
			if not is_solid_cell(s, l): continue
			var cp = cell_center(s, l)
			var d = cp.distance_to(world_pos)
			if d > max_range: continue
			if get_ore(s, l) != "":
				if d < best_ore_d:
					best_ore_d = d
					best_ore_c = Vector2i(s, l)
			elif l < LAYERS - 1: # Prefer mining underground rock rather than punching holes in surface floor
				if d < best_rock_d:
					best_rock_d = d
					best_rock_c = Vector2i(s, l)

	if best_ore_c.x >= 0:
		return {"type": "cell", "cell": best_ore_c, "pos": cell_center(best_ore_c.x, best_ore_c.y)}
	if best_rock_c.x >= 0:
		return {"type": "cell", "cell": best_rock_c, "pos": cell_center(best_rock_c.x, best_rock_c.y)}
	return {}

func spawn_spark_burst(pos: Vector2, col: Color, count: int = 6) -> void:
	if particles.size() > 260: return
	for _i in range(count):
		var ang = randf_range(0.0, TAU)
		var spd = randf_range(35.0, 140.0)
		particles.append({
			"pos": pos,
			"vel": Vector2(cos(ang), sin(ang)) * spd,
			"life": randf_range(0.22, 0.55),
			"max_life": 0.55,
			"size": randf_range(2.5, 4.5),
			"col": col,
		})

func spawn_smoke_puff(pos: Vector2, dir: Vector2) -> void:
	if particles.size() > 260: return
	particles.append({
		"pos": pos,
		"vel": dir.normalized() * randf_range(26.0, 48.0) + Vector2(randf_range(-8.0, 8.0), randf_range(-8.0, 8.0)),
		"life": 1.0,
		"max_life": 1.0,
		"size": randf_range(4.0, 7.0),
		"col": Color(0.55, 0.62, 0.72, 0.55),
	})

func spawn_world_popup(pos: Vector2, text: String, col: Color) -> void:
	world_popups.append({
		"pos": pos,
		"dir": pos.normalized() if pos.length() > 10.0 else Vector2.UP,
		"text": text,
		"col": col,
		"life": 1.5,
		"max_life": 1.5,
	})

func _ore_color(ore: String) -> Color:
	match ore:
		"fe": return Color(0.32, 0.85, 1.0)
		"cu": return Color(1.0, 0.58, 0.22)
		"si": return Color(0.75, 0.48, 1.0)
		"ti": return Color(0.55, 1.0, 0.72)
	return Color(0.78, 0.84, 0.92)

func _process(delta: float) -> void:
	anim_time += delta
	for a in asteroids:
		a["ang"] += a["orbit_spd"] * delta
		a["pos"] = Vector2(cos(a["ang"]), sin(a["ang"])) * a["dist"]
	for i in range(particles.size() - 1, -1, -1):
		var p = particles[i]
		p["pos"] += p["vel"] * delta
		p["vel"] *= 0.94
		p["life"] -= delta
		if p["life"] <= 0.0:
			particles.remove_at(i)
	for i in range(world_popups.size() - 1, -1, -1):
		var w = world_popups[i]
		w["pos"] += w["dir"] * 24.0 * delta
		w["life"] -= delta
		if w["life"] <= 0.0:
			world_popups.remove_at(i)
	queue_redraw()

func _draw() -> void:
	var vrect = get_viewport_rect()
	var inv_xform = get_canvas_transform().affine_inverse()
	var tl = inv_xform * Vector2.ZERO
	var br = inv_xform * vrect.size
	var min_x = minf(tl.x, br.x) - 360.0
	var max_x = maxf(tl.x, br.x) + 360.0
	var min_y = minf(tl.y, br.y) - 360.0
	var max_y = maxf(tl.y, br.y) + 360.0

	# 1. Deep Open Space Void
	draw_rect(Rect2(min_x, min_y, max_x - min_x, max_y - min_y), Color(0.02, 0.032, 0.068, 1.0))

	# 2. Starfield in visible open-world frustum
	for st in stars:
		var sp: Vector2 = st["pos"]
		if sp.x < min_x or sp.x > max_x or sp.y < min_y or sp.y > max_y:
			continue
		var tw = 0.5 + 0.5 * sin(anim_time * 2.0 + st["phase"])
		var c: Color = st["tint"]
		c.a = 0.35 + 0.65 * tw
		draw_rect(Rect2(sp, Vector2(st["size"], st["size"])), c)

	# 3. Spherical Atmospheric Corona around Origin-Prime (0,0)
	if Rect2(-950, -950, 1900, 1900).intersects(Rect2(min_x, min_y, max_x - min_x, max_y - min_y)):
		draw_circle(Vector2.ZERO, R_SURFACE + 145.0, Color(0.06, 0.14, 0.28, 0.35))
		draw_circle(Vector2.ZERO, R_SURFACE + 72.0, Color(0.11, 0.24, 0.44, 0.42))
		draw_circle(Vector2.ZERO, R_SURFACE + 22.0, Color(0.16, 0.35, 0.58, 0.48))

	# 4. Distant Open-World Planets & Stars
	var font = ThemeDB.fallback_font
	for b in celestials:
		var bp: Vector2 = b["pos"]
		var br_rad: float = b["r"]
		if bp.x + br_rad < min_x or bp.x - br_rad > max_x or bp.y + br_rad < min_y or bp.y - br_rad > max_y:
			continue
		var tex: Texture2D = tex_celestials.get(b["tex"], null)
		if tex:
			draw_texture_rect(tex, Rect2(bp - Vector2(br_rad, br_rad), Vector2(br_rad * 2.0, br_rad * 2.0)), false)
		if font:
			draw_string(font, bp + Vector2(-46.0, br_rad + 18.0), b["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.65, 0.85, 1.0, 0.85))

	# 5. Orbital Harvestable Asteroids
	var ast_tex: Texture2D = tex_celestials.get("asteroid", null)
	for a in asteroids:
		var ap: Vector2 = a["pos"]
		if ap.x < min_x or ap.x > max_x or ap.y < min_y or ap.y > max_y:
			continue
		var r = a["radius"]
		if ast_tex:
			draw_texture_rect(ast_tex, Rect2(ap - Vector2(r, r), Vector2(r * 2.0, r * 2.0)), false, _ore_color(a["ore"]).lerp(Color.WHITE, 0.45))

	# 6. Spherical Cross-Section Planet Origin-Prime (Only if near viewport)
	if Rect2(-720, -720, 1440, 1440).intersects(Rect2(min_x, min_y, max_x - min_x, max_y - min_y)):
		# Deep dark interior bedrock void
		draw_circle(Vector2.ZERO, R_SURFACE, Color(0.04, 0.045, 0.085, 1.0))

		# Molten Inner Core Glow (R < R_MAGMA) with plasma swirl arcs
		var core_pulse = 0.88 + 0.12 * sin(anim_time * 3.0)
		draw_circle(Vector2.ZERO, R_MAGMA, Color(0.95, 0.36 * core_pulse, 0.08, 1.0))
		draw_circle(Vector2.ZERO, R_MAGMA * 0.65, Color(1.0, 0.72 * core_pulse, 0.22, 1.0))
		draw_arc(Vector2.ZERO, R_MAGMA * 0.82, anim_time * 0.4, anim_time * 0.4 + 2.2, 20, Color(1.0, 0.82, 0.32, 0.55), 3.0)
		draw_arc(Vector2.ZERO, R_MAGMA * 0.44, -anim_time * 0.7, -anim_time * 0.7 + 2.8, 16, Color(1.0, 0.95, 0.70, 0.65), 2.5)

		# Radial Wedge Strata Cells (72 sectors x 10 layers)
		for l in range(LAYERS):
			var r0 = layer_inner_r(l)
			var r1 = layer_outer_r(l)
			for s in range(SECTORS):
				var idx = l * SECTORS + s
				var k = cell_kind[idx]
				if k == CellKind.EMPTY:
					continue
				var a0 = float(s) * DA
				var a1 = float(s + 1) * DA
				var pts = PackedVector2Array([
					Vector2(cos(a0) * r0, sin(a0) * r0),
					Vector2(cos(a0) * r1, sin(a0) * r1),
					Vector2(cos(a1) * r1, sin(a1) * r1),
					Vector2(cos(a1) * r0, sin(a1) * r0),
				])
				var grain = float((s * 17 + l * 31) % 7) * 0.014
				var base_col = Color(0.22 + grain, 0.23 + grain, 0.31 + grain, 1.0)
				if k == CellKind.SURFACE:
					base_col = Color(0.28 + grain, 0.36 + grain, 0.47 + grain, 1.0)
				elif k == CellKind.ROCK:
					var sh = 0.76 + 0.28 * (float(l) / float(LAYERS)) + grain
					base_col = Color(0.22 * sh, 0.22 * sh, 0.30 * sh, 1.0)
				elif k == CellKind.MAGMA:
					base_col = Color(0.90, (0.34 + grain) * core_pulse, 0.09, 1.0)
				draw_colored_polygon(pts, base_col)

				# Subtle sector border & cavern rim highlight for crisp readability
				if k == CellKind.SURFACE:
					draw_line(pts[1], pts[2], Color(0.45, 0.88, 1.0, 0.90), 2.4)
					draw_line(pts[0], pts[3], Color(0.18, 0.24, 0.34, 0.70), 1.2)
				else:
					draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2]]), Color(0.08, 0.10, 0.16, 0.50), 1.0)
					if not is_solid_cell(s, l + 1):
						draw_line(pts[1], pts[2], Color(0.46, 0.54, 0.72, 0.85), 2.0)
					if not is_solid_cell(s - 1, l):
						draw_line(pts[0], pts[1], Color(0.46, 0.54, 0.72, 0.85), 2.0)

				# Mineral Ore Vein Icon + Glowing Crystal Flecks
				var ore = cell_ore[idx]
				if ore != "":
					var center = cell_center(s, l)
					var oc = _ore_color(ore)
					draw_circle(center, 11.0, Color(oc.r, oc.g, oc.b, 0.14))
					var otex: Texture2D = tex_ores.get(ore, null)
					if otex:
						draw_texture_rect(otex, Rect2(center - Vector2(11, 11), Vector2(22, 22)), false)
					draw_circle(center, 3.8, Color(oc.r, oc.g, oc.b, 0.45 + 0.25 * sin(anim_time * 3.0 + float(s + l))))

	# 7. Sparks & Smoke
	for p in particles:
		var a = clampf(p["life"] / maxf(0.01, p["max_life"]), 0.0, 1.0)
		var col: Color = p["col"]
		col.a *= a
		var sz = p["size"]
		draw_rect(Rect2(p["pos"] - Vector2(sz * 0.5, sz * 0.5), Vector2(sz, sz)), col)

	# 8. Popups
	if font:
		for wp in world_popups:
			var a = clampf(wp["life"] / maxf(0.01, wp["max_life"]), 0.0, 1.0)
			var c: Color = wp["col"]
			c.a = a
			var tp = wp["pos"] + Vector2(-28, 0)
			draw_string(font, tp + Vector2(1, 1), wp["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0, 0, 0, a * 0.85))
			draw_string(font, tp, wp["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, c)
