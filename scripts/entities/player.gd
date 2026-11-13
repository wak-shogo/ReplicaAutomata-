extends CharacterBody2D
class_name PlayerUnit

# ==============================================================================
# STAR REPLICA: AUTOMA - MODULAR CAPSULE -> APOLLO LUNAR LANDER PHYSICS UNIT
# Full multi-body inverse-square gravity, atmospheric drag, RCS attitude
# torque, axial rocket bell thrust, and zero-drift spherical surface anchoring.
# Procedural modular assembly renders directly on the central seed cylinder.
# ==============================================================================

const GROUND_SPEED: float = 185.0
const MAX_SPACE_SPEED: float = 1100.0
const SURFACE_LOCK_R: float = PlanetWorld.R_SURFACE + 24.0

var world: PlanetWorld
var factory: FactorySim

var anim_time: float = 0.0
var mine_cooldown: float = 0.0
var grounded_warn_cd: float = 0.0
var mine_beams: Array[Dictionary] = []

var virtual_move_vec: Vector2 = Vector2.ZERO
var virtual_mine_active: bool = false
var is_anchored_surface: bool = true
var brake_active: bool = false
var hover_stabilize: bool = false

# Live propulsion/attitude state for procedural exhaust & RCS visuals
var main_throttle: float = 0.0
var rcs_turn_dir: int = 0 # -1 CCW, +1 CW, 0 idle
var leg_extend: float = 1.0 # 1.0 extended for landing, 0.25 retracted in cruise
var current_g_norm: float = 0.92 # Local gravity in Origin-Prime surface g units

func _ready() -> void:
	reset_to_spawn()

func reset_to_spawn() -> void:
	var a = PlanetWorld.sector_center_angle(PlanetWorld.SPAWN_SECTOR)
	position = Vector2(cos(a), sin(a)) * (PlanetWorld.R_SURFACE + 24.0)
	velocity = Vector2.ZERO
	rotation = a + PI * 0.5
	is_anchored_surface = true
	brake_active = false
	hover_stabilize = false
	main_throttle = 0.0
	rcs_turn_dir = 0
	leg_extend = 1.0

func setup(p_world: PlanetWorld, p_factory: FactorySim) -> void:
	world = p_world
	factory = p_factory

func set_virtual_input(move_vec: Vector2, mining: bool) -> void:
	virtual_move_vec = move_vec
	virtual_mine_active = mining

func trigger_brake() -> void:
	if is_anchored_surface:
		velocity = Vector2.ZERO
		hover_stabilize = false
		brake_active = false
	else:
		brake_active = true
		hover_stabilize = true
	AudioSynth.play_synth("select")

func trigger_primary_action() -> void:
	var tool_id = GameState.selected_tool
	if tool_id in GameState.BUILDINGS and factory:
		factory.try_build_nearest_ghost()
	elif tool_id == "demolish" and factory:
		factory.try_demolish_at(position)
	else:
		_perform_mining()

