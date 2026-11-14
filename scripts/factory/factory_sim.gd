extends Node2D
class_name FactorySim

# ==============================================================================
# STAR REPLICA: AUTOMA - CONNECTED SPHERICAL POWER GRID & LOGISTICS ENGINE
#   - Hard Local Power Grid: Solar/Geo -> Wire Link -> Tesla Coil Dome (0% outside)
#   - Buffered Physical Logistics: Drill (cap 6) -> Arc Belt -> Player Magnet /
#     Cargo Depot (4-way directional filter) -> Smelter -> Assembler -> Printer / Launch
#   - Visual clarity: Copper Tesla coils, glowing power cables & domes, item pips,
#     status indicators (NO PWR / FULL / RECIPE), & ship refueling pads.
# ==============================================================================

signal depot_opened(uid: int)
signal grid_status_changed

const WIRE_RANGE: float = 900.0
const TESLA_DOME_R: float = 560.0
const BUFFER_CAP_DRILL: int = 6
const BUFFER_CAP_IN: int = 12
const BUFFER_CAP_OUT: int = 12
const BATTERY_CAP_KJ: float = 18000.0
const DEPOT_CAP: int = 400
const POWER_NODE_IDS: Array[String] = ["solar", "geothermal", "tesla", "battery"]
const ASSEMBLER_RECIPES: Array[String] = ["circuit", "alloy", "sci_pack"]

var world: PlanetWorld
var swarm_sim: Node2D
var player: Node2D

var next_uid: int = 1
var buildings: Array[Dictionary] = []
var occupied: Dictionary = {} # "s,l" -> bldg idx
var wires: Array = []         # [[uid_a, uid_b], ...]

# Moving items on belts & lifts: {sec: int, layer: int, t: float, item: String, dir: int, is_lift: bool}
var belt_items: Array[Dictionary] = []
var projectiles: Array[Dictionary] = []
var laser_beams: Array[Dictionary] = []

# Blueprint Ghost Slots
var blueprint_slots: Array[Dictionary] = []
var active_ghost_idx: int = -1

# Interactive selection state
var wire_pick_uid: int = -1
var selected_depot_uid: int = -1

var sprite_textures: Dictionary = {}
var item_icons: Dictionary = {}
var tex_orbital_hub: Texture2D
var anim_time: float = 0.0
var grid_summary: Dictionary = {"prod": 0.0, "use": 0.0, "stored": 0.0, "cap": 0.0, "teslas_on": 0, "wires": 0}

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_load_assets()
	if not GameState.blueprint_selected.is_connected(_on_tool_changed):
		GameState.blueprint_selected.connect(_on_tool_changed)

func setup(p_world: PlanetWorld, p_swarm: Node2D, p_player: Node2D) -> void:
	world = p_world
	swarm_sim = p_swarm
	player = p_player
	refresh_blueprint_slots()

func _load_assets() -> void:
	for bid in GameState.BUILDINGS.keys():
		var sp_path: String = GameState.BUILDINGS[bid].get("sheet", "")
		if sp_path != "" and ResourceLoader.exists(sp_path):
			sprite_textures[bid] = load(sp_path)
	tex_orbital_hub = load("res://assets/sprites/orbital_hub.png")
	item_icons = {
		"fe": load("res://assets/ui/fe.png"),
		"cu": load("res://assets/ui/cu.png"),
		"si": load("res://assets/ui/si.png"),
		"ti": load("res://assets/ui/ti.png"),
		"ice": load("res://assets/ui/si.png"),
		"plate_fe": load("res://assets/ui/item_plate_fe.png"),
		"wire_cu": load("res://assets/ui/item_wire_cu.png"),
		"wafer_si": load("res://assets/ui/item_silicon_wafer.png"),
		"circuit": load("res://assets/ui/item_circuit.png"),
		"alloy": load("res://assets/ui/item_alloy.png"),
		"sci_pack": load("res://assets/ui/item_circuit.png"),
		"probe": load("res://assets/ui/item_drone_unit.png"),
	}

func _on_tool_changed(_id: String) -> void:
	if GameState.selected_tool != "wire":
		wire_pick_uid = -1
	refresh_blueprint_slots()
	queue_redraw()

func clear_factory() -> void:
	buildings.clear()
	occupied.clear()
	wires.clear()
	belt_items.clear()
	projectiles.clear()
	laser_beams.clear()
	next_uid = 1
	wire_pick_uid = -1
	selected_depot_uid = -1
	_recompute_local_grids(0.0)
	refresh_blueprint_slots()
	queue_redraw()

func _key(s: int, l: int) -> String:
	return "%d,%d" % [posmod(s, PlanetWorld.SECTORS), l]

func is_span_free(sec: int, layer: int, sec_w: int) -> bool:
	for ds in range(sec_w):
		if occupied.has(_key(sec + ds, layer)):
			return false
	return true

func can_place_building(bid: String, sec: int, layer: int) -> bool:
	if not world or not GameState.BUILDINGS.has(bid):
		return false
	var info = GameState.BUILDINGS[bid]
	var sec_w = int(info.get("sec_w", 1))
	var rule: String = info["place"]
	var ws = world.wrap_sector(sec)

	if not is_span_free(ws, layer, sec_w):
		return false

	match rule:
		"SURFACE":
			if layer < PlanetWorld.LAYERS - 3 or layer > PlanetWorld.LAYERS:
				return false
			var has_anchor = false
			for ds in range(sec_w):
				if layer < PlanetWorld.LAYERS and world.is_solid_cell(ws + ds, layer):
					return false
				if world.is_solid_cell(ws + ds, layer - 1):
					has_anchor = true
				elif layer < 2 or not world.is_solid_cell(ws + ds, layer - 2):
					return false
			return has_anchor
		"UNDERGROUND":
			if layer < 1 or layer >= PlanetWorld.LAYERS:
				return false
			if bid == "drill":
				return world.is_solid_cell(ws, layer)
			return true
		"ANY_SPHERE":
			if layer == PlanetWorld.LAYERS:
				return world.is_solid_cell(ws, PlanetWorld.LAYERS - 1)
			return layer >= 1 and layer < PlanetWorld.LAYERS
		"DEEP_ROCK":
			return layer >= 1 and layer <= 3
	return false

func _slot_world_pose(sec: int, layer: int, sec_w: int) -> Dictionary:
	var ws = world.wrap_sector(sec)
	var mid_ang = (float(ws) + float(sec_w) * 0.5) * PlanetWorld.DA
	var base_r = PlanetWorld.R_SURFACE if layer >= PlanetWorld.LAYERS else PlanetWorld.layer_inner_r(layer)
	var arc_w = maxf(26.0, float(sec_w) * PlanetWorld.DA * base_r)
	return {
		"pos": Vector2(cos(mid_ang), sin(mid_ang)) * base_r,
		"rot": mid_ang + PI * 0.5,
		"w_px": arc_w,
		"ang": mid_ang,
		"r": base_r,
	}

