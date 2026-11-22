extends Node2D

# Multi-layer Surface & Subterranean Industrial Grid:
# Hard Local Wired Power (Solar/Geo/Battery -> Wire -> Tesla Relay Dome),
# Physical Logistics (Drill -> Belt/Lift -> 4-Way Filter Depot -> Smelter -> Assembler -> Gantry Printer -> Mass Driver),
# and HD-2D Pixel-Art Rendering with Smoke Plumes, Fireglow & Foundation Pads.

signal depot_opened(uid: int)
signal building_inspected(uid: int)

const POWER_NODES: Array[String] = ["solar", "geothermal", "tesla", "battery"]
const WIRE_RANGE: float = 680.0
const TESLA_DOME_R: float = 480.0
const BATTERY_CAP_KJ: float = 18000.0
const DRILL_BUF: int = 6
const IN_CAP: int = 12
const OUT_CAP: int = 8
const DEPOT_CAP: int = 240
const RECIPES: Array[String] = ["circuit", "alloy", "sci_pack"]

var planet: SphericalPlanet = null
var player: Node2D = null
var swarm: Node2D = null

var buildings: Array[Dictionary] = []
var wires: Array[Array] = []
var belt_items: Array[Dictionary] = []
var launch_trails: Array[Dictionary] = []
var turret_beams: Array[Dictionary] = []

var wire_pick_uid: int = -1
var selected_depot_uid: int = -1
var salvage_armed_uid: int = -1
var salvage_armed_ms: int = 0
var next_uid: int = 1
var anim_t: float = 0.0
var hover_world: Vector2 = Vector2.ZERO
var show_ghost: bool = false

func _ready() -> void:
	z_index = 10

func clear_all() -> void:
	buildings.clear(); wires.clear(); belt_items.clear()
	launch_trails.clear(); turret_beams.clear()
	wire_pick_uid = -1; selected_depot_uid = -1; salvage_armed_uid = -1; salvage_armed_ms = 0; next_uid = 1

func _by_uid(uid: int) -> Dictionary:
	for b in buildings:
		if int(b["uid"]) == uid: return b
	return {}

func _buf_sum(d: Dictionary) -> int:
	var s := 0
	for v in d.values(): s += int(v)
	return s

func _buf_add(d: Dictionary, item: String, qty: int) -> void:
	d[item] = int(d.get(item, 0)) + qty

func _buf_take(d: Dictionary, want: String = "auto") -> String:
	if d.is_empty(): return ""
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

func is_foundation_protected(col: int, row: int) -> bool:
	var wc := SphericalPlanet.wrap_col(col)
	for b in buildings:
		var br := int(b["row"])
		if row < br - 2 or row >= br: continue
		var bc := int(b["col"])
		var span := maxi(2, int(ceil(float(State.BLD[b["id"]]["w"]) / 48.0)))
		var dc := absi(SphericalPlanet.wrap_col(wc - bc + SphericalPlanet.COLS / 2) - SphericalPlanet.COLS / 2)
		if dc <= span:
			return true
	return false

# ------------------------------------------------------------------------------
# PLACEMENT ON CURVED SURFACE OR INSIDE EXCAVATED CAVERNS
# ------------------------------------------------------------------------------
func compute_snap_pose(world_pos: Vector2, bid: String) -> Dictionary:
	if not planet or not State.BLD.has(bid):
		return {}
	var cell := planet.world_to_cell(world_pos)
	var c := cell.x
	var r := cell.y
	# Find solid floor directly beneath cursor (surface OR cave floor!)
	if r >= SphericalPlanet.ROWS - 4 or not planet.is_solid(c, r):
		var floor_r := r
		while floor_r > 6 and not planet.is_solid(c, floor_r - 1):
			floor_r -= 1
		if floor_r <= 6:
			floor_r = planet.get_surface_row(c) + 1
		r = floor_r
	else:
		# Cursor inside rock: snap to top of local surface above it
		r = planet.get_surface_row(c) + 1
	return planet.get_pose_at(c, r)

func _too_close_to_existing(pos: Vector2, bid: String) -> bool:
	var min_d := 34.0 if (bid == "belt" or bid == "lift") else 54.0
	for b in buildings:
		var d := Vector2(b["pos"]).distance_to(pos)
		var bd := 30.0 if (b["id"] == "belt" or b["id"] == "lift") else min_d
		if d < bd:
			return true
	return false

