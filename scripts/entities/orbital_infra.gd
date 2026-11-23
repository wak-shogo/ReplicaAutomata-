extends Node2D

# World-Space Heliocentric Celestials Renderer + Analytical Keplerian Orbit Prediction +
# Co-Orbital Infrastructure System:
#   - orb_power     : Orbital Power Satellite (+120W beamed to ground Tesla grid & orbital modules)
#   - orb_laser     : Orbital Mining Laser (mines surface veins below -> launches physical gravity-falling packets!)
#   - orb_collector : Orbital Collector Module (catches rising/arcing packets via tractor field -> transfers to station)
#   - orb_station   : Orbital Craft Station (crafts quantum_core / antimatter / dyson_panel / probe_stock x4 in orbit!)

signal orbital_inspected(uid: int)

const ORB_RECIPES: Array[String] = ["quantum_core", "dyson_panel", "antimatter", "probe_stock", "sci_pack"]

var planet: SphericalPlanet = null
var player: Node2D = null
var grid: Node2D = null

var modules: Array[Dictionary] = [] # Deployed orbital modules on exact Keplerian rails
var packets: Array[Dictionary] = [] # Physical gravity-affected mined mineral packets!
var cargo_beams: Array[Dictionary] = []
var next_oid: int = 1
var anim_t: float = 0.0
var salvage_armed_oid: int = -1
var salvage_armed_ms: int = 0

func _ready() -> void:
	z_index = 18
	process_physics_priority = -5

func clear_all() -> void:
	modules.clear()
	packets.clear()
	cargo_beams.clear()
	next_oid = 1
	salvage_armed_oid = -1
	State.orb_power_bonus_w = 0.0

func _by_oid(oid: int) -> Dictionary:
	for m in modules:
		if int(m["uid"]) == oid:
			return m
	return {}

func _buf_sum(d: Dictionary) -> int:
	var s := 0
	for v in d.values(): s += int(v)
	return s

func _buf_add(d: Dictionary, k: String, q: int) -> void:
	d[k] = int(d.get(k, 0)) + q

func find_nearest_module(world_pos: Vector2, max_d: float = 95.0) -> Dictionary:
	var best: Dictionary = {}
	var bd := max_d
	for m in modules:
		var d := Vector2(m["pos"]).distance_to(world_pos)
		if d < bd:
			bd = d
			best = m
	return best

func deploy_on_player_orbit(bid: String) -> bool:
	if not planet or not player or not State.is_orbital_bld(bid):
		return false
	if not State.is_unlocked(bid):
		Sfx.play("error")
		State.add_log("先に【研究】で必要な技術を解放してください。", "warn")
		return false
	if State.get_stock(bid) <= 0:
		Sfx.play("error")
		State.add_log("%sの在庫がありません。【クラフト】で製造してください。" % State.BLD[bid]["name"], "warn")
		return false
	var orb: Dictionary = player.get_deploy_orbit()
	if orb.is_empty():
		Sfx.play("error")
		State.add_log("安定した周回軌道に進入してから軌道施設を配置してください！", "warn")
		return false

	# Slight phase offset if another module is right on top of player's current phase M
	var m_phase := float(orb["M"])
	for ex in modules:
		if String(ex["orb"]["body_id"]) == String(orb["body_id"]):
			if absf(wrapf(float(ex["orb"]["M"]) - m_phase, -PI, PI)) < 0.045:
				m_phase = wrapf(m_phase + 0.065 * float(orb["dir_sign"]), -PI, PI)
	orb["M"] = m_phase
	var st := Kepler.eval_state(orb, m_phase)
	var b := planet.get_body(String(orb["body_id"]))
	var wpos := Vector2(b["pos"]) + Vector2(st["pos_rel"])

	State.add_stock(bid, -1)
	if State.get_stock(bid) <= 0 and State.selected_tool == bid:
		State.selected_tool = "mine"

	var mod := {
		"uid": next_oid,
		"id": bid,
		"orb": orb,
		"pos": wpos,
		"vel": Vector2(st["vel_rel"]),
		"powered": false,
		"pwr_ratio": 0.0,
		"timer": 0.0,
		"laser_target": Vector2.ZERO,
		"laser_ore": "",
		"power_beam_to": Vector2.ZERO,
		"recipe": "quantum_core",
		"in_buf": {},
		"out_buf": {},
		"collected": 0,
	}
	next_oid += 1
	modules.append(mod)
	planet.spawn_sparks_world(wpos, Color(0.42, 0.96, 1.0), 14)
	Sfx.play("build")
	State.note_building_placed(bid)
	State.add_log("同一軌道へ配置完了: %s！" % State.BLD[bid]["name"], "good")
	return true