func refresh_blueprint_slots() -> void:
	blueprint_slots.clear()
	active_ghost_idx = -1
	if not world:
		return
	var bid = GameState.selected_tool
	if not GameState.BUILDINGS.has(bid):
		return
	var info = GameState.BUILDINGS[bid]
	var sec_w = int(info.get("sec_w", 1))
	var h_px = float(info.get("h_px", 40.0))
	var rule: String = info["place"]

	var pcell = world.pos_to_cell(player.position) if player else Vector2i(PlanetWorld.SPAWN_SECTOR, PlanetWorld.LAYERS)
	var base_sec = pcell.x

	if rule == "SURFACE":
		for l in range(PlanetWorld.LAYERS - 3, PlanetWorld.LAYERS + 1):
			for offset in range(-8, 9):
				var s = world.wrap_sector(base_sec + offset)
				if can_place_building(bid, s, l):
					var pose = _slot_world_pose(s, l, sec_w)
					blueprint_slots.append({
						"sec": s, "layer": l, "sec_w": sec_w,
						"pos": pose["pos"], "rot": pose["rot"],
						"w_px": pose["w_px"], "h_px": h_px,
					})
	elif rule == "UNDERGROUND":
		for l in range(maxi(1, pcell.y - 3), mini(PlanetWorld.LAYERS, pcell.y + 3)):
			for offset in range(-7, 8):
				var s = world.wrap_sector(base_sec + offset)
				if can_place_building(bid, s, l):
					var pose = _slot_world_pose(s, l, sec_w)
					blueprint_slots.append({
						"sec": s, "layer": l, "sec_w": sec_w,
						"pos": pose["pos"], "rot": pose["rot"],
						"w_px": pose["w_px"], "h_px": h_px,
					})
	elif rule == "ANY_SPHERE":
		for offset in range(-18, 19):
			var s = world.wrap_sector(base_sec + offset)
			if can_place_building(bid, s, PlanetWorld.LAYERS):
				var pose = _slot_world_pose(s, PlanetWorld.LAYERS, sec_w)
				blueprint_slots.append({
					"sec": s, "layer": PlanetWorld.LAYERS, "sec_w": sec_w,
					"pos": pose["pos"], "rot": pose["rot"],
					"w_px": pose["w_px"], "h_px": h_px,
				})
		if pcell.y < PlanetWorld.LAYERS:
			for l in range(maxi(1, pcell.y - 2), mini(PlanetWorld.LAYERS, pcell.y + 3)):
				for offset in range(-6, 7):
					var su = world.wrap_sector(base_sec + offset)
					if can_place_building(bid, su, l):
						var pose_u = _slot_world_pose(su, l, sec_w)
						blueprint_slots.append({
							"sec": su, "layer": l, "sec_w": sec_w,
							"pos": pose_u["pos"], "rot": pose_u["rot"],
							"w_px": pose_u["w_px"], "h_px": h_px,
						})
	elif rule == "DEEP_ROCK":
		for l in [1, 2, 3]:
			for offset in range(-12, 13):
				var s = world.wrap_sector(base_sec + offset)
				if can_place_building(bid, s, l):
					var pose = _slot_world_pose(s, l, sec_w)
					blueprint_slots.append({
						"sec": s, "layer": l, "sec_w": sec_w,
						"pos": pose["pos"], "rot": pose["rot"],
						"w_px": pose["w_px"], "h_px": h_px,
					})

	if player and blueprint_slots.size() > 0:
		var best_d = 999999.0
		for i in range(blueprint_slots.size()):
			var d = blueprint_slots[i]["pos"].distance_to(player.position)
			if d < best_d:
				best_d = d
				active_ghost_idx = i

func _get_building_by_uid(uid: int) -> Dictionary:
	for b in buildings:
		if int(b.get("uid", -1)) == uid:
			return b
	return {}

func _get_building_at(sec: int, layer: int) -> Dictionary:
	var k = _key(sec, layer)
	if not occupied.has(k):
		return {}
	var idx = int(occupied[k])
	if idx < 0 or idx >= buildings.size():
		return {}
	return buildings[idx]

func find_nearest_building(world_pos: Vector2, max_dist: float = 90.0, filter_ids: Array = []) -> Dictionary:
	var best: Dictionary = {}
	var best_d = max_dist
	for b in buildings:
		if not filter_ids.is_empty() and not (b["id"] in filter_ids):
			continue
		var d = Vector2(b["pos"]).distance_to(world_pos)
		if d < best_d:
			best_d = d
			best = b
	return best

func _is_power_node(bid: String) -> bool:
	return bid in POWER_NODE_IDS

func _are_wired(u1: int, u2: int) -> bool:
	for w in wires:
		if (int(w[0]) == u1 and int(w[1]) == u2) or (int(w[0]) == u2 and int(w[1]) == u1):
			return true
	return false

func toggle_wire(u1: int, u2: int) -> bool:
	if u1 <= 0 or u2 <= 0 or u1 == u2:
		return false
	var b1 = _get_building_by_uid(u1)
	var b2 = _get_building_by_uid(u2)
	if b1.is_empty() or b2.is_empty():
		return false
	if not _is_power_node(b1["id"]) or not _is_power_node(b2["id"]):
		return false
	for i in range(wires.size()):
		var w = wires[i]
		if (int(w[0]) == u1 and int(w[1]) == u2) or (int(w[0]) == u2 and int(w[1]) == u1):
			wires.remove_at(i)
			_recompute_local_grids(0.0)
			AudioSynth.play_synth("pop")
			GameState.add_log("Power line disconnected.", "info")
			return true
	var d = Vector2(b1["pos"]).distance_to(Vector2(b2["pos"]))
	if d > WIRE_RANGE:
		AudioSynth.play_synth("error")
		GameState.add_log("Wire out of range (%dpx > %dpx)." % [int(d), int(WIRE_RANGE)], "warn")
		return false
	wires.append([u1, u2])
	if world:
		world.spawn_spark_burst((Vector2(b1["pos"]) + Vector2(b2["pos"])) * 0.5, Color(0.35, 0.95, 1.0), 8)
	_recompute_local_grids(0.0)
	AudioSynth.play_synth("select")
	GameState.add_log("POWER GRID WIRED: %s <-> %s" % [GameState.BUILDINGS[b1["id"]]["name"], GameState.BUILDINGS[b2["id"]]["name"]], "good")
	queue_redraw()
	return true

func try_wire_nearest(ref_pos: Vector2) -> bool:
	var near = find_nearest_building(ref_pos, 180.0, POWER_NODE_IDS)
	if near.is_empty():
		GameState.add_log("Stand near a Solar/Geo/Tesla node to wire.", "warn")
		return false
	var u1 = int(near["uid"])
	if wire_pick_uid == -1:
		wire_pick_uid = u1
		AudioSynth.play_synth("click")
		GameState.add_log("WIRE SOURCE: %s. Tap target or press [A] at target." % GameState.BUILDINGS[near["id"]]["name"], "info")
		return true
	elif wire_pick_uid == u1:
		# Smart convenience: strongly prefer complementary power role (Solar/Geo <-> Tesla) over same-type
		var best_u = -1
		var best_score = 1e9
		var near_is_gen = near["id"] in ["solar", "geothermal"]
		for b in buildings:
			var bu = int(b["uid"])
			if bu == u1 or not _is_power_node(b["id"]) or _are_wired(u1, bu):
				continue
			var d = Vector2(near["pos"]).distance_to(Vector2(b["pos"]))
			if d <= WIRE_RANGE:
				var b_is_gen = b["id"] in ["solar", "geothermal"]
				var score = d - (1200.0 if (near_is_gen != b_is_gen) else 0.0)
				if score < best_score:
					best_score = score
					best_u = bu
		wire_pick_uid = -1
		if best_u > 0:
			return toggle_wire(u1, best_u)
		GameState.add_log("Wire selection cleared.", "info")
		return true
	else:
		var prev = wire_pick_uid
		wire_pick_uid = -1
		return toggle_wire(prev, u1)

func _collect_building_out_buf(b: Dictionary) -> int:
	if not b.has("out_buf"):
		return 0
	var out: Dictionary = b["out_buf"]
	var got = 0
	for k in out.keys().duplicate():
		var cnt = int(out[k])
		if cnt > 0:
			GameState.add_res(k, cnt, false)
			out.erase(k)
			got += cnt
			if world:
				world.spawn_world_popup(Vector2(b["pos"]) + Vector2(0, -18), "+%d %s" % [cnt, String(k).to_upper()], Color(0.45, 0.95, 1.0))
	if got > 0:
		AudioSynth.play_synth("pop")
	return got

