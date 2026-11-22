extends Node2D

# Multi-Planet Surface & Subterranean Industrial Grid:
# - Smart Recipe-Demand Logistics (Depot & Upstream send ONLY needed recipe ingredients in balanced ratios!)
# - 4-Connected Polar-Grid A* PCB Autorouter (Conveyors route around obstacles & NEVER cross/overlap; unroutable = blocked!)
# - Multi-Planet Placement (TERRA-I, LUNA, IGNIS-I, CRYO-IV, ASTRA-V), Building HP, Planetary Pollution & Laser Turret Defense!

signal depot_opened(uid: int)
signal building_inspected(uid: int)

const POWER_NODES: Array[String] = ["solar", "geothermal", "tesla", "battery"]
const LOGI_NODES: Array[String] = ["drill", "depot", "smelter", "assembler", "gantry_printer", "mass_driver"]
const WIRE_RANGE: float = 680.0
const CONVEYOR_MAX_RANGE: float = 1250.0
const CONVEYOR_SEG_LEN: float = 70.0
const CONVEYOR_FE_PER_SEG: int = 2
const TESLA_DOME_R: float = 480.0
const BATTERY_CAP_KJ: float = 18000.0
const DRILL_BUF: int = 6
const IN_CAP: int = 12
const OUT_CAP: int = 8
const DEPOT_CAP: int = 240
const RECIPES: Array[String] = ["circuit", "alloy", "plasma_cell", "cryo_rod", "sci_pack"]

var planet: SphericalPlanet = null
var player: Node2D = null
var swarm: Node2D = null

var buildings: Array[Dictionary] = []
var wires: Array[Array] = []
var conveyors: Array[Dictionary] = [] # {"from": uid, "to": uid, "body_id": String, "cost_fe": int, "filter": String, "cells": Array[Vector2i], "pts": PackedVector2Array, "local_pts": PackedVector2Array, "total_len": float}
var belt_items: Array[Dictionary] = []
var launch_trails: Array[Dictionary] = []
var turret_beams: Array[Dictionary] = []

var wire_pick_uid: int = -1
var conveyor_pick_uid: int = -1
var conveyor_fail_flash: Dictionary = {}
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
	buildings.clear(); wires.clear(); conveyors.clear(); belt_items.clear()
	launch_trails.clear(); turret_beams.clear()
	wire_pick_uid = -1; conveyor_pick_uid = -1; conveyor_fail_flash = {}
	selected_depot_uid = -1; salvage_armed_uid = -1; salvage_armed_ms = 0; next_uid = 1

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
		for k_v in d.keys():
			var k := String(k_v)
			if int(d[k]) > 0:
				var v := int(d[k]) - 1
				if v <= 0: d.erase(k)
				else: d[k] = v
				return k
		return ""
	if int(d.get(want, 0)) > 0:
		var v := int(d[want]) - 1
		if v <= 0: d.erase(want)
		else: d[want] = v
		return want
	return ""

# ------------------------------------------------------------------------------
# SMART DEMAND-DRIVEN RECIPE LOGISTICS (NEVER CLOGS WITH ONE INGREDIENT!)
# ------------------------------------------------------------------------------
func get_facility_recipe_needs(target_b: Dictionary) -> Dictionary:
	var bid := String(target_b.get("id", ""))
	match bid:
		"smelter":
			return {"fe": 2, "cu": 2, "si": 2}
		"assembler":
			var rec := String(target_b.get("recipe", "circuit"))
			if State.ASSEMBLER_RECIPES.has(rec):
				return State.ASSEMBLER_RECIPES[rec]["in"]
			return {"plate_fe": 1, "wire_cu": 1}
		"gantry_printer":
			return State.PRINTER_RECIPE["in"]
		"mass_driver":
			return {"probe_stock": 1}
		_:
			return {}

func _count_incoming(target_uid: int, item: String) -> int:
	var c := 0
	for bi in belt_items:
		if int(bi.get("target_uid", -1)) == target_uid and String(bi.get("item", "")) == item:
			c += 1
	return c

func _can_accept_item(target_b: Dictionary, item: String, count_inflight: bool = true) -> bool:
	var bid := String(target_b.get("id", ""))
	if bid == "depot":
		return _buf_sum(target_b["inv"]) < DEPOT_CAP
	var needs := get_facility_recipe_needs(target_b)
	if not needs.has(item):
		return false
	if _buf_sum(target_b["in_buf"]) >= IN_CAP:
		return false
	var req_q := maxi(1, int(needs[item]))
	# Per-ingredient cap guarantees NO single ingredient can fill IN_CAP (12) and starve other ingredients!
	var per_item_cap := maxi(4, req_q * 2) if bid == "smelter" else maxi(3, req_q * 2)
	var cur := int(target_b["in_buf"].get(item, 0))
	if count_inflight:
		cur += _count_incoming(int(target_b["uid"]), item)
	return cur < per_item_cap

func _pick_item_for_target(src_buf: Dictionary, target_b: Dictionary, filter_item: String) -> String:
	if src_buf.is_empty():
		return ""
	if filter_item != "auto":
		if int(src_buf.get(filter_item, 0)) > 0 and _can_accept_item(target_b, filter_item, true):
			return _buf_take(src_buf, filter_item)
		return ""

	var bid := String(target_b.get("id", ""))
	if bid == "depot":
		return _buf_take(src_buf, "auto") if _buf_sum(target_b["inv"]) < DEPOT_CAP else ""

	var needs := get_facility_recipe_needs(target_b)
	var t_uid := int(target_b["uid"])
	var best_item := ""
	var best_ratio := 1e9
	for req_k in needs.keys():
		var it := String(req_k)
		if int(src_buf.get(it, 0)) <= 0:
			continue
		if not _can_accept_item(target_b, it, true):
			continue
		var req_q := float(maxi(1, int(needs[it])))
		var cur_have := float(int(target_b["in_buf"].get(it, 0)) + _count_incoming(t_uid, it))
		var ratio := cur_have / req_q
		if ratio < best_ratio:
			best_ratio = ratio
			best_item = it
	if best_item != "":
		return _buf_take(src_buf, best_item)
	return ""

# ------------------------------------------------------------------------------
# 4-CONNECTED POLAR-GRID A* PCB AUTOROUTER FOR CONVEYORS
# ------------------------------------------------------------------------------
func _body_grid_meta(body_id: String) -> Dictionary:
	if not planet or body_id == "terra" or not planet.extra_vox.has(body_id):
		return {
			"cols": SphericalPlanet.COLS, "rows": SphericalPlanet.ROWS,
			"r_core": SphericalPlanet.R_CORE, "cell_h": SphericalPlanet.CELL_H,
			"da": SphericalPlanet.DA, "b_off": Vector2.ZERO,
		}
	var ev: Dictionary = planet.extra_vox[body_id]
	var b_off := Vector2(planet.bodies[body_id]["pos"]) - Vector2(planet.bodies["terra"]["pos"])
	return {
		"cols": SphericalPlanet.EX_COLS, "rows": SphericalPlanet.EX_ROWS,
		"r_core": float(ev["r_core"]), "cell_h": float(ev["cell_h"]),
		"da": SphericalPlanet.EX_DA, "b_off": b_off,
	}

func _cell_to_local_pt(meta: Dictionary, c: int, r: int) -> Vector2:
	var cols_n := int(meta["cols"])
	var wc := ((c % cols_n) + cols_n) % cols_n
	var a := (float(wc) + 0.5) * float(meta["da"])
	var rad := float(meta["r_core"]) + (float(r) + 0.5) * float(meta["cell_h"])
	return Vector2(cos(a) * rad, sin(a) * rad)