func salvage_module(oid: int) -> bool:
	for i in range(modules.size()):
		if int(modules[i]["uid"]) == oid:
			var m := modules[i]
			var bid := String(m["id"])
			for k in m["in_buf"].keys(): State.add_r(String(k), int(m["in_buf"][k]))
			for k in m["out_buf"].keys(): State.add_r(String(k), int(m["out_buf"][k]))
			State.add_stock(bid, 1)
			modules.remove_at(i)
			Sfx.play("pop")
			State.add_log("軌道施設を回収: %s" % State.BLD[bid]["name"], "info")
			return true
	return false

func handle_world_click(world_pos: Vector2) -> bool:
	var tool := State.selected_tool
	if State.is_orbital_bld(tool):
		return deploy_on_player_orbit(tool)
	var m := find_nearest_module(world_pos, 95.0)
	if m.is_empty():
		salvage_armed_oid = -1
		return false
	var oid := int(m["uid"])
	if tool == "salvage":
		var now := Time.get_ticks_msec()
		if salvage_armed_oid == oid and (now - salvage_armed_ms) <= 3200:
			salvage_armed_oid = -1
			return salvage_module(oid)
		salvage_armed_oid = oid
		salvage_armed_ms = now
		Sfx.play("click")
		State.add_log("削除確認: もう一度タップで「%s」を回収" % State.BLD[m["id"]]["name"], "warn")
		return true
	if tool == "mine":
		Sfx.play("select")
		orbital_inspected.emit(oid)
		return true
	return false

func get_module_snap(oid: int) -> Dictionary:
	var m := _by_oid(oid)
	if m.is_empty(): return {}
	var bid := String(m["id"])
	var info: Dictionary = State.BLD[bid]
	var rec := String(m["recipe"])
	var rinfo: Dictionary = State.ORB_STATION_RECIPES.get(rec, {})
	var cyc := float(rinfo.get("time", 3.0)) if bid == "orb_station" else (1.6 if bid == "orb_laser" else 0.0)
	var prog := clampf(float(m["timer"]) / maxf(0.1, cyc), 0.0, 1.0) if cyc > 0.0 else 0.0
	return {
		"uid": oid, "id": bid, "name": String(info["name"]), "tex": String(info["tex"]),
		"desc": String(info["desc"]), "body_id": String(m["orb"]["body_id"]),
		"pwr_ratio": float(m["pwr_ratio"]), "prog": prog, "has_prog": (cyc > 0.0),
		"recipe": rec, "recipe_info": rinfo, "collected": int(m["collected"]),
		"laser_ore": String(m["laser_ore"]),
		"in_buf": m["in_buf"].duplicate(), "out_buf": m["out_buf"].duplicate(),
	}

func module_cycle_recipe(oid: int) -> String:
	var m := _by_oid(oid)
	if m.is_empty(): return ""
	var ri := (ORB_RECIPES.find(String(m["recipe"])) + 1) % ORB_RECIPES.size()
	m["recipe"] = ORB_RECIPES[ri]
	m["timer"] = 0.0
	Sfx.play("select")
	return String(m["recipe"])

func module_collect(oid: int) -> int:
	var m := _by_oid(oid)
	if m.is_empty(): return 0
	var got := 0
	for k in m["out_buf"].keys().duplicate():
		var c := int(m["out_buf"][k])
		if c > 0:
			State.add_r(String(k), c)
			m["out_buf"].erase(k)
			got += c
	if got > 0: Sfx.play("pop")
	return got