func try_handle_click_at(world_pos: Vector2) -> bool:
	var tool = GameState.selected_tool

	# 1. Explicit Wire Mode: tap power nodes to connect Solar/Geo <-> Tesla
	if tool == "wire":
		var pnode = find_nearest_building(world_pos, 130.0, POWER_NODE_IDS)
		if not pnode.is_empty():
			var uid = int(pnode["uid"])
			if wire_pick_uid == -1:
				wire_pick_uid = uid
				AudioSynth.play_synth("click")
				GameState.add_log("WIRE PICKED: %s -> Tap Tesla/Generator" % GameState.BUILDINGS[pnode["id"]]["name"], "info")
			elif wire_pick_uid == uid:
				wire_pick_uid = -1
				GameState.add_log("Wire pick cleared.", "info")
			else:
				var u0 = wire_pick_uid
				wire_pick_uid = -1
				toggle_wire(u0, uid)
			return true
		wire_pick_uid = -1
		return true

	# 2. Demolish Mode
	if tool == "demolish":
		return try_demolish_at(world_pos)

	# 3. Direct Blueprint Placement when a building tool is selected
	if GameState.BUILDINGS.has(tool) and not blueprint_slots.is_empty():
		var best_i = -1
		var best_d = 120.0
		for i in range(blueprint_slots.size()):
			var d = blueprint_slots[i]["pos"].distance_to(world_pos)
			if d < best_d:
				best_d = d
				best_i = i
		if best_i >= 0:
			active_ghost_idx = best_i
			var sl = blueprint_slots[best_i]
			if try_place_building(tool, sl["sec"], sl["layer"]):
				return true

	# 4. World Structure Interactions (Power wire tap, Depot UI, Belt flip, Assembler recipe, Drill unload)
	var b = find_nearest_building(world_pos, 115.0)
	if not b.is_empty():
		var bid: String = b["id"]
		if _is_power_node(bid):
			var uid = int(b["uid"])
			if wire_pick_uid == -1:
				wire_pick_uid = uid
				AudioSynth.play_synth("click")
				GameState.add_log("WIRE SOURCE: %s. Tap target Solar/Tesla!" % GameState.BUILDINGS[bid]["name"], "info")
			elif wire_pick_uid == uid:
				wire_pick_uid = -1
				GameState.add_log("Wire pick cleared.", "info")
			else:
				var u0 = wire_pick_uid
				wire_pick_uid = -1
				if not _are_wired(u0, uid):
					toggle_wire(u0, uid)
				else:
					GameState.add_log("Already wired (use Power Wire tool to unplug).", "info")
			return true
		elif bid == "depot":
			selected_depot_uid = int(b["uid"])
			AudioSynth.play_synth("select")
			depot_opened.emit(selected_depot_uid)
			return true
		elif bid == "belt" or bid == "lift":
			b["dir"] = -int(b.get("dir", 1))
			AudioSynth.play_synth("click")
			GameState.add_log("%s direction flipped." % GameState.BUILDINGS[bid]["name"], "info")
			queue_redraw()
			return true
		elif bid == "assembler":
			var cur = String(b.get("recipe", "circuit"))
			var ri = (ASSEMBLER_RECIPES.find(cur) + 1) % ASSEMBLER_RECIPES.size()
			b["recipe"] = ASSEMBLER_RECIPES[ri]
			_collect_building_out_buf(b)
			AudioSynth.play_synth("select")
			GameState.add_log("Assembler Recipe: %s" % String(b["recipe"]).to_upper(), "info")
			queue_redraw()
			return true
		elif bid == "drill" or bid == "smelter":
			if _collect_building_out_buf(b) == 0 and bid == "smelter":
				_hand_feed_machine(b)
			return true

	wire_pick_uid = -1
	return false

func try_interact_nearest(world_pos: Vector2, id_filter: Array = []) -> bool:
	if GameState.selected_tool == "wire":
		return try_wire_nearest(world_pos)
	var b = find_nearest_building(world_pos, 190.0, id_filter)
	if id_filter.is_empty() and not b.is_empty() and (_is_power_node(b["id"]) or b["id"] == "belt"):
		# Inside a factory cluster, prioritize functional machines over passive belts/wired power poles
		var functional = find_nearest_building(world_pos, 195.0, ["depot", "smelter", "assembler", "drill"])
		if not functional.is_empty():
			b = functional
	if b.is_empty():
		return false
	var bid: String = b["id"]
	if bid == "depot":
		selected_depot_uid = int(b["uid"])
		AudioSynth.play_synth("select")
		depot_opened.emit(selected_depot_uid)
		return true
	if _is_power_node(bid):
		if not b.get("wired", false):
			return try_wire_nearest(world_pos)
		GameState.add_log("%s online in wired grid (+%dW prod)." % [GameState.BUILDINGS[bid]["name"], int(grid_summary.get("prod", 0))], "info")
		return false
	if bid == "drill" or bid == "smelter" or bid == "assembler":
		var got = _collect_building_out_buf(b)
		if bid == "smelter" or bid == "assembler":
			var fed = _hand_feed_machine(b)
			return got > 0 or fed
		return got > 0
	return false

func _hand_feed_machine(b: Dictionary) -> bool:
	var bid: String = b["id"]
	var fed = false
	if bid == "smelter":
		var ore_to_prod = {"fe": "plate_fe", "cu": "wire_cu", "si": "wafer_si"}
		var ores: Array[String] = ["fe", "cu", "si"]
		ores.sort_custom(func(a: String, c: String) -> bool:
			var qa = float(GameState.get_res(ore_to_prod[a])) + float(b["in_buf"].get(a, 0)) * 0.5
			var qc = float(GameState.get_res(ore_to_prod[c])) + float(b["in_buf"].get(c, 0)) * 0.5
			if a == "fe" and GameState.get_res("plate_fe") < 4: qa -= 4.0
			if c == "fe" and GameState.get_res("plate_fe") < 4: qc -= 4.0
			return qa < qc
		)
		for ore in ores:
			if GameState.get_res(ore) >= 2 and _buf_total(b["in_buf"]) < BUFFER_CAP_IN:
				var give = mini(4, mini(GameState.get_res(ore), BUFFER_CAP_IN - _buf_total(b["in_buf"])))
				GameState.add_res(ore, -give)
				_buf_add(b["in_buf"], ore, give)
				fed = true
				break
	elif bid == "assembler":
		var rec = String(b.get("recipe", "circuit"))
		var wants: Array[String] = ["plate_fe", "wire_cu", "wafer_si"] if rec == "circuit" else (["plate_fe", "ti"] if rec == "alloy" else ["plate_fe", "wire_cu", "circuit"])
		for w in wants:
			if GameState.get_res(w) >= 1 and _buf_total(b["in_buf"]) < BUFFER_CAP_IN:
				var give = mini(2, mini(GameState.get_res(w), BUFFER_CAP_IN - _buf_total(b["in_buf"])))
				GameState.add_res(w, -give)
				_buf_add(b["in_buf"], w, give)
				fed = true
	if fed:
		AudioSynth.play_synth("pop")
		GameState.add_log("Loaded items into %s." % GameState.BUILDINGS[bid]["name"], "good")
	return fed

func try_build_nearest_ghost() -> bool:
	var tool = GameState.selected_tool
	if tool == "wire":
		return try_wire_nearest(player.position if player else Vector2.ZERO)
	if not GameState.BUILDINGS.has(tool):
		return false
	if blueprint_slots.is_empty():
		refresh_blueprint_slots()
	if active_ghost_idx < 0 or active_ghost_idx >= blueprint_slots.size():
		GameState.add_log("No valid spherical slot nearby.", "warn")
		AudioSynth.play_synth("error")
		return false
	var sl = blueprint_slots[active_ghost_idx]
	return try_place_building(tool, sl["sec"], sl["layer"])

func try_place_building(bid: String, sec: int, layer: int) -> bool:
	if not world or not GameState.BUILDINGS.has(bid):
		return false
	if not GameState.is_building_unlocked(bid):
		var req_t: String = String(GameState.BUILDINGS[bid].get("req_tech", ""))
		var t_name: String = String(GameState.TECH_TREE.get(req_t, {}).get("name", req_t))
		GameState.add_log("Locked: Research [%s] in Tech Tree!" % t_name, "warn")
		AudioSynth.play_synth("error")
		return false
	var ws = world.wrap_sector(sec)
	if not can_place_building(bid, ws, layer):
		AudioSynth.play_synth("error")
		GameState.add_log("Cannot place here (occupied or needs rock crust).", "warn")
		return false
	var info = GameState.BUILDINGS[bid]
	var cost: Dictionary = info["cost"]
	if not GameState.can_afford(cost):
		AudioSynth.play_synth("error")
		var miss_txt: Array[String] = []
		for r_id in cost.keys():
			var have = GameState.get_res(r_id)
			var need = int(cost[r_id])
			if have < need:
				miss_txt.append("%s %d/%d" % [String(r_id).to_upper(), have, need])
		GameState.add_log("Need resources: %s" % ", ".join(miss_txt), "warn")
		return false

	GameState.spend_cost(cost)
	if GameState.megastructures.has(bid):
		GameState.megastructures[bid] = true
		if GameState.megastructures.get("warpgate", false) and GameState.boss_defeated:
			GameState.game_won = true
			GameState.add_log("COLONY VICTORY: WARP GATE & CORE HUB LIBERATED!", "good")
	var sec_w = int(info.get("sec_w", 1))
	var pose = _slot_world_pose(ws, layer, sec_w)
	var default_dir = 1
	if player and bid == "belt":
		var p_ang = player.position.angle()
		var tang = Vector2(-sin(p_ang), cos(p_ang))
		if player.velocity.length() > 15.0 and player.velocity.dot(tang) < 0.0:
			default_dir = -1

	var ore_t = _find_drill_ore(ws, layer)
	var b: Dictionary = {
		"uid": next_uid,
		"id": bid,
		"sec": ws,
		"layer": layer,
		"sec_w": sec_w,
		"dir": default_dir,
		"pos": pose["pos"],
		"rot": pose["rot"],
		"w_px": pose["w_px"],
		"timer": 0.0,
		"push_t": 0.0,
		"smoke_t": 0.0,
		"charge_t": 0.0,
		"frame": 0,
		"ore_target": ore_t,
		"in_buf": {},
		"out_buf": {},
		"inv": {},
		"out_filters": {"left": "auto", "right": "auto", "up": "none", "down": "none"},
		"recipe": "circuit",
		"battery_kj": (BATTERY_CAP_KJ * 0.25) if bid == "battery" else 0.0,
		"pwr_ratio": 0.0,
		"wired": false,
		"blocked": false,
	}
	next_uid += 1

	var idx = buildings.size()
	buildings.append(b)
	for ds in range(sec_w):
		occupied[_key(ws + ds, layer)] = idx

	if world:
		world.spawn_spark_burst(pose["pos"], Color(0.35, 0.92, 1.0), 8)
	_recompute_local_grids(0.0)
	refresh_blueprint_slots()
	AudioSynth.play_synth("build")
	GameState.add_log("Built %s!%s" % [
		info["name"],
		" Wire Solar <-> Tesla to energize." if (bid == "tesla" or bid == "solar") else ""
	], "good")
	queue_redraw()
	return true

