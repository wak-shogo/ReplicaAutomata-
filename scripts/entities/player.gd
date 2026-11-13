extends CharacterBody2D
class_name PlayerUnit

# ==============================================================================
# STAR REPLICA: AUTOMA - SPHERICAL SEED UNIT & DOCKED FABRICATOR DRONES
# Radial planet anchoring (Zero Drift) + Open-World Inertial Flight (Newtons 1st Law).
# Fully operable with 1 Joystick + ABXY buttons.
# ==============================================================================

const GROUND_SPEED: float = 175.0
const SPACE_ACCEL: float = 420.0
const SURFACE_LOCK_R: float = PlanetWorld.R_SURFACE + 24.0

var world: PlanetWorld
var factory: FactorySim

var tex_core: Texture2D
var tex_drone: Texture2D
var anim_time: float = 0.0
var mine_cooldown: float = 0.0
var grounded_warn_cd: float = 0.0
var mine_beams: Array[Dictionary] = []

var virtual_move_vec: Vector2 = Vector2.ZERO
var virtual_mine_active: bool = false
var is_anchored_surface: bool = true
var brake_active: bool = false

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tex_core = load("res://assets/sprites/player_core_sheet.png")
	tex_drone = load("res://assets/sprites/fabricator_drone_sheet.png")
	reset_to_spawn()

func reset_to_spawn() -> void:
	var a = PlanetWorld.sector_center_angle(PlanetWorld.SPAWN_SECTOR)
	position = Vector2(cos(a), sin(a)) * (PlanetWorld.R_SURFACE + 24.0)
	velocity = Vector2.ZERO
	rotation = a + PI * 0.5
	is_anchored_surface = true
	brake_active = false

func setup(p_world: PlanetWorld, p_factory: FactorySim) -> void:
	world = p_world
	factory = p_factory

func set_virtual_input(move_vec: Vector2, mining: bool) -> void:
	virtual_move_vec = move_vec
	virtual_mine_active = mining