func module_hand_feed(oid: int) -> bool:
	var m := _by_oid(oid)
	if m.is_empty() or String(m["id"]) != "orb_station": return false
	var rinfo: Dictionary = State.ORB_STATION_RECIPES.get(String(m["recipe"]), {})
	var req: Dictionary = rinfo.get("in", {})
	var fed := false
	for k in req.keys():
		var kn := String(k)
		if State.get_r(kn) >= 1 and _buf_sum(m["in_buf"]) < 30:
			var mv := mini(4, State.get_r(kn))
			State.add_r(kn, -mv)
			_buf_add(m["in_buf"], kn, mv)
			fed = true
	if fed: Sfx.play("pop")
	return fed

func _physics_process(delta: float) -> void:
	anim_t += delta
	if not planet: return

	# 1. Advance ALL orbital modules on exact Analytical Keplerian Rails (Vis-Viva speed, 0 drift!)
	var power_sats: Array[Dictionary] = []
	var collectors: Array[Dictionary] = []
	var stations: Array[Dictionary] = []
	var orb_bonus_w := 0.0

	for m in modules:
		var orb: Dictionary = m["orb"]
		var body_id := String(orb["body_id"])
		var body := planet.get_body(body_id)
		orb["M"] = wrapf(float(orb["M"]) + float(orb["n"]) * delta, -PI, PI)
		var st := Kepler.eval_state(orb, float(orb["M"]))
		m["pos"] = Vector2(body["pos"]) + Vector2(st["pos_rel"])
		m["vel"] = Vector2(st["vel_rel"])
		m["laser_target"] = Vector2.ZERO
		m["power_beam_to"] = Vector2.ZERO

		var bid := String(m["id"])
		if bid == "orb_power":
			var sun_l := planet.get_sunlight_world(Vector2(m["pos"]))
			m["pwr_ratio"] = sun_l
			m["powered"] = (sun_l > 0.2)
			if m["powered"]:
				power_sats.append(m)
				if body_id == "terra":
					orb_bonus_w += 120.0 * sun_l
					# Beam down visually to Terra's surface directly below
					var dir_d := (Vector2(body["pos"]) - Vector2(m["pos"])).normalized()
					m["power_beam_to"] = Vector2(body["pos"]) - dir_d * SphericalPlanet.R_SURFACE
		elif bid == "orb_collector":
			collectors.append(m)
		elif bid == "orb_station":
			stations.append(m)

	State.orb_power_bonus_w = orb_bonus_w

	# 2. Power distribution & Orbital Module Operations
	for m in modules:
		var bid := String(m["id"])
		if bid == "orb_power": continue
		var mp: Vector2 = m["pos"]
		var pwr := 0.35 * planet.get_sunlight_world(mp) # Small onboard solar backup
		for ps in power_sats:
			if String(ps["orb"]["body_id"]) == String(m["orb"]["body_id"]):
				pwr = 1.0
				break
		m["pwr_ratio"] = pwr
		m["powered"] = (pwr > 0.1)

		if bid == "orb_laser" and pwr > 0.1:
			var sample := planet.sample_surface_ore_under(mp)
			if not sample.is_empty():
				m["laser_target"] = Vector2(sample["world_pos"])
				m["laser_ore"] = String(sample["ore"])
				m["timer"] = float(m["timer"]) + delta * pwr
				if float(m["timer"]) >= 1.6:
					m["timer"] = 0.0
					_launch_mined_packet(m, sample)
		elif bid == "orb_station" and pwr > 0.1:
			var rec := String(m["recipe"])
			var rinfo: Dictionary = State.ORB_STATION_RECIPES.get(rec, {})
			var req: Dictionary = rinfo.get("in", {})
			var ib: Dictionary = m["in_buf"]
			var ok_in := not req.is_empty()
			for k in req.keys():
				if int(ib.get(String(k), 0)) < int(req[k]):
					ok_in = false
					break
			if ok_in and _buf_sum(m["out_buf"]) < 40:
				m["timer"] = float(m["timer"]) + delta * pwr
				if float(m["timer"]) >= float(rinfo["time"]):
					m["timer"] = 0.0
					for k in req.keys():
						var kn := String(k)
						ib[kn] = int(ib[kn]) - int(req[k])
						if int(ib[kn]) <= 0: ib.erase(kn)
					var out_id := String(rinfo["out"])
					var out_q := int(rinfo["qty"])
					State.add_r(out_id, out_q)
					planet.spawn_popup_world(mp, "+%d %s" % [out_q, State.res_name(out_id)], SphericalPlanet.ore_col(out_id))
			else:
				m["timer"] = 0.0

	# 3. Gravity-Affected Mined Resource Packets (Rise from planet -> Caught by Collector OR Fall back under REAL gravity!)
	for i in range(packets.size() - 1, -1, -1):
		var pkt: Dictionary = packets[i]
		var bid := String(pkt["body_id"])
		var b := planet.get_body(bid)
		var bp: Vector2 = b["pos"]
		var brad := float(b["rad"])

		# Co-moving body shift + REAL gravitational acceleration pulling back toward planet!
		var ppos := Vector2(pkt["pos"]) + Vector2(b["delta_pos"])
		var pvel := Vector2(pkt["vel"])
		var g := planet.compute_gravity_for(ppos, bid)
		pvel += g * delta

		# Check Orbital Collectors' magnetic tractor field!
		var captured := false
		for col in collectors:
			var cp: Vector2 = col["pos"]
			var d := ppos.distance_to(cp)
			if d <= 680.0:
				var pull := (cp - ppos).normalized()
				pvel += pull * 960.0 * delta
				pvel = pvel.lerp(Vector2(col["vel"]) + pull * 360.0, clampf(delta * 2.8, 0.0, 1.0))
				if d <= 92.0:
					_on_packet_collected(col, pkt, stations)
					packets.remove_at(i)
					captured = true
					break
		if captured:
			continue

		ppos += pvel * delta
		pkt["pos"] = ppos
		pkt["vel"] = pvel
		pkt["age"] = float(pkt["age"]) + delta

		# Impact planet surface if uncollected and fell back down!
		var dist_c := ppos.distance_to(bp)
		if (float(pkt["age"]) > 0.6 and dist_c <= brad + 12.0) or float(pkt["age"]) > 38.0:
			if dist_c <= brad + 16.0:
				planet.spawn_sparks_world(ppos, SphericalPlanet.ore_col(String(pkt["ore"])), 5)
			packets.remove_at(i)

	# 4. Decay cargo transfer beams
	for i in range(cargo_beams.size() - 1, -1, -1):
		cargo_beams[i]["life"] = float(cargo_beams[i]["life"]) - delta
		if float(cargo_beams[i]["life"]) <= 0.0:
			cargo_beams.remove_at(i)

	queue_redraw()

