extends Node2D
class_name FactorySim

# ==============================================================================
# STAR REPLICA: AUTOMA - 360-DEGREE SPHERICAL FACTORY & MASS DRIVER SIMULATION
# Every facility snaps cleanly to spherical sectors/layers and aligns along
# planetary surface normals around the entire globe.
# ==============================================================================

var world: PlanetWorld
var swarm_sim: Node2D
var player: Node2D

# Buildings: {id, sec: int, layer: int, sec_w: int, dir: int, timer, smoke_t, charge_t, frame, ore_target}
var buildings: Array[Dictionary] = []
# Occupancy key "s,l" -> building idx
var occupied: Dictionary = {}

# Moving items on curved surface belts & radial lifts: {sec: int, layer: int, t: float, item: String}
var belt_items: Array[Dictionary] = []

# Mass Driver orbital projectiles
var projectiles: Array[Dictionary] = []
var laser_beams: Array[Dictionary] = []

# Nearby Holographic Blueprint Ghost Slots: {sec: int, layer: int, sec_w: int, pos: Vector2, rot: float, w_px: float, h_px: float}
var blueprint_slots: Array[Dictionary] = []
var active_ghost_idx: int = -1

var sprite_textures: Dictionary = {}
var item_icons: Dictionary = {}
var tex_orbital_hub: Texture2D
var anim_time: float = 0.0

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
		"plate_fe": load("res://assets/ui/item_plate_fe.png"),
		"wire_cu": load("res://assets/ui/item_wire_cu.png"),
		"wafer_si": load("res://assets/ui/item_silicon_wafer.png"),
		"circuit": load("res://assets/ui/item_circuit.png"),
		"alloy": load("res://assets/ui/item_alloy.png"),
		"probe": load("res://assets/ui/item_drone_unit.png"),
	}

func _on_tool_changed(_id: String) -> void:
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
			if layer != PlanetWorld.LAYERS:
				return false
			for ds in range(sec_w):
				if not world.is_solid_cell(ws + ds, PlanetWorld.LAYERS - 1):
					return false
			return true
		"UNDERGROUND":
			if layer < 1 or layer >= PlanetWorld.LAYERS:
				return false
			if bid == "drill":
				return world.is_solid_cell(ws, layer)
			return true # Lift can be routed radially through shafts/crust up to surface
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
		for offset in range(-22, 23):
			var s = world.wrap_sector(base_sec + offset)
			var l = PlanetWorld.LAYERS
			if can_place_building(bid, s, l):
				var pose = _slot_world_pose(s, l, sec_w)
				blueprint_slots.append({
					"sec": s, "layer": l, "sec_w": sec_w,
					"pos": pose["pos"], "rot": pose["rot"],
					"w_px": pose["w_px"], "h_px": h_px,
				})
	elif rule == "UNDERGROUND":
		for l in range(maxi(1, pcell.y - 3), mini(PlanetWorld.LAYERS, pcell.y + 3)):
			for offset in range(-8, 9):
				var s = world.wrap_sector(base_sec + offset)
				if bid == "drill" and world.get_ore(s, l) == "":
					continue
				if can_place_building(bid, s, l):
					var pose = _slot_world_pose(s, l, sec_w)
					blueprint_slots.append({
						"sec": s, "layer": l, "sec_w": sec_w,
						"pos": pose["pos"], "rot": pose["rot"],
						"w_px": pose["w_px"], "h_px": h_px,
					})
	elif rule == "DEEP_ROCK":
		for l in range(1, 4):
			for offset in range(-8, 9, 2):
				var s = world.wrap_sector(base_sec + offset)
				if can_place_building(bid, s, l):
					var pose = _slot_world_pose(s, l, sec_w)
					blueprint_slots.append({
						"sec": s, "layer": l, "sec_w": sec_w,
						"pos": pose["pos"], "rot": pose["rot"],
						"w_px": pose["w_px"], "h_px": h_px,
					})

	# Focus nearest ghost to player for instant single-button [A] construction!
	if player and blueprint_slots.size() > 0:
		var best_d = 999999.0
		for i in range(blueprint_slots.size()):
			var d = blueprint_slots[i]["pos"].distance_to(player.position)
			if d < best_d:
				best_d = d
				active_ghost_idx = i

func try_build_nearest_ghost() -> bool:
	refresh_blueprint_slots()
	if active_ghost_idx < 0 or active_ghost_idx >= blueprint_slots.size():
		return false
	var sl = blueprint_slots[active_ghost_idx]
	return try_place_building(GameState.selected_tool, sl["sec"], sl["layer"])

