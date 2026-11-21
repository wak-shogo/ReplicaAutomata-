extends Node2D

# Hard Local Wired Power Grid + Battery Storage, Physical Connected Logistics
# (Drill -> Belt/Lift -> Cargo Depot 4-way Filter -> Smelter -> Assembler -> Macro Printer -> Mass Driver),
# and HD-2D Pixel-Art Rendering along the curved spherical planet.

signal depot_opened(uid: int)

const POWER_NODES: Array[String] = ["solar", "geothermal", "tesla", "battery"]
const WIRE_RANGE: float = 920.0
const TESLA_DOME_R: float = 580.0
const BATTERY_CAP_KJ: float = 18000.0
const DRILL_BUF_CAP: int = 6
const MACHINE_IN_CAP: int = 12
const MACHINE_OUT_CAP: int = 8
const DEPOT_CAP: int = 240
const ASSEMBLER_RECIPES: Array[String] = ["circuit", "alloy", "sci_pack"]

var world: Node2D = null
var player: Node2D = null
var swarm: Node2D = null

var buildings: Array[Dictionary] = []
var occupied: Dictionary = {} # "sec:layer" -> building index
var wires: Array[Array] = []  # [uid1, uid2]
var belt_items: Array[Dictionary] = []
var launch_trails: Array[Dictionary] = []
var turret_beams: Array[Dictionary] = []

var blueprint_slots: Array[Dictionary] = []
var active_slot_idx: int = -1
var wire_pick_uid: int = -1
var selected_depot_uid: int = -1
var next_uid: int = 1
var anim_t: float = 0.0

func _ready() -> void:
	z_index = 10

func clear_all() -> void:
	buildings.clear()
	occupied.clear()
	wires.clear()
	belt_items.clear()
	launch_trails.clear()
	turret_beams.clear()
	blueprint_slots.clear()
	wire_pick_uid = -1
	selected_depot_uid = -1
	next_uid = 1

func _k(s: int, l: int) -> String:
	return "%d:%d" % [PlanetWorld.wrap_sector(s), l]

func is_occupied(s: int, l: int) -> bool:
	return occupied.has(_k(s, l))

func _by_uid(uid: int) -> Dictionary:
	for b in buildings:
		if int(b["uid"]) == uid:
			return b
	return {}

func _at(s: int, l: int) -> Dictionary:
	var key := _k(s, l)
	if not occupied.has(key):
		return {}
	var idx := int(occupied[key])
	if idx < 0 or idx >= buildings.size():
		return {}
	return buildings[idx]

func _buf_total(d: Dictionary) -> int:
	var t := 0
	for v in d.values():
		t += int(v)
	return t

func _buf_add(d: Dictionary, item: String, qty: int) -> void:
	d[item] = int(d.get(item, 0)) + qty

func _buf_take(d: Dictionary, want: String = "auto") -> String:
	if d.is_empty():
		return ""
	if want == "auto":
		var k := String(d.keys()[0])
		var v := int(d[k]) - 1
		if v <= 0: d.erase(k)
		else: d[k] = v
		return k
	if int(d.get(want, 0)) > 0:
		var v := int(d[want]) - 1
		if v <= 0: d.erase(want)
		else: d[want] = v
		return want
	return ""

# ------------------------------------------------------------------------------
# BLUEPRINT SLOTS & BUILDING PLACEMENT
# ------------------------------------------------------------------------------
func refresh_blueprints() -> void:
	blueprint_slots.clear()
	active_slot_idx = -1
	if not world or not player:
		return
	var tool := GameState.selected_tool
	if not GameState.BUILDINGS.has(tool):
		return
	var info: Dictionary = GameState.BUILDINGS[tool]
	var sw := int(info.get("sec_w", 1))
	var pc: Vector2i = world.world_to_cell(player.position)
	var underground := player.position.length() < PlanetWorld.R_SURFACE - 140.0

	var best_d := 1e9
	for ds in range(-4, 5):
		var ws := PlanetWorld.wrap_sector(pc.x + ds)
		var l: int = pc.y if (underground and (tool == "lift" or tool == "belt" or tool == "drill")) else (int(world.get_surface_layer(ws)) + 1)
		if l < 1 or l > PlanetWorld.LAYERS:
			continue
		var free := true
		for w_i in range(sw):
			if occupied.has(_k(ws + w_i, l)):
				free = false
				break
		if not free:
			continue
		var pose: Dictionary = world.get_surface_pose(ws, l, 0.0)
		var slot := {"sec": ws, "layer": l, "pos": pose["pos"], "rot": pose["rot"], "normal": pose["normal"]}
		var d := Vector2(pose["pos"]).distance_to(player.position)
		if d < best_d:
			best_d = d
			active_slot_idx = blueprint_slots.size()
		blueprint_slots.append(slot)

func try_place_active_blueprint() -> bool:
	refresh_blueprints()
	if active_slot_idx < 0 or active_slot_idx >= blueprint_slots.size():
		AudioSynth.play_sfx("error")
		GameState.add_log("No open build slot nearby.", "warn")
		return false
	var sl := blueprint_slots[active_slot_idx]
	return try_place_building(GameState.selected_tool, int(sl["sec"]), int(sl["layer"]))

func try_place_building(bid: String, sec: int, layer: int) -> bool:
	if not world or not GameState.BUILDINGS.has(bid):
		return false
	if not GameState.is_building_unlocked(bid):
		AudioSynth.play_sfx("error")
		GameState.add_log("Research required for %s." % GameState.BUILDINGS[bid]["name"], "warn")
		return false
	var info: Dictionary = GameState.BUILDINGS[bid]
	var sw := int(info.get("sec_w", 1))
	var ws := PlanetWorld.wrap_sector(sec)
	for w_i in range(sw):
		if occupied.has(_k(ws + w_i, layer)):
			AudioSynth.play_sfx("error")
			return false
	if not GameState.spend(info["cost"]):
		AudioSynth.play_sfx("error")
		GameState.add_log("Insufficient resources for %s." % info["name"], "warn")
		return false

	var pose: Dictionary = world.get_surface_pose(ws, layer, 0.0)
	var ore_t := _find_drill_ore(ws, layer) if bid == "drill" else ""
	var b := {
		"uid": next_uid,
		"id": bid,
		"sec": ws,
		"layer": layer,
		"sec_w": sw,
		"pos": pose["pos"],
		"normal": pose["normal"],
		"rot": pose["rot"],
		"dir": GameState.build_dir,
		"pwr_ratio": 0.0,
		"wired": false,
		"timer": 0.0,
		"push_t": 0.0,
		"smoke_t": 0.0,
		"blocked": false,
		"ore_target": ore_t,
		"recipe": "circuit",
		"in_buf": {},
		"out_buf": {},
		"inv": {},
		"out_filters": {"left": "none", "right": "none", "up": "none", "down": "none"},
		"battery_kj": (BATTERY_CAP_KJ * 0.25) if bid == "battery" else 0.0,
	}
	next_uid += 1
	var idx := buildings.size()
	buildings.append(b)
	for w_i in range(sw):
		occupied[_k(ws + w_i, layer)] = idx
	world.spawn_spark_burst(pose["pos"], Color(0.38, 0.92, 1.0), 10)
	_solve_power_grids(0.0)
	refresh_blueprints()
	AudioSynth.play_sfx("build")
	GameState.add_log("Built %s%s" % [
		info["name"],
		" (wire Solar/Battery <-> Tesla)" if (bid in POWER_NODES) else ""
	], "good")
	return true

