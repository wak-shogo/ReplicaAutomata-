extends Node2D

# GPU-Instanced 10,000-Unit Swarm Fleet (MultiMeshInstance2D) + Upper-Right Corrupted Orbital Fortress.
# Streams sweeping golden ribbons of autonomous replica ships across the starfield sky
# right above the curved planet, exchanging laser tracers with the Enemy Station!

const MAX_SHIPS: int = 10000

var planet: SphericalPlanet = null
var mm_node: MultiMeshInstance2D = null
var mm: MultiMesh = null

var pos_arr: PackedVector2Array
var vel_arr: PackedVector2Array
var orb_r: PackedFloat32Array
var orb_a: PackedFloat32Array
var orb_spd: PackedFloat32Array
var active_n: int = 0

# Corrupted Enemy Orbital Fortress positioned dramatically in upper-right orbit (concept art!)
var boss_ang: float = -PI * 0.38
var boss_r: float = 5250.0
var boss_pos: Vector2 = Vector2.ZERO

var raiders: Array[Dictionary] = []
var tracers: Array[Dictionary] = []
var _doc_t: float = 0.0
var _raid_t: float = 0.0

func _ready() -> void:
	z_index = 15
	_init_multimesh()
	pos_arr.resize(MAX_SHIPS); vel_arr.resize(MAX_SHIPS)
	orb_r.resize(MAX_SHIPS); orb_a.resize(MAX_SHIPS); orb_spd.resize(MAX_SHIPS)
	boss_pos = Vector2(cos(boss_ang), sin(boss_ang)) * boss_r

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
		if Vector2(raiders[i]["pos"]).distance_to(p) <= 90.0:
			raiders[i]["hp"] = float(raiders[i]["hp"]) - dmg
			if float(raiders[i]["hp"]) <= 0.0:
				if planet: planet.spawn_sparks(raiders[i]["pos"], Color(1.0, 0.44, 0.24), 10)
				State.add_r("ti", 2); raiders.remove_at(i)
			return

func damage_boss(dmg: float) -> void:
	if State.boss_dead: return
	State.boss_hp = maxf(0.0, State.boss_hp - dmg)
	if planet and randf() < 0.45:
		planet.spawn_sparks(boss_pos + Vector2(randf_range(-65, 65), randf_range(-45, 45)), Color(1.0, 0.72, 0.28), 6)
	if State.boss_hp <= 0.0:
		State.boss_dead = true
		if planet: planet.spawn_sparks(boss_pos, Color(1.0, 0.56, 0.22), 40)
		Sfx.play("boom")
		State.add_log("汚染軌道要塞を撃破しました！", "good")
		State.check_victory()

func _process(delta: float) -> void:
	_sync()
	if not State.boss_dead:
		boss_ang = wrapf(boss_ang + 0.004 * delta, -PI, PI)
		boss_pos = Vector2(cos(boss_ang), sin(boss_ang)) * boss_r

	if not State.boss_dead and (State.propulsion_tier >= 2 or State.swarm_fleet >= 24):
		_raid_t += delta
		if _raid_t >= 18.0 and raiders.size() < 6:
			_raid_t = 0.0
			raiders.append({"pos": boss_pos + Vector2(randf_range(-90, 90), randf_range(-90, 90)), "vel": Vector2.ZERO, "hp": 60.0})

	for rd in raiders:
		var tgt := Vector2(0.0, -SphericalPlanet.R_SURFACE - 260.0)
		rd["vel"] = Vector2(rd["vel"]).lerp((tgt - Vector2(rd["pos"])).normalized() * 230.0, delta * 1.4)
		rd["pos"] = Vector2(rd["pos"]) + Vector2(rd["vel"]) * delta

	_doc_t += delta
	if _doc_t >= 1.0:
		_doc_t = 0.0
		var n := State.swarm_fleet
		if n > 0:
			match State.doctrine:
				State.Doctrine.HARVEST:
					State.add_r(["fe", "cu", "si", "ti"][randi() % 4], maxi(1, int(sqrt(float(n)) * 0.5)))
				State.Doctrine.REPLICATE:
					State.swarm_fleet = mini(State.SWARM_MAX, State.swarm_fleet + maxi(1, int(float(n) * 0.05)))
				State.Doctrine.DEFEND:
					if not raiders.is_empty(): damage_raider_near(raiders[0]["pos"], 20.0 + float(n) * 0.15)
				State.Doctrine.ASSAULT:
					if not State.boss_dead:
						var dps := 10.0 + sqrt(float(n)) * 4.2 + (50.0 if bool(State.megastructures["citadel"]) else 0.0)
						damage_boss(dps)
						if active_n > 0:
							for _k in range(mini(4, active_n)):
								var si := randi() % active_n
								tracers.append({"a": pos_arr[si], "b": boss_pos + Vector2(randf_range(-48, 48), randf_range(-38, 38)), "c": Color(1.0, 0.84, 0.34, 0.92), "life": 0.24})

	var asslt := (State.doctrine == State.Doctrine.ASSAULT and not State.boss_dead)
	for i in range(active_n):
		orb_a[i] += orb_spd[i] * delta
		var goal := Vector2(cos(orb_a[i]), sin(orb_a[i])) * orb_r[i]
		if asslt and (i % 3 != 0):
			var sw := orb_a[i] * 5.0 + float(i) * 0.19
			goal = boss_pos + Vector2(cos(sw), sin(sw)) * (210.0 + float(i % 7) * 48.0)
		var dg := goal - pos_arr[i]
		vel_arr[i] = vel_arr[i].lerp(dg.normalized() * clampf(dg.length() * 1.15, 190.0, 620.0), clampf(delta * 2.5, 0.0, 1.0))
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
	for rd in raiders:
		draw_circle(rd["pos"], 9.0, Color(1.0, 0.26, 0.32))
	for tr in tracers:
		draw_line(tr["a"], tr["b"], tr["c"], 2.8)
		draw_line(tr["a"], tr["b"], Color(1.0, 0.98, 0.86, 0.9), 1.0)