func try_handle_click_at(world_pos: Vector2) -> bool:
	var tool_id = GameState.selected_tool
	if tool_id == "demolish":
		return try_demolish_at(world_pos)
	if not GameState.BUILDINGS.has(tool_id):
		return false

	for sl in blueprint_slots:
		var center_off = Vector2(cos(sl["rot"] - PI * 0.5), sin(sl["rot"] - PI * 0.5)) * (sl["h_px"] * 0.5)
		if (sl["pos"] + center_off).distance_to(world_pos) <= maxf(34.0, sl["w_px"] * 0.7):
			return try_place_building(tool_id, sl["sec"], sl["layer"])

	var cell = world.pos_to_cell(world_pos)
	var target_l = PlanetWorld.LAYERS if world_pos.length() >= PlanetWorld.R_SURFACE - 16.0 else cell.y
	if can_place_building(tool_id, cell.x, target_l):
		return try_place_building(tool_id, cell.x, target_l)
	return false

func try_place_building(bid: String, sec: int, layer: int) -> bool:
	if not GameState.BUILDINGS.has(bid):
		return false
	var info = GameState.BUILDINGS[bid]
	var sec_w = int(info.get("sec_w", 1))
	var ws = world.wrap_sector(sec)
	var pose = _slot_world_pose(ws, layer, sec_w)
	var popup_pos = pose["pos"] + Vector2(cos(pose["ang"]), sin(pose["ang"])) * 32.0

	var req_d = int(info.get("req_drones", 0))
	if GameState.drones < req_d:
		if world:
			world.spawn_world_popup(popup_pos, "NEED %d DRONES" % req_d, Color(1.0, 0.28, 0.28))
		GameState.emit_signal("log_event", "%s requires %d Drones" % [info["name"], req_d], "error")
		AudioSynth.play_synth("error")
		return false

	if not can_place_building(bid, ws, layer):
		if world:
			world.spawn_world_popup(popup_pos, "INVALID SLOT", Color(1.0, 0.35, 0.28))
		AudioSynth.play_synth("error")
		return false

	var cost: Dictionary = info["cost"]
	if not GameState.spend_cost(cost):
		var miss = GameState.get_missing_text(cost)
		if world:
			world.spawn_world_popup(popup_pos, miss, Color(1.0, 0.22, 0.22))
		GameState.emit_signal("log_event", miss, "error")
		AudioSynth.play_synth("error")
		return false

	var idx = buildings.size()
	buildings.append({
		"id": bid,
		"sec": ws,
		"layer": layer,
		"sec_w": sec_w,
		"dir": GameState.build_rotation,
		"timer": 0.0,
		"smoke_t": 0.0,
		"charge_t": 0.0,
		"frame": 0,
		"ore_target": world.get_ore(ws, layer) if bid == "drill" else "",
	})
	for ds in range(sec_w):
		occupied[_key(ws + ds, layer)] = idx

	if bid in GameState.megastructures:
		GameState.megastructures[bid] = true
		AudioSynth.play_synth("mega")
		GameState.emit_signal("log_event", "MEGASTRUCTURE: %s" % info["name"], "good")
		if GameState.boss_defeated and GameState.megastructures["warpgate"]:
			GameState.game_won = true
			GameState.emit_signal("log_event", "COLONY VICTORY: WARP GATE & CORE LIBERATED!", "good")
	else:
		AudioSynth.play_synth("build")
		GameState.emit_signal("log_event", "Built %s" % info["name"], "good")

	if world:
		world.spawn_spark_burst(popup_pos, Color(0.25, 0.92, 1.0), 10)
	_recompute_power_grid()
	refresh_blueprint_slots()
	queue_redraw()
	return true

func try_demolish_at(world_pos: Vector2) -> bool:
	var best_idx = -1
	var best_d = 46.0
	for i in range(buildings.size()):
		var b = buildings[i]
		var pose = _slot_world_pose(b["sec"], b["layer"], b["sec_w"])
		var d = pose["pos"].distance_to(world_pos)
		if d < best_d:
			best_d = d
			best_idx = i
	if best_idx == -1:
		return false

	var rb = buildings[best_idx]
	var info = GameState.BUILDINGS.get(rb["id"], {})
	var cost: Dictionary = info.get("cost", {})
	for rname in cost.keys():
		GameState.add_res(rname, maxi(1, int(cost[rname]) / 2))

	buildings.remove_at(best_idx)
	occupied.clear()
	for i in range(buildings.size()):
		var bb = buildings[i]
		for ds in range(bb["sec_w"]):
			occupied[_key(bb["sec"] + ds, bb["layer"])] = i

	_recompute_power_grid()
	refresh_blueprint_slots()
	AudioSynth.play_synth("pop")
	GameState.emit_signal("log_event", "Salvaged %s" % info.get("name", rb["id"]), "info")
	queue_redraw()
	return true