func _find_drill_ore(sec: int, layer: int) -> String:
	if not world:
		return "fe"
	for dl in range(0, 4):
		var l = layer - 1 - dl
		if l >= 1 and l < PlanetWorld.LAYERS:
			var o = world.get_ore(sec, l)
			if o != "":
				return o
	for ds in [-1, 1]:
		for dl in range(0, 3):
			var l = layer - 1 - dl
			if l >= 1 and l < PlanetWorld.LAYERS:
				var o = world.get_ore(sec + ds, l)
				if o != "":
					return o
	return "fe"

func try_demolish_at(world_pos: Vector2) -> bool:
	var best_idx = -1
	var best_d = 95.0
	for i in range(buildings.size()):
		var d = buildings[i]["pos"].distance_to(world_pos)
		if d < best_d:
			best_d = d
			best_idx = i
	if best_idx == -1:
		return false
	var b = buildings[best_idx]
	var dead_uid = int(b["uid"])
	var info = GameState.BUILDINGS[b["id"]]
	for r_id in info["cost"].keys():
		GameState.add_res(r_id, maxi(1, int(info["cost"][r_id]) / 2), false)
	for wi in range(wires.size() - 1, -1, -1):
		if int(wires[wi][0]) == dead_uid or int(wires[wi][1]) == dead_uid:
			wires.remove_at(wi)
	if wire_pick_uid == dead_uid:
		wire_pick_uid = -1
	if selected_depot_uid == dead_uid:
		selected_depot_uid = -1
	buildings.remove_at(best_idx)
	occupied.clear()
	for i in range(buildings.size()):
		for ds in range(buildings[i]["sec_w"]):
			occupied[_key(buildings[i]["sec"] + ds, buildings[i]["layer"])] = i
	_recompute_local_grids(0.0)
	refresh_blueprint_slots()
	AudioSynth.play_synth("pop")
	GameState.add_log("Salvaged %s." % info["name"], "info")
	queue_redraw()
	return true

# ------------------------------------------------------------------------------
# LOCAL WIRED POWER GRID SOLVER (ZERO GLOBAL POOL - HARD LOCAL GRID)
# ------------------------------------------------------------------------------
func _recompute_local_grids(delta: float) -> void:
	var uid_to_idx: Dictionary = {}
	for i in range(buildings.size()):
		uid_to_idx[int(buildings[i]["uid"])] = i
		buildings[i]["pwr_ratio"] = 0.0
		buildings[i]["wired"] = false

	# Prune stale wires & build adjacency
	var adj: Dictionary = {}
	for i in range(wires.size() - 1, -1, -1):
		var u1 = int(wires[i][0])
		var u2 = int(wires[i][1])
		if not uid_to_idx.has(u1) or not uid_to_idx.has(u2):
			wires.remove_at(i)
			continue
		if not adj.has(u1): adj[u1] = []
		if not adj.has(u2): adj[u2] = []
		adj[u1].append(u2)
		adj[u2].append(u1)

	# Find connected wired components
	var visited: Dictionary = {}
	var comp_id_of_b: Dictionary = {}
	var comps: Array[Dictionary] = []

	for b in buildings:
		var uid = int(b["uid"])
		if not _is_power_node(b["id"]) or visited.has(uid):
			continue
		var q: Array[int] = [uid]
		visited[uid] = true
		var nodes: Array[int] = []
		var gen_kw: float = 0.0
		var bat_indices: Array[int] = []
		var has_tesla = false
		var has_gen = false
		while not q.is_empty():
			var cur_u: int = q.pop_front()
			var bi = int(uid_to_idx[cur_u])
			nodes.append(bi)
			var cb = buildings[bi]
			if adj.has(cur_u) and adj[cur_u].size() > 0:
				cb["wired"] = true
			if cb["id"] == "solar":
				has_gen = true
				var sun = world.get_sunlight_at(cb["pos"]) if world else 1.0
				gen_kw += 38.0 * sun
			elif cb["id"] == "geothermal":
				has_gen = true
				gen_kw += 135.0
			elif cb["id"] == "tesla":
				has_tesla = true
			elif cb["id"] == "battery":
				bat_indices.append(bi)
			if adj.has(cur_u):
				for nxt in adj[cur_u]:
					if not visited.has(nxt):
						visited[nxt] = true
						q.append(nxt)

		# Megastructure Dyson Swarm wireless beam feeds any wired Tesla grid
		var dyson_kw = float(GameState.megastructures.get("dyson", 0)) * 450.0
		if has_tesla and dyson_kw > 0.0:
			gen_kw += dyson_kw
			has_gen = true

		var cid = comps.size()
		for bi in nodes:
			comp_id_of_b[bi] = cid
		comps.append({
			"nodes": nodes,
			"gen": gen_kw,
			"use": 0.0,
			"bat_indices": bat_indices,
			"has_tesla": has_tesla,
			"has_gen": has_gen,
			"ratio": 0.0,
		})

	# Map every consumer machine inside radius of an active Tesla coil to its Tesla's component
	var machine_comp: Dictionary = {} # b_idx -> cid
	for i in range(buildings.size()):
		var b = buildings[i]
		if _is_power_node(b["id"]):
			continue
		var pwr = float(GameState.BUILDINGS[b["id"]].get("power", 0))
		if pwr >= 0.0:
			# Passive structures (Depot / Elevator)
			b["pwr_ratio"] = 1.0
			continue
		var best_cid = -1
		var best_d = TESLA_DOME_R
		for c_idx in range(comps.size()):
			var comp = comps[c_idx]
			if not comp["has_gen"] and comp["bat_indices"].is_empty():
				continue
			for ni in comp["nodes"]:
				if buildings[ni]["id"] == "tesla":
					var d = Vector2(buildings[ni]["pos"]).distance_to(Vector2(b["pos"]))
					if d <= best_d:
						best_d = d
						best_cid = c_idx
		if best_cid >= 0:
			machine_comp[i] = best_cid
			comps[best_cid]["use"] += -pwr

	# Solve energy balance + battery charge/discharge per local grid component
	var tot_prod = 0.0
	var tot_use = 0.0
	var tot_stored = 0.0
	var tot_cap = 0.0
	var teslas_on = 0

	for cid in range(comps.size()):
		var c = comps[cid]
		var gen = float(c["gen"])
		var use = float(c["use"])
		var bat_list: Array = c["bat_indices"]
		var stored_sum = 0.0
		var cap_sum = float(bat_list.size()) * BATTERY_CAP_KJ
		for bi in bat_list:
			stored_sum += float(buildings[bi].get("battery_kj", 0.0))

		var net = gen - use
		if delta > 0.0 and not bat_list.is_empty():
			if net >= 0.0:
				var charge = minf(net * delta, cap_sum - stored_sum)
				if charge > 0.0:
					var each = charge / float(bat_list.size())
					for bi in bat_list:
						buildings[bi]["battery_kj"] = minf(BATTERY_CAP_KJ, float(buildings[bi].get("battery_kj", 0.0)) + each)
					stored_sum += charge
				c["ratio"] = 1.0 if (gen > 0.0 or use == 0.0) else 0.0
			else:
				var need_kj = (-net) * delta
				if stored_sum >= need_kj:
					var take_each = need_kj / float(bat_list.size())
					for bi in bat_list:
						buildings[bi]["battery_kj"] = maxf(0.0, float(buildings[bi].get("battery_kj", 0.0)) - take_each)
					stored_sum -= need_kj
					c["ratio"] = 1.0
				else:
					for bi in bat_list:
						buildings[bi]["battery_kj"] = 0.0
					stored_sum = 0.0
					c["ratio"] = clampf(gen / maxf(1.0, use), 0.0, 1.0)
		else:
			if use <= 0.0:
				c["ratio"] = 1.0 if (gen > 0.0 or stored_sum > 0.5) else 0.0
			elif gen >= use or stored_sum > 0.5:
				c["ratio"] = 1.0
			elif gen > 0.0:
				var r = gen / use
				c["ratio"] = r if r >= 0.15 else 0.0
			else:
				c["ratio"] = 0.0

		for ni in c["nodes"]:
			buildings[ni]["pwr_ratio"] = c["ratio"]
			if buildings[ni]["id"] == "tesla" and c["ratio"] > 0.05:
				teslas_on += 1

		if c["has_tesla"] or not bat_list.is_empty():
			tot_prod += gen
		tot_use += use
		tot_stored += stored_sum
		tot_cap += cap_sum

	# Assign solved power ratio to consumers inside active Tesla domes
	for bi in machine_comp.keys():
		var cid = int(machine_comp[bi])
		buildings[bi]["pwr_ratio"] = comps[cid]["ratio"]

	GameState.power_gen = tot_prod
	GameState.power_use = tot_use
	GameState.power_stored = tot_stored
	GameState.power_cap = tot_cap
	GameState.power_ratio = (tot_prod / tot_use) if tot_use > 0.0 else (1.0 if tot_prod > 0.0 else 0.0)
	grid_summary = {
		"prod": int(tot_prod), "use": int(tot_use),
		"stored": int(tot_stored), "cap": int(tot_cap),
		"teslas_on": teslas_on, "wires": wires.size(),
	}
	grid_status_changed.emit()

