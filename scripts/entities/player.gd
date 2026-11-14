extends Node2D
class_name PlayerUnit

# ==============================================================================
# STAR REPLICA: AUTOMA - TRUE KEPLERIAN VESSEL PHYSICS & APOLLO EVOLUTION
#   - Cylindrical Starter Capsule -> Apollo Lander/CSM Evolution (Tiers 0..3)
#   - True Spherical Multi-Body Gravity + Zero-Drag Space + Quadratic Atmos Drag
#   - Propellant Fuel + Solar-Recharging Electric Ion Backup (anti-softlock)
#   - Diegetic Fighter-Jet Circular Ship HUD (Left Arc: HP/Shield, Right Arc: Fuel/Bat)
# ==============================================================================

const MAX_SPACE_SPEED: float = 2400.0
const CAP_RADIUS: float = 18.0
const ENGINE_THRUST: Array[float] = [0.0, 340.0, 580.0, 960.0]

var world: PlanetWorld
var factory: Node2D

var velocity: Vector2 = Vector2.ZERO
var is_anchored_surface: bool = true
var is_thrusting: bool = false
var is_ion_thrusting: bool = false
var is_braking: bool = false
var is_mining: bool = false
var mining_target_pos: Vector2 = Vector2.ZERO
var current_g_norm: float = 1.0
var last_net_accel: Vector2 = Vector2.ZERO

var virtual_stick: Vector2 = Vector2.ZERO
var virtual_fire: bool = false
var virtual_brake: bool = false
var mine_cd: float = 0.0
var anim_time: float = 0.0
var impact_flash_t: float = 0.0
var shield_regen_delay: float = 0.0

func setup(p_world: PlanetWorld, p_factory: Node2D = null) -> void:
	world = p_world
	factory = p_factory
	reset_to_surface()

func reset_to_spawn() -> void:
	reset_to_surface()

func reset_to_surface() -> void:
	position = Vector2(0.0, -(PlanetWorld.R_SURFACE + CAP_RADIUS + 2.0))
	velocity = Vector2.ZERO
	rotation = 0.0
	is_anchored_surface = true
	is_thrusting = false
	is_ion_thrusting = false
	is_braking = false
	GameState.player_hp = GameState.player_max_hp
	GameState.player_shield = GameState.player_max_shield
	GameState.player_fuel = GameState.player_max_fuel
	GameState.player_battery = GameState.player_max_battery

func redeploy_capsule() -> void:
	if world:
		world.spawn_spark_burst(position, Color(1.0, 0.55, 0.25), 16)
	AudioSynth.play_synth("explosion")
	reset_to_surface()
	if world:
		world.spawn_world_popup(position + Vector2(0, -34), "CAPSULE REDEPLOYED", Color(0.35, 0.95, 1.0))
	GameState.add_log("Emergency Capsule Redeployed at North Pole Surface!", "warn")
	queue_redraw()

func set_virtual_input(stick_vec: Vector2, firing: bool, braking: bool = false) -> void:
	virtual_stick = stick_vec
	virtual_fire = firing
	virtual_brake = braking

