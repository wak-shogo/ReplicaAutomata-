extends Node2D

# ==============================================================================
# STAR REPLICA: AUTOMA - SPHERICAL OPEN-WORLD MAIN CONTROLLER & TEST HARNESS
# ==============================================================================

@onready var world: PlanetWorld = $PlanetWorld
@onready var factory: FactorySim = $FactorySim
@onready var swarm: SwarmSimulation = $SwarmSimulation
@onready var player: PlayerUnit = $Player
@onready var camera: Camera2D = $Camera2D
@onready var hud: GameHUD = $HUD

var target_zoom: float = 0.92
var orbit_overview: bool = false
var is_automated_run: bool = false

func _ready() -> void:
	world.generate_world(42077)
	factory.setup(world, swarm, player)
	swarm.setup(world)
	player.setup(world, factory)
	hud.setup(player, world, swarm)

	hud.orbit_cam_toggled.connect(func(): orbit_overview = hud.orbit_cam_active)
	hud.save_requested.connect(func(): SaveManager.save_game(world, factory, player))
	hud.reset_requested.connect(_on_reset_requested)
	hud.brake_requested.connect(func(): player.trigger_brake())

	var args = OS.get_cmdline_args() + OS.get_cmdline_user_args()
	if "--run-tests" in args:
		is_automated_run = true
		call_deferred("_run_automated_suite")
	elif "--capture-shots" in args:
		is_automated_run = true
		call_deferred("_capture_visual_shots")
	else:
		if SaveManager.load_game(factory, player):
			swarm.sync_to_game_state(GameState.fleet_count)
		else:
			_start_fresh_landing()

func _start_fresh_landing() -> void:
	GameState.reset_state()
	world.generate_world(42077)
	factory.clear_factory()
	swarm.reset_swarm()
	player.reset_to_spawn()
	GameState.set_tool("pick")
	if camera:
		camera.position = player.position
		camera.zoom = Vector2(target_zoom, target_zoom)
	GameState.emit_signal("log_event", "Grounded on Origin-Prime. Hold [A] to mine, [Y] Printer.", "info")

func _on_reset_requested() -> void:
	SaveManager.delete_save()
	_start_fresh_landing()
	AudioSynth.play_synth("pop")

func _process(delta: float) -> void:
	if not is_automated_run:
		_update_camera(delta)

func _update_camera(delta: float) -> void:
	var win_sz = Vector2(DisplayServer.window_get_size())
	var narrow_boost = 0.78 if win_sz.x < win_sz.y else 1.0
	var goal_pos = player.position
	var goal_z = target_zoom * narrow_boost
	if orbit_overview:
		goal_pos = Vector2.ZERO
		goal_z = 0.052 * narrow_boost
	elif player.position.length() > PlanetWorld.R_ATMOS_OUTER:
		goal_z = 0.42 * narrow_boost
	elif player.position.length() > PlanetWorld.R_SURFACE + 180.0:
		goal_z = 0.68 * narrow_boost
	camera.position = camera.position.lerp(goal_pos, clampf(7.5 * delta, 0.0, 1.0))
	var nz = lerpf(camera.zoom.x, goal_z, clampf(7.5 * delta, 0.0, 1.0))
	camera.zoom = Vector2(nz, nz)

func _unhandled_input(event: InputEvent) -> void:
	if is_automated_run:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			if not hud.is_blocking_world_input():
				target_zoom = clampf(target_zoom + 0.12, 0.25, 1.65)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			if not hud.is_blocking_world_input():
				target_zoom = clampf(target_zoom - 0.12, 0.25, 1.65)
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if not hud.is_blocking_world_input():
				var wpos = get_global_mouse_position()
				if GameState.selected_tool != "pick":
					factory.try_handle_click_at(wpos)
				else:
					player.trigger_primary_action()

