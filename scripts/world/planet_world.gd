extends Node2D
class_name PlanetWorld

# ==============================================================================
# STAR REPLICA: AUTOMA - 2D CROSS-SECTION PLANET & ORBITAL WORLD
# Visual layout modeled on target_gameplay_concept.jpeg:
#   - Space & Orbit (y < 0): Starfield, Planets, Asteroids, Orbital Hub
#   - Surface Horizon (row 0, y = 0..32): Industrial flat plateau + outer ridges
#   - Underground Strata (rows 1..23): Rock, carved caverns, glowing crystal veins
#   - Magma Core (rows 24..27): Glowing geothermal crust
# ==============================================================================

const TILE_SIZE: int = 32
const COLS: int = 84
const ROWS: int = 28
const WORLD_WIDTH: float = COLS * TILE_SIZE
const WORLD_HEIGHT: float = ROWS * TILE_SIZE
const MAGMA_START_ROW: int = 24
const SPAWN_COL: int = 42

enum TileKind { EMPTY, SURFACE, ROCK, MAGMA }

# Flat PackedByteArray storage for fast lookup
var tile_kind: PackedByteArray = PackedByteArray()
var tile_ore: Array[String] = []
var tile_hp: PackedFloat32Array = PackedFloat32Array()
var tile_max_hp: PackedFloat32Array = PackedFloat32Array()
var was_cavern: PackedByteArray = PackedByteArray()

# Orbital Asteroids: {pos, ore, hp, max_hp, radius, seed}
var asteroids: Array[Dictionary] = []

# Mining beam FX & Floating numbers
var particles: Array[Dictionary] = []
var world_popups: Array[Dictionary] = []

# Preloaded Pixel Textures
var tex_surface: Texture2D
var tex_rock: Texture2D
var tex_magma: Texture2D
var tex_orbital_hub: Texture2D
var tex_ores: Dictionary = {}
var tex_celestials: Dictionary = {}

# Pre-baked starfield & distant celestial backdrop layout
var stars: Array[Dictionary] = []
var backdrop_bodies: Array[Dictionary] = []
var anim_time: float = 0.0

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_load_textures()
	_init_stars_and_celestials()
	generate_world(42077)

func _load_textures() -> void:
	tex_surface = load("res://assets/environment/surface_tile.png")
	tex_rock = load("res://assets/environment/rock_tile.png")
	tex_magma = load("res://assets/environment/magma_tile.png")
	tex_orbital_hub = load("res://assets/sprites/orbital_hub.png")
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

func _init_stars_and_celestials() -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = 19987
	stars.clear()
	for i in range(260):
		stars.append({
			"pos": Vector2(rng.randf_range(-400.0, WORLD_WIDTH + 400.0), rng.randf_range(-2100.0, -24.0)),
			"size": 1.0 if rng.randf() < 0.72 else 2.0,
			"phase": rng.randf_range(0.0, TAU),
			"tint": Color(0.78, 0.88, 1.0, 1.0) if rng.randf() < 0.7 else Color(1.0, 0.88, 0.68, 1.0),
		})
	backdrop_bodies = [
		{"tex": "moon", "pos": Vector2(620.0, -480.0), "scale": 1.05, "name": "LUNA-PRIME"},
		{"tex": "planet_large", "pos": Vector2(2040.0, -780.0), "scale": 0.92, "name": "GAIA-MAJOR"},
		{"tex": "planet_crystal", "pos": Vector2(460.0, -1180.0), "scale": 0.85, "name": "CRYO-CRYSTAL"},
		{"tex": "sun", "pos": Vector2(2260.0, -1580.0), "scale": 0.95, "name": "HELIOS-PRIME"},
		{"tex": "planet_volcanic", "pos": Vector2(1020.0, -1480.0), "scale": 0.78, "name": "IGNIS-IV"},
		{"tex": "pulsar", "pos": Vector2(1680.0, -1720.0), "scale": 0.85, "name": "PULSAR-X"},
		{"tex": "blackhole", "pos": Vector2(360.0, -1760.0), "scale": 0.85, "name": "GARGANTUA-0"},
	]

