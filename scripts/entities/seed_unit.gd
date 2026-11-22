extends Node2D

# Protagonist Seed Unit (World Space — Heliocentric Solar System):
# - Patched-Conic SOI gravity & co-moving reference frames across SUN, IGNIS-I, TERRA-I, LUNA, CRYO-IV, ASTRA-V
# - Zero-jitter magnetic ground anchoring on TERRA and ALL Moons/Planets (never slides off Luna!)
# - Symplectic Velocity-Verlet thrusting + Seamless Analytical Keplerian On-Rails Orbit Lock
#   (exact Vis-Viva speed: faster at Pe, slower at Ap, 0.000px drift over infinite revolutions!)

var planet: SphericalPlanet = null
var grid: Node2D = null
var swarm: Node2D = null

var active_body_id: String = "terra"
var velocity: Vector2 = Vector2.ZERO # Relative velocity to active_body!
var on_ground: bool = false
var anchored: bool = false
var anchored_body_id: String = ""
var anchor_rel: Vector2 = Vector2.ZERO

# Analytical Keplerian Orbit state
var orbit_info: Dictionary = {}
var on_rails: bool = false
var rails_orb: Dictionary = {}

var move_input: Vector2 = Vector2.ZERO
var aim_world: Vector2 = Vector2.ZERO
var manual_aim_dir: Vector2 = Vector2.ZERO
var last_aim_dir: Vector2 = Vector2.DOWN
var braking: bool = false
var firing_mine: bool = false
var mine_target: Dictionary = {}
var beam_end_world: Vector2 = Vector2.ZERO
var firing_chem: bool = false
var firing_ion: bool = false
var local_g: float = 1.0
var anim_t: float = 0.0

const RADIUS: float = 18.0

func _ready() -> void:
	z_index = 25
	process_physics_priority = -10

func spawn_north_pole() -> void:
	var r0 := SphericalPlanet.R_SURFACE + 28.0
	var terra_p := Vector2.ZERO
	if planet:
		terra_p = planet.get_terra_pos()
		var sr := planet.get_surface_row(SphericalPlanet.SPAWN_COL)
		r0 = SphericalPlanet.R_CORE + float(sr + 1) * SphericalPlanet.CELL_H + RADIUS + 4.0
	active_body_id = "terra"
	position = terra_p + Vector2(0.0, -r0)
	velocity = Vector2.ZERO
	rotation = 0.0
	on_ground = false
	anchored = false
	anchored_body_id = ""
	on_rails = false
	rails_orb = {}
	orbit_info = {}
	mine_target = {}

func emergency_redrop() -> void:
	if planet: planet.spawn_sparks_world(position, Color(1.0, 0.56, 0.22), 24)
	Sfx.play("boom")
	State.hp = State.max_hp
	State.ion_bat = State.max_ion_bat
	State.fuel = State.max_fuel * 0.6
	spawn_north_pole()
	State.add_log("北極拠点へ緊急再降下しました。", "warn")

func get_altitude() -> float:
	if not planet: return 0.0
	var b := planet.get_body(active_body_id)
	return position.distance_to(Vector2(b["pos"])) - float(b["rad"])

func get_active_body_name() -> String:
	if not planet: return "テラ-I"
	return String(planet.get_body(active_body_id)["name"])

func is_in_orbit() -> bool:
	if on_rails and bool(rails_orb.get("closed", false)):
		return true
	return bool(orbit_info.get("closed", false)) and bool(orbit_info.get("can_lock", false))

func get_deploy_orbit() -> Dictionary:
	if on_rails and bool(rails_orb.get("closed", false)):
		return rails_orb.duplicate()
	if bool(orbit_info.get("closed", false)) and bool(orbit_info.get("can_lock", false)):
		return orbit_info.duplicate()
	return {}

func _check_soi_transition() -> void:
	var dom := planet.get_dominant_body(position)
	var new_id := String(dom["id"])
	if new_id != active_body_id:
		var old_b := planet.get_body(active_body_id)
		# Preserve inertial world velocity seamlessly across SOI boundary!
		velocity = velocity + Vector2(old_b["vel"]) - Vector2(dom["vel"])
		active_body_id = new_id
		on_rails = false
		rails_orb = {}
		anchored = false
		anchored_body_id = ""
		State.add_log("重力圏進入: %s" % String(dom["name"]), "info")

