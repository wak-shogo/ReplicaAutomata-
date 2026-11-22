extends Node2D

# Scene Root for STAR REPLICA: AUTOMA
# Heliocentric Solar System (SUN at 0,0) + HomeSystem (TERRA-I + IndustrialGrid + OrbitalSwarm)
# + OrbitalInfra (Other Planets, Luna, Keplerian Orbit Prediction, Co-Orbital Modules & Gravity Packets)
# + Always Player-Centered Camera + Larger Visual-First Japanese HUD + Exhaustive Headless Test Suite.

@onready var sky: Node2D = $CosmicSky
@onready var home_root: Node2D = $HomeSystem
@onready var planet: SphericalPlanet = $HomeSystem/SphericalPlanet
@onready var grid: Node2D = $HomeSystem/IndustrialGrid
@onready var swarm: Node2D = $HomeSystem/OrbitalSwarm
@onready var orbital: Node2D = $OrbitalInfra
@onready var player: Node2D = $SeedUnit
@onready var cam: Camera2D = $Camera2D
@onready var hud: CanvasLayer = $CommandHUD

var user_zoom: float = 0.88
const ZOOM_MIN: float = 0.014 # 太陽系全体を一望できる超広域ズーム
const ZOOM_MAX: float = 2.60  # 機体や施設が大きく映る超近接ズーム
var _tel_t: float = 0.0
var _test_failed: bool = false

func _ready() -> void:
	sky.planet = planet
	planet.home_root = home_root
	planet.factory = grid
	planet.step_celestials(0.0, true)

	grid.planet = planet
	grid.player = player
	grid.swarm = swarm
	swarm.planet = planet
	swarm.grid = grid
	orbital.planet = planet
	orbital.player = player
	orbital.grid = grid
	player.planet = planet
	player.grid = grid
	player.swarm = swarm
	hud.planet = planet
	hud.grid = grid
	hud.orbital = orbital
	hud.player = player
	hud.swarm = swarm
	hud.game_root = self

	grid.depot_opened.connect(hud.open_depot)
	grid.building_inspected.connect(hud.open_building)
	orbital.orbital_inspected.connect(hud.open_orbital)

	player.spawn_north_pole()
	cam.position = player.global_position
	cam.zoom = Vector2(user_zoom, user_zoom)

	if "--run-tests" in OS.get_cmdline_args() or "--run-tests" in OS.get_cmdline_user_args():
		call_deferred("_run_tests")

func adjust_zoom(factor: float) -> void:
	if factor <= 0.0: return
	if State.orbit_view and factor > 1.02:
		State.orbit_view = false
	user_zoom = clampf(user_zoom * factor, ZOOM_MIN, ZOOM_MAX)

func set_zoom_val(v: float) -> void:
	user_zoom = clampf(v, ZOOM_MIN, ZOOM_MAX)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			adjust_zoom(1.16)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			adjust_zoom(1.0 / 1.16)
	elif event is InputEventMagnifyGesture:
		adjust_zoom(event.factor)

func _process(delta: float) -> void:
	if State.orbit_view:
		# Explicit Solar System Overview Map button
		cam.position = cam.position.lerp(Vector2.ZERO, minf(1.0, delta * 5.0))
		var vp := get_viewport_rect().size
		var fit := minf(vp.x, vp.y) / 126000.0
		cam.zoom = cam.zoom.lerp(Vector2(fit, fit), minf(1.0, delta * 5.0))
	else:
		# ALWAYS Player-Centered Camera at ALL zoom levels (0px orbital trailing lag!)
		var target_z := clampf(user_zoom, ZOOM_MIN, ZOOM_MAX)
		cam.zoom = cam.zoom.lerp(Vector2(target_z, target_z), minf(1.0, delta * 10.0))
		cam.position = player.global_position

	if OS.has_feature("web"):
		_tel_t += delta
		if _tel_t >= 0.12:
			_tel_t = 0.0
			_publish_tel()