func _launch_mined_packet(laser_mod: Dictionary, sample: Dictionary) -> void:
	if packets.size() >= 64:
		packets.pop_front()
	var bid := String(sample["body_id"])
	var b := planet.get_body(bid)
	var surf_p: Vector2 = sample["world_pos"]
	var n: Vector2 = sample["normal"]
	var rad := float(b["rad"])
	var gm := float(b["gm"])
	var r_orb := maxf(rad + 200.0, Vector2(laser_mod["pos"]).distance_to(Vector2(b["pos"])))
	# Exact energy to reach just past orbital height (1.06 * altitude), then fall back if uncollected!
	var d_pot := maxf(0.0, 2.0 * gm * (1.0 / rad - 1.0 / (rad + (r_orb - rad) * 1.06)))
	var v_up := clampf(sqrt(d_pot), 240.0, 960.0)
	var tang := Vector2(-n.y, n.x) * float(laser_mod["orb"]["dir_sign"])
	var v0 := n * v_up + tang * (Vector2(laser_mod["vel"]).length() * 0.28)
	packets.append({
		"body_id": bid,
		"pos": surf_p + n * 18.0,
		"vel": v0,
		"ore": String(sample["ore"]),
		"age": 0.0,
	})
	planet.spawn_sparks_world(surf_p, SphericalPlanet.ore_col(String(sample["ore"])), 6)

