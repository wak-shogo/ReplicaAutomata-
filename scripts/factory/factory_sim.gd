extends Node2D
class_name FactorySim

# ==============================================================================
# STAR REPLICA: AUTOMA - FACTORY, CONVEYOR LOGISTICS & MASS DRIVER SIMULATION
# Renders animated 16-bit sprite sheets, conveyor belt items, smoke stacks,
# laser turrets, blueprint ghost slots, and luminous Mass Driver launches.
# ==============================================================================

const TILE_SIZE: int = 32

var world: PlanetWorld
var swarm_sim: Node2D
var player: Node2D

# Placed Buildings: Array of Dictionaries
# {id, tile: Vector2i, size: Vector2i, dir: int, timer: float, active: bool, smoke_t: float, charge_t: float}
var buildings: Array[Dictionary] = []
# Occupancy map: "c,r" -> building index
var occupied: Dictionary = {}

# Moving items on belts/lifts: {c: int, r: int, t: float, item: String}
var belt_items: Array[Dictionary] = []

# Launched probes flying from Mass Driver into Orbit: {pos: Vector2, vel: Vector2, target_y: float, trail: Array[Vector2]}
var projectiles: Array[Dictionary] = []

# Defensive turret beam FX: {from: Vector2, to: Vector2, life: float}
var laser_beams: Array[Dictionary] = []

# Holographic blueprint candidate slots currently shown
var blueprint_slots: Array[Dictionary] = []

# Sprite Textures & Item Icons
var sprite_textures: Dictionary = {}
var item_icons: Dictionary = {}
var anim_time: float = 0.0
var hover_tile: Vector2i = Vector2i(-999, -999)

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_load_assets()
	if GameState.blueprint_selected.is_connected(_on_tool_changed) == false:
		GameState.blueprint_selected.connect(_on_tool_changed)

func setup(p_world: PlanetWorld, p_swarm: Node2D, p_player: Node2D) -> void:
	world = p_world
	swarm_sim = p_swarm
	player = p_player
	refresh_blueprint_slots()

func _load_assets() -> void:
	for bid in GameState.BUILDINGS.keys():
		var info = GameState.BUILDINGS[bid]
		var sp_path: String = info.get("sheet", "")
		if sp_path != "" and ResourceLoader.exists(sp_path):
			sprite_textures[bid] = load(sp_path)

	item_icons = {
		"fe": load("res://assets/ui/fe.png"),
		"cu": load("res://assets/ui/cu.png"),
		"si": load("res://assets/ui/si.png"),
		"ti": load("res://assets/ui/ti.png"),
		"plate_fe": load("res://assets/ui/item_plate_fe.png"),
		"wire_cu": load("res://assets/ui/item_wire_cu.png"),
		"wafer_si": load("res://assets/ui/item_silicon_wafer.png"),
		"circuit": load("res://assets/ui/item_circuit.png"),
		"alloy": load("res://assets/ui/item_alloy.png"),
		"probe": load("res://assets/ui/item_drone_unit.png"),
	}

func _on_tool_changed(_tool_id: String) -> void:
	refresh_blueprint_slots()
	queue_redraw()

func clear_factory() -> void:
	buildings.clear()
	occupied.clear()
	belt_items.clear()
	projectiles.clear()
	laser_beams.clear()
	_recompute_power_grid()
	refresh_blueprint_slots()
	queue_redraw()

func _key(c: int, r: int) -> String:
	return "%d,%d" % [c, r]

func is_area_free(origin: Vector2i, sz: Vector2i) -> bool:
	for dy in range(sz.y):
		for dx in range(sz.x):
			if occupied.has(_key(origin.x + dx, origin.y + dy)):
				return false
	return true

