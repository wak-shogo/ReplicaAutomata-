extends Node2D

# GPU-Instanced 10,000-Unit Player Swarm Fleet + 5,000-Unit Enemy Swarm Fleet (MultiMeshInstance2D) +
# Outer Planet ASTRA-V Operating Enemy Factories & Enemy Mass Drivers +
# Orbital-Trajectory Invasion & Symmetric Mutual Beam Combat +
# Pollution-Triggered & Off-Map Continuous Enemy Raids attacking Non-Starter Planetary Facilities!

const MAX_SHIPS: int = 10000
const MAX_ENEMY_SHIPS: int = 5000
const UNIT_HP: float = 45.0
const UNIT_SPEED: float = 240.0
const UNIT_BEAM_RANGE: float = 520.0
const UNIT_BEAM_DPS: float = 18.0

var planet: SphericalPlanet = null
var grid: Node2D = null
var mm_node: MultiMeshInstance2D = null
var mm: MultiMesh = null
var enemy_mm_node: MultiMeshInstance2D = null
var enemy_mm: MultiMesh = null

var pos_arr: PackedVector2Array
var vel_arr: PackedVector2Array
var hp_arr: PackedFloat32Array
var orb_r: PackedFloat32Array
var orb_a: PackedFloat32Array
var orb_spd: PackedFloat32Array
var transfer_p: PackedFloat32Array
var active_n: int = 0

var e_pos_arr: PackedVector2Array
var e_vel_arr: PackedVector2Array
var e_hp_arr: PackedFloat32Array
var e_orb_r: PackedFloat32Array
var e_orb_a: PackedFloat32Array
var e_orb_spd: PackedFloat32Array
var e_active_n: int = 0
var enemy_launch_trails: Array[Dictionary] = []

var boss_ang: float = -PI * 0.38
var boss_r: float = 4200.0
var boss_pos: Vector2 = Vector2.ZERO # In HomeSystem (Terra-relative) coordinates

var raiders: Array[Dictionary] = []
var tracers: Array[Dictionary] = []
var _doc_t: float = 0.0
var _combat_t: float = 0.0
var _enemy_launch_t: float = 0.0
var _raid_t: float = 0.0
var _offmap_raid_t: float = 0.0

func _ready() -> void:
	z_index = 15
	_init_multimesh()
	pos_arr.resize(MAX_SHIPS); vel_arr.resize(MAX_SHIPS); hp_arr.resize(MAX_SHIPS)
	orb_r.resize(MAX_SHIPS); orb_a.resize(MAX_SHIPS); orb_spd.resize(MAX_SHIPS); transfer_p.resize(MAX_SHIPS)
	e_pos_arr.resize(MAX_ENEMY_SHIPS); e_vel_arr.resize(MAX_ENEMY_SHIPS); e_hp_arr.resize(MAX_ENEMY_SHIPS)
	e_orb_r.resize(MAX_ENEMY_SHIPS); e_orb_a.resize(MAX_ENEMY_SHIPS); e_orb_spd.resize(MAX_ENEMY_SHIPS)
	_update_boss_pos(0.0)

func _init_multimesh() -> void:
	var mesh := ArrayMesh.new()
	var v := PackedVector2Array([
		Vector2(9, 0), Vector2(-6, -4.5), Vector2(-3.5, 0),
		Vector2(9, 0), Vector2(-3.5, 0), Vector2(-6, 4.5),
	])
	var arr := []; arr.resize(Mesh.ARRAY_MAX); arr[Mesh.ARRAY_VERTEX] = v
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)

	mm_node = MultiMeshInstance2D.new()
	mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.instance_count = MAX_SHIPS
	mm.visible_instance_count = 0
	mm.mesh = mesh
	mm_node.multimesh = mm
	add_child(mm_node)

	enemy_mm_node = MultiMeshInstance2D.new()
	enemy_mm = MultiMesh.new()
	enemy_mm.transform_format = MultiMesh.TRANSFORM_2D
	enemy_mm.use_colors = true
	enemy_mm.instance_count = MAX_ENEMY_SHIPS
	enemy_mm.visible_instance_count = 0
	enemy_mm.mesh = mesh
	enemy_mm_node.multimesh = enemy_mm
	add_child(enemy_mm_node)