# ------------------------------------------------------------------------------
# BUFFER & LOGISTICS HELPERS
# ------------------------------------------------------------------------------
func _buf_total(buf: Dictionary) -> int:
	var s = 0
	for k in buf.keys():
		s += int(buf[k])
	return s

func _buf_add(buf: Dictionary, item: String, qty: int) -> void:
	if item == "" or qty <= 0:
		return
	buf[item] = int(buf.get(item, 0)) + qty

func _buf_take_one(buf: Dictionary, filter_item: String = "auto") -> String:
	if filter_item == "none" or buf.is_empty():
		return ""
	if filter_item != "" and filter_item != "auto":
		var cnt = int(buf.get(filter_item, 0))
		if cnt > 0:
			if cnt == 1: buf.erase(filter_item)
			else: buf[filter_item] = cnt - 1
			return filter_item
		return ""
	for k in buf.keys():
		var cnt = int(buf[k])
		if cnt > 0:
			if cnt == 1: buf.erase(k)
			else: buf[k] = cnt - 1
			return String(k)
	return ""

func _can_accept_into_machine(b: Dictionary, item: String) -> bool:
	var bid: String = b["id"]
	if bid == "depot":
		return _buf_total(b["inv"]) < DEPOT_CAP
	if bid == "smelter":
		return (item in ["fe", "cu", "si"]) and _buf_total(b["in_buf"]) < BUFFER_CAP_IN
	if bid == "assembler":
		return (item in ["plate_fe", "wire_cu", "wafer_si", "ti", "circuit"]) and _buf_total(b["in_buf"]) < BUFFER_CAP_IN
	if bid == "printer":
		return item in ["fe", "cu", "si", "ti", "plate_fe", "wire_cu", "wafer_si", "circuit", "alloy"]
	if bid == "replicator":
		return (item in ["circuit", "plate_fe", "alloy"]) and _buf_total(b["in_buf"]) < BUFFER_CAP_IN
	if bid == "mass_driver":
		return (item in ["plate_fe", "alloy", "circuit", "probe"]) and _buf_total(b["in_buf"]) < BUFFER_CAP_IN
	return false

func _deliver_to_target(b: Dictionary, item: String) -> bool:
	if not _can_accept_into_machine(b, item):
		return false
	var bid: String = b["id"]
	if bid == "depot":
		_buf_add(b["inv"], item, 1)
		return true
	if bid == "printer":
		GameState.add_res(item, 1, false)
		return true
	_buf_add(b["in_buf"], item, 1)
	return true

func _count_belt_items_at(sec: int, layer: int, t_limit: float = 0.40) -> int:
	var ws = world.wrap_sector(sec) if world else sec
	var c = 0
	for it in belt_items:
		if int(it["sec"]) == ws and int(it["layer"]) == layer and float(it["t"]) <= t_limit:
			c += 1
	return c

func _spawn_item_on_belt(sec: int, layer: int, item: String, dir_hint: int = 1) -> bool:
	if belt_items.size() > 360:
		return false
	var target_b = _get_building_at(sec, layer)
	if target_b.is_empty():
		return false
	var tbid: String = target_b["id"]
	if tbid == "belt" or tbid == "lift":
		if _count_belt_items_at(sec, layer, 0.35) >= 2:
			return false
		belt_items.append({
			"sec": world.wrap_sector(sec),
			"layer": layer,
			"t": 0.06,
			"item": item,
			"dir": int(target_b.get("dir", dir_hint)),
			"is_lift": (tbid == "lift"),
		})
		return true
	return _deliver_to_target(target_b, item)

func _try_push_item_adjacent(src_b: Dictionary, buf: Dictionary) -> void:
	if buf.is_empty():
		return
	var ws: int = src_b["sec"]
	var sw: int = src_b["sec_w"]
	var l: int = src_b["layer"]
	var probes: Array[Array] = [
		[ws + sw, l, 1],
		[ws - 1, l, -1],
		[ws, l + 1, 1],
	]
	for p in probes:
		var tb = _get_building_at(int(p[0]), int(p[1]))
		if tb.is_empty():
			continue
		var item = _buf_take_one(buf, "auto")
		if item == "":
			return
		var did_send = false
		if tb["id"] == "belt" or tb["id"] == "lift":
			did_send = _spawn_item_on_belt(tb["sec"], tb["layer"], item, int(p[2]))
		else:
			did_send = _deliver_to_target(tb, item)
		if not did_send:
			_buf_add(buf, item, 1)
		else:
			return

func _push_depot_outputs(depot: Dictionary) -> void:
	var inv: Dictionary = depot["inv"]
	if inv.is_empty():
		return
	var filters: Dictionary = depot.get("out_filters", {})
	var ws: int = depot["sec"]
	var sw: int = depot["sec_w"]
	var l: int = depot["layer"]
	var ports: Array[Dictionary] = [
		{"key": "right", "sec": ws + sw, "layer": l, "dir": 1},
		{"key": "left",  "sec": ws - 1,  "layer": l, "dir": -1},
		{"key": "up",    "sec": ws,      "layer": l + 1, "dir": 1},
		{"key": "down",  "sec": ws,      "layer": l - 1, "dir": -1},
	]
	for p in ports:
		var f_item: String = String(filters.get(p["key"], "none"))
		if f_item == "none":
			continue
		var tb = _get_building_at(int(p["sec"]), int(p["layer"]))
		if tb.is_empty():
			continue
		var picked = _buf_take_one(inv, f_item)
		if picked == "":
			continue
		var ok = false
		if tb["id"] == "belt" or tb["id"] == "lift":
			ok = _spawn_item_on_belt(tb["sec"], tb["layer"], picked, int(p["dir"]))
		else:
			ok = _deliver_to_target(tb, picked)
		if not ok:
			_buf_add(inv, picked, 1)

# ------------------------------------------------------------------------------
# PLAYER LOGISTICS INTERFACE (MAGNET PICKUP, DEPOT UI, SHIP SERVICE PAD)
# ------------------------------------------------------------------------------
func collect_nearby_items(pos: Vector2, radius: float = 95.0) -> int:
	var got = 0
	if world:
		for i in range(belt_items.size() - 1, -1, -1):
			var ip = _belt_item_world_pos(belt_items[i])
			if ip.distance_to(pos) <= radius:
				GameState.add_res(belt_items[i]["item"], 1, true)
				belt_items.remove_at(i)
				got += 1
	# Also allow player walking/flying right over a standalone Drill (no adjacent belt) to loot out_buf
	for b in buildings:
		if b["id"] == "drill" or b["id"] == "smelter" or b["id"] == "assembler":
			if Vector2(b["pos"]).distance_to(pos) <= 72.0 and not b["out_buf"].is_empty():
				got += _collect_building_out_buf(b)
	if got > 0:
		AudioSynth.play_synth("pop")
	return got

