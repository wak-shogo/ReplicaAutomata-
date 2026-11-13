extends CharacterBody2D
class_name PlayerUnit

# ==============================================================================
# STAR REPLICA: AUTOMA - SEED UNIT & DOCKED FABRICATOR DRONES
# Grounded Zero-Drift Magnetic Hover on Planet Surface / Tunnels +
# Pure Uniform Linear Motion (Inertial Flight) in Deep Space Orbit.
# ==============================================================================

const GROUND_SPEED: float = 235.0
const SPACE_ACCEL: float = 440.0
const SPACE_MAX_SPEED: float = 420.0
const SURFACE_HOVER_Y: float = -24.0

var world: PlanetWorld
var factory: FactorySim

var tex_core: Texture2D
var tex_drone: Texture2D
var anim_time: float = 0.0
var mine_cooldown: float = 0.0
var mine_beams: Array[Dictionary] = []

var virtual_move_vec: Vector2 = Vector2.ZERO
var virtual_mine_active: bool = false
var is_anchored_surface: bool = true
var brake_active: bool = false

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tex_core = load("res://assets/sprites/player_core_sheet.png")
	tex_drone = load("res://assets/sprites/fabricator_drone_sheet.png")
	position = Vector2(PlanetWorld.SPAWN_COL * PlanetWorld.TILE_SIZE, SURFACE_HOVER_Y)

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

func _physics_process(delta: float) -> void:
	anim_time += delta
	var move_dir = _read_move_input()

	var in_orbit = position.y < -52.0
	is_anchored_surface = false

	if in_orbit:
		# Deep Space: Pure Uniform Linear Motion (Newtons 1st Law)
		if Input.is_key_pressed(KEY_B) or brake_active:
			velocity = velocity.move_toward(Vector2.ZERO, SPACE_ACCEL * 2.5 * delta)
			if velocity.length() < 4.0:
				velocity = Vector2.ZERO
				brake_active = false
		elif move_dir.length_squared() > 0.01:
			brake_active = false
			velocity += move_dir.normalized() * SPACE_ACCEL * delta
			if velocity.length() > SPACE_MAX_SPEED:
				velocity = velocity.normalized() * SPACE_MAX_SPEED
		# Zero friction in orbit when no brake pressed -> pure uniform linear cruise!
	else:
		# Planetary Surface & Underground Caverns: Crisp zero-drift hover control
		brake_active = false
		if move_dir.length_squared() > 0.01:
			var target_v = move_dir.normalized() * GROUND_SPEED
			velocity = velocity.lerp(target_v, clampf(16.0 * delta, 0.0, 1.0))
		else:
			# Immediate magnetic stop so surface craft NEVER drifts!
			velocity = Vector2.ZERO
			if absf(position.y - SURFACE_HOVER_Y) <= 18.0:
				is_anchored_surface = true

	var next_pos = position + velocity * delta
	# Clamp world horizontal bounds cleanly & ceiling
	next_pos.x = clampf(next_pos.x, 48.0, PlanetWorld.WORLD_WIDTH - 48.0)
	next_pos.y = clampf(next_pos.y, -2050.0, PlanetWorld.WORLD_HEIGHT - 64.0)

	# Prevent passing straight into solid unmined rock (slide cleanly & auto-mine when holding pick)
	if world and next_pos.y > -8.0:
		var tc = world.world_to_tile(next_pos)
		if world.is_solid(tc.x, tc.y):
			# If moving downward/sideways into solid tile with pick selected, auto-chip the rock!
			if GameState.selected_tool == "pick" and move_dir.length_squared() > 0.01:
				if mine_cooldown <= 0.0:
					_mine_tile_at(tc.x, tc.y)
			# Slide along non-solid axis if possible
			var tc_x = world.world_to_tile(Vector2(next_pos.x, position.y))
			var tc_y = world.world_to_tile(Vector2(position.x, next_pos.y))
			if not world.is_solid(tc_x.x, tc_x.y):
				next_pos.y = position.y
			elif not world.is_solid(tc_y.x, tc_y.y):
				next_pos.x = position.x
			else:
				next_pos = position
				velocity = Vector2.ZERO

	# Gentle surface horizon snap when cruising flat on surface
	if move_dir.length_squared() > 0.01 and absf(move_dir.y) < 0.2 and absf(next_pos.y - SURFACE_HOVER_Y) < 10.0:
		next_pos.y = lerpf(next_pos.y, SURFACE_HOVER_Y, clampf(10.0 * delta, 0.0, 1.0))

	position = next_pos

	# Audio thruster ambience update
	var thrust_ratio = clampf(move_dir.length(), 0.0, 1.0)
	AudioSynth.update_celestial_ambience(0.0, 0.0, thrust_ratio)

	# Decay beams & handle mining
	for bi in range(mine_beams.size() - 1, -1, -1):
		mine_beams[bi]["life"] -= delta
		if mine_beams[bi]["life"] <= 0.0:
			mine_beams.remove_at(bi)

	if mine_cooldown > 0.0:
		mine_cooldown -= delta

	var wants_mine = virtual_mine_active or Input.is_key_pressed(KEY_SPACE) or (
		GameState.selected_tool == "pick" and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not _is_pointer_over_ui()
	)
	if wants_mine and mine_cooldown <= 0.0:
		_perform_mining()

	queue_redraw()

func _read_move_input() -> Vector2:
	var v = Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): v.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): v.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): v.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): v.y += 1.0
	v += virtual_move_vec
	if v.length() > 1.0:
		v = v.normalized()
	return v