func _get_astra_off() -> Vector2:
	if planet and planet.bodies.has("astra"):
		return Vector2(planet.bodies["astra"]["pos"]) - Vector2(planet.bodies["terra"]["pos"])
	return Vector2(5250.0, 0.0)

func _update_boss_pos(delta: float) -> void:
	boss_ang = wrapf(boss_ang + 0.005 * delta, -PI, PI)
	var astra_off := _get_astra_off()
	boss_pos = astra_off + Vector2(cos(boss_ang), sin(boss_ang)) * boss_r

func spawn_launched(origin: Vector2, dir: Vector2, cnt: int) -> void:
	for _i in range(cnt):
		if active_n >= MAX_SHIPS: break
		var i := active_n; active_n += 1
		pos_arr[i] = origin + Vector2(randf_range(-12, 12), randf_range(-12, 12))
		vel_arr[i] = dir * randf_range(220.0, 280.0)
		hp_arr[i] = UNIT_HP
		orb_r[i] = randf_range(SphericalPlanet.R_SURFACE + 520.0, SphericalPlanet.R_ATMOS + 1100.0)
		orb_a[i] = atan2(origin.y, origin.x) + randf_range(-0.15, 0.15)
		orb_spd[i] = randf_range(0.032, 0.068) * (1.0 if i % 6 != 0 else -1.0)
		transfer_p[i] = 0.0
	_sync()

func _spawn_enemy_launched(origin: Vector2, dir: Vector2) -> void:
	if e_active_n >= MAX_ENEMY_SHIPS:
		return
	var astra_off := _get_astra_off()
	var astra_r := float(planet.bodies["astra"]["rad"]) if (planet and planet.bodies.has("astra")) else 3100.0
	var i := e_active_n; e_active_n += 1
	e_pos_arr[i] = origin
	e_vel_arr[i] = dir * UNIT_SPEED
	e_hp_arr[i] = UNIT_HP
	e_orb_r[i] = randf_range(astra_r + 360.0, astra_r + 1350.0)
	var rel := origin - astra_off
	e_orb_a[i] = atan2(rel.y, rel.x)
	e_orb_spd[i] = randf_range(0.035, 0.075) * (1.0 if i % 5 != 0 else -1.0)
	if enemy_mm:
		enemy_mm.visible_instance_count = e_active_n

func _remove_player_ship(idx: int) -> void:
	if idx < 0 or idx >= active_n: return
	var last := active_n - 1
	if idx != last:
		pos_arr[idx] = pos_arr[last]
		vel_arr[idx] = vel_arr[last]
		hp_arr[idx] = hp_arr[last]
		orb_r[idx] = orb_r[last]
		orb_a[idx] = orb_a[last]
		orb_spd[idx] = orb_spd[last]
		transfer_p[idx] = transfer_p[last]
	active_n -= 1
	State.swarm_fleet = maxi(0, active_n)
	if mm: mm.visible_instance_count = active_n

func _remove_enemy_ship(idx: int) -> void:
	if idx < 0 or idx >= e_active_n: return
	var last := e_active_n - 1
	if idx != last:
		e_pos_arr[idx] = e_pos_arr[last]
		e_vel_arr[idx] = e_vel_arr[last]
		e_hp_arr[idx] = e_hp_arr[last]
		e_orb_r[idx] = e_orb_r[last]
		e_orb_a[idx] = e_orb_a[last]
		e_orb_spd[idx] = e_orb_spd[last]
	e_active_n -= 1
	State.enemy_swarm_fleet = maxi(0, e_active_n)
	if enemy_mm: enemy_mm.visible_instance_count = e_active_n