func generate_world(seed_val: int = 42077) -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_val

	var total = COLS * ROWS
	tile_kind.resize(total)
	tile_hp.resize(total)
	tile_max_hp.resize(total)
	was_cavern.resize(total)
	tile_ore.resize(total)

	for r in range(ROWS):
		for c in range(COLS):
			var idx = r * COLS + c
			tile_ore[idx] = ""
			was_cavern[idx] = 0
			if r == 0:
				tile_kind[idx] = TileKind.SURFACE
				tile_hp[idx] = 12.0
				tile_max_hp[idx] = 12.0
			elif r >= MAGMA_START_ROW:
				tile_kind[idx] = TileKind.MAGMA
				tile_hp[idx] = 9999.0
				tile_max_hp[idx] = 9999.0
			else:
				tile_kind[idx] = TileKind.ROCK
				var depth_hp = 10.0 + float(r) * 1.4
				tile_hp[idx] = depth_hp
				tile_max_hp[idx] = depth_hp

	# Carve scenic subterranean caverns matching concept art cross-section (leaving starter plateau solid beneath row 0)
	var cavern_seeds = [
		Vector3(24, 7, 3.6),
		Vector3(34, 11, 4.0),
		Vector3(49, 9, 4.2),
		Vector3(59, 6, 3.3),
		Vector3(41, 17, 4.8),
		Vector3(20, 16, 4.0),
		Vector3(65, 16, 4.2),
	]
	for cv in cavern_seeds:
		var cx = int(cv.x)
		var cy = int(cv.y)
		var rad = cv.z
		for r in range(maxi(2, cy - 5), mini(MAGMA_START_ROW - 1, cy + 5)):
			for c in range(maxi(2, cx - 7), mini(COLS - 2, cx + 7)):
				var d = Vector2((c - cx) * 0.72, (r - cy) * 1.05).length()
				if d <= rad + rng.randf_range(-0.5, 0.5):
					var idx = r * COLS + c
					tile_kind[idx] = TileKind.EMPTY
					was_cavern[idx] = 1
					tile_hp[idx] = 0.0

	# Guaranteed rich starter veins right beneath & beside Spawn Plateau (col 42)
	_paint_vein(rng, 39, 2, "fe", 2, 1, 16)
	_paint_vein(rng, 45, 2, "fe", 2, 1, 16)
	_paint_vein(rng, 36, 4, "cu", 1, 1, 14)
	_paint_vein(rng, 48, 4, "cu", 1, 1, 14)
	_paint_vein(rng, 42, 6, "si", 1, 1, 14)
	_paint_vein(rng, 44, 12, "ti", 2, 1, 18)

	# Distributed natural mineral pockets across subterranean strata
	for _i in range(11):
		var c = rng.randi_range(4, COLS - 5)
		var r = rng.randi_range(1, 13)
		_paint_vein(rng, c, r, "fe", 1, 1, 14)
	for _i in range(9):
		var c = rng.randi_range(4, COLS - 5)
		var r = rng.randi_range(2, 16)
		_paint_vein(rng, c, r, "cu", 1, 1, 14)
	for _i in range(7):
		var c = rng.randi_range(4, COLS - 5)
		var r = rng.randi_range(5, 20)
		_paint_vein(rng, c, r, "si", 1, 1, 14)
	for _i in range(6):
		var c = rng.randi_range(4, COLS - 5)
		var r = rng.randi_range(10, 22)
		_paint_vein(rng, c, r, "ti", 1, 1, 18)

	# Orbital Asteroids (harvestable by player & Swarm HARVEST doctrine)
	asteroids.clear()
	var ore_cycle = ["fe", "cu", "si", "ti"]
	for i in range(22):
		var ax = rng.randf_range(240.0, WORLD_WIDTH - 240.0)
		var ay = rng.randf_range(-920.0, -340.0)
		var otype = ore_cycle[i % ore_cycle.size()]
		asteroids.append({
			"pos": Vector2(ax, ay),
			"ore": otype,
			"hp": 120.0,
			"max_hp": 120.0,
			"radius": rng.randf_range(20.0, 30.0),
			"rot": rng.randf_range(0.0, TAU),
		})
	queue_redraw()

func _paint_vein(rng: RandomNumberGenerator, center_c: int, center_r: int, ore: String, rx: int, ry: int, hp_bonus: int) -> void:
	for r in range(maxi(1, center_r - ry), mini(MAGMA_START_ROW, center_r + ry + 1)):
		for c in range(maxi(1, center_c - rx), mini(COLS - 1, center_c + rx + 1)):
			if abs(c - center_c) + abs(r - center_r) <= rx + ry - rng.randi_range(0, 1):
				var idx = r * COLS + c
				if tile_kind[idx] == TileKind.ROCK or tile_kind[idx] == TileKind.EMPTY:
					tile_kind[idx] = TileKind.ROCK
					tile_ore[idx] = ore
					tile_max_hp[idx] = float(10 + r + hp_bonus)
					tile_hp[idx] = tile_max_hp[idx]

