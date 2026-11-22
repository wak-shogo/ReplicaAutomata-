extends Node2D

# GPU-Instanced 10,000-Unit Swarm Fleet (MultiMeshInstance2D) +
# Outer Planet ASTRA-V Enemy Stronghold Garrison +
# Pollution-Triggered & Off-Map Continuous Enemy Raids attacking Planetary Facilities!

const MAX_SHIPS: int = 10000

var planet: SphericalPlanet = null
var grid: Node2D = null
var mm_node: MultiMeshInstance2D = null
var mm: MultiMesh = null

var pos_arr: PackedVector2Array
var vel_arr: PackedVector2Array
var orb_r: PackedFloat32Array
var orb_a: PackedFloat32Array
var orb_spd: PackedFloat32Array
var active_n: int = 0

var boss_ang: float = -PI * 0.38
var boss_r: float = 4200.0
var boss_pos: Vector2 = Vector2.ZERO # In HomeSystem (Terra-relative) coordinates

var raiders: Array[Dictionary] = [] # {"pos": terra_local_pos, "vel": Vec2, "hp": float, "max_hp": float, "target_body": String}
var tracers: Array[Dictionary] = []
var _doc_t: float = 0.0
var _raid_t: float = 0.0
var _offmap_raid_t: float = 0.0

func _ready() -> void:
	z_index = 15
	_init_multimesh()
	pos_arr.resize(MAX_SHIPS); vel_arr.resize(MAX_SHIPS)
	orb_r.resize(MAX_SHIPS); orb_a.resize(MAX_SHIPS); orb_spd.resize(MAX_SHIPS)
	_update_boss_pos(0.0)

func _init_multimesh() -> void:
	mm_node = MultiMeshInstance2D.new()
	mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.instance_count = MAX_SHIPS
	mm.visible_instance_count = 0
	var mesh := ArrayMesh.new()
	var v := PackedVector2Array([
		Vector2(9, 0), Vector2(-6, -4.5), Vector2(-3.5, 0),
		Vector2(9, 0), Vector2(-3.5, 0), Vector2(-6, 4.5),
	])
	var arr := []; arr.resize(Mesh.ARRAY_MAX); arr[Mesh.ARRAY_VERTEX] = v
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mm.mesh = mesh
	mm_node.multimesh = mm
	add_child(mm_node)

func _update_boss_pos(delta: float) -> void:
	boss_ang = wrapf(boss_ang + 0.005 * delta, -PI, PI)
	if planet and planet.bodies.has("astra"):
		var astra_off := Vector2(planet.bodies["astra"]["pos"]) - Vector2(planet.bodies["terra"]["pos"])
		boss_pos = astra_off + Vector2(cos(boss_ang), sin(boss_ang)) * boss_r
	else:
		boss_pos = Vector2(cos(boss_ang), sin(boss_ang)) * 5250.0

func spawn_launched(origin: Vector2, dir: Vector2, cnt: int) -> void:
	for _i in range(cnt):
		if active_n >= MAX_SHIPS: break
		var i := active_n; active_n += 1
		pos_arr[i] = origin + Vector2(randf_range(-20, 20), randf_range(-20, 20))
		vel_arr[i] = dir * randf_range(380.0, 560.0)
		orb_r[i] = randf_range(SphericalPlanet.R_SURFACE + 520.0, SphericalPlanet.R_ATMOS + 1100.0)
		orb_a[i] = atan2(origin.y, origin.x) + randf_range(-0.15, 0.15)
		orb_spd[i] = randf_range(0.042, 0.088) * (1.0 if i % 6 != 0 else -1.0)
	_sync()

func _sync() -> void:
	var tgt := mini(MAX_SHIPS, State.swarm_fleet)
	while active_n < tgt:
		var i := active_n; active_n += 1
		var a := -PI * 0.5 + randf_range(-0.8, 0.8) if i < 600 else randf_range(0.0, TAU)
		var r := randf_range(SphericalPlanet.R_SURFACE + 460.0, SphericalPlanet.R_ATMOS + 1100.0)
		orb_a[i] = a; orb_r[i] = r
		pos_arr[i] = Vector2(cos(a), sin(a)) * r
		vel_arr[i] = Vector2(-sin(a), cos(a)) * 280.0
		orb_spd[i] = randf_range(0.040, 0.085)
	if active_n > tgt: active_n = tgt
	if mm: mm.visible_instance_count = active_n

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

	# 4. Swarm Fleet Doctrines (HARVEST, REPLICATE, DEFEND, ASSAULT on ASTRA-V!)
	_doc_t += delta
	if _doc_t >= 1.0:
		_doc_t = 0.0
		var n := State.swarm_fleet
		if n > 0:
			match State.doctrine:
				State.Doctrine.HARVEST:
					State.add_r(["fe", "cu", "si"][randi() % 3], maxi(1, int(sqrt(float(n)) * 0.5)))
				State.Doctrine.REPLICATE:
					State.swarm_fleet = mini(State.SWARM_MAX, State.swarm_fleet + maxi(1, int(float(n) * 0.05)))
				State.Doctrine.DEFEND:
					if not raiders.is_empty():
						var r0_p: Vector2 = raiders[0]["pos"]
						tracers.append({"a": r0_p + Vector2(60, -80), "b": r0_p, "c": Color(0.38, 0.96, 1.0, 0.9), "life": 0.22})
						damage_raider_near(r0_p, 28.0 + float(n) * 0.25)
				State.Doctrine.ASSAULT:
					if not State.boss_dead or not State.astra_liberated:
						var dps := 22.0 + sqrt(float(n)) * 8.5 + (65.0 if bool(State.megastructures["citadel"]) else 0.0)
						damage_boss(dps)
						if active_n > 0:
							for _k in range(mini(5, active_n)):
								var si := randi() % active_n
								tracers.append({"a": pos_arr[si], "b": boss_pos + Vector2(randf_range(-60, 60), randf_range(-60, 60)), "c": Color(1.0, 0.84, 0.34, 0.92), "life": 0.24})

	var asslt := (State.doctrine == State.Doctrine.ASSAULT and (not State.boss_dead or not State.astra_liberated))
	for i in range(active_n):
		orb_a[i] += orb_spd[i] * delta
		var goal := Vector2(cos(orb_a[i]), sin(orb_a[i])) * orb_r[i]
		if asslt and (i % 3 != 0):
			var sw := orb_a[i] * 5.0 + float(i) * 0.19
			goal = boss_pos + Vector2(cos(sw), sin(sw)) * (260.0 + float(i % 7) * 58.0)
		var dg := goal - pos_arr[i]
		vel_arr[i] = vel_arr[i].lerp(dg.normalized() * clampf(dg.length() * 1.15, 220.0, 820.0), clampf(delta * 2.5, 0.0, 1.0))
		pos_arr[i] += vel_arr[i] * delta
		mm.set_instance_transform_2d(i, Transform2D(vel_arr[i].angle(), pos_arr[i]))
		mm.set_instance_color(i, Color(1.0, 0.86, 0.42) if (i % 4 != 0) else Color(0.55, 0.94, 1.0))

	for i in range(tracers.size() - 1, -1, -1):
		tracers[i]["life"] -= delta
		if float(tracers[i]["life"]) <= 0.0: tracers.remove_at(i)
	queue_redraw()

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
	for tr in tracers:
		draw_line(tr["a"], tr["b"], tr["c"], 2.8)
		draw_line(tr["a"], tr["b"], Color(1.0, 0.98, 0.86, 0.9), 1.0)