func try_place_at(bid: String, world_pos: Vector2) -> bool:
	if not planet or not State.BLD.has(bid): return false
	if not State.is_unlocked(bid):
		Sfx.play("error")
		State.add_log("先に【研究】で必要な技術を解放してください。", "warn")
		return false
	if State.get_stock(bid) <= 0:
		Sfx.play("error")
		State.add_log("%sの在庫がありません。【クラフト】で製造してください。" % State.BLD[bid]["name"], "warn")
		return false
	var pose := compute_snap_pose(world_pos, bid)
	if pose.is_empty(): return false
	if _too_close_to_existing(pose["pos"], bid):
		Sfx.play("error")
		State.add_log("既存の装置と近すぎます。少し離れた地面をタップしてください。", "warn")
		return false
	var info: Dictionary = State.BLD[bid]
	State.add_stock(bid, -1)
	if State.get_stock(bid) <= 0 and State.selected_tool == bid:
		State.selected_tool = "mine"

	var ore_t := _find_local_ore(int(pose["col"]), int(pose["row"])) if bid == "drill" else ""
	var b := {
		"uid": next_uid,
		"id": bid,
		"col": int(pose["col"]),
		"row": int(pose["row"]),
		"pos": pose["pos"],
		"normal": pose["normal"],
		"rot": float(pose["rot"]),
		"dir": State.build_dir,
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
	buildings.append(b)
	planet.spawn_sparks(pose["pos"], Color(0.36, 0.94, 1.0), 10)
	_solve_power(0.0)
	Sfx.play("build")
	State.note_building_placed(bid)
	State.add_log("設置完了: %s%s" % [info["name"], "（【配線】でテスラリレーへ接続しよう）" if (bid in POWER_NODES) else ""], "good")
	return true

func _find_local_ore(c: int, r: int) -> String:
	for dr in range(1, 8):
		for dc in range(-2, 3):
			var o := planet.get_ore_id(c + dc, r - dr)
			if o != "": return o
	return "fe"

func salvage_by_uid(uid: int) -> bool:
	var bi := -1
	for i in range(buildings.size()):
		if int(buildings[i]["uid"]) == uid:
			bi = i; break
	if bi < 0: return false
	var b := buildings[bi]
	var dead_u := int(b["uid"])
	var bid := String(b["id"])
	var info: Dictionary = State.BLD[bid]
	# 中に入っていた資源・在庫も漏れなくプレイヤーへ返却！
	for k in b["in_buf"].keys(): State.add_r(String(k), int(b["in_buf"][k]))
	for k in b["out_buf"].keys(): State.add_r(String(k), int(b["out_buf"][k]))
	for k in b["inv"].keys(): State.add_r(String(k), int(b["inv"][k]))
	State.add_stock(bid, 1)
	for wi in range(wires.size() - 1, -1, -1):
		if int(wires[wi][0]) == dead_u or int(wires[wi][1]) == dead_u:
			wires.remove_at(wi)
	if wire_pick_uid == dead_u: wire_pick_uid = -1
	if selected_depot_uid == dead_u: selected_depot_uid = -1
	if salvage_armed_uid == dead_u: salvage_armed_uid = -1
	buildings.remove_at(bi)
	_solve_power(0.0)
	Sfx.play("pop")
	State.add_log("削除・回収完了: %s（所持リストに戻りました）" % info["name"], "info")
	return true

func try_salvage_at(world_pos: Vector2) -> bool:
	var b := find_nearest(world_pos, 78.0)
	if b.is_empty(): return false
	return salvage_by_uid(int(b["uid"]))

func try_double_tap_salvage(world_pos: Vector2) -> bool:
	var b := find_nearest(world_pos, 78.0)
	if b.is_empty():
		salvage_armed_uid = -1
		return false
	var uid := int(b["uid"])
	var now := Time.get_ticks_msec()
	if salvage_armed_uid == uid and (now - salvage_armed_ms) <= 3200:
		salvage_armed_uid = -1
		return salvage_by_uid(uid)
	salvage_armed_uid = uid
	salvage_armed_ms = now
	Sfx.play("click")
	State.add_log("削除確認: もう一度「%s」をタップすると削除・回収します" % State.BLD[b["id"]]["name"], "warn")
	return true

# ------------------------------------------------------------------------------
# POWER WIRING & BUILDING INTERACTION
# ------------------------------------------------------------------------------
func find_nearest(pos: Vector2, max_d: float = 110.0, ids: Array = []) -> Dictionary:
	var best: Dictionary = {}
	var bd := max_d
	for b in buildings:
		if not ids.is_empty() and not (b["id"] in ids): continue
		var d := Vector2(b["pos"]).distance_to(pos)
		if d < bd: bd = d; best = b
	return best

func _are_wired(u1: int, u2: int) -> bool:
	for w in wires:
		if (int(w[0]) == u1 and int(w[1]) == u2) or (int(w[0]) == u2 and int(w[1]) == u1): return true
	return false

func toggle_wire(u1: int, u2: int) -> bool:
	if u1 <= 0 or u2 <= 0 or u1 == u2: return false
	var b1 := _by_uid(u1); var b2 := _by_uid(u2)
	if b1.is_empty() or b2.is_empty(): return false
	if not (b1["id"] in POWER_NODES) or not (b2["id"] in POWER_NODES): return false
	for i in range(wires.size()):
		var w := wires[i]
		if (int(w[0]) == u1 and int(w[1]) == u2) or (int(w[0]) == u2 and int(w[1]) == u1):
			wires.remove_at(i)
			_solve_power(0.0)
			Sfx.play("pop")
			return true
	if Vector2(b1["pos"]).distance_to(Vector2(b2["pos"])) > WIRE_RANGE:
		Sfx.play("error")
		State.add_log("電線の距離が長すぎます（最大 %dpx）。" % int(WIRE_RANGE), "warn")
		return false
	wires.append([u1, u2])
	if planet:
		planet.spawn_sparks((Vector2(b1["pos"]) + Vector2(b2["pos"])) * 0.5, Color(0.32, 0.94, 1.0), 10)
	_solve_power(0.0)
	Sfx.play("wire")
	State.update_tutorial()
	State.add_log("電線接続: %s ⇔ %s" % [State.BLD[b1["id"]]["name"], State.BLD[b2["id"]]["name"]], "good")
	return true

func try_wire_at(pos: Vector2) -> bool:
	var pn := find_nearest(pos, 150.0, POWER_NODES)
	if pn.is_empty():
		wire_pick_uid = -1
		return false
	var u1 := int(pn["uid"])
	if wire_pick_uid == -1:
		wire_pick_uid = u1
		Sfx.play("click")
		State.add_log("接続元選択: %s → つなぐ先の電力装置をタップ" % State.BLD[pn["id"]]["name"], "info")
		return true
	elif wire_pick_uid == u1:
		var best_u := -1; var best_s := 1e9
		var is_gen: bool = String(pn["id"]) in ["solar", "geothermal"]
		for b in buildings:
			var bu := int(b["uid"])
			if bu == u1 or not (b["id"] in POWER_NODES) or _are_wired(u1, bu): continue
			var d := Vector2(pn["pos"]).distance_to(Vector2(b["pos"]))
			if d <= WIRE_RANGE:
				var b_gen: bool = String(b["id"]) in ["solar", "geothermal"]
				var sc := d - (1000.0 if (is_gen != b_gen) else 0.0)
				if sc < best_s: best_s = sc; best_u = bu
		wire_pick_uid = -1
		if best_u > 0: return toggle_wire(u1, best_u)
		return true
	else:
		var u0 := wire_pick_uid
		wire_pick_uid = -1
		return toggle_wire(u0, u1)

func handle_world_click(world_pos: Vector2) -> bool:
	var tool := State.selected_tool
	if tool == "wire":
		salvage_armed_uid = -1
		return try_wire_at(world_pos)
	if tool == "salvage":
		return try_double_tap_salvage(world_pos)
	if State.BLD.has(tool):
		salvage_armed_uid = -1
		return try_place_at(tool, world_pos)

	# 通常モード：施設をタップすると中身・詳細パネルを開く（タップ採掘は廃止！）
	salvage_armed_uid = -1
	var b := find_nearest(world_pos, 78.0)
	if b.is_empty(): return false
	var uid := int(b["uid"])
	var bid := String(b["id"])
	if bid == "depot":
		selected_depot_uid = uid
		State.tut_opened_depot = true
		State.update_tutorial()
		Sfx.play("select")
		depot_opened.emit(uid)
		return true
	Sfx.play("select")
	building_inspected.emit(uid)
	return true

func interact_near_player(pos: Vector2) -> bool:
	var b := find_nearest(pos, 115.0)
	if b.is_empty(): return false
	var uid := int(b["uid"])
	if String(b["id"]) == "depot":
		selected_depot_uid = uid
		State.tut_opened_depot = true
		State.update_tutorial()
		Sfx.play("select")
		depot_opened.emit(uid)
		return true
	Sfx.play("select")
	building_inspected.emit(uid)
	return true

# ------------------------------------------------------------------------------
# 施設詳細・中身インスペクタ用API（全施設対応）
# ------------------------------------------------------------------------------
func get_building_snap(uid: int) -> Dictionary:
	var b := _by_uid(uid)
	if b.is_empty(): return {}
	var bid := String(b["id"])
	var info: Dictionary = State.BLD[bid]
	var links: Array[String] = []
	for w in wires:
		if int(w[0]) == uid:
			var ob := _by_uid(int(w[1]))
			if not ob.is_empty(): links.append(String(State.BLD[ob["id"]]["name"]))
		elif int(w[1]) == uid:
			var ob := _by_uid(int(w[0]))
			if not ob.is_empty(): links.append(String(State.BLD[ob["id"]]["name"]))
	var live_gen := 0.0
	if bid == "solar":
		live_gen = float(info["gen"]) * (planet.get_sunlight(b["pos"]) if planet else 1.0)
	elif bid == "geothermal":
		live_gen = float(info["gen"])
	return {
		"uid": uid, "id": bid, "name": String(info["name"]), "tex": String(info["tex"]),
		"desc": String(info["desc"]), "is_power": (bid in POWER_NODES),
		"gen": live_gen, "use": float(info["use"]),
		"pwr_ratio": float(b["pwr_ratio"]), "wired": bool(b["wired"]), "links": links,
		"battery_kj": float(b["battery_kj"]), "battery_cap": BATTERY_CAP_KJ,
		"ore_target": String(b["ore_target"]), "dir": int(b["dir"]),
		"recipe": String(b["recipe"]), "blocked": bool(b["blocked"]),
		"in_buf": b["in_buf"].duplicate(), "out_buf": b["out_buf"].duplicate(),
	}

func building_collect(uid: int) -> int:
	var b := _by_uid(uid)
	if b.is_empty(): return 0
	return _collect_out(b)

func building_hand_feed(uid: int) -> bool:
	var b := _by_uid(uid)
	if b.is_empty(): return false
	return _hand_feed(b)

func building_flip_dir(uid: int) -> void:
	var b := _by_uid(uid)
	if b.is_empty(): return
	b["dir"] = -int(b["dir"])
	Sfx.play("click")
	State.add_log("%s の向きを反転しました。" % State.BLD[b["id"]]["name"], "info")

func building_cycle_recipe(uid: int) -> String:
	var b := _by_uid(uid)
	if b.is_empty(): return ""
	var ri := (RECIPES.find(String(b["recipe"])) + 1) % RECIPES.size()
	b["recipe"] = RECIPES[ri]
	_collect_out(b)
	Sfx.play("select")
	State.add_log("自動組立機レシピ変更: %s" % State.res_name(String(b["recipe"])), "info")
	return String(b["recipe"])

func start_wire_from(uid: int) -> void:
	var b := _by_uid(uid)
	if b.is_empty() or not (b["id"] in POWER_NODES): return
	State.selected_tool = "wire"
	wire_pick_uid = uid
	Sfx.play("click")
	State.add_log("接続元選択: %s → つなぐ先の電力装置をタップ" % State.BLD[b["id"]]["name"], "info")

func _collect_out(b: Dictionary) -> int:
	var out: Dictionary = b["out_buf"]
	var got := 0
	for k in out.keys().duplicate():
		var cnt := int(out[k])
		if cnt > 0:
			State.add_r(String(k), cnt)
			out.erase(k)
			got += cnt
			if planet:
				planet.spawn_popup(Vector2(b["pos"]), "+%d %s" % [cnt, State.res_name(String(k))], Color(0.45, 0.96, 1.0))
	if got > 0: Sfx.play("pop")
	return got

func _hand_feed(b: Dictionary) -> bool:
	var bid := String(b["id"])
	var fed := false
	if bid == "smelter":
		var o2p := {"fe": "plate_fe", "cu": "wire_cu", "si": "wafer_si"}
		var ores: Array[String] = ["fe", "cu", "si"]
		ores.sort_custom(func(a: String, c: String) -> bool:
			return float(State.get_r(o2p[a])) < float(State.get_r(o2p[c]))
		)
		for o in ores:
			if State.get_r(o) >= 2 and _buf_sum(b["in_buf"]) < IN_CAP:
				var g := mini(4, mini(State.get_r(o), IN_CAP - _buf_sum(b["in_buf"])))
				State.add_r(o, -g); _buf_add(b["in_buf"], o, g); fed = true; break
	elif bid == "assembler":
		var rec := String(b["recipe"])
		var wants: Array[String] = ["plate_fe", "wire_cu"] if rec == "circuit" else (["plate_fe", "ti"] if rec == "alloy" else ["plate_fe", "circuit"])
		for w in wants:
			if State.get_r(w) >= 1 and _buf_sum(b["in_buf"]) < IN_CAP:
				var g := mini(2, mini(State.get_r(w), IN_CAP - _buf_sum(b["in_buf"])))
				State.add_r(w, -g); _buf_add(b["in_buf"], w, g); fed = true
	elif bid == "gantry_printer":
		for w in ["plate_fe", "circuit"]:
			if State.get_r(w) >= 1 and _buf_sum(b["in_buf"]) < IN_CAP:
				var g := mini(2, mini(State.get_r(w), IN_CAP - _buf_sum(b["in_buf"])))
				State.add_r(w, -g); _buf_add(b["in_buf"], w, g); fed = true
	if fed: Sfx.play("pop")
	return fed

# ------------------------------------------------------------------------------
# DEPOT 4-WAY OUTPUT FILTER INTERFACE
# ------------------------------------------------------------------------------
func get_depot_snap(uid: int) -> Dictionary:
	var d := _by_uid(uid)
	if d.is_empty(): return {}
	return {"uid": uid, "inv": d["inv"].duplicate(), "out_filters": d["out_filters"].duplicate(), "total": _buf_sum(d["inv"]), "cap": DEPOT_CAP}

func depot_transfer(uid: int, item: String, to_depot: bool, qty: int = 5) -> bool:
	var d := _by_uid(uid)
	if d.is_empty(): return false
	var inv: Dictionary = d["inv"]
	if to_depot:
		var mv := mini(qty, mini(State.get_r(item), maxi(0, DEPOT_CAP - _buf_sum(inv))))
		if mv <= 0: return false
		State.add_r(item, -mv); _buf_add(inv, item, mv)
	else:
		var hv := int(inv.get(item, 0))
		var mv := mini(qty, hv)
		if mv <= 0: return false
		if hv == mv: inv.erase(item)
		else: inv[item] = hv - mv
		State.add_r(item, mv)
	Sfx.play("pop")
	return true

func depot_deposit_all(uid: int) -> int:
	var tot := 0
	for r in ["fe", "cu", "si", "ti", "ice"]:
		var a := State.get_r(r)
		if a > 0 and depot_transfer(uid, r, true, a): tot += a
	return tot

func depot_cycle_filter(uid: int, dir_key: String) -> String:
	var d := _by_uid(uid)
	if d.is_empty(): return "none"
	var cyc: Array[String] = ["none", "auto", "fe", "cu", "si", "ti", "plate_fe", "wire_cu", "wafer_si", "circuit", "alloy", "sci_pack", "probe_stock"]
	var cur := String(d["out_filters"].get(dir_key, "none"))
	var nxt := cyc[(cyc.find(cur) + 1) % cyc.size()]
	d["out_filters"][dir_key] = nxt
	Sfx.play("click")
	return nxt

# ------------------------------------------------------------------------------
# HARD LOCAL WIRED POWER GRID SOLVER
# ------------------------------------------------------------------------------
func _solve_power(delta: float) -> void:
	for b in buildings:
		b["pwr_ratio"] = 0.0; b["wired"] = false
	var adj: Dictionary = {}
	for b in buildings:
		if b["id"] in POWER_NODES: adj[int(b["uid"])] = []
	for w in wires:
		var u1 := int(w[0]); var u2 := int(w[1])
		if adj.has(u1) and adj.has(u2):
			adj[u1].append(u2); adj[u2].append(u1)
			var b1 := _by_uid(u1); var b2 := _by_uid(u2)
			if not b1.is_empty(): b1["wired"] = true
			if not b2.is_empty(): b2["wired"] = true

	var vis: Dictionary = {}
	var tot_p := 0.0; var tot_u := 0.0; var tot_s := 0.0; var tot_c := 0.0; var t_on := 0
	var dyson_w := 240.0 if bool(State.megastructures["dyson"]) else 0.0

	for uid in adj.keys():
		if vis.has(uid): continue
		var comp: Array[int] = []; var q: Array[int] = [int(uid)]; vis[uid] = true
		while not q.is_empty():
			var cur: int = int(q.pop_front())
			comp.append(cur)
			for nb in adj[cur]:
				if not vis.has(nb): vis[nb] = true; q.append(int(nb))
		var gen := 0.0; var teslas: Array[Dictionary] = []; var bats: Array[Dictionary] = []
		for cu in comp:
			var nb := _by_uid(cu)
			if nb.is_empty(): continue
			var bid := String(nb["id"])
			if bid == "solar":
				gen += float(State.BLD["solar"]["gen"]) * (planet.get_sunlight(nb["pos"]) if planet else 1.0)
			elif bid == "geothermal":
				gen += float(State.BLD["geothermal"]["gen"])
			elif bid == "tesla": teslas.append(nb)
			elif bid == "battery": bats.append(nb)
		if not teslas.is_empty(): gen += dyson_w

		var cons: Array[Dictionary] = []; var seen: Dictionary = {}; var dem := 0.0
		for ts in teslas:
			var tp: Vector2 = ts["pos"]
			for b in buildings:
				var bu := int(b["uid"])
				if seen.has(bu) or (b["id"] in POWER_NODES): continue
				if Vector2(b["pos"]).distance_to(tp) <= TESLA_DOME_R:
					seen[bu] = true; cons.append(b); dem += float(State.BLD[b["id"]]["use"])

		var stored := 0.0; var cap := float(bats.size()) * BATTERY_CAP_KJ
		for bt in bats: stored += float(bt["battery_kj"])
		var sup := gen
		if delta > 0.0 and not bats.is_empty():
			if gen >= dem:
				var sur := (gen - dem) * delta
				for bt in bats:
					bt["battery_kj"] = minf(BATTERY_CAP_KJ, float(bt["battery_kj"]) + sur / float(bats.size()))
			else:
				var def := (dem - gen) * delta; var drn := 0.0
				for bt in bats:
					var tk := minf(float(bt["battery_kj"]), def / float(bats.size()))
					bt["battery_kj"] = float(bt["battery_kj"]) - tk; drn += tk
				sup = gen + drn / maxf(0.0001, delta)
			stored = 0.0
			for bt in bats: stored += float(bt["battery_kj"])

		var ratio := 0.0
		if not teslas.is_empty():
			ratio = (1.0 if (sup > 0.5 or stored > 1.0) else 0.0) if dem <= 0.01 else clampf(sup / dem, 0.0, 1.0)
		for cu in comp:
			var nb := _by_uid(cu)
			if not nb.is_empty(): nb["pwr_ratio"] = ratio if (not teslas.is_empty() or not bats.is_empty()) else 0.0
		if ratio > 0.15: t_on += teslas.size()
		for c in cons: c["pwr_ratio"] = maxf(float(c["pwr_ratio"]), ratio)
		if not teslas.is_empty() or not bats.is_empty(): tot_p += gen
		tot_u += dem; tot_s += stored; tot_c += cap

	State.pwr_prod = tot_p; State.pwr_use = tot_u; State.pwr_stored = tot_s
	State.pwr_cap = tot_c; State.wire_count = wires.size(); State.active_teslas = t_on

# ------------------------------------------------------------------------------
# PHYSICAL LOGISTICS & PRODUCTION TICK
# ------------------------------------------------------------------------------
func _deliver(target: Dictionary, item: String) -> bool:
	var bid := String(target["id"])
	if bid == "depot":
		if _buf_sum(target["inv"]) >= DEPOT_CAP: return false
		_buf_add(target["inv"], item, 1); return true
	elif bid == "smelter":
		if not (item in ["fe", "cu", "si"]) or _buf_sum(target["in_buf"]) >= IN_CAP: return false
		_buf_add(target["in_buf"], item, 1); return true
	elif bid == "assembler":
		if not (item in ["plate_fe", "wire_cu", "wafer_si", "ti", "circuit"]) or _buf_sum(target["in_buf"]) >= IN_CAP: return false
		_buf_add(target["in_buf"], item, 1); return true
	elif bid == "gantry_printer":
		if not (item in ["plate_fe", "circuit"]) or _buf_sum(target["in_buf"]) >= IN_CAP: return false
		_buf_add(target["in_buf"], item, 1); return true
	elif bid == "mass_driver" and item == "probe_stock":
		_buf_add(target["in_buf"], item, 1); return true
	return false

func _find_neighbor(b: Dictionary, dir_vec: Vector2) -> Dictionary:
	var p: Vector2 = b["pos"]
	var best: Dictionary = {}; var bd := 115.0
	for o in buildings:
		if int(o["uid"]) == int(b["uid"]): continue
		var dvec := Vector2(o["pos"]) - p
		var d := dvec.length()
		if d < bd and d > 12.0 and dvec.normalized().dot(dir_vec) > 0.55:
			bd = d; best = o
	return best

func _try_send(b: Dictionary, buf: Dictionary, filter_item: String, dir_vec: Vector2) -> bool:
	var nb := _find_neighbor(b, dir_vec)
	if nb.is_empty(): return false
	var it := _buf_take(buf, filter_item)
	if it == "": return false
	var ok := false
	if nb["id"] == "belt" or nb["id"] == "lift":
		belt_items.append({"from": b["pos"], "to": nb["pos"], "target_uid": int(nb["uid"]), "item": it, "t": 0.05})
		ok = true
	else:
		ok = _deliver(nb, it)
	if not ok: _buf_add(buf, it, 1)
	return ok

func collect_near_player(pos: Vector2, rad: float = 82.0) -> int:
	var got := 0
	for i in range(belt_items.size() - 1, -1, -1):
		var p: Vector2 = Vector2(belt_items[i]["from"]).lerp(Vector2(belt_items[i]["to"]), float(belt_items[i]["t"]))
		if p.distance_to(pos) <= rad:
			State.add_r(String(belt_items[i]["item"]), 1)
			belt_items.remove_at(i); got += 1
	for b in buildings:
		if b["id"] in ["drill", "smelter", "assembler", "gantry_printer"] and not b["out_buf"].is_empty():
			if Vector2(b["pos"]).distance_to(pos) <= 68.0:
				got += _collect_out(b)
	if got > 0: Sfx.play("pop")
	return got

func service_player(pos: Vector2, delta: float) -> void:
	var near_pad := false
	for b in buildings:
		if (b["id"] in POWER_NODES or b["id"] == "depot") and float(b["pwr_ratio"]) > 0.15:
			if Vector2(b["pos"]).distance_to(pos) <= 260.0: near_pad = true; break
	if near_pad:
		State.ion_bat = minf(State.max_ion_bat, State.ion_bat + 36.0 * delta)
		State.fuel = minf(State.max_fuel, State.fuel + 28.0 * delta)
		State.hp = minf(State.max_hp, State.hp + 12.0 * delta)
	else:
		var sun := planet.get_sunlight(pos) if planet else 0.6
		State.ion_bat = minf(State.max_ion_bat, State.ion_bat + (6.0 + 9.0 * sun) * delta)

func _process(delta: float) -> void:
	anim_t += delta
	_solve_power(delta)
	var spd := 1.0 + float(State.attached_drones) * 0.16
	var act_p := 0; var tot_p := 0

	for b in buildings:
		var bid := String(b["id"])
		var pwr := float(b["pwr_ratio"])
		b["blocked"] = false
		if pwr > 0.05:
			b["timer"] = float(b["timer"]) + delta * spd * pwr
			b["smoke_t"] = float(b["smoke_t"]) + delta * pwr
		b["push_t"] = float(b["push_t"]) + delta
		var n: Vector2 = b["normal"]
		var tang := Vector2(-n.y, n.x)

		if float(b["push_t"]) >= 0.45:
			b["push_t"] = 0.0
			if bid == "depot":
				var flts: Dictionary = b["out_filters"]
				for pair in [["right", tang], ["left", -tang], ["up", n], ["down", -n]]:
					var fk := String(flts.get(pair[0], "none"))
					if fk != "none": _try_send(b, b["inv"], fk, pair[1])
			elif bid in ["drill", "smelter", "assembler", "gantry_printer"] and not b["out_buf"].is_empty():
				for dv in [tang, -tang, n, -n]:
					if _try_send(b, b["out_buf"], "auto", dv): break

		match bid:
			"drill":
				if pwr <= 0.05: continue
				if _buf_sum(b["out_buf"]) >= DRILL_BUF: b["blocked"] = true; continue
				if float(b["timer"]) >= 1.2:
					b["timer"] = 0.0; _buf_add(b["out_buf"], String(b["ore_target"]), 1)
					if planet and float(b["smoke_t"]) >= 1.0:
						b["smoke_t"] = 0.0; planet.spawn_smoke(Vector2(b["pos"]) + n * 42.0, n)
			"smelter":
				if pwr <= 0.05: continue
				if _buf_sum(b["out_buf"]) >= OUT_CAP: b["blocked"] = true; continue
				if planet and float(b["smoke_t"]) >= 0.55 and not b["in_buf"].is_empty():
					b["smoke_t"] = 0.0; planet.spawn_smoke(Vector2(b["pos"]) + n * 76.0 - tang * 16.0, n, Color(0.76, 0.80, 0.88, 0.44))
				if float(b["timer"]) >= 1.8:
					b["timer"] = 0.0
					var ib: Dictionary = b["in_buf"]
					if int(ib.get("fe", 0)) >= 2: ib["fe"] -= 2; if ib["fe"] <= 0: ib.erase("fe"); _buf_add(b["out_buf"], "plate_fe", 1)
					elif int(ib.get("cu", 0)) >= 2: ib["cu"] -= 2; if ib["cu"] <= 0: ib.erase("cu"); _buf_add(b["out_buf"], "wire_cu", 1)
					elif int(ib.get("si", 0)) >= 2: ib["si"] -= 2; if ib["si"] <= 0: ib.erase("si"); _buf_add(b["out_buf"], "wafer_si", 1)
			"assembler":
				if pwr <= 0.05: continue
				if _buf_sum(b["out_buf"]) >= OUT_CAP: b["blocked"] = true; continue
				if float(b["timer"]) >= 2.1:
					b["timer"] = 0.0
					var ib: Dictionary = b["in_buf"]; var rec := String(b["recipe"])
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
			"gantry_printer":
				tot_p += 1
				if pwr <= 0.05: continue
				act_p += 1
				if _buf_sum(b["out_buf"]) >= OUT_CAP: b["blocked"] = true; continue
				if float(b["timer"]) >= 2.6:
					b["timer"] = 0.0
					var ib: Dictionary = b["in_buf"]
					if int(ib.get("plate_fe", 0)) >= 2 and int(ib.get("circuit", 0)) >= 1:
						ib["plate_fe"] -= 2; ib["circuit"] -= 1
						if ib["plate_fe"] <= 0: ib.erase("plate_fe")
						if ib["circuit"] <= 0: ib.erase("circuit")
						_buf_add(b["out_buf"], "probe_stock", 1)
					elif State.get_r("plate_fe") >= 2 and State.get_r("circuit") >= 1:
						State.add_r("plate_fe", -2); State.add_r("circuit", -1); _buf_add(b["out_buf"], "probe_stock", 1)
			"mass_driver":
				if pwr <= 0.05: continue
				if float(b["timer"]) >= 2.2:
					var has_p := int(b["in_buf"].get("probe_stock", 0)) > 0
					var from_g := (not has_p) and State.get_r("probe_stock") > 0
					if has_p or from_g:
						b["timer"] = 0.0
						if has_p: _buf_take(b["in_buf"], "probe_stock")
						else: State.add_r("probe_stock", -1)
						_fire_railgun(b)
			"turret":
				if pwr <= 0.05 or not swarm: continue
				if float(b["timer"]) >= 0.65 and swarm.has_method("find_nearest_raider"):
					var tgt: Vector2 = swarm.find_nearest_raider(b["pos"], 1150.0)
					if tgt != Vector2.ZERO:
						b["timer"] = 0.0; swarm.damage_raider_near(tgt, 30.0)
						turret_beams.append({"a": Vector2(b["pos"]) + n * 34.0, "b": tgt, "life": 0.14})
						Sfx.play("laser")

	State.active_printers = act_p; State.total_printers = tot_p

	# Advance physical items traveling along belts/lifts
	for i in range(belt_items.size() - 1, -1, -1):
		var it := belt_items[i]
		var tb := _by_uid(int(it["target_uid"]))
		if tb.is_empty(): belt_items.remove_at(i); continue
		var bp := float(tb["pwr_ratio"])
		if bp <= 0.05: continue
		it["t"] = minf(1.02, float(it["t"]) + delta * 1.45 * bp)
		if float(it["t"]) >= 1.0:
			var n: Vector2 = tb["normal"]; var tang := Vector2(-n.y, n.x)
			var fwd := (n if tb["id"] == "lift" else tang) * float(tb["dir"])
			var nxt := _find_neighbor(tb, fwd)
			if not nxt.is_empty():
				if nxt["id"] == "belt" or nxt["id"] == "lift":
					it["from"] = tb["pos"]; it["to"] = nxt["pos"]; it["target_uid"] = int(nxt["uid"]); it["t"] = 0.04
				elif _deliver(nxt, String(it["item"])):
					belt_items.remove_at(i)
				else:
					it["t"] = 0.96
			else:
				it["t"] = 0.96

	for i in range(launch_trails.size() - 1, -1, -1):
		launch_trails[i]["pos"] += launch_trails[i]["vel"] * delta
		launch_trails[i]["life"] -= delta
		if float(launch_trails[i]["life"]) <= 0.0: launch_trails.remove_at(i)

	for i in range(turret_beams.size() - 1, -1, -1):
		turret_beams[i]["life"] -= delta
		if float(turret_beams[i]["life"]) <= 0.0: turret_beams.remove_at(i)

	queue_redraw()

func _fire_railgun(b: Dictionary) -> void:
	var n: Vector2 = b["normal"]; var tang := Vector2(-n.y, n.x)
	var dir := (n * 0.72 + tang * 0.69).normalized()
	var muzzle := Vector2(b["pos"]) + n * 86.0 + tang * 46.0
	launch_trails.append({"pos": muzzle, "vel": dir * 1050.0, "life": 2.2})
	if planet:
		planet.spawn_sparks(muzzle, Color(1.0, 0.86, 0.40), 16)
		planet.spawn_smoke(muzzle, dir, Color(1.0, 0.88, 0.68, 0.46))
	State.total_launches += 1
	var batch := 12 if State.swarm_fleet >= 30 else 6
	State.swarm_fleet = mini(State.SWARM_MAX, State.swarm_fleet + batch)
	if swarm and swarm.has_method("spawn_launched"):
		swarm.spawn_launched(muzzle, dir, batch)
	Sfx.play("launch")

# ------------------------------------------------------------------------------
# RENDERING: HD-2D BUILDINGS, FOUNDATION PADS, POWER WIRES, ITEMS & RAILGUN FIRE
# ------------------------------------------------------------------------------
func _draw() -> void:
	if not planet: return
	var glow := ArtReg.get_t("glow")
	var font := ArtReg.get_font()
	var fi := int(floor(anim_t * 10.0)) % 4

	# 1. Placement Hologram Ghost under cursor/player
	if show_ghost and State.BLD.has(State.selected_tool) and State.get_stock(State.selected_tool) > 0:
		var pose := compute_snap_pose(hover_world, State.selected_tool)
		if not pose.is_empty():
			var info: Dictionary = State.BLD[State.selected_tool]
			var ok := not _too_close_to_existing(pose["pos"], State.selected_tool)
			var gcol := Color(0.32, 0.98, 0.72, 0.78) if ok else Color(1.0, 0.36, 0.34, 0.75)
			draw_set_transform(pose["pos"], float(pose["rot"]), Vector2.ONE)
			var t := ArtReg.get_t(String(info["tex"]))
			var bw := float(info["w"]); var bh := float(info["h"])
			if t: draw_texture_rect(t, Rect2(-bw * 0.5, -bh, bw, bh), false, gcol)
			draw_rect(Rect2(-bw * 0.5, -bh, bw, bh), gcol, false, 2.2)
			draw_string(font, Vector2(-56, -bh - 10), "ここへ設置" if ok else "近すぎます", HORIZONTAL_ALIGNMENT_CENTER, 112, 11, gcol)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 2. Tesla Power Domes
	for b in buildings:
		if b["id"] != "tesla": continue
		var act := float(b["pwr_ratio"]) > 0.1
		draw_circle(b["pos"], TESLA_DOME_R, Color(0.22, 0.84, 1.0, 0.07) if act else Color(0.6, 0.25, 0.25, 0.04))
		draw_arc(b["pos"], TESLA_DOME_R, 0.0, TAU, 64, Color(0.34, 0.92, 1.0, 0.45) if act else Color(0.85, 0.35, 0.35, 0.28), 2.0)

	# 3. Buildings with Steel Foundation Girders + Emissive Glows!
	for b in buildings:
		var bid := String(b["id"]); var bp: Vector2 = b["pos"]; var n: Vector2 = b["normal"]
		var pwr := float(b["pwr_ratio"]); var info: Dictionary = State.BLD[bid]
		var bw := float(info["w"]); var bh := float(info["h"])

		if glow and pwr > 0.1:
			if bid == "tesla":
				draw_texture_rect(glow, Rect2(bp.x + n.x * 66 - 58, bp.y + n.y * 66 - 58, 116, 116), false, Color(0.26, 0.88, 1.0, 0.42))
			elif bid == "smelter" and not b["in_buf"].is_empty():
				draw_texture_rect(glow, Rect2(bp.x + n.x * 30 - 60, bp.y + n.y * 30 - 60, 120, 120), false, Color(1.0, 0.52, 0.14, 0.40))
			elif bid == "gantry_printer":
				draw_texture_rect(glow, Rect2(bp.x + n.x * 46 - 76, bp.y + n.y * 46 - 76, 152, 152), false, Color(0.30, 0.88, 1.0, 0.32))
			elif bid == "geothermal":
				draw_texture_rect(glow, Rect2(bp.x + n.x * 36 - 64, bp.y + n.y * 36 - 64, 128, 128), false, Color(1.0, 0.44, 0.12, 0.38))

		draw_set_transform(bp, float(b["rot"]), Vector2.ONE)
		# Reinforced industrial steel foundation pad anchoring structure seamlessly into curved ground!
		if bid != "belt" and bid != "lift":
			draw_rect(Rect2(-bw * 0.48, -2, bw * 0.96, 10), Color(0.16, 0.20, 0.26, 0.95))
			draw_rect(Rect2(-bw * 0.48, -2, bw * 0.96, 2), Color(0.45, 0.52, 0.62))

		if bid == "belt" and not ArtReg.belt_frames.is_empty():
			draw_set_transform(bp, float(b["rot"]), Vector2(float(b["dir"]), 1.0))
			draw_texture_rect(ArtReg.belt_frames[fi if pwr > 0.05 else 0], Rect2(-bw * 0.5, -bh, bw, bh), false)
		elif bid == "lift" and not ArtReg.lift_frames.is_empty():
			draw_texture_rect(ArtReg.lift_frames[fi if pwr > 0.05 else 0], Rect2(-bw * 0.5, -bh, bw, bh), false)
		else:
			var t := ArtReg.get_t(String(info["tex"]))
			var y_off := 16.0 if bid == "drill" else 0.0
			if t: draw_texture_rect(t, Rect2(-bw * 0.5, -bh + y_off, bw, bh), false)

		if bid == "battery":
			var pct := clampf(float(b["battery_kj"]) / BATTERY_CAP_KJ, 0.0, 1.0)
			draw_rect(Rect2(-24, -bh - 10, 48, 6), Color(0.08, 0.12, 0.18, 0.92))
			draw_rect(Rect2(-23, -bh - 9, 46 * pct, 4), Color(0.28, 0.96, 0.66))
		elif bid == "assembler":
			draw_string(font, Vector2(-38, -bh - 10), State.res_name(String(b["recipe"])), HORIZONTAL_ALIGNMENT_CENTER, 76, 10, Color(0.46, 0.96, 1.0))

		if int(b["uid"]) == salvage_armed_uid:
			var pulse_d := 38.0 + sin(anim_t * 9.0) * 5.0
			draw_arc(Vector2(0, -bh * 0.5), pulse_d, 0.0, TAU, 24, Color(1.0, 0.28, 0.28, 0.96), 3.2)
			draw_string(font, Vector2(-68, -bh - 18), "もう一度タップで削除！", HORIZONTAL_ALIGNMENT_CENTER, 136, 11, Color(1.0, 0.42, 0.38))
		elif int(b["uid"]) == wire_pick_uid:
			draw_arc(Vector2(0, -bh * 0.5), 36.0, 0.0, TAU, 24, Color(0.45, 1.0, 1.0), 2.8)
		elif State.tut_enabled and State.tut_step == 5 and (bid in POWER_NODES) and not bool(b["wired"]):
			var pulse := 34.0 + sin(anim_t * 6.0) * 5.0
			draw_arc(Vector2(0, -bh * 0.5), pulse, 0.0, TAU, 24, Color(1.0, 0.86, 0.28, 0.92), 2.6)
		elif float(info["use"]) > 0.0 and pwr <= 0.05:
			draw_string(font, Vector2(-34, -bh - 12), "未通電", HORIZONTAL_ALIGNMENT_CENTER, 68, 10, Color(1.0, 0.42, 0.36))
		elif bool(b["blocked"]):
			draw_string(font, Vector2(-28, -bh - 12), "満杯", HORIZONTAL_ALIGNMENT_CENTER, 56, 10, Color(1.0, 0.84, 0.32))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 4. Glowing Power Cables with Animated Pulses (snapped to per-building junction height!)
	for w in wires:
		var b1 := _by_uid(int(w[0])); var b2 := _by_uid(int(w[1]))
		if b1.is_empty() or b2.is_empty(): continue
		var id1 := String(b1["id"]); var id2 := String(b2["id"])
		var h1 := float(State.BLD[id1]["h"]) * (0.86 if id1 == "tesla" else 0.54)
		var h2 := float(State.BLD[id2]["h"]) * (0.86 if id2 == "tesla" else 0.54)
		var p1 := Vector2(b1["pos"]) + Vector2(b1["normal"]) * h1
		var p2 := Vector2(b2["pos"]) + Vector2(b2["normal"]) * h2
		var hot := float(b1["pwr_ratio"]) > 0.1 or float(b2["pwr_ratio"]) > 0.1
		draw_line(p1, p2, Color(0.06, 0.16, 0.28, 0.78), 5.5)
		draw_line(p1, p2, Color(0.32, 0.94, 1.0, 0.9) if hot else Color(0.50, 0.58, 0.70, 0.55), 2.2)
		if hot:
			draw_circle(p1.lerp(p2, fposmod(anim_t * 0.85, 1.0)), 4.0, Color(0.90, 1.0, 1.0))

	# 5. Physical Items Moving on Belts
	for it in belt_items:
		var ip := Vector2(it["from"]).lerp(Vector2(it["to"]), float(it["t"]))
		var ic := ArtReg.get_icon(String(it["item"]))
		if ic: draw_texture_rect(ic, Rect2(ip - Vector2(8, 8), Vector2(16, 16)), false)

	# 6. Blazing Mass Driver Launch Trails & Turret Lasers
	for tr in launch_trails:
		var p: Vector2 = tr["pos"]; var v: Vector2 = Vector2(tr["vel"]).normalized()
		draw_line(p, p - v * 150.0, Color(1.0, 0.76, 0.30, 0.82), 5.5)
		draw_line(p, p - v * 80.0, Color(1.0, 0.98, 0.88, 0.96), 2.5)
		if glow: draw_texture_rect(glow, Rect2(p.x - 42, p.y - 42, 84, 84), false, Color(1.0, 0.82, 0.36, 0.65))
	for bm in turret_beams:
		draw_line(bm["a"], bm["b"], Color(0.34, 0.94, 1.0, 0.88), 3.0)
