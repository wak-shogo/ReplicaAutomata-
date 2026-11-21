extends Node2D

# Protagonist Seed Unit (DESIGN_SPECIFICATION.md):
# Starts as an autonomous armored Seed Unit; physically docks crafted Fabricator Drones (0..8)
# around its chassis on articulated mechanical arms to grow into a multi-beam industrial swarm mech!
# Bolts on Orbital Booster modules for full Newtonian Gravity & Zero-Drag Keplerian Orbit spaceflight.

var planet: SphericalPlanet = null
var grid: Node2D = null
var swarm: Node2D = null

var velocity: Vector2 = Vector2.ZERO
var on_ground: bool = false
var move_input: Vector2 = Vector2.ZERO
var aim_world: Vector2 = Vector2.ZERO
var braking: bool = false
var firing_mine: bool = false
var mine_target: Dictionary = {}
var firing_chem: bool = false
var firing_ion: bool = false
var local_g: float = 1.0
var anim_t: float = 0.0

const RADIUS: float = 18.0

func _ready() -> void:
	z_index = 25
	spawn_north_pole()

func spawn_north_pole() -> void:
	var r0 := SphericalPlanet.R_SURFACE + 28.0
	if planet:
		var sr := planet.get_surface_row(SphericalPlanet.SPAWN_COL)
		r0 = SphericalPlanet.R_CORE + float(sr + 1) * SphericalPlanet.CELL_H + RADIUS + 4.0
	position = Vector2(0.0, -r0)
	velocity = Vector2.ZERO
	rotation = 0.0
	on_ground = false
	mine_target = {}

func emergency_redrop() -> void:
	if planet: planet.spawn_sparks(position, Color(1.0, 0.56, 0.22), 24)
	Sfx.play("boom")
	State.hp = State.max_hp
	State.ion_bat = State.max_ion_bat
	State.fuel = State.max_fuel * 0.6
	spawn_north_pole()
	State.add_log("Emergency Seed Re-Drop complete at North Pole.", "warn")

func get_altitude() -> float:
	return position.length() - SphericalPlanet.R_SURFACE