func _publish_tel() -> void:
	var d := {
		"px": int(round(player.position.x)), "py": int(round(player.position.y)),
		"vx": snappedf(player.velocity.x, 0.1), "vy": snappedf(player.velocity.y, 0.1),
		"body": player.active_body_id, "on_rails": player.on_rails,
		"orbit_closed": bool(player.orbit_info.get("closed", false)),
		"sunlight": snappedf(planet.get_sunlight_world(player.position), 0.02),
		"beam_x": snappedf(player.beam_end_world.x - player.position.x, 0.1) if player.beam_end_world != Vector2.ZERO else 0.0,
		"beam_y": snappedf(player.beam_end_world.y - player.position.y, 0.1) if player.beam_end_world != Vector2.ZERO else 0.0,
		"alt": int(round(player.get_altitude())),
		"vel": int(round(player.velocity.length())), "grav": snappedf(player.local_g, 0.02),
		"cam_err": int(round(cam.position.distance_to(player.global_position))),
		"drones": State.attached_drones, "prop": State.propulsion_tier,
		"fe": State.get_r("fe"), "cu": State.get_r("cu"), "si": State.get_r("si"), "ti": State.get_r("ti"),
		"plate_fe": State.get_r("plate_fe"), "wire_cu": State.get_r("wire_cu"), "wafer_si": State.get_r("wafer_si"),
		"circuit": State.get_r("circuit"), "alloy": State.get_r("alloy"), "sci_pack": State.get_r("sci_pack"),
		"ignis_ore": State.get_r("ignis_ore"), "ice": State.get_r("ice"), "astra_shard": State.get_r("astra_shard"),
		"plasma_cell": State.get_r("plasma_cell"), "cryo_rod": State.get_r("cryo_rod"),
		"quantum_core": State.get_r("quantum_core"), "antimatter": State.get_r("antimatter"), "dyson_panel": State.get_r("dyson_panel"),
		"pollution": snappedf(State.get_pollution(player.active_body_id), 0.1),
		"astra_lib": State.astra_liberated, "item_tree_sel": hud.item_tree_sel,
		"queue": State.craft_queue.size(),
		"stock_solar": State.get_stock("solar"), "stock_tesla": State.get_stock("tesla"),
		"tut_step": State.tut_step,
		"pwr_prod": int(round(State.pwr_prod)), "pwr_use": int(round(State.pwr_use)),
		"pwr_stored": int(round(State.pwr_stored)), "wires": State.wire_count, "teslas_on": State.active_teslas,
		"bldg": grid.buildings.size(), "orb_mods": orbital.modules.size(), "orb_pkts": orbital.packets.size(),
		"fleet": State.swarm_fleet, "launches": State.total_launches,
		"techs": State.unlocked_techs, "tool": State.selected_tool, "modal": hud.modal,
		"tech_detail": hud.tech_detail_open,
		"zoom": snappedf(cam.zoom.x, 0.001), "insp_uid": hud.inspect_uid, "armed_del": grid.salvage_armed_uid,
		"orbit": State.orbit_view, "won": State.game_won,
	}
	JavaScriptBridge.eval("window.__star_tel = " + JSON.stringify(d) + ";")

func _chk(ok: bool, msg: String) -> void:
	if not ok:
		_test_failed = true
		push_error("FAIL: " + msg)
		print("FAIL: " + msg)

func _craft_and_finish(kind: String, id: String) -> bool:
	if not State.enqueue_craft(kind, id):
		return false
	for _i in range(240):
		if State.craft_queue.is_empty():
			break
		State._process(0.1)
	return State.craft_queue.is_empty()