func _sync() -> void:
	var tgt := mini(MAX_SHIPS, State.swarm_fleet)
	while active_n < tgt:
		var i := active_n; active_n += 1
		var a := -PI * 0.5 + randf_range(-0.8, 0.8) if i < 600 else randf_range(0.0, TAU)
		var r := randf_range(SphericalPlanet.R_SURFACE + 460.0, SphericalPlanet.R_ATMOS + 1100.0)
		orb_a[i] = a; orb_r[i] = r; hp_arr[i] = UNIT_HP; transfer_p[i] = 0.0
		pos_arr[i] = Vector2(cos(a), sin(a)) * r
		vel_arr[i] = Vector2(-sin(a), cos(a)) * UNIT_SPEED
		orb_spd[i] = randf_range(0.032, 0.068)
	if active_n > tgt: active_n = tgt
	if mm: mm.visible_instance_count = active_n

	var e_tgt := mini(MAX_ENEMY_SHIPS, State.enemy_swarm_fleet)
	var astra_off := _get_astra_off()
	var astra_r := float(planet.bodies["astra"]["rad"]) if (planet and planet.bodies.has("astra")) else 3100.0
	while e_active_n < e_tgt:
		var j := e_active_n; e_active_n += 1
		var ea := randf_range(0.0, TAU)
		var er := randf_range(astra_r + 360.0, astra_r + 1350.0)
		e_orb_a[j] = ea; e_orb_r[j] = er; e_hp_arr[j] = UNIT_HP
		e_pos_arr[j] = astra_off + Vector2(cos(ea), sin(ea)) * er
		e_vel_arr[j] = Vector2(-sin(ea), cos(ea)) * UNIT_SPEED
		e_orb_spd[j] = randf_range(0.035, 0.075) * (1.0 if j % 5 != 0 else -1.0)
	if e_active_n > e_tgt: e_active_n = e_tgt
	if enemy_mm: enemy_mm.visible_instance_count = e_active_n

func find_nearest_raider(p: Vector2, max_d: float) -> Vector2:
	var bd := max_d; var best := Vector2.ZERO
	for r in raiders:
		var d := p.distance_to(r["pos"])
		if d < bd: bd = d; best = r["pos"]
	return best

func damage_raider_near(p: Vector2, dmg: float) -> void:
	for i in range(raiders.size() - 1, -1, -1):
		if Vector2(raiders[i]["pos"]).distance_to(p) <= 100.0:
			raiders[i]["hp"] = float(raiders[i]["hp"]) - dmg
			if float(raiders[i]["hp"]) <= 0.0:
				if planet: planet.spawn_sparks(raiders[i]["pos"], Color(1.0, 0.44, 0.24), 10)
				State.add_r("ti", 2)
				raiders.remove_at(i)
			return

func spawn_raider_wave(target_body: String, from_offmap: bool = false) -> void:
	if not planet or raiders.size() >= 14: return
	# 最初の惑星（テラ-I）には敵が一切来ないように保護（月ルナや他惑星のみ襲撃）
	var safe_target := target_body
	if safe_target == "" or safe_target == "terra":
		safe_target = "luna"
	var terra_p := Vector2(planet.bodies["terra"]["pos"])
	var spawn_l := boss_pos
	var idx_seed := raiders.size()
	var slot_a := wrapf(float(idx_seed) * 0.92 - 1.15, -1.45, 1.45) + randf_range(-0.14, 0.14)
	var h_rad := 54.0 + float(idx_seed % 4) * 24.0 + randf_range(-5.0, 7.0)
	if from_offmap:
		var ang := randf_range(0.0, TAU)
		var off_world := Vector2(cos(ang), sin(ang)) * 72000.0
		spawn_l = off_world - terra_p
	elif planet.bodies.has(safe_target):
		var bp := Vector2(planet.bodies[safe_target]["pos"]) - terra_p
		var a := -PI * 0.5 + slot_a * 0.65
		spawn_l = bp + Vector2(cos(a), sin(a)) * (float(planet.bodies[safe_target]["rad"]) + 1800.0)
	var spread_off := Vector2.from_angle(float(idx_seed) * 1.25 + randf_range(-0.2, 0.2)) * (64.0 + float(idx_seed) * 18.0)
	raiders.append({
		"pos": spawn_l + spread_off,
		"vel": Vector2.ZERO,
		"hp": 65.0,
		"max_hp": 65.0,
		"target_body": safe_target,
		"atk_t": 0.0,
		"slot_ang": slot_a,
		"hover_r": h_rad,
		"rot": 0.0,
	})

func damage_boss(dmg: float) -> void:
	if planet and not State.astra_liberated:
		planet.damage_astra_bastions(dmg * 0.45)
	if State.boss_dead: return
	State.boss_hp = maxf(0.0, State.boss_hp - dmg)
	if planet and randf() < 0.45:
		planet.spawn_sparks(boss_pos + Vector2(randf_range(-65, 65), randf_range(-45, 45)), Color(1.0, 0.72, 0.28), 6)
	if State.boss_hp <= 0.0:
		State.boss_dead = true
		if planet:
			planet.damage_astra_bastions(9999.0)
			planet.spawn_sparks(boss_pos, Color(1.0, 0.56, 0.22), 40)
		Sfx.play("boom")
		State.add_log("最外周アストラ-Vの汚染軌道要塞を撃破しました！（マップ外からの残党襲撃は継続します）", "good")
		State.check_victory()