func _physics_process(delta: float) -> void:
	anim_t += delta
	firing_chem = false; firing_ion = false
	if not planet: return

	# 1. Co-moving frame carry with active dominant celestial body!
	var body := planet.get_body(active_body_id)
	var body_pos: Vector2 = body["pos"]
	var body_rad := float(body["rad"])
	var body_atmos := float(body["atmos_r"])
	var body_soi := float(body["soi_r"])
	var body_gm := float(body["gm"])

	if anchored and anchored_body_id != "":
		var ab := planet.get_body(anchored_body_id)
		active_body_id = anchored_body_id
		body = ab
		body_pos = ab["pos"]
		body_rad = float(ab["rad"])
		body_atmos = float(ab["atmos_r"])
		body_soi = float(ab["soi_r"])
		body_gm = float(ab["gm"])
		position = body_pos + anchor_rel
	else:
		position += Vector2(body["delta_pos"])

	var inp := move_input
	if inp.length() > 1.0: inp = inp.normalized()
	var wdir := inp.normalized() if inp.length() > 0.08 else Vector2.ZERO
	var rel := position - body_pos
	var r := rel.length()
	var up := rel.normalized() if r > 1.0 else Vector2.UP
	var grav := planet.compute_gravity_for(position, active_body_id)
	local_g = grav.length() / SphericalPlanet.GRAV_SURF

	# 2. Anchored state (zero jitter on Terra AND on Luna/Ignis/Cryo/Astra!)
	if anchored:
		var ground_ok := true
		if anchored_body_id == "terra":
			ground_ok = _has_terra_ground_below(rel, up)
		if wdir.length() > 0.08 or not ground_ok:
			anchored = false
			anchored_body_id = ""
		else:
			velocity = Vector2.ZERO
			on_ground = true
			on_rails = false
			orbit_info = {}
			var urot_a := up.angle() + PI * 0.5
			rotation = wrapf(rotation + clampf(wrapf(urot_a - rotation, -PI, PI), -8.0 * delta, 8.0 * delta), -PI, PI)

	# 3. Analytical Keplerian On-Rails Propagation (0.000px drift, exact Vis-Viva speed!)
	if not anchored and on_rails:
		if wdir.length() > 0.08 or braking or not bool(rails_orb.get("closed", false)):
			on_rails = false
		else:
			var r_body := planet.get_body(String(rails_orb["body_id"]))
			rails_orb["M"] = wrapf(float(rails_orb["M"]) + float(rails_orb["n"]) * delta, -PI, PI)
			var st := Kepler.eval_state(rails_orb, float(rails_orb["M"]))
			var p_rel: Vector2 = st["pos_rel"]
			var v_rel: Vector2 = st["vel_rel"]
			position = Vector2(r_body["pos"]) + p_rel
			velocity = v_rel
			orbit_info = rails_orb.duplicate()
			# Face prograde smoothly while coasting in orbit
			var prog_rot := velocity.angle() + PI * 0.5
			rotation = wrapf(rotation + clampf(wrapf(prog_rot - rotation, -PI, PI), -4.0 * delta, 4.0 * delta), -PI, PI)
			on_ground = false
			# Check if entering a moon's SOI (e.g. Luna encounter!) or atmosphere
			var dom_chk := planet.get_dominant_body(position)
			if String(dom_chk["id"]) != active_body_id:
				_check_soi_transition()

	# 4. Dynamic Symplectic Velocity-Verlet Physics (Thrusting / Atmosphere / Landing)
	if not anchored and not on_rails:
		var tinfo: Dictionary = State.PROPULSION_TIERS[State.propulsion_tier]
		var chem_t := float(tinfo["thrust"])
		var ion_t := float(tinfo["ion"])
		var max_s := float(tinfo["max_spd"])
		var alt := r - body_rad
		var thrust_acc := Vector2.ZERO

		if wdir.length() > 0.08:
			var mag := inp.length()
			var target_rot := (wdir.angle() + PI * 0.5) if State.propulsion_tier >= 1 and alt > 80.0 else (up.angle() + PI * 0.5)
			var diff := wrapf(target_rot - rotation, -PI, PI)
			rotation = wrapf(rotation + clampf(diff, -6.5 * delta, 6.5 * delta), -PI, PI)

			if State.propulsion_tier >= 1 and State.fuel > 0.1:
				firing_chem = true
				thrust_acc = wdir * (chem_t * mag)
				State.fuel = maxf(0.0, State.fuel - (4.2 if State.propulsion_tier == 1 else 2.8) * mag * delta)
			elif State.ion_bat > 0.5:
				firing_ion = true
				var tdir := wdir
				if State.propulsion_tier == 0 and active_body_id == "terra" and alt > 95.0:
					var oc := tdir.dot(up)
					if oc > 0.0:
						tdir = tdir - up * oc
						tdir = tdir.normalized() if tdir.length() > 0.05 else Vector2.ZERO
				thrust_acc = tdir * (ion_t * mag)
				State.ion_bat = maxf(0.0, State.ion_bat - 22.0 * mag * delta)
		else:
			var urot := up.angle() + PI * 0.5
			rotation = wrapf(rotation + clampf(wrapf(urot - rotation, -PI, PI), -5.0 * delta, 5.0 * delta), -PI, PI)

		# Symplectic Velocity Verlet step (high orbital energy accuracy even during burns!)
		var a0 := grav + thrust_acc
		position += velocity * delta + a0 * (0.5 * delta * delta)
		var g1 := planet.compute_gravity_for(position, active_body_id)
		velocity += (a0 + g1 + thrust_acc) * (0.5 * delta)

		if braking:
			velocity *= exp(-7.0 * delta)
			if velocity.length() < 6.0: velocity = Vector2.ZERO

		# Atmospheric Drag ONLY inside Terra's atmosphere; STRICTLY ZERO in Vacuum Space!
		var atmos := planet.get_atmos_density_world(position)
		if atmos > 0.0:
			var dk := 0.85 if State.propulsion_tier == 0 else (0.36 * atmos)
			velocity *= exp(-dk * delta)
			if atmos > 0.25 and velocity.length() > max_s * 1.45:
				velocity = velocity.normalized() * lerpf(velocity.length(), max_s * 1.45, delta * 3.0)

		# Collisions: Terra Voxels + ALL Moons/Other Planets (LUNA, IGNIS, CRYO, ASTRA)
		on_ground = false
		if active_body_id == "terra":
			_resolve_terra_collision(delta, body_pos)

		var chit := planet.check_celestial_hit(position, RADIUS)
		if bool(chit.get("hit", false)):
			var hit_bid := String(chit["body_id"])
			if hit_bid == "sun":
				emergency_redrop()
				return
			position = Vector2(chit["push"])
			var mn: Vector2 = chit["normal"]
			var vn := velocity.dot(mn)
			if vn < 0.0: velocity -= mn * vn
			velocity *= exp(-7.0 * delta)
			on_ground = true
			if wdir.length() <= 0.08 and velocity.length() < 32.0:
				velocity = Vector2.ZERO
				anchored = true
				anchored_body_id = hit_bid
				anchor_rel = position - Vector2(chit["body"]["pos"])

		# Magnetic surface anchor on Terra when resting with no input
		if active_body_id == "terra" and on_ground and wdir.length() <= 0.08 and velocity.length() < 26.0:
			velocity = Vector2.ZERO
			anchored = true
			anchored_body_id = "terra"
			anchor_rel = position - body_pos

		# Check Patched-Conic SOI transition
		if not anchored:
			_check_soi_transition()
			body = planet.get_body(active_body_id)
			body_pos = body["pos"]
			body_rad = float(body["rad"])
			body_atmos = float(body["atmos_r"])
			body_soi = float(body["soi_r"])
			body_gm = float(body["gm"])

		# Update exact analytical Keplerian Orbit Prediction & Seamless On-Rails Lock!
		var rel_now := position - body_pos
		var alt_now := rel_now.length() - body_rad
		var atmos_now := planet.get_atmos_density_world(position)
		if not anchored and (alt_now > 120.0 or active_body_id != "terra"):
			orbit_info = Kepler.compute_elements(rel_now, velocity, body_gm, active_body_id, body_rad, body_atmos, body_soi)
			# Lock seamlessly onto exact Keplerian rails as soon as player stops thrusting in vacuum on a safe closed orbit!
			if wdir.length() <= 0.08 and not braking and atmos_now <= 0.001 and bool(orbit_info.get("can_lock", false)):
				on_rails = true
				rails_orb = orbit_info.duplicate()
		else:
			orbit_info = {}

	# 5. Grid pickup & recharge (when near Terra)
	if grid and active_body_id == "terra":
		grid.collect_near_player(position, 86.0)
		grid.service_player(position, delta)
	else:
		# Solar battery recharge in deep space / on moons
		var sun_l := planet.get_sunlight_world(position)
		State.ion_bat = minf(State.max_ion_bat, State.ion_bat + (6.0 + 10.0 * sun_l) * delta)

	# 6. Directional Multi-Beam Mining & Combat Laser
	mine_target = {}
	beam_end_world = Vector2.ZERO
	if firing_mine and State.selected_tool == "mine":
		var aim_dir := last_aim_dir
		if manual_aim_dir.length() > 0.10:
			aim_dir = manual_aim_dir.normalized()
		elif aim_world != Vector2.ZERO and aim_world.distance_to(position) > 8.0:
			aim_dir = (aim_world - position).normalized()
		elif wdir.length() > 0.10:
			aim_dir = wdir.normalized()
		else:
			aim_dir = -up
		last_aim_dir = aim_dir

		var reach := 225.0 + float(State.attached_drones) * 24.0
		var tgt := planet.find_mine_target(position, aim_dir, reach)
		var boss_world := planet.to_world_pos(swarm.boss_pos) if swarm else Vector2.ZERO
		if not tgt.is_empty():
			mine_target = tgt
			beam_end_world = Vector2(tgt["pos"])
			var dps := (28.0 + float(State.attached_drones) * 9.0 + float(State.propulsion_tier) * 6.0) * delta
			planet.damage_target(tgt, dps)
		elif swarm and not State.boss_dead and position.distance_to(boss_world) <= 480.0 and (boss_world - position).normalized().dot(aim_dir) > 0.85:
			mine_target = {"kind": "boss", "pos": boss_world}
			beam_end_world = boss_world
			swarm.damage_boss((50.0 + float(State.attached_drones) * 12.0) * delta)
		else:
			beam_end_world = position + aim_dir * reach

	queue_redraw()