func _on_packet_collected(col: Dictionary, pkt: Dictionary, stations: Array[Dictionary]) -> void:
	var ore_id := String(pkt["ore"])
	col["collected"] = int(col["collected"]) + 1
	var cp: Vector2 = col["pos"]

	# Route to nearest Orbital Craft Station on same body (within 3400px)!
	var best_st: Dictionary = {}
	var bd := 3400.0
	for st in stations:
		if String(st["orb"]["body_id"]) != String(col["orb"]["body_id"]): continue
		var d := cp.distance_to(Vector2(st["pos"]))
		if d < bd and _buf_sum(st["in_buf"]) < 36:
			bd = d
			best_st = st
	if not best_st.is_empty():
		_buf_add(best_st["in_buf"], ore_id, 1)
		cargo_beams.append({"a": cp, "b": Vector2(best_st["pos"]), "col": SphericalPlanet.ore_col(ore_id), "life": 0.45})
	else:
		State.add_r(ore_id, 1)
	planet.spawn_sparks_world(cp, SphericalPlanet.ore_col(ore_id), 6)

# ------------------------------------------------------------------------------
# RENDERING: OTHER PLANETS & MOONS (WITH NIGHT SHADOW), KEPLER ORBIT PREDICTION,
#            ORBITAL MODULES, GRAVITY-AFFECTED PACKETS & LASER BEAMS
# ------------------------------------------------------------------------------
func _draw() -> void:
	if not planet: return
	var cam := get_viewport().get_camera_2d()
	var cpos := cam.global_position if cam else Vector2.ZERO
	var vp := get_viewport_rect().size
	var z := cam.zoom.x if cam else 1.0
	var z_inv := 1.0 / maxf(0.008, z)
	var half := (vp * 0.5) * z_inv + Vector2(600, 600) * z_inv
	var vrect := Rect2(cpos - half, half * 2.0)
	var glow := ArtReg.get_t("glow")
	var font := ArtReg.get_font()

	# 1. Other Solar System Planets & Luna (with real sun-facing Day/Night shadows!)
	var terra_p := planet.get_terra_pos()
	if z < 0.30:
		draw_arc(terra_p, float(planet.bodies["luna"]["orbit_r"]), 0.0, TAU, 96, Color(0.56, 0.72, 0.94, 0.22), 1.6 * z_inv)

	for bid in ["ignis", "luna", "cryo", "astra"]:
		var b: Dictionary = planet.bodies[bid]
		var bp: Vector2 = b["pos"]
		var br := float(b["rad"])
		var bcore := float(b.get("r_core", br * 0.32))
		var bsoi := float(b["soi_r"])
		if z < 0.22:
			var sc: Color = b["col"]; sc.a = 0.16
			draw_arc(bp, bsoi, 0.0, TAU, 48, sc, 1.2 * z_inv)
		if not vrect.intersects(Rect2(bp.x - br * 1.6, bp.y - br * 1.6, br * 3.2, br * 3.2)):
			continue
		if glow:
			var gc: Color = b["col"]; gc.a = 0.16
			draw_texture_rect(glow, Rect2(bp.x - br * 1.35, bp.y - br * 1.35, br * 2.7, br * 2.7), false, gc)
		# Annular Sun-aligned Nightside shadow ring over each sliced voxel planet (keeps inner core glowing!)
		var sun_ang := (-bp).angle() if bp.length() > 1.0 else -PI * 0.5
		var night_a := sun_ang + PI
		var pts := PackedVector2Array()
		for si in range(25):
			var a := night_a - PI * 0.52 + float(si) / 24.0 * PI * 1.04
			pts.append(bp + Vector2(cos(a), sin(a)) * (br + 18.0))
		for si in range(24, -1, -1):
			var a := night_a - PI * 0.52 + float(si) / 24.0 * PI * 1.04
			pts.append(bp + Vector2(cos(a), sin(a)) * (bcore + 10.0))
		draw_colored_polygon(pts, Color(0.01, 0.015, 0.038, 0.56))
		if z < 0.45:
			var tag := String(b["name"]) + (" [敵中枢拠点]" if (bid == "astra" and not State.astra_liberated) else "")
			var lcol := Color(1.0, 0.46, 0.52) if (bid == "astra" and not State.astra_liberated) else Color(0.92, 0.96, 1.0, 0.92)
			draw_set_transform(bp + Vector2(0.0, -br - 16.0 * z_inv), 0.0, Vector2(z_inv, z_inv))
			draw_string(font, Vector2(-110.0, 0.0), tag, HORIZONTAL_ALIGNMENT_CENTER, 220, 14, lcol)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 2. World-Space Asteroids
	if z >= 0.05:
		for ast in planet.asteroids:
			var ap: Vector2 = ast["pos"]
			if not vrect.has_point(ap): continue
			var ar := float(ast["rad"])
			var at := ArtReg.get_t("ast_" + String(ast["ore"]))
			if at:
				draw_set_transform(ap, float(ast["rot"]), Vector2.ONE)
				draw_texture_rect(at, Rect2(-ar, -ar, ar * 2.0, ar * 2.0), false)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 3. Deployed Orbital Modules' Shared Keplerian Rings
	var drawn_rings: Dictionary = {}
	for m in modules:
		var orb: Dictionary = m["orb"]
		var rkey := "%s_%d_%d" % [String(orb["body_id"]), int(round(float(orb["a"]) * 0.1)), int(round(float(orb["e"]) * 100.0))]
		if not drawn_rings.has(rkey):
			drawn_rings[rkey] = true
			var b := planet.get_body(String(orb["body_id"]))
			var pts := Kepler.sample_ellipse(orb, Vector2(b["pos"]), 84)
			if pts.size() >= 3:
				draw_polyline(pts, Color(0.32, 0.94, 0.86, 0.34), maxf(1.5, 1.8 * z_inv))

	# 4. Player Analytical Keplerian Orbit Prediction (Pe / Ap / Status Color!)
	if player and not player.anchored:
		var orb: Dictionary = player.rails_orb if player.on_rails else player.orbit_info
		if bool(orb.get("valid", false)):
			var b := planet.get_body(String(orb["body_id"]))
			var bp: Vector2 = b["pos"]
			var brad := float(b["rad"])
			var st_str := String(orb.get("status", "stable"))
			var ocol := Color(0.32, 0.98, 1.0, 0.90) if player.on_rails else (
				Color(0.36, 0.84, 1.0, 0.78) if st_str == "stable" else (
				Color(1.0, 0.78, 0.24, 0.82) if st_str == "aero" else Color(1.0, 0.32, 0.30, 0.85)))
			var lw := maxf(2.0, 2.4 * z_inv)

			if bool(orb.get("closed", false)):
				var pts := Kepler.sample_ellipse(orb, bp, 96)
				if pts.size() >= 3:
					draw_polyline(pts, ocol, lw)
				var pe_w := bp + Vector2(orb["pe_rel"])
				var ap_w := bp + Vector2(orb["ap_rel"])
				var mr := maxf(7.0, 6.0 * z_inv)
				# Pe (Periapsis) Marker (fixed 14px glyph + GPU transform scale -> zero FreeType atlas growth!)
				draw_circle(pe_w, mr, Color(0.34, 1.0, 0.74))
				draw_set_transform(pe_w + Vector2(mr + 4.0 * z_inv, 4.0 * z_inv), 0.0, Vector2(z_inv, z_inv))
				draw_string(font, Vector2.ZERO, "Pe %dm" % int(maxf(0.0, float(orb["rp"]) - brad)), HORIZONTAL_ALIGNMENT_LEFT, 140, 14, Color(0.42, 1.0, 0.78))
				# Ap (Apoapsis) Marker
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				draw_circle(ap_w, mr, Color(1.0, 0.84, 0.32))
				draw_set_transform(ap_w + Vector2(mr + 4.0 * z_inv, 4.0 * z_inv), 0.0, Vector2(z_inv, z_inv))
				draw_string(font, Vector2.ZERO, "Ap %dm" % int(maxf(0.0, float(orb["ra"]) - brad)), HORIZONTAL_ALIGNMENT_LEFT, 140, 14, Color(1.0, 0.88, 0.42))
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			else:
				var rel := player.position - bp
				var arc := Kepler.predict_open_arc(rel, player.velocity, float(b["gm"]), bp, brad, float(b["soi_r"]), 70, 0.65)
				if arc.size() >= 2:
					draw_polyline(arc, Color(1.0, 0.56, 0.28, 0.78), lw)

	# 5. Orbital Module Beams, Tractor Fields & HD-2D Sprites!
	for m in modules:
		var bid := String(m["id"])
		var mp: Vector2 = m["pos"]
		var b := planet.get_body(String(m["orb"]["body_id"]))
		var to_body := (Vector2(b["pos"]) - mp).normalized()
		var rot := to_body.angle() - PI * 0.5

		# Power microwave beam down to planet
		if bid == "orb_power" and Vector2(m["power_beam_to"]) != Vector2.ZERO:
			var ptgt := Vector2(m["power_beam_to"])
			draw_line(mp, ptgt, Color(1.0, 0.82, 0.26, 0.22), maxf(10.0, 8.0 * z_inv))
			draw_line(mp, ptgt, Color(1.0, 0.94, 0.56, 0.70), maxf(3.0, 2.5 * z_inv))

		# Orbital Mining Laser beam down to surface mineral vein!
		if bid == "orb_laser" and Vector2(m["laser_target"]) != Vector2.ZERO:
			var lt := Vector2(m["laser_target"])
			var pulse := 0.75 + 0.25 * sin(anim_t * 14.0)
			draw_line(mp, lt, Color(0.22, 0.96, 0.82, 0.34 * pulse), maxf(12.0, 9.0 * z_inv))
			draw_line(mp, lt, Color(0.84, 1.0, 0.96, 0.92), maxf(3.4, 2.6 * z_inv))
			if glow:
				draw_texture_rect(glow, Rect2(lt.x - 42, lt.y - 42, 84, 84), false, Color(0.32, 1.0, 0.82, 0.65))

		# Orbital Collector magnetic tractor scoop field!
		if bid == "orb_collector":
			var pulse_c := 0.24 + 0.10 * sin(anim_t * 4.5)
			draw_circle(mp, 680.0, Color(0.24, 0.92, 0.86, 0.05))
			draw_arc(mp, 680.0, 0.0, TAU, 48, Color(0.36, 0.98, 0.88, pulse_c), maxf(1.8, 1.6 * z_inv))

		# Draw HD-2D Orbital Module Sprite (scaled cleanly so visible even when zoomed out!)
		var info: Dictionary = State.BLD[bid]
		var sc := maxf(1.0, 0.42 * z_inv)
		var bw := float(info["w"]) * sc
		var bh := float(info["h"]) * sc
		if glow and bool(m["powered"]):
			var gc := Color(1.0, 0.84, 0.34, 0.32) if bid == "orb_power" else Color(0.32, 0.96, 1.0, 0.30)
			draw_texture_rect(glow, Rect2(mp.x - bw, mp.y - bw, bw * 2.0, bw * 2.0), false, gc)
		draw_set_transform(mp, rot, Vector2.ONE)
		var o_key := String(info["tex"])
		var o_frame := (1 + (int(floor(anim_t * 7.5 + float(m["uid"]))) % 5)) if bool(m["powered"]) else 0
		var t := ArtReg.get_anim(o_key, o_frame)
		if t:
			draw_texture_rect(t, Rect2(-bw * 0.5, -bh * 0.5, bw, bh), false)
		if int(m["uid"]) == salvage_armed_oid:
			draw_arc(Vector2.ZERO, maxf(bw, bh) * 0.72, 0.0, TAU, 24, Color(1.0, 0.28, 0.28, 0.95), maxf(2.5, 2.5 * z_inv))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 6. Collector -> Station Cargo Laser Beams
	for cb in cargo_beams:
		var a_f := clampf(float(cb["life"]) / 0.45, 0.0, 1.0)
		var c: Color = cb["col"]; c.a = 0.88 * a_f
		draw_line(cb["a"], cb["b"], c, maxf(3.0, 2.8 * z_inv))

	# 7. Gravity-Affected Mined Resource Packets rising & arcing!
	for pkt in packets:
		var pp: Vector2 = pkt["pos"]
		if not vrect.has_point(pp): continue
		var o_id := String(pkt["ore"])
		var oc := SphericalPlanet.ore_col(o_id)
		var psz := maxf(16.0, 14.0 * z_inv)
		if glow:
			var gc := oc; gc.a = 0.58
			draw_texture_rect(glow, Rect2(pp.x - psz * 1.4, pp.y - psz * 1.4, psz * 2.8, psz * 2.8), false, gc)
		var ic := ArtReg.get_icon(o_id)
		if ic:
			draw_texture_rect(ic, Rect2(pp.x - psz * 0.5, pp.y - psz * 0.5, psz, psz), false)
		else:
			draw_circle(pp, psz * 0.4, oc)