func _process(delta: float) -> void:
	_sync()
	_update_boss_pos(delta)

	# 1. Pollution-Triggered Enemy Raids on Non-Starter Planets (luna, ignis, cryo, astra)!
	_raid_t += delta
	if _raid_t >= 7.5:
		_raid_t = 0.0
		for bid in ["luna", "ignis", "cryo", "astra"]:
			var pol := State.get_pollution(bid)
			if pol >= 12.0 and randf() < clampf(pol / 85.0, 0.20, 0.90):
				spawn_raider_wave(bid, false)
				if planet:
					State.add_log("警告: %s の汚染(%d%%)に反応して敵襲撃機が飛来！" % [planet.bodies[bid]["name"], int(pol)], "warn")
				break

	# 2. Continuous Off-Map Random Enemy Raids (NEVER attacks starter planet TERRA-I; attacks Luna & other planets!)
	_offmap_raid_t += delta
	if _offmap_raid_t >= 16.0 and grid:
		_offmap_raid_t = 0.0
		var b_targets: Array[String] = []
		for b in grid.buildings:
			var bid_b := String(b.get("body_id", "terra"))
			if bid_b != "terra" and not (bid_b in b_targets):
				b_targets.append(bid_b)
		if b_targets.is_empty() and (State.astra_liberated or State.propulsion_tier >= 1):
			b_targets.append("luna")
		if not b_targets.is_empty():
			var chosen_b: String = b_targets[randi() % b_targets.size()]
			spawn_raider_wave(chosen_b, true)
			if planet and planet.bodies.has(chosen_b):
				State.add_log("星系外縁から敵性の自己複製探査機が %s へ接近中！" % planet.bodies[chosen_b]["name"], "warn")

	# 3. Raider AI: fly toward nearest player facility on non-starter planet (Luna/Ignis/Cryo/Astra) & Boids anti-overlap!
	for i in range(raiders.size()):
		var rd: Dictionary = raiders[i]
		var tbody := String(rd.get("target_body", "luna"))
		if tbody == "" or tbody == "terra":
			tbody = "luna"
			rd["target_body"] = "luna"
		var slot_a := float(rd.get("slot_ang", float(i) * 0.85 - 1.0))
		var h_rad := float(rd.get("hover_r", 62.0))
		var t_pos := boss_pos
		if planet and planet.bodies.has(tbody):
			var bp := Vector2(planet.bodies[tbody]["pos"]) - Vector2(planet.bodies["terra"]["pos"])
			var brad := float(planet.bodies[tbody]["rad"])
			var p_ang := -PI * 0.5 + slot_a
			t_pos = bp + Vector2(cos(p_ang), sin(p_ang)) * (brad + 95.0 + h_rad)

		var best_b: Dictionary = {}
		if grid and grid.has_method("find_nearest_on_body"):
			best_b = grid.find_nearest_on_body(Vector2(rd["pos"]), tbody)
			if not best_b.is_empty() and String(best_b.get("body_id", "terra")) != "terra":
				var b_norm := Vector2(best_b["normal"])
				var fan_dir := b_norm.rotated(slot_a * 0.62)
				t_pos = Vector2(best_b["pos"]) + fan_dir * h_rad
			else:
				best_b = {}

		var to_t := t_pos - Vector2(rd["pos"])
		var dist := to_t.length()
		var desired_v := (to_t / maxf(0.01, dist)) * (260.0 if dist > 110.0 else (55.0 if dist > 18.0 else 0.0))

		# Boids pairwise separation force so multiple raiders never stack on the same spot
		var sep_v := Vector2.ZERO
		for j in range(raiders.size()):
			if i == j: continue
			var diff := Vector2(rd["pos"]) - Vector2(raiders[j]["pos"])
			var d := diff.length()
			if d < 78.0:
				var dir_sep := (diff / d) if d > 0.01 else Vector2.from_angle(float(i - j) * 1.37)
				sep_v += dir_sep * ((78.0 - d) * 5.2)

		rd["vel"] = Vector2(rd["vel"]).lerp(desired_v + sep_v, clampf(delta * 3.0, 0.0, 1.0))
		rd["pos"] = Vector2(rd["pos"]) + Vector2(rd["vel"]) * delta

		# Rotate red probe toward target facility when attacking, or along velocity vector when flying
		if not best_b.is_empty() and Vector2(rd["pos"]).distance_to(Vector2(best_b["pos"])) <= 185.0:
			var aim_v := Vector2(best_b["pos"]) - Vector2(rd["pos"])
			if aim_v.length() > 1.0:
				rd["rot"] = aim_v.angle()
		elif Vector2(rd["vel"]).length() > 8.0:
			rd["rot"] = Vector2(rd["vel"]).angle()

		if not best_b.is_empty() and Vector2(rd["pos"]).distance_to(Vector2(best_b["pos"])) <= 165.0:
			rd["atk_t"] = float(rd.get("atk_t", 0.0)) + delta
			if float(rd["atk_t"]) >= 0.75:
				rd["atk_t"] = 0.0
				var b_hit_pos := Vector2(best_b["pos"]) + Vector2(best_b["normal"]) * 24.0
				tracers.append({"a": Vector2(rd["pos"]), "b": b_hit_pos, "c": Color(1.0, 0.24, 0.32, 0.92), "life": 0.20})
				grid.damage_building_uid(int(best_b["uid"]), 18.0)

	# Hard pairwise position constraint so two enemy probes can never overlap even when spawning or cornered
	for i in range(raiders.size()):
		for j in range(i + 1, raiders.size()):
			var pi := Vector2(raiders[i]["pos"])
			var pj := Vector2(raiders[j]["pos"])
			var diff := pi - pj
			var d := diff.length()
			var min_sep := 44.0
			if d < min_sep:
				var push_dir := (diff / d) if d > 0.01 else Vector2.from_angle(float(i + j * 3) * 1.1)
				var push := push_dir * ((min_sep - d) * 0.52)
				raiders[i]["pos"] = pi + push
				raiders[j]["pos"] = pj - push

	# 4. Enemy Von Neumann Factories & Mass Drivers on ASTRA-V (Manufacture & Launch Enemy Swarm up to 5,000!)
	if State.enemy_launch_slow_t > 0.0:
		State.enemy_launch_slow_t = maxf(0.0, State.enemy_launch_slow_t - delta)
	if planet:
		planet.sync_astra_facility_counts()
		var ep := State.enemy_printers_left
		var ed := State.enemy_drivers_left
		if ep > 0 and ed > 0 and State.enemy_swarm_fleet < State.ENEMY_SWARM_MAX:
			var prod_rate := (float(ep) / 4.0) * (float(ed) / 4.0)
			if State.enemy_launch_slow_t > 0.0:
				# 敵施設が破壊されてから1分間（60秒間）は射出速度が大幅低下！
				prod_rate *= 0.28
			_enemy_launch_t += delta * prod_rate
			if _enemy_launch_t >= 1.35:
				_enemy_launch_t = 0.0
				var alive_drvs: Array[Dictionary] = []
				for bst in planet.astra_bastions:
					if bool(bst["alive"]) and String(bst.get("kind", "")) == "enemy_driver":
						alive_drvs.append(bst)
				if not alive_drvs.is_empty():
					var drv: Dictionary = alive_drvs[randi() % alive_drvs.size()]
					var astra_off := _get_astra_off()
					var dn := Vector2(drv["normal"])
					var dtang := Vector2(-dn.y, dn.x)
					var ldir := (dn * 0.72 + dtang * 0.69).normalized()
					var muzzle := astra_off + Vector2(drv["local_pos"]) + dn * 78.0
					enemy_launch_trails.append({"pos": muzzle, "vel": ldir * 720.0, "life": 1.6})
					State.enemy_swarm_fleet = mini(State.ENEMY_SWARM_MAX, State.enemy_swarm_fleet + 1)
					_spawn_enemy_launched(muzzle, ldir)
		else:
			_enemy_launch_t = 0.0

	# 5. Swarm Fleet Doctrines (HARVEST, DEFEND, ASSAULT — NO free self-replication!)
	_doc_t += delta
	if _doc_t >= 1.0:
		_doc_t = 0.0
		var n := State.swarm_fleet
		if n > 0:
			match State.doctrine:
				State.Doctrine.HARVEST:
					State.add_r(["fe", "cu", "si"][randi() % 3], maxi(1, int(sqrt(float(n)) * 0.5)))
				State.Doctrine.DEFEND:
					if not raiders.is_empty():
						var r0_p: Vector2 = raiders[0]["pos"]
						tracers.append({"a": r0_p + Vector2(60, -80), "b": r0_p, "c": Color(0.38, 0.96, 1.0, 0.9), "life": 0.22})
						damage_raider_near(r0_p, 28.0 + float(n) * 0.25)
				State.Doctrine.ASSAULT:
					pass

	# 6. Player Swarm Orbital Transfer Trajectory & Enemy Swarm Orbit Update (Same UNIT_SPEED = 240 px/s!)
	var asslt := (State.doctrine == State.Doctrine.ASSAULT and (not State.boss_dead or not State.astra_liberated or e_active_n > 0))
	var astra_off_now := _get_astra_off()
	var astra_r_now := float(planet.bodies["astra"]["rad"]) if (planet and planet.bodies.has("astra")) else 3100.0
	var sun_off := -Vector2(planet.bodies["terra"]["pos"]) if (planet and planet.bodies.has("terra")) else Vector2(0.0, -32000.0)

	for i in range(active_n):
		orb_a[i] += orb_spd[i] * delta
		if asslt:
			transfer_p[i] = minf(1.0, transfer_p[i] + delta * 0.032)
		else:
			transfer_p[i] = maxf(0.0, transfer_p[i] - delta * 0.045)
		var tp := transfer_p[i]
		var home_goal := Vector2(cos(orb_a[i]), sin(orb_a[i])) * orb_r[i]
		var goal := home_goal
		if tp > 0.001:
			var sw := orb_a[i] * 2.2 + float(i) * 0.19
			var astra_goal := astra_off_now + Vector2(cos(sw), sin(sw)) * (astra_r_now + 360.0 + float(i % 9) * 65.0)
			if tp >= 0.995:
				goal = astra_goal
			else:
				# Heliocentric Hohmann Orbital Transfer Arc around the Sun (curved orbital trajectory!)
				var v_s := home_goal - sun_off
				var v_e := astra_goal - sun_off
				var r_s := maxf(100.0, v_s.length())
				var r_e := maxf(100.0, v_e.length())
				var a_s := v_s.angle()
				var a_e := v_e.angle()
				var da_h := wrapf(a_e - a_s, -PI, PI)
				var bend := 0.55 * sin(tp * PI)
				var r_cur := lerpf(r_s, r_e, tp * tp * (3.0 - 2.0 * tp))
				var a_cur := a_s + da_h * tp + bend
				goal = sun_off + Vector2(cos(a_cur), sin(a_cur)) * r_cur
		var dg := goal - pos_arr[i]
		var d_len := dg.length()
		var spd_lim := UNIT_SPEED if d_len > 30.0 else (d_len * 6.0)
		var dir_v := (dg / d_len) if d_len > 0.01 else Vector2.RIGHT
		vel_arr[i] = vel_arr[i].lerp(dir_v * spd_lim, clampf(delta * 2.4, 0.0, 1.0))
		pos_arr[i] += vel_arr[i] * delta
		mm.set_instance_transform_2d(i, Transform2D(vel_arr[i].angle(), pos_arr[i]))
		mm.set_instance_color(i, Color(1.0, 0.86, 0.42) if (i % 4 != 0) else Color(0.55, 0.94, 1.0))

	for j in range(e_active_n):
		e_orb_a[j] += e_orb_spd[j] * delta
		var e_goal := astra_off_now + Vector2(cos(e_orb_a[j]), sin(e_orb_a[j])) * e_orb_r[j]
		var edg := e_goal - e_pos_arr[j]
		var ed_len := edg.length()
		var edir := (edg / ed_len) if ed_len > 0.01 else Vector2.LEFT
		e_vel_arr[j] = e_vel_arr[j].lerp(edir * UNIT_SPEED, clampf(delta * 2.4, 0.0, 1.0))
		e_pos_arr[j] += e_vel_arr[j] * delta
		enemy_mm.set_instance_transform_2d(j, Transform2D(e_vel_arr[j].angle(), e_pos_arr[j]))
		enemy_mm.set_instance_color(j, Color(1.0, 0.24, 0.34) if (j % 3 != 0) else Color(1.0, 0.56, 0.22))

	# 7. Symmetric Nearby Beam Combat (Player Swarm vs Enemy Swarm & Enemy Surface Factories/Mass Drivers!)
	_combat_t += delta
	if _combat_t >= 0.25:
		var dt_c := _combat_t
		_combat_t = 0.0
		_step_swarm_combat(dt_c, astra_off_now, astra_r_now)

	for i in range(enemy_launch_trails.size() - 1, -1, -1):
		enemy_launch_trails[i]["pos"] += enemy_launch_trails[i]["vel"] * delta
		enemy_launch_trails[i]["life"] -= delta
		if float(enemy_launch_trails[i]["life"]) <= 0.0:
			enemy_launch_trails.remove_at(i)

	for i in range(tracers.size() - 1, -1, -1):
		tracers[i]["life"] -= delta
		if float(tracers[i]["life"]) <= 0.0: tracers.remove_at(i)
	queue_redraw()