func _find_drill_ore(sec: int, layer: int) -> String:
	for dl in range(0, 4):
		var l := layer - 1 - dl
		if l >= 1 and l < PlanetWorld.LAYERS:
			var o: String = world.get_ore(sec, l)
			if o != "": return o
	for ds in [-1, 1]:
		for dl in range(0, 3):
			var l := layer - 1 - dl
			if l >= 1 and l < PlanetWorld.LAYERS:
				var o: String = world.get_ore(sec + ds, l)
				if o != "": return o
	return "fe"

func try_demolish_near(pos: Vector2) -> bool:
	var best_i := -1
	var best_d := 110.0
	for i in range(buildings.size()):
		var d := Vector2(buildings[i]["pos"]).distance_to(pos)
		if d < best_d:
			best_d = d
			best_i = i
	if best_i < 0:
		return false
	var b := buildings[best_i]
	var dead_uid := int(b["uid"])
	var info: Dictionary = GameState.BUILDINGS[b["id"]]
	for r_id in info["cost"].keys():
		GameState.add_res(String(r_id), maxi(1, int(info["cost"][r_id]) / 2))
	for wi in range(wires.size() - 1, -1, -1):
		if int(wires[wi][0]) == dead_uid or int(wires[wi][1]) == dead_uid:
			wires.remove_at(wi)
	if wire_pick_uid == dead_uid: wire_pick_uid = -1
	if selected_depot_uid == dead_uid: selected_depot_uid = -1
	buildings.remove_at(best_i)
	occupied.clear()
	for i in range(buildings.size()):
		for w_i in range(int(buildings[i]["sec_w"])):
			occupied[_k(int(buildings[i]["sec"]) + w_i, int(buildings[i]["layer"]))] = i
	_solve_power_grids(0.0)
	AudioSynth.play_sfx("pop")
	GameState.add_log("Salvaged %s." % info["name"], "info")
	return true

# ------------------------------------------------------------------------------
# POWER WIRING & INTERACTIONS
# ------------------------------------------------------------------------------
func find_nearest_building(pos: Vector2, max_d: float = 130.0, filter_ids: Array = []) -> Dictionary:
	var best: Dictionary = {}
	var bd := max_d
	for b in buildings:
		if not filter_ids.is_empty() and not (b["id"] in filter_ids):
			continue
		var d := Vector2(b["pos"]).distance_to(pos)
		if d < bd:
			bd = d
			best = b
	return best

func _are_wired(u1: int, u2: int) -> bool:
	for w in wires:
		if (int(w[0]) == u1 and int(w[1]) == u2) or (int(w[0]) == u2 and int(w[1]) == u1):
			return true
	return false

func toggle_wire(u1: int, u2: int) -> bool:
	if u1 <= 0 or u2 <= 0 or u1 == u2:
		return false
	var b1 := _by_uid(u1)
	var b2 := _by_uid(u2)
	if b1.is_empty() or b2.is_empty():
		return false
	if not (b1["id"] in POWER_NODES) or not (b2["id"] in POWER_NODES):
		return false
	for i in range(wires.size()):
		var w := wires[i]
		if (int(w[0]) == u1 and int(w[1]) == u2) or (int(w[0]) == u2 and int(w[1]) == u1):
			wires.remove_at(i)
			_solve_power_grids(0.0)
			AudioSynth.play_sfx("pop")
			GameState.add_log("Power cable disconnected.", "info")
			return true
	var d := Vector2(b1["pos"]).distance_to(Vector2(b2["pos"]))
	if d > WIRE_RANGE:
		AudioSynth.play_sfx("error")
		GameState.add_log("Power cable out of range (%dpx > %dpx)." % [int(d), int(WIRE_RANGE)], "warn")
		return false
	wires.append([u1, u2])
	if world:
		world.spawn_spark_burst((Vector2(b1["pos"]) + Vector2(b2["pos"])) * 0.5, Color(0.32, 0.94, 1.0), 10)
	_solve_power_grids(0.0)
	AudioSynth.play_sfx("wire")
	GameState.add_log("WIRED: %s <-> %s" % [GameState.BUILDINGS[b1["id"]]["name"], GameState.BUILDINGS[b2["id"]]["name"]], "good")
	return true

func try_wire_near(pos: Vector2) -> bool:
	var near := find_nearest_building(pos, 190.0, POWER_NODES)
	if near.is_empty():
		GameState.add_log("Move near a Solar, Battery, Geo, or Tesla node to wire.", "warn")
		return false
	var u1 := int(near["uid"])
	if wire_pick_uid == -1:
		wire_pick_uid = u1
		AudioSynth.play_sfx("click")
		GameState.add_log("WIRE START: %s. Tap target or press [A] again to auto-link." % GameState.BUILDINGS[near["id"]]["name"], "info")
		return true
	elif wire_pick_uid == u1:
		# Auto-link to nearest unwired complementary power node within WIRE_RANGE!
		var best_u := -1
		var best_s := 1e9
		var is_gen: bool = String(near["id"]) in ["solar", "geothermal"]
		for b in buildings:
			var bu := int(b["uid"])
			if bu == u1 or not (b["id"] in POWER_NODES) or _are_wired(u1, bu):
				continue
			var d := Vector2(near["pos"]).distance_to(Vector2(b["pos"]))
			if d <= WIRE_RANGE:
				var b_gen: bool = String(b["id"]) in ["solar", "geothermal"]
				var sc := d - (1200.0 if (is_gen != b_gen) else 0.0)
				if sc < best_s:
					best_s = sc
					best_u = bu
		wire_pick_uid = -1
		if best_u > 0:
			return toggle_wire(u1, best_u)
		GameState.add_log("Wire pick cleared.", "info")
		return true
	else:
		var u0 := wire_pick_uid
		wire_pick_uid = -1
		return toggle_wire(u0, u1)