func in_bounds(c: int, r: int) -> bool:
	return c >= 0 and c < COLS and r >= 0 and r < ROWS

func world_to_tile(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / float(TILE_SIZE)), floori(pos.y / float(TILE_SIZE)))

func tile_to_world_center(c: int, r: int) -> Vector2:
	return Vector2((float(c) + 0.5) * TILE_SIZE, (float(r) + 0.5) * TILE_SIZE)

func is_solid(c: int, r: int) -> bool:
	if not in_bounds(c, r):
		return false
	return tile_kind[r * COLS + c] != TileKind.EMPTY

func get_kind(c: int, r: int) -> int:
	if not in_bounds(c, r):
		return TileKind.EMPTY
	return tile_kind[r * COLS + c]

func get_ore(c: int, r: int) -> String:
	if not in_bounds(c, r):
		return ""
	return tile_ore[r * COLS + c]

func damage_tile(c: int, r: int, power: float, track_player_popup: bool = true) -> Dictionary:
	var result = {"hit": false, "destroyed": false, "ore": "", "amount": 0}
	if not in_bounds(c, r):
		return result
	var idx = r * COLS + c
	if tile_kind[idx] == TileKind.EMPTY or tile_kind[idx] == TileKind.MAGMA:
		return result

	result["hit"] = true
	tile_hp[idx] -= power
	var ore_name = tile_ore[idx]
	var center = tile_to_world_center(c, r)

	# Continuous chip extraction every hit on ore veins so mining feels rewarding!
	if ore_name != "" and randf() < 0.35:
		GameState.add_res(ore_name, 1, track_player_popup)
		result["ore"] = ore_name
		result["amount"] = 1

	spawn_spark_burst(center, _ore_color(ore_name), 3)

	if tile_hp[idx] <= 0.0:
		tile_kind[idx] = TileKind.EMPTY
		was_cavern[idx] = 1
		result["destroyed"] = true
		if ore_name != "":
			var burst = 5 + int(r / 4)
			GameState.add_res(ore_name, burst, track_player_popup)
			result["ore"] = ore_name
			result["amount"] += burst
			tile_ore[idx] = ""
			spawn_world_popup(center, "+%d %s" % [burst, ore_name.to_upper()], _ore_color(ore_name))
		else:
			# Rock gives 1 Fe scrap reliably on break!
			GameState.add_res("fe", 2, track_player_popup)
			result["ore"] = "fe"
			result["amount"] += 2
			spawn_world_popup(center, "+2 FE", Color(0.55, 0.85, 1.0))
		spawn_spark_burst(center, _ore_color(ore_name), 9)
		queue_redraw()
	return result

func mine_asteroid_at(world_pos: Vector2, power: float, max_dist: float = 160.0) -> Dictionary:
	var best_idx = -1
	var best_d = max_dist
	for i in range(asteroids.size()):
		var a = asteroids[i]
		if a["hp"] <= 0.0:
			continue
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
	if randf() < 0.45:
		GameState.add_res(ore_name, 1, true)
	if ast["hp"] <= 0.0:
		var yield_amt = 12
		GameState.add_res(ore_name, yield_amt, true)
		spawn_world_popup(ast["pos"], "+%d %s" % [yield_amt, ore_name.to_upper()], _ore_color(ore_name))
		spawn_spark_burst(ast["pos"], Color(1.0, 0.8, 0.35), 14)
		# Respawn new distant asteroid so orbital harvesting stays alive
		ast["hp"] = ast["max_hp"]
		ast["pos"].x = clampf(ast["pos"].x + randf_range(-420.0, 420.0), 180.0, WORLD_WIDTH - 180.0)
		ast["pos"].y = randf_range(-980.0, -380.0)
	return {"hit": true, "pos": ast["pos"], "ore": ore_name}

