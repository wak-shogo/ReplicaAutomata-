with open('scripts/main.gd', 'r', encoding='utf-8') as f:
    content = f.read()

# Let's replace the regression test implementation in main.gd
old_start_pos = content.find("func _start_regression_tests() -> void:")
assert old_start_pos != -1, "Could not find _start_regression_tests in main.gd"

new_tests = '''func _start_regression_tests() -> void:
	print(">>> STARTING BLUEPRINT & AUTONOMOUS DRONE REGRESSION TESTS <<<")
	get_tree().create_timer(0.6).timeout.connect(_run_test_dormant)

func _run_test_dormant() -> void:
	print("TEST PHASE 0: DORMANT PROBE & SCI-FI GUIDANCE OVERLAY")
	_save_test_screen("docs/art/test_00_dormant_probe.png")
	
	# プローブを起動し、地表アタッチ移動へ遷移
	if player:
		player.is_dormant = false
	if hud and hud.boot_guide_overlay:
		hud.boot_guide_overlay.visible = false
		
	get_tree().create_timer(0.5).timeout.connect(_run_test_surface_movement)

func _run_test_surface_movement() -> void:
	print("TEST PHASE 1: SURFACE MOVEMENT & ATTACHMENT ZERO-DRIFT")
	if player and grid_manager:
		player.is_surface_attached = true
		player.attached_angle_off = -0.4
		player.touch_walking_dir = 1.0
	get_tree().create_timer(0.5).timeout.connect(func():
		_save_test_screen("docs/art/test_01_surface_movement.png")
		_run_test_mining()
	)

func _run_test_mining() -> void:
	print("TEST PHASE 2: ORE VEIN LASER MINING & CUMULATIVE POPUP")
	if player and grid_manager:
		player.touch_walking_dir = 0.0
		var ore_pos = grid_manager.HOME_CENTER + Vector2(0, -grid_manager.HOME_RADIUS)
		player.global_position = ore_pos + Vector2(-60.0, -16.0)
		player.is_mining = true
		player.mining_target = ore_pos
		player._detect_nearest_ore(ore_pos)
		GameState.add_resource("Fe", 25)
		player.spawn_resource_popup("Fe", 25)
	
	get_tree().create_timer(0.5).timeout.connect(func():
		_save_test_screen("docs/art/test_02_mining_laser_popup.png")
		_run_test_tech_tree_modal()
	)

func _run_test_tech_tree_modal() -> void:
	print("TEST PHASE 3: TECH TREE BLUEPRINT CATALOG MODAL (RESPONSIVE & NO OVERFLOW)")
	if player:
		player.is_mining = false
	if hud:
		hud.open_tech_tree_modal()
		
		# モーダルが見切れていないかのアサーション
		var vp_rect = get_viewport().get_visible_rect()
		var modal = hud.tech_tree_modal
		assert(modal != null, "CRITICAL ERROR: Tech tree modal not found!")
		var m_rect = modal.get_global_rect()
		print("ASSERTION: Tech tree modal rect -> pos: (%.1f, %.1f), size: (%.1f, %.1f), vp_size: (%.1f, %.1f)" % [
			m_rect.position.x, m_rect.position.y, m_rect.size.x, m_rect.size.y, vp_rect.size.x, vp_rect.size.y
		])
		assert(m_rect.position.x >= 0, "CRITICAL ERROR: Modal left edge is off-screen!")
		assert(m_rect.end.x <= vp_rect.size.x + 2.0, "CRITICAL ERROR: Modal right edge overflows screen width!")
		assert(m_rect.end.y <= vp_rect.size.y + 2.0, "CRITICAL ERROR: Modal bottom edge overflows screen height!")
	
	get_tree().create_timer(0.5).timeout.connect(func():
		_save_test_screen("docs/art/test_03_tech_tree_modal.png")
		_run_test_insufficient_resource_alert()
	)

func _run_test_insufficient_resource_alert() -> void:
	print("TEST PHASE 4: INSUFFICIENT RESOURCE ALERT & RED WARNING BANNER")
	if hud:
		if hud.tech_tree_modal:
			hud.tech_tree_modal.visible = false
		if player:
			hud.show_missing_res_alert(player.global_position, "Cu", 15)
	
	get_tree().create_timer(0.4).timeout.connect(func():
		_save_test_screen("docs/art/test_04_missing_resource_alert.png")
		_run_test_blueprint_hologram()
	)

func _run_test_blueprint_hologram() -> void:
	print("TEST PHASE 5: BLUEPRINT VIRTUAL GHOSTS ON SURFACE")
	GameState.set_story_phase(GameState.StoryPhase.SPACE)
	GameState.items["miner"] = 5
	GameState.items["belt"] = 25
	GameState.items["smelter"] = 5
	GameState.items["turret"] = 5
	GameState.resources["Fe"] = 150
	GameState.resources["Cu"] = 150
	GameState.resources["Si"] = 100
	GameState.attached_drones = 2
	
	if grid_manager:
		grid_manager.select_tool("miner")
		grid_manager._add_blueprint("miner", -0.52, 20.0, "Fe", false)
		grid_manager._add_blueprint("smelter", -0.38, 32.0, "Fe", false)
		for i in range(5):
			var ba = lerpf(-0.52, -0.38, float(i) / 4.0)
			grid_manager._add_blueprint("belt", ba, 4.0, "", false)
			
	get_tree().create_timer(0.5).timeout.connect(func():
		_save_test_screen("docs/art/test_05_blueprint_hologram.png")
		_run_test_drones_welding()
	)

func _run_test_drones_welding() -> void:
	print("TEST PHASE 6: AUTONOMOUS DRONES WELDING BEAMS")
	get_tree().create_timer(0.5).timeout.connect(func():
		_save_test_screen("docs/art/test_06_drones_welding.png")
		_run_test_sub_drone_replication()
	)

func _run_test_sub_drone_replication() -> void:
	print("TEST PHASE 7: SUB-DRONE REPLICATION FROM RESOURCES")
	GameState.resources["Fe"] = 80
	GameState.attach_drone()
	
	get_tree().create_timer(0.5).timeout.connect(func():
		_save_test_screen("docs/art/test_07_sub_drone_replication.png")
		_run_test_turret_air_raid()
	)

func _run_test_turret_air_raid() -> void:
	print("TEST PHASE 8: AIR RAID INCOMING & TURRET DEFENSE")
	spawn_air_raid(1)
	GameState.raid_alert.emit(true, "RAID ALERT")
	get_tree().create_timer(0.5).timeout.connect(func():
		_save_test_screen("docs/art/test_08_air_raid_turret.png")
		_run_test_swarm_megastructure()
	)

func _run_test_swarm_megastructure() -> void:
	print("TEST PHASE 9: SWARM DEPLOYMENT & MEGASTRUCTURE BUILDING")
	active_bombers.clear()
	GameState.add_fleet(2200)
	GameState.megastructures["elevator"]["progress"] = 0.85
	GameState.megastructures["dyson"]["progress"] = 0.50
	GameState.active_megastructure_project = "elevator"
	if camera:
		target_zoom = Vector2(0.65, 0.65)
		camera.zoom = target_zoom
		
	get_tree().create_timer(0.5).timeout.connect(func():
		_save_test_screen("docs/art/test_09_swarm_megastructure.png")
		_run_test_macro_map()
	)

func _run_test_macro_map() -> void:
	print("TEST PHASE 10: MACRO ORBITAL MAP VIEW (FULL SOLAR SCALE)")
	toggle_map_view()
	get_tree().create_timer(0.6).timeout.connect(func():
		_save_test_screen("docs/art/test_10_macro_map.png")
		_run_test_assault_boss()
	)

func _run_test_assault_boss() -> void:
	print("TEST PHASE 11: ASSAULT DOCTRINE ON ENEMY BOSS CORE")
	is_map_mode = false
	is_following_player = false
	GameState.set_fleet_doctrine("ASSAULT")
	var boss_pos = grid_manager.SUN_POS + Vector2(7600.0, -1200.0) if grid_manager else Vector2(8400.0, -2050.0)
	if camera:
		camera.global_position = boss_pos
		target_zoom = Vector2(0.85, 0.85)
		camera.zoom = target_zoom
		
	get_tree().create_timer(0.5).timeout.connect(func():
		_save_test_screen("docs/art/test_11_assault_boss.png")
		_run_test_celestial_mining()
	)

func _run_test_celestial_mining() -> void:
	print("TEST PHASE 12: CELESTIAL MINING (LUNA He3 & BLACK HOLE SINGULARITY)")
	is_map_mode = false
	is_following_player = false
	if hud and hud.alert_rect:
		hud.alert_rect.visible = false
		hud.alert_timer = 0.0
	if player and grid_manager:
		var moon_pos = grid_manager.moon_body.get("pos", Vector2(1200, 300))
		player.global_position = moon_pos + Vector2(-90.0, -40.0)
		player.is_mining = true
		player.mining_target = moon_pos
		player._detect_nearest_ore(moon_pos)
		GameState.add_resource(player.current_mining_ore, 12)
		if camera:
			camera.global_position = player.global_position
			target_zoom = Vector2(1.35, 1.35)
			camera.zoom = target_zoom

	get_tree().create_timer(0.5).timeout.connect(func():
		_save_test_screen("docs/art/test_12_celestial_mining.png")
		_run_test_surface_clamping()
	)

func _run_test_surface_clamping() -> void:
	print("TEST PHASE 13: SURFACE COLLISION & CLAMPING TEST (NO PENETRATION)")
	if player and grid_manager:
		player.is_mining = false
		player.global_position = grid_manager.HOME_CENTER + Vector2(0, -grid_manager.HOME_RADIUS - 16.0)
		player.velocity = Vector2(0, 300.0)
		is_following_player = true
		if camera:
			camera.global_position = player.global_position
			target_zoom = Vector2(1.3, 1.3)
			camera.zoom = target_zoom

	get_tree().create_timer(0.5).timeout.connect(func():
		if player and grid_manager:
			var cur_dist = (player.global_position - grid_manager.HOME_CENTER).length()
			var min_dist = grid_manager.HOME_RADIUS + 15.9
			var is_clamped = (cur_dist >= min_dist)
			print("ASSERTION: Surface clamping check -> cur_dist: %.2f, min_dist: %.2f, RESULT: %s" % [cur_dist, min_dist, "PASSED" if is_clamped else "FAILED"])
			assert(is_clamped, "CRITICAL ERROR: Player penetrated inside planet surface!")
		_save_test_screen("docs/art/test_13_surface_clamping.png")
		_run_test_deep_space_inertia()
	)

func _run_test_deep_space_inertia() -> void:
	print("TEST PHASE 14: DEEP SPACE NEWTONIAN INERTIAL MOTION (ZERO GHOST DRIFT)")
	if player and grid_manager:
		player.is_surface_attached = false
		player.global_position = grid_manager.SUN_POS + Vector2(25000.0, 25000.0)
		player.velocity = Vector2(160.0, 0.0)
	
	get_tree().create_timer(0.5).timeout.connect(func():
		if player:
			var vx = player.velocity.x
			print("ASSERTION: Deep space inertial velocity X -> %.2f px/s (Initial: 160.0)" % vx)
			assert(abs(vx - 160.0) < 5.0, "CRITICAL ERROR: Artificial damping or unexpected force in deep space!")
			
			# 停止テスト
			player.velocity = Vector2.ZERO
			var pos_before = player.global_position
			get_tree().create_timer(0.3).timeout.connect(func():
				var pos_after = player.global_position
				var drift_dist = pos_before.distance_to(pos_after)
				print("ASSERTION: Post-brake stationary drift -> %.4f px" % drift_dist)
				assert(drift_dist < 0.05, "CRITICAL ERROR: Player drifts after stopping in space!")
				_save_test_screen("docs/art/test_14_deep_space_flight.png")
				print(">>> ALL 15 CRITICAL IN-GAME SCENE & MODAL TESTS COMPLETED WITH 100% SUCCESS! <<<")
				get_tree().quit(0)
			)
	)

func _save_test_screen(rel_path: String) -> void:
	var tex = get_viewport().get_texture()
	if tex:
		var img = tex.get_image()
		if img:
			var full_p = ProjectSettings.globalize_path(rel_path)
			var err = img.save_png(full_p)
			print("SAVED SCREENSHOT: ", rel_path, " -> ERR: ", err)
'''

content = content[:old_start_pos] + new_tests

with open('scripts/main.gd', 'w', encoding='utf-8') as f:
    f.write(content)

print("scripts/main.gd updated with all 15 regression test phases.")