func try_world_tap(world_pos: Vector2) -> bool:
	var tool := GameState.selected_tool
	if tool == "wire":
		var pn := find_nearest_building(world_pos, 130.0, POWER_NODES)
		if not pn.is_empty():
			var uid := int(pn["uid"])
			if wire_pick_uid == -1:
				wire_pick_uid = uid
				AudioSynth.play_sfx("click")
				GameState.add_log("WIRE PICK: %s -> Tap target node" % GameState.BUILDINGS[pn["id"]]["name"], "info")
			elif wire_pick_uid == uid:
				wire_pick_uid = -1
			else:
				var u0 := wire_pick_uid
				wire_pick_uid = -1
				toggle_wire(u0, uid)
			return true
		wire_pick_uid = -1
		return true
	if tool == "demolish":
		return try_demolish_near(world_pos)
	if GameState.BUILDINGS.has(tool):
		refresh_blueprints()
		var best_i := -1
		var best_d := 125.0
		for i in range(blueprint_slots.size()):
			var d := Vector2(blueprint_slots[i]["pos"]).distance_to(world_pos)
			if d < best_d:
				best_d = d
				best_i = i
		if best_i >= 0:
			var sl := blueprint_slots[best_i]
			return try_place_building(tool, int(sl["sec"]), int(sl["layer"]))

	# Tap existing building directly
	var b := find_nearest_building(world_pos, 115.0)
	if b.is_empty():
		wire_pick_uid = -1
		return false
	var bid := String(b["id"])
	if bid in POWER_NODES:
		var uid := int(b["uid"])
		if wire_pick_uid == -1:
			wire_pick_uid = uid
			AudioSynth.play_sfx("click")
			GameState.add_log("WIRE PICK: %s -> Tap Tesla/Solar/Battery" % GameState.BUILDINGS[bid]["name"], "info")
		elif wire_pick_uid == uid:
			wire_pick_uid = -1
		else:
			var u0 := wire_pick_uid
			wire_pick_uid = -1
			if not _are_wired(u0, uid):
				toggle_wire(u0, uid)
		return true
	elif bid == "depot":
		selected_depot_uid = int(b["uid"])
		AudioSynth.play_sfx("select")
		depot_opened.emit(selected_depot_uid)
		return true
	elif bid == "belt" or bid == "lift":
		b["dir"] = -int(b["dir"])
		AudioSynth.play_sfx("click")
		GameState.add_log("%s direction flipped." % GameState.BUILDINGS[bid]["name"], "info")
		return true
	elif bid == "assembler":
		var cur := String(b["recipe"])
		var ri := (ASSEMBLER_RECIPES.find(cur) + 1) % ASSEMBLER_RECIPES.size()
		b["recipe"] = ASSEMBLER_RECIPES[ri]
		_collect_out(b)
		AudioSynth.play_sfx("select")
		GameState.add_log("Assembler recipe -> %s" % String(b["recipe"]).to_upper(), "info")
		return true
	elif bid in ["drill", "smelter", "printer"]:
		if _collect_out(b) == 0:
			_hand_feed(b)
		return true
	return false

func try_interact_near(pos: Vector2) -> bool:
	if GameState.selected_tool == "wire":
		return try_wire_near(pos)
	var b := find_nearest_building(pos, 180.0)
	if not b.is_empty() and (b["id"] in POWER_NODES or b["id"] == "belt"):
		var func_b := find_nearest_building(pos, 180.0, ["depot", "smelter", "assembler", "printer", "drill"])
		if not func_b.is_empty():
			b = func_b
	if b.is_empty():
		return false
	var bid := String(b["id"])
	if bid == "depot":
		selected_depot_uid = int(b["uid"])
		AudioSynth.play_sfx("select")
		depot_opened.emit(selected_depot_uid)
		return true
	if bid in POWER_NODES:
		if not bool(b["wired"]):
			return try_wire_near(pos)
		return false
	if bid in ["drill", "smelter", "assembler", "printer"]:
		var got := _collect_out(b)
		var fed := _hand_feed(b) if bid != "drill" else false
		return got > 0 or fed
	return false

func _collect_out(b: Dictionary) -> int:
	var out: Dictionary = b["out_buf"]
	var got := 0
	for k in out.keys().duplicate():
		var cnt := int(out[k])
		if cnt > 0:
			GameState.add_res(String(k), cnt)
			out.erase(k)
			got += cnt
			if world:
				world.spawn_popup(Vector2(b["pos"]), "+%d %s" % [cnt, String(k).to_upper()], Color(0.42, 0.94, 1.0))
	if got > 0:
		AudioSynth.play_sfx("pop")
	return got

func _hand_feed(b: Dictionary) -> bool:
	var bid := String(b["id"])
	var fed := false
	if bid == "smelter":
		var o2p := {"fe": "plate_fe", "cu": "wire_cu", "si": "wafer_si"}
		var ores: Array[String] = ["fe", "cu", "si"]
		ores.sort_custom(func(a: String, c: String) -> bool:
			var qa := float(GameState.get_res(o2p[a])) + float(b["in_buf"].get(a, 0)) * 0.5
			var qc := float(GameState.get_res(o2p[c])) + float(b["in_buf"].get(c, 0)) * 0.5
			return qa < qc
		)
		for ore in ores:
			if GameState.get_res(ore) >= 2 and _buf_total(b["in_buf"]) < MACHINE_IN_CAP:
				var give := mini(4, mini(GameState.get_res(ore), MACHINE_IN_CAP - _buf_total(b["in_buf"])))
				GameState.add_res(ore, -give)
				_buf_add(b["in_buf"], ore, give)
				fed = true
				break
	elif bid == "assembler":
		var rec := String(b["recipe"])
		var wants: Array[String] = ["plate_fe", "wire_cu"] if rec == "circuit" else (["plate_fe", "ti"] if rec == "alloy" else ["plate_fe", "circuit"])
		for w in wants:
			if GameState.get_res(w) >= 1 and _buf_total(b["in_buf"]) < MACHINE_IN_CAP:
				var give := mini(2, mini(GameState.get_res(w), MACHINE_IN_CAP - _buf_total(b["in_buf"])))
				GameState.add_res(w, -give)
				_buf_add(b["in_buf"], w, give)
				fed = true
	elif bid == "printer":
		for w in ["plate_fe", "circuit"]:
			if GameState.get_res(w) >= 1 and _buf_total(b["in_buf"]) < MACHINE_IN_CAP:
				var give := mini(2, mini(GameState.get_res(w), MACHINE_IN_CAP - _buf_total(b["in_buf"])))
				GameState.add_res(w, -give)
				_buf_add(b["in_buf"], w, give)
				fed = true
	if fed:
		AudioSynth.play_sfx("pop")
	return fed