func find_nearest_mine_target(world_pos: Vector2, max_range: float = 135.0) -> Dictionary:
	# Check asteroids in orbit first if above surface
	if world_pos.y < -60.0:
		var best_ast = null
		var best_d = max_range * 1.3
		for a in asteroids:
			var d = a["pos"].distance_to(world_pos)
			if d < best_d:
				best_d = d
				best_ast = a
		if best_ast != null:
			return {"type": "asteroid", "pos": best_ast["pos"]}

	# Check solid ore tiles first, then rock tiles in radius
	var tc = world_to_tile(world_pos)
	var rad = int(ceil(max_range / float(TILE_SIZE)))
	var best_ore_dist = 999999.0
	var best_ore_tile = Vector2i(-1, -1)
	var best_rock_dist = 999999.0
	var best_rock_tile = Vector2i(-1, -1)

	for r in range(maxi(0, tc.y - rad), mini(MAGMA_START_ROW, tc.y + rad + 1)):
		for c in range(maxi(0, tc.x - rad), mini(COLS, tc.x + rad + 1)):
			if not is_solid(c, r):
				continue
			var d = tile_to_world_center(c, r).distance_to(world_pos)
			if d > max_range:
				continue
			if get_ore(c, r) != "":
				if d < best_ore_dist:
					best_ore_dist = d
					best_ore_tile = Vector2i(c, r)
			elif r > 0: # Avoid accidentally punching holes through flat factory floor unless targeted directly
				if d < best_rock_dist:
					best_rock_dist = d
					best_rock_tile = Vector2i(c, r)

	if best_ore_tile.x >= 0:
		return {"type": "tile", "tile": best_ore_tile, "pos": tile_to_world_center(best_ore_tile.x, best_ore_tile.y)}
	if best_rock_tile.x >= 0:
		return {"type": "tile", "tile": best_rock_tile, "pos": tile_to_world_center(best_rock_tile.x, best_rock_tile.y)}
	return {}

func spawn_spark_burst(pos: Vector2, col: Color, count: int = 6) -> void:
	if particles.size() > 260:
		return
	for _i in range(count):
		var ang = randf_range(0.0, TAU)
		var spd = randf_range(28.0, 120.0)
		particles.append({
			"pos": pos + Vector2(randf_range(-4.0, 4.0), randf_range(-4.0, 4.0)),
			"vel": Vector2(cos(ang), sin(ang)) * spd,
			"life": randf_range(0.22, 0.55),
			"max_life": 0.55,
			"size": randf_range(2.0, 4.0),
			"col": col,
		})

func spawn_smoke_puff(pos: Vector2) -> void:
	if particles.size() > 260:
		return
	particles.append({
		"pos": pos + Vector2(randf_range(-3.0, 3.0), 0.0),
		"vel": Vector2(randf_range(8.0, 22.0), randf_range(-28.0, -45.0)),
		"life": 1.1,
		"max_life": 1.1,
		"size": randf_range(4.0, 7.0),
		"col": Color(0.55, 0.60, 0.68, 0.55),
	})

