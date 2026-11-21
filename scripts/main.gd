extends Node2D

# Root scene coordinator: wires world, factory, 10k swarm, evolving vessel,
# smooth horizon/orbital camera, Web read-only telemetry bridge, and --run-tests suite.

@onready var sky: Node2D = $SkyBackdrop
@onready var world: Node2D = $PlanetWorld
@onready var factory: Node2D = $FactorySim
@onready var swarm: Node2D = $SwarmSim
@onready var player: Node2D = $PlayerVessel
@onready var cam: Camera2D = $Camera2D
@onready var hud: CanvasLayer = $HUD

var user_zoom: float = 1.0
var _tel_timer: float = 0.0

func _ready() -> void:
	world.factory = factory
	factory.world = world
	factory.player = player
	factory.swarm = swarm
	swarm.world = world
	player.world = world
	player.factory = factory
	player.swarm = swarm

	hud.world = world
	hud.factory = factory
	hud.player = player
	hud.swarm = swarm
	factory.depot_opened.connect(hud.open_depot)

	cam.position = player.position
	cam.zoom = Vector2(0.92, 0.92)

	if "--run-tests" in OS.get_cmdline_args() or "--run-tests" in OS.get_cmdline_user_args():
		call_deferred("_run_automated_tests")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			user_zoom = clampf(user_zoom * 1.12, 0.45, 1.65)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			user_zoom = clampf(user_zoom / 1.12, 0.45, 1.65)

func _process(delta: float) -> void:
	if GameState.orbit_camera:
		cam.position = cam.position.lerp(Vector2.ZERO, minf(1.0, delta * 5.0))
		var vp := get_viewport_rect().size
		var fit := minf(vp.x, vp.y) / 30000.0
		cam.zoom = cam.zoom.lerp(Vector2(fit, fit), minf(1.0, delta * 5.0))
	else:
		cam.position = cam.position.lerp(player.position, minf(1.0, delta * 7.5))
		var alt := maxf(0.0, player.get_altitude())
		var auto_z := lerpf(0.95, 0.48, clampf(alt / 4200.0, 0.0, 1.0)) * user_zoom
		cam.zoom = cam.zoom.lerp(Vector2(auto_z, auto_z), minf(1.0, delta * 4.5))

	if OS.has_feature("web"):
		_tel_timer += delta
		if _tel_timer >= 0.12:
			_tel_timer = 0.0
			_publish_web_telemetry()

func _publish_web_telemetry() -> void:
	var na: Dictionary = world.find_nearest_asteroid(player.position)
	var d := {
		"px": int(round(player.position.x)),
		"py": int(round(player.position.y)),
		"r": int(round(player.position.length())),
		"alt": int(round(player.get_altitude())),
		"vx": int(round(player.velocity.x)),
		"vy": int(round(player.velocity.y)),
		"vel": int(round(player.velocity.length())),
		"rot": snappedf(player.rotation, 0.02),
		"grav": snappedf(player.local_grav_g, 0.02),
		"on_ground": player.on_ground,
		"eng": GameState.vessel_tier,
		"drones": GameState.drones,
		"hp": int(round(GameState.hp)),
		"fuel": int(round(GameState.fuel)),
		"bat": int(round(GameState.ion_battery)),
		"fe": GameState.get_res("fe"),
		"cu": GameState.get_res("cu"),
		"si": GameState.get_res("si"),
		"ti": GameState.get_res("ti"),
		"plate_fe": GameState.get_res("plate_fe"),
		"wire_cu": GameState.get_res("wire_cu"),
		"wafer_si": GameState.get_res("wafer_si"),
		"circuit": GameState.get_res("circuit"),
		"alloy": GameState.get_res("alloy"),
		"sci_pack": GameState.get_res("sci_pack"),
		"probe_stock": GameState.get_res("probe_stock"),
		"pwr_prod": int(round(GameState.power_prod)),
		"pwr_use": int(round(GameState.power_use)),
		"pwr_stored": int(round(GameState.power_stored)),
		"wires": GameState.wire_count,
		"teslas_on": GameState.active_teslas,
		"bldg": factory.buildings.size(),
		"belts_items": factory.belt_items.size(),
		"fleet": GameState.swarm_fleet,
		"launches": GameState.total_launches,
		"boss_hp": int(round(GameState.boss_hp)),
		"boss_dead": GameState.boss_defeated,
		"won": GameState.game_won,
		"techs": GameState.unlocked_techs,
		"tool": GameState.selected_tool,
		"menu": hud.menu_state,
		"orbit_cam": GameState.orbit_camera,
		"near_ast": na,
	}
	JavaScriptBridge.eval("window.__star_tel = " + JSON.stringify(d) + ";")