func can_place_building(bid: String, origin: Vector2i) -> bool:
	if not world or not GameState.BUILDINGS.has(bid):
		return false
	var info = GameState.BUILDINGS[bid]
	var sz: Vector2i = info["size"]
	if origin.x < 1 or origin.x + sz.x >= PlanetWorld.COLS - 1:
		return false
	if not is_area_free(origin, sz):
		return false

	var rule: String = info["place"]
	match rule:
		"SURFACE":
			# Surface buildings sit immediately above row 0 (origin.y + sz.y == 0) with solid crust below
			if origin.y + sz.y != 0:
				return false
			for dx in range(sz.x):
				if not world.is_solid(origin.x + dx, 0):
					return false
			return true
		"SURFACE_OR_CAVERN":
			if origin.y + sz.y == 0:
				for dx in range(sz.x):
					if not world.is_solid(origin.x + dx, 0):
						return false
				return true
			# Underground cleared cavern resting on solid rock floor
			if origin.y >= 1 and origin.y + sz.y < PlanetWorld.MAGMA_START_ROW:
				for dy in range(sz.y):
					for dx in range(sz.x):
						if world.is_solid(origin.x + dx, origin.y + dy):
							return false
				for dx in range(sz.x):
					if not world.is_solid(origin.x + dx, origin.y + sz.y):
						return false
				return true
			return false
		"ORE_OR_ROCK":
			# Mining Drill snaps onto solid ore/rock tiles (origin.y >= 1) OR surface horizon resting on row 0
			if origin.y >= 1 and origin.y + sz.y <= PlanetWorld.MAGMA_START_ROW:
				var has_solid = false
				for dy in range(sz.y):
					for dx in range(sz.x):
						if world.is_solid(origin.x + dx, origin.y + dy):
							has_solid = true
				return has_solid
			elif origin.y + sz.y == 0:
				return world.is_solid(origin.x, 0)
			return false
		"DEEP_ROCK":
			# Geothermal plant sits deep underground (row >= 14 near magma!)
			if origin.y >= 14 and origin.y + sz.y <= PlanetWorld.MAGMA_START_ROW:
				for dy in range(sz.y):
					for dx in range(sz.x):
						if world.is_solid(origin.x + dx, origin.y + dy):
							return false
				return true
			return false
		"ANY_CLEAR":
			# Belts, lifts & inserters can run across surface (row = -1), inside caverns, or cleanly through underground shafts
			return origin.y >= -1 and origin.y < PlanetWorld.MAGMA_START_ROW
	return false

func get_snap_origin_for_cursor(bid: String, world_pos: Vector2) -> Vector2i:
	if not GameState.BUILDINGS.has(bid):
		return Vector2i(-999, -999)
	var info = GameState.BUILDINGS[bid]
	var sz: Vector2i = info["size"]
	var tc = world.world_to_tile(world_pos)
	var rule: String = info["place"]
	if rule == "SURFACE" or (rule == "SURFACE_OR_CAVERN" and world_pos.y <= 16.0):
		return Vector2i(tc.x - sz.x / 2, -sz.y)
	if rule == "ANY_CLEAR" and world_pos.y <= 8.0 and world_pos.y >= -48.0:
		return Vector2i(tc.x, -1)
	return Vector2i(tc.x - sz.x / 2, tc.y - sz.y + 1)