func _physics_process(delta: float) -> void:
	anim_time += delta
	if grounded_warn_cd > 0.0:
		grounded_warn_cd -= delta

	var move_dir = _read_move_input()
	var g_vec = world.compute_gravity_at(position) if world else Vector2.ZERO
	current_g_norm = g_vec.length() / PlanetWorld.G_ORIGIN

	var dist_center = position.length()
	var origin_up = position.normalized() if dist_center > 1.0 else Vector2.UP
	var cel_near = world.get_celestial_collision(position, 44.0) if world else {}
	var surf_up = cel_near["normal"] if not cel_near.is_empty() else origin_up
	var on_origin_surf = dist_center <= PlanetWorld.R_SURFACE + 34.0 and (world == null or world.is_point_solid(position - origin_up * 32.0))
	var on_cel_surf = not cel_near.is_empty()
	var near_ground = on_origin_surf or on_cel_surf

	# Smoothly articulate landing struts when near any solid planet/moon
	var want_legs = 1.0 if (dist_center <= PlanetWorld.R_SURFACE + 420.0 or not cel_near.is_empty() and cel_near["dist"] < cel_near["body"]["r"] + 380.0) else 0.25
	leg_extend = lerpf(leg_extend, want_legs, clampf(4.5 * delta, 0.0, 1.0))

	main_throttle = 0.0
	rcs_turn_dir = 0
	var thrust_accel = GameState.get_engine_thrust()
	var wants_liftoff = (GameState.engine_tier > 0 and move_dir.length_squared() > 0.02 and move_dir.normalized().dot(surf_up) > 0.40)

	# 1. Grounded Capsule / Lander Surface Mobility (Zero Unintended Drift)
	if near_ground and not wants_liftoff and (is_anchored_surface or velocity.dot(surf_up) <= 45.0):
		hover_stabilize = false
		brake_active = false
		var target_rot = surf_up.angle() + PI * 0.5
		rotation = lerp_angle(rotation, target_rot, clampf(12.0 * delta, 0.0, 1.0))

		if move_dir.length_squared() > 0.01:
			is_anchored_surface = false
			var want_dir = move_dir.normalized()
			var radial_out = want_dir.dot(surf_up)
			if GameState.engine_tier <= 0 and radial_out > 0.15 and dist_center >= PlanetWorld.R_SURFACE - 6.0:
				want_dir = (want_dir - surf_up * radial_out)
				if want_dir.length_squared() > 0.01:
					want_dir = want_dir.normalized()
				else:
					want_dir = Vector2.ZERO
				if grounded_warn_cd <= 0.0:
					grounded_warn_cd = 2.5
					GameState.emit_signal("log_event", "GROUNDED: Print Mk-I Thruster & Legs via [Y] PRINTER!", "warn")
			if want_dir.length_squared() > 0.01:
				if radial_out >= -0.25 and (not on_origin_surf or dist_center >= PlanetWorld.R_SURFACE - 6.0):
					var tang = (want_dir - surf_up * radial_out)
					if tang.length_squared() > 0.01:
						want_dir = (tang.normalized() - surf_up * 0.16).normalized()
				velocity = velocity.lerp(want_dir * GROUND_SPEED, clampf(16.0 * delta, 0.0, 1.0))
			else:
				velocity = Vector2.ZERO
				is_anchored_surface = true
		else:
			velocity = Vector2.ZERO
			is_anchored_surface = true
	else:
		# 2. Full Gravity + Attitude Rotation + Axial Rocket Propulsion
		is_anchored_surface = false

		# Grounded block safety if engine_tier == 0 while detached slightly above Origin-Prime
		if GameState.engine_tier <= 0:
			brake_active = false
			hover_stabilize = false
			velocity += g_vec * delta
			var target_rot0 = origin_up.angle() + PI * 0.5
			rotation = lerp_angle(rotation, target_rot0, clampf(10.0 * delta, 0.0, 1.0))
			if move_dir.length_squared() > 0.01:
				var want0 = move_dir.normalized()
				var rad0 = want0.dot(origin_up)
				if rad0 > 0.15 and dist_center >= PlanetWorld.R_SURFACE - 6.0:
					want0 = want0 - origin_up * rad0
					if grounded_warn_cd <= 0.0:
						grounded_warn_cd = 2.5
						GameState.emit_signal("log_event", "GROUNDED: Print Mk-I Thruster & Legs via [Y] PRINTER!", "warn")
				if want0.length_squared() > 0.01:
					velocity = velocity.lerp(want0.normalized() * GROUND_SPEED, clampf(10.0 * delta, 0.0, 1.0))
		else:
			var rho = world.get_atmosphere_density(position) if world else 0.0

			if Input.is_key_pressed(KEY_B) or brake_active:
				# Retrograde Velocity Match / RCS Station-Keep Hover
				var damp_rate = maxf(420.0, thrust_accel * 1.4)
				velocity = velocity.move_toward(Vector2.ZERO, damp_rate * delta)
				if velocity.length() < 10.0:
					velocity = Vector2.ZERO
					brake_active = false
				if move_dir.length_squared() > 0.02:
					hover_stabilize = false
					brake_active = false
			elif move_dir.length_squared() > 0.02:
				hover_stabilize = false
				var m_dir = move_dir.normalized()
				var m_mag = clampf(move_dir.length(), 0.0, 1.0)
				# RCS Torque Rotation toward desired flight heading
				var want_rot = m_dir.angle() + PI * 0.5
				var ang_err = wrapf(want_rot - rotation, -PI, PI)
				var rot_rate = 4.6 + float(GameState.engine_tier) * 1.4
				var max_step = rot_rate * delta
				if absf(ang_err) > 0.06:
					rcs_turn_dir = 1 if ang_err > 0.0 else -1
				rotation = wrapf(rotation + clampf(ang_err, -max_step, max_step), -PI, PI)

				# Main Bell Rocket Thrust strictly along Forward Nose Axis (-Y local)!
				var forward_dir = Vector2.UP.rotated(rotation)
				var align = clampf((forward_dir.dot(m_dir) - 0.12) / 0.88, 0.0, 1.0)
				main_throttle = align * m_mag
				velocity += forward_dir * (thrust_accel * main_throttle) * delta

			# Apply real multi-body gravitational acceleration unless Station-Keeping Hover is holding
			if not hover_stabilize:
				velocity += g_vec * delta
			else:
				# Gently align upright relative to local gravity while station-keeping
				if g_vec.length_squared() > 1.0:
					var hold_rot = (-g_vec).angle() + PI * 0.5
					rotation = lerp_angle(rotation, hold_rot, clampf(5.0 * delta, 0.0, 1.0))

			# Thick lower atmosphere aerodynamic drag (produces realistic ~45s Mk-I climb)
			if rho > 0.0:
				var drag_k = 2.65 * (0.58 + 0.42 * rho) * smoothstep(0.0, 0.08, rho)
				velocity -= velocity * clampf(drag_k * delta, 0.0, 0.92)

			if velocity.length() > MAX_SPACE_SPEED:
				velocity = velocity.normalized() * MAX_SPACE_SPEED

	var next_pos = position + velocity * delta

	# Prevent Grounded Seed Cylinder from climbing off surface ceiling
	if GameState.engine_tier <= 0 and next_pos.length() > SURFACE_LOCK_R:
		next_pos = next_pos.normalized() * SURFACE_LOCK_R
		if velocity.dot(origin_up) > 0.0:
			velocity -= origin_up * velocity.dot(origin_up)

	# Keep within cosmic star-system boundary
	if next_pos.length() > PlanetWorld.WORLD_LIMIT_R - 80.0:
		next_pos = next_pos.normalized() * (PlanetWorld.WORLD_LIMIT_R - 80.0)
		velocity = Vector2.ZERO

	# Solid Outer Celestial Collision (LUNA-PRIME, CRYO-CRYSTAL, IGNIS-IV, GAIA-MAJOR)
	if world:
		var next_cel = world.get_celestial_collision(next_pos, 24.0)
		if not next_cel.is_empty():
			var cn: Vector2 = next_cel["normal"]
			var sr: float = float(next_cel["surf_r"])
			var impact_rad = velocity.dot(cn)
			next_pos = Vector2(next_cel["body"]["pos"]) + cn * sr
			if impact_rad < 0.0:
				if absf(impact_rad) > 360.0:
					world.spawn_spark_burst(next_pos - cn * 14.0, Color(1.0, 0.72, 0.3), 10)
				velocity -= cn * impact_rad
				if move_dir.length_squared() < 0.02:
					velocity = Vector2.ZERO
					is_anchored_surface = true

	# Origin-Prime Magma Core & Solid Terrain / Landing Strut Touchdown
	if world and next_pos.length() <= PlanetWorld.R_SURFACE + 4.0:
		if next_pos.length() < PlanetWorld.R_MAGMA + 24.0:
			next_pos = next_pos.normalized() * (PlanetWorld.R_MAGMA + 24.0)
			velocity = Vector2.ZERO
		elif world.is_point_solid(next_pos):
			var c = world.pos_to_cell(next_pos)
			var inward_spd = -velocity.dot(origin_up)
			var contact_drill = move_dir.length_squared() > 0.01 and (move_dir.normalized().dot(origin_up) < -0.25 or position.length() < PlanetWorld.R_SURFACE - 6.0)
			if GameState.selected_tool == "pick" and contact_drill and mine_cooldown <= 0.0:
				_mine_cell(c.x, c.y)
			if position.length() >= PlanetWorld.R_SURFACE - 6.0 and (move_dir.length_squared() <= 0.01 or move_dir.normalized().dot(origin_up) >= -0.30):
				if inward_spd > 280.0:
					world.spawn_spark_burst(next_pos, Color(1.0, 0.78, 0.35), 8)
				next_pos = next_pos.normalized() * SURFACE_LOCK_R
				velocity -= origin_up * minf(0.0, velocity.dot(origin_up))
				if move_dir.length_squared() <= 0.02:
					velocity = Vector2.ZERO
					is_anchored_surface = true
			else:
				next_pos = position
				velocity = Vector2.ZERO

	position = next_pos

	AudioSynth.update_celestial_ambience(0.0, 0.0, clampf(main_throttle + move_dir.length() * 0.4, 0.0, 1.0))

	for bi in range(mine_beams.size() - 1, -1, -1):
		mine_beams[bi]["life"] -= delta
		if mine_beams[bi]["life"] <= 0.0:
			mine_beams.remove_at(bi)

	if mine_cooldown > 0.0:
		mine_cooldown -= delta

	var wants_mine = virtual_mine_active or Input.is_key_pressed(KEY_SPACE) or Input.is_joy_button_pressed(0, JOY_BUTTON_A)
	if wants_mine and mine_cooldown <= 0.0 and GameState.selected_tool == "pick":
		_perform_mining()

	queue_redraw()