func trigger_brake() -> void:
	brake_active = true
	velocity = Vector2.ZERO
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
	var dist_center = position.length()
	var normal = position.normalized() if dist_center > 1.0 else Vector2.UP
	var max_flight = GameState.get_flight_speed()
	var in_open_space = dist_center > PlanetWorld.R_ATMOS_OUTER
	var is_lifting_off = (GameState.engine_tier > 0 and move_dir.length_squared() > 0.01 and move_dir.normalized().dot(normal) > 0.45)
	var airborne = dist_center > PlanetWorld.R_SURFACE + 38.0 or is_lifting_off

	is_anchored_surface = false

	if in_open_space and GameState.engine_tier > 0:
		# Deep Open World: Pure Uniform Linear Motion (Newtons 1st Law), speed capped by Engine Tier
		if Input.is_key_pressed(KEY_B) or brake_active:
			velocity = velocity.move_toward(Vector2.ZERO, SPACE_ACCEL * 2.8 * delta)
			if velocity.length() < 4.0:
				velocity = Vector2.ZERO
				brake_active = false
		elif move_dir.length_squared() > 0.01:
			brake_active = false
			velocity += move_dir.normalized() * SPACE_ACCEL * delta
			if velocity.length() > max_flight:
				velocity = velocity.normalized() * max_flight
		if velocity.length() > 15.0:
			rotation = lerp_angle(rotation, velocity.angle() + PI * 0.5, clampf(6.0 * delta, 0.0, 1.0))
	else:
		# Planetary Surface, Underground & Thick Atmosphere
		brake_active = false
		var target_rot = position.angle() + PI * 0.5
		rotation = lerp_angle(rotation, target_rot, clampf(12.0 * delta, 0.0, 1.0))
		if move_dir.length_squared() > 0.01:
			var want_dir = move_dir.normalized()
			var radial_out = want_dir.dot(normal)
			# If Grounded (no Engine printed yet), block flying off planet surface!
			if GameState.engine_tier <= 0 and dist_center >= PlanetWorld.R_SURFACE + 14.0 and radial_out > 0.15:
				want_dir = (want_dir - normal * radial_out)
				if want_dir.length_squared() > 0.01:
					want_dir = want_dir.normalized()
				else:
					want_dir = Vector2.ZERO
				if grounded_warn_cd <= 0.0:
					grounded_warn_cd = 2.5
					GameState.emit_signal("log_event", "GROUNDED: Print Thruster Mk-I via [Y] PRINTER!", "warn")
			var spd = max_flight if airborne else GROUND_SPEED
			if not in_open_space and dist_center <= PlanetWorld.R_SURFACE + 38.0 and not is_lifting_off and move_dir.dot(normal) >= -0.25 and dist_center >= PlanetWorld.R_SURFACE - 6.0:
				# Hug curved spherical surface gently while moving laterally unless lifting off outward!
				var tang_dir = (want_dir - normal * radial_out)
				if tang_dir.length_squared() > 0.01:
					want_dir = (tang_dir.normalized() - normal * 0.18).normalized()
			velocity = velocity.lerp(want_dir * spd, clampf(16.0 * delta, 0.0, 1.0))
		else:
			velocity = Vector2.ZERO
			is_anchored_surface = true

	var next_pos = position + velocity * delta
	# Clamp atmospheric ceiling back to ground when engine_tier == 0
	if GameState.engine_tier <= 0 and next_pos.length() > SURFACE_LOCK_R:
		next_pos = next_pos.normalized() * SURFACE_LOCK_R
		if velocity.dot(normal) > 0.0:
			velocity -= normal * velocity.dot(normal)

	# Keep within open-world cosmic boundary
	if next_pos.length() > PlanetWorld.WORLD_LIMIT_R - 80.0:
		next_pos = next_pos.normalized() * (PlanetWorld.WORLD_LIMIT_R - 80.0)
		velocity = Vector2.ZERO

	# Inner magma boundary + solid planetary terrain collision / auto-drill
	if world and next_pos.length() <= PlanetWorld.R_SURFACE + 4.0:
		if next_pos.length() < PlanetWorld.R_MAGMA + 24.0:
			next_pos = next_pos.normalized() * (PlanetWorld.R_MAGMA + 24.0)
			velocity = Vector2.ZERO
		elif world.is_point_solid(next_pos):
			var c = world.pos_to_cell(next_pos)
			if GameState.selected_tool == "pick" and move_dir.length_squared() > 0.01 and mine_cooldown <= 0.0:
				_mine_cell(c.x, c.y)
			# Allow smooth tangential sliding along curved solid surface!
			var surf_r = SURFACE_LOCK_R
			if position.length() >= PlanetWorld.R_SURFACE - 6.0 and move_dir.dot(normal) >= -0.35:
				next_pos = next_pos.normalized() * surf_r
			else:
				next_pos = position
				velocity = Vector2.ZERO

	position = next_pos

	# Audio ambience blend
	AudioSynth.update_celestial_ambience(0.0, 0.0, clampf(move_dir.length(), 0.0, 1.0))

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
	# Gamepad Left Analog Stick support
	var joy = Vector2(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
	if joy.length() > 0.18:
		v += joy
	v += virtual_move_vec
	if v.length() > 1.0:
		v = v.normalized()
	return v

func _perform_mining() -> void:
	if not world: return
	var nearest = world.find_nearest_mine_target(position, 165.0)
	if nearest.is_empty():
		return
	if nearest["type"] == "asteroid":
		_mine_asteroid(nearest["pos"])
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
	var ring_r = 32.0 if total <= 6 else 38.0
	var ang = anim_time * 1.65 + (TAU * float(idx) / maxf(1.0, float(total)))
	return Vector2(cos(ang) * ring_r, sin(ang) * ring_r * 0.68 - 4.0)

func _draw() -> void:
	var font = ThemeDB.fallback_font
	# Transform world-space beams cleanly back to player-rotated local space
	var inv_rot = -rotation
	for mb in mine_beams:
		var a = clampf(mb["life"] / 0.16, 0.0, 1.0)
		var f_loc = (mb["from"] - position).rotated(inv_rot)
		var t_loc = (mb["to"] - position).rotated(inv_rot)
		var col = Color(0.25, 0.96, 1.0, a) if mb["main"] else Color(1.0, 0.78, 0.28, a * 0.85)
		draw_line(f_loc, t_loc, col, 2.5 if mb["main"] else 1.5)
		draw_circle(t_loc, 4.0 * a, Color(0.85, 1.0, 1.0, a))

	var frame_idx = int(anim_time * 6.0) % 4
	# Subtle Seed Unit radial shield aura & thruster core glow for high visibility
	draw_circle(Vector2.ZERO, 28.0, Color(0.16, 0.72, 1.0, 0.14))
	draw_arc(Vector2.ZERO, 26.0, 0.0, TAU, 24, Color(0.32, 0.94, 1.0, 0.34), 1.4)
	if velocity.length() > 25.0:
		var thrust_p = Vector2(-velocity.rotated(inv_rot).normalized()) * 22.0
		draw_circle(thrust_p, 8.0, Color(0.30, 0.92, 1.0, 0.45))
	if tex_core:
		var fw = float(tex_core.get_width()) / 4.0
		var src = Rect2(frame_idx * fw, 0.0, fw, float(tex_core.get_height()))
		draw_texture_rect_region(tex_core, Rect2(-24.0, -24.0, 48.0, 48.0), src)

	if tex_drone and GameState.drones > 0:
		var dw = float(tex_drone.get_width()) / 4.0
		var df = int(anim_time * 8.0) % 4
		var dsrc = Rect2(df * dw, 0.0, dw, float(tex_drone.get_height()))
		var vis_d = mini(GameState.drones, 12)
		for i in range(vis_d):
			var off = _get_drone_offset(i, vis_d)
			draw_line(Vector2.ZERO, off, Color(0.22, 0.85, 1.0, 0.22), 1.0)
			draw_texture_rect_region(tex_drone, Rect2(off - Vector2(10.0, 10.0), Vector2(20.0, 20.0)), dsrc)

	# Unrotated upright floating popup beside Seed Unit
	draw_set_transform(Vector2.ZERO, inv_rot)
	if font and GameState.recent_ore_timer > 0.0 and GameState.recent_ore_amount > 0:
		var alpha = clampf(GameState.recent_ore_timer / 0.5, 0.0, 1.0)
		var txt = "+%d %s" % [GameState.recent_ore_amount, GameState.recent_ore_type.to_upper()]
		draw_string(font, Vector2(31.0, -13.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0, 0, 0, alpha * 0.9))
		draw_string(font, Vector2(30.0, -14.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.42, 1.0, 0.72, alpha))
	draw_set_transform(Vector2.ZERO, 0.0)