func _read_move_input() -> Vector2:
	var kb = Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): kb.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): kb.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP): kb.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN): kb.y += 1.0
	var joy = Vector2(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
	if joy.length() < 0.22:
		joy = Vector2.ZERO
	var v = kb + joy + virtual_stick
	if v.length() > 1.0:
		v = v.normalized()
	return v

func trigger_brake() -> void:
	is_braking = true
	AudioSynth.play_synth("click")

func trigger_primary_action() -> void:
	var tool = GameState.selected_tool
	if factory and GameState.BUILDINGS.has(tool):
		factory.try_build_nearest_ghost()
		return
	if factory and tool == "wire":
		factory.try_wire_nearest(position)
		return
	if factory and tool == "demolish":
		factory.try_demolish_at(position)
		return
	if factory and factory.find_nearest_building(position, 185.0, ["smelter", "assembler"]).size() > 0:
		factory.try_interact_nearest(position, ["smelter", "assembler"])
		return
	if mine_cd <= 0.0:
		var in_v = _read_move_input()
		var did_mine = _perform_mining(in_v.y <= 0.35)
		if not did_mine and factory:
			factory.try_interact_nearest(position)

func _physics_process(delta: float) -> void:
	if not world:
		return
	anim_time += delta
	if mine_cd > 0.0: mine_cd -= delta
	if impact_flash_t > 0.0: impact_flash_t -= delta
	if shield_regen_delay > 0.0:
		shield_regen_delay -= delta
	elif GameState.player_shield < GameState.player_max_shield:
		GameState.player_shield = minf(GameState.player_max_shield, GameState.player_shield + 8.0 * delta)

	var in_vec = _read_move_input()
	is_braking = virtual_brake or Input.is_physical_key_pressed(KEY_B) or Input.is_physical_key_pressed(KEY_SHIFT)

	# 1. Planetary Service (Refuel + Recharge + Item Belt Magnet Pickup)
	if factory:
		if factory.has_method("service_player"):
			factory.service_player(position, delta)
		if factory.has_method("collect_nearby_items"):
			factory.collect_nearby_items(position, 92.0)

	# 2. Local Surface Frame Vectors
	var r = maxf(position.length(), 1.0)
	var up = position / r
	var tang_cw = Vector2(-up.y, up.x) # +X on surface moves clockwise around sphere
	var alt = r - PlanetWorld.R_SURFACE
	var grav: Vector2 = world.compute_gravity_at(position)
	current_g_norm = grav.length() / PlanetWorld.G_ORIGIN
	var g_dir = grav.normalized() if grav.length() > 1.0 else -up
	var rho = world.get_atmosphere_density(position)

	# 3. Capsule Rolling / Rocket Gimbal & True Orbital Thrust
	var tier: int = GameState.engine_tier
	is_thrusting = false
	is_ion_thrusting = false
	var target_rot = up.angle() + PI * 0.5
	var accel = grav

	if tier == 0:
		# Starter Drop Capsule: rolls along spherical surface/tunnels + weak Electric Ion climb/hop (alt < 260px)
		if is_anchored_surface or alt < 260.0:
			var roll_spd = 260.0
			var v_tang = velocity.dot(tang_cw)
			var target_t = in_vec.x * roll_spd
			velocity += tang_cw * clampf(target_t - v_tang, -480.0 * delta, 480.0 * delta)

			# Electric Ion Surface Hop (scales slightly above local gravity up to +220px alt so pits never trap)
			if in_vec.y < -0.25 and alt < 220.0 and GameState.player_battery > 1.5:
				var ion_force = maxf(265.0, grav.length() * 1.28)
				var ion_up = up * ion_force * clampf(-in_vec.y, 0.35, 1.0)
				accel += ion_up
				var drain_rate = 5.0 if alt < 0.0 else 13.0
				GameState.player_battery = maxf(0.0, GameState.player_battery - drain_rate * delta)
				is_ion_thrusting = true
				is_anchored_surface = false
			elif in_vec.y > 0.25 and not is_anchored_surface:
				accel -= up * 160.0

			if is_braking:
				velocity -= tang_cw * velocity.dot(tang_cw) * minf(1.0, 9.0 * delta)
		target_rot = lerpf(target_rot, up.angle() + PI * 0.5 + in_vec.x * 0.25, 0.5)
	else:
		# Evolved Rocket / Lander Propulsion (Fuel primary + Solar Electric Ion Backup!)
		var mag = in_vec.length()
		if is_braking and velocity.length() > 8.0 and not is_anchored_surface:
			# Real Gimbal Retrograde Burn (NO mid-air gravity freeze!)
			var retro = -velocity.normalized()
			target_rot = retro.angle() + PI * 0.5
			if GameState.player_fuel > 0.1:
				var retro_f = ENGINE_THRUST[tier] * 0.85
				accel += retro * retro_f
				GameState.player_fuel = maxf(0.0, GameState.player_fuel - 2.4 * delta)
				is_thrusting = true
			elif GameState.player_battery > 0.5:
				accel += retro * 260.0
				GameState.player_battery = maxf(0.0, GameState.player_battery - 9.0 * delta)
				is_ion_thrusting = true
		elif mag > 0.12:
			# On surface when gently steering left/right with little upward push, allow sleek RCS/rover roll
			if (is_anchored_surface or (alt <= 35.0 and absf(velocity.dot(up)) < 85.0)) and in_vec.y >= -0.15 and absf(in_vec.x) > 0.25:
				var roll_v = velocity.dot(tang_cw)
				velocity += tang_cw * clampf(in_vec.x * 320.0 - roll_v, -520.0 * delta, 520.0 * delta)
				target_rot = up.angle() + PI * 0.5 + in_vec.x * 0.28
			else:
				# On/near planet surface (<800m alt): stick follows curved horizon (Up=outward, Left/Right=CW/CCW tangent)
				# High altitude & open space (>=800m alt): stick points directly in screen/world direction
				var thrust_dir = (tang_cw * in_vec.x - up * in_vec.y).normalized() if r <= PlanetWorld.R_SURFACE + 800.0 else in_vec.normalized()
				target_rot = thrust_dir.angle() + PI * 0.5
				var spd_mult = GameState.get_flight_speed() / 160.0
				if GameState.player_fuel > 0.1:
					var burn_acc = ENGINE_THRUST[tier] * (0.75 + 0.25 * clampf(spd_mult, 0.8, 1.5))
					accel += thrust_dir * burn_acc * mag
					GameState.player_fuel = maxf(0.0, GameState.player_fuel - (2.8 * mag) * delta)
					is_thrusting = true
					is_anchored_surface = false
				elif GameState.player_battery > 0.5:
					# Weak Electric Ion Backup Drive (prevents permanent stranding in space!)
					accel += thrust_dir * 255.0 * mag
					GameState.player_battery = maxf(0.0, GameState.player_battery - (11.0 * mag) * delta)
					is_ion_thrusting = true
					is_anchored_surface = false
		else:
			if velocity.length() > 80.0 and alt > 180.0:
				target_rot = velocity.angle() + PI * 0.5
			else:
				target_rot = (-g_dir).angle() + PI * 0.5

		if is_braking and is_anchored_surface:
			velocity -= tang_cw * velocity.dot(tang_cw) * minf(1.0, 10.0 * delta)

	rotation = lerp_angle(rotation, target_rot, minf(1.0, 9.5 * delta))

	# 4. Quadratic Atmospheric Drag ONLY (0.0000 in Vacuum Space -> True Keplerian Orbit!)
	if rho > 0.001 and not is_anchored_surface:
		var spd = velocity.length()
		if spd > 4.0:
			accel -= velocity * spd * rho * 0.00048

	last_net_accel = accel
	velocity += accel * delta
	if velocity.length() > MAX_SPACE_SPEED:
		velocity = velocity.normalized() * MAX_SPACE_SPEED

	# 5. Swept Substep Integration against Spherical Terrain & Celestial Bodies
	is_anchored_surface = false
	var step_vec = velocity * delta
	var n_steps = clampi(int(ceil(step_vec.length() / 10.0)), 1, 8)
	var sub_dt = step_vec / float(n_steps)
	for _s in range(n_steps):
		var next_p = position + sub_dt
		var nr = next_p.length()
		var n_up = next_p / maxf(nr, 1.0)

		# Inner molten magma bounce & thermal hazard
		if nr < PlanetWorld.R_MAGMA + CAP_RADIUS:
			next_p = n_up * (PlanetWorld.R_MAGMA + CAP_RADIUS)
			var vr = velocity.dot(n_up)
			if vr < 0.0:
				velocity -= n_up * vr * 1.45
			_apply_hull_damage(18.0 * delta)

		# Check solid radial crust & cavern cells
		if nr <= PlanetWorld.R_SURFACE + CAP_RADIUS + 20.0:
			var hit_dir = _check_circle_terrain_hit(next_p, CAP_RADIUS)
			if hit_dir != Vector2.ZERO:
				var push = hit_dir.normalized()
				var vr_in = -velocity.dot(push)
				if vr_in > 520.0:
					_apply_hull_damage((vr_in - 520.0) * 0.09)
				# Push cleanly out radially/cell-normal without snagging
				var resolved = false
				for push_try in range(4):
					var cand = position + push * float(push_try + 1) * 3.5
					if _check_circle_terrain_hit(cand, CAP_RADIUS) == Vector2.ZERO:
						next_p = cand
						resolved = true
						break
				if not resolved:
					next_p = position
				if velocity.dot(push) < 0.0:
					velocity -= push * velocity.dot(push)
				if push.dot(up) > 0.35 and not is_thrusting and not is_ion_thrusting:
					is_anchored_surface = true
					velocity *= (0.84 if in_vec.length() <= 0.12 else 0.96)

		# Check solid moons/celestials
		var cel_hit = world.get_celestial_collision(next_p, CAP_RADIUS)
		if not cel_hit.is_empty():
			var cn: Vector2 = cel_hit["normal"]
			next_p = Vector2(cel_hit["body"]["pos"]) + cn * float(cel_hit["surf_r"])
			var cv_in = -velocity.dot(cn)
			if cv_in > 520.0:
				_apply_hull_damage((cv_in - 520.0) * 0.08)
			if velocity.dot(cn) < 0.0:
				velocity -= cn * velocity.dot(cn)
			is_anchored_surface = true

		position = next_p

	# World boundary clamp
	if position.length() > PlanetWorld.WORLD_LIMIT_R - 800.0:
		position = position.normalized() * (PlanetWorld.WORLD_LIMIT_R - 800.0)
		velocity *= 0.85

	# 6. Continuous Mining Trigger while Holding [A] / Space in mine mode (building/wire triggers once per press)
	is_mining = false
	var act_held = virtual_fire or Input.is_physical_key_pressed(KEY_SPACE)
	if act_held and mine_cd <= 0.0:
		if GameState.selected_tool == "pick" or GameState.selected_tool == "mine":
			_perform_mining(in_vec.y <= 0.35)

	queue_redraw()

func _apply_hull_damage(dmg: float) -> void:
	if dmg <= 0.0:
		return
	shield_regen_delay = 3.5
	impact_flash_t = 0.28
	var rem = dmg
	if GameState.player_shield > 0.0:
		var ab = minf(GameState.player_shield, rem)
		GameState.player_shield -= ab
		rem -= ab
	if rem > 0.0:
		GameState.player_hp = maxf(0.0, GameState.player_hp - rem)
		AudioSynth.play_synth("alert")
	if GameState.player_hp <= 0.0:
		redeploy_capsule()

func _check_circle_terrain_hit(p: Vector2, rad: float) -> Vector2:
	var probes = [
		Vector2(0, 1), Vector2(0, -1), Vector2(1, 0), Vector2(-1, 0),
		Vector2(0.7, 0.7), Vector2(-0.7, 0.7), Vector2(0.7, -0.7), Vector2(-0.7, -0.7),
	]
	var out_push = Vector2.ZERO
	var hits = 0
	for d in probes:
		var sp = p + d * rad
		if world.is_point_solid(sp):
			out_push -= d
			hits += 1
	if hits == 0:
		return Vector2.ZERO
	if out_push.length() < 0.1:
		return p.normalized()
	return out_push.normalized()

func _perform_mining(prefer_sideways: bool = false) -> bool:
	if not world:
		return false
	var tgt = world.find_nearest_mine_target(position, 320.0, prefer_sideways)
	if tgt.is_empty():
		return false
	is_mining = true
	mining_target_pos = tgt["pos"]
	mine_cd = 0.22
	var power = 9.0 + float(GameState.engine_tier) * 6.0
	match tgt["type"]:
		"asteroid":
			world.mine_asteroid_at(tgt["pos"], power, 220.0)
			AudioSynth.play_synth("mine")
			return true
		"celestial":
			world.mine_celestial_body(tgt["body"], tgt["pos"])
			AudioSynth.play_synth("mine")
			return true
		"cell":
			var c: Vector2i = tgt["cell"]
			var mres = world.damage_cell(c.x, c.y, power, true)
			if mres["hit"]:
				AudioSynth.play_synth("mine")
				return true
	return false

# ------------------------------------------------------------------------------
# PROCEDURAL APOLLO CAPSULE->LANDER + KEPLER ORBIT ARC + FIGHTER-JET SHIP HUD
# ------------------------------------------------------------------------------
func _draw() -> void:
	var tier = GameState.engine_tier

	# 1. Predicted Keplerian Orbital Trajectory Arc (when flying/above ground)
	if world and (not is_anchored_surface or velocity.length() > 90.0):
		_draw_predicted_orbit()

	# 2. Mining Laser Beam
	if is_mining:
		var local_tgt = to_local(mining_target_pos)
		draw_line(Vector2.ZERO, local_tgt, Color(0.28, 0.96, 1.0, 0.92), 4.0)
		draw_line(Vector2.ZERO, local_tgt, Color(0.95, 1.0, 1.0, 0.95), 1.6)
		draw_circle(local_tgt, 9.0 + 3.0 * sin(anim_time * 18.0), Color(0.45, 0.98, 1.0, 0.75))

	# 3. Rocket / Ion Thruster Plume
	if is_thrusting:
		var fl = 28.0 + float(tier) * 11.0 + 7.0 * sin(anim_time * 42.0)
		draw_colored_polygon(PackedVector2Array([Vector2(-9, 18), Vector2(9, 18), Vector2(0, 18 + fl)]), Color(1.0, 0.56, 0.16, 0.92))
		draw_colored_polygon(PackedVector2Array([Vector2(-4, 18), Vector2(4, 18), Vector2(0, 18 + fl * 0.65)]), Color(1.0, 0.94, 0.68, 0.96))
	elif is_ion_thrusting:
		var fl_ion = 22.0 + 5.0 * sin(anim_time * 36.0)
		draw_colored_polygon(PackedVector2Array([Vector2(-7, 16), Vector2(7, 16), Vector2(0, 16 + fl_ion)]), Color(0.22, 0.88, 1.0, 0.88))
		draw_circle(Vector2(0, 20), 6.5, Color(0.65, 1.0, 1.0, 0.72))

	# 4. Evolving Cylindrical Capsule -> Apollo Spacecraft Hull (ship-local frame)
	var hull_col = Color(0.84, 0.89, 0.95) if impact_flash_t <= 0.0 else Color(1.0, 0.35, 0.35)
	var trim_col = Color(0.92, 0.68, 0.22)
	var cyan_col = Color(0.28, 0.92, 1.0)

	if tier >= 1:
		# Deployed Lander Struts Mk-I
		draw_line(Vector2(-10, 8), Vector2(-22, 22), trim_col, 3.0)
		draw_line(Vector2(10, 8), Vector2(22, 22), trim_col, 3.0)
		draw_line(Vector2(-26, 22), Vector2(-18, 22), Color(0.75, 0.82, 0.9), 3.0)
		draw_line(Vector2(18, 22), Vector2(26, 22), Color(0.75, 0.82, 0.9), 3.0)
		draw_colored_polygon(PackedVector2Array([Vector2(-7, 14), Vector2(7, 14), Vector2(10, 21), Vector2(-10, 21)]), Color(0.32, 0.38, 0.46))

	if tier >= 2:
		# Apollo Solar Wing Arrays & Service Adapter Mk-II
		draw_rect(Rect2(-34, -2, 20, 9), Color(0.14, 0.36, 0.74), true)
		draw_rect(Rect2(-34, -2, 20, 9), cyan_col, false, 1.2)
		draw_rect(Rect2(14, -2, 20, 9), Color(0.14, 0.36, 0.74), true)
		draw_rect(Rect2(14, -2, 20, 9), cyan_col, false, 1.2)
		draw_rect(Rect2(-12, 3, 24, 12), trim_col, true)

	if tier >= 3:
		# Warp Ascent Mk-III swept delta fins & plasma ring
		draw_colored_polygon(PackedVector2Array([Vector2(-12, -4), Vector2(-30, 14), Vector2(-12, 14)]), Color(0.24, 0.42, 0.68))
		draw_colored_polygon(PackedVector2Array([Vector2(12, -4), Vector2(30, 14), Vector2(12, 14)]), Color(0.24, 0.42, 0.68))
		draw_arc(Vector2(0, 2), 20.0, 0.0, TAU, 24, Color(0.32, 0.95, 1.0, 0.55), 2.2)

	# Core Cylindrical Drop Capsule (always recognizable!)
	draw_rect(Rect2(-10, -10, 20, 24), hull_col, true)
	draw_rect(Rect2(-10, -10, 20, 24), Color(0.18, 0.25, 0.36), false, 1.6)
	draw_colored_polygon(PackedVector2Array([Vector2(-10, -10), Vector2(10, -10), Vector2(6, -19), Vector2(-6, -19)]), Color(0.68, 0.76, 0.86))
	draw_circle(Vector2(0, -3), 5.0, cyan_col)
	draw_rect(Rect2(-9, 11, 18, 4), Color(0.22, 0.24, 0.30), true)

	# 5. Diegetic Fighter-Jet Circular Ship HUD (Left = HP/Shield, Right = Fuel/Battery, V/ALT/PWR)
	_draw_fighter_hud()

func _draw_predicted_orbit() -> void:
	draw_set_transform(Vector2.ZERO, -rotation, Vector2.ONE)
	var sim_p = position
	var sim_v = velocity
	var pts: PackedVector2Array = PackedVector2Array([Vector2.ZERO])
	var step_dt = 0.32
	var impact_pt = Vector2.ZERO
	var min_r = sim_p.length()
	var max_r = sim_p.length()
	var pe_local = Vector2.ZERO
	var ap_local = Vector2.ZERO
	for i in range(44):
		var g = world.compute_gravity_at(sim_p)
		sim_v += g * step_dt
		var rho = world.get_atmosphere_density(sim_p)
		if rho > 0.001:
			sim_v -= sim_v * sim_v.length() * rho * 0.00048 * step_dt
		sim_p += sim_v * step_dt
		var rel = sim_p - position
		pts.append(rel)
		var r = sim_p.length()
		if r < min_r:
			min_r = r
			pe_local = rel
		if r > max_r:
			max_r = r
			ap_local = rel
		if r < PlanetWorld.R_SURFACE - 10.0:
			impact_pt = rel
			break
	if pts.size() >= 2:
		var arc_col = Color(1.0, 0.48, 0.28, 0.55) if impact_pt != Vector2.ZERO else Color(0.28, 0.95, 1.0, 0.52)
		for k in range(pts.size() - 1):
			if k % 2 == 0:
				draw_line(pts[k], pts[k + 1], arc_col, 2.0)
	if impact_pt != Vector2.ZERO:
		draw_line(impact_pt + Vector2(-7, -7), impact_pt + Vector2(7, 7), Color(1.0, 0.35, 0.35, 0.85), 2.2)
		draw_line(impact_pt + Vector2(-7, 7), impact_pt + Vector2(7, -7), Color(1.0, 0.35, 0.35, 0.85), 2.2)
	var font = ThemeDB.fallback_font
	if font:
		if pe_local != Vector2.ZERO and min_r > PlanetWorld.R_SURFACE + 40.0:
			draw_circle(pe_local, 4.0, Color(0.28, 0.96, 0.68, 0.85))
			draw_string(font, pe_local + Vector2(6, -4), "PE %dm" % int(min_r - PlanetWorld.R_SURFACE), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.28, 0.96, 0.68, 0.9))
		if ap_local != Vector2.ZERO and max_r > PlanetWorld.R_SURFACE + 80.0:
			draw_circle(ap_local, 4.0, Color(0.32, 0.90, 1.0, 0.85))
			draw_string(font, ap_local + Vector2(6, -4), "AP %dm" % int(max_r - PlanetWorld.R_SURFACE), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.32, 0.90, 1.0, 0.9))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_fighter_hud() -> void:
	draw_set_transform(Vector2.ZERO, -rotation, Vector2.ONE)
	var R_ARC = 56.0
	var track_col = Color(0.08, 0.16, 0.28, 0.62)

	# LEFT ARC: Durability HP + Shield (PI - 0.85 .. PI + 0.85, filling bottom->top clockwise along left side)
	var l_start = PI * 0.72
	var l_end = PI * 1.28
	var hp_r = clampf(GameState.player_hp / maxf(1.0, GameState.player_max_hp), 0.0, 1.0)
	var sh_r = clampf(GameState.player_shield / maxf(1.0, GameState.player_max_shield), 0.0, 1.0)
	var hp_col = Color(0.28, 0.96, 0.68, 0.92) if hp_r > 0.45 else (Color(1.0, 0.72, 0.22, 0.95) if hp_r > 0.2 else Color(1.0, 0.28, 0.34, 0.98))
	draw_arc(Vector2.ZERO, R_ARC, l_start, l_end, 20, track_col, 5.0)
	if hp_r > 0.01:
		draw_arc(Vector2.ZERO, R_ARC, l_end - (l_end - l_start) * hp_r, l_end, 18, hp_col, 4.5)
	if sh_r > 0.01:
		draw_arc(Vector2.ZERO, R_ARC + 6.0, l_end - (l_end - l_start) * sh_r, l_end, 16, Color(0.28, 0.88, 1.0, 0.82), 2.5)

	# RIGHT ARC: Propellant Fuel (outer Amber) + Electric Ion Battery (inner Cyan)
	var r_top = -PI * 0.28
	var r_bot = PI * 0.28
	var fu_r = clampf(GameState.player_fuel / maxf(1.0, GameState.player_max_fuel), 0.0, 1.0)
	var ba_r = clampf(GameState.player_battery / maxf(1.0, GameState.player_max_battery), 0.0, 1.0)
	draw_arc(Vector2.ZERO, R_ARC, r_top, r_bot, 20, track_col, 5.0)
	if fu_r > 0.01:
		draw_arc(Vector2.ZERO, R_ARC, r_bot - (r_bot - r_top) * fu_r, r_bot, 18, Color(1.0, 0.72, 0.22, 0.94), 4.5)
	draw_arc(Vector2.ZERO, R_ARC - 6.0, r_top, r_bot, 18, Color(0.08, 0.16, 0.28, 0.48), 3.0)
	if ba_r > 0.01:
		draw_arc(Vector2.ZERO, R_ARC - 6.0, r_bot - (r_bot - r_top) * ba_r, r_bot, 16, Color(0.24, 0.95, 1.0, 0.92), 2.8)

	# Prograde Velocity Vector Chevron on Ring
	if velocity.length() > 35.0:
		var vdir = velocity.normalized()
		draw_circle(vdir * (R_ARC + 10.0), 4.0, Color(0.32, 0.96, 1.0, 0.9))

	# Compact Fighter-Jet Readouts flanking the ring
	var font = ThemeDB.fallback_font
	if font:
		var spd = int(velocity.length())
		var alt_m = int(position.length() - PlanetWorld.R_SURFACE)
		var alt_txt = "ALT %dm" % alt_m if alt_m >= 0 else "D %dm" % alt_m
		draw_string(font, Vector2(R_ARC + 10.0, -14.0), "V %d" % spd, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.35, 0.96, 1.0, 0.95))
		draw_string(font, Vector2(R_ARC + 10.0, 2.0), alt_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.86, 0.94, 1.0, 0.92))
		var pwr_net = int(GameState.power_gen - GameState.power_use)
		var pwr_str = "PWR %+dW" % pwr_net if GameState.power_gen > 0.0 else "BAT %d%%" % int(ba_r * 100.0)
		draw_string(font, Vector2(-R_ARC - 68.0, 2.0), "HP %d" % int(GameState.player_hp), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, hp_col)
		draw_string(font, Vector2(-R_ARC - 68.0, 16.0), pwr_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.68, 0.88, 1.0, 0.9))

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