func refresh_blueprint_slots() -> void:
	blueprint_slots.clear()
	if not world:
		return
	var bid = GameState.selected_tool
	if not GameState.BUILDINGS.has(bid):
		return
	var info = GameState.BUILDINGS[bid]
	var sz: Vector2i = info["size"]
	var rule: String = info["place"]

	var center_col = PlanetWorld.SPAWN_COL
	if player:
		center_col = clampi(floori(player.position.x / float(TILE_SIZE)), 4, PlanetWorld.COLS - 5)

	if rule in ["SURFACE", "SURFACE_OR_CAVERN"]:
		var col_min = maxi(6, center_col - 18)
		var col_max = mini(PlanetWorld.COLS - sz.x - 2, center_col + 18)
		var step = maxi(1, sz.x)
		for c in range(col_min, col_max, step):
			var orig = Vector2i(c, -sz.y)
			if can_place_building(bid, orig):
				blueprint_slots.append({"origin": orig, "size": sz})
	if rule == "ORE_OR_ROCK":
		# Highlight nearby ore vein clusters!
		var p_tile = world.world_to_tile(player.position) if player else Vector2i(center_col, 0)
		for r in range(maxi(1, p_tile.y - 6), mini(PlanetWorld.MAGMA_START_ROW - sz.y, p_tile.y + 8)):
			for c in range(maxi(2, center_col - 14), mini(PlanetWorld.COLS - 3, center_col + 14), 2):
				if world.get_ore(c, r) != "" and can_place_building(bid, Vector2i(c, r)):
					blueprint_slots.append({"origin": Vector2i(c, r), "size": sz})
					if blueprint_slots.size() >= 18:
						return
	elif rule == "DEEP_ROCK":
		for r in range(18, PlanetWorld.MAGMA_START_ROW - sz.y + 1, 2):
			for c in range(maxi(4, center_col - 12), mini(PlanetWorld.COLS - 4, center_col + 12), 3):
				var orig = Vector2i(c, r)
				if can_place_building(bid, orig):
					blueprint_slots.append({"origin": orig, "size": sz})
	elif rule == "ANY_CLEAR":
		# Surface horizontal belt snaps around center + vertical lift slots under surface
		for c in range(maxi(4, center_col - 12), mini(PlanetWorld.COLS - 4, center_col + 12)):
			var orig = Vector2i(c, -1)
			if can_place_building(bid, orig):
				blueprint_slots.append({"origin": orig, "size": sz})
		if bid == "lift":
			for r in range(0, 12):
				for c in range(maxi(6, center_col - 8), mini(PlanetWorld.COLS - 6, center_col + 8), 3):
					var orig = Vector2i(c, r)
					if can_place_building(bid, orig):
						blueprint_slots.append({"origin": orig, "size": sz})

func try_handle_click_at(world_pos: Vector2) -> bool:
	var tool_id = GameState.selected_tool
	if tool_id == "demolish":
		return try_demolish_at(world_pos)
	if not GameState.BUILDINGS.has(tool_id):
		return false

	# First check if click hits any active displayed blueprint slot
	var clicked_origin = Vector2i(-999, -999)
	for sl in blueprint_slots:
		var o: Vector2i = sl["origin"]
		var s: Vector2i = sl["size"]
		var rect = Rect2(o.x * TILE_SIZE, o.y * TILE_SIZE, s.x * TILE_SIZE, s.y * TILE_SIZE)
		if rect.grow(6.0).has_point(world_pos):
			clicked_origin = o
			break

	if clicked_origin.x == -999:
		var snap = get_snap_origin_for_cursor(tool_id, world_pos)
		if can_place_building(tool_id, snap):
			clicked_origin = snap

	if clicked_origin.x == -999:
		return false

	return try_place_building(tool_id, clicked_origin)