func spawn_world_popup(pos: Vector2, text: String, col: Color) -> void:
	world_popups.append({
		"pos": pos,
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
	for i in range(particles.size() - 1, -1, -1):
		var p = particles[i]
		p["pos"] += p["vel"] * delta
		p["vel"] *= 0.95
		p["life"] -= delta
		if p["life"] <= 0.0:
			particles.remove_at(i)
	for i in range(world_popups.size() - 1, -1, -1):
		var w = world_popups[i]
		w["pos"].y -= 22.0 * delta
		w["life"] -= delta
		if w["life"] <= 0.0:
			world_popups.remove_at(i)
	queue_redraw()

func _draw() -> void:
	# Determine visible world rect via CanvasTransform so off-screen tiles are culled cleanly
	var vrect = get_viewport_rect()
	var inv_xform = get_canvas_transform().affine_inverse()
	var tl = inv_xform * Vector2.ZERO
	var br = inv_xform * vrect.size
	var min_x = minf(tl.x, br.x) - 120.0
	var max_x = maxf(tl.x, br.x) + 120.0
	var min_y = minf(tl.y, br.y) - 120.0
	var max_y = maxf(tl.y, br.y) + 120.0

	# 1. Atmospheric Sky -> Deep Space vertical gradient bands above surface
	draw_rect(Rect2(-600.0, -2400.0, WORLD_WIDTH + 1200.0, 2400.0), Color(0.025, 0.04, 0.085, 1.0))
	if max_y > -520.0:
		draw_rect(Rect2(-600.0, -520.0, WORLD_WIDTH + 1200.0, 280.0), Color(0.06, 0.11, 0.21, 0.72))
		draw_rect(Rect2(-600.0, -240.0, WORLD_WIDTH + 1200.0, 160.0), Color(0.10, 0.18, 0.32, 0.78))
		draw_rect(Rect2(-600.0, -80.0, WORLD_WIDTH + 1200.0, 80.0), Color(0.15, 0.26, 0.42, 0.85))

	# 2. Starfield in visible rect
	for st in stars:
		var sp: Vector2 = st["pos"]
		if sp.x < min_x or sp.x > max_x or sp.y < min_y or sp.y > max_y:
			continue
		var twinkle = 0.5 + 0.5 * sin(anim_time * 2.1 + st["phase"])
		var c: Color = st["tint"]
		c.a = 0.35 + 0.65 * twinkle
		draw_rect(Rect2(sp, Vector2(st["size"], st["size"])), c)

	# 3. Distant Planets & Celestials high in orbit
	var font = ThemeDB.fallback_font
	for b in backdrop_bodies:
		var bp: Vector2 = b["pos"]
		if bp.x < min_x - 260 or bp.x > max_x + 260 or bp.y < min_y - 260 or bp.y > max_y + 260:
			continue
		var tex: Texture2D = tex_celestials.get(b["tex"], null)
		if tex:
			var sz = tex.get_size() * b["scale"]
			draw_texture_rect(tex, Rect2(bp - sz * 0.5, sz), false)
			if font:
				draw_string(font, bp + Vector2(-sz.x * 0.3, sz.y * 0.5 + 14.0), b["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.55, 0.78, 0.96, 0.72))

	# 4. Orbital Space Station Anchor (above landing zone at y = -680)
	var hub_pos = Vector2(SPAWN_COL * TILE_SIZE, -680.0)
	if tex_orbital_hub and hub_pos.y >= min_y - 120 and hub_pos.y <= max_y + 120:
		var hsz = tex_orbital_hub.get_size() * 1.35
		draw_texture_rect(tex_orbital_hub, Rect2(hub_pos - hsz * 0.5, hsz), false)
		if font:
			draw_string(font, hub_pos + Vector2(-58, hsz.y * 0.5 + 14.0), "ORBITAL SHIPYARD HUB", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.45, 0.92, 1.0, 0.85))

	# 5. Orbital Harvestable Asteroids
	var ast_tex: Texture2D = tex_celestials.get("asteroid", null)
	for a in asteroids:
		var ap: Vector2 = a["pos"]
		if ap.x < min_x - 60 or ap.x > max_x + 60 or ap.y < min_y - 60 or ap.y > max_y + 60:
			continue
		var r = a["radius"]
		if ast_tex:
			draw_texture_rect(ast_tex, Rect2(ap - Vector2(r, r), Vector2(r * 2.0, r * 2.0)), false, _ore_color(a["ore"]).lerp(Color.WHITE, 0.45))
		else:
			draw_circle(ap, r, _ore_color(a["ore"]))

	# 6. Dark subterranean planetary crust backdrop below y = 0
	if max_y > 0.0:
		draw_rect(Rect2(0.0, 0.0, WORLD_WIDTH, WORLD_HEIGHT), Color(0.035, 0.035, 0.055, 1.0))

	# 7. Tile Grid Rendering (culled to camera viewport)
	var c0 = maxi(0, floori(min_x / float(TILE_SIZE)))
	var c1 = mini(COLS - 1, floori(max_x / float(TILE_SIZE)))
	var r0 = maxi(0, floori(min_y / float(TILE_SIZE)))
	var r1 = mini(ROWS - 1, floori(max_y / float(TILE_SIZE)))

	for r in range(r0, r1 + 1):
		for c in range(c0, c1 + 1):
			var idx = r * COLS + c
			var k = tile_kind[idx]
			var rect = Rect2(c * TILE_SIZE, r * TILE_SIZE, TILE_SIZE, TILE_SIZE)

			if k == TileKind.EMPTY:
				# Recessed dug tunnel / cavern backwall contrasting with solid stone
				draw_rect(rect, Color(0.045, 0.052, 0.095, 1.0))
				if ((c + r) % 2) == 0:
					draw_rect(Rect2(rect.position + Vector2(6, 6), Vector2(4, 4)), Color(0.075, 0.085, 0.14, 0.65))
				continue

			if k == TileKind.SURFACE:
				draw_rect(rect, Color(0.24, 0.26, 0.32, 1.0))
				if tex_surface:
					draw_texture_rect(tex_surface, rect, false, Color(1.25, 1.25, 1.25, 1.0))
				# Crisp horizon rim highlight along surface top
				draw_line(rect.position, rect.position + Vector2(TILE_SIZE, 0), Color(0.45, 0.80, 0.96, 0.72), 2.0)
			elif k == TileKind.ROCK:
				var shade = clampf(1.0 - float(r) * 0.015, 0.65, 1.0)
				# Visible textured slate-stone base so strata & caverns read crisply like concept art!
				var stone_col = Color(0.19 * shade, 0.185 * shade, 0.24 * shade, 1.0)
				draw_rect(rect, stone_col)
				if tex_rock:
					draw_texture_rect(tex_rock, rect, false, Color(1.4 * shade, 1.38 * shade, 1.48 * shade, 0.92))
				# Subtle cavern-wall bevel rim wherever rock borders open air
				var rim = Color(0.38, 0.42, 0.56, 0.7)
				if not is_solid(c, r - 1):
					draw_line(rect.position, rect.position + Vector2(TILE_SIZE, 0), rim, 2.0)
				if not is_solid(c, r + 1):
					draw_line(rect.position + Vector2(0, TILE_SIZE), rect.position + Vector2(TILE_SIZE, TILE_SIZE), Color(0.1, 0.11, 0.16, 0.9), 2.0)
				if not is_solid(c - 1, r):
					draw_line(rect.position, rect.position + Vector2(0, TILE_SIZE), rim, 2.0)
				if not is_solid(c + 1, r):
					draw_line(rect.position + Vector2(TILE_SIZE, 0), rect.position + Vector2(TILE_SIZE, TILE_SIZE), rim, 2.0)
				# Damage cracks when partially mined
				var hp_ratio = tile_hp[idx] / maxf(1.0, tile_max_hp[idx])
				if hp_ratio < 0.9:
					draw_rect(Rect2(rect.position + Vector2(4, 4), Vector2(24, 24)), Color(0.0, 0.0, 0.0, 0.4 * (1.0 - hp_ratio)))
					draw_rect(rect, Color(1.0, 0.85, 0.4, 0.45), false, 1.0)
			elif k == TileKind.MAGMA:
				var pulse = 0.86 + 0.14 * sin(anim_time * 3.0 + float(c) * 0.6)
				draw_rect(rect, Color(0.55, 0.16, 0.05, 1.0))
				if tex_magma:
					draw_texture_rect(tex_magma, rect, false, Color(1.15, 1.1 * pulse, 0.95, 1.0))

			# Glowing Underground Mineral Veins (Fe, Cu, Si, Ti)
			var ore = tile_ore[idx]
			if ore != "":
				var oc = _ore_color(ore)
				var otex: Texture2D = tex_ores.get(ore, null)
				if otex:
					draw_texture_rect(otex, Rect2(rect.position + Vector2(6, 6), Vector2(20, 20)), false)
				# Glowing crystal flecks for instant readability
				var glow_a = 0.5 + 0.3 * sin(anim_time * 2.8 + float(c + r))
				draw_rect(Rect2(rect.position + Vector2(5, 7), Vector2(4, 6)), Color(oc.r, oc.g, oc.b, glow_a))
				draw_rect(Rect2(rect.position + Vector2(21, 19), Vector2(5, 5)), Color(oc.r, oc.g, oc.b, glow_a))

	# 8. Particles (drill sparks, factory smoke puffs)
	for p in particles:
		var a = clampf(p["life"] / maxf(0.01, p["max_life"]), 0.0, 1.0)
		var col: Color = p["col"]
		col.a *= a
		var s = p["size"]
		draw_rect(Rect2(p["pos"] - Vector2(s * 0.5, s * 0.5), Vector2(s, s)), col)

	# 9. World Popups (+N Fe, Red missing text, etc.)
	if font:
		for wp in world_popups:
			var a = clampf(wp["life"] / maxf(0.01, wp["max_life"]), 0.0, 1.0)
			var c: Color = wp["col"]
			c.a = a
			var tpos = wp["pos"] + Vector2(-28, 0)
			draw_string(font, tpos + Vector2(1, 1), wp["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0, 0, 0, a * 0.85))
			draw_string(font, tpos, wp["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, c)
