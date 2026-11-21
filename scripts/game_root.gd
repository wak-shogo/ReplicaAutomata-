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

var user_zoom: float = 1.0
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
	grid.depot_opened.connect(hud.open_depot)

	player.spawn_north_pole()
	cam.position = player.position + Vector2(0, -45)
	cam.zoom = Vector2(0.88, 0.88)

	if "--run-tests" in OS.get_cmdline_args() or "--run-tests" in OS.get_cmdline_user_args():
		call_deferred("_run_tests")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			user_zoom = clampf(user_zoom * 1.12, 0.35, 1.8)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			user_zoom = clampf(user_zoom / 1.12, 0.35, 1.8)

func _process(delta: float) -> void:
	if State.orbit_view:
		cam.position = cam.position.lerp(Vector2.ZERO, minf(1.0, delta * 5.0))
		var vp := get_viewport_rect().size
		var fit := minf(vp.x, vp.y) / 17000.0
		cam.zoom = cam.zoom.lerp(Vector2(fit, fit), minf(1.0, delta * 5.0))
	else:
		# Offset slightly skyward when on surface so player sees both subterranean caves AND upper sky!
		var up := player.position.normalized() if player.position.length() > 1.0 else Vector2.UP
		var target_c := player.position + (up * 35.0 if player.get_altitude() < 260.0 else Vector2.ZERO)
		cam.position = cam.position.lerp(target_c, minf(1.0, delta * 7.5))
		var alt := maxf(0.0, player.get_altitude())
		var az := lerpf(0.88, 0.44, clampf(alt / 3200.0, 0.0, 1.0)) * user_zoom
		cam.zoom = cam.zoom.lerp(Vector2(az, az), minf(1.0, delta * 4.5))

	if OS.has_feature("web"):
		_tel_t += delta
		if _tel_t >= 0.12:
			_tel_t = 0.0
			_publish_tel()

func _publish_tel() -> void:
	var d := {
		"px": int(round(player.position.x)), "py": int(round(player.position.y)),
		"r": int(round(player.position.length())), "alt": int(round(player.get_altitude())),
		"vel": int(round(player.velocity.length())), "grav": snappedf(player.local_g, 0.02),
		"drones": State.attached_drones, "prop": State.propulsion_tier,
		"fe": State.get_r("fe"), "cu": State.get_r("cu"), "si": State.get_r("si"), "ti": State.get_r("ti"),
		"plate_fe": State.get_r("plate_fe"), "wire_cu": State.get_r("wire_cu"), "wafer_si": State.get_r("wafer_si"),
		"circuit": State.get_r("circuit"), "alloy": State.get_r("alloy"),
		"pwr_prod": int(round(State.pwr_prod)), "pwr_use": int(round(State.pwr_use)),
		"pwr_stored": int(round(State.pwr_stored)), "wires": State.wire_count, "teslas_on": State.active_teslas,
		"bldg": grid.buildings.size(), "fleet": State.swarm_fleet, "launches": State.total_launches,
		"techs": State.unlocked_techs, "tool": State.selected_tool, "modal": hud.modal,
		"orbit": State.orbit_view, "won": State.game_won,
	}
	JavaScriptBridge.eval("window.__star_tel = " + JSON.stringify(d) + ";")

func _chk(ok: bool, msg: String) -> void:
	if not ok:
		_test_failed = true
		push_error("FAIL: " + msg)
		print("FAIL: " + msg)