func _physics_process(delta: float) -> void:
	anim_t += delta
	firing_chem = false; firing_ion = false
	if not planet: return

	var r := position.length()
	var up := position.normalized() if r > 1.0 else Vector2.UP
	var tang := Vector2(-up.y, up.x)

	# 1. Multi-body Newtonian Gravity
	var grav := planet.compute_gravity(position)
	local_g = grav.length() / SphericalPlanet.GRAV_SURF
	velocity += grav * delta

	# 2. Movement vector (local curved horizon below 650m alt; world space above)
	var inp := move_input
	if inp.length() > 1.0: inp = inp.normalized()
	var wdir := Vector2.ZERO
	if inp.length() > 0.08:
		wdir = (tang * inp.x + up * (-inp.y)).normalized() if r <= SphericalPlanet.R_SURFACE + 650.0 else inp.normalized()

	var tinfo: Dictionary = State.PROPULSION_TIERS[State.propulsion_tier]
	var chem_t := float(tinfo["thrust"])
	var ion_t := float(tinfo["ion"])
	var max_s := float(tinfo["max_spd"])
	var alt := r - SphericalPlanet.R_SURFACE

	if wdir.length() > 0.08:
		var mag := inp.length()
		var target_rot := (wdir.angle() + PI * 0.5) if State.propulsion_tier >= 1 and alt > 80.0 else (up.angle() + PI * 0.5)
		var diff := wrapf(target_rot - rotation, -PI, PI)
		rotation = wrapf(rotation + clampf(diff, -6.5 * delta, 6.5 * delta), -PI, PI)

		if State.propulsion_tier >= 1 and State.fuel > 0.1:
			firing_chem = true
			velocity += wdir * (chem_t * mag) * delta
			State.fuel = maxf(0.0, State.fuel - (4.2 if State.propulsion_tier == 1 else 2.8) * mag * delta)
		elif State.ion_bat > 0.5:
			firing_ion = true
			var tdir := wdir
			if State.propulsion_tier == 0 and alt > 95.0:
				var oc := tdir.dot(up)
				if oc > 0.0: tdir = (tdir - up * oc).normalized()
			velocity += tdir * (ion_t * mag) * delta
			State.ion_bat = maxf(0.0, State.ion_bat - 22.0 * mag * delta)
	else:
		var urot := up.angle() + PI * 0.5
		rotation = wrapf(rotation + clampf(wrapf(urot - rotation, -PI, PI), -5.0 * delta, 5.0 * delta), -PI, PI)

	if braking:
		velocity *= exp(-7.0 * delta)
		if velocity.length() < 6.0: velocity = Vector2.ZERO

	# 3. Atmospheric Drag ONLY inside atmosphere; STRICTLY ZERO in Vacuum Space!
	var atmos := planet.get_atmos_density(position)
	if atmos > 0.0:
		var dk := 0.85 if State.propulsion_tier == 0 else (0.36 * atmos)
		velocity *= exp(-dk * delta)
		if atmos > 0.25 and velocity.length() > max_s * 1.45:
			velocity = velocity.normalized() * lerpf(velocity.length(), max_s * 1.45, delta * 3.0)

	# 4. Integrate & Smooth Fine-Voxel Collision Resolution
	position += velocity * delta
	on_ground = false
	_resolve_collision(delta)

	var mhit := planet.check_moon_hit(position, RADIUS)
	if bool(mhit.get("hit", false)):
		position = mhit["push"]
		var mn: Vector2 = mhit["normal"]
		var vn := velocity.dot(mn)
		if vn < 0.0: velocity -= mn * vn; velocity *= 0.88
		on_ground = true

	if grid:
		grid.collect_near_player(position, 86.0)
		grid.service_player(position, delta)

	# 5. Multi-Beam Mining & Combat Laser (1 Core Beam + N Docked Fabricator Drone Beams!)
	mine_target = {}
	if firing_mine and State.selected_tool == "mine":
		var aim_dir := (aim_world - position).normalized() if aim_world.distance_to(position) > 8.0 else wdir
		var reach := 220.0 + float(State.attached_drones) * 24.0
		var tgt := planet.find_mine_target(position, aim_dir, reach)
		if not tgt.is_empty():
			mine_target = tgt
			var dps := (26.0 + float(State.attached_drones) * 8.5 + float(State.propulsion_tier) * 6.0) * delta
			planet.damage_target(tgt, dps)
		elif swarm and not State.boss_dead and position.distance_to(swarm.boss_pos) <= 460.0:
			mine_target = {"kind": "boss", "pos": swarm.boss_pos}
			swarm.damage_boss((50.0 + float(State.attached_drones) * 12.0) * delta)

	queue_redraw()

func _resolve_collision(delta: float) -> void:
	var r := position.length()
	if r < SphericalPlanet.R_CORE + 6.0 * SphericalPlanet.CELL_H + RADIUS:
		var n := position.normalized()
		position = n * (SphericalPlanet.R_CORE + 6.0 * SphericalPlanet.CELL_H + RADIUS)
		var vn := velocity.dot(n)
		if vn < 0.0: velocity -= n * vn
		on_ground = true
		return
	if r > SphericalPlanet.R_SURFACE + RADIUS + 24.0:
		return

	var up := position.normalized()
	var tang := Vector2(-up.y, up.x)
	var pts: Array[Vector2] = [
		-up * RADIUS,
		(tang * 0.7 - up * 0.7) * RADIUS,
		(-tang * 0.7 - up * 0.7) * RADIUS,
		tang * RADIUS, -tang * RADIUS, up * RADIUS,
	]
	for off in pts:
		var sp: Vector2 = position + off
		var c := planet.world_to_cell(sp)
		if planet.is_solid(c.x, c.y):
			var pdir: Vector2 = (-off).normalized()
			position += pdir * 4.2
			var vn := velocity.dot(pdir)
			if vn < 0.0: velocity -= pdir * vn * 1.02
			if off.dot(up) < -RADIUS * 0.4:
				on_ground = true
				var vt := velocity.dot(tang)
				velocity -= tang * (vt * minf(1.0, delta * 4.2))