# ------------------------------------------------------------------------------
# DEPOT ROUTING INTERFACE (4-WAY OUTPUT FILTERS)
# ------------------------------------------------------------------------------
func get_depot_snapshot(uid: int) -> Dictionary:
	var d := _by_uid(uid)
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
	var d := _by_uid(uid)
	if d.is_empty():
		return false
	var inv: Dictionary = d["inv"]
	if to_depot:
		var have := GameState.get_res(item)
		var room := maxi(0, DEPOT_CAP - _buf_total(inv))
		var mv := mini(qty, mini(have, room))
		if mv <= 0: return false
		GameState.add_res(item, -mv)
		_buf_add(inv, item, mv)
	else:
		var have_d := int(inv.get(item, 0))
		var mv := mini(qty, have_d)
		if mv <= 0: return false
		if have_d == mv: inv.erase(item)
		else: inv[item] = have_d - mv
		GameState.add_res(item, mv)
	AudioSynth.play_sfx("pop")
	return true

func depot_deposit_all(uid: int) -> int:
	var moved := 0
	for r in ["fe", "cu", "si", "ti", "ice"]:
		var amt := GameState.get_res(r)
		if amt > 0 and depot_transfer(uid, r, true, amt):
			moved += amt
	return moved

func depot_cycle_filter(uid: int, dir_key: String) -> String:
	var d := _by_uid(uid)
	if d.is_empty():
		return "none"
	var cycle: Array[String] = ["none", "auto", "fe", "cu", "si", "ti", "plate_fe", "wire_cu", "wafer_si", "circuit", "alloy", "sci_pack", "probe_stock"]
	var cur := String(d["out_filters"].get(dir_key, "none"))
	var nxt := cycle[(cycle.find(cur) + 1) % cycle.size()]
	d["out_filters"][dir_key] = nxt
	AudioSynth.play_sfx("click")
	return nxt

# ------------------------------------------------------------------------------
# HARD LOCAL WIRED POWER GRID SOLVER (ZERO FREE GLOBAL POWER!)
# ------------------------------------------------------------------------------
func _solve_power_grids(delta: float) -> void:
	for b in buildings:
		b["pwr_ratio"] = 0.0
		b["wired"] = false

	# Adjacency graph of power nodes connected by physical wires
	var adj: Dictionary = {}
	for b in buildings:
		if b["id"] in POWER_NODES:
			adj[int(b["uid"])] = []
	for w in wires:
		var u1 := int(w[0]); var u2 := int(w[1])
		if adj.has(u1) and adj.has(u2):
			adj[u1].append(u2)
			adj[u2].append(u1)
			var b1 := _by_uid(u1); var b2 := _by_uid(u2)
			if not b1.is_empty(): b1["wired"] = true
			if not b2.is_empty(): b2["wired"] = true

	var visited: Dictionary = {}
	var tot_prod := 0.0
	var tot_use := 0.0
	var tot_stored := 0.0
	var tot_cap := 0.0
	var teslas_on := 0

	# Dyson Ring megastructure beams 240W to any wired Tesla grid
	var dyson_bonus := 240.0 if bool(GameState.megastructures.get("dyson", false)) else 0.0

	for uid in adj.keys():
		if visited.has(uid):
			continue
		var comp_uids: Array[int] = []
		var queue: Array[int] = [uid]
		visited[uid] = true
		while not queue.is_empty():
			var cur: int = int(queue.pop_front())
			comp_uids.append(cur)
			for nb in adj[cur]:
				if not visited.has(nb):
					visited[nb] = true
					queue.append(nb)

		var gen := 0.0
		var teslas: Array[Dictionary] = []
		var bats: Array[Dictionary] = []
		for cu in comp_uids:
			var nb := _by_uid(cu)
			if nb.is_empty(): continue
			var bid := String(nb["id"])
			if bid == "solar":
				var sun: float = world.get_sunlight_at(nb["pos"]) if world else 1.0
				gen += float(GameState.BUILDINGS["solar"]["pwr_gen"]) * sun
			elif bid == "geothermal":
				gen += float(GameState.BUILDINGS["geothermal"]["pwr_gen"])
			elif bid == "tesla":
				teslas.append(nb)
			elif bid == "battery":
				bats.append(nb)

		if not teslas.is_empty():
			gen += dyson_bonus

		# Collect unique powered consumers inside any Tesla dome in this wired component
		var consumers: Array[Dictionary] = []
		var seen_c: Dictionary = {}
		var demand := 0.0
		for ts in teslas:
			var tpos: Vector2 = ts["pos"]
			for b in buildings:
				var bu := int(b["uid"])
				if seen_c.has(bu) or (b["id"] in POWER_NODES):
					continue
				if Vector2(b["pos"]).distance_to(tpos) <= TESLA_DOME_R:
					seen_c[bu] = true
					consumers.append(b)
					demand += float(GameState.BUILDINGS[b["id"]]["pwr_use"])

		# Battery charge / discharge across daytime and planetary dusk/night
		var stored := 0.0
		var cap := float(bats.size()) * BATTERY_CAP_KJ
		for bt in bats:
			stored += float(bt["battery_kj"])

		var supply := gen
		if delta > 0.0 and not bats.is_empty():
			if gen >= demand:
				var surplus := (gen - demand) * delta
				for bt in bats:
					var room := BATTERY_CAP_KJ - float(bt["battery_kj"])
					var add_e := minf(room, surplus / float(bats.size()))
					bt["battery_kj"] = float(bt["battery_kj"]) + add_e
			else:
				var deficit := (demand - gen) * delta
				var drawn := 0.0
				for bt in bats:
					var take := minf(float(bt["battery_kj"]), deficit / float(bats.size()))
					bt["battery_kj"] = float(bt["battery_kj"]) - take
					drawn += take
				supply = gen + (drawn / maxf(0.0001, delta))
			stored = 0.0
			for bt in bats:
				stored += float(bt["battery_kj"])

		var ratio := 0.0
		if not teslas.is_empty():
			if demand <= 0.01:
				ratio = 1.0 if (supply > 0.5 or stored > 1.0) else 0.0
			else:
				ratio = clampf(supply / demand, 0.0, 1.0)

		for cu in comp_uids:
			var nb := _by_uid(cu)
			if not nb.is_empty():
				nb["pwr_ratio"] = ratio if (not teslas.is_empty() or not bats.is_empty()) else 0.0
		if ratio > 0.15:
			teslas_on += teslas.size()
		for c in consumers:
			c["pwr_ratio"] = maxf(float(c["pwr_ratio"]), ratio)

		# Only count generation connected to a Tesla or Battery grid (unwired Solars report 0W!)
		if not teslas.is_empty() or not bats.is_empty():
			tot_prod += gen
		tot_use += demand
		tot_stored += stored
		tot_cap += cap

	GameState.power_prod = tot_prod
	GameState.power_use = tot_use
	GameState.power_stored = tot_stored
	GameState.power_cap = tot_cap
	GameState.wire_count = wires.size()
	GameState.active_teslas = teslas_on