func _step_swarm_combat(dt_c: float, astra_off: Vector2, astra_r: float) -> void:
	if active_n <= 0:
		return
	# Collect indices of Player Swarm units that are actually near ASTRA-V or Enemy Swarm
	var near_p: Array[int] = []
	var check_step := maxi(1, active_n / 120)
	for i in range(0, active_n, check_step):
		if pos_arr[i].distance_to(astra_off) <= astra_r + 2200.0:
			near_p.append(i)
	if near_p.is_empty():
		return

	var p_mult := float(check_step) * (1.5 if bool(State.megastructures.get("citadel", false)) else 1.0)
	var base_shot_dmg := UNIT_BEAM_DPS * dt_c

	# A) Symmetric Ship-vs-Ship Mutual Beam Combat (Identical base specs for Player & Enemy units!)
	if e_active_n > 0:
		var e_step := maxi(1, e_active_n / 120)
		var e_mult := float(e_step)
		var p_kill_list: Array[int] = []
		var e_kill_list: Array[int] = []
		var beam_budget := 10

		for pi in near_p:
			var p_pos := pos_arr[pi]
			var best_ej := -1
			var best_d := UNIT_BEAM_RANGE
			for _probe_k in range(mini(12, e_active_n)):
				var cand_j := (pi * 7 + _probe_k * e_step) % e_active_n
				var d := p_pos.distance_to(e_pos_arr[cand_j])
				if d < best_d:
					best_d = d
					best_ej = cand_j
			if best_ej >= 0:
				# Both units exchange laser beams!
				e_hp_arr[best_ej] -= base_shot_dmg * p_mult
				hp_arr[pi] -= base_shot_dmg * e_mult
				if beam_budget > 0:
					beam_budget -= 1
					tracers.append({"a": p_pos, "b": e_pos_arr[best_ej], "c": Color(0.38, 0.96, 1.0, 0.92), "life": 0.20})
					tracers.append({"a": e_pos_arr[best_ej], "b": p_pos, "c": Color(1.0, 0.24, 0.34, 0.92), "life": 0.20})
				if e_hp_arr[best_ej] <= 0.0 and not (best_ej in e_kill_list):
					e_kill_list.append(best_ej)
				if hp_arr[pi] <= 0.0 and not (pi in p_kill_list):
					p_kill_list.append(pi)

		e_kill_list.sort()
		for k in range(e_kill_list.size() - 1, -1, -1):
			var ej := e_kill_list[k]
			if ej < e_active_n:
				if planet and randf() < 0.35:
					planet.spawn_sparks(e_pos_arr[ej], Color(1.0, 0.32, 0.26), 5)
				_remove_enemy_ship(ej)

		p_kill_list.sort()
		for k in range(p_kill_list.size() - 1, -1, -1):
			var pi := p_kill_list[k]
			if pi < active_n:
				if planet and randf() < 0.35:
					planet.spawn_sparks(pos_arr[pi], Color(0.42, 0.96, 1.0), 5)
				_remove_player_ship(pi)

	# B) Arrived Player Swarm Units Attack ASTRA-V Surface Enemy Factories, Mass Drivers, and Orbital Core!
	if planet and (not State.astra_liberated or not State.boss_dead):
		var fac_beam_budget := 6
		for pi in near_p:
			if pi >= active_n: continue
			var p_pos := pos_arr[pi]
			var best_bi := -1
			var best_fd := UNIT_BEAM_RANGE * 1.45
			for bi in range(planet.astra_bastions.size()):
				var bst: Dictionary = planet.astra_bastions[bi]
				if not bool(bst["alive"]): continue
				var f_pos := astra_off + Vector2(bst["local_pos"])
				var fd := p_pos.distance_to(f_pos)
				if fd < best_fd:
					best_fd = fd
					best_bi = bi
			if best_bi >= 0:
				var bst_t: Dictionary = planet.astra_bastions[best_bi]
				var f_pos_t := astra_off + Vector2(bst_t["local_pos"])
				planet.damage_astra_facility(best_bi, base_shot_dmg * p_mult * 0.55)
				if fac_beam_budget > 0:
					fac_beam_budget -= 1
					tracers.append({"a": p_pos, "b": f_pos_t, "c": Color(1.0, 0.86, 0.34, 0.94), "life": 0.22})
			elif not State.boss_dead and p_pos.distance_to(boss_pos) <= UNIT_BEAM_RANGE * 1.6:
				damage_boss(base_shot_dmg * p_mult * 0.50)
				if fac_beam_budget > 0:
					fac_beam_budget -= 1
					tracers.append({"a": p_pos, "b": boss_pos + Vector2(randf_range(-45, 45), randf_range(-45, 45)), "c": Color(1.0, 0.86, 0.34, 0.94), "life": 0.22})

