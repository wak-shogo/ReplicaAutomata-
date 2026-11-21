extends Node2D

# Procedural Cylinder -> Apollo Lander Evolving Spacecraft with Full Newtonian
# Multi-Body Gravity, Zero-Drag Vacuum Keplerian Orbit, RCS Attitude + Axial Bell Thrust,
# Electric Ion Anti-Softlock Backup, Tethered Fabricator Drones & Multi-Beam Mining Laser.

var world: Node2D = null
var factory: Node2D = null
var swarm: Node2D = null

var velocity: Vector2 = Vector2.ZERO
var on_ground: bool = false
var thrust_input: Vector2 = Vector2.ZERO # Stick / WASD in screen/horizon frame
var braking: bool = false
var mining_active: bool = false
var mine_target: Dictionary = {}
var firing_chemical: bool = false
var firing_ion: bool = false
var rcs_torque_vis: float = 0.0
var local_grav_g: float = 1.0
var anim_t: float = 0.0

const SHIP_R: float = 20.0

func _ready() -> void:
	z_index = 25
	spawn_at_north_pole()

func spawn_at_north_pole() -> void:
	position = Vector2(0.0, -(PlanetWorld.R_SURFACE + 24.0))
	velocity = Vector2.ZERO
	rotation = 0.0
	on_ground = false
	mine_target = {}

func self_destruct_respawn() -> void:
	if world:
		world.spawn_spark_burst(position, Color(1.0, 0.52, 0.22), 28)
	AudioSynth.play_sfx("explosion")
	GameState.hp = GameState.max_hp
	GameState.ion_battery = GameState.max_ion_battery
	GameState.fuel = GameState.max_fuel * 0.5
	spawn_at_north_pole()
	GameState.add_log("Emergency Capsule Re-Drop deployed at North Pole.", "warn")

func get_altitude() -> float:
	return position.length() - PlanetWorld.R_SURFACE

func trigger_primary_press() -> void:
	if not factory:
		return
	var tool := GameState.selected_tool
	if tool == "wire":
		factory.try_wire_near(position)
		return
	if tool == "demolish":
		factory.try_demolish_near(position)
		return
	if GameState.BUILDINGS.has(tool):
		factory.try_place_active_blueprint()
		return
	# Pick mode: first check nearby interactive facility (Depot, Smelter, Assembler, Printer, Unwired Power)
	if factory.try_interact_near(position):
		return
	# Otherwise initiate mining laser immediately
	mining_active = true