func _recompute_power_grid() -> void:
	var gen = 15.0 + float(GameState.drones) * 3.0
	var use = 0.0
	for b in buildings:
		var info = GameState.BUILDINGS.get(b["id"], {})
		var p = float(info.get("power", 0.0))
		if p > 0.0: gen += p
		elif p < 0.0: use += -p
	GameState.power_gen = gen
	GameState.power_use = use
	GameState.power_ratio = 1.0 if use <= 0.01 else clampf(gen / use, 0.25, 1.25)
	GameState.emit_signal("state_updated")

func _find_adj_belt_or_lift(sec: int, layer: int, sec_w: int) -> Vector2i:
	for dl in range(-1, 2):
		for ds in range(-1, sec_w + 1):
			var ws = world.wrap_sector(sec + ds)
			var tl = layer + dl
			var k = _key(ws, tl)
			if occupied.has(k):
				var nb = buildings[occupied[k]]
				if nb["id"] in ["belt", "lift"]:
					return Vector2i(ws, tl)
	return Vector2i(-1, -1)

func _spawn_belt_item(s: int, l: int, item: String) -> void:
	if belt_items.size() > 140: return
	belt_items.append({"sec": s, "layer": l, "t": 0.0, "item": item})

func _process(delta: float) -> void:
	anim_time += delta
	if GameState.selected_tool in GameState.BUILDINGS and Engine.get_process_frames() % 6 == 0:
		refresh_blueprint_slots()

	var p_eff = GameState.power_ratio
	var has_elev = GameState.megastructures["elevator"]
	var has_dyson = GameState.megastructures["dyson"]
	var printer_any = false

	for b in buildings:
		var bid: String = b["id"]
		b["timer"] += delta * p_eff
		b["smoke_t"] += delta
		var pose = _slot_world_pose(b["sec"], b["layer"], b["sec_w"])

		match bid:
			"drill":
				b["frame"] = int(anim_time * 9.0) % 4
				if b["timer"] >= 1.1:
					b["timer"] = 0.0
					var oname: String = b.get("ore_target", "fe")
					if oname == "": oname = "fe"
					GameState.add_res(oname, 2)
					if oname != "fe":
						GameState.add_res("fe", 1)
					var bp = _find_adj_belt_or_lift(b["sec"], b["layer"], b["sec_w"])
					if bp.x >= 0: _spawn_belt_item(bp.x, bp.y, oname)
			"belt", "lift":
				b["frame"] = int(anim_time * 8.0) % 4
			"smelter":
				b["frame"] = int(anim_time * 5.0) % 4
				if b["timer"] >= 1.3:
					b["timer"] = 0.0
					# Balance refined Plate / Wire / Wafer cleanly without starving raw reserve
					var opts: Array = []
					if GameState.fe >= 16 and GameState.plate_fe < 30:
						opts.append(["fe", "plate_fe", GameState.plate_fe])
					if GameState.cu >= 16 and GameState.wire_cu < 24:
						opts.append(["cu", "wire_cu", GameState.wire_cu])
					if GameState.si >= 24 and GameState.wafer_si < 16:
						opts.append(["si", "wafer_si", GameState.wafer_si])
					if not opts.is_empty():
						opts.sort_custom(func(a, c): return a[2] < c[2])
						var pick = opts[0]
						GameState.add_res(pick[0], -1)
						GameState.add_res(pick[1], 1)
						var bp = _find_adj_belt_or_lift(b["sec"], b["layer"], b["sec_w"])
						if bp.x >= 0: _spawn_belt_item(bp.x, bp.y, pick[1])
				if b["smoke_t"] >= 0.45 and world:
					b["smoke_t"] = 0.0
					var up_dir = Vector2(cos(pose["ang"]), sin(pose["ang"]))
					world.spawn_smoke_puff(pose["pos"] + up_dir * 46.0, up_dir)
			"assembler":
				b["frame"] = int(anim_time * 6.0) % 4
				if b["timer"] >= 1.7:
					b["timer"] = 0.0
					var made = ""
					if GameState.circuit < 18 and GameState.wire_cu >= 1 and GameState.wafer_si >= 1:
						GameState.add_res("wire_cu", -1); GameState.add_res("wafer_si", -1); GameState.add_res("circuit", 1); made = "circuit"
					elif GameState.circuit < 14 and GameState.cu >= 18 and GameState.si >= 20:
						GameState.add_res("cu", -2); GameState.add_res("si", -1); GameState.add_res("circuit", 1); made = "circuit"
					elif GameState.ti >= 160 and GameState.plate_fe >= 1:
						GameState.add_res("plate_fe", -1); GameState.add_res("ti", -1); GameState.add_res("alloy", 1); made = "alloy"
					if made != "":
						var bp = _find_adj_belt_or_lift(b["sec"], b["layer"], b["sec_w"])
						if bp.x >= 0: _spawn_belt_item(bp.x, bp.y, made)
			"printer":
				printer_any = true
				b["frame"] = int(anim_time * 7.0) % 4
				var spd = (0.4 if not has_elev else 0.78) * (1.35 if has_dyson else 1.0)
				if b["timer"] >= 1.0 / spd:
					var printed = false
					if GameState.probe_stock < 12:
						if GameState.plate_fe >= 2 and GameState.circuit >= 1:
							GameState.add_res("plate_fe", -2); GameState.add_res("circuit", -1); printed = true
						elif GameState.fe >= 18 and GameState.cu >= 10:
							GameState.add_res("fe", -6); GameState.add_res("cu", -2); printed = true
					if printed:
						b["timer"] = 0.0
						GameState.add_res("probe_stock", 1)
						GameState.printer_progress = 1.0
				else:
					GameState.printer_progress = clampf(b["timer"] * spd, 0.0, 0.99)
				if b["smoke_t"] >= 0.35 and world:
					b["smoke_t"] = 0.0
					var up_dir = Vector2(cos(pose["ang"]), sin(pose["ang"]))
					world.spawn_smoke_puff(pose["pos"] + up_dir * 56.0, up_dir)
			"mass_driver":
				if b["charge_t"] > 0.0:
					b["charge_t"] -= delta
					b["frame"] = clampi(int((1.0 - b["charge_t"] / 0.85) * 4.0), 0, 3)
					if b["charge_t"] <= 0.0:
						_fire_mass_driver(pose)
				elif GameState.probe_stock >= 1 and b["timer"] >= 1.1:
					GameState.add_res("probe_stock", -1)
					b["timer"] = 0.0
					b["charge_t"] = 0.85
					b["frame"] = 1
				else:
					b["frame"] = 0
			"turret":
				if b["timer"] >= 1.2 and swarm_sim and swarm_sim.has_method("find_nearest_hostile"):
					var tpos = pose["pos"] + Vector2(cos(pose["ang"]), sin(pose["ang"])) * 18.0
					var h_pos = swarm_sim.find_nearest_hostile(tpos, 580.0)
					if h_pos != Vector2.ZERO:
						b["timer"] = 0.0
						swarm_sim.damage_hostile_near(h_pos, 35.0)
						laser_beams.append({"from": tpos, "to": h_pos, "life": 0.14})
						AudioSynth.play_synth("laser")

	GameState.printer_active = printer_any

	# Belt item travel around sphere
	for i in range(belt_items.size() - 1, -1, -1):
		var it = belt_items[i]
		it["t"] += delta * 2.4 * p_eff
		if it["t"] >= 1.0:
			it["t"] = 0.0
			var k = _key(it["sec"], it["layer"])
			if occupied.has(k):
				var b = buildings[occupied[k]]
				if b["id"] == "lift":
					it["layer"] += 1
				elif b["id"] == "belt":
					it["sec"] = world.wrap_sector(it["sec"] + int(b["dir"]))
				else:
					belt_items.remove_at(i); continue
			else:
				belt_items.remove_at(i); continue
			if not occupied.has(_key(it["sec"], it["layer"])):
				belt_items.remove_at(i)

	# Launched projectiles flying outward under planetary gravity into orbit
	for i in range(projectiles.size() - 1, -1, -1):
		var pr = projectiles[i]
		pr["trail"].append(pr["pos"])
		if pr["trail"].size() > 14: pr["trail"].remove_at(0)
		if world:
			pr["vel"] += world.compute_gravity_at(pr["pos"]) * delta * 0.45
		pr["pos"] += pr["vel"] * delta
		if pr["pos"].length() >= pr["target_r"]:
			var add_amt = 1
			if GameState.megastructures["elevator"]: add_amt += 1
			if GameState.megastructures["warpgate"]: add_amt += 2
			GameState.add_fleet_units(add_amt)
			GameState.total_launches += 1
			GameState.emit_signal("probe_launched", pr["pos"])
			if swarm_sim and swarm_sim.has_method("spawn_friendly_units"):
				swarm_sim.spawn_friendly_units(add_amt, pr["pos"])
			if world:
				world.spawn_spark_burst(pr["pos"], Color(0.25, 0.95, 1.0), 8)
				world.spawn_world_popup(pr["pos"], "+%d SWARM" % add_amt, Color(0.35, 0.95, 1.0))
			projectiles.remove_at(i)

	for li in range(laser_beams.size() - 1, -1, -1):
		laser_beams[li]["life"] -= delta
		if laser_beams[li]["life"] <= 0.0:
			laser_beams.remove_at(li)

	queue_redraw()