func _draw() -> void:
	var glow := ArtReg.get_t("glow")
	if not State.boss_dead:
		if glow:
			draw_texture_rect(glow, Rect2(boss_pos.x - 190, boss_pos.y - 190, 380, 380), false, Color(1.0, 0.22, 0.24, 0.28))
		var ft := ArtReg.get_t("enemy_station")
		if ft: draw_texture_rect(ft, Rect2(boss_pos.x - 120, boss_pos.y - 90, 240, 180), false)
		var f := clampf(State.boss_hp / maxf(1.0, State.boss_max_hp), 0.0, 1.0)
		draw_rect(Rect2(boss_pos.x - 74, boss_pos.y - 108, 148, 9), Color(0.06, 0.08, 0.12, 0.9))
		draw_rect(Rect2(boss_pos.x - 72, boss_pos.y - 106, 144 * f, 5), Color(1.0, 0.28, 0.34))
	var probe_tex := ArtReg.get_t("enemy_probe")
	for rd in raiders:
		var rp: Vector2 = rd["pos"]
		var rot := float(rd.get("rot", 0.0))
		if glow:
			draw_texture_rect(glow, Rect2(rp.x - 30, rp.y - 30, 60, 60), false, Color(1.0, 0.16, 0.24, 0.28))
		draw_set_transform(rp, rot, Vector2.ONE)
		# Crimson plasma thruster plume behind the self-replicating probe
		draw_polygon(
			PackedVector2Array([Vector2(-15, -4), Vector2(-28, 0), Vector2(-15, 4)]),
			PackedColorArray([Color(1.0, 0.28, 0.22, 0.85), Color(1.0, 0.72, 0.26, 0.15), Color(1.0, 0.28, 0.22, 0.85)])
		)
		if probe_tex:
			draw_texture_rect(probe_tex, Rect2(-20, -20, 40, 40), false)
		else:
			draw_polygon(
				PackedVector2Array([Vector2(18, 0), Vector2(-12, -13), Vector2(-7, 0), Vector2(-12, 13)]),
				PackedColorArray([Color(0.92, 0.16, 0.24)])
			)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var rf := clampf(float(rd["hp"]) / maxf(1.0, float(rd.get("max_hp", 65.0))), 0.0, 1.0)
		draw_rect(Rect2(rp.x - 16, rp.y - 24, 32, 4), Color(0.08, 0.08, 0.12, 0.92))
		draw_rect(Rect2(rp.x - 16, rp.y - 24, 32 * rf, 4), Color(1.0, 0.30, 0.36))
	for etr in enemy_launch_trails:
		var ep_t: Vector2 = etr["pos"]
		var ev_t: Vector2 = etr["vel"].normalized()
		draw_line(ep_t, ep_t - ev_t * 48.0, Color(1.0, 0.24, 0.34, 0.88), 3.4)
		draw_circle(ep_t, 5.0, Color(1.0, 0.72, 0.28))
	for tr in tracers:
		draw_line(tr["a"], tr["b"], tr["c"], 2.8)
		draw_line(tr["a"], tr["b"], Color(1.0, 0.98, 0.86, 0.9), 1.0)