func service_player(pos: Vector2, delta: float) -> void:
	var near_powered_pad = false
	for b in buildings:
		if (b["id"] in ["solar", "geothermal", "tesla", "battery", "depot"]) and float(b.get("pwr_ratio", 0.0)) > 0.2:
			if Vector2(b["pos"]).distance_to(pos) <= 260.0:
				near_powered_pad = true
				break
	if near_powered_pad:
		GameState.player_battery = minf(GameState.player_max_battery, GameState.player_battery + 30.0 * delta)
		GameState.player_fuel = minf(GameState.player_max_fuel, GameState.player_fuel + 18.0 * delta)
		GameState.player_hp = minf(GameState.player_max_hp, GameState.player_hp + 6.0 * delta)
	elif world and pos.length() <= PlanetWorld.R_ATMOS_OUTER:
		var sun = world.get_sunlight_at(pos)
		if sun > 0.15:
			GameState.player_battery = minf(GameState.player_max_battery, GameState.player_battery + 8.0 * sun * delta)
		else:
			GameState.player_battery = minf(GameState.player_max_battery, GameState.player_battery + 3.5 * delta)

func get_depot_snapshot(uid: int) -> Dictionary:
	var d = _get_building_by_uid(uid)
	if d.is_empty():
		return {}
	return {
		"uid": uid,
		"inv": d["inv"].duplicate(),
		"out_filters": d["out_filters"].duplicate(),
		"total": _buf_total(d["inv"]),
		"cap": DEPOT_CAP,
	}

func depot_transfer(uid: int, item: String, to_depot: bool, qty: int = 5) -> bool:
	var d = _get_building_by_uid(uid)
	if d.is_empty():
		return false
	var inv: Dictionary = d["inv"]
	if to_depot:
		var have = GameState.get_res(item)
		var room = maxi(0, DEPOT_CAP - _buf_total(inv))
		var move = mini(qty, mini(have, room))
		if move <= 0:
			return false
		GameState.add_res(item, -move)
		_buf_add(inv, item, move)
	else:
		var have_d = int(inv.get(item, 0))
		var move = mini(qty, have_d)
		if move <= 0:
			return false
		if have_d == move: inv.erase(item)
		else: inv[item] = have_d - move
		GameState.add_res(item, move, false)
	AudioSynth.play_synth("pop")
	return true

func depot_deposit_all_ores(uid: int) -> int:
	var moved = 0
	for r in ["fe", "cu", "si", "ti", "ice"]:
		var amt = GameState.get_res(r)
		if amt > 0 and depot_transfer(uid, r, true, amt):
			moved += amt
	return moved

func depot_cycle_filter(uid: int, dir_key: String) -> String:
	var d = _get_building_by_uid(uid)
	if d.is_empty():
		return "none"
	var cycle: Array[String] = ["none", "auto", "fe", "cu", "si", "ti", "plate_fe", "wire_cu", "wafer_si", "circuit", "alloy", "sci_pack"]
	var cur = String(d["out_filters"].get(dir_key, "none"))
	var nxt = cycle[(cycle.find(cur) + 1) % cycle.size()]
	d["out_filters"][dir_key] = nxt
	AudioSynth.play_synth("click")
	return nxt

func _belt_item_world_pos(it: Dictionary) -> Vector2:
	if not world:
		return Vector2.ZERO
	if it.get("is_lift", false):
		var a = PlanetWorld.sector_center_angle(it["sec"])
		var r0 = PlanetWorld.layer_inner_r(it["layer"])
		var t = float(it["t"]) if int(it["dir"]) >= 0 else (1.0 - float(it["t"]))
		return world.polar_to_world(a, r0 + t * PlanetWorld.LAYER_THICK)
	var base_s = float(it["sec"])
	var frac = float(it["t"]) if int(it["dir"]) >= 0 else (1.0 - float(it["t"]))
	var ang = (base_s + frac) * PlanetWorld.DA
	var r = PlanetWorld.R_SURFACE + 14.0 if int(it["layer"]) >= PlanetWorld.LAYERS else PlanetWorld.layer_inner_r(it["layer"]) + 14.0
	return world.polar_to_world(ang, r)