func _has_terra_ground_below(rel_pos: Vector2, up: Vector2) -> bool:
	if not planet: return false
	var r := rel_pos.length()
	if r <= SphericalPlanet.R_CORE + 6.0 * SphericalPlanet.CELL_H + RADIUS + 2.0:
		return true
	if r > SphericalPlanet.R_SURFACE + RADIUS + 24.0:
		return false
	var tang := Vector2(-up.y, up.x)
	for probe in [-up * (RADIUS + 2.5), (-up * 0.85 + tang * 0.45) * (RADIUS + 2.0), (-up * 0.85 - tang * 0.45) * (RADIUS + 2.0)]:
		var c := planet.world_to_cell(rel_pos + probe)
		if planet.is_solid(c.x, c.y):
			return true
	return false

func _resolve_terra_collision(delta: float, terra_pos: Vector2) -> void:
	var rel := position - terra_pos
	var r := rel.length()
	if r < SphericalPlanet.R_CORE + 6.0 * SphericalPlanet.CELL_H + RADIUS:
		var n := rel.normalized()
		position = terra_pos + n * (SphericalPlanet.R_CORE + 6.0 * SphericalPlanet.CELL_H + RADIUS)
		var vn := velocity.dot(n)
		if vn < 0.0: velocity -= n * vn
		on_ground = true
		return
	if r > SphericalPlanet.R_SURFACE + RADIUS + 24.0:
		return

	var up := rel.normalized()
	var tang := Vector2(-up.y, up.x)

	var foot_c := planet.world_to_cell(rel - up * RADIUS)
	if planet.is_solid(foot_c.x, foot_c.y):
		var exact_r := SphericalPlanet.R_CORE + float(foot_c.y + 1) * SphericalPlanet.CELL_H + RADIUS
		if rel.length() < exact_r:
			rel = up * exact_r
			position = terra_pos + rel
		var vn := velocity.dot(up)
		if vn < 0.0: velocity -= up * vn
		on_ground = true
		var vt := velocity.dot(tang)
		velocity -= tang * (vt * minf(1.0, delta * 8.0))

	var side_pts: Array[Vector2] = [
		tang * RADIUS, -tang * RADIUS, up * RADIUS,
		(tang * 0.7 - up * 0.7) * RADIUS,
		(-tang * 0.7 - up * 0.7) * RADIUS,
	]
	for _iter in range(3):
		var hit_any := false
		for off in side_pts:
			var sp: Vector2 = (position - terra_pos) + off
			var c := planet.world_to_cell(sp)
			if planet.is_solid(c.x, c.y):
				hit_any = true
				var pdir: Vector2 = (-off).normalized()
				position += pdir * 1.4
				var vn := velocity.dot(pdir)
				if vn < 0.0: velocity -= pdir * vn
				if off.dot(up) < -RADIUS * 0.4:
					on_ground = true
					var vt := velocity.dot(tang)
					velocity -= tang * (vt * minf(1.0, delta * 8.0))
		if not hit_any:
			break

