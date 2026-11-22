extends Node2D

# Scene Root for STAR REPLICA: AUTOMA (True Concept-Art & Design-Spec Ground-Up Rebuild)
# Wires CosmicSky, SphericalPlanet (24px GPU-baked organic caves), IndustrialGrid,
# OrbitalSwarm (10,000 MultiMesh2D), SeedUnit (Docking Drones), Camera2D, CommandHUD,
# Web telemetry bridge, and headless --run-tests verification suite.

@onready var sky: Node2D = $CosmicSky
@onready var planet: SphericalPlanet = $SphericalPlanet
@onready var grid: Node2D = $IndustrialGrid
@onready var swarm: Node2D = $OrbitalSwarm
@onready var player: Node2D = $SeedUnit
@onready var cam: Camera2D = $Camera2D
@onready var hud: CanvasLayer = $CommandHUD

var user_zoom: float = 0.88
const ZOOM_MIN: float = 0.072 # 惑星全体＆衛星軌道まで一望
const ZOOM_MAX: float = 2.60  # 機体や施設が大きく映る超近接ズーム
var _tel_t: float = 0.0
var _test_failed: bool = false

func _ready() -> void:
	planet.factory = grid
	grid.planet = planet
	grid.player = player
	grid.swarm = swarm
	swarm.planet = planet
	player.planet = planet
	player.grid = grid
	player.swarm = swarm
	hud.planet = planet
	hud.grid = grid
	hud.player = player
	hud.swarm = swarm
	hud.game_root = self
	grid.depot_opened.connect(hud.open_depot)
	grid.building_inspected.connect(hud.open_building)

	player.spawn_north_pole()
	cam.position = player.position + Vector2(0, -45)
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
		cam.position = cam.position.lerp(Vector2.ZERO, minf(1.0, delta * 5.0))
		var vp := get_viewport_rect().size
		var fit := minf(vp.x, vp.y) / 17000.0
		cam.zoom = cam.zoom.lerp(Vector2(fit, fit), minf(1.0, delta * 5.0))
	else:
		# 超広域ズーム（ピンチアウトで惑星全体まで引いた時）は惑星中心へ滑らかに視点を寄せる
		var alt := maxf(0.0, player.get_altitude())
		var alt_scale := lerpf(1.0, 0.55, clampf(alt / 3200.0, 0.0, 1.0))
		var target_z := clampf(user_zoom * alt_scale, ZOOM_MIN, ZOOM_MAX)
		cam.zoom = cam.zoom.lerp(Vector2(target_z, target_z), minf(1.0, delta * 10.0))

		var up := player.position.normalized() if player.position.length() > 1.0 else Vector2.UP
		var local_c := player.position + (up * 35.0 if player.get_altitude() < 260.0 else Vector2.ZERO)
		var macro_t := clampf((0.26 - cam.zoom.x) / (0.26 - 0.11), 0.0, 1.0)
		var target_c := local_c.lerp(Vector2.ZERO, macro_t)
		cam.position = cam.position.lerp(target_c, minf(1.0, delta * 8.0))

	if OS.has_feature("web"):
		_tel_t += delta
		if _tel_t >= 0.12:
			_tel_t = 0.0
			_publish_tel()

