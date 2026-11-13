extends Node2D

# ==============================================================================
# STAR REPLICA: AUTOMA - MAIN ENTRY, CAMERA CONTROLLER & VERIFICATION HARNESS
# ==============================================================================

@onready var world: PlanetWorld = $PlanetWorld
@onready var factory: FactorySim = $FactorySim
@onready var swarm: SwarmSimulation = $SwarmSimulation
@onready var player: PlayerUnit = $Player
@onready var camera: Camera2D = $Camera2D
@onready var hud: GameHUD = $HUD

var target_zoom: float = 1.25
var orbit_overview: bool = false
var is_automated_run: bool = false

func _ready() -> void:
	world.generate_world(42077)
	factory.setup(world, swarm, player)
	swarm.setup(world)
	player.setup(world, factory)
	hud.setup(player)

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
	player.position = Vector2(PlanetWorld.SPAWN_COL * PlanetWorld.TILE_SIZE, PlayerUnit.SURFACE_HOVER_Y)
	player.velocity = Vector2.ZERO
	GameState.set_tool("pick")
	GameState.emit_signal("log_event", "Landed as 1 Seed Unit. Hold SPACE or Click ore below to mine!", "info")
	GameState.emit_signal("log_event", "Mine 10 Fe -> Craft 1st Fabricator Drone to unlock Drills & Belts.", "good")

func _on_reset_requested() -> void:
	SaveManager.delete_save()
	_start_fresh_landing()
	AudioSynth.play_synth("pop")

func _process(delta: float) -> void:
	if not is_automated_run:
		_update_camera(delta)

func _update_camera(delta: float) -> void:
	var vp_w = get_viewport().get_visible_rect().size.x
	var mobile_scale = 0.72 if vp_w < 780.0 else 1.0
	var goal_pos = player.position + Vector2(0.0, 28.0)
	var goal_z = target_zoom * mobile_scale
	if orbit_overview:
		goal_pos = Vector2(PlanetWorld.SPAWN_COL * PlanetWorld.TILE_SIZE, -420.0)
		goal_z = 0.52 * mobile_scale
	camera.position = camera.position.lerp(goal_pos, clampf(7.5 * delta, 0.0, 1.0))
	var nz = lerpf(camera.zoom.x, goal_z, clampf(7.5 * delta, 0.0, 1.0))
	camera.zoom = Vector2(nz, nz)