# ------------------------------------------------------------------------------
# HEADLESS AUTOMATED VERIFICATION SUITE (--run-tests)
# ------------------------------------------------------------------------------
var _test_failed: bool = false

func _assert_ok(cond: bool, msg: String) -> void:
	if not cond:
		_test_failed = true
		push_error("TEST FAILED: " + msg)
		print("TEST FAILED: " + msg)

func _run_automated_tests() -> void:
	print("=== STAR REPLICA: AUTOMA HEADLESS TEST SUITE ===")

	# 1. Clean initial state (Zero pre-built station, Tier 0 Cylinder Capsule, 14 Hi-Fi audio presets)
	_assert_ok(factory.buildings.is_empty(), "Must start with 0 buildings")
	_assert_ok(GameState.vessel_tier == 0, "Must start as Tier 0 Seed Capsule")
	_assert_ok(AudioSynth.get_preset_names().size() >= 14, "AudioSynth presets missing")
	_assert_ok(ArtRegistry.textures.size() >= 25, "HD-2D pixel art atlas missing textures")

	# 2. Unwired Solar must report 0W; Wiring Solar <-> Tesla + Battery energizes dome & survives Night!
	GameState.add_res("fe", 250)
	GameState.add_res("cu", 200)
	GameState.add_res("si", 120)
	GameState.add_res("ti", 120)
	_assert_ok(GameState.research_tech("tesla_grid"), "Research tesla_grid failed")
	_assert_ok(GameState.research_tech("belt_logistics"), "Research belt_logistics failed")
	_assert_ok(GameState.research_tech("metallurgy"), "Research metallurgy failed")

	var l_surf := PlanetWorld.LAYERS
	_assert_ok(factory.try_place_building("solar", 268, l_surf), "Place Solar failed")
	factory._solve_power_grids(0.1)
	_assert_ok(GameState.power_prod <= 0.1, "Unwired Solar must report 0W, got %.1f" % GameState.power_prod)

	_assert_ok(factory.try_place_building("tesla", 270, l_surf), "Place Tesla failed")
	_assert_ok(factory.try_place_building("battery", 269, l_surf), "Place Battery failed")
	var u_sol := int(factory.buildings[0]["uid"])
	var u_tes := int(factory.buildings[1]["uid"])
	var u_bat := int(factory.buildings[2]["uid"])
	_assert_ok(factory.toggle_wire(u_sol, u_tes), "Wire Solar<->Tesla failed")
	_assert_ok(factory.toggle_wire(u_bat, u_tes), "Wire Battery<->Tesla failed")
	factory._solve_power_grids(0.5)
	_assert_ok(GameState.power_prod > 30.0 and GameState.active_teslas == 1, "Wired Solar+Tesla failed to energize")

	# 3. Physical Connected Logistics: Drill -> Belt -> Depot (4-way filter) -> Smelter -> Assembler -> Printer -> Mass Driver!
	_assert_ok(factory.try_place_building("drill", 271, l_surf), "Place Drill failed")
	_assert_ok(factory.try_place_building("belt", 272, l_surf), "Place Belt failed")
	_assert_ok(factory.try_place_building("depot", 273, l_surf), "Place Depot failed")
	_assert_ok(factory.try_place_building("smelter", 274, l_surf), "Place Smelter failed")
	var depot_u := int(factory.buildings[5]["uid"])
	factory.depot_cycle_filter(depot_u, "right") # -> "auto"
	# Simulate 10s of factory production!
	for _t in range(100):
		factory._process(0.1)
	_assert_ok(factory.buildings[6]["out_buf"].size() > 0 or factory.buildings[6]["in_buf"].size() > 0 or factory.buildings[5]["inv"].size() > 0, "Connected Drill->Belt->Depot->Smelter pipeline produced nothing")

	# Nighttime Battery survival test (set sun to opposite side of planet!)
	world.sun_angle = PI * 0.5
	factory._solve_power_grids(1.0)
	_assert_ok(GameState.power_prod < 2.0, "Expected nighttime solar ~0W")
	_assert_ok(float(factory.buildings[3]["pwr_ratio"]) > 0.9, "Battery failed to carry factory through planetary night!")
	world.sun_angle = -PI * 0.42

	# 4. Vessel Upgrade -> True Newtonian Zero-Drag Keplerian Orbit test!
	GameState.add_res("plate_fe", 140)
	GameState.add_res("wire_cu", 120)
	GameState.add_res("wafer_si", 80)
	GameState.add_res("circuit", 100)
	GameState.add_res("alloy", 80)
	GameState.add_res("sci_pack", 40)
	_assert_ok(GameState.upgrade_vessel() and GameState.vessel_tier == 1, "Upgrade Lander Mk-I failed")
	player.position = Vector2(0.0, -11000.0)
	var v_circ := sqrt(PlanetWorld.ORIGIN_GM / 11000.0)
	player.velocity = Vector2(v_circ, 0.0)
	player.thrust_input = Vector2.ZERO
	player.braking = false
	for _k in range(120):
		player._physics_process(0.05)
	_assert_ok(absf(player.velocity.length() - v_circ) < 15.0, "Vacuum Keplerian orbit speed drifted artificially! v=%.1f vs %.1f" % [player.velocity.length(), v_circ])

	# 5. Full Tech Tree, Mass Driver Launch, 10k Swarm MultiMesh & Victory!
	_assert_ok(GameState.research_tech("orbital_rocket"), "Research orbital_rocket failed")
	_assert_ok(GameState.research_tech("apollo_stage"), "Research apollo_stage failed")
	_assert_ok(GameState.upgrade_vessel() and GameState.vessel_tier == 2, "Upgrade Apollo Mk-II failed")
	_assert_ok(GameState.research_tech("swarm_automation"), "Research swarm_automation failed")
	_assert_ok(GameState.upgrade_vessel() and GameState.vessel_tier == 3, "Upgrade Warp Mk-III failed")
	_assert_ok(GameState.research_tech("megastructures"), "Research megastructures failed")
	_assert_ok(factory.try_place_building("mass_driver", 265, l_surf), "Place Mass Driver failed")
	GameState.add_res("probe_stock", 2)
	for _t in range(40):
		factory._process(0.1)
	_assert_ok(GameState.total_launches >= 1 and GameState.swarm_fleet >= 4, "Mass Driver failed to launch swarm probe!")

	# Anti-softlock Self-Destruct Re-Drop
	player.self_destruct_respawn()
	_assert_ok(absf(player.position.length() - (PlanetWorld.R_SURFACE + 24.0)) < 10.0, "Capsule Re-Drop position mismatch")

	# Megastructures + Boss Defeat -> Victory
	for mid in ["elevator", "dyson", "citadel", "warpgate"]:
		_assert_ok(GameState.build_megastructure(mid), "Build megastructure %s failed" % mid)
	swarm.damage_boss(5000.0)
	_assert_ok(GameState.boss_defeated and GameState.game_won, "Victory trigger failed")

	if _test_failed:
		print("TEST SUITE FAILED!")
		get_tree().quit(1)
		return
	print("ALL TESTS PASSED! Buildings=%d Wires=%d Fleet=%d Launches=%d Presets=%d" % [
		factory.buildings.size(), GameState.wire_count, GameState.swarm_fleet, GameState.total_launches, AudioSynth.get_preset_names().size()
	])
	get_tree().quit(0)