func _read_move_input() -> Vector2:
	var v = Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): v.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): v.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): v.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): v.y += 1.0
	var joy = Vector2(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
	if joy.length() > 0.18:
		v += joy
	v += virtual_move_vec
	if v.length() > 1.0:
		v = v.normalized()
	return v

func _perform_mining() -> void:
	if not world: return
	var move_dir = _read_move_input()
	var origin_up = position.normalized() if position.length() > 1.0 else Vector2.UP
	var digging_down = move_dir.length_squared() > 0.04 and move_dir.normalized().dot(origin_up) < -0.35
	var nearest = world.find_nearest_mine_target(position, 235.0, not digging_down)
	if nearest.is_empty():
		return
	if nearest["type"] == "asteroid":
		_mine_asteroid(nearest["pos"])
	elif nearest["type"] == "celestial":
		world.mine_celestial_body(nearest["body"], nearest["pos"])
		mine_cooldown = 0.22
		AudioSynth.play_synth("mine")
		_emit_beams(nearest["pos"], mini(1 + GameState.drones, 7))
	else:
		var c: Vector2i = nearest["cell"]
		_mine_cell(c.x, c.y, nearest["pos"])

func _mine_cell(s: int, l: int, world_target: Vector2 = Vector2.ZERO) -> void:
	var tgt = world_target if world_target != Vector2.ZERO else world.cell_center(s, l)
	var dmg = 7.5 + float(GameState.drones) * 3.0
	world.damage_cell(s, l, dmg, true)
	mine_cooldown = 0.22
	AudioSynth.play_synth("mine")
	_emit_beams(tgt, mini(1 + GameState.drones, 7))

func _mine_asteroid(ast_pos: Vector2) -> void:
	var dmg = 7.5 + float(GameState.drones) * 4.2
	world.mine_asteroid_at(ast_pos, dmg, 195.0)
	mine_cooldown = 0.22
	AudioSynth.play_synth("mine")
	_emit_beams(ast_pos, mini(1 + GameState.drones, 7))

func _emit_beams(world_tgt: Vector2, beam_count: int) -> void:
	mine_beams.append({"from": position, "to": world_tgt, "life": 0.16, "main": true})
	var dc = mini(GameState.drones, beam_count - 1)
	for i in range(dc):
		var local_off = _get_drone_offset(i, GameState.drones).rotated(rotation)
		mine_beams.append({"from": position + local_off, "to": world_tgt, "life": 0.16, "main": false})

func _get_drone_offset(idx: int, total: int) -> Vector2:
	var ring_r = 34.0 if total <= 6 else 42.0
	var ang = anim_time * 1.65 + (TAU * float(idx) / maxf(1.0, float(total)))
	return Vector2(cos(ang) * ring_r, sin(ang) * ring_r * 0.68 - 4.0)

func _draw() -> void:
	var font = ThemeDB.fallback_font
	var inv_rot = -rotation
	var tier = GameState.engine_tier

	# 1. Active Mining / Salvage Beams
	for mb in mine_beams:
		var a = clampf(mb["life"] / 0.16, 0.0, 1.0)
		var f_loc = (mb["from"] - position).rotated(inv_rot)
		var t_loc = (mb["to"] - position).rotated(inv_rot)
		var col = Color(0.25, 0.96, 1.0, a) if mb["main"] else Color(1.0, 0.78, 0.28, a * 0.85)
		draw_line(f_loc, t_loc, col, 2.5 if mb["main"] else 1.5)
		draw_circle(t_loc, 4.0 * a, Color(0.85, 1.0, 1.0, a))

	# 2. Propulsion & Attitude Plumes (rendered behind hull)
	var flicker = 0.85 + 0.15 * sin(anim_time * 42.0)
	if tier >= 1 and (main_throttle > 0.05 or brake_active):
		var pwr = maxf(main_throttle, 0.45 if brake_active else 0.0)
		var base_y = 26.0
		var flame_len = (22.0 + float(tier) * 10.0) * pwr * flicker
		var flame_w = 5.5 + float(tier) * 1.5
		var outer_col = Color(0.32, 0.85, 1.0, 0.82) if tier >= 3 else Color(1.0, 0.56, 0.16, 0.88)
		var core_col = Color(0.92, 0.99, 1.0, 0.96)
		draw_colored_polygon(PackedVector2Array([
			Vector2(-flame_w, base_y), Vector2(flame_w, base_y), Vector2(0.0, base_y + flame_len)
		]), outer_col)
		draw_colored_polygon(PackedVector2Array([
			Vector2(-flame_w * 0.48, base_y), Vector2(flame_w * 0.48, base_y), Vector2(0.0, base_y + flame_len * 0.62)
		]), core_col)
		if tier >= 2:
			for sx in [-12.0, 12.0]:
				draw_colored_polygon(PackedVector2Array([
					Vector2(sx - 2.6, 22.0), Vector2(sx + 2.6, 22.0), Vector2(sx, 22.0 + flame_len * 0.55)
				]), outer_col)

	# Hover-Stabilizer Micro-Jets & RCS Attitude Thruster Puffs
	if tier >= 1 and hover_stabilize:
		for sx in [-10.0, 10.0]:
			draw_colored_polygon(PackedVector2Array([
				Vector2(sx - 2.0, 21.0), Vector2(sx + 2.0, 21.0), Vector2(sx, 21.0 + 10.0 * flicker)
			]), Color(0.75, 0.95, 1.0, 0.72))
	if tier >= 1 and rcs_turn_dir != 0:
		var rcs_col = Color(0.85, 0.96, 1.0, 0.82)
		if rcs_turn_dir > 0:
			# Torque CW: top-left & bottom-right RCS puffs
			draw_colored_polygon(PackedVector2Array([Vector2(-9.0, -14.0), Vector2(-21.0, -17.0), Vector2(-21.0, -11.0)]), rcs_col)
			draw_colored_polygon(PackedVector2Array([Vector2(9.0, 12.0), Vector2(21.0, 9.0), Vector2(21.0, 15.0)]), rcs_col)
		else:
			# Torque CCW: top-right & bottom-left RCS puffs
			draw_colored_polygon(PackedVector2Array([Vector2(9.0, -14.0), Vector2(21.0, -17.0), Vector2(21.0, -11.0)]), rcs_col)
			draw_colored_polygon(PackedVector2Array([Vector2(-9.0, 12.0), Vector2(-21.0, 9.0), Vector2(-21.0, 15.0)]), rcs_col)

	# 3. Tier >= 3 Deployable Solar/Radiator Wings & Magnetic Warp Halo (under body)
	if tier >= 3:
		draw_arc(Vector2(0.0, 0.0), 31.0, 0.0, TAU, 28, Color(0.28, 0.92, 1.0, 0.30 + 0.14 * sin(anim_time * 4.0)), 1.8)
		for sx in [-1.0, 1.0]:
			var wing_pts = PackedVector2Array([
				Vector2(sx * 14.0, -4.0), Vector2(sx * 31.0, -7.0),
				Vector2(sx * 31.0, 7.0), Vector2(sx * 14.0, 5.0)
			])
			draw_colored_polygon(wing_pts, Color(0.10, 0.24, 0.44, 0.95))
			draw_polyline(PackedVector2Array([wing_pts[0], wing_pts[1], wing_pts[2], wing_pts[3], wing_pts[0]]), Color(0.36, 0.88, 1.0, 0.85), 1.3)
			draw_line(Vector2(sx * 16.0, 0.0), Vector2(sx * 30.0, 0.0), Color(0.36, 0.88, 1.0, 0.55), 1.0)

	# 4. Tier >= 1 Articulated Apollo Lunar Lander Struts & Footpads
	if tier >= 1:
		var foot_x = 16.0 + 9.0 * leg_extend
		var foot_y = 21.0 + 6.0 * leg_extend
		for sx in [-1.0, 1.0]:
			draw_line(Vector2(sx * 8.0, 8.0), Vector2(sx * foot_x, foot_y), Color(0.84, 0.72, 0.34, 1.0), 2.6)
			draw_line(Vector2(sx * 6.0, 17.0), Vector2(sx * foot_x, foot_y), Color(0.55, 0.62, 0.72, 1.0), 2.0)
			draw_line(Vector2(sx * 10.0, 13.0), Vector2(sx * (foot_x * 0.72), foot_y - 3.0), Color(0.38, 0.44, 0.54, 1.0), 1.6)
			# Wide circular lander footpad
			draw_line(Vector2(sx * (foot_x - 4.5), foot_y), Vector2(sx * (foot_x + 4.5), foot_y), Color(0.92, 0.80, 0.38, 1.0), 3.0)

	# 5. Tier >= 1 Main Center Bell Nozzle (+ Twin Vernier Bells at Tier >= 2)
	if tier >= 1:
		draw_colored_polygon(PackedVector2Array([
			Vector2(-4.5, 17.0), Vector2(4.5, 17.0), Vector2(7.0, 26.5), Vector2(-7.0, 26.5)
		]), Color(0.22, 0.25, 0.32, 1.0))
		draw_polyline(PackedVector2Array([
			Vector2(-4.5, 17.0), Vector2(-7.0, 26.5), Vector2(7.0, 26.5), Vector2(4.5, 17.0)
		]), Color(0.62, 0.70, 0.80, 1.0), 1.2)
		if tier >= 2:
			for sx in [-12.0, 12.0]:
				draw_colored_polygon(PackedVector2Array([
					Vector2(sx - 2.2, 15.0), Vector2(sx + 2.2, 15.0), Vector2(sx + 3.4, 22.0), Vector2(sx - 3.4, 22.0)
				]), Color(0.28, 0.32, 0.40, 1.0))

	# 6. BASE MODULE (Always Visible — Simple Cylindrical Seed Capsule at Tier 0)
	# Metallic cylinder body
	draw_colored_polygon(PackedVector2Array([
		Vector2(-8.0, -17.0), Vector2(8.0, -17.0), Vector2(9.0, -13.0),
		Vector2(9.0, 15.0), Vector2(7.0, 18.0), Vector2(-7.0, 18.0),
		Vector2(-9.0, 15.0), Vector2(-9.0, -13.0)
	]), Color(0.46, 0.54, 0.64, 1.0))
	# Specular brushed-steel highlight stripe along left third of cylinder
	draw_rect(Rect2(-5.5, -14.0, 4.2, 30.0), Color(0.76, 0.84, 0.92, 0.72))
	# Darker shadow side along right rim
	draw_rect(Rect2(4.5, -14.0, 3.8, 30.0), Color(0.22, 0.28, 0.36, 0.80))
	# Ribbed structural cylinder bands & top docking collar
	draw_line(Vector2(-8.5, -6.0), Vector2(8.5, -6.0), Color(0.18, 0.24, 0.32, 1.0), 1.8)
	draw_line(Vector2(-8.5, 6.0), Vector2(8.5, 6.0), Color(0.18, 0.24, 0.32, 1.0), 1.8)
	draw_line(Vector2(-6.0, -17.5), Vector2(6.0, -17.5), Color(0.70, 0.80, 0.92, 1.0), 2.2)
	# Charred heat-shield base cap
	draw_rect(Rect2(-7.5, 15.5, 15.0, 3.0), Color(0.16, 0.18, 0.24, 1.0))
	# Illuminated cyan capsule viewport slit
	draw_rect(Rect2(-4.5, -12.5, 9.0, 3.2), Color(0.24, 0.94, 1.0, 0.95))
	# Micro surface treads only when bare Tier 0 capsule
	if tier == 0:
		for sx in [-5.5, 5.5]:
			draw_circle(Vector2(sx, 19.5), 2.2, Color(0.24, 0.30, 0.38, 1.0))
			draw_circle(Vector2(sx, 19.5), 1.0, Color(0.65, 0.78, 0.90, 1.0))

	# 7. Tier >= 2 Apollo Gold Kapton Foil Descent Box + Cryo Propellant Spheres + Dish
	if tier >= 2:
		# Gold foil octagonal descent chassis wrapped onto lower cylinder
		var foil_pts = PackedVector2Array([
			Vector2(-11.0, 1.0), Vector2(11.0, 1.0), Vector2(12.5, 15.0),
			Vector2(9.0, 17.5), Vector2(-9.0, 17.5), Vector2(-12.5, 15.0)
		])
		draw_colored_polygon(foil_pts, Color(0.84, 0.58, 0.14, 1.0))
		draw_line(Vector2(-11.5, 9.0), Vector2(11.5, 9.0), Color(0.98, 0.78, 0.28, 0.90), 1.5)
		draw_polyline(PackedVector2Array([foil_pts[0], foil_pts[1], foil_pts[2], foil_pts[3], foil_pts[4], foil_pts[5], foil_pts[0]]), Color(0.50, 0.32, 0.06, 1.0), 1.4)
		# Cryogenic spherical tanks mounted on left/right of cylinder
		for sx in [-12.5, 12.5]:
			draw_circle(Vector2(sx, -2.5), 4.6, Color(0.82, 0.88, 0.96, 1.0))
			draw_arc(Vector2(sx, -2.5), 4.6, 0.0, TAU, 14, Color(0.32, 0.40, 0.52, 1.0), 1.1)
			draw_line(Vector2(sx * 0.7, -2.5), Vector2(sx, -2.5), Color(0.55, 0.65, 0.76, 1.0), 1.6)
		# High-Gain Dish Antenna & telemetry mast
		draw_line(Vector2(8.0, -14.0), Vector2(13.5, -20.5), Color(0.75, 0.82, 0.90, 1.0), 1.5)
		draw_arc(Vector2(14.5, -22.5), 5.5, 0.3, PI - 0.3, 10, Color(0.88, 0.94, 1.0, 1.0), 1.8)

	# 8. Tier >= 3 Conical Apollo Command Fairing + Cockpit Windows + RCS Port Pods
	if tier >= 3:
		draw_colored_polygon(PackedVector2Array([
			Vector2(-9.5, -16.5), Vector2(9.5, -16.5), Vector2(4.2, -31.0), Vector2(-4.2, -31.0)
		]), Color(0.72, 0.79, 0.88, 1.0))
		draw_colored_polygon(PackedVector2Array([
			Vector2(-2.2, -31.0), Vector2(2.2, -31.0), Vector2(0.0, -37.0)
		]), Color(0.95, 0.76, 0.25, 1.0))
		# Angled triangular Apollo command viewports
		draw_colored_polygon(PackedVector2Array([Vector2(-5.5, -21.0), Vector2(-1.5, -21.0), Vector2(-2.5, -25.0)]), Color(0.24, 0.95, 1.0, 0.95))
		draw_colored_polygon(PackedVector2Array([Vector2(5.5, -21.0), Vector2(1.5, -21.0), Vector2(2.5, -25.0)]), Color(0.24, 0.95, 1.0, 0.95))

	# 9. Procedural Micro-Fabricator Drone Pods (orbiting/docked around hull)
	if GameState.drones > 0:
		var vis_d = mini(GameState.drones, 12)
		for i in range(vis_d):
			var off = _get_drone_offset(i, vis_d)
			draw_line(Vector2.ZERO, off, Color(0.22, 0.85, 1.0, 0.20), 1.0)
			# Procedural diamond micro-drone with cyan lens & winglet solar blades
			draw_line(off + Vector2(-7.0, 0.0), off + Vector2(7.0, 0.0), Color(0.18, 0.42, 0.68, 0.95), 2.4)
			draw_colored_polygon(PackedVector2Array([
				off + Vector2(0.0, -4.5), off + Vector2(4.5, 0.0),
				off + Vector2(0.0, 4.5), off + Vector2(-4.5, 0.0)
			]), Color(0.70, 0.82, 0.95, 1.0))
			draw_circle(off, 1.8, Color(0.28, 0.96, 1.0, 1.0))

	# 10. Upright Floating Mineral Counter & Space Prograde Momentum Vector Pip
	draw_set_transform(Vector2.ZERO, inv_rot)
	if not is_anchored_surface and velocity.length() > 35.0:
		var v_dir = velocity.normalized()
		var pip = v_dir * 42.0
		draw_circle(pip, 3.0, Color(0.28, 0.96, 1.0, 0.72))
		draw_arc(pip, 5.5, 0.0, TAU, 12, Color(0.28, 0.96, 1.0, 0.50), 1.2)
	if font and GameState.recent_ore_timer > 0.0 and GameState.recent_ore_amount > 0:
		var alpha = clampf(GameState.recent_ore_timer / 0.5, 0.0, 1.0)
		var txt = "+%d %s" % [GameState.recent_ore_amount, GameState.recent_ore_type.to_upper()]
		draw_string(font, Vector2(31.0, -13.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0, 0, 0, alpha * 0.9))
		draw_string(font, Vector2(30.0, -14.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.42, 1.0, 0.72, alpha))
	draw_set_transform(Vector2.ZERO, 0.0)