func _run_tests() -> void:
	print("=== STAR REPLICA: AUTOMA (V3 CONCEPT REBUILD) HEADLESS TESTS ===")
	_chk(grid.buildings.is_empty(), "Must start with 0 buildings")
	_chk(State.attached_drones == 0 and State.propulsion_tier == 0, "Must start with 0 drones & tier 0")
	_chk(Sfx.preset_count() >= 13, "Missing Sfx presets")
	_chk(ArtReg.tex.size() >= 28, "Missing HD-2D sprites")

	# 1. Organic 24px voxel digging & docking Fabricator Drones!
	State.add_r("fe", 300); State.add_r("cu", 240); State.add_r("si", 160); State.add_r("ti", 160)
	_chk(State.dock_new_drone() and State.attached_drones == 1, "Dock Drone #1 failed")
	_chk(State.dock_new_drone() and State.attached_drones == 2, "Dock Drone #2 failed")

	# 2. Wired Local Power Grid + Night Battery
	_chk(State.research("power_grid"), "Research power_grid failed")
	_chk(State.research("cave_logistics"), "Research cave_logistics failed")
	_chk(State.research("smelting_booster"), "Research smelting_booster failed")
	var p_sol: Vector2 = planet.get_pose_at(SphericalPlanet.SPAWN_COL - 6, SphericalPlanet.ROWS - 2)["pos"]
	var p_tes: Vector2 = planet.get_pose_at(SphericalPlanet.SPAWN_COL, SphericalPlanet.ROWS - 2)["pos"]
	var p_bat: Vector2 = planet.get_pose_at(SphericalPlanet.SPAWN_COL - 3, SphericalPlanet.ROWS - 2)["pos"]
	_chk(grid.try_place_at("solar", p_sol), "Place Solar failed")
	grid._solve_power(0.1)
	_chk(State.pwr_prod <= 0.1, "Unwired Solar must report 0W!")
	_chk(grid.try_place_at("tesla", p_tes), "Place Tesla failed")
	_chk(grid.try_place_at("battery", p_bat), "Place Battery failed")
	_chk(grid.toggle_wire(int(grid.buildings[0]["uid"]), int(grid.buildings[1]["uid"])), "Wire Solar<->Tesla failed")
	_chk(grid.toggle_wire(int(grid.buildings[2]["uid"]), int(grid.buildings[1]["uid"])), "Wire Battery<->Tesla failed")
	grid._solve_power(0.5)
	_chk(State.pwr_prod > 30.0 and State.active_teslas == 1, "Wired Solar+Tesla failed")

	# 3. Physical Connected Pipeline: Drill -> Belt -> Depot (4-way filter) -> Smelter + Night Survival!
	_chk(grid.try_place_at("drill", planet.get_pose_at(SphericalPlanet.SPAWN_COL + 3, SphericalPlanet.ROWS - 2)["pos"]), "Place Drill failed")
	_chk(grid.try_place_at("belt", planet.get_pose_at(SphericalPlanet.SPAWN_COL + 6, SphericalPlanet.ROWS - 2)["pos"]), "Place Belt failed")
	_chk(grid.try_place_at("depot", planet.get_pose_at(SphericalPlanet.SPAWN_COL + 10, SphericalPlanet.ROWS - 2)["pos"]), "Place Depot failed")
	_chk(grid.try_place_at("smelter", planet.get_pose_at(SphericalPlanet.SPAWN_COL + 14, SphericalPlanet.ROWS - 2)["pos"]), "Place Smelter failed")
	grid.depot_cycle_filter(int(grid.buildings[5]["uid"]), "right")
	for _k in range(100): grid._process(0.1)
	_chk(grid.buildings[5]["inv"].size() > 0 or grid.buildings[6]["in_buf"].size() > 0 or grid.buildings[6]["out_buf"].size() > 0, "Logistics pipeline produced nothing")

	# Nighttime battery test
	planet.sun_angle = PI * 0.5
	grid._solve_power(1.0)
	_chk(State.pwr_prod < 2.0 and float(grid.buildings[3]["pwr_ratio"]) > 0.9, "Battery failed during night!")
	planet.sun_angle = -PI * 0.44

	# 4. Zero-Drag Vacuum Keplerian Orbit Verification
	State.add_r("plate_fe", 160); State.add_r("wire_cu", 120); State.add_r("wafer_si", 80)
	State.add_r("circuit", 100); State.add_r("alloy", 80); State.add_r("sci_pack", 40)
	_chk(State.upgrade_propulsion() and State.propulsion_tier == 1, "Orbital Booster upgrade failed")
	player.position = Vector2(0.0, -6800.0)
	var vc := sqrt(SphericalPlanet.ORIGIN_GM / 6800.0)
	player.velocity = Vector2(vc, 0.0)
	player.move_input = Vector2.ZERO; player.braking = false
	for _k in range(100): player._physics_process(0.05)
	_chk(absf(player.velocity.length() - vc) < 16.0, "Vacuum Keplerian orbit drifted! %.1f vs %.1f" % [player.velocity.length(), vc])

	# 5. Macro Gantry Printer -> Mass Driver Launch -> 10k Swarm -> Boss Defeat & Victory!
	_chk(State.research("circuits_geo"), "Research circuits_geo failed")
	_chk(State.research("deep_space"), "Research deep_space failed")
	_chk(State.research("macro_swarm"), "Research macro_swarm failed")
	_chk(State.research("megastructures"), "Research megastructures failed")
	_chk(grid.try_place_at("gantry_printer", planet.get_pose_at(SphericalPlanet.SPAWN_COL - 12, SphericalPlanet.ROWS - 2)["pos"]), "Place Gantry Printer failed")
	_chk(grid.try_place_at("mass_driver", planet.get_pose_at(SphericalPlanet.SPAWN_COL - 18, SphericalPlanet.ROWS - 2)["pos"]), "Place Mass Driver failed")
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
	print("ALL V3 CONCEPT REBUILD TESTS PASSED! Bldgs=%d Wires=%d Drones=%d Fleet=%d Launches=%d" % [
		grid.buildings.size(), State.wire_count, State.attached_drones, State.swarm_fleet, State.total_launches
	])
	get_tree().quit(0)