func export_save_data() -> Dictionary:
	var m_arr: Array = []
	for m in modules:
		var o: Dictionary = m["orb"]
		var o_save := {}
		for k in o.keys():
			var v = o[k]
			if v is Vector2:
				o_save[String(k)] = [v.x, v.y]
			else:
				o_save[String(k)] = v
		m_arr.append({
			"uid": int(m["uid"]), "id": String(m["id"]),
			"orb": o_save, "recipe": String(m.get("recipe", "quantum_core")),
			"in_buf": m["in_buf"].duplicate(), "out_buf": m["out_buf"].duplicate(),
			"collected": int(m.get("collected", 0)),
		})
	return {"next_oid": next_oid, "modules": m_arr}

func import_save_data(d: Dictionary) -> void:
	if d.is_empty() or not planet: return
	clear_all()
	next_oid = maxi(1, int(d.get("next_oid", 1)))
	for mv in d.get("modules", []):
		if not (mv is Dictionary): continue
		var md: Dictionary = mv
		var bid := String(md.get("id", ""))
		if not State.BLD.has(bid): continue
		var o_raw: Dictionary = md.get("orb", {})
		var orb: Dictionary = {}
		for k in o_raw.keys():
			var v = o_raw[k]
			if v is Array and v.size() == 2 and (String(k).ends_with("_rel") or String(k) == "e_vec"):
				orb[String(k)] = Vector2(float(v[0]), float(v[1]))
			else:
				orb[String(k)] = v
		if not orb.has("body_id") or not orb.has("a"): continue
		var st := Kepler.eval_state(orb, float(orb.get("M", 0.0)))
		var b := planet.get_body(String(orb["body_id"]))
		var ib_d: Dictionary = {}
		for k in md.get("in_buf", {}).keys(): ib_d[String(k)] = int(md["in_buf"][k])
		var ob_d: Dictionary = {}
		for k in md.get("out_buf", {}).keys(): ob_d[String(k)] = int(md["out_buf"][k])
		var uid := int(md.get("uid", next_oid))
		next_oid = maxi(next_oid, uid + 1)
		modules.append({
			"uid": uid, "id": bid, "orb": orb,
			"pos": Vector2(b["pos"]) + Vector2(st["pos_rel"]),
			"vel": Vector2(st["vel_rel"]),
			"powered": false, "pwr_ratio": 0.0, "timer": 0.0,
			"laser_target": Vector2.ZERO, "laser_ore": "", "power_beam_to": Vector2.ZERO,
			"recipe": String(md.get("recipe", "quantum_core")),
			"in_buf": ib_d, "out_buf": ob_d, "collected": int(md.get("collected", 0)),
		})