# ------------------------------------------------------------------------------
# SEED UNIT + PHYSICALLY DOCKED FABRICATOR DRONES + MULTI-BEAM LASERS
# ------------------------------------------------------------------------------
func _draw() -> void:
	var glow := ArtReg.get_t("glow")
	var d_cnt := State.attached_drones

	# 1. Thruster Exhaust Flames
	if firing_chem:
		var fl := 26.0 + float(State.propulsion_tier) * 10.0 + sin(anim_t * 48.0) * 6.0
		if glow: draw_texture_rect(glow, Rect2(-26, 16, 52, fl + 22), false, Color(1.0, 0.62, 0.16, 0.55))
		draw_polygon(PackedVector2Array([Vector2(-9, 20), Vector2(9, 20), Vector2(0, 20 + fl)]), PackedColorArray([Color(1.0, 0.60, 0.14, 0.92)]))
		draw_polygon(PackedVector2Array([Vector2(-5, 20), Vector2(5, 20), Vector2(0, 20 + fl * 0.62)]), PackedColorArray([Color(1.0, 0.96, 0.78, 0.96)]))
	elif firing_ion:
		var fl := 15.0 + sin(anim_t * 36.0) * 3.5
		if glow: draw_texture_rect(glow, Rect2(-18, 12, 36, fl + 14), false, Color(0.28, 0.88, 1.0, 0.44))
		draw_polygon(PackedVector2Array([Vector2(-5, 16), Vector2(5, 16), Vector2(0, 16 + fl)]), PackedColorArray([Color(0.32, 0.92, 1.0, 0.88)]))

	# 2. Bolt-On Orbital Booster Skirt (when propulsion_tier >= 1)
	if State.propulsion_tier >= 1:
		var bt := ArtReg.get_t("orbital_booster")
		if bt: draw_texture_rect(bt, Rect2(-26, -24, 52, 56), false)

	# 3. Physically Docked Fabricator Drones on Articulated Mechanical Struts!
	var drone_positions: Array[Vector2] = []
	var dtex := ArtReg.get_t("fab_drone")
	for i in range(d_cnt):
		var a := -PI * 0.5 + float(i) * (TAU / float(maxi(4, d_cnt))) + sin(anim_t * 1.6 + float(i)) * 0.08
		var arm_r := 26.0 + (6.0 if i >= 4 else 0.0)
		var dp := Vector2(cos(a) * arm_r, sin(a) * arm_r)
		drone_positions.append(dp)
		# Articulated mechanical strut connecting drone to central Seed Core!
		draw_line(Vector2.ZERO, dp, Color(0.24, 0.30, 0.40), 4.0)
		draw_line(Vector2.ZERO, dp, Color(0.66, 0.74, 0.86), 1.8)
		if dtex:
			draw_texture_rect(dtex, Rect2(dp - Vector2(11, 11), Vector2(22, 22)), false)
		else:
			draw_circle(dp, 6.0, Color(0.94, 0.74, 0.30))

	# 4. Central Seed Unit Core Sprite
	var ctex := ArtReg.get_t("seed_core")
	if glow:
		draw_texture_rect(glow, Rect2(-28, -28, 56, 56), false, Color(0.26, 0.88, 1.0, 0.24))
	if ctex:
		draw_texture_rect(ctex, Rect2(-20, -20, 40, 40), false)
	else:
		draw_circle(Vector2.ZERO, 16.0, Color(0.35, 0.85, 1.0))

	# 5. Synchronized Multi-Beam Mining / Welding Lasers (Core + ALL Docked Drones!)
	if not mine_target.is_empty():
		var lt := to_local(Vector2(mine_target["pos"]))
		var bc := Color(0.32, 0.94, 1.0, 0.90) if String(mine_target.get("kind", "")) != "boss" else Color(1.0, 0.44, 0.24, 0.92)
		draw_line(Vector2.ZERO, lt, bc, 4.6)
		draw_line(Vector2.ZERO, lt, Color(0.95, 1.0, 1.0, 0.95), 1.6)
		for dp in drone_positions:
			draw_line(dp, lt, Color(0.45, 0.96, 1.0, 0.68), 2.2)
		if glow:
			draw_texture_rect(glow, Rect2(lt.x - 24, lt.y - 24, 48, 48), false, bc)