func _physics_process(delta: float) -> void:
	anim_t += delta
	firing_chemical = false
	firing_ion = false
	rcs_torque_vis = 0.0
	if not world:
		return

	var r := position.length()
	var up := position.normalized() if r > 1.0 else Vector2.UP
	var tang_cw := Vector2(-up.y, up.x) # +X along curved surface horizon

	# 1. Multi-body Newtonian Gravity
	var grav: Vector2 = world.compute_gravity_at(position)
	local_grav_g = grav.length() / PlanetWorld.GRAV_SURF
	velocity += grav * delta

	# 2. Convert joystick input to world thrust direction
	# Below 850m altitude: local horizon frame (+X = CW along planet, -Y = radially UP)
	# High atmosphere & Space: intuitive world screen frame (+X right, -Y up)
	var stick := thrust_input
	if stick.length() > 1.0:
		stick = stick.normalized()
	var world_dir := Vector2.ZERO
	if stick.length() > 0.08:
		if r <= PlanetWorld.R_SURFACE + 850.0:
			world_dir = (tang_cw * stick.x + up * (-stick.y)).normalized()
		else:
			world_dir = stick.normalized()

	# 3. Attitude Rotation (RCS) + Axial Chemical Rocket or Electric Ion Backup
	var tier_info: Dictionary = GameState.VESSEL_TIERS[GameState.vessel_tier]
	var chem_thrust := float(tier_info["thrust"])
	var ion_thrust := float(tier_info["ion_thrust"])
	var max_spd := float(tier_info["max_spd"])
	var alt := r - PlanetWorld.R_SURFACE

	if world_dir.length() > 0.08:
		var target_rot := world_dir.angle() + PI * 0.5
		var diff := wrapf(target_rot - rotation, -PI, PI)
		var turn_spd := 5.2 + float(GameState.vessel_tier) * 1.35
		rcs_torque_vis = clampf(diff * 2.5, -1.0, 1.0)
		rotation = wrapf(rotation + clampf(diff, -turn_spd * delta, turn_spd * delta), -PI, PI)

		var mag := stick.length()
		var axial := Vector2.UP.rotated(rotation)
		var align := maxf(0.18, axial.dot(world_dir))

		if GameState.vessel_tier >= 1 and GameState.fuel > 0.1:
			# True Axial Chemical Rocket Thrust
			firing_chemical = true
			var thrust_vec := axial * (chem_thrust * mag * align)
			velocity += thrust_vec * delta
			var burn_rate := (4.8 if GameState.vessel_tier == 1 else (3.6 if GameState.vessel_tier == 2 else 2.5)) * mag
			GameState.fuel = maxf(0.0, GameState.fuel - burn_rate * delta)
		elif GameState.ion_battery > 0.5:
			# Electric Ion Thruster Backup (anti-softlock! Recharges passively from sunlight/base)
			firing_ion = true
			# Tier 0 Seed Capsule cannot escape planetary gravity above 75m alt (must print Lander Mk-I to fly!)
			var thrust_dir := world_dir
			var eff_ion := ion_thrust
			if GameState.vessel_tier == 0:
				if alt > 75.0:
					var out_comp := thrust_dir.dot(up)
					if out_comp > 0.0:
						thrust_dir = (thrust_dir - up * out_comp).normalized()
				elif alt < 25.0 and thrust_dir.dot(up) > 0.25:
					# Trench/ledge climb boost so surface trenches never trap the capsule
					eff_ion *= 1.45
			velocity += thrust_dir * (eff_ion * mag) * delta
			GameState.ion_battery = maxf(0.0, GameState.ion_battery - 26.0 * mag * delta)
	elif on_ground:
		# Gently self-right upright with planet normal while resting on terrain
		var upright_rot := up.angle() + PI * 0.5
		var diff := wrapf(upright_rot - rotation, -PI, PI)
		rotation = wrapf(rotation + clampf(diff, -4.5 * delta, 4.5 * delta), -PI, PI)

	# 4. Retrograde Hover Brake ([B])
	if braking:
		var brake_f := exp(-6.8 * delta)
		velocity *= brake_f
		if velocity.length() < 8.0:
			velocity = Vector2.ZERO

	# 5. Atmospheric Drag ONLY inside atmosphere (r < R_ATMOS); STRICTLY ZERO in vacuum space!
	var atmos: float = world.get_atmos_density(position)
	if atmos > 0.0:
		var drag_k := 0.34 * atmos
		if GameState.vessel_tier == 0:
			drag_k = 0.85
		elif GameState.vessel_tier == 1:
			# Makes Tier 1 atmospheric climb feel weighty (~45-55s ascent) while keeping orbital speed attainable
			drag_k = 0.42 * atmos
		velocity *= exp(-drag_k * delta)
		# Soft atmospheric terminal speed cap ONLY inside dense atmosphere
		if atmos > 0.25 and velocity.length() > max_spd * 1.45:
			velocity = velocity.normalized() * lerpf(velocity.length(), max_spd * 1.45, delta * 3.0)

	# 6. Integrate Position & Resolve Planetary / Moon Collisions
	position += velocity * delta
	on_ground = false
	_resolve_terrain_collision(delta)

	var mhit: Dictionary = world.check_moon_collision(position, SHIP_R)
	if bool(mhit.get("hit", false)):
		position = mhit["push_pos"]
		var mn: Vector2 = mhit["normal"]
		var vn := velocity.dot(mn)
		if vn < 0.0:
			velocity -= mn * vn
			velocity *= 0.88
		on_ground = true

	# 7. Factory Auto-Pickup & Service Pad Refuel/Recharge
	if factory:
		factory.collect_nearby_items(position, 92.0)
		factory.service_player(position, delta)

	# 8. Continuous Multi-Beam Mining Laser & Combat Laser (when [A] held)
	mine_target = {}
	if mining_active and GameState.selected_tool == "pick":
		var prefer_side := (stick.y <= 0.35) # Only dig straight down if player pushes stick downward!
		var aim_w := world_dir if world_dir.length() > 0.1 else Vector2.UP.rotated(rotation)
		var reach := 235.0 + float(GameState.drones) * 18.0
		var tgt: Dictionary = world.find_nearest_mine_target(position, aim_w, reach, prefer_side)
		if not tgt.is_empty():
			mine_target = tgt
			var dps := (24.0 + float(GameState.drones) * 6.5 + float(GameState.vessel_tier) * 8.0) * delta
			world.damage_mine_target(tgt, dps)
		elif swarm and not GameState.boss_defeated:
			# Allow player ship laser to directly damage boss or raiders when in range!
			if position.distance_to(swarm.boss_pos) <= 520.0:
				mine_target = {"kind": "boss", "pos": swarm.boss_pos}
				swarm.damage_boss((45.0 + float(GameState.vessel_tier) * 28.0) * delta)

	queue_redraw()