func _is_pointer_over_ui() -> bool:
	var hud = get_tree().root.find_child("HUD", true, false)
	if hud and hud.has_method("is_blocking_world_input"):
		return hud.is_blocking_world_input()
	return false

func _perform_mining() -> void:
	if not world:
		return
	var target_pos = Vector2.ZERO
	var cursor_world = get_global_mouse_position()
	var picked_tile = Vector2i(-1, -1)

	# If mouse/touch directly points near a valid solid tile within laser reach, prioritize it
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and cursor_world.distance_to(position) <= 170.0:
		var mt = world.world_to_tile(cursor_world)
		if world.is_solid(mt.x, mt.y) and mt.y < PlanetWorld.MAGMA_START_ROW:
			picked_tile = mt
			target_pos = world.tile_to_world_center(mt.x, mt.y)

	if picked_tile.x == -1:
		var nearest = world.find_nearest_mine_target(position, 145.0)
		if nearest.is_empty():
			return
		if nearest["type"] == "asteroid":
			_mine_asteroid(nearest["pos"])
			return
		picked_tile = nearest["tile"]
		target_pos = nearest["pos"]

	_mine_tile_at(picked_tile.x, picked_tile.y, target_pos)

func _mine_tile_at(c: int, r: int, world_target: Vector2 = Vector2.ZERO) -> void:
	if not world:
		return
	var tgt = world_target if world_target != Vector2.ZERO else world.tile_to_world_center(c, r)
	var beam_count = 1 + GameState.drones
	var dmg = 3.5 + float(GameState.drones) * 2.2
	world.damage_tile(c, r, dmg, true)
	mine_cooldown = 0.24
	AudioSynth.play_synth("mine")
	_emit_mining_beams(tgt, mini(beam_count, 7))

func _mine_asteroid(ast_pos: Vector2) -> void:
	var dmg = 7.0 + float(GameState.drones) * 4.0
	world.mine_asteroid_at(ast_pos, dmg, 190.0)
	mine_cooldown = 0.24
	AudioSynth.play_synth("mine")
	_emit_mining_beams(ast_pos, mini(1 + GameState.drones, 7))

func _emit_mining_beams(tgt: Vector2, beam_count: int) -> void:
	mine_beams.append({"from": position, "to": tgt, "life": 0.16, "main": true})
	var dc = mini(GameState.drones, beam_count - 1)
	for i in range(dc):
		var dpos = position + _get_drone_offset(i, GameState.drones)
		mine_beams.append({"from": dpos, "to": tgt, "life": 0.16, "main": false})

func _get_drone_offset(idx: int, total: int) -> Vector2:
	var ring_r = 32.0 if total <= 6 else 38.0
	var ang = anim_time * 1.65 + (TAU * float(idx) / maxf(1.0, float(total)))
	return Vector2(cos(ang) * ring_r, sin(ang) * ring_r * 0.68 - 6.0)

func _draw() -> void:
	var font = ThemeDB.fallback_font
	# Draw active laser beams in world space (player local coordinates -> offset by -position)
	for mb in mine_beams:
		var a = clampf(mb["life"] / 0.16, 0.0, 1.0)
		var f_loc = mb["from"] - position
		var t_loc = mb["to"] - position
		var col = Color(0.25, 0.95, 1.0, a) if mb["main"] else Color(1.0, 0.78, 0.28, a * 0.85)
		draw_line(f_loc, t_loc, col, 2.5 if mb["main"] else 1.5)
		draw_circle(t_loc, 4.0 * a, Color(0.8, 1.0, 1.0, a))

	# Draw Seed Unit Core sprite (4 frames of 48x48)
	var frame_idx = int(anim_time * 6.0) % 4
	if tex_core:
		var fw = float(tex_core.get_width()) / 4.0
		var fh = float(tex_core.get_height())
		var src = Rect2(frame_idx * fw, 0.0, fw, fh)
		draw_texture_rect_region(tex_core, Rect2(-24.0, -24.0, 48.0, 48.0), src)
	else:
		draw_circle(Vector2.ZERO, 16.0, Color(0.25, 0.85, 1.0))

	# Draw Docked Fabricator Drones orbiting around Seed Unit
	if tex_drone and GameState.drones > 0:
		var dw = float(tex_drone.get_width()) / 4.0
		var dh = float(tex_drone.get_height())
		var df = int(anim_time * 8.0) % 4
		var dsrc = Rect2(df * dw, 0.0, dw, dh)
		var vis_drones = mini(GameState.drones, 12)
		for i in range(vis_drones):
			var off = _get_drone_offset(i, vis_drones)
			draw_line(Vector2.ZERO, off, Color(0.2, 0.8, 1.0, 0.22), 1.0)
			draw_texture_rect_region(tex_drone, Rect2(off - Vector2(10.0, 10.0), Vector2(20.0, 20.0)), dsrc)

	# Cumulative Mining Gain Display beside Seed Unit (+23 FE)
	if font and GameState.recent_ore_timer > 0.0 and GameState.recent_ore_amount > 0:
		var alpha = clampf(GameState.recent_ore_timer / 0.5, 0.0, 1.0)
		var txt = "+%d %s" % [GameState.recent_ore_amount, GameState.recent_ore_type.to_upper()]
		var tpos = Vector2(30.0, -14.0)
		draw_string(font, tpos + Vector2(1, 1), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0, 0, 0, alpha * 0.9))
		draw_string(font, tpos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.42, 1.0, 0.72, alpha))

	# Magnetic Ground Lock indicator
	if font and is_anchored_surface and position.y >= -48.0:
		draw_string(font, Vector2(-24.0, 29.0), "ANCHORED", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.35, 0.85, 1.0, 0.65))