# ------------------------------------------------------------------------------
# SEED UNIT + PHYSICALLY DOCKED FABRICATOR DRONES + MULTI-BEAM LASERS
# ------------------------------------------------------------------------------
func _draw() -> void:
	var glow := ArtReg.get_t("glow")
	var d_cnt := State.attached_drones

	if firing_chem:
		var fl := 26.0 + float(State.propulsion_tier) * 10.0 + sin(anim_t * 48.0) * 6.0
		if glow: draw_texture_rect(glow, Rect2(-26, 16, 52, fl + 22), false, Color(1.0, 0.62, 0.16, 0.55))
		draw_polygon(PackedVector2Array([Vector2(-9, 20), Vector2(9, 20), Vector2(0, 20 + fl)]), PackedColorArray([Color(1.0, 0.60, 0.14, 0.92)]))
		draw_polygon(PackedVector2Array([Vector2(-5, 20), Vector2(5, 20), Vector2(0, 20 + fl * 0.62)]), PackedColorArray([Color(1.0, 0.96, 0.78, 0.96)]))
	elif firing_ion:
		var fl := 15.0 + sin(anim_t * 36.0) * 3.5
		if glow: draw_texture_rect(glow, Rect2(-18, 12, 36, fl + 14), false, Color(0.28, 0.88, 1.0, 0.44))
		draw_polygon(PackedVector2Array([Vector2(-5, 16), Vector2(5, 16), Vector2(0, 16 + fl)]), PackedColorArray([Color(0.32, 0.92, 1.0, 0.88)]))

	if State.propulsion_tier >= 1:
		var bt := ArtReg.get_t("orbital_booster")
		if bt: draw_texture_rect(bt, Rect2(-26, -24, 52, 56), false)

	var drone_positions: Array[Vector2] = []
	var dtex := ArtReg.get_t("fab_drone")
	for i in range(d_cnt):
		var a := -PI * 0.5 + float(i) * (TAU / float(maxi(4, d_cnt))) + sin(anim_t * 1.6 + float(i)) * 0.08
		var arm_r := 26.0 + (6.0 if i >= 4 else 0.0)
		var dp := Vector2(cos(a) * arm_r, sin(a) * arm_r)
		drone_positions.append(dp)
		draw_line(Vector2.ZERO, dp, Color(0.24, 0.30, 0.40), 4.0)
		draw_line(Vector2.ZERO, dp, Color(0.66, 0.74, 0.86), 1.8)
		if dtex:
			draw_texture_rect(dtex, Rect2(dp - Vector2(11, 11), Vector2(22, 22)), false)
		else:
			draw_circle(dp, 6.0, Color(0.94, 0.74, 0.30))

	var ctex := ArtReg.get_t("seed_core")
	if glow:
		draw_texture_rect(glow, Rect2(-28, -28, 56, 56), false, Color(0.26, 0.88, 1.0, 0.24))
	if ctex:
		draw_texture_rect(ctex, Rect2(-20, -20, 40, 40), false)
	else:
		draw_circle(Vector2.ZERO, 16.0, Color(0.35, 0.85, 1.0))

	if firing_mine and State.selected_tool == "mine" and beam_end_world != Vector2.ZERO:
		var lt := to_local(beam_end_world)
		var hit := not mine_target.is_empty()
		var bc := Color(1.0, 0.44, 0.24, 0.92) if String(mine_target.get("kind", "")) == "boss" else (Color(0.32, 0.94, 1.0, 0.92) if hit else Color(0.32, 0.94, 1.0, 0.56))
		draw_line(Vector2.ZERO, lt, bc, 4.6 if hit else 3.2)
		draw_line(Vector2.ZERO, lt, Color(0.95, 1.0, 1.0, 0.95 if hit else 0.70), 1.6)
		for dp in drone_positions:
			draw_line(dp, lt, Color(0.45, 0.96, 1.0, 0.68 if hit else 0.40), 2.2)
		if glow:
			var gr := 24.0 if hit else 14.0
			draw_texture_rect(glow, Rect2(lt.x - gr, lt.y - gr, gr * 2.0, gr * 2.0), false, bc)