# ------------------------------------------------------------------------------
# MAIN SIMULATION STEP
# ------------------------------------------------------------------------------
func _process(delta: float) -> void:
	anim_time += delta
	_recompute_local_grids(delta)

	var spd_bonus = 1.0 + float(GameState.drones) * 0.18

	for b in buildings:
		var bid: String = b["id"]
		var pwr = float(b.get("pwr_ratio", 0.0))
		b["blocked"] = false

		if pwr > 0.05:
			b["timer"] += delta * spd_bonus * pwr
			b["smoke_t"] += delta * pwr

		b["push_t"] += delta
		if b["push_t"] >= 0.42:
			b["push_t"] = 0.0
			if bid == "depot":
				_push_depot_outputs(b)
			elif bid in ["drill", "smelter", "assembler"]:
				_try_push_item_adjacent(b, b["out_buf"])

		match bid:
			"drill":
				if pwr <= 0.05:
					continue
				if _buf_total(b["out_buf"]) >= BUFFER_CAP_DRILL:
					b["blocked"] = true
					continue
				if b["timer"] >= 1.15:
					b["timer"] = 0.0
					b["frame"] = (b["frame"] + 1) % 4
					var ore: String = b["ore_target"]
					_buf_add(b["out_buf"], ore, 1)
					if world and b["smoke_t"] >= 0.9:
						b["smoke_t"] = 0.0
						world.spawn_smoke_puff(b["pos"] + b["pos"].normalized() * 34.0, b["pos"].normalized())

			"smelter":
				if pwr <= 0.05:
					continue
				if _buf_total(b["out_buf"]) >= BUFFER_CAP_OUT:
					b["blocked"] = true
					continue
				var inb: Dictionary = b["in_buf"]
				if b["timer"] >= 2.0:
					b["timer"] = 0.0
					if int(inb.get("fe", 0)) >= 2:
						inb["fe"] -= 2
						if inb["fe"] <= 0: inb.erase("fe")
						_buf_add(b["out_buf"], "plate_fe", 1)
					elif int(inb.get("cu", 0)) >= 2:
						inb["cu"] -= 2
						if inb["cu"] <= 0: inb.erase("cu")
						_buf_add(b["out_buf"], "wire_cu", 1)
					elif int(inb.get("si", 0)) >= 2:
						inb["si"] -= 2
						if inb["si"] <= 0: inb.erase("si")
						_buf_add(b["out_buf"], "wafer_si", 1)
					b["frame"] = (b["frame"] + 1) % 3

			"assembler":
				if pwr <= 0.05:
					continue
				if _buf_total(b["out_buf"]) >= BUFFER_CAP_OUT:
					b["blocked"] = true
					continue
				var rec: String = String(b.get("recipe", "circuit"))
				var ib: Dictionary = b["in_buf"]
				if b["timer"] >= 2.4:
					b["timer"] = 0.0
					if rec == "circuit" and int(ib.get("plate_fe", 0)) >= 1 and int(ib.get("wire_cu", 0)) >= 1:
						ib["plate_fe"] -= 1; ib["wire_cu"] -= 1
						if ib["plate_fe"] <= 0: ib.erase("plate_fe")
						if ib["wire_cu"] <= 0: ib.erase("wire_cu")
						_buf_add(b["out_buf"], "circuit", 1)
					elif rec == "alloy" and int(ib.get("plate_fe", 0)) >= 2 and int(ib.get("ti", 0)) >= 1:
						ib["plate_fe"] -= 2; ib["ti"] -= 1
						if ib["plate_fe"] <= 0: ib.erase("plate_fe")
						if ib["ti"] <= 0: ib.erase("ti")
						_buf_add(b["out_buf"], "alloy", 1)
					elif rec == "sci_pack" and int(ib.get("plate_fe", 0)) >= 1 and int(ib.get("circuit", 0)) >= 1:
						ib["plate_fe"] -= 1; ib["circuit"] -= 1
						if ib["plate_fe"] <= 0: ib.erase("plate_fe")
						if ib["circuit"] <= 0: ib.erase("circuit")
						_buf_add(b["out_buf"], "sci_pack", 1)
						GameState.add_res("sci_pack", 1, false)
					b["frame"] = (b["frame"] + 1) % 4

			"printer":
				if pwr <= 0.05:
					continue
				if b["timer"] >= 4.0:
					b["timer"] = 0.0
					if int(b["in_buf"].get("circuit", 0)) >= 1 and int(b["in_buf"].get("plate_fe", 0)) >= 2:
						b["in_buf"]["circuit"] -= 1; b["in_buf"]["plate_fe"] -= 2
						if b["in_buf"]["circuit"] <= 0: b["in_buf"].erase("circuit")
						if b["in_buf"]["plate_fe"] <= 0: b["in_buf"].erase("plate_fe")
						_buf_add(b["out_buf"], "probe_stock", 1)
					elif GameState.can_afford({"circuit": 1, "plate_fe": 2}):
						GameState.spend_cost({"circuit": 1, "plate_fe": 2})
						GameState.add_res("probe_stock", 1, false)
					b["frame"] = (b["frame"] + 1) % 4

			"mass_driver":
				if pwr <= 0.05:
					continue
				if b["timer"] >= 3.2:
					b["timer"] = 0.0
					var used_buf = false
					if not b["in_buf"].is_empty():
						var _pi = _buf_take_one(b["in_buf"], "auto")
						used_buf = (_pi != "")
					elif GameState.probe_stock > 0:
						GameState.add_res("probe_stock", -1)
						used_buf = true
					elif GameState.can_afford({"plate_fe": 2, "circuit": 1}):
						GameState.spend_cost({"plate_fe": 2, "circuit": 1})
						used_buf = true
					if used_buf:
						b["charge_t"] = 1.0
						GameState.total_launches += 1
						GameState.add_fleet_units(1)
						var dir_out = Vector2(b["pos"]).normalized()
						projectiles.append({"pos": b["pos"] + dir_out * 64.0, "vel": dir_out * 920.0, "life": 6.0})
						AudioSynth.play_synth("launch")

			"turret":
				if pwr <= 0.05:
					continue
				if b["timer"] >= 0.72 and swarm_sim and swarm_sim.has_method("find_nearest_hostile"):
					var tgt: Vector2 = swarm_sim.find_nearest_hostile(b["pos"], 1150.0)
					if tgt != Vector2.ZERO:
						b["timer"] = 0.0
						swarm_sim.damage_hostile_near(tgt, 26.0)
						laser_beams.append({"a": b["pos"] + b["pos"].normalized() * 26.0, "b": tgt, "life": 0.14})
						AudioSynth.play_synth("laser")

	# Move physical items along Powered Belts & Lifts (STOP when belt unpowered or dead-ended!)
	for i in range(belt_items.size() - 1, -1, -1):
		var it = belt_items[i]
		var cur_b = _get_building_at(it["sec"], it["layer"])
		if cur_b.is_empty() or (cur_b["id"] != "belt" and cur_b["id"] != "lift"):
			belt_items.remove_at(i)
			continue
		it["dir"] = int(cur_b.get("dir", 1))
		var b_pwr = float(cur_b.get("pwr_ratio", 0.0))
		if b_pwr <= 0.05:
			continue
		it["t"] = minf(1.02, float(it["t"]) + delta * 1.15 * b_pwr)
		if float(it["t"]) >= 1.0:
			var ns = world.wrap_sector(it["sec"] + it["dir"]) if not it["is_lift"] else it["sec"]
			var nl = it["layer"] if not it["is_lift"] else (it["layer"] + it["dir"])
			var nxt_b = _get_building_at(ns, nl)
			if not nxt_b.is_empty():
				var nbid: String = nxt_b["id"]
				if nbid == "belt" or nbid == "lift":
					if _count_belt_items_at(ns, nl, 0.35) < 2:
						it["sec"] = ns
						it["layer"] = nl
						it["t"] = 0.04
						it["is_lift"] = (nbid == "lift")
					else:
						it["t"] = 0.96
				elif _deliver_to_target(nxt_b, it["item"]):
					belt_items.remove_at(i)
				else:
					it["t"] = 0.96
			else:
				it["t"] = 0.96 # Hold safely at belt end (never vanishes!)

	# Mass driver projectiles
	for i in range(projectiles.size() - 1, -1, -1):
		var pr = projectiles[i]
		if world:
			pr["vel"] += world.compute_gravity_at(pr["pos"]) * delta * 0.35
		pr["pos"] += pr["vel"] * delta
		pr["life"] -= delta
		if pr["life"] <= 0.0:
			projectiles.remove_at(i)

	for i in range(laser_beams.size() - 1, -1, -1):
		laser_beams[i]["life"] -= delta
		if laser_beams[i]["life"] <= 0.0:
			laser_beams.remove_at(i)

	if GameState.selected_tool != "" and GameState.BUILDINGS.has(GameState.selected_tool):
		refresh_blueprint_slots()
	queue_redraw()