# ------------------------------------------------------------------------------
# PHYSICAL ITEM-FLOW & PRODUCTION TICK
# ------------------------------------------------------------------------------
func _spawn_on_belt(sec: int, layer: int, item: String, dir: int) -> bool:
	var ws := PlanetWorld.wrap_sector(sec)
	var cnt := 0
	for it in belt_items:
		if int(it["sec"]) == ws and int(it["layer"]) == layer and float(it["t"]) < 0.4:
			cnt += 1
	if cnt >= 2:
		return false
	var b := _at(ws, layer)
	if b.is_empty() or (b["id"] != "belt" and b["id"] != "lift"):
		return false
	belt_items.append({"sec": ws, "layer": layer, "item": item, "t": 0.06, "dir": dir, "is_lift": b["id"] == "lift"})
	return true

func _deliver_to(target: Dictionary, item: String) -> bool:
	var bid := String(target["id"])
	if bid == "depot":
		if _buf_total(target["inv"]) >= DEPOT_CAP: return false
		_buf_add(target["inv"], item, 1)
		return true
	elif bid == "smelter":
		if not (item in ["fe", "cu", "si"]) or _buf_total(target["in_buf"]) >= MACHINE_IN_CAP: return false
		_buf_add(target["in_buf"], item, 1)
		return true
	elif bid == "assembler":
		if not (item in ["plate_fe", "wire_cu", "wafer_si", "ti", "circuit"]) or _buf_total(target["in_buf"]) >= MACHINE_IN_CAP: return false
		_buf_add(target["in_buf"], item, 1)
		return true
	elif bid == "printer":
		if not (item in ["plate_fe", "circuit"]) or _buf_total(target["in_buf"]) >= MACHINE_IN_CAP: return false
		_buf_add(target["in_buf"], item, 1)
		return true
	elif bid == "mass_driver":
		if item == "probe_stock":
			_buf_add(target["in_buf"], item, 1)
			return true
	return false

func _push_adjacent(b: Dictionary, buf: Dictionary) -> void:
	if buf.is_empty(): return
	var ws := int(b["sec"]); var sw := int(b["sec_w"]); var l := int(b["layer"])
	var ports := [
		[ws + sw, l, 1],
		[ws - 1, l, -1],
		[ws, l + 1, 1],
		[ws, l - 1, -1],
	]
	for p in ports:
		var tb := _at(int(p[0]), int(p[1]))
		if tb.is_empty(): continue
		var it := _buf_take(buf, "auto")
		if it == "": return
		var ok := _spawn_on_belt(int(tb["sec"]), int(tb["layer"]), it, int(p[2])) if (tb["id"] == "belt" or tb["id"] == "lift") else _deliver_to(tb, it)
		if ok: return
		_buf_add(buf, it, 1)

func _push_depot(b: Dictionary) -> void:
	var inv: Dictionary = b["inv"]
	if inv.is_empty(): return
	var filters: Dictionary = b["out_filters"]
	var ws := int(b["sec"]); var sw := int(b["sec_w"]); var l := int(b["layer"])
	var ports := [
		{"k": "right", "s": ws + sw, "l": l, "d": 1},
		{"k": "left",  "s": ws - 1,  "l": l, "d": -1},
		{"k": "up",    "s": ws,      "l": l + 1, "d": 1},
		{"k": "down",  "s": ws,      "l": l - 1, "d": -1},
	]
	for p in ports:
		var flt := String(filters.get(p["k"], "none"))
		if flt == "none": continue
		var tb := _at(int(p["s"]), int(p["l"]))
		if tb.is_empty(): continue
		var it := _buf_take(inv, flt)
		if it == "": continue
		var ok := _spawn_on_belt(int(tb["sec"]), int(tb["layer"]), it, int(p["d"])) if (tb["id"] == "belt" or tb["id"] == "lift") else _deliver_to(tb, it)
		if not ok:
			_buf_add(inv, it, 1)

func _belt_item_pos(it: Dictionary) -> Vector2:
	if not world: return Vector2.ZERO
	if bool(it["is_lift"]):
		var a := PlanetWorld.sector_center_angle(int(it["sec"]))
		var r0 := PlanetWorld.layer_inner_r(int(it["layer"]))
		var frac := float(it["t"]) if int(it["dir"]) >= 0 else (1.0 - float(it["t"]))
		return world.polar_to_world(a, r0 + frac * PlanetWorld.LAYER_THICK)
	var frac := float(it["t"]) if int(it["dir"]) >= 0 else (1.0 - float(it["t"]))
	var ang := (float(it["sec"]) + frac) * PlanetWorld.DA
	var r := PlanetWorld.layer_inner_r(int(it["layer"])) + 12.0
	return world.polar_to_world(ang, r)