func autoroute_conveyor(b1: Dictionary, b2: Dictionary, ignore_conv_idx: int = -1) -> Dictionary:
	var bid1 := String(b1.get("body_id", "terra"))
	var bid2 := String(b2.get("body_id", "terra"))
	if bid1 != bid2:
		return {"ok": false, "reason": "異なる惑星間はコンベア接続できません"}
	var p1 := _conv_anchor(b1)
	var p2 := _conv_anchor(b2)
	var dist := p1.distance_to(p2)
	if dist > CONVEYOR_MAX_RANGE:
		return {"ok": false, "too_far": true, "reason": "距離オーバー（最大 %dpx）" % int(CONVEYOR_MAX_RANGE)}

	var meta := _body_grid_meta(bid1)
	var cols_n := int(meta["cols"])
	var rows_n := int(meta["rows"])
	var min_r := 6 if bid1 == "terra" else 4
	var max_r := rows_n + 18

	var s_cell := Vector2i(((int(b1["col"]) % cols_n) + cols_n) % cols_n, clampi(int(b1["row"]) + 1, min_r, max_r))
	var g_cell := Vector2i(((int(b2["col"]) % cols_n) + cols_n) % cols_n, clampi(int(b2["row"]) + 1, min_r, max_r))

	# Build obstacle map:
	# 1) ALL intermediate cells of existing conveyors on this planet are STRICTLY BLOCKED (zero crossing/overlap!)
	# 2) Direct duplicate edge is blocked
	# 3) Other buildings' core cells are blocked so traces route cleanly around machines!
	var blocked: Dictionary = {}
	var u1 := int(b1["uid"])
	var u2 := int(b2["uid"])
	for ci in range(conveyors.size()):
		if ci == ignore_conv_idx: continue
		var cv: Dictionary = conveyors[ci]
		if String(cv.get("body_id", "terra")) != bid1: continue
		var cells_cv: Array = cv.get("cells", [])
		var n_cv := cells_cv.size()
		for k in range(n_cv):
			var cc: Vector2i = cells_cv[k]
			# Block every intermediate cell; also block start/end if it doesn't belong to u1 or u2
			var is_end := (k == 0 or k == n_cv - 1)
			var shared_endpoint := (int(cv["from"]) == u1 or int(cv["from"]) == u2 or int(cv["to"]) == u1 or int(cv["to"]) == u2)
			if not is_end or not shared_endpoint:
				blocked[cc] = true

	for ob in buildings:
		var ouid := int(ob["uid"])
		if ouid == u1 or ouid == u2: continue
		if String(ob.get("body_id", "terra")) != bid1: continue
		var oc := ((int(ob["col"]) % cols_n) + cols_n) % cols_n
		var orow := int(ob["row"])
		for dc in range(-1, 2):
			var wc := ((oc + dc) % cols_n + cols_n) % cols_n
			blocked[Vector2i(wc, orow)] = true
			blocked[Vector2i(wc, orow + 1)] = true

	blocked.erase(s_cell)
	blocked.erase(g_cell)

	# 4-Connected Polar-Grid A* Search with Bend Penalty (PCB Autorouter!)
	var open_list: Array[Vector2i] = [s_cell]
	var in_open: Dictionary = {s_cell: true}
	var came_from: Dictionary = {}
	var dir_from: Dictionary = {s_cell: Vector2i.ZERO}
	var g_score: Dictionary = {s_cell: 0.0}
	var f_score: Dictionary = {s_cell: _polar_manhattan(s_cell, g_cell, cols_n)}
	var closed: Dictionary = {}
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var max_iters := 2200
	var iters := 0
	var found := false

	while not open_list.is_empty() and iters < max_iters:
		iters += 1
		var best_idx := 0
		var best_f := float(f_score.get(open_list[0], 1e9))
		for i in range(1, open_list.size()):
			var fi := float(f_score.get(open_list[i], 1e9))
			if fi < best_f:
				best_f = fi
				best_idx = i
		var cur: Vector2i = open_list[best_idx]
		open_list.remove_at(best_idx)
		in_open.erase(cur)
		if cur == g_cell:
			found = true
			break
		closed[cur] = true
		var prev_d: Vector2i = dir_from.get(cur, Vector2i.ZERO)
		var cur_g := float(g_score[cur])

		for d in dirs:
			var nr := cur.y + d.y
			if nr < min_r or nr > max_r: continue
			var nc := ((cur.x + d.x) % cols_n + cols_n) % cols_n
			var nxt := Vector2i(nc, nr)
			if closed.has(nxt) or blocked.has(nxt): continue
			# Prevent bounding too far away tangentially
			if _col_dist(nc, s_cell.x, cols_n) > 85 and _col_dist(nc, g_cell.x, cols_n) > 85:
				continue
			var step_cost := 1.0
			if prev_d != Vector2i.ZERO and prev_d != d:
				step_cost += 0.42 # Bend penalty for crisp PCB straight lines & 90-degree elbows!
			if nr > rows_n + 2:
				step_cost += float(nr - rows_n) * 0.06
			var ten_g := cur_g + step_cost
			if ten_g < float(g_score.get(nxt, 1e9)):
				came_from[nxt] = cur
				dir_from[nxt] = d
				g_score[nxt] = ten_g
				f_score[nxt] = ten_g + _polar_manhattan(nxt, g_cell, cols_n)
				if not in_open.has(nxt):
					open_list.append(nxt)
					in_open[nxt] = true

	if not found:
		return {"ok": false, "blocked_route": true, "reason": "自動配線エラー：他ラインと被らないルートが見つかりません！"}

	var cells: Array[Vector2i] = []
	var walk := g_cell
	while true:
		cells.push_front(walk)
		if walk == s_cell or not came_from.has(walk):
			break
		walk = came_from[walk]

	# Build local & HomeSystem polyline waypoints along the routed grid cells
	var b_off: Vector2 = meta["b_off"]
	var l_pts := PackedVector2Array()
	var w_pts := PackedVector2Array()
	var l_start := p1 - b_off
	var l_end := p2 - b_off
	l_pts.append(l_start); w_pts.append(p1)
	for i in range(cells.size()):
		var lp := _cell_to_local_pt(meta, cells[i].x, cells[i].y)
		if l_pts[l_pts.size() - 1].distance_to(lp) >= 6.0:
			l_pts.append(lp)
			w_pts.append(b_off + lp)
	if l_pts[l_pts.size() - 1].distance_to(l_end) >= 4.0:
		l_pts.append(l_end); w_pts.append(p2)
	else:
		l_pts[l_pts.size() - 1] = l_end; w_pts[w_pts.size() - 1] = p2

	var tot_len := 0.0
	for i in range(w_pts.size() - 1):
		tot_len += w_pts[i].distance_to(w_pts[i + 1])
	var cost_fe := maxi(1, int(ceil(tot_len / CONVEYOR_SEG_LEN))) * CONVEYOR_FE_PER_SEG
	return {
		"ok": true, "cells": cells, "local_pts": l_pts, "pts": w_pts,
		"total_len": maxf(40.0, tot_len), "cost_fe": cost_fe, "body_id": bid1,
	}

static func _col_dist(c1: int, c2: int, cols_n: int) -> int:
	var d := absi(c1 - c2)
	return mini(d, cols_n - d)

static func _polar_manhattan(a: Vector2i, b: Vector2i, cols_n: int) -> float:
	return float(_col_dist(a.x, b.x, cols_n) + absi(a.y - b.y))

static func _sample_polyline(pts: PackedVector2Array, t: float) -> Vector2:
	var n := pts.size()
	if n == 0: return Vector2.ZERO
	if n == 1 or t <= 0.0: return pts[0]
	if t >= 1.0: return pts[n - 1]
	var tot := 0.0
	for i in range(n - 1):
		tot += pts[i].distance_to(pts[i + 1])
	if tot <= 0.01: return pts[0]
	var target_d := clampf(t, 0.0, 1.0) * tot
	var acc := 0.0
	for i in range(n - 1):
		var seg := pts[i].distance_to(pts[i + 1])
		if acc + seg >= target_d and seg > 0.001:
			return pts[i].lerp(pts[i + 1], (target_d - acc) / seg)
		acc += seg
	return pts[n - 1]