# ==============================================================================
# AUTOMATED VERIFICATION SUITE (--run-tests)
# ==============================================================================
func _run_automated_suite() -> void:
	print("=== SPHERICAL OPEN-WORLD TEST SUITE START ===")
	var failures: Array[String] = []

	_start_fresh_landing()
	await get_tree().process_frame
	if GameState.drones != 0 or GameState.fleet_count != 0 or GameState.fe != 0:
		failures.append("Phase 1 clean slate failed")

	# Radial mining on 10x spherical ore vein around SPAWN_SECTOR = 270
	var hit = world.damage_cell(268, 38, 100.0, true)
	if not hit["destroyed"] or GameState.fe <= 0:
		failures.append("Spherical cell mining failed")

	# Grounded check: Engine Tier 0 cannot fly off planet surface (R_SURFACE = 6400)
	player.reset_to_spawn()
	player.position = Vector2(0.0, -(PlanetWorld.R_SURFACE + 120.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	if player.position.length() > PlanetWorld.R_SURFACE + 28.0:
		failures.append("Grounded Seed Unit escaped planet without printing Thruster Mk-I")

	# Spherical surface zero-drift clamp
	player.reset_to_spawn()
	player.velocity = Vector2(200.0, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	if player.velocity.length() > 1.0:
		failures.append("Surface anchor drifted")

	# Print Thruster Engine Mk-I via Onboard 3D Printer [Y] -> [Y] (2 clicks!), verify slow ~58s Atmos Climb speed = 62px/s
	GameState.add_res("fe", 40)
	GameState.add_res("cu", 20)
	hud._trigger_abxy("Y")
	if hud.menu_state != GameHUD.MenuState.CMD_TREE:
		failures.append("Y failed to open Onboard Printer tree")
	hud._trigger_abxy("Y") # Slot 0 = PRINT Thruster Mk-I
	if GameState.engine_tier != 1 or not is_equal_approx(GameState.get_flight_speed(), 62.0):
		failures.append("Onboard Printer Engine Mk-I craft failed")

	# Open-world space pure uniform linear motion (> R_ATMOS_OUTER = 10000) capped by engine speed
	player.position = Vector2(12800.0, -900.0)
	player.velocity = Vector2(55.0, -15.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	if player.velocity.distance_to(Vector2(55.0, -15.0)) > 1.0:
		failures.append("Open-space inertial flight drifted")
	player.reset_to_spawn()

	# 2-click ABXY Build Tree verification (Click 1: X -> BUILD_TREE, Click 2: Y -> Drill -> FIELD)
	hud._trigger_abxy("X")
	if hud.menu_state != GameHUD.MenuState.BUILD_TREE:
		failures.append("X failed to open 2-click Build Tree")
	hud._trigger_abxy("Y") # Pick Slot 1 (Mining Drill) -> back to FIELD in 2 clicks!
	if GameState.selected_tool != "drill" or hud.menu_state != GameHUD.MenuState.FIELD:
		failures.append("2-click Drill selection via ABXY failed")
	hud._trigger_abxy("Y")
	if hud.menu_state != GameHUD.MenuState.CMD_TREE:
		failures.append("Y failed to open 2-click Printer/Cmd Tree")
	hud._trigger_abxy("B")
	if hud.menu_state != GameHUD.MenuState.FIELD:
		failures.append("B failed to close Tree")

	# Drone craft & 10x spherical factory build around globe
	GameState.add_res("fe", 650)
	GameState.add_res("cu", 320)
	GameState.add_res("si", 220)
	GameState.add_res("ti", 150)
	for _i in range(6):
		if not GameState.try_craft_drone():
			failures.append("Drone craft failed")

	var plan = [
		["drill", 267, 38],
		["lift", 273, 38],
		["lift", 273, 39],
		["belt", 273, PlanetWorld.LAYERS],
		["depot", 269, PlanetWorld.LAYERS],
		["smelter", 274, PlanetWorld.LAYERS],
		["assembler", 276, PlanetWorld.LAYERS],
		["printer", 278, PlanetWorld.LAYERS],
		["mass_driver", 281, PlanetWorld.LAYERS],
		["solar", 266, PlanetWorld.LAYERS],
		["turret", 265, PlanetWorld.LAYERS],
	]
	for item in plan:
		if not factory.try_place_building(item[0], item[1], item[2]):
			failures.append("Failed placing %s at (%d,%d)" % [item[0], item[1], item[2]])

	GameState.add_res("plate_fe", 40)
	GameState.add_res("circuit", 20)
	GameState.add_res("probe_stock", 2)
	for _s in range(110):
		await get_tree().process_frame
		factory._process(0.05)
		swarm._process(0.05)
		world._process(0.05)

	if GameState.total_launches < 1 or GameState.fleet_count < 1:
		failures.append("Mass Driver launch into orbit failed")

	GameState.add_fleet_units(1200)
	swarm.sync_to_game_state(GameState.fleet_count)
	GameState.set_doctrine(GameState.Doctrine.ASSAULT)
	for _s in range(25):
		swarm._process(0.05)
	if swarm.f_active < 1200:
		failures.append("Swarm MultiMesh scaling failed")

	if failures.is_empty():
		print("ALL SPHERICAL OPEN-WORLD TESTS PASSED! Launches=%d Fleet=%d Drones=%d Buildings=%d" % [
			GameState.total_launches, GameState.fleet_count, GameState.drones, factory.buildings.size()
		])
	else:
		for f in failures:
			push_error("TEST FAILURE: " + f)
		print("TESTS FAILED (%d)" % failures.size())

	get_tree().quit(0 if failures.is_empty() else 1)

# ==============================================================================
# VISUAL SCREENSHOT CAPTURE (--capture-shots)
# ==============================================================================
func _capture_visual_shots() -> void:
	var out_dir = "C:/Users/wakazaki shogo/.gemini/antigravity/brain/a952e86c-2824-4a0b-8f37-837ef56179e4/scratch"
	DirAccess.make_dir_recursive_absolute(out_dir)

	# Shot 1: Spherical Landing (1600x900 Desktop - Zero Station, Zero Clutter)
	_start_fresh_landing()
	camera.position = player.position + Vector2(0, 215)
	camera.zoom = Vector2(0.86, 0.86)
	await _wait_frames(4)
	await _save_shot(out_dir + "/v2_shot1_sphere_landing.png")

	# Shot 2: 2-Click Build Tree Open
	GameState.add_res("fe", 180)
	GameState.add_res("cu", 60)
	GameState.try_craft_drone()
	GameState.try_craft_drone()
	hud._trigger_abxy("X")
	await _wait_frames(3)
	await _save_shot(out_dir + "/v2_shot2_abxy_build_tree.png")
	hud.menu_state = GameHUD.MenuState.FIELD

	# Shot 3: 360-deg 10x Spherical Colony & Curved Surface Factory + Cyan Ghosts
	GameState.add_res("fe", 800); GameState.add_res("cu", 400); GameState.add_res("si", 300); GameState.add_res("ti", 200)
	GameState.add_res("plate_fe", 60); GameState.add_res("circuit", 40)
	for _i in range(4): GameState.try_craft_drone()
	for s in range(267, 276):
		world.damage_cell(s, 38, 999.0, false)
	var layout = [
		["drill", 267, 38], ["lift", 273, 38], ["lift", 273, 39],
		["belt", 273, PlanetWorld.LAYERS], ["depot", 269, PlanetWorld.LAYERS],
		["smelter", 274, PlanetWorld.LAYERS], ["assembler", 276, PlanetWorld.LAYERS],
		["printer", 278, PlanetWorld.LAYERS], ["mass_driver", 281, PlanetWorld.LAYERS],
		["solar", 266, PlanetWorld.LAYERS], ["turret", 265, PlanetWorld.LAYERS],
		["elevator", 285, PlanetWorld.LAYERS],
	]
	for item in layout:
		factory.try_place_building(item[0], item[1], item[2])
	GameState.add_res("probe_stock", 2)
	GameState.set_tool("solar")
	for _k in range(40):
		await get_tree().process_frame
		factory._process(0.05)
		world._process(0.05)
	camera.position = Vector2(560, -6420)
	camera.zoom = Vector2(0.70, 0.70)
	await _wait_frames(3)
	await _save_shot(out_dir + "/v2_shot3_spherical_factory.png")

	# Shot 4: Open-World Cosmic View + 10x Spherical Globe + 1,500 Swarm Battle
	GameState.add_fleet_units(1500)
	swarm.sync_to_game_state(GameState.fleet_count)
	GameState.set_doctrine(GameState.Doctrine.ASSAULT)
	for _s in range(36):
		await get_tree().process_frame
		swarm._process(0.05)
	GameState.set_tool("pick")
	camera.position = Vector2(5200, -7800)
	camera.zoom = Vector2(0.055, 0.055)
	await _wait_frames(3)
	await _save_shot(out_dir + "/v2_shot4_open_world_orbit.png")

	# Shot 5: 3x High-DPI Mobile Chrome Simulation (1080x2400)
	get_window().size = Vector2i(1080, 2400)
	await _wait_frames(4)
	hud._on_viewport_resized()
	camera.position = Vector2(0, -6220)
	camera.zoom = Vector2(0.68, 0.68)
	await _wait_frames(4)
	await _save_shot(out_dir + "/v2_shot5_mobile_1080x2400.png")

	# Shot 6: High-DPI Mobile Command Tree (CMD_ROOT)
	hud._trigger_abxy("Y")
	await _wait_frames(4)
	await _save_shot(out_dir + "/v2_shot6_mobile_cmd_tree.png")

	print("Captured all 6 v2 spherical verification screenshots!")
	get_tree().quit(0)

func _wait_frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func _save_shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img = get_viewport().get_texture().get_image()
	img.save_png(path)