func _unhandled_input(event: InputEvent) -> void:
	if is_automated_run:
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			if not hud.is_blocking_world_input():
				target_zoom = clampf(target_zoom + 0.14, 0.45, 2.1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			if not hud.is_blocking_world_input():
				target_zoom = clampf(target_zoom - 0.14, 0.45, 2.1)
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if not hud.is_blocking_world_input():
				var wpos = get_global_mouse_position()
				if GameState.selected_tool != "pick":
					factory.try_handle_click_at(wpos)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if GameState.selected_tool != "pick":
				GameState.set_tool("pick")
				AudioSynth.play_synth("click")

	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_Q:
				GameState.set_tool("pick")
			KEY_X:
				GameState.set_tool("demolish")
			KEY_B:
				hud.toggle_tech_modal()
			KEY_M:
				orbit_overview = not orbit_overview
				hud.orbit_cam_active = orbit_overview
				hud.refresh_all()
			KEY_R:
				GameState.build_rotation = (GameState.build_rotation + 2) % 4
				AudioSynth.play_synth("click")
			KEY_ESCAPE:
				if hud.tech_modal.visible:
					hud.tech_modal.visible = false
				elif GameState.selected_tool != "pick":
					GameState.set_tool("pick")
			KEY_1: GameState.set_tool("drill")
			KEY_2: GameState.set_tool("belt")
			KEY_3: GameState.set_tool("lift")
			KEY_4: GameState.set_tool("inserter")
			KEY_5: GameState.set_tool("depot")
			KEY_6: GameState.set_tool("smelter")
			KEY_7: GameState.set_tool("assembler")
			KEY_8: GameState.set_tool("printer")
			KEY_9: GameState.set_tool("mass_driver")
			KEY_0: GameState.set_tool("solar")

# ==============================================================================
# AUTOMATED TEST SUITE & VISUAL SCREENSHOT CAPTURE (--run-tests)
# ==============================================================================
func _run_automated_suite() -> void:
	print("=== STAR REPLICA REBUILD TEST SUITE START ===")
	var failures: Array[String] = []

	# 1. Clean-slate initial state check (start with ZERO fleet, ZERO drones)
	_start_fresh_landing()
	await get_tree().process_frame
	if GameState.drones != 0 or GameState.fleet_count != 0 or GameState.fe != 0:
		failures.append("Phase 1 clean slate failed (expected drones=0, fleet=0, fe=0)")

	# 2. Manual mining + cumulative popup verification
	var res_hit = world.damage_tile(39, 1, 100.0, true)
	if not res_hit["destroyed"] or GameState.fe <= 0:
		failures.append("Underground ore tile mining failed")
	if GameState.recent_ore_amount <= 0:
		failures.append("Cumulative player mining counter failed to update")

	# 3. Surface ground physics zero-drift test
	player.position = Vector2(1344.0, PlayerUnit.SURFACE_HOVER_Y)
	player.velocity = Vector2(180.0, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	if player.velocity.length() > 1.0:
		failures.append("Surface zero-drift clamp failed; velocity=%s" % [str(player.velocity)])

	# 4. Space inertial uniform linear motion test
	player.position = Vector2(1344.0, -320.0)
	player.velocity = Vector2(210.0, -40.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	if player.velocity.distance_to(Vector2(210.0, -40.0)) > 1.0:
		failures.append("Space uniform linear motion drifted; velocity=%s" % [str(player.velocity)])
	player.position = Vector2(1344.0, PlayerUnit.SURFACE_HOVER_Y)
	player.velocity = Vector2.ZERO

	# 5. Drone crafting + tier unlock progression
	GameState.add_res("fe", 600)
	GameState.add_res("cu", 300)
	GameState.add_res("si", 200)
	GameState.add_res("ti", 150)
	for _i in range(6):
		if not GameState.try_craft_drone():
			failures.append("Failed crafting fabricator drone #%d" % (GameState.drones + 1))
	if GameState.drones != 6:
		failures.append("Expected 6 drones, got %d" % GameState.drones)

	# 6. Build full underground-to-surface factory & Mass Driver pipeline
	var build_plan = [
		["drill", Vector2i(40, 2)],
		["lift", Vector2i(41, 2)],
		["lift", Vector2i(41, 1)],
		["lift", Vector2i(41, 0)],
		["lift", Vector2i(41, -1)],
		["belt", Vector2i(42, -1)],
		["belt", Vector2i(43, -1)],
		["smelter", Vector2i(44, -2)],
		["assembler", Vector2i(46, -2)],
		["depot", Vector2i(37, -2)],
		["solar", Vector2i(35, -1)],
		["solar", Vector2i(33, -1)],
		["printer", Vector2i(48, -2)],
		["mass_driver", Vector2i(51, -3)],
		["turret", Vector2i(32, -1)],
	]
	for item in build_plan:
		if not factory.try_place_building(item[0], item[1]):
			failures.append("Failed placing building %s at %s" % [item[0], str(item[1])])

	# 7. Missing resource feedback check
	GameState.fe = 1
	GameState.set_tool("mass_driver")
	if factory.try_place_building("mass_driver", Vector2i(26, -3)):
		failures.append("Placed building despite missing resources")

	# 8. Fast-forward factory ticks -> Printer -> Mass Driver Launch -> Swarm growth
	GameState.add_res("fe", 400)
	GameState.add_res("cu", 200)
	GameState.add_res("si", 150)
	GameState.add_res("ti", 100)
	GameState.add_res("plate_fe", 40)
	GameState.add_res("circuit", 20)
	GameState.add_res("probe_stock", 3)

	for _step in range(110):
		await get_tree().process_frame
		factory._process(0.05)
		swarm._process(0.05)
		world._process(0.05)

	if GameState.total_launches < 1 or GameState.fleet_count < 1:
		failures.append("Mass Driver failed to launch replica probes into orbit (launches=%d, fleet=%d)" % [GameState.total_launches, GameState.fleet_count])

	# 9. Test 1,000+ MultiMesh Swarm scaling & Assault combat
	GameState.add_fleet_units(1200)
	swarm.sync_to_game_state(GameState.fleet_count)
	GameState.set_doctrine(GameState.Doctrine.ASSAULT)
	for _s in range(30):
		swarm._process(0.05)
	if swarm.f_active < 1200:
		failures.append("Swarm MultiMesh count mismatch: %d" % swarm.f_active)

	# 10. Save/Load roundtrip
	var pre_fleet = GameState.fleet_count
	if not SaveManager.save_game(world, factory, player):
		failures.append("SaveManager.save_game failed")
	GameState.reset_state()
	if not SaveManager.load_game(factory, player):
		failures.append("SaveManager.load_game failed")
	if GameState.fleet_count != pre_fleet:
		failures.append("Save/Load fleet count mismatch")
	SaveManager.delete_save()

	# Print report
	if failures.is_empty():
		print("ALL TESTS PASSED! Launches=%d Fleet=%d Drones=%d Buildings=%d" % [
			GameState.total_launches, GameState.fleet_count, GameState.drones, factory.buildings.size()
		])
	else:
		for f in failures:
			push_error("TEST FAILURE: " + f)
		print("TESTS FAILED (%d errors)" % failures.size())

	get_tree().quit(0 if failures.is_empty() else 1)

# ==============================================================================
# VISUAL SCREENSHOT CAPTURE ACROSS ALL PHASES (--capture-shots)
# ==============================================================================
func _capture_visual_shots() -> void:
	var out_dir = "C:/Users/wakazaki shogo/.gemini/antigravity/brain/a952e86c-2824-4a0b-8f37-837ef56179e4/scratch"
	DirAccess.make_dir_recursive_absolute(out_dir)

	# Shot 1: Fresh Phase 1 Landing (zero buildings, ore glowing underground, desktop HUD)
	_start_fresh_landing()
	camera.position = player.position + Vector2(0.0, 48.0)
	camera.zoom = Vector2(1.25, 1.25)
	await _wait_frames(4)
	await _save_shot(out_dir + "/shot1_phase1_landing.png")

	# Shot 2: Tech Tree / Blueprint Catalog Modal
	GameState.add_res("fe", 150)
	GameState.add_res("cu", 40)
	GameState.try_craft_drone()
	GameState.try_craft_drone()
	hud.toggle_tech_modal()
	await _wait_frames(3)
	await _save_shot(out_dir + "/shot2_tech_modal.png")
	hud.tech_modal.visible = false

	# Shot 3: Underground-to-Surface Automated Factory + Blueprint Ghosts + Active Launch!
	GameState.add_res("fe", 800)
	GameState.add_res("cu", 400)
	GameState.add_res("si", 300)
	GameState.add_res("ti", 200)
	GameState.add_res("plate_fe", 60)
	GameState.add_res("circuit", 40)
	for _i in range(4):
		GameState.try_craft_drone()

	# Dig vertical shaft & cavern pocket visually around drill
	for r in range(0, 6):
		world.damage_tile(41, r, 999.0, false)
	world.damage_tile(40, 2, 999.0, false)
	world.damage_tile(40, 3, 999.0, false)

	var layout = [
		["drill", Vector2i(39, 2)],
		["lift", Vector2i(41, 3)],
		["lift", Vector2i(41, 2)],
		["lift", Vector2i(41, 1)],
		["lift", Vector2i(41, 0)],
		["lift", Vector2i(41, -1)],
		["belt", Vector2i(42, -1)],
		["belt", Vector2i(43, -1)],
		["smelter", Vector2i(44, -2)],
		["assembler", Vector2i(46, -2)],
		["depot", Vector2i(37, -2)],
		["solar", Vector2i(34, -1)],
		["printer", Vector2i(48, -2)],
		["mass_driver", Vector2i(51, -3)],
		["turret", Vector2i(32, -1)],
	]
	for item in layout:
		factory.try_place_building(item[0], item[1])

	GameState.add_res("probe_stock", 2)
	GameState.set_tool("solar") # Show glowing cyan blueprint ghosts!
	for _k in range(44):
		await get_tree().process_frame
		factory._process(0.05)
		world._process(0.05)

	camera.position = Vector2(1420.0, 20.0)
	camera.zoom = Vector2(1.15, 1.15)
	await _wait_frames(3)
	await _save_shot(out_dir + "/shot3_factory_cross_section.png")

	# Shot 4: Orbit Overview + Mass Driver Launch + 1,500 Swarm Battle
	GameState.add_fleet_units(1500)
	swarm.sync_to_game_state(GameState.fleet_count)
	GameState.set_doctrine(GameState.Doctrine.ASSAULT)
	for _s in range(36):
		await get_tree().process_frame
		swarm._process(0.05)
	camera.position = Vector2(1460.0, -680.0)
	camera.zoom = Vector2(0.55, 0.55)
	GameState.set_tool("pick")
	await _wait_frames(3)
	await _save_shot(out_dir + "/shot4_orbit_swarm_battle.png")

	# Shot 5: Mobile Portrait Responsiveness Check (390x844)
	get_window().size = Vector2i(390, 844)
	await _wait_frames(4)
	hud._on_viewport_resized()
	camera.position = Vector2(1420.0, 20.0)
	camera.zoom = Vector2(0.72, 0.72)
	await _wait_frames(4)
	await _save_shot(out_dir + "/shot5_mobile_portrait.png")

	# Shot 6: Mobile Portrait Tech Modal Check
	hud.toggle_tech_modal()
	await _wait_frames(4)
	await _save_shot(out_dir + "/shot6_mobile_tech_modal.png")

	print("Captured all 6 verification screenshots to " + out_dir)
	get_tree().quit(0)

func _wait_frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func _save_shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img = get_viewport().get_texture().get_image()
	img.save_png(path)