func _resolve_terrain_collision(delta: float) -> void:
	var r := position.length()
	if r < PlanetWorld.R_CORE + SHIP_R:
		var n := position.normalized()
		position = n * (PlanetWorld.R_CORE + SHIP_R)
		var vn := velocity.dot(n)
		if vn < 0.0:
			velocity -= n * vn
		on_ground = true
		return

	if r > PlanetWorld.R_SURFACE + SHIP_R + 8.0:
		return

	# Check 5 perimeter sample points around circular vessel hull
	var up := position.normalized()
	var tang := Vector2(-up.y, up.x)
	var samples: Array[Vector2] = [
		-up * SHIP_R,
		(tang * 0.72 - up * 0.68) * SHIP_R,
		(-tang * 0.72 - up * 0.68) * SHIP_R,
		tang * SHIP_R,
		-tang * SHIP_R,
		up * SHIP_R,
	]
	for off in samples:
		var sp: Vector2 = position + off
		var cell: Vector2i = world.world_to_cell(sp)
		if world.is_cell_solid(cell.x, cell.y):
			var push_dir: Vector2 = (-off).normalized()
			if off.dot(up) < -SHIP_R * 0.4:
				# Landed cleanly on planetary crust!
				var top_r := PlanetWorld.layer_outer_r(cell.y) + SHIP_R
				if r < top_r + 14.0:
					position = up * maxf(r, top_r)
				var vn := velocity.dot(up)
				if vn < 0.0:
					velocity -= up * vn
				# Gentle surface traction friction so walking stops crisply
				var vt := velocity.dot(tang)
				velocity -= tang * (vt * minf(1.0, delta * 3.8))
				on_ground = true
			else:
				position += push_dir * 4.5
				var vn := velocity.dot(push_dir)
				if vn < 0.0:
					velocity -= push_dir * vn * 1.05