func try_place_building(bid: String, origin: Vector2i) -> bool:
	if not GameState.BUILDINGS.has(bid):
		return false
	var info = GameState.BUILDINGS[bid]
	var sz: Vector2i = info["size"]
	var center = Vector2((origin.x + sz.x * 0.5) * TILE_SIZE, (origin.y + sz.y * 0.5) * TILE_SIZE)

	var req_drones = int(info.get("req_drones", 0))
	if GameState.drones < req_drones:
		if world:
			world.spawn_world_popup(center, "NEED %d DRONES" % req_drones, Color(1.0, 0.25, 0.25))
		GameState.emit_signal("log_event", "%s requires %d Fabricator Drones!" % [info["name"], req_drones], "error")
		AudioSynth.play_synth("error")
		return false

	if not can_place_building(bid, origin):
		if world:
			world.spawn_world_popup(center, "INVALID SLOT", Color(1.0, 0.35, 0.25))
		AudioSynth.play_synth("error")
		return false

	var cost: Dictionary = info["cost"]
	if not GameState.spend_cost(cost):
		var miss = GameState.get_missing_text(cost)
		if world:
			world.spawn_world_popup(center, miss, Color(1.0, 0.22, 0.22))
		GameState.emit_signal("log_event", miss, "error")
		AudioSynth.play_synth("error")
		return false

	var b_idx = buildings.size()
	var dir = 1 if (GameState.build_rotation % 4) != 2 else -1
	buildings.append({
		"id": bid,
		"tile": origin,
		"size": sz,
		"dir": dir,
		"timer": 0.0,
		"active": true,
		"smoke_t": 0.0,
		"charge_t": 0.0,
		"frame": 0,
		"ore_target": _detect_drill_ore(origin, sz) if bid == "drill" else "",
	})
	for dy in range(sz.y):
		for dx in range(sz.x):
			occupied[_key(origin.x + dx, origin.y + dy)] = b_idx

	if bid in GameState.megastructures:
		GameState.megastructures[bid] = true
		AudioSynth.play_synth("mega")
		GameState.emit_signal("log_event", "MEGASTRUCTURE ONLINE: %s!" % info["name"], "good")
	else:
		AudioSynth.play_synth("build")
		GameState.emit_signal("log_event", "Built %s" % info["name"], "good")

	if world:
		world.spawn_spark_burst(center, Color(0.25, 0.9, 1.0), 10)
	_recompute_power_grid()
	refresh_blueprint_slots()
	queue_redraw()
	return true

func try_demolish_at(world_pos: Vector2) -> bool:
	var tc = world.world_to_tile(world_pos)
	var k = _key(tc.x, tc.y)
	if not occupied.has(k):
		return false
	var idx: int = occupied[k]
	var b = buildings[idx]
	var bid: String = b["id"]
	var info = GameState.BUILDINGS.get(bid, {})
	var cost: Dictionary = info.get("cost", {})
	for rname in cost.keys():
		GameState.add_res(rname, maxi(1, int(cost[rname]) / 2))

	# Remove & re-index occupancy cleanly
	buildings.remove_at(idx)
	occupied.clear()
	for bi in range(buildings.size()):
		var bb = buildings[bi]
		for dy in range(bb["size"].y):
			for dx in range(bb["size"].x):
				occupied[_key(bb["tile"].x + dx, bb["tile"].y + dy)] = bi

	_recompute_power_grid()
	refresh_blueprint_slots()
	AudioSynth.play_synth("pop")
	GameState.emit_signal("log_event", "Salvaged %s (50%% refunded)" % info.get("name", bid), "info")
	queue_redraw()
	return true

func _detect_drill_ore(origin: Vector2i, sz: Vector2i) -> String:
	if not world:
		return "fe"
	for dy in range(sz.y + 1):
		for dx in range(sz.x):
			var o = world.get_ore(origin.x + dx, origin.y + dy)
			if o != "":
				return o
	return "fe"

func _recompute_power_grid() -> void:
	var gen = 15.0 + float(GameState.drones) * 3.0
	var use = 0.0
	for b in buildings:
		var info = GameState.BUILDINGS.get(b["id"], {})
		var p = float(info.get("power", 0.0))
		if p > 0.0:
			gen += p
		elif p < 0.0:
			use += -p
	GameState.power_gen = gen
	GameState.power_use = use
	GameState.power_ratio = 1.0 if use <= 0.01 else clampf(gen / use, 0.25, 1.25)
	GameState.emit_signal("state_updated")

func _has_building_nearby_or_depot(bid_filter: Array) -> bool:
	for b in buildings:
		if b["id"] in bid_filter:
			return true
	return false

func _spawn_belt_item(c: int, r: int, item_name: String) -> void:
	if belt_items.size() > 160:
		return
	belt_items.append({"c": c, "r": r, "t": 0.0, "item": item_name})