func collect_nearby_items(pos: Vector2, rad: float = 95.0) -> int:
	var got := 0
	for i in range(belt_items.size() - 1, -1, -1):
		if _belt_item_pos(belt_items[i]).distance_to(pos) <= rad:
			GameState.add_res(String(belt_items[i]["item"]), 1)
			belt_items.remove_at(i)
			got += 1
	for b in buildings:
		if b["id"] in ["drill", "smelter", "assembler", "printer"] and not b["out_buf"].is_empty():
			if Vector2(b["pos"]).distance_to(pos) <= 72.0:
				got += _collect_out(b)
	if got > 0:
		AudioSynth.play_sfx("pop")
	return got

func service_player(pos: Vector2, delta: float) -> void:
	var near_pad := false
	for b in buildings:
		if (b["id"] in POWER_NODES or b["id"] == "depot") and float(b["pwr_ratio"]) > 0.15:
			if Vector2(b["pos"]).distance_to(pos) <= 280.0:
				near_pad = true
				break
	if near_pad:
		GameState.ion_battery = minf(GameState.max_ion_battery, GameState.ion_battery + 35.0 * delta)
		GameState.fuel = minf(GameState.max_fuel, GameState.fuel + 24.0 * delta)
		GameState.hp = minf(GameState.max_hp, GameState.hp + 10.0 * delta)
	else:
		# Passive capsule micro-solar recharge so player can NEVER softlock on Ion backup!
		var sun: float = world.get_sunlight_at(pos) if world else 0.5
		GameState.ion_battery = minf(GameState.max_ion_battery, GameState.ion_battery + (4.5 + 8.5 * sun) * delta)

func _process(delta: float) -> void:
	anim_t += delta
	_solve_power_grids(delta)
	var spd := 1.0 + float(GameState.drones) * 0.16

	for b in buildings:
		var bid := String(b["id"])
		var pwr := float(b["pwr_ratio"])
		b["blocked"] = false
		if pwr > 0.05:
			b["timer"] = float(b["timer"]) + delta * spd * pwr
			b["smoke_t"] = float(b["smoke_t"]) + delta * pwr
		b["push_t"] = float(b["push_t"]) + delta
		if float(b["push_t"]) >= 0.42:
			b["push_t"] = 0.0
			if bid == "depot": _push_depot(b)
			elif bid in ["drill", "smelter", "assembler", "printer"]: _push_adjacent(b, b["out_buf"])

		match bid:
			"drill":
				if pwr <= 0.05: continue
				if _buf_total(b["out_buf"]) >= DRILL_BUF_CAP:
					b["blocked"] = true
					continue
				if float(b["timer"]) >= 1.25:
					b["timer"] = 0.0
					_buf_add(b["out_buf"], String(b["ore_target"]), 1)
					if world and float(b["smoke_t"]) >= 1.0:
						b["smoke_t"] = 0.0
						world.spawn_smoke(Vector2(b["pos"]) + Vector2(b["normal"]) * 36.0, b["normal"])
			"smelter":
				if pwr <= 0.05: continue
				if _buf_total(b["out_buf"]) >= MACHINE_OUT_CAP:
					b["blocked"] = true
					continue
				if world and float(b["smoke_t"]) >= 0.65 and not b["in_buf"].is_empty():
					b["smoke_t"] = 0.0
					world.spawn_smoke(Vector2(b["pos"]) + Vector2(b["normal"]) * 56.0, b["normal"], Color(0.72, 0.76, 0.84, 0.42))
				if float(b["timer"]) >= 1.9:
					b["timer"] = 0.0
					var ib: Dictionary = b["in_buf"]
					if int(ib.get("fe", 0)) >= 2:
						ib["fe"] -= 2; if ib["fe"] <= 0: ib.erase("fe")
						_buf_add(b["out_buf"], "plate_fe", 1)
					elif int(ib.get("cu", 0)) >= 2:
						ib["cu"] -= 2; if ib["cu"] <= 0: ib.erase("cu")
						_buf_add(b["out_buf"], "wire_cu", 1)
					elif int(ib.get("si", 0)) >= 2:
						ib["si"] -= 2; if ib["si"] <= 0: ib.erase("si")
						_buf_add(b["out_buf"], "wafer_si", 1)
			"assembler":
				if pwr <= 0.05: continue
				if _buf_total(b["out_buf"]) >= MACHINE_OUT_CAP:
					b["blocked"] = true
					continue
				if float(b["timer"]) >= 2.2:
					b["timer"] = 0.0
					var ib: Dictionary = b["in_buf"]
					var rec := String(b["recipe"])
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
			"printer":
				if pwr <= 0.05: continue
				if _buf_total(b["out_buf"]) >= MACHINE_OUT_CAP:
					b["blocked"] = true
					continue
				if float(b["timer"]) >= 2.8:
					b["timer"] = 0.0
					var ib: Dictionary = b["in_buf"]
					if int(ib.get("plate_fe", 0)) >= 2 and int(ib.get("circuit", 0)) >= 1:
						ib["plate_fe"] -= 2; ib["circuit"] -= 1
						if ib["plate_fe"] <= 0: ib.erase("plate_fe")
						if ib["circuit"] <= 0: ib.erase("circuit")
						_buf_add(b["out_buf"], "probe_stock", 1)
					elif GameState.get_res("plate_fe") >= 2 and GameState.get_res("circuit") >= 1:
						GameState.add_res("plate_fe", -2)
						GameState.add_res("circuit", -1)
						_buf_add(b["out_buf"], "probe_stock", 1)
			"mass_driver":
				if pwr <= 0.05: continue
				if float(b["timer"]) >= 2.6:
					var has_probe := int(b["in_buf"].get("probe_stock", 0)) > 0
					var from_global := (not has_probe) and GameState.get_res("probe_stock") > 0
					if has_probe or from_global:
						b["timer"] = 0.0
						if has_probe:
							_buf_take(b["in_buf"], "probe_stock")
						else:
							GameState.add_res("probe_stock", -1)
						_fire_mass_driver(b)
			"turret":
				if pwr <= 0.05 or not swarm: continue
				if float(b["timer"]) >= 0.70 and swarm.has_method("find_nearest_raider"):
					var tgt: Vector2 = swarm.find_nearest_raider(b["pos"], 1200.0)
					if tgt != Vector2.ZERO:
						b["timer"] = 0.0
						swarm.damage_raider_near(tgt, 28.0)
						turret_beams.append({"a": Vector2(b["pos"]) + Vector2(b["normal"]) * 28.0, "b": tgt, "life": 0.14})
						AudioSynth.play_sfx("laser")

	# Move physical items along powered belts & lifts
	for i in range(belt_items.size() - 1, -1, -1):
		var it := belt_items[i]
		var cb := _at(int(it["sec"]), int(it["layer"]))
		if cb.is_empty() or (cb["id"] != "belt" and cb["id"] != "lift"):
			belt_items.remove_at(i)
			continue
		it["dir"] = int(cb["dir"])
		var bp := float(cb["pwr_ratio"])
		if bp <= 0.05: continue
		it["t"] = minf(1.02, float(it["t"]) + delta * 1.15 * bp)
		if float(it["t"]) >= 1.0:
			var ns := PlanetWorld.wrap_sector(int(it["sec"]) + int(it["dir"])) if not bool(it["is_lift"]) else int(it["sec"])
			var nl := int(it["layer"]) if not bool(it["is_lift"]) else (int(it["layer"]) + int(it["dir"]))
			var nb := _at(ns, nl)
			if not nb.is_empty():
				if nb["id"] == "belt" or nb["id"] == "lift":
					it["sec"] = ns; it["layer"] = nl; it["t"] = 0.05; it["is_lift"] = (nb["id"] == "lift")
				elif _deliver_to(nb, String(it["item"])):
					belt_items.remove_at(i)
				else:
					it["t"] = 0.96
			else:
				it["t"] = 0.96

	# Mass Driver ballistic launch trails
	for i in range(launch_trails.size() - 1, -1, -1):
		var tr := launch_trails[i]
		tr["pos"] += tr["vel"] * delta
		if world:
			tr["vel"] += world.compute_gravity_at(tr["pos"]) * delta * 0.25
		tr["life"] -= delta
		if float(tr["life"]) <= 0.0:
			launch_trails.remove_at(i)

	for i in range(turret_beams.size() - 1, -1, -1):
		turret_beams[i]["life"] -= delta
		if float(turret_beams[i]["life"]) <= 0.0:
			turret_beams.remove_at(i)

	if GameState.BUILDINGS.has(GameState.selected_tool):
		refresh_blueprints()
	queue_redraw()