# ------------------------------------------------------------------------------
# PROCEDURAL CYLINDER -> APOLLO LANDER VESSEL RENDERING + DRONES & LASERS
# ------------------------------------------------------------------------------
func _draw() -> void:
	var tier := GameState.vessel_tier
	var glow := ArtRegistry.get_tex("glow_soft")

	# 1. Active Mining / Combat Laser Beams (Main + Tethered Drone Beams!)
	if not mine_target.is_empty():
		var local_tgt := to_local(Vector2(mine_target["pos"]))
		var bcol := Color(0.32, 0.94, 1.0, 0.88) if String(mine_target.get("kind", "")) != "boss" else Color(1.0, 0.45, 0.25, 0.92)
		draw_line(Vector2(0, -14), local_tgt, bcol, 5.2)
		draw_line(Vector2(0, -14), local_tgt, Color(0.95, 1.0, 1.0, 0.95), 1.8)
		if glow:
			draw_texture_rect(glow, Rect2(local_tgt.x - 24, local_tgt.y - 24, 48, 48), false, bcol)

	# 2. Thruster Plumes (Chemical Orange-Gold Flame vs Electric Cyan Ion Jet)
	if firing_chemical:
		var fl := 24.0 + float(tier) * 10.0 + sin(anim_t * 48.0) * 6.0
		var bell_y := 16.0 if tier == 1 else 21.0
		if glow:
			draw_texture_rect(glow, Rect2(-26, bell_y - 4, 52, fl + 24), false, Color(1.0, 0.62, 0.18, 0.52))
		draw_polygon(PackedVector2Array([Vector2(-7, bell_y), Vector2(7, bell_y), Vector2(0, bell_y + fl)]), PackedColorArray([Color(1.0, 0.58, 0.14, 0.92)]))
		draw_polygon(PackedVector2Array([Vector2(-4, bell_y), Vector2(4, bell_y), Vector2(0, bell_y + fl * 0.65)]), PackedColorArray([Color(1.0, 0.96, 0.78, 0.95)]))
	elif firing_ion:
		var fl := 16.0 + sin(anim_t * 36.0) * 4.0
		if glow:
			draw_texture_rect(glow, Rect2(-18, 10, 36, fl + 16), false, Color(0.28, 0.88, 1.0, 0.42))
		draw_polygon(PackedVector2Array([Vector2(-5, 13), Vector2(5, 13), Vector2(0, 13 + fl)]), PackedColorArray([Color(0.32, 0.92, 1.0, 0.88)]))

	# RCS Attitude Puffs
	if absf(rcs_torque_vis) > 0.15:
		var sgn := signf(rcs_torque_vis)
		draw_line(Vector2(-sgn * 10, -8), Vector2(-sgn * 20, -8), Color(0.85, 0.95, 1.0, 0.7), 2.0)

	# 3. Tier 3 Deployable Solar Wing Arrays (behind chassis)
	if tier >= 3:
		for sx in [-1.0, 1.0]:
			draw_line(Vector2(sx * 12, -2), Vector2(sx * 36, -2), Color(0.74, 0.80, 0.88), 2.4)
			var rx := 15.0 if sx > 0 else -39.0
			draw_rect(Rect2(rx, -9, 24, 14), Color(0.10, 0.30, 0.62))
			draw_rect(Rect2(rx, -9, 24, 14), Color(0.45, 0.85, 1.0), false, 1.4)
			draw_line(Vector2(rx + 8, -9), Vector2(rx + 8, 5), Color(0.34, 0.74, 0.98), 1.0)
			draw_line(Vector2(rx + 16, -9), Vector2(rx + 16, 5), Color(0.34, 0.74, 0.98), 1.0)

	# 4. Tier 1+ Articulated Apollo Lander Struts & Chemical Rocket Bell
	if tier >= 1:
		var strut_col := Color(0.88, 0.72, 0.32) if tier >= 2 else Color(0.76, 0.82, 0.90)
		for sx in [-1.0, 1.0]:
			draw_line(Vector2(sx * 9, 4), Vector2(sx * 19, 19), strut_col, 2.6)
			draw_line(Vector2(sx * 8, 12), Vector2(sx * 16, 14), Color(0.46, 0.54, 0.64), 1.6)
			draw_rect(Rect2(sx * 19 - 4, 18, 8, 3), Color(0.92, 0.84, 0.56))
		# Flared Chemical Bell Nozzle
		var bell := PackedVector2Array([Vector2(-5, 11), Vector2(5, 11), Vector2(8, 19), Vector2(-8, 19)])
		draw_polygon(bell, PackedColorArray([Color(0.28, 0.32, 0.40)]))
		draw_polyline(bell, Color(0.68, 0.74, 0.84), 1.2)

	# 5. Tier 2+ Kapton Gold-Foil Apollo Descent Module & Twin Cryo Spheres
	if tier >= 2:
		var gold := PackedVector2Array([Vector2(-12, 2), Vector2(12, 2), Vector2(15, 12), Vector2(-15, 12)])
		draw_polygon(gold, PackedColorArray([Color(0.88, 0.66, 0.18)]))
		draw_polyline(gold, Color(0.32, 0.22, 0.06), 1.4)
		# Cryo propellant spheres on sides
		draw_circle(Vector2(-13, -1), 4.5, Color(0.86, 0.90, 0.96))
		draw_circle(Vector2(13, -1), 4.5, Color(0.86, 0.90, 0.96))
		# Parabolic high-gain dish antenna
		draw_line(Vector2(7, -12), Vector2(12, -19), Color(0.78, 0.84, 0.92), 1.6)
		draw_arc(Vector2(13, -20), 4.5, PI * 0.1, PI * 1.1, 10, Color(0.95, 0.97, 1.0), 1.8)

	# 6. Core Minimal Cylindrical Seed Capsule (ALWAYS visible as the heart of the ship!)
	var cyl := Rect2(-8, -14, 16, 26)
	draw_rect(cyl, Color(0.68, 0.74, 0.82))
	draw_rect(Rect2(-8, -14, 5, 26), Color(0.86, 0.90, 0.96)) # Specular metal highlight
	draw_rect(Rect2(4, -14, 4, 26), Color(0.42, 0.48, 0.58))  # Shadow edge
	draw_rect(cyl, Color(0.10, 0.14, 0.20), false, 1.6)
	# Top cap or Tier 3 aerodynamic command cone
	if tier >= 3:
		draw_polygon(PackedVector2Array([Vector2(-8, -14), Vector2(0, -26), Vector2(8, -14)]), PackedColorArray([Color(0.92, 0.94, 0.98)]))
		draw_polyline(PackedVector2Array([Vector2(-8, -14), Vector2(0, -26), Vector2(8, -14)]), Color(0.12, 0.16, 0.24), 1.5)
	else:
		draw_rect(Rect2(-6, -17, 12, 4), Color(0.54, 0.60, 0.70))
		draw_rect(Rect2(-6, -17, 12, 4), Color(0.10, 0.14, 0.20), false, 1.4)
	# Glowing cyan core optic visor
	draw_rect(Rect2(-5, -8, 10, 6), Color(0.10, 0.22, 0.34))
	draw_rect(Rect2(-4, -7, 8, 4), Color(0.32, 0.94, 1.0))
	draw_rect(Rect2(-3, -6, 3, 2), Color(0.86, 1.0, 1.0))
	# Bottom electric ion emitter ring
	draw_rect(Rect2(-6, 10, 12, 3), Color(0.28, 0.86, 1.0) if GameState.ion_battery > 5.0 else Color(0.4, 0.25, 0.25))

	# 7. Tethered Fabricator Drones orbiting vessel
	for i in range(GameState.drones):
		var a := anim_t * 1.9 + float(i) * (TAU / maxf(1.0, float(GameState.drones)))
		var dp := Vector2(cos(a) * 34.0, sin(a) * 26.0)
		draw_circle(dp, 5.0, Color(0.14, 0.18, 0.26))
		draw_circle(dp, 3.6, Color(0.92, 0.76, 0.32))
		draw_circle(dp, 1.8, Color(0.35, 0.96, 1.0))
		if not mine_target.is_empty():
			var lt := to_local(Vector2(mine_target["pos"]))
			draw_line(dp, lt, Color(0.38, 0.94, 1.0, 0.55), 1.6)