func _find_adjacent_belt(origin: Vector2i, sz: Vector2i) -> Vector2i:
	for dy in range(-1, sz.y + 1):
		for dx in range(-1, sz.x + 1):
			var c = origin.x + dx
			var r = origin.y + dy
			var k = _key(c, r)
			if occupied.has(k):
				var nb = buildings[occupied[k]]
				if nb["id"] in ["belt", "lift"]:
					return Vector2i(c, r)
	return Vector2i(-999, -999)

func _process(delta: float) -> void:
	anim_time += delta
	if GameState.selected_tool in GameState.BUILDINGS:
		var mpos = get_global_mouse_position()
		hover_tile = get_snap_origin_for_cursor(GameState.selected_tool, mpos)

	var p_eff = GameState.power_ratio
	var has_elevator = GameState.megastructures["elevator"]
	var has_dyson = GameState.megastructures["dyson"]
	var printer_any_active = false

	# 1. Tick all factory buildings
	for i in range(buildings.size()):
		var b = buildings[i]
		var bid: String = b["id"]
		b["timer"] += delta * p_eff
		b["smoke_t"] += delta

		match bid:
			"drill":
				b["frame"] = int(anim_time * 9.0) % 4
				if b["timer"] >= 1.4:
					b["timer"] = 0.0
					var ore_k: String = b.get("ore_target", "fe")
					if ore_k == "": ore_k = "fe"
					GameState.add_res(ore_k, 1, false)
					var belt_pt = _find_adjacent_belt(b["tile"], b["size"])
					if belt_pt.x != -999:
						_spawn_belt_item(belt_pt.x, belt_pt.y, ore_k)
			"belt":
				b["frame"] = int(anim_time * 8.0) % 4
			"lift":
				b["frame"] = int(anim_time * 8.0) % 4
			"inserter":
				b["frame"] = int(anim_time * 6.0) % 4
			"smelter":
				b["frame"] = int(anim_time * 5.0) % 4
				if b["timer"] >= 1.6:
					b["timer"] = 0.0
					var produced = ""
					if GameState.fe >= 1:
						GameState.add_res("fe", -1)
						GameState.add_res("plate_fe", 1)
						produced = "plate_fe"
					elif GameState.cu >= 1:
						GameState.add_res("cu", -1)
						GameState.add_res("wire_cu", 1)
						produced = "wire_cu"
					elif GameState.si >= 1:
						GameState.add_res("si", -1)
						GameState.add_res("wafer_si", 1)
						produced = "wafer_si"
					if produced != "":
						var belt_pt = _find_adjacent_belt(b["tile"], b["size"])
						if belt_pt.x != -999:
							_spawn_belt_item(belt_pt.x, belt_pt.y, produced)
				if b["smoke_t"] >= 0.45 and world:
					b["smoke_t"] = 0.0
					world.spawn_smoke_puff(Vector2((b["tile"].x + 0.4) * TILE_SIZE, b["tile"].y * TILE_SIZE))
			"assembler":
				b["frame"] = int(anim_time * 6.0) % 4
				if b["timer"] >= 1.8:
					b["timer"] = 0.0
					var made = ""
					if GameState.wire_cu >= 1 and GameState.wafer_si >= 1:
						GameState.add_res("wire_cu", -1)
						GameState.add_res("wafer_si", -1)
						GameState.add_res("circuit", 1)
						made = "circuit"
					elif GameState.plate_fe >= 1 and GameState.ti >= 1:
						GameState.add_res("plate_fe", -1)
						GameState.add_res("ti", -1)
						GameState.add_res("alloy", 1)
						made = "alloy"
					elif GameState.cu >= 2 and GameState.si >= 1:
						GameState.add_res("cu", -2)
						GameState.add_res("si", -1)
						GameState.add_res("circuit", 1)
						made = "circuit"
					if made != "":
						var belt_pt = _find_adjacent_belt(b["tile"], b["size"])
						if belt_pt.x != -999:
							_spawn_belt_item(belt_pt.x, belt_pt.y, made)
			"printer":
				printer_any_active = true
				b["frame"] = int(anim_time * 7.0) % 4
				var speed = (0.38 if not has_elevator else 0.75) * (1.3 if has_dyson else 1.0)
				if b["timer"] >= 1.0 / speed:
					# Print 1 Replica Probe using Plate + Circuit or fallback raw cost
					var can_print = false
					if GameState.plate_fe >= 2 and GameState.circuit >= 1:
						GameState.add_res("plate_fe", -2)
						GameState.add_res("circuit", -1)
						can_print = true
					elif GameState.fe >= 6 and GameState.cu >= 2:
						GameState.add_res("fe", -6)
						GameState.add_res("cu", -2)
						can_print = true
					if can_print:
						b["timer"] = 0.0
						GameState.add_res("probe_stock", 1)
						GameState.printer_progress = 1.0
						var belt_pt = _find_adjacent_belt(b["tile"], b["size"])
						if belt_pt.x != -999:
							_spawn_belt_item(belt_pt.x, belt_pt.y, "probe")
					else:
						GameState.printer_progress = 0.15
				else:
					GameState.printer_progress = clampf(b["timer"] * speed, 0.0, 0.99)
				if b["smoke_t"] >= 0.35 and world:
					b["smoke_t"] = 0.0
					world.spawn_smoke_puff(Vector2((b["tile"].x + 2.2) * TILE_SIZE, b["tile"].y * TILE_SIZE))
			"mass_driver":
				if b["charge_t"] > 0.0:
					b["charge_t"] -= delta
					var prog = 1.0 - (b["charge_t"] / 0.9)
					b["frame"] = clampi(int(prog * 4.0), 0, 3)
					if b["charge_t"] <= 0.0:
						_fire_mass_driver(b)
				elif GameState.probe_stock >= 1 and b["timer"] >= 1.2:
					GameState.add_res("probe_stock", -1)
					b["timer"] = 0.0
					b["charge_t"] = 0.9
					b["frame"] = 1
				else:
					b["frame"] = 0
			"turret":
				if b["timer"] >= 1.2 and swarm_sim and swarm_sim.has_method("find_nearest_hostile"):
					var tpos = Vector2((b["tile"].x + 0.5) * TILE_SIZE, b["tile"].y * TILE_SIZE)
					var h_pos = swarm_sim.find_nearest_hostile(tpos, 520.0)
					if h_pos != Vector2.ZERO:
						b["timer"] = 0.0
						swarm_sim.damage_hostile_near(h_pos, 35.0)
						laser_beams.append({"from": tpos + Vector2(0, -10), "to": h_pos, "life": 0.14})
						AudioSynth.play_synth("laser")

	GameState.printer_active = printer_any_active

	# 2. Animate visible belt / lift items
	for bi in range(belt_items.size() - 1, -1, -1):
		var it = belt_items[bi]
		it["t"] += delta * 2.2 * p_eff
		if it["t"] >= 1.0:
			it["t"] = 0.0
			var k = _key(it["c"], it["r"])
			if occupied.has(k):
				var b = buildings[occupied[k]]
				if b["id"] == "lift":
					it["r"] -= 1
				elif b["id"] == "belt":
					it["c"] += int(b["dir"])
				else:
					belt_items.remove_at(bi)
					continue
			else:
				belt_items.remove_at(bi)
				continue
			if not occupied.has(_key(it["c"], it["r"])):
				belt_items.remove_at(bi)

	# 3. Animate Mass Driver launched probes flying into orbit
	for pi in range(projectiles.size() - 1, -1, -1):
		var pr = projectiles[pi]
		pr["trail"].append(pr["pos"])
		if pr["trail"].size() > 14:
			pr["trail"].remove_at(0)
		pr["pos"] += pr["vel"] * delta
		pr["vel"].y -= 180.0 * delta
		if pr["pos"].y <= pr["target_y"]:
			var add_amt = 1
			if GameState.megastructures["elevator"]: add_amt += 1
			if GameState.megastructures["warpgate"]: add_amt += 2
			GameState.add_fleet_units(add_amt)
			GameState.total_launches += 1
			GameState.emit_signal("probe_launched", pr["pos"])
			if swarm_sim and swarm_sim.has_method("spawn_friendly_units"):
				swarm_sim.spawn_friendly_units(add_amt, pr["pos"])
			if world:
				world.spawn_spark_burst(pr["pos"], Color(0.25, 0.92, 1.0), 8)
				world.spawn_world_popup(pr["pos"], "+%d SWARM" % add_amt, Color(0.35, 0.95, 1.0))
			projectiles.remove_at(pi)

	# 4. Decay turret laser FX
	for li in range(laser_beams.size() - 1, -1, -1):
		laser_beams[li]["life"] -= delta
		if laser_beams[li]["life"] <= 0.0:
			laser_beams.remove_at(li)

	queue_redraw()