# ------------------------------------------------------------------------------
# SPHERICAL RENDERING + POWER WIRES / TESLA DOMES / LOGISTICS OVERLAY
# ------------------------------------------------------------------------------
func _draw() -> void:
	if not world:
		return

	var cam = get_viewport().get_camera_2d()
	var cpos = cam.global_position if cam else Vector2.ZERO
	var vrect = get_viewport_rect()
	var z_f = (1.0 / cam.zoom.x) if cam else 1.0
	var max_view_d = maxf(vrect.size.x, vrect.size.y) * 0.75 * z_f + 900.0

	# 1. Holographic Blueprint Ghost Slots
	if GameState.BUILDINGS.has(GameState.selected_tool):
		for i in range(blueprint_slots.size()):
			var sl = blueprint_slots[i]
			if sl["pos"].distance_to(cpos) > max_view_d:
				continue
			var is_act = (i == active_ghost_idx)
			var col = Color(0.28, 1.0, 0.72, 0.72) if is_act else Color(0.25, 0.75, 1.0, 0.28)
			draw_set_transform(sl["pos"], sl["rot"], Vector2.ONE)
			var hw = sl["w_px"] * 0.46
			var h = sl["h_px"]
			var rc = Rect2(-hw, -h, hw * 2.0, h)
			draw_rect(rc, Color(col.r, col.g, col.b, col.a * 0.25), true)
			draw_rect(rc, col, false, 2.2 if is_act else 1.2)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 2. Tesla Power Domes (under buildings)
	for b in buildings:
		if b["id"] == "tesla" and Vector2(b["pos"]).distance_to(cpos) <= max_view_d + TESLA_DOME_R:
			var pwr = float(b.get("pwr_ratio", 0.0))
			var col_d = Color(0.25, 0.92, 1.0, 0.14 if pwr > 0.05 else 0.05)
			var ring_d = Color(0.32, 0.96, 1.0, 0.65 if pwr > 0.05 else 0.25)
			draw_circle(b["pos"], TESLA_DOME_R, col_d)
			draw_arc(b["pos"], TESLA_DOME_R, 0.0, TAU, 48, ring_d, 2.0 if pwr > 0.05 else 1.0)

	# 3. Glowing Power Wires (Solar/Geo/Battery <-> Tesla)
	for w in wires:
		var b1 = _get_building_by_uid(int(w[0]))
		var b2 = _get_building_by_uid(int(w[1]))
		if b1.is_empty() or b2.is_empty():
			continue
		var p1 = Vector2(b1["pos"]) + Vector2(b1["pos"]).normalized() * 24.0
		var p2 = Vector2(b2["pos"]) + Vector2(b2["pos"]).normalized() * 24.0
		if p1.distance_to(cpos) > max_view_d + WIRE_RANGE:
			continue
		var live = float(b1.get("pwr_ratio", 0.0)) > 0.05 or float(b2.get("pwr_ratio", 0.0)) > 0.05
		var w_col = Color(0.28, 0.95, 1.0, 0.88) if live else Color(0.65, 0.45, 0.25, 0.55)
		draw_line(p1, p2, w_col, 3.0 if live else 2.0)
		if live:
			var t_pulse = fposmod(anim_time * 0.9, 1.0)
			var pp = p1.lerp(p2, t_pulse)
			draw_circle(pp, 4.5, Color(0.85, 1.0, 1.0, 0.95))

	# Wire-in-progress rubber band to player
	if wire_pick_uid > 0 and player:
		var wb = _get_building_by_uid(wire_pick_uid)
		if not wb.is_empty():
			var p0 = Vector2(wb["pos"]) + Vector2(wb["pos"]).normalized() * 24.0
			draw_line(p0, player.position, Color(1.0, 0.85, 0.30, 0.85), 2.5)

	# 4. Physical Buildings + Status Badges
	var font = ThemeDB.fallback_font
	for b in buildings:
		var bpos: Vector2 = b["pos"]
		if bpos.distance_to(cpos) > max_view_d:
			continue
		var bid: String = b["id"]
		var info = GameState.BUILDINGS[bid]
		var w = b["w_px"]
		var h = float(info["h_px"])
		var tex: Texture2D = sprite_textures.get(bid, null)
		var pwr = float(b.get("pwr_ratio", 0.0))

		draw_set_transform(bpos, b["rot"], Vector2.ONE)
		if bid == "tesla":
			# Bespoke Glowing Copper Tesla Tower
			draw_rect(Rect2(-14, -14, 28, 14), Color(0.24, 0.34, 0.48, 1.0), true)
			draw_rect(Rect2(-6, -h * 0.82, 12, h * 0.70), Color(0.78, 0.48, 0.22, 1.0), true)
			for ci in range(4):
				draw_line(Vector2(-9, -18 - ci * 9), Vector2(9, -18 - ci * 9), Color(1.0, 0.72, 0.32), 2.0)
			var orb_c = Color(0.30, 0.95, 1.0) if pwr > 0.05 else Color(0.42, 0.48, 0.56)
			draw_circle(Vector2(0, -h * 0.88), 11.0, orb_c)
			if pwr > 0.05:
				draw_circle(Vector2(0, -h * 0.88), 16.0 + 3.0 * sin(anim_time * 6.0), Color(0.35, 0.95, 1.0, 0.32))
		elif bid == "battery":
			draw_rect(Rect2(-w * 0.42, -h, w * 0.84, h), Color(0.14, 0.22, 0.34, 1.0), true)
			draw_rect(Rect2(-w * 0.42, -h, w * 0.84, h), Color(0.35, 0.82, 1.0, 0.9), false, 2.0)
			var ch_f = clampf(float(b.get("battery_kj", 0.0)) / BATTERY_CAP_KJ, 0.0, 1.0)
			draw_rect(Rect2(-w * 0.32, -h + 6.0 + (h - 12.0) * (1.0 - ch_f), w * 0.64, (h - 12.0) * ch_f), Color(0.28, 0.96, 0.68), true)
		elif tex:
			var cols = int(info.get("frames", 1))
			var col_idx = int(b["frame"]) % maxi(1, cols)
			var tw = float(tex.get_width()) / float(maxi(1, cols))
			var th = float(tex.get_height())
			var mod = Color.WHITE if (pwr > 0.05 or bid in ["depot", "solar", "geothermal", "elevator"]) else Color(0.55, 0.55, 0.65, 0.85)
			draw_texture_rect_region(tex, Rect2(-w * 0.48, -h, w * 0.96, h), Rect2(col_idx * tw, 0, tw, th), mod)

		# Drill / Machine Buffer Fill Bar
		if bid in ["drill", "smelter", "assembler"]:
			var cap = BUFFER_CAP_DRILL if bid == "drill" else BUFFER_CAP_OUT
			var fill = float(_buf_total(b["out_buf"])) / float(cap)
			if fill > 0.0:
				var fcol = Color(1.0, 0.45, 0.25) if b["blocked"] else Color(0.35, 0.98, 0.68)
				draw_rect(Rect2(-w * 0.36, -h - 9.0, w * 0.72 * clampf(fill, 0.0, 1.0), 4.0), fcol, true)
		if bid == "belt" or bid == "lift":
			var arrow_x = float(b["dir"]) * 12.0
			draw_line(Vector2(-arrow_x, -6.0), Vector2(arrow_x, -6.0), Color(1.0, 0.85, 0.28, 0.9), 2.5)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

		# Diegetic floating status text
		if font:
			var lbl_pos = bpos + bpos.normalized() * (h + 12.0) + Vector2(-26.0, 0.0)
			if pwr <= 0.05 and float(info.get("power", 0)) < 0.0:
				draw_string(font, lbl_pos, "NO PWR", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.32, 0.35, 0.95))
			elif b["blocked"]:
				draw_string(font, lbl_pos, "FULL", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.76, 0.22, 0.95))
			elif bid == "depot":
				draw_string(font, lbl_pos, "DEPOT[%d]" % _buf_total(b["inv"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.95, 0.84, 0.35, 0.95))
			elif bid == "assembler":
				draw_string(font, lbl_pos, String(b.get("recipe", "circuit")).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.55, 0.95, 1.0, 0.92))

		if bid == "elevator" and tex_orbital_hub:
			var dock_r = PlanetWorld.R_ATMOS_OUTER + 420.0
			var dock_ang = (float(b["sec"]) + 1.0) * PlanetWorld.DA
			var dock_pos = world.polar_to_world(dock_ang, dock_r)
			draw_line(bpos, dock_pos, Color(0.32, 0.88, 1.0, 0.65), 6.0)
			if dock_pos.distance_to(cpos) <= max_view_d + 240.0:
				draw_set_transform(dock_pos, dock_ang + PI * 0.5, Vector2.ONE)
				draw_texture_rect(tex_orbital_hub, Rect2(-120, -120, 240, 240), false)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 5. Moving Items on Arc Belts & Radial Lifts
	for it in belt_items:
		var ip = _belt_item_world_pos(it)
		if ip.distance_to(cpos) > max_view_d:
			continue
		var ic: Texture2D = item_icons.get(it["item"], null)
		if ic:
			draw_texture_rect(ic, Rect2(ip - Vector2(12, 12), Vector2(24, 24)), false)

	# 6. Turret Laser Beams & Mass Driver Projectiles
	for lb in laser_beams:
		draw_line(lb["a"], lb["b"], Color(0.28, 0.95, 1.0, 0.9), 3.0)
	for pr in projectiles:
		draw_circle(pr["pos"], 12.0, Color(1.0, 0.65, 0.25))

# ------------------------------------------------------------------------------
# SERIALIZATION
# ------------------------------------------------------------------------------
func to_dict() -> Dictionary:
	return {
		"next_uid": next_uid,
		"buildings": buildings.duplicate(true),
		"wires": wires.duplicate(true),
		"belt_items": belt_items.duplicate(true),
	}

func from_dict(d: Dictionary) -> void:
	clear_factory()
	next_uid = int(d.get("next_uid", 1))
	for b in d.get("buildings", []):
		if not GameState.BUILDINGS.has(b.get("id", "")):
			continue
		var ws = int(b["sec"])
		var layer = int(b["layer"])
		var sw = int(b.get("sec_w", 1))
		var pose = _slot_world_pose(ws, layer, sw)
		var nb = {
			"uid": int(b.get("uid", next_uid)),
			"id": b["id"], "sec": ws, "layer": layer, "sec_w": sw,
			"dir": int(b.get("dir", 1)),
			"pos": pose["pos"], "rot": pose["rot"], "w_px": pose["w_px"],
			"timer": float(b.get("timer", 0.0)), "push_t": 0.0, "smoke_t": 0.0,
			"charge_t": 0.0, "frame": int(b.get("frame", 0)),
			"ore_target": String(b.get("ore_target", "fe")),
			"in_buf": Dictionary(b.get("in_buf", {})).duplicate(),
			"out_buf": Dictionary(b.get("out_buf", {})).duplicate(),
			"inv": Dictionary(b.get("inv", {})).duplicate(),
			"out_filters": Dictionary(b.get("out_filters", {"left": "auto", "right": "auto", "up": "none", "down": "none"})).duplicate(),
			"recipe": String(b.get("recipe", "circuit")),
			"battery_kj": float(b.get("battery_kj", 0.0)),
			"pwr_ratio": 0.0, "wired": false, "blocked": false,
		}
		if nb["uid"] >= next_uid:
			next_uid = nb["uid"] + 1
		var idx = buildings.size()
		buildings.append(nb)
		for ds in range(sw):
			occupied[_key(ws + ds, layer)] = idx
	for w in d.get("wires", []):
		if w is Array and w.size() >= 2:
			wires.append([int(w[0]), int(w[1])])
	for it in d.get("belt_items", []):
		belt_items.append(it)
	_recompute_local_grids(0.0)
	refresh_blueprint_slots()
	queue_redraw()