func _fire_mass_driver(b: Dictionary) -> void:
	var p: Vector2 = b["pos"]
	var n: Vector2 = b["normal"]
	var tang := Vector2(-n.y, n.x)
	var launch_dir := (n * 0.72 + tang * 0.69).normalized()
	var muzzle := p + n * 58.0 + tang * 28.0
	launch_trails.append({"pos": muzzle, "vel": launch_dir * 980.0, "life": 2.4})
	if world:
		world.spawn_spark_burst(muzzle, Color(1.0, 0.86, 0.42), 14)
		world.spawn_smoke(muzzle, launch_dir, Color(0.95, 0.88, 0.72, 0.45))
	GameState.total_launches += 1
	var batch := 8 if GameState.swarm_fleet >= 24 else 4
	GameState.swarm_fleet = mini(GameState.SWARM_MAX, GameState.swarm_fleet + batch)
	if swarm and swarm.has_method("spawn_launched_units"):
		swarm.spawn_launched_units(muzzle, launch_dir, batch)
	AudioSynth.play_sfx("launch")

# ------------------------------------------------------------------------------
# HD-2D PIXEL-ART FACTORY RENDERING
# ------------------------------------------------------------------------------
func _draw() -> void:
	if not world: return
	var cam := get_viewport().get_camera_2d()
	var cpos := cam.global_position if cam else Vector2.ZERO
	var vp := get_viewport_rect().size
	var z := cam.zoom.x if cam else 1.0
	var max_d := maxf(vp.x, vp.y) * 0.75 / maxf(0.02, z) + 950.0
	var glow := ArtRegistry.get_tex("glow_soft")
	var font := ThemeDB.fallback_font

	# 1. Holographic Blueprint Slots
	if GameState.BUILDINGS.has(GameState.selected_tool):
		var tex := ArtRegistry.get_tex(String(GameState.BUILDINGS[GameState.selected_tool]["tex"]))
		for i in range(blueprint_slots.size()):
			var sl := blueprint_slots[i]
			var is_act := (i == active_slot_idx)
			var col := Color(0.32, 0.96, 1.0, 0.75 if is_act else 0.30)
			draw_set_transform(sl["pos"], float(sl["rot"]), Vector2.ONE)
			if tex:
				var sz := tex.get_size() * 1.15
				if GameState.selected_tool == "belt": sz = Vector2(110, 26)
				elif GameState.selected_tool == "lift": sz = Vector2(36, 118)
				draw_texture_rect(tex, Rect2(-sz.x * 0.5, -sz.y, sz.x, sz.y), false, col)
			draw_rect(Rect2(-46, -54, 92, 54), col, false, 2.2 if is_act else 1.2)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 2. Tesla Energy Domes (back layer)
	for b in buildings:
		if b["id"] != "tesla": continue
		var bp: Vector2 = b["pos"]
		if bp.distance_to(cpos) > max_d + TESLA_DOME_R: continue
		var active := float(b["pwr_ratio"]) > 0.1
		var dcol := Color(0.22, 0.84, 1.0, 0.08) if active else Color(0.6, 0.3, 0.3, 0.04)
		var rcol := Color(0.35, 0.92, 1.0, 0.50) if active else Color(0.85, 0.35, 0.35, 0.28)
		draw_circle(bp, TESLA_DOME_R, dcol)
		draw_arc(bp, TESLA_DOME_R, 0.0, TAU, 72, rcol, 2.2)

	# 3. Physical Buildings (Crisp HD-2D Pixel Art Sprites + Additive Glows!)
	var belt_fi := int(floor(anim_t * 10.0)) % 4
	for b in buildings:
		var bp: Vector2 = b["pos"]
		if bp.distance_to(cpos) > max_d: continue
		var bid := String(b["id"])
		var pwr := float(b["pwr_ratio"])
		var rot := float(b["rot"])
		var n: Vector2 = b["normal"]

		# Emissive glow halos for active furnaces, Tesla orbs, Geothermal & Printers
		if glow and pwr > 0.1:
			if bid == "tesla":
				draw_texture_rect(glow, Rect2(bp.x + n.x * 58 - 54, bp.y + n.y * 58 - 54, 108, 108), false, Color(0.25, 0.88, 1.0, 0.38))
			elif bid == "smelter" and not b["in_buf"].is_empty():
				draw_texture_rect(glow, Rect2(bp.x + n.x * 26 - 52, bp.y + n.y * 26 - 52, 104, 104), false, Color(1.0, 0.52, 0.14, 0.36))
			elif bid == "geothermal":
				draw_texture_rect(glow, Rect2(bp.x + n.x * 32 - 58, bp.y + n.y * 32 - 58, 116, 116), false, Color(1.0, 0.45, 0.12, 0.35))
			elif bid == "printer":
				draw_texture_rect(glow, Rect2(bp.x + n.x * 42 - 64, bp.y + n.y * 42 - 64, 128, 128), false, Color(0.28, 0.88, 1.0, 0.28))

		draw_set_transform(bp, rot, Vector2.ONE)
		if bid == "belt" and not ArtRegistry.belt_frames.is_empty():
			var bf := ArtRegistry.belt_frames[belt_fi if pwr > 0.05 else 0]
			var sx := 1.0 if int(b["dir"]) >= 0 else -1.0
			draw_set_transform(bp, rot, Vector2(sx, 1.0))
			draw_texture_rect(bf, Rect2(-56, -24, 112, 24), false)
		elif bid == "lift" and not ArtRegistry.lift_frames.is_empty():
			var lf := ArtRegistry.lift_frames[belt_fi if pwr > 0.05 else 0]
			draw_texture_rect(lf, Rect2(-18, -120, 36, 120), false)
		else:
			var tex := ArtRegistry.get_tex(String(GameState.BUILDINGS[bid]["tex"]))
			if tex:
				var scale_f := 1.35 if bid in ["printer", "mass_driver"] else 1.25
				var sz := tex.get_size() * scale_f
				var y_off := 16.0 if bid == "drill" else 0.0
				draw_texture_rect(tex, Rect2(-sz.x * 0.5, -sz.y + y_off, sz.x, sz.y), false)

		# Live Battery charge gauge bar
		if bid == "battery":
			var pct := clampf(float(b["battery_kj"]) / BATTERY_CAP_KJ, 0.0, 1.0)
			draw_rect(Rect2(-24, -68, 48, 7), Color(0.08, 0.12, 0.18, 0.9))
			draw_rect(Rect2(-23, -67, 46 * pct, 5), Color(0.28, 0.95, 0.65))

		# Assembler recipe label + progress bar
		if bid == "assembler":
			draw_string(font, Vector2(-34, -72), String(b["recipe"]).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 68, 11, Color(0.45, 0.96, 1.0))
			var pr := clampf(float(b["timer"]) / 2.2, 0.0, 1.0)
			draw_rect(Rect2(-26, -66, 52, 4), Color(0.08, 0.12, 0.18))
			draw_rect(Rect2(-26, -66, 52 * pr, 4), Color(0.32, 0.96, 0.68))

		# Status badge (NO PWR / FULL / WIRE PICK)
		if int(b["uid"]) == wire_pick_uid:
			draw_circle(Vector2(0, -48), 32.0, Color(0.35, 0.95, 1.0, 0.25))
			draw_arc(Vector2(0, -48), 32.0, 0.0, TAU, 24, Color(0.5, 1.0, 1.0), 2.5)
		elif float(GameState.BUILDINGS[bid]["pwr_use"]) > 0.0 and pwr <= 0.05:
			draw_string(font, Vector2(-28, -80), "NO PWR", HORIZONTAL_ALIGNMENT_CENTER, 56, 10, Color(1.0, 0.42, 0.36))
		elif bool(b["blocked"]):
			draw_string(font, Vector2(-22, -80), "FULL", HORIZONTAL_ALIGNMENT_CENTER, 44, 10, Color(1.0, 0.82, 0.32))

		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 4. Power Cables with Animated Traveling Electric Pulses
	for w in wires:
		var b1 := _by_uid(int(w[0])); var b2 := _by_uid(int(w[1]))
		if b1.is_empty() or b2.is_empty(): continue
		var p1 := Vector2(b1["pos"]) + Vector2(b1["normal"]) * 46.0
		var p2 := Vector2(b2["pos"]) + Vector2(b2["normal"]) * 46.0
		if p1.distance_to(cpos) > max_d + WIRE_RANGE: continue
		var hot := float(b1["pwr_ratio"]) > 0.1 or float(b2["pwr_ratio"]) > 0.1
		var c_line := Color(0.30, 0.92, 1.0, 0.88) if hot else Color(0.52, 0.60, 0.72, 0.55)
		draw_line(p1, p2, Color(0.06, 0.16, 0.26, 0.75), 6.0)
		draw_line(p1, p2, c_line, 2.4)
		if hot:
			var t := fposmod(anim_t * 0.85, 1.0)
			draw_circle(p1.lerp(p2, t), 4.2, Color(0.88, 1.0, 1.0, 0.95))

	# 5. Physical Items Traveling on Belts & Lifts
	for it in belt_items:
		var ip := _belt_item_pos(it)
		if ip.distance_to(cpos) > max_d: continue
		var ic := ArtRegistry.get_item_icon(String(it["item"]))
		if ic:
			draw_texture_rect(ic, Rect2(ip - Vector2(9, 9), Vector2(18, 18)), false)
		else:
			draw_circle(ip, 5.0, Color(0.95, 0.78, 0.36))

	# 6. Mass Driver Blazing Spacecraft Launch Trails & Turret Lasers
	for tr in launch_trails:
		var p: Vector2 = tr["pos"]
		var v: Vector2 = tr["vel"].normalized()
		draw_line(p, p - v * 120.0, Color(1.0, 0.78, 0.34, 0.75), 5.0)
		draw_line(p, p - v * 65.0, Color(0.95, 0.98, 1.0, 0.95), 2.5)
		if glow:
			draw_texture_rect(glow, Rect2(p.x - 36, p.y - 36, 72, 72), false, Color(1.0, 0.82, 0.36, 0.55))

	for bm in turret_beams:
		draw_line(bm["a"], bm["b"], Color(0.32, 0.94, 1.0, 0.85), 3.2)
		draw_line(bm["a"], bm["b"], Color(1.0, 1.0, 1.0, 0.9), 1.2)