func _fire_mass_driver(b: Dictionary) -> void:
	var muzzle = Vector2((b["tile"].x + 3.4) * TILE_SIZE, (b["tile"].y + 0.35) * TILE_SIZE)
	projectiles.append({
		"pos": muzzle,
		"vel": Vector2(130.0, -540.0),
		"target_y": -640.0,
		"trail": [muzzle],
	})
	if world:
		world.spawn_spark_burst(muzzle, Color(0.55, 0.95, 1.0), 12)
	AudioSynth.play_synth("launch")

func _draw() -> void:
	var font = ThemeDB.fallback_font
	# 1. Draw placed buildings
	for b in buildings:
		var bid: String = b["id"]
		var info = GameState.BUILDINGS.get(bid, {})
		var sz: Vector2i = b["size"]
		var rect = Rect2(b["tile"].x * TILE_SIZE, b["tile"].y * TILE_SIZE, sz.x * TILE_SIZE, sz.y * TILE_SIZE)
		var tex: Texture2D = sprite_textures.get(bid, null)
		var frames = int(info.get("frames", 1))
		if tex:
			if frames > 1:
				var fw = float(tex.get_width()) / float(frames)
				var fh = float(tex.get_height())
				var f = clampi(int(b.get("frame", 0)), 0, frames - 1)
				var src = Rect2(f * fw, 0.0, fw, fh)
				var dest = rect
				if bid == "belt" and int(b.get("dir", 1)) < 0:
					dest.position.x += dest.size.x
					dest.size.x = -dest.size.x
				draw_texture_rect_region(tex, dest, src)
			else:
				draw_texture_rect(tex, rect, false)
		else:
			draw_rect(rect, Color(0.25, 0.45, 0.65))

	# 2. Draw visible conveyor/lift items
	for it in belt_items:
		var cx = (float(it["c"]) + 0.5) * TILE_SIZE
		var cy = (float(it["r"]) + 0.5) * TILE_SIZE
		var k = _key(it["c"], it["r"])
		if occupied.has(k):
			var b = buildings[occupied[k]]
			if b["id"] == "lift":
				cy = (float(it["r"]) + (1.0 - it["t"])) * TILE_SIZE
			elif b["id"] == "belt":
				cx = (float(it["c"]) + 0.1 + it["t"] * 0.8 * float(b["dir"])) * TILE_SIZE
		var icon: Texture2D = item_icons.get(it["item"], null)
		if icon:
			draw_texture_rect(icon, Rect2(cx - 7.0, cy - 7.0, 14.0, 14.0), false)
		else:
			draw_rect(Rect2(cx - 4.0, cy - 4.0, 8.0, 8.0), Color(0.3, 0.9, 1.0))

	# 3. Draw Holographic Blueprint Ghost slots when a build blueprint is selected!
	var sel = GameState.selected_tool
	if sel in GameState.BUILDINGS:
		var info = GameState.BUILDINGS[sel]
		var can_pay = GameState.can_afford(info["cost"]) and GameState.drones >= int(info.get("req_drones", 0))
		var pulse = 0.35 + 0.18 * sin(anim_time * 5.0)
		var g_col = Color(0.15, 0.9, 1.0, pulse) if can_pay else Color(1.0, 0.42, 0.25, pulse)
		var b_col = Color(0.35, 0.98, 1.0, 0.9) if can_pay else Color(1.0, 0.55, 0.3, 0.85)
		var ghost_tex: Texture2D = sprite_textures.get(sel, null)
		var frames = int(info.get("frames", 1))

		for sl in blueprint_slots:
			var o: Vector2i = sl["origin"]
			var s: Vector2i = sl["size"]
			var rect = Rect2(o.x * TILE_SIZE, o.y * TILE_SIZE, s.x * TILE_SIZE, s.y * TILE_SIZE)
			draw_rect(rect, Color(g_col.r, g_col.g, g_col.b, 0.22))
			if ghost_tex:
				if frames > 1:
					var fw = float(ghost_tex.get_width()) / float(frames)
					draw_texture_rect_region(ghost_tex, rect, Rect2(0, 0, fw, ghost_tex.get_height()), g_col)
				else:
					draw_texture_rect(ghost_tex, rect, false, g_col)
			draw_rect(rect, b_col, false, 1.5)

		# Snap highlight directly under cursor
		if hover_tile.x != -999 and can_place_building(sel, hover_tile):
			var sz: Vector2i = info["size"]
			var hrect = Rect2(hover_tile.x * TILE_SIZE, hover_tile.y * TILE_SIZE, sz.x * TILE_SIZE, sz.y * TILE_SIZE)
			draw_rect(hrect, Color(1.0, 1.0, 1.0, 0.95), false, 2.0)
			if font:
				var hint = "CLICK TO BUILD" if can_pay else GameState.get_missing_text(info["cost"])
				if GameState.drones < int(info.get("req_drones", 0)):
					hint = "REQ %d DRONES" % int(info["req_drones"])
				draw_string(font, hrect.position + Vector2(0, -6), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 1.0, 1.0) if can_pay else Color(1.0, 0.35, 0.35))

	# 4. Mass Driver Launched Projectiles
	for pr in projectiles:
		var pts: Array = pr["trail"]
		for ti in range(1, pts.size()):
			var a = float(ti) / float(pts.size())
			draw_line(pts[ti - 1], pts[ti], Color(0.35, 0.92, 1.0, a * 0.85), 2.5)
		draw_circle(pr["pos"], 4.5, Color(0.85, 0.98, 1.0))
		draw_circle(pr["pos"], 8.0, Color(0.25, 0.85, 1.0, 0.45))

	# 5. Defense Turret Laser Bolts
	for lb in laser_beams:
		draw_line(lb["from"], lb["to"], Color(0.3, 1.0, 0.85, 0.95), 2.2)

func to_dict() -> Dictionary:
	var arr: Array = []
	for b in buildings:
		arr.append({
			"id": b["id"],
			"cx": b["tile"].x,
			"cy": b["tile"].y,
			"dir": b["dir"],
		})
	return {"buildings": arr}

func from_dict(d: Dictionary) -> void:
	clear_factory()
	var arr = d.get("buildings", [])
	for item in arr:
		var bid = String(item.get("id", ""))
		if not GameState.BUILDINGS.has(bid):
			continue
		var info = GameState.BUILDINGS[bid]
		var origin = Vector2i(int(item.get("cx", 40)), int(item.get("cy", -1)))
		var sz: Vector2i = info["size"]
		var b_idx = buildings.size()
		buildings.append({
			"id": bid, "tile": origin, "size": sz, "dir": int(item.get("dir", 1)),
			"timer": 0.0, "active": true, "smoke_t": 0.0, "charge_t": 0.0, "frame": 0,
			"ore_target": _detect_drill_ore(origin, sz) if bid == "drill" else "",
		})
		for dy in range(sz.y):
			for dx in range(sz.x):
				occupied[_key(origin.x + dx, origin.y + dy)] = b_idx
	_recompute_power_grid()
	refresh_blueprint_slots()
	queue_redraw()