# ------------------------------------------------------------------------------
# MULTI-PLANET PLACEMENT & FOUNDATION PROTECTION
# ------------------------------------------------------------------------------
func is_foundation_protected(col: int, row: int, body_id: String = "terra") -> bool:
	var cols_n := SphericalPlanet.COLS if body_id == "terra" else SphericalPlanet.EX_COLS
	var wc := ((col % cols_n) + cols_n) % cols_n
	for b in buildings:
		if String(b.get("body_id", "terra")) != body_id: continue
		var br := int(b["row"])
		if row < br - 2 or row >= br: continue
		var bc := int(b["col"])
		var span := maxi(2, int(ceil(float(State.BLD[b["id"]]["w"]) / 48.0)))
		var dc := absi(((wc - bc + cols_n / 2) % cols_n + cols_n) % cols_n - cols_n / 2)
		if dc <= span:
			return true
	return false

func _is_drill_node_occupied(dn_id: int) -> bool:
	for b in buildings:
		if int(b.get("drill_node_id", -1)) == dn_id:
			return true
	return false

func compute_snap_pose(terra_local_pos: Vector2, bid: String) -> Dictionary:
	if not planet or not State.BLD.has(bid):
		return {}
	var world_pos := planet.to_world_pos(terra_local_pos)
	var dom := planet.get_dominant_body(world_pos)
	var body_id := String(dom["id"])
	if body_id == "sun":
		body_id = "terra"
	if body_id == "astra" and not State.astra_liberated:
		var b_off_a := Vector2(planet.bodies["astra"]["pos"]) - planet.get_terra_pos()
		var rel_a := terra_local_pos - b_off_a
		var n_a := rel_a.normalized() if rel_a.length() > 1.0 else Vector2.UP
		return {
			"body_id": "astra", "col": 0, "row": SphericalPlanet.EX_ROWS - 1,
			"local_pos": n_a * float(dom["rad"]), "pos": b_off_a + n_a * float(dom["rad"]),
			"normal": n_a, "rot": n_a.angle() + PI * 0.5,
			"valid": false, "reason": "敵中枢拠点（艦隊で制圧後に設置可）",
		}

	if bid == "drill":
		var dn := planet.find_nearest_drill_node(terra_local_pos, 185.0)
		if not dn.is_empty() and not _is_drill_node_occupied(int(dn["id"])):
			return {
				"body_id": String(dn.get("body_id", "terra")),
				"col": int(dn["col"]), "row": int(dn["row"]),
				"local_pos": dn["local_pos"], "pos": dn["pos"],
				"normal": dn["normal"], "rot": float(dn["rot"]),
				"drill_node_id": int(dn["id"]), "ore_target": String(dn["ore"]),
				"valid": true, "reason": "",
			}
		var fb_pose := _snap_floor_on_body(body_id, terra_local_pos)
		fb_pose["valid"] = false
		fb_pose["reason"] = "硬質鉱床の上のみ設置可"
		return fb_pose

	var pose := _snap_floor_on_body(body_id, terra_local_pos)
	pose["valid"] = true
	pose["reason"] = ""
	return pose

func _snap_floor_on_body(body_id: String, terra_local_pos: Vector2) -> Dictionary:
	if body_id == "terra" or not planet.extra_vox.has(body_id):
		var cell := planet.world_to_cell(terra_local_pos)
		var c := cell.x; var r := cell.y
		if r >= SphericalPlanet.ROWS - 4 or not planet.is_solid(c, r):
			var floor_r := r
			while floor_r > 6 and not planet.is_solid(c, floor_r - 1): floor_r -= 1
			if floor_r <= 6: floor_r = planet.get_surface_row(c) + 1
			r = floor_r
		else:
			r = planet.get_surface_row(c) + 1
		return planet.get_body_pose_at("terra", c, r)

	var b_off := Vector2(planet.bodies[body_id]["pos"]) - planet.get_terra_pos()
	var rel := terra_local_pos - b_off
	var ecell := planet.extra_local_to_cell(body_id, rel)
	var ec := ecell.x; var er := ecell.y
	if er >= SphericalPlanet.EX_ROWS - 3 or not planet.is_extra_solid(body_id, ec, er):
		var fl_r := mini(SphericalPlanet.EX_ROWS - 1, er)
		while fl_r > 4 and not planet.is_extra_solid(body_id, ec, fl_r - 1): fl_r -= 1
		if fl_r <= 4: fl_r = planet.get_extra_surface_row(body_id, ec) + 1
		er = fl_r
	else:
		er = planet.get_extra_surface_row(body_id, ec) + 1
	return planet.get_body_pose_at(body_id, ec, er)

func _too_close_to_existing(pos: Vector2, bid: String) -> bool:
	var min_d := 34.0 if (bid == "belt" or bid == "lift") else 54.0
	for b in buildings:
		var d := Vector2(b["pos"]).distance_to(pos)
		var bd := 30.0 if (b["id"] == "belt" or b["id"] == "lift") else min_d
		if d < bd:
			return true
	return false