func _fire_mass_driver(pose: Dictionary) -> void:
	var n_dir = Vector2(cos(pose["ang"]), sin(pose["ang"]))
	var tang = Vector2(-n_dir.y, n_dir.x)
	var muzzle = pose["pos"] + n_dir * 64.0 + tang * 14.0
	projectiles.append({
		"pos": muzzle,
		"vel": (n_dir * 0.92 + tang * 0.30).normalized() * 980.0,
		"target_r": PlanetWorld.R_SURFACE + 520.0,
		"trail": [muzzle],
	})
	if world:
		world.spawn_spark_burst(muzzle, Color(0.55, 0.96, 1.0), 12)
	AudioSynth.play_synth("launch")

func _draw() -> void:
	var font = ThemeDB.fallback_font
	# 1. Draw radially aligned buildings around the 360-degree sphere
	for b in buildings:
		var bid: String = b["id"]
		var info = GameState.BUILDINGS.get(bid, {})
		var pose = _slot_world_pose(b["sec"], b["layer"], b["sec_w"])
		var h_px = float(info.get("h_px", 40.0)) * 1.45
		var w_px = maxf(36.0, pose["w_px"] * 1.02)
		var rect = Rect2(-w_px * 0.5, -h_px, w_px, h_px)

		draw_set_transform(pose["pos"], pose["rot"])
		# Subtle foundation plinth so machinery pops cleanly against space & planet crust
		if b["layer"] >= PlanetWorld.LAYERS and bid != "belt":
			draw_rect(Rect2(-w_px * 0.46, -4.0, w_px * 0.92, 6.0), Color(0.14, 0.24, 0.36, 0.92))
			draw_line(Vector2(-w_px * 0.42, -4.0), Vector2(w_px * 0.42, -4.0), Color(0.32, 0.85, 1.0, 0.55), 1.4)
		var tex: Texture2D = sprite_textures.get(bid, null)
		var frames = int(info.get("frames", 1))
		if tex:
			if frames > 1:
				var fw = float(tex.get_width()) / float(frames)
				var src = Rect2(clampi(int(b.get("frame", 0)), 0, frames - 1) * fw, 0.0, fw, float(tex.get_height()))
				var dst = rect
				if bid == "belt" and int(b.get("dir", 1)) < 0:
					dst.position.x += dst.size.x
					dst.size.x = -dst.size.x
				draw_texture_rect_region(tex, dst, src)
			else:
				draw_texture_rect(tex, rect, false)
		draw_set_transform(Vector2.ZERO, 0.0)

		# Player-constructed Orbital Shipyard Hub anchored cleanly ONLY after Space Elevator is built!
		if bid == "elevator" and tex_orbital_hub:
			var orb_r = PlanetWorld.R_SURFACE + 460.0
			var orb_p = Vector2(cos(pose["ang"]), sin(pose["ang"])) * orb_r
			draw_line(pose["pos"], orb_p, Color(0.3, 0.88, 1.0, 0.72), 3.0)
			draw_set_transform(orb_p, pose["rot"])
			draw_texture_rect(tex_orbital_hub, Rect2(-120, -60, 240, 120), false)
			draw_set_transform(Vector2.ZERO, 0.0)

	# 2. Moving belt items
	for it in belt_items:
		var pose = _slot_world_pose(it["sec"], it["layer"], 1)
		var n_dir = Vector2(cos(pose["ang"]), sin(pose["ang"]))
		var pos = pose["pos"] + n_dir * (10.0 if it["layer"] >= PlanetWorld.LAYERS else float(it["t"]) * 36.0)
		var icon: Texture2D = item_icons.get(it["item"], null)
		if icon:
			draw_texture_rect(icon, Rect2(pos - Vector2(7, 7), Vector2(14, 14)), false)

	# 3. Spherical Blueprint Ghosts
	var sel = GameState.selected_tool
	if sel in GameState.BUILDINGS:
		var info = GameState.BUILDINGS[sel]
		var can_pay = GameState.can_afford(info["cost"]) and GameState.drones >= int(info.get("req_drones", 0))
		var pulse = 0.35 + 0.18 * sin(anim_time * 5.0)
		var tex: Texture2D = sprite_textures.get(sel, null)
		var frames = int(info.get("frames", 1))

		for i in range(blueprint_slots.size()):
			var sl = blueprint_slots[i]
			var is_focus = (i == active_ghost_idx)
			var col = Color(0.22, 0.94, 1.0, pulse + (0.2 if is_focus else 0.0)) if can_pay else Color(1.0, 0.38, 0.25, pulse + 0.1)
			var bcol = Color(0.95, 1.0, 1.0, 0.95) if is_focus else Color(col.r, col.g, col.b, 0.85)
			var w_px = maxf(36.0, sl["w_px"] * 1.02)
			var h_sc = sl["h_px"] * 1.45
			var rect = Rect2(-w_px * 0.5, -h_sc, w_px, h_sc)
			draw_set_transform(sl["pos"], sl["rot"])
			draw_rect(rect, Color(col.r, col.g, col.b, 0.22))
			if tex:
				if frames > 1:
					draw_texture_rect_region(tex, rect, Rect2(0, 0, float(tex.get_width()) / float(frames), float(tex.get_height())), col)
				else:
					draw_texture_rect(tex, rect, false, col)
			draw_rect(rect, bcol, false, 2.2 if is_focus else 1.3)
			draw_set_transform(Vector2.ZERO, 0.0)
			if is_focus and font:
				var msg = "[A] PLACE" if can_pay else GameState.get_missing_text(info["cost"])
				if GameState.drones < int(info.get("req_drones", 0)):
					msg = "NEED %d DRONES" % int(info.get("req_drones", 0))
				var lp = sl["pos"] + Vector2(cos(sl["rot"] - PI * 0.5), sin(sl["rot"] - PI * 0.5)) * (h_sc + 14.0)
				draw_string(font, lp + Vector2(-34, 0), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.45, 1.0, 1.0) if can_pay else Color(1.0, 0.32, 0.32))

	# 4. Mass Driver Launched Projectiles
	for pr in projectiles:
		var pts: Array = pr["trail"]
		for ti in range(1, pts.size()):
			draw_line(pts[ti - 1], pts[ti], Color(0.35, 0.95, 1.0, float(ti) / float(pts.size())), 2.5)
		draw_circle(pr["pos"], 5.0, Color(0.9, 1.0, 1.0))

	# 5. Turret Laser Bolts
	for lb in laser_beams:
		draw_line(lb["from"], lb["to"], Color(0.3, 1.0, 0.85, 0.95), 2.2)

func to_dict() -> Dictionary:
	var arr: Array = []
	for b in buildings:
		arr.append({"id": b["id"], "sec": b["sec"], "layer": b["layer"], "dir": b["dir"]})
	return {"buildings": arr}

func from_dict(d: Dictionary) -> void:
	clear_factory()
	for item in d.get("buildings", []):
		var bid = String(item.get("id", ""))
		if not GameState.BUILDINGS.has(bid): continue
		var info = GameState.BUILDINGS[bid]
		var ws = world.wrap_sector(int(item.get("sec", 0)))
		var layer = int(item.get("layer", PlanetWorld.LAYERS))
		var sec_w = int(info.get("sec_w", 1))
		var idx = buildings.size()
		buildings.append({
			"id": bid, "sec": ws, "layer": layer, "sec_w": sec_w, "dir": int(item.get("dir", 1)),
			"timer": 0.0, "smoke_t": 0.0, "charge_t": 0.0, "frame": 0,
			"ore_target": world.get_ore(ws, layer) if bid == "drill" else "",
		})
		for ds in range(sec_w):
			occupied[_key(ws + ds, layer)] = idx
	_recompute_power_grid()
	refresh_blueprint_slots()
	queue_redraw()