func _publish_tel() -> void:
	var d := {
		"px": int(round(player.position.x)), "py": int(round(player.position.y)),
		"vx": snappedf(player.velocity.x, 0.1), "vy": snappedf(player.velocity.y, 0.1),
		"beam_x": snappedf(player.beam_end_world.x - player.position.x, 0.1) if player.beam_end_world != Vector2.ZERO else 0.0,
		"beam_y": snappedf(player.beam_end_world.y - player.position.y, 0.1) if player.beam_end_world != Vector2.ZERO else 0.0,
		"r": int(round(player.position.length())), "alt": int(round(player.get_altitude())),
		"vel": int(round(player.velocity.length())), "grav": snappedf(player.local_g, 0.02),
		"drones": State.attached_drones, "prop": State.propulsion_tier,
		"fe": State.get_r("fe"), "cu": State.get_r("cu"), "si": State.get_r("si"), "ti": State.get_r("ti"),
		"plate_fe": State.get_r("plate_fe"), "wire_cu": State.get_r("wire_cu"), "wafer_si": State.get_r("wafer_si"),
		"circuit": State.get_r("circuit"), "alloy": State.get_r("alloy"),
		"queue": State.craft_queue.size(),
		"stock_solar": State.get_stock("solar"), "stock_tesla": State.get_stock("tesla"),
		"tut_step": State.tut_step,
		"pwr_prod": int(round(State.pwr_prod)), "pwr_use": int(round(State.pwr_use)),
		"pwr_stored": int(round(State.pwr_stored)), "wires": State.wire_count, "teslas_on": State.active_teslas,
		"bldg": grid.buildings.size(), "fleet": State.swarm_fleet, "launches": State.total_launches,
		"techs": State.unlocked_techs, "tool": State.selected_tool, "modal": hud.modal,
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
	for _i in range(200):
		if State.craft_queue.is_empty():
			break
		State._process(0.1)
	return State.craft_queue.is_empty()

func _run_tests() -> void:
	print("=== STAR REPLICA: AUTOMA (JP CRAFT QUEUE + SCREEN MOVE + TUTORIAL) HEADLESS TESTS ===")
	_chk(grid.buildings.is_empty(), "Must start with 0 buildings")
	_chk(State.attached_drones == 0 and State.propulsion_tier == 0, "Must start with 0 drones & tier 0")
	_chk(Sfx.preset_count() >= 13, "Missing Sfx presets")
	_chk(ArtReg.tex.size() >= 28, "Missing HD-2D sprites")
	_chk(ArtReg.ui_font != null, "Japanese UI font NotoSansJP-Bold failed to load!")

	# 1. Screen-space movement check at bottom-right of planet (+PI/4): pressing RIGHT (+X) must push +X, NOT -X or down-only!
	var br_ang := PI * 0.25
	player.position = Vector2(cos(br_ang), sin(br_ang)) * (SphericalPlanet.R_SURFACE + 45.0)
	player.velocity = Vector2.ZERO
	player.move_input = Vector2(1.0, 0.0) # Screen RIGHT
	player.braking = false
	for _m in range(10):
		player._physics_process(0.05)
	_chk(player.velocity.x > 20.0, "Screen-space RIGHT at bottom-right failed! vel=%s" % str(player.velocity))
	player.spawn_north_pole()
	player.move_input = Vector2.ZERO
	# 1a. Zero-jitter surface anchor test: let Seed Unit land & verify it locks completely still (0.0px jitter)!
	for _s in range(60):
		player._physics_process(0.05)
	var settled_pos := player.position
	for _s2 in range(30):
		player._physics_process(0.05)
	_chk(player.anchored and player.velocity.length() < 0.01 and player.position.distance_to(settled_pos) < 0.01,
		"Seed Unit still jittering on surface! anchored=%s vel=%.2f drift=%.3f" % [str(player.anchored), player.velocity.length(), player.position.distance_to(settled_pos)])

	# 1b. Directional raycast mining test: aiming UP into empty sky must NOT auto-snap to ground below; aiming DOWN hits crust!
	var up_hit := planet.find_mine_target(player.position, Vector2.UP, 220.0)
	var dn_hit := planet.find_mine_target(player.position, Vector2.DOWN, 220.0)
	_chk(up_hit.is_empty(), "Aiming UP into sky must not auto-target ground! got=%s" % str(up_hit))
	_chk(not dn_hit.is_empty(), "Aiming DOWN at crust must hit terrain!")

	# 2. Timed Craft Queue + Cancel Refund + Auto-Docking Fabricator Drones!
	State.add_r("fe", 320); State.add_r("cu", 240); State.add_r("si", 160); State.add_r("ti", 160)
	var fe_before := State.get_r("fe")
	_chk(State.enqueue_craft("drone", "fab_drone"), "Enqueue Drone failed")
	_chk(State.attached_drones == 0 and State.craft_queue.size() == 1, "Craft must be timed (queued), NOT instant!")
	_chk(State.cancel_craft(0) and State.get_r("fe") == fe_before, "Cancel craft refund failed!")
	_chk(_craft_and_finish("drone", "fab_drone") and State.attached_drones == 1, "Craft Drone #1 failed")
	_chk(_craft_and_finish("drone", "fab_drone") and State.attached_drones == 2, "Craft Drone #2 failed")

	# 3. Research + Timed Building Craft -> Stock -> Place -> Salvage Refund Stock -> Wired Local Power Grid
	_chk(State.research("power_grid"), "Research power_grid failed")
	_chk(State.research("cave_logistics"), "Research cave_logistics failed")
	_chk(State.research("smelting_booster"), "Research smelting_booster failed")
	for b_req in ["solar", "tesla", "battery", "drill", "depot", "smelter"]:
		_chk(_craft_and_finish("building", b_req) and State.get_stock(b_req) == 1, "Craft building %s failed" % b_req)

	var p_sol: Vector2 = planet.get_pose_at(SphericalPlanet.SPAWN_COL - 6, SphericalPlanet.ROWS - 2)["pos"]
	var p_tes: Vector2 = planet.get_pose_at(SphericalPlanet.SPAWN_COL + 8, SphericalPlanet.ROWS - 2)["pos"]
	var p_bat: Vector2 = planet.get_pose_at(SphericalPlanet.SPAWN_COL, SphericalPlanet.ROWS - 2)["pos"]
	_chk(grid.try_place_at("solar", p_sol) and State.get_stock("solar") == 0, "Place Solar failed")
	# Double-tap delete check: 1st tap only arms, 2nd tap deletes & refunds stock!
	_chk(grid.try_double_tap_salvage(p_sol) and grid.buildings.size() == 1 and grid.salvage_armed_uid > 0, "1st tap in delete mode must only arm, not delete!")
	_chk(grid.try_double_tap_salvage(p_sol) and grid.buildings.is_empty() and State.get_stock("solar") == 1, "2nd tap in delete mode must delete & refund stock!")
	_chk(grid.try_place_at("solar", p_sol) and State.get_stock("solar") == 0, "Re-place Solar failed")
	var bsnap: Dictionary = grid.get_building_snap(int(grid.buildings[0]["uid"]))
	_chk(String(bsnap.get("id", "")) == "solar", "Building inspector snap failed!")
	# Wide pinch zoom bounds check (close-up to full planet!)
	adjust_zoom(5.0)
	_chk(user_zoom >= 2.5, "Max close-up zoom too small: %.2f" % user_zoom)
	adjust_zoom(0.01)
	_chk(user_zoom <= 0.08, "Min full-planet zoom too large: %.3f" % user_zoom)
	set_zoom_val(0.88)
	grid._solve_power(0.1)
	_chk(State.pwr_prod <= 0.1, "Unwired Solar must report 0W!")
	_chk(grid.try_place_at("tesla", p_tes), "Place Tesla failed")
	_chk(grid.try_place_at("battery", p_bat), "Place Battery failed")
	_chk(grid.toggle_wire(int(grid.buildings[0]["uid"]), int(grid.buildings[1]["uid"])), "Wire Solar<->Tesla failed")
	_chk(grid.toggle_wire(int(grid.buildings[2]["uid"]), int(grid.buildings[1]["uid"])), "Wire Battery<->Tesla failed")
	grid._solve_power(0.5)
	_chk(State.pwr_prod > 30.0 and State.active_teslas == 1, "Wired Solar+Tesla failed")
	_chk(State.tut_step >= 6, "Interactive tutorial did not advance to step 6! step=%d" % State.tut_step)

	# 4. Indestructible Drill-Only Bedrock Nodes + Free-Linking Conveyor Tubes (length-scaled Iron cost + red shortage!)
	_chk(planet.drill_nodes.size() >= 8, "Missing bedrock drill nodes!")
	var dn_pos: Vector2 = planet.drill_nodes[1]["pos"] # Starter Fe bedrock node at SPAWN_COL + 12 (inside Tesla dome!)
	_chk(not planet.damage_target({"kind": "drill_node", "pos": dn_pos, "ore": "fe"}, 999.0), "Player hand laser must NOT break bedrock drill nodes!")
	var ordinary_pos: Vector2 = planet.get_pose_at(SphericalPlanet.SPAWN_COL + 2, SphericalPlanet.ROWS - 2)["pos"]
	_chk(not grid.try_place_at("drill", ordinary_pos), "Drill must NOT be placeable on ordinary rock!")
	_chk(grid.try_place_at("drill", dn_pos), "Place Drill on Bedrock Ore Node failed!")
	_chk(grid.try_place_at("depot", planet.get_pose_at(SphericalPlanet.SPAWN_COL + 16, SphericalPlanet.ROWS - 2)["pos"]), "Place Depot failed")
	_chk(grid.try_place_at("smelter", planet.get_pose_at(SphericalPlanet.SPAWN_COL + 21, SphericalPlanet.ROWS - 2)["pos"]), "Place Smelter failed")
	var u_drill := int(grid.buildings[3]["uid"])
	var u_depot := int(grid.buildings[4]["uid"])
	var u_smelt := int(grid.buildings[5]["uid"])

	# Verify insufficient Iron blocks conveyor & triggers red split shortage flash!
	var saved_fe := State.get_r("fe")
	State.res["fe"] = 0
	_chk(not grid.toggle_conveyor(u_drill, u_depot) and not grid.conveyor_fail_flash.is_empty(), "Conveyor with 0 Fe must fail & show red shortage flash!")
	State.res["fe"] = saved_fe
	var fe_pre_conv := State.get_r("fe")
	_chk(grid.toggle_conveyor(u_drill, u_depot) and State.get_r("fe") < fe_pre_conv, "Free-link Drill->Depot conveyor failed or didn't cost Fe!")
	_chk(grid.toggle_conveyor(u_depot, u_smelt) and grid.conveyors.size() == 2, "Free-link Depot->Smelter conveyor failed!")
	for _k in range(110): grid._process(0.1)
	_chk(grid.buildings[4]["inv"].size() > 0 or grid.buildings[5]["in_buf"].size() > 0 or grid.buildings[5]["out_buf"].size() > 0, "Free-linked Conveyor pipeline produced nothing!")
	# Regression test for Smelter with 12 Cu: MUST smelt 12 -> 10 Cu and produce wire_cu on VERY FIRST cycle!
	var sm_b: Dictionary = grid.buildings[5]
	sm_b["in_buf"] = {"cu": 12}
	sm_b["out_buf"] = {}
	sm_b["timer"] = 0.0
	for _sm in range(25): grid._process(0.1)
	_chk(int(sm_b["out_buf"].get("wire_cu", 0)) >= 1 and int(sm_b["in_buf"].get("cu", 0)) <= 10,
		"Smelter failed to smelt Cu x12! in=%s out=%s" % [str(sm_b["in_buf"]), str(sm_b["out_buf"])])

	# Nighttime battery test
	planet.sun_angle = PI * 0.5
	grid._solve_power(1.0)
	_chk(State.pwr_prod < 2.0 and float(grid.buildings[3]["pwr_ratio"]) > 0.9, "Battery failed during night!")
	planet.sun_angle = -PI * 0.44

	# 5. Zero-Drag Vacuum Keplerian Orbit Verification (Timed Orbital Booster Craft!)
	State.add_r("plate_fe", 160); State.add_r("wire_cu", 120); State.add_r("wafer_si", 80)
	State.add_r("circuit", 100); State.add_r("alloy", 80); State.add_r("sci_pack", 40)
	_chk(_craft_and_finish("propulsion", "1") and State.propulsion_tier == 1, "Timed Orbital Booster craft failed")
	player.position = Vector2(0.0, -6800.0)
	var vc := sqrt(SphericalPlanet.ORIGIN_GM / 6800.0)
	player.velocity = Vector2(vc, 0.0)
	player.move_input = Vector2.ZERO; player.braking = false
	for _k in range(100): player._physics_process(0.05)
	_chk(absf(player.velocity.length() - vc) < 16.0, "Vacuum Keplerian orbit drifted! %.1f vs %.1f" % [player.velocity.length(), vc])

	# 6. Macro Gantry Printer -> Mass Driver Launch -> 10k Swarm -> Boss Defeat & Victory!
	_chk(State.research("circuits_geo"), "Research circuits_geo failed")
	_chk(State.research("deep_space"), "Research deep_space failed")
	_chk(State.research("macro_swarm"), "Research macro_swarm failed")
	_chk(State.research("megastructures"), "Research megastructures failed")
	_chk(_craft_and_finish("building", "gantry_printer"), "Craft Gantry Printer failed")
	_chk(_craft_and_finish("building", "mass_driver"), "Craft Mass Driver failed")
	_chk(grid.try_place_at("gantry_printer", planet.get_pose_at(SphericalPlanet.SPAWN_COL - 3, SphericalPlanet.ROWS - 2)["pos"]), "Place Gantry Printer failed")
	_chk(grid.try_place_at("mass_driver", planet.get_pose_at(SphericalPlanet.SPAWN_COL + 4, SphericalPlanet.ROWS - 2)["pos"]), "Place Mass Driver failed")
	State.add_r("probe_stock", 2)
	for _k in range(40): grid._process(0.1)
	_chk(State.total_launches >= 1 and State.swarm_fleet >= 6, "Mass Driver failed to launch!")
	for mid in ["elevator", "dyson", "citadel", "warpgate"]:
		_chk(State.build_mega(mid), "Build mega %s failed" % mid)
	swarm.damage_boss(5000.0)
	_chk(State.boss_dead and State.game_won, "Victory trigger failed")

	if _test_failed:
		print("TESTS FAILED!")
		get_tree().quit(1)
		return
	print("ALL V4 JP CRAFT-QUEUE + SCREEN-MOVE + TUTORIAL TESTS PASSED! Bldgs=%d Wires=%d Drones=%d Fleet=%d Launches=%d TutStep=%d" % [
		grid.buildings.size(), State.wire_count, State.attached_drones, State.swarm_fleet, State.total_launches, State.tut_step
	])
	get_tree().quit(0)