func try_place_at(bid: String, terra_local_pos: Vector2) -> bool:
	if not planet or not State.BLD.has(bid) or State.is_orbital_bld(bid): return false
	if not State.is_unlocked(bid):
		Sfx.play("error")
		State.add_log("先に【研究】で必要な技術を解放してください。", "warn")
		return false
	if State.get_stock(bid) <= 0:
		Sfx.play("error")
		State.add_log("%sの在庫がありません。【クラフト】で製造してください。" % State.BLD[bid]["name"], "warn")
		return false
	var pose := compute_snap_pose(terra_local_pos, bid)
	if pose.is_empty(): return false
	if not bool(pose.get("valid", true)):
		Sfx.play("error")
		State.add_log(String(pose.get("reason", "ここには設置できません")), "warn")
		return false
	if _too_close_to_existing(pose["pos"], bid):
		Sfx.play("error")
		State.add_log("既存の装置と近すぎます。少し離れた地面をタップしてください。", "warn")
		return false
	var info: Dictionary = State.BLD[bid]
	State.add_stock(bid, -1)
	if State.get_stock(bid) <= 0 and State.selected_tool == bid:
		State.selected_tool = "mine"

	var ore_t := String(pose.get("ore_target", "fe")) if bid == "drill" else ""
	var max_h := float(info.get("hp", 150.0))
	var b := {
		"uid": next_uid,
		"id": bid,
		"body_id": String(pose.get("body_id", "terra")),
		"col": int(pose["col"]),
		"row": int(pose["row"]),
		"local_pos": pose["local_pos"],
		"pos": pose["pos"],
		"normal": pose["normal"],
		"rot": float(pose["rot"]),
		"dir": State.build_dir,
		"drill_node_id": int(pose.get("drill_node_id", -1)),
		"hp": max_h,
		"max_hp": max_h,
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
	var extra := "（【配線】でテスラリレーへ接続しよう）" if (bid in POWER_NODES) else ("（%s鉱床へ設置！）" % State.res_name(ore_t) if bid == "drill" else "")
	State.add_log("設置完了: %s%s" % [info["name"], extra], "good")
	return true

func damage_building_uid(uid: int, dmg: float) -> bool:
	for i in range(buildings.size()):
		if int(buildings[i]["uid"]) == uid:
			var b: Dictionary = buildings[i]
			# 最初の惑星（テラ-I）の施設は聖域として保護（敵に攻撃されない）
			if String(b.get("body_id", "terra")) == "terra":
				return false
			b["hp"] = maxf(0.0, float(b.get("hp", 100.0)) - dmg)
			if planet:
				planet.spawn_sparks(Vector2(b["pos"]), Color(1.0, 0.36, 0.28), 6)
			if float(b["hp"]) <= 0.0:
				var bname := String(State.BLD[b["id"]]["name"])
				var bpos := Vector2(b["pos"])
				_remove_building_index(i, false)
				if planet:
					planet.spawn_sparks(bpos, Color(1.0, 0.45, 0.18), 22)
				Sfx.play("boom")
				State.add_log("敵襲撃により「%s」が破壊されました！レーザー砲台で防衛しよう！" % bname, "warn")
				return true
			return false
	return false

func _remove_building_index(bi: int, refund_to_player: bool) -> void:
	var b := buildings[bi]
	var dead_u := int(b["uid"])
	var bid := String(b["id"])
	if refund_to_player:
		for k in b["in_buf"].keys(): State.add_r(String(k), int(b["in_buf"][k]))
		for k in b["out_buf"].keys(): State.add_r(String(k), int(b["out_buf"][k]))
		for k in b["inv"].keys(): State.add_r(String(k), int(b["inv"][k]))
		State.add_stock(bid, 1)
	for wi in range(wires.size() - 1, -1, -1):
		if int(wires[wi][0]) == dead_u or int(wires[wi][1]) == dead_u:
			wires.remove_at(wi)
	for ci in range(conveyors.size() - 1, -1, -1):
		var cv: Dictionary = conveyors[ci]
		if int(cv["from"]) == dead_u or int(cv["to"]) == dead_u:
			if refund_to_player:
				State.add_r("fe", int(cv["cost_fe"]))
			conveyors.remove_at(ci)
	if wire_pick_uid == dead_u: wire_pick_uid = -1
	if conveyor_pick_uid == dead_u: conveyor_pick_uid = -1
	if selected_depot_uid == dead_u: selected_depot_uid = -1
	if salvage_armed_uid == dead_u: salvage_armed_uid = -1
	buildings.remove_at(bi)
	_solve_power(0.0)

func salvage_by_uid(uid: int) -> bool:
	var bi := -1
	for i in range(buildings.size()):
		if int(buildings[i]["uid"]) == uid:
			bi = i; break
	if bi < 0: return false
	var bname := String(State.BLD[buildings[bi]["id"]]["name"])
	_remove_building_index(bi, true)
	Sfx.play("pop")
	State.add_log("削除・回収完了: %s（所持リストに戻りました）" % bname, "info")
	return true

func try_salvage_at(terra_local_pos: Vector2) -> bool:
	var b := find_nearest(terra_local_pos, 78.0)
	if b.is_empty(): return false
	return salvage_by_uid(int(b["uid"]))

func try_double_tap_salvage(terra_local_pos: Vector2) -> bool:
	var b := find_nearest(terra_local_pos, 78.0)
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
# POWER WIRING & PCB AUTOROUTED CONVEYORS
# ------------------------------------------------------------------------------
func find_nearest(pos: Vector2, max_d: float = 110.0, ids: Array = []) -> Dictionary:
	var best: Dictionary = {}
	var bd := max_d
	for b in buildings:
		if not ids.is_empty() and not (b["id"] in ids): continue
		var d := Vector2(b["pos"]).distance_to(pos)
		if d < bd: bd = d; best = b
	return best

func find_nearest_on_body(pos: Vector2, body_id: String) -> Dictionary:
	if body_id == "terra":
		return {}
	var best: Dictionary = {}
	var bd := 1e9
	for b in buildings:
		var b_body := String(b.get("body_id", "terra"))
		if b_body == "terra":
			continue
		if body_id != "" and b_body != body_id:
			continue
		var d := Vector2(b["pos"]).distance_to(pos)
		if d < bd:
			bd = d; best = b
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
	State.add_log("電線接続: %s - %s" % [State.BLD[b1["id"]]["name"], State.BLD[b2["id"]]["name"]], "good")
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

func _conv_anchor(b: Dictionary) -> Vector2:
	var h := float(State.BLD[b["id"]]["h"]) * 0.42
	return Vector2(b["pos"]) + Vector2(b["normal"]) * h

func calc_conveyor_cost(p1: Vector2, p2: Vector2) -> int:
	var segs := maxi(1, int(ceil(p1.distance_to(p2) / CONVEYOR_SEG_LEN)))
	return segs * CONVEYOR_FE_PER_SEG

func toggle_conveyor(u_from: int, u_to: int) -> bool:
	if u_from <= 0 or u_to <= 0 or u_from == u_to: return false
	var b1 := _by_uid(u_from); var b2 := _by_uid(u_to)
	if b1.is_empty() or b2.is_empty(): return false
	if not (b1["id"] in LOGI_NODES) or not (b2["id"] in LOGI_NODES): return false

	for i in range(conveyors.size()):
		var cv: Dictionary = conveyors[i]
		if int(cv["from"]) == u_from and int(cv["to"]) == u_to:
			var ref_fe := int(cv["cost_fe"])
			State.add_r("fe", ref_fe)
			conveyors.remove_at(i)
			Sfx.play("pop")
			State.add_log("搬送ライン撤去: 鉄+%d 返却" % ref_fe, "info")
			return true

	var p1 := _conv_anchor(b1); var p2 := _conv_anchor(b2)
	var route := autoroute_conveyor(b1, b2)
	if not bool(route.get("ok", false)):
		Sfx.play("error")
		var too_far := bool(route.get("too_far", false))
		var blocked_r := bool(route.get("blocked_route", false))
		var need_est := calc_conveyor_cost(p1, p2)
		conveyor_fail_flash = {
			"p1": p1, "p2": p2, "ratio": 0.0, "need": need_est, "have": State.get_r("fe"),
			"too_far": too_far, "blocked_route": blocked_r, "reason": String(route.get("reason", "配線不可")),
			"life": 3.2,
		}
		State.add_log(String(route.get("reason", "搬送ラインを設置できません")), "warn")
		return false

	var need_fe := int(route["cost_fe"])
	var have_fe := State.get_r("fe")
	if have_fe < need_fe:
		Sfx.play("error")
		var ratio := clampf(float(have_fe) / maxf(1.0, float(need_fe)), 0.0, 1.0)
		conveyor_fail_flash = {
			"p1": p1, "p2": p2, "pts": route["pts"], "ratio": ratio,
			"need": need_fe, "have": have_fe, "too_far": false, "blocked_route": false,
			"life": 3.2,
		}
		State.add_log("鉄不足！自動配線ラインに鉄%d必要（あと鉄%d不足）" % [need_fe, need_fe - have_fe], "warn")
		return false

	State.spend({"fe": need_fe})
	conveyors.append({
		"from": u_from, "to": u_to,
		"body_id": String(route["body_id"]),
		"cost_fe": need_fe, "filter": "auto",
		"cells": route["cells"],
		"local_pts": route["local_pts"],
		"pts": route["pts"],
		"total_len": float(route["total_len"]),
	})
	conveyor_fail_flash = {}
	if planet:
		planet.spawn_sparks((p1 + p2) * 0.5, Color(1.0, 0.78, 0.28), 10)
	Sfx.play("wire")
	State.add_log("自動配線コンベア接続: %s → %s（鉄%d消費）" % [State.BLD[b1["id"]]["name"], State.BLD[b2["id"]]["name"], need_fe], "good")
	return true

func try_conveyor_at(pos: Vector2) -> bool:
	var ln := find_nearest(pos, 150.0, LOGI_NODES)
	if ln.is_empty():
		conveyor_pick_uid = -1
		return false
	var u1 := int(ln["uid"])
	if conveyor_pick_uid == -1:
		conveyor_pick_uid = u1
		Sfx.play("click")
		State.add_log("搬送元選択: %s → 送り先の施設をタップ" % State.BLD[ln["id"]]["name"], "info")
		return true
	elif conveyor_pick_uid == u1:
		conveyor_pick_uid = -1
		Sfx.play("click")
		return true
	else:
		var u0 := conveyor_pick_uid
		conveyor_pick_uid = -1
		return toggle_conveyor(u0, u1)

func start_conveyor_from(uid: int) -> void:
	var b := _by_uid(uid)
	if b.is_empty() or not (b["id"] in LOGI_NODES): return
	State.selected_tool = "conveyor"
	conveyor_pick_uid = uid
	wire_pick_uid = -1
	salvage_armed_uid = -1
	Sfx.play("click")
	State.add_log("搬送元選択: %s → 送り先の施設をタップ" % State.BLD[b["id"]]["name"], "info")

func handle_world_click(world_pos: Vector2) -> bool:
	var local_pos := to_local(world_pos)
	var tool := State.selected_tool
	if State.is_orbital_bld(tool):
		return false
	if tool == "wire":
		salvage_armed_uid = -1; conveyor_pick_uid = -1
		return try_wire_at(local_pos)
	if tool == "conveyor":
		salvage_armed_uid = -1; wire_pick_uid = -1
		return try_conveyor_at(local_pos)
	if tool == "salvage":
		wire_pick_uid = -1; conveyor_pick_uid = -1
		return try_double_tap_salvage(local_pos)
	if State.BLD.has(tool):
		salvage_armed_uid = -1; wire_pick_uid = -1; conveyor_pick_uid = -1
		return try_place_at(tool, local_pos)

	salvage_armed_uid = -1
	var b := find_nearest(local_pos, 78.0)
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

func interact_near_player(world_pos: Vector2) -> bool:
	var b := find_nearest(to_local(world_pos), 115.0)
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
# FACILITY INSPECTOR API
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
		var wpos := planet.to_world_pos(Vector2(b["pos"])) if planet else Vector2(b["pos"])
		live_gen = float(info["gen"]) * (planet.get_sunlight_world(wpos) if planet else 1.0)
	elif bid == "geothermal":
		live_gen = float(info["gen"])
	var conv_out: Array[String] = []
	for cv in conveyors:
		if int(cv["from"]) == uid:
			var ob := _by_uid(int(cv["to"]))
			if not ob.is_empty(): conv_out.append("→" + String(State.BLD[ob["id"]]["name"]))
	var cyc_t := 1.2 if bid == "drill" else (1.8 if bid == "smelter" else (2.1 if bid == "assembler" else (2.4 if bid == "gantry_printer" else 0.0)))
	var prog := clampf(float(b["timer"]) / cyc_t, 0.0, 1.0) if cyc_t > 0.0 else 0.0
	return {
		"uid": uid, "id": bid, "name": String(info["name"]), "tex": String(info["tex"]),
		"body_id": String(b.get("body_id", "terra")),
		"hp": float(b.get("hp", 150.0)), "max_hp": float(b.get("max_hp", 150.0)),
		"desc": String(info["desc"]), "is_power": (bid in POWER_NODES), "is_logi": (bid in LOGI_NODES),
		"gen": live_gen, "use": float(info["use"]), "prog": prog, "has_prog": (cyc_t > 0.0),
		"pwr_ratio": float(b["pwr_ratio"]), "wired": bool(b["wired"]), "links": links, "conv_out": conv_out,
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

func building_cycle_recipe(uid: int) -> String:
	var b := _by_uid(uid)
	if b.is_empty(): return ""
	var ri := (RECIPES.find(String(b["recipe"])) + 1) % RECIPES.size()
	b["recipe"] = RECIPES[ri]
	# Return any unconsumed input ingredients that don't belong to the new recipe back to player!
	var new_needs := get_facility_recipe_needs(b)
	var ib: Dictionary = b["in_buf"]
	for k in ib.keys().duplicate():
		var kn := String(k)
		if not new_needs.has(kn):
			State.add_r(kn, int(ib[kn]))
			ib.erase(kn)
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
	var needs := get_facility_recipe_needs(b)
	if needs.is_empty(): return false
	var fed := false
	for w_k in needs.keys():
		var w := String(w_k)
		if State.get_r(w) >= 1 and _can_accept_item(b, w, false):
			var g := mini(2, State.get_r(w))
			State.add_r(w, -g)
			_buf_add(b["in_buf"], w, g)
			fed = true
	if fed: Sfx.play("pop")
	return fed

# ------------------------------------------------------------------------------
# DEPOT OUTPUT FILTER INTERFACE
# ------------------------------------------------------------------------------
func get_depot_snap(uid: int) -> Dictionary:
	var d := _by_uid(uid)
	if d.is_empty(): return {}
	var out_links: Array[Dictionary] = []
	for ci in range(conveyors.size()):
		var cv: Dictionary = conveyors[ci]
		if int(cv["from"]) == uid:
			var tb := _by_uid(int(cv["to"]))
			if not tb.is_empty():
				out_links.append({
					"idx": ci, "to_uid": int(cv["to"]),
					"to_name": String(State.BLD[tb["id"]]["name"]),
					"filter": String(cv.get("filter", "auto")),
				})
	return {
		"uid": uid, "inv": d["inv"].duplicate(),
		"out_filters": d["out_filters"].duplicate(),
		"out_links": out_links,
		"total": _buf_sum(d["inv"]), "cap": DEPOT_CAP,
	}

func depot_cycle_link_filter(link_idx: int) -> String:
	if link_idx < 0 or link_idx >= conveyors.size(): return "auto"
	var cyc: Array[String] = ["auto", "fe", "cu", "si", "ti", "ignis_ore", "ice", "astra_shard", "plate_fe", "wire_cu", "wafer_si", "circuit", "alloy", "plasma_cell", "cryo_rod", "probe_stock", "none"]
	var cur := String(conveyors[link_idx].get("filter", "auto"))
	var nxt := cyc[(cyc.find(cur) + 1) % cyc.size()]
	conveyors[link_idx]["filter"] = nxt
	Sfx.play("click")
	return nxt

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
	for r in ["fe", "cu", "si", "ti", "ignis_ore", "ice", "astra_shard", "plate_fe", "wire_cu", "wafer_si", "alloy", "circuit"]:
		var a := State.get_r(r)
		if a > 0 and depot_transfer(uid, r, true, a): tot += a
	return tot

func depot_cycle_filter(uid: int, dir_key: String) -> String:
	var d := _by_uid(uid)
	if d.is_empty(): return "none"
	var cyc: Array[String] = ["none", "auto", "fe", "cu", "si", "ti", "plate_fe", "wire_cu", "wafer_si", "circuit", "alloy", "probe_stock"]
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
	var dyson_w := (240.0 if bool(State.megastructures["dyson"]) else 0.0) + State.orb_power_bonus_w

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
				var wpos := planet.to_world_pos(Vector2(nb["pos"])) if planet else Vector2(nb["pos"])
				gen += float(State.BLD["solar"]["gen"]) * (planet.get_sunlight_world(wpos) if planet else 1.0)
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
		for c in cons:
			c["pwr_ratio"] = maxf(float(c["pwr_ratio"]), ratio)
			# Auto-repair damaged buildings inside powered Tesla domes!
			if ratio > 0.5 and delta > 0.0 and float(c.get("hp", 100.0)) < float(c.get("max_hp", 100.0)):
				c["hp"] = minf(float(c["max_hp"]), float(c["hp"]) + 3.5 * delta)
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
	if not _can_accept_item(target, item, false):
		return false
	_buf_add(target["in_buf"], item, 1)
	return true

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
	var it := _pick_item_for_target(buf, nb, filter_item)
	if it == "": return false
	var ok := _deliver(nb, it)
	if not ok: _buf_add(buf, it, 1)
	return ok

func collect_near_player(world_pos: Vector2, rad: float = 82.0) -> int:
	var pos := to_local(world_pos)
	var got := 0
	for i in range(belt_items.size() - 1, -1, -1):
		var bi: Dictionary = belt_items[i]
		var p: Vector2 = _sample_polyline(bi["pts"], float(bi["t"])) if bi.has("pts") else Vector2(bi["from"]).lerp(Vector2(bi["to"]), float(bi["t"]))
		if p.distance_to(pos) <= rad:
			State.add_r(String(bi["item"]), 1)
			belt_items.remove_at(i); got += 1
	for b in buildings:
		if b["id"] in ["drill", "smelter", "assembler", "gantry_printer"] and not b["out_buf"].is_empty():
			if Vector2(b["pos"]).distance_to(pos) <= 68.0:
				got += _collect_out(b)
	if got > 0: Sfx.play("pop")
	return got

func service_player(world_pos: Vector2, delta: float) -> void:
	var pos := to_local(world_pos)
	var near_pad := false
	for b in buildings:
		if (b["id"] in POWER_NODES or b["id"] == "depot") and float(b["pwr_ratio"]) > 0.15:
			if Vector2(b["pos"]).distance_to(pos) <= 260.0: near_pad = true; break
	if near_pad:
		State.ion_bat = minf(State.max_ion_bat, State.ion_bat + 36.0 * delta)
		State.fuel = minf(State.max_fuel, State.fuel + 28.0 * delta)
		State.hp = minf(State.max_hp, State.hp + 12.0 * delta)
	else:
		var sun := planet.get_sunlight_world(world_pos) if planet else 0.6
		State.ion_bat = minf(State.max_ion_bat, State.ion_bat + (6.0 + 9.0 * sun) * delta)

func _sync_multiplanet_positions() -> void:
	if not planet: return
	var terra_p := planet.get_terra_pos()
	for b in buildings:
		var bid_p := String(b.get("body_id", "terra"))
		if bid_p == "terra" or not planet.bodies.has(bid_p):
			b["pos"] = b["local_pos"]
		else:
			var b_off := Vector2(planet.bodies[bid_p]["pos"]) - terra_p
			b["pos"] = b_off + Vector2(b["local_pos"])

	for cv in conveyors:
		var bid_c := String(cv.get("body_id", "terra"))
		var l_pts: PackedVector2Array = cv["local_pts"]
		if bid_c == "terra" or not planet.bodies.has(bid_c):
			cv["pts"] = l_pts
		else:
			var b_off := Vector2(planet.bodies[bid_c]["pos"]) - terra_p
			var w_pts := PackedVector2Array()
			w_pts.resize(l_pts.size())
			for i in range(l_pts.size()):
				w_pts[i] = b_off + l_pts[i]
			cv["pts"] = w_pts

func _process(delta: float) -> void:
	anim_t += delta
	_sync_multiplanet_positions()
	_solve_power(delta)
	var spd := 1.0 + float(State.attached_drones) * 0.16
	var act_p := 0; var tot_p := 0

	# Slowly decay planetary pollution when idle
	for p_bid in ["luna", "ignis", "cryo", "astra"]:
		State.add_pollution(p_bid, -0.05 * delta)

	for b in buildings:
		var bid := String(b["id"])
		var body_id := String(b.get("body_id", "terra"))
		var pwr := float(b["pwr_ratio"])
		b["blocked"] = false
		if pwr > 0.05:
			b["timer"] = float(b["timer"]) + delta * spd * pwr
			b["smoke_t"] = float(b["smoke_t"]) + delta * pwr
			# Non-starter planets accumulate environmental pollution when factories run!
			if body_id != "terra" and bid in ["drill", "smelter", "assembler", "gantry_printer", "mass_driver"]:
				var p_rate := 0.75 if bid == "smelter" else (0.55 if bid == "drill" else 0.65)
				State.add_pollution(body_id, p_rate * pwr * delta)
		b["push_t"] = float(b["push_t"]) + delta
		var n: Vector2 = b["normal"]
		var tang := Vector2(-n.y, n.x)

		if float(b["push_t"]) >= 0.42:
			b["push_t"] = 0.0
			# 1) Smart Demand-Driven Autorouted Conveyors!
			var buid := int(b["uid"])
			var src_buf: Dictionary = b["inv"] if bid == "depot" else b["out_buf"]
			if not src_buf.is_empty():
				for cv in conveyors:
					if int(cv["from"]) != buid: continue
					var flt := String(cv.get("filter", "auto"))
					if flt == "none": continue
					var tb := _by_uid(int(cv["to"]))
					if tb.is_empty(): continue
					var it_c := _pick_item_for_target(src_buf, tb, flt)
					if it_c == "": continue
					var pts_c: PackedVector2Array = cv["pts"]
					belt_items.append({
						"from": pts_c[0], "to": pts_c[pts_c.size() - 1],
						"pts": pts_c,
						"from_uid": buid, "target_uid": int(tb["uid"]),
						"item": it_c, "t": 0.02, "dist": maxf(40.0, float(cv.get("total_len", 100.0))), "free": true,
					})
			# 2) Direct adjacent transfer
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
				var ib_s: Dictionary = b["in_buf"]
				var has_ore := int(ib_s.get("fe", 0)) >= 2 or int(ib_s.get("cu", 0)) >= 2 or int(ib_s.get("si", 0)) >= 2
				if not has_ore:
					b["timer"] = 0.0
					continue
				if planet and float(b["smoke_t"]) >= 0.55:
					b["smoke_t"] = 0.0; planet.spawn_smoke(Vector2(b["pos"]) + n * 76.0 - tang * 16.0, n, Color(0.76, 0.80, 0.88, 0.44))
				if float(b["timer"]) >= 1.8:
					b["timer"] = 0.0
					# Round-robin / least-output smelting so Fe/Cu/Si all get smelted fairly!
					var cands: Array[Array] = []
					if int(ib_s.get("fe", 0)) >= 2: cands.append(["fe", "plate_fe", int(b["out_buf"].get("plate_fe", 0))])
					if int(ib_s.get("cu", 0)) >= 2: cands.append(["cu", "wire_cu", int(b["out_buf"].get("wire_cu", 0))])
					if int(ib_s.get("si", 0)) >= 2: cands.append(["si", "wafer_si", int(b["out_buf"].get("wafer_si", 0))])
					if not cands.is_empty():
						cands.sort_custom(func(a: Array, c: Array) -> bool: return int(a[2]) < int(c[2]))
						var pick_o := String(cands[0][0])
						var pick_p := String(cands[0][1])
						ib_s[pick_o] = int(ib_s[pick_o]) - 2
						if int(ib_s[pick_o]) <= 0: ib_s.erase(pick_o)
						_buf_add(b["out_buf"], pick_p, 1)
			"assembler":
				if pwr <= 0.05: continue
				var rec := String(b["recipe"])
				var rdata: Dictionary = State.ASSEMBLER_RECIPES.get(rec, State.ASSEMBLER_RECIPES["circuit"])
				var req_in: Dictionary = rdata["in"]
				var ib: Dictionary = b["in_buf"]
				var has_all := true
				for rk in req_in.keys():
					if int(ib.get(String(rk), 0)) < int(req_in[rk]):
						has_all = false; break
				if not has_all:
					b["timer"] = 0.0
					continue
				if rec != "sci_pack" and _buf_sum(b["out_buf"]) >= OUT_CAP:
					b["blocked"] = true; continue
				if float(b["timer"]) >= float(rdata["time"]):
					b["timer"] = 0.0
					for rk in req_in.keys():
						var rks := String(rk)
						ib[rks] = int(ib[rks]) - int(req_in[rk])
						if int(ib[rks]) <= 0: ib.erase(rks)
					var out_id := String(rdata["out"])
					var out_q := int(rdata["qty"])
					if out_id == "sci_pack":
						State.add_r("sci_pack", out_q)
						if planet:
							planet.spawn_popup(Vector2(b["pos"]), "+%d 研究ポイント" % out_q, Color(0.38, 1.0, 0.78))
					else:
						_buf_add(b["out_buf"], out_id, out_q)
			"gantry_printer":
				tot_p += 1
				if pwr <= 0.05: continue
				act_p += 1
				if _buf_sum(b["out_buf"]) >= OUT_CAP: b["blocked"] = true; continue
				if float(b["timer"]) >= 2.4:
					b["timer"] = 0.0
					var ib: Dictionary = b["in_buf"]
					if int(ib.get("plate_fe", 0)) >= 2 and int(ib.get("circuit", 0)) >= 1:
						ib["plate_fe"] = int(ib["plate_fe"]) - 2
						ib["circuit"] = int(ib["circuit"]) - 1
						if int(ib["plate_fe"]) <= 0: ib.erase("plate_fe")
						if int(ib["circuit"]) <= 0: ib.erase("circuit")
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
				if float(b["timer"]) >= 0.55 and swarm.has_method("find_nearest_raider"):
					var tgt: Vector2 = swarm.find_nearest_raider(b["pos"], 1250.0)
					if tgt != Vector2.ZERO:
						b["timer"] = 0.0; swarm.damage_raider_near(tgt, 34.0)
						turret_beams.append({"a": Vector2(b["pos"]) + n * 34.0, "b": tgt, "life": 0.16})
						Sfx.play("laser")

	State.active_printers = act_p; State.total_printers = tot_p

	for i in range(belt_items.size() - 1, -1, -1):
		var it := belt_items[i]
		var tb := _by_uid(int(it["target_uid"]))
		if tb.is_empty(): belt_items.remove_at(i); continue
		var dist := maxf(40.0, float(it.get("dist", 100.0)))
		it["t"] = minf(1.02, float(it["t"]) + (220.0 / dist) * delta)
		if float(it["t"]) >= 1.0:
			if _deliver(tb, String(it["item"])):
				belt_items.remove_at(i)
			else:
				var fb := _by_uid(int(it.get("from_uid", -1)))
				if not fb.is_empty():
					var fbuf: Dictionary = fb["inv"] if String(fb["id"]) == "depot" else fb["out_buf"]
					_buf_add(fbuf, String(it["item"]), 1)
				belt_items.remove_at(i)

	if not conveyor_fail_flash.is_empty():
		conveyor_fail_flash["life"] = float(conveyor_fail_flash["life"]) - delta
		if float(conveyor_fail_flash["life"]) <= 0.0:
			conveyor_fail_flash = {}

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
	var batch := 14 if State.swarm_fleet >= 30 else 8
	State.swarm_fleet = mini(State.SWARM_MAX, State.swarm_fleet + batch)
	if swarm and swarm.has_method("spawn_launched"):
		swarm.spawn_launched(muzzle, dir, batch)
	Sfx.play("launch")

# ------------------------------------------------------------------------------
# RENDERING: BUILDINGS, HP BARS, WIRES & PCB-AUTOROUTED CONVEYOR TRACES
# ------------------------------------------------------------------------------
func _draw() -> void:
	if not planet: return
	var glow := ArtReg.get_t("glow")
	var font := ArtReg.get_font()
	var fi := int(floor(anim_t * 10.0)) % 4

	var hover_local := to_local(hover_world)
	if show_ghost and State.BLD.has(State.selected_tool) and not State.is_orbital_bld(State.selected_tool) and State.get_stock(State.selected_tool) > 0:
		var pose := compute_snap_pose(hover_local, State.selected_tool)
		if not pose.is_empty():
			var info: Dictionary = State.BLD[State.selected_tool]
			var pose_ok := bool(pose.get("valid", true))
			var ok := pose_ok and not _too_close_to_existing(pose["pos"], State.selected_tool)
			var gcol := Color(0.32, 0.98, 0.72, 0.78) if ok else Color(1.0, 0.30, 0.28, 0.80)
			draw_set_transform(pose["pos"], float(pose["rot"]), Vector2.ONE)
			var t := ArtReg.get_t(String(info["tex"]))
			var bw := float(info["w"]); var bh := float(info["h"])
			if t: draw_texture_rect(t, Rect2(-bw * 0.5, -bh, bw, bh), false, gcol)
			draw_rect(Rect2(-bw * 0.5, -bh, bw, bh), gcol, false, 2.2)
			var glbl := ("ここへ設置" if State.selected_tool != "drill" else "鉱床へ設置OK") if ok else (String(pose.get("reason", "")) if not pose_ok else "近すぎます")
			draw_string(font, Vector2(-90, -bh - 10), glbl, HORIZONTAL_ALIGNMENT_CENTER, 180, 12, gcol)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 2. Tesla Power Domes
	for b in buildings:
		if b["id"] != "tesla": continue
		var act := float(b["pwr_ratio"]) > 0.1
		draw_circle(b["pos"], TESLA_DOME_R, Color(0.22, 0.84, 1.0, 0.07) if act else Color(0.6, 0.25, 0.25, 0.04))
		draw_arc(b["pos"], TESLA_DOME_R, 0.0, TAU, 64, Color(0.34, 0.92, 1.0, 0.45) if act else Color(0.85, 0.35, 0.35, 0.28), 2.0)

	# 3. Buildings + Durability HP Bars
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
		if bid != "belt" and bid != "lift":
			draw_rect(Rect2(-bw * 0.48, -2, bw * 0.96, 10), Color(0.16, 0.20, 0.26, 0.95))
			draw_rect(Rect2(-bw * 0.48, -2, bw * 0.96, 2), Color(0.45, 0.52, 0.62))

		var t := ArtReg.get_t(String(info["tex"]))
		var y_off := 16.0 if bid == "drill" else 0.0
		if t: draw_texture_rect(t, Rect2(-bw * 0.5, -bh + y_off, bw, bh), false)

		# Durability HP Bar (shown when damaged < 99%!)
		var cur_hp := float(b.get("hp", 150.0))
		var max_h := maxf(1.0, float(b.get("max_hp", 150.0)))
		if cur_hp < max_h * 0.99:
			var hf := clampf(cur_hp / max_h, 0.0, 1.0)
			draw_rect(Rect2(-26, -bh - 20, 52, 6), Color(0.12, 0.06, 0.08, 0.94))
			draw_rect(Rect2(-25, -bh - 19, 50 * hf, 4), Color(0.32, 0.96, 0.58) if hf > 0.45 else Color(1.0, 0.30, 0.28))

		if bid == "battery":
			var pct := clampf(float(b["battery_kj"]) / BATTERY_CAP_KJ, 0.0, 1.0)
			draw_rect(Rect2(-24, -bh - 10, 48, 6), Color(0.08, 0.12, 0.18, 0.92))
			draw_rect(Rect2(-23, -bh - 9, 46 * pct, 4), Color(0.28, 0.96, 0.66))
		elif bid == "assembler":
			draw_string(font, Vector2(-46, -bh - 10), State.res_name(String(b["recipe"])), HORIZONTAL_ALIGNMENT_CENTER, 92, 11, Color(0.46, 0.96, 1.0))

		if int(b["uid"]) == salvage_armed_uid:
			var pulse_d := 38.0 + sin(anim_t * 9.0) * 5.0
			draw_arc(Vector2(0, -bh * 0.5), pulse_d, 0.0, TAU, 24, Color(1.0, 0.28, 0.28, 0.96), 3.2)
			draw_string(font, Vector2(-68, -bh - 18), "もう一度タップで削除！", HORIZONTAL_ALIGNMENT_CENTER, 136, 11, Color(1.0, 0.42, 0.38))
		elif int(b["uid"]) == wire_pick_uid:
			draw_arc(Vector2(0, -bh * 0.5), 36.0, 0.0, TAU, 24, Color(0.45, 1.0, 1.0), 2.8)
		elif int(b["uid"]) == conveyor_pick_uid:
			draw_arc(Vector2(0, -bh * 0.5), 38.0, 0.0, TAU, 24, Color(1.0, 0.80, 0.28), 3.0)
			draw_string(font, Vector2(-58, -bh - 16), "搬送元 選択中", HORIZONTAL_ALIGNMENT_CENTER, 116, 11, Color(1.0, 0.86, 0.36))
		elif State.tut_enabled and State.tut_step == 5 and (bid in POWER_NODES) and not bool(b["wired"]):
			var pulse := 34.0 + sin(anim_t * 6.0) * 5.0
			draw_arc(Vector2(0, -bh * 0.5), pulse, 0.0, TAU, 24, Color(1.0, 0.86, 0.28, 0.92), 2.6)
		elif float(info["use"]) > 0.0 and pwr <= 0.05:
			draw_string(font, Vector2(-34, -bh - 12), "未通電", HORIZONTAL_ALIGNMENT_CENTER, 68, 11, Color(1.0, 0.42, 0.36))
		elif bool(b["blocked"]):
			draw_string(font, Vector2(-28, -bh - 12), "満杯", HORIZONTAL_ALIGNMENT_CENTER, 56, 11, Color(1.0, 0.84, 0.32))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 4. Glowing Power Cables
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

	# 4b. PCB-Autorouted Non-Overlapping Grid Conveyor Tracks!
	for cv in conveyors:
		var pts: PackedVector2Array = cv["pts"]
		if pts.size() < 2: continue
		draw_polyline(pts, Color(0.09, 0.13, 0.20, 0.95), 11.0)
		draw_polyline(pts, Color(0.28, 0.54, 0.72, 0.92), 6.0)
		draw_polyline(pts, Color(0.14, 0.22, 0.32, 0.96), 3.4)
		# Solder-pad / PCB via nodes at start, corners, and end
		draw_circle(pts[0], 5.5, Color(1.0, 0.80, 0.28))
		draw_circle(pts[pts.size() - 1], 5.5, Color(0.38, 0.98, 0.76))
		# Animated directional flow pulse dots along the routed PCB trace!
		var tot_l := maxf(40.0, float(cv.get("total_len", 100.0)))
		var n_dots := maxi(2, int(tot_l / 48.0))
		for di in range(n_dots):
			var ft := fposmod(float(di) / float(n_dots) + anim_t * (68.0 / tot_l), 1.0)
			var dp := _sample_polyline(pts, ft)
			draw_circle(dp, 2.8, Color(1.0, 0.82, 0.30, 0.92))

	# 4c. Live Autorouter Conveyor Preview (Shows exact A* routed trace OR red unroutable error!)
	if State.selected_tool == "conveyor" and conveyor_pick_uid != -1:
		var src_b := _by_uid(conveyor_pick_uid)
		if not src_b.is_empty():
			var p1 := _conv_anchor(src_b)
			var snap_t := find_nearest(hover_local, 130.0, LOGI_NODES)
			if not snap_t.is_empty() and int(snap_t["uid"]) != conveyor_pick_uid:
				var route := autoroute_conveyor(src_b, snap_t)
				var p2 := _conv_anchor(snap_t)
				if not bool(route.get("ok", false)):
					_draw_split_conveyor_preview(p1, p2, PackedVector2Array([p1, p2]), 0.0, 0, State.get_r("fe"),
						bool(route.get("too_far", false)), true, String(route.get("reason", "配線不可")), font)
				else:
					var need_fe := int(route["cost_fe"])
					var have_fe := State.get_r("fe")
					var ratio := clampf(float(have_fe) / maxf(1.0, float(need_fe)), 0.0, 1.0)
					_draw_split_conveyor_preview(p1, p2, route["pts"], ratio, need_fe, have_fe, false, false, "", font)
			elif p1.distance_to(hover_local) > 20.0:
				var dist := p1.distance_to(hover_local)
				var need_fe := calc_conveyor_cost(p1, hover_local)
				var have_fe := State.get_r("fe")
				var too_far := dist > CONVEYOR_MAX_RANGE
				var ratio := clampf((CONVEYOR_MAX_RANGE / dist) if too_far else (float(have_fe) / maxf(1.0, float(need_fe))), 0.0, 1.0)
				_draw_split_conveyor_preview(p1, hover_local, PackedVector2Array([p1, hover_local]), ratio, need_fe, have_fe, too_far, false, "", font)

	if not conveyor_fail_flash.is_empty():
		var f_pts: PackedVector2Array = conveyor_fail_flash.get("pts", PackedVector2Array([Vector2(conveyor_fail_flash["p1"]), Vector2(conveyor_fail_flash["p2"])]))
		_draw_split_conveyor_preview(
			Vector2(conveyor_fail_flash["p1"]), Vector2(conveyor_fail_flash["p2"]), f_pts,
			float(conveyor_fail_flash["ratio"]), int(conveyor_fail_flash["need"]),
			int(conveyor_fail_flash["have"]), bool(conveyor_fail_flash.get("too_far", false)),
			bool(conveyor_fail_flash.get("blocked_route", false)),
			String(conveyor_fail_flash.get("reason", "")), font
		)

	# 5. Physical Items Moving Along Autorouted PCB Conveyor Traces
	for it in belt_items:
		var ip: Vector2 = _sample_polyline(it["pts"], float(it["t"])) if it.has("pts") else Vector2(it["from"]).lerp(Vector2(it["to"]), float(it["t"]))
		var ic := ArtReg.get_icon(String(it["item"]))
		if ic: draw_texture_rect(ic, Rect2(ip - Vector2(8, 8), Vector2(16, 16)), false)

	# 6. Railgun Launch Trails & Turret Lasers
	for tr in launch_trails:
		var p: Vector2 = tr["pos"]; var v: Vector2 = Vector2(tr["vel"]).normalized()
		draw_line(p, p - v * 150.0, Color(1.0, 0.76, 0.30, 0.82), 5.5)
		draw_line(p, p - v * 80.0, Color(1.0, 0.98, 0.88, 0.96), 2.5)
		if glow: draw_texture_rect(glow, Rect2(p.x - 42, p.y - 42, 84, 84), false, Color(1.0, 0.82, 0.36, 0.65))
	for bm in turret_beams:
		draw_line(bm["a"], bm["b"], Color(0.34, 0.94, 1.0, 0.92), 3.4)

func _draw_split_conveyor_preview(p1: Vector2, p2: Vector2, pts: PackedVector2Array, ratio: float, need_fe: int, have_fe: int, too_far: bool, blocked_route: bool, reason: String, font: Font) -> void:
	var ok := (not too_far) and (not blocked_route) and (have_fe >= need_fe)
	var mid := _sample_polyline(pts, 0.5) if pts.size() >= 2 else p1.lerp(p2, 0.5)
	if ok:
		if pts.size() >= 2:
			draw_polyline(pts, Color(0.06, 0.22, 0.20, 0.85), 10.0)
			draw_polyline(pts, Color(0.34, 0.98, 0.76, 0.96), 4.2)
		var lbl := "自動配線OK: 鉄%d消費" % need_fe
		draw_rect(Rect2(mid.x - 102, mid.y - 28, 204, 24), Color(0.04, 0.14, 0.16, 0.94))
		draw_rect(Rect2(mid.x - 102, mid.y - 28, 204, 24), Color(0.36, 0.98, 0.76), false, 1.5)
		draw_string(font, Vector2(mid.x - 102, mid.y - 11), lbl, HORIZONTAL_ALIGNMENT_CENTER, 204, 12, Color(0.88, 1.0, 0.94))
	else:
		var pulse_r := 0.72 + 0.28 * sin(anim_t * 10.0)
		var split_p := p1.lerp(p2, clampf(ratio, 0.0, 1.0))
		if not blocked_route and ratio > 0.02:
			draw_line(p1, split_p, Color(0.34, 0.92, 1.0, 0.90), 4.0)
		draw_line(split_p if not blocked_route else p1, p2, Color(1.0, 0.22, 0.22, pulse_r), 5.5)
		var lbl := reason if (blocked_route and reason != "") else ("距離オーバー！（最大 %dpx）" % int(CONVEYOR_MAX_RANGE) if too_far else ("鉄不足！あと 鉄%d 必要（%d/%d）" % [need_fe - have_fe, have_fe, need_fe]))
		draw_rect(Rect2(mid.x - 156, mid.y - 30, 312, 26), Color(0.24, 0.04, 0.06, 0.95))
		draw_rect(Rect2(mid.x - 156, mid.y - 30, 312, 26), Color(1.0, 0.30, 0.28), false, 1.6)
		draw_string(font, Vector2(mid.x - 156, mid.y - 12), lbl, HORIZONTAL_ALIGNMENT_CENTER, 312, 12, Color(1.0, 0.88, 0.86))