func _run_tests() -> void:
	print("=== STAR REPLICA: AUTOMA V5 HELIOCENTRIC + KEPLER ON-RAILS + ORBITAL INFRA TESTS ===")
	_chk(grid.buildings.is_empty(), "Must start with 0 buildings")
	_chk(State.attached_drones == 0 and State.propulsion_tier == 0, "Must start with 0 drones & tier 0")
	_chk(Sfx.preset_count() >= 13, "Missing Sfx presets")
	_chk(ArtReg.tex.size() >= 33, "Missing HD-2D sprites (got %d)" % ArtReg.tex.size())
	_chk(ArtReg.ui_font != null, "Japanese UI font NotoSansJP-Bold failed to load!")
	_chk(ArtReg.get_icon("quantum_core") != null and ArtReg.get_icon("antimatter") != null and ArtReg.get_icon("dyson_panel") != null, "Missing new orbital resource icons!")

	# 0. Organic FastNoiseLite Cave Sanity Check
	var cave_cells := 0
	var solid_cells := 0
	for i in range(planet.mat.size()):
		if int(planet.mat[i]) == 4: cave_cells += 1
		elif int(planet.mat[i]) in [1, 2]: solid_cells += 1
	_chk(cave_cells > 4000 and solid_cells > 40000, "FastNoiseLite caves invalid! cave=%d solid=%d" % [cave_cells, solid_cells])

	# 1. Screen-space movement check at bottom-right of Terra (+PI/4)
	var terra_p := planet.get_terra_pos()
	var br_ang := PI * 0.25
	player.position = terra_p + Vector2(cos(br_ang), sin(br_ang)) * (SphericalPlanet.R_SURFACE + 45.0)
	player.velocity = Vector2.ZERO
	player.move_input = Vector2(1.0, 0.0)
	player.braking = false
	for _m in range(10):
		planet.step_celestials(0.05)
		player._physics_process(0.05)
	_chk(player.velocity.x > 20.0, "Screen-space RIGHT at bottom-right failed! vel=%s" % str(player.velocity))
	player.spawn_north_pole()
	player.move_input = Vector2.ZERO

	# 1a. Zero-jitter surface anchor test while Terra orbits the Sun!
	for _s in range(60):
		planet.step_celestials(0.05)
		player._physics_process(0.05)
	var settled_rel := player.position - planet.get_terra_pos()
	for _s2 in range(30):
		planet.step_celestials(0.05)
		player._physics_process(0.05)
	var drift_rel := (player.position - planet.get_terra_pos()).distance_to(settled_rel)
	_chk(player.anchored and player.velocity.length() < 0.01 and drift_rel < 0.01,
		"Seed Unit still jittering on orbiting Terra! anchored=%s vel=%.2f drift=%.4f" % [str(player.anchored), player.velocity.length(), drift_rel])

	# 1b. Always Player-Centered Camera test even when zoomed far out (0.04x)!
	set_zoom_val(0.04)
	for _c in range(40):
		_process(0.05)
	_chk(cam.position.distance_to(player.global_position) < 5.0,
		"Camera drifted away from player on zoom-out! err=%.1f" % cam.position.distance_to(player.global_position))
	set_zoom_val(0.88)

	# 1c. Directional raycast mining test
	var up_hit := planet.find_mine_target(player.position, Vector2.UP, 220.0)
	var dn_hit := planet.find_mine_target(player.position, Vector2.DOWN, 220.0)
	_chk(up_hit.is_empty(), "Aiming UP into sky must not auto-target ground!")
	_chk(not dn_hit.is_empty(), "Aiming DOWN at crust must hit terrain!")

	# 1d. Real Heliocentric Day/Night Sunlight Check (North Pole faces Sun -> Day > 0.7; South Pole away -> Night == 0.0!)
	var day_sun := planet.get_sunlight_local(Vector2(0.0, -SphericalPlanet.R_SURFACE))
	var night_sun := planet.get_sunlight_local(Vector2(0.0, SphericalPlanet.R_SURFACE))
	_chk(day_sun > 0.75 and night_sun <= 0.01, "Heliocentric Day/Night sunlight broken! day=%.2f night=%.2f" % [day_sun, night_sun])

	# 1e. Real Moon (LUNA) Gravity & Co-Moving Landing Anchor Test (MUST NOT slide off toward Terra!)
	var luna_b := planet.get_body("luna")
	player.anchored = false; player.anchored_body_id = ""; player.on_rails = false
	player.active_body_id = "luna"
	player.position = Vector2(luna_b["pos"]) + Vector2(0.0, -(float(luna_b["rad"]) + float(player.RADIUS) + 18.0))
	player.velocity = Vector2.ZERO
	player.move_input = Vector2.ZERO
	for _l in range(70):
		planet.step_celestials(0.05)
		player._physics_process(0.05)
	var luna_settled_rel := player.position - Vector2(planet.get_body("luna")["pos"])
	for _l2 in range(50):
		planet.step_celestials(0.05)
		player._physics_process(0.05)
	var luna_drift := (player.position - Vector2(planet.get_body("luna")["pos"])).distance_to(luna_settled_rel)
	_chk(player.anchored and player.anchored_body_id == "luna" and luna_drift < 0.1,
		"Player slid off LUNA! anchored=%s body=%s drift=%.2f" % [str(player.anchored), player.anchored_body_id, luna_drift])
	player.spawn_north_pole()

	# 2. Timed Craft Queue + Cancel Refund + Auto-Docking Fabricator Drones
	State.add_r("fe", 420); State.add_r("cu", 340); State.add_r("si", 260); State.add_r("ti", 260)
	var fe_before := State.get_r("fe")
	_chk(State.enqueue_craft("drone", "fab_drone"), "Enqueue Drone failed")
	_chk(State.attached_drones == 0 and State.craft_queue.size() == 1, "Craft must be queued!")
	_chk(State.cancel_craft(0) and State.get_r("fe") == fe_before, "Cancel craft refund failed!")
	_chk(_craft_and_finish("drone", "fab_drone") and State.attached_drones == 1, "Craft Drone #1 failed")
	_chk(_craft_and_finish("drone", "fab_drone") and State.attached_drones == 2, "Craft Drone #2 failed")

	# 3. Research + Ground Factory + Power Grid + Smelter Cu x12 Regression
	_chk(State.research("power_grid"), "Research power_grid failed")
	_chk(State.research("cave_logistics"), "Research cave_logistics failed")
	_chk(State.research("smelting_booster"), "Research smelting_booster failed")
	for b_req in ["solar", "tesla", "battery", "drill", "depot", "smelter"]:
		_chk(_craft_and_finish("building", b_req) and State.get_stock(b_req) == 1, "Craft %s failed" % b_req)

	var p_sol: Vector2 = planet.get_pose_at(SphericalPlanet.SPAWN_COL - 6, SphericalPlanet.ROWS - 2)["pos"]
	var p_tes: Vector2 = planet.get_pose_at(SphericalPlanet.SPAWN_COL + 8, SphericalPlanet.ROWS - 2)["pos"]
	var p_bat: Vector2 = planet.get_pose_at(SphericalPlanet.SPAWN_COL, SphericalPlanet.ROWS - 2)["pos"]
	_chk(grid.try_place_at("solar", p_sol), "Place Solar failed")
	_chk(grid.try_place_at("tesla", p_tes), "Place Tesla failed")
	_chk(grid.try_place_at("battery", p_bat), "Place Battery failed")
	_chk(grid.toggle_wire(int(grid.buildings[0]["uid"]), int(grid.buildings[1]["uid"])), "Wire Solar<->Tesla failed")
	_chk(grid.toggle_wire(int(grid.buildings[2]["uid"]), int(grid.buildings[1]["uid"])), "Wire Battery<->Tesla failed")
	grid._solve_power(0.5)
	_chk(State.pwr_prod > 30.0 and State.active_teslas == 1, "Wired Solar+Tesla failed")

	var dn_pos: Vector2 = planet.drill_nodes[1]["pos"]
	_chk(grid.try_place_at("drill", dn_pos), "Place Drill failed")
	_chk(grid.try_place_at("depot", planet.get_pose_at(SphericalPlanet.SPAWN_COL + 16, SphericalPlanet.ROWS - 2)["pos"]), "Place Depot failed")
	_chk(grid.try_place_at("smelter", planet.get_pose_at(SphericalPlanet.SPAWN_COL + 21, SphericalPlanet.ROWS - 2)["pos"]), "Place Smelter failed")
	var sm_b: Dictionary = grid.buildings[5]
	sm_b["in_buf"] = {"cu": 12}; sm_b["out_buf"] = {}; sm_b["timer"] = 0.0
	for _sm in range(25): grid._process(0.1)
	_chk(int(sm_b["out_buf"].get("wire_cu", 0)) >= 1, "Smelter Cu x12 regression failed!")

	# 3b. Complete Item Tree Audit (100% of resources & active facilities in ITEM_TREE_NODES!)
	var tree_ids: Dictionary = {}
	for nd in State.ITEM_TREE_NODES:
		tree_ids[String(nd["id"])] = true
	for r_id in State.RES_NAMES.keys():
		_chk(tree_ids.has(String(r_id)), "Resource %s missing from ITEM_TREE_NODES!" % String(r_id))
	for b_id in State.BLD.keys():
		if String(b_id) in ["belt", "lift"]: continue
		_chk(tree_ids.has(String(b_id)), "Building %s missing from ITEM_TREE_NODES!" % String(b_id))

	# 3c. Starter Planet TERRA-I Resource Gating + All 5 Planets Sliced Voxel Interiors!
	var terra_ti_cnt := 0
	for v_o in planet.ore:
		if int(v_o) == 4: terra_ti_cnt += 1
	_chk(terra_ti_cnt == 0, "Starter planet TERRA-I must NOT contain Titanium (ti)! Found=%d" % terra_ti_cnt)
	for ex_id in ["luna", "ignis", "cryo", "astra"]:
		_chk(planet.extra_vox.has(ex_id) and int(planet.extra_vox[ex_id]["mat"].size()) == SphericalPlanet.EX_COLS * SphericalPlanet.EX_ROWS,
			"Extra planet %s missing sliced voxel interior!" % ex_id)

	# 3d. Smart Demand-Driven Logistics (Depot -> Assembler crafting 'circuit' MUST send both plate_fe AND wire_cu!) + PCB Autorouter!
	State.add_r("plate_fe", 260); State.add_r("wire_cu", 220); State.add_r("wafer_si", 180)
	State.add_r("circuit", 160); State.add_r("alloy", 120); State.add_r("plasma_cell", 40); State.add_r("cryo_rod", 40)
	_chk(State.research("circuits_geo"), "Research circuits_geo failed")
	_chk(_craft_and_finish("building", "assembler"), "Craft Assembler failed")
	_chk(grid.try_place_at("assembler", planet.get_pose_at(SphericalPlanet.SPAWN_COL + 3, SphericalPlanet.ROWS - 2)["pos"]), "Place Assembler failed")
	var dep_b: Dictionary = grid.buildings[4]
	var asm_b: Dictionary = grid.buildings[6]
	dep_b["inv"] = {"plate_fe": 50, "wire_cu": 6, "si": 30}
	asm_b["recipe"] = "circuit"
	asm_b["in_buf"] = {}
	asm_b["out_buf"] = {}
	_chk(grid.toggle_conveyor(int(dep_b["uid"]), int(asm_b["uid"])), "Autoroute Depot->Assembler failed!")
	_chk(grid.conveyors[0]["cells"].size() >= 2, "Autorouter did not generate grid cells!")
	for _al in range(110):
		grid._process(0.1)
	_chk(int(asm_b["out_buf"].get("circuit", 0)) >= 2 and int(asm_b["in_buf"].get("si", 0)) == 0,
		"Smart Depot->Assembler failed to balance plate_fe & wire_cu into circuit! in=%s out=%s" % [str(asm_b["in_buf"]), str(asm_b["out_buf"])])

	# 3e. PCB Autorouter Non-Overlapping & Unroutable Rejection Test!
	# Surround Smelter's port cell with a closed ring of occupied conveyor cells -> autoroute_conveyor MUST reject!
	var sm_c := int(sm_b["col"]); var sm_r := int(sm_b["row"]) + 1
	var ring_cells: Array[Vector2i] = [
		Vector2i(SphericalPlanet.wrap_col(sm_c + 1), sm_r),
		Vector2i(SphericalPlanet.wrap_col(sm_c - 1), sm_r),
		Vector2i(sm_c, sm_r + 1),
		Vector2i(sm_c, sm_r - 1),
		Vector2i(sm_c, sm_r), # start dummy
		Vector2i(sm_c, sm_r + 2), # end dummy
	]
	grid.conveyors.append({
		"from": 9991, "to": 9992, "body_id": "terra", "cost_fe": 2, "filter": "auto",
		"cells": [ring_cells[4], ring_cells[0], ring_cells[1], ring_cells[2], ring_cells[3], ring_cells[5]],
		"local_pts": PackedVector2Array(), "pts": PackedVector2Array(), "total_len": 40.0,
	})
	var blocked_res: Dictionary = grid.autoroute_conveyor(dep_b, sm_b)
	_chk(not bool(blocked_res.get("ok", true)) and bool(blocked_res.get("blocked_route", false)),
		"PCB Autorouter MUST reject route when all non-overlapping grid paths are blocked! got=%s" % str(blocked_res))
	grid.conveyors.pop_back()

	# 3f. Building Durability HP, Non-Starter Planet Pollution & ASTRA-V Fleet Liberation + Research Points 1,000 Victory!
	var sol_uid := int(grid.buildings[0]["uid"])
	var hp_pre := float(grid.buildings[0]["hp"])
	grid.damage_building_uid(sol_uid, 25.0)
	_chk(float(grid.buildings[0]["hp"]) < hp_pre, "Building HP did not decrease on enemy damage!")
	State.add_pollution("luna", 22.0)
	State.add_pollution("terra", 22.0)
	_chk(State.get_pollution("luna") >= 20.0 and State.get_pollution("terra") == 0.0, "Starter planet terra must stay 0 pollution while luna accumulates pollution!")
	_chk(not State.astra_liberated and State.astra_bastions_left == 6, "ASTRA-V must start fortified with 6 bastions!")
	planet.damage_astra_bastions(1000.0)
	_chk(State.astra_liberated and State.astra_bastions_left == 0, "Swarm fleet assault failed to liberate ASTRA-V!")

	# 4. EXACT ANALYTICAL KEPLERIAN ON-RAILS ORBIT (Eccentric e=0.14, 5 FULL REVOLUTIONS, ZERO DRIFT, VIS-VIVA SPEED!)
	_chk(_craft_and_finish("propulsion", "1") and State.propulsion_tier == 1, "Orbital Booster craft failed")
	_chk(State.research("deep_space"), "Research deep_space failed")

	# Put player at Periapsis rp = 6150 (above atmos 5900), e = 0.14 -> a = 7151, ra = 8152 (clear of Luna SOI 8300!)
	var rp_t := 6150.0
	var e_t := 0.14
	var a_t := rp_t / (1.0 - e_t)
	var ra_t := a_t * (1.0 + e_t)
	var mu_t := SphericalPlanet.ORIGIN_GM
	var v_pe_exact := sqrt(mu_t * (2.0 / rp_t - 1.0 / a_t))
	var v_ap_exact := sqrt(mu_t * (2.0 / ra_t - 1.0 / a_t))
	var period_t := TAU / sqrt(mu_t / (a_t * a_t * a_t))

	player.anchored = false; player.on_rails = false; player.active_body_id = "terra"
	player.position = planet.get_terra_pos() + Vector2(0.0, -rp_t)
	player.velocity = Vector2(v_pe_exact, 0.0)
	player.move_input = Vector2.ZERO; player.braking = false

	# First tick locks onto analytical Keplerian rails seamlessly!
	planet.step_celestials(0.05)
	player._physics_process(0.05)
	_chk(player.on_rails and player.is_in_orbit(), "Player failed to lock onto analytical Keplerian rails! info=%s" % str(player.orbit_info))

	var min_v := 1e9; var max_v := 0.0
	var min_r := 1e9; var max_r := 0.0
	# Simulate 5 FULL REVOLUTIONS!
	var steps_5rev := int(ceil((period_t * 5.0) / 0.2))
	for _k in range(steps_5rev):
		planet.step_celestials(0.2)
		player._physics_process(0.2)
		var spd: float = player.velocity.length()
		var rad: float = player.position.distance_to(planet.get_terra_pos())
		min_v = minf(min_v, spd); max_v = maxf(max_v, spd)
		min_r = minf(min_r, rad); max_r = maxf(max_r, rad)
	_chk(player.on_rails, "Orbit lost rails during 5 revolutions!")
	_chk(absf(min_r - rp_t) < 25.0 and absf(max_r - ra_t) < 25.0,
		"Keplerian 5-rev radius drifted! min_r=%.1f (exp %.1f) max_r=%.1f (exp %.1f)" % [min_r, rp_t, max_r, ra_t])
	_chk(max_v > min_v * 1.25 and absf(max_v - v_pe_exact) < v_pe_exact * 0.02 and absf(min_v - v_ap_exact) < v_ap_exact * 0.02,
		"Vis-Viva Pe/Ap speed mismatch! max_v=%.1f (exp %.1f) min_v=%.1f (exp %.1f)" % [max_v, v_pe_exact, min_v, v_ap_exact])

	# 5. ORBITAL INFRASTRUCTURE FULL LOOP (Same-Orbit Deploy, Power Beam, Gravity-Falling Packets, Collector -> Craft Station!)
	for oid_b in ["orb_power", "orb_laser", "orb_collector", "orb_station"]:
		_chk(_craft_and_finish("building", oid_b) and State.get_stock(oid_b) == 1, "Craft %s failed" % oid_b)
	_chk(orbital.deploy_on_player_orbit("orb_power"), "Deploy orb_power on player orbit failed!")
	_chk(orbital.deploy_on_player_orbit("orb_laser"), "Deploy orb_laser on player orbit failed!")
	# Step 4s without collector: laser must beam down & launch physical packet, and packet must decelerate under gravity!
	for _o1 in range(40):
		planet.step_celestials(0.1)
		orbital._physics_process(0.1)
	_chk(State.orb_power_bonus_w > 60.0, "Orbital Power Satellite did not beam power down! bonus=%.1f" % State.orb_power_bonus_w)
	_chk(not orbital.packets.is_empty(), "Orbital Mining Laser failed to launch rising mineral packets!")
	var pkt0: Dictionary = orbital.packets[0]
	var r0_v := Vector2(pkt0["vel"]).dot((Vector2(pkt0["pos"]) - planet.get_terra_pos()).normalized())
	for _o2 in range(30):
		planet.step_celestials(0.1)
		orbital._physics_process(0.1)
	if not orbital.packets.is_empty():
		var pkt_chk: Dictionary = orbital.packets[0]
		var r1_v := Vector2(pkt_chk["vel"]).dot((Vector2(pkt_chk["pos"]) - planet.get_terra_pos()).normalized())
		_chk(r1_v < r0_v, "Mined orbital packet did NOT decelerate under planet gravity! r0=%.1f r1=%.1f" % [r0_v, r1_v])

	# Now deploy Orbital Collector + Orbital Craft Station on the same orbit!
	_chk(orbital.deploy_on_player_orbit("orb_collector"), "Deploy orb_collector failed!")
	_chk(orbital.deploy_on_player_orbit("orb_station"), "Deploy orb_station failed!")
	# Seed a packet right near collector + feed station to verify collection + quantum_core crafting!
	var col_pos := Vector2(orbital.modules[2]["pos"])
	orbital.packets.append({"body_id": "terra", "pos": col_pos + Vector2(0, 140), "vel": Vector2(0, -180), "ore": "si", "age": 1.0})
	orbital.packets.append({"body_id": "terra", "pos": col_pos + Vector2(30, 120), "vel": Vector2(0, -180), "ore": "si", "age": 1.0})
	orbital.packets.append({"body_id": "terra", "pos": col_pos + Vector2(-30, 120), "vel": Vector2(0, -180), "ore": "cu", "age": 1.0})
	orbital.packets.append({"body_id": "terra", "pos": col_pos + Vector2(10, 110), "vel": Vector2(0, -180), "ore": "cu", "age": 1.0})
	for _o3 in range(80):
		planet.step_celestials(0.1)
		orbital._physics_process(0.1)
	_chk(int(orbital.modules[2]["collected"]) >= 4 and State.get_r("quantum_core") >= 1,
		"Orbital Collector -> Station pipeline failed! collected=%d qcore=%d" % [int(orbital.modules[2]["collected"]), State.get_r("quantum_core")])

	# 6. Research Point (研究ポイント >= 1,000) Victory + Macro Swarm
	_chk(State.research("macro_swarm"), "Research macro_swarm failed")
	_chk(State.research("megastructures"), "Research megastructures failed")
	State.add_r("sci_pack", 1000)
	_chk(State.game_won, "Reaching 1,000 Research Points (研究ポイント) must trigger game clear!")
	swarm.spawn_raider_wave("luna", true)
	_chk(not swarm.raiders.is_empty(), "Continuous off-map enemy raids must continue even after ASTRA-V liberation!")

	if _test_failed:
		print("TESTS FAILED!")
		get_tree().quit(1)
		return
	print("ALL V5 HELIOCENTRIC + KEPLER ON-RAILS + ORBITAL INFRA TESTS PASSED! Caves=%d LunaDrift=%.3f PeV=%.1f ApV=%.1f OrbMods=%d QCore=%d" % [
		cave_cells, luna_drift, max_v, min_v, orbital.modules.size(), State.get_r("quantum_core")
	])
	get_tree().quit(0)
