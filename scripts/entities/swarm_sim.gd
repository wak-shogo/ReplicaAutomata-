extends Node2D

# GPU-Instanced 10,000-Unit Swarm Fleet (MultiMeshInstance2D) + Corrupted Enemy Orbital Fortress Boss.
# Renders sweeping golden ribbons of autonomous replica ships across the starfield sky
# inspired directly by docs/art/target_gameplay_concept.jpeg!

const MAX_RENDER_SHIPS: int = 10000

var world: Node2D = null
var multi_mesh_node: MultiMeshInstance2D = null
var mm: MultiMesh = null

# Flat SOA arrays for 60 FPS up to 10,000 units
var ship_pos: PackedVector2Array
var ship_vel: PackedVector2Array
var ship_orbit_r: PackedFloat32Array
var ship_ang: PackedFloat32Array
var ship_spd: PackedFloat32Array
var active_count: int = 0

# Corrupted Orbital Fortress Boss (upper-right deep orbit, zero pre-built friendly station!)
var boss_pos: Vector2 = Vector2(9200.0, -10400.0)
var boss_ang: float = -PI * 0.27
var boss_orbit_r: float = 13800.0

# Enemy raiders & plasma tracer beams
var raiders: Array[Dictionary] = []
var tracers: Array[Dictionary] = []
var _doctrine_t: float = 0.0
var _raider_t: float = 0.0

func _ready() -> void:
	z_index = 15
	_setup_multimesh()
	ship_pos.resize(MAX_RENDER_SHIPS)
	ship_vel.resize(MAX_RENDER_SHIPS)
	ship_orbit_r.resize(MAX_RENDER_SHIPS)
	ship_ang.resize(MAX_RENDER_SHIPS)
	ship_spd.resize(MAX_RENDER_SHIPS)

func _setup_multimesh() -> void:
	multi_mesh_node = MultiMeshInstance2D.new()
	mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.instance_count = MAX_RENDER_SHIPS
	mm.visible_instance_count = 0

	# Sleek delta-wing spacecraft mesh (6 vertices = 2 triangles)
	var mesh := ArrayMesh.new()
	var verts := PackedVector2Array([
		Vector2(10, 0), Vector2(-7, -5), Vector2(-4, 0),
		Vector2(10, 0), Vector2(-4, 0), Vector2(-7, 5),
	])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mm.mesh = mesh

	multi_mesh_node.multimesh = mm
	add_child(multi_mesh_node)

func reset_swarm() -> void:
	active_count = 0
	if mm:
		mm.visible_instance_count = 0
	raiders.clear()
	tracers.clear()
	boss_ang = -PI * 0.27
	boss_pos = Vector2(cos(boss_ang), sin(boss_ang)) * boss_orbit_r

func spawn_launched_units(origin: Vector2, dir: Vector2, count: int) -> void:
	for _i in range(count):
		if active_count >= MAX_RENDER_SHIPS:
			break
		var i := active_count
		active_count += 1
		ship_pos[i] = origin + Vector2(randf_range(-24, 24), randf_range(-24, 24))
		ship_vel[i] = dir * randf_range(380.0, 560.0)
		ship_orbit_r[i] = randf_range(PlanetWorld.R_ATMOS + 450.0, PlanetWorld.R_ATMOS + 3800.0)
		ship_ang[i] = atan2(origin.y, origin.x) + randf_range(-0.12, 0.12)
		ship_spd[i] = randf_range(0.032, 0.068) * (1.0 if i % 5 != 0 else -1.0)
	_sync_count()

func _sync_count() -> void:
	var target := mini(MAX_RENDER_SHIPS, GameState.swarm_fleet)
	while active_count < target:
		var i := active_count
		active_count += 1
		var a := randf_range(0.0, TAU)
		var r := randf_range(PlanetWorld.R_ATMOS + 400.0, PlanetWorld.R_ATMOS + 3900.0)
		ship_ang[i] = a
		ship_orbit_r[i] = r
		ship_pos[i] = Vector2(cos(a), sin(a)) * r
		ship_vel[i] = Vector2(-sin(a), cos(a)) * 280.0
		ship_spd[i] = randf_range(0.030, 0.066)
	if active_count > target:
		active_count = target
	if mm:
		mm.visible_instance_count = active_count

func find_nearest_raider(pos: Vector2, max_d: float) -> Vector2:
	var best_d := max_d
	var best := Vector2.ZERO
	for r in raiders:
		var d := pos.distance_to(r["pos"])
		if d < best_d:
			best_d = d
			best = r["pos"]
	return best

func damage_raider_near(pos: Vector2, dmg: float) -> void:
	for i in range(raiders.size() - 1, -1, -1):
		if Vector2(raiders[i]["pos"]).distance_to(pos) <= 90.0:
			raiders[i]["hp"] = float(raiders[i]["hp"]) - dmg
			if float(raiders[i]["hp"]) <= 0.0:
				if world:
					world.spawn_spark_burst(raiders[i]["pos"], Color(1.0, 0.42, 0.25), 10)
				GameState.add_res("ti", 2)
				raiders.remove_at(i)
			return

func damage_boss(dmg: float) -> void:
	if GameState.boss_defeated:
		return
	GameState.boss_hp = maxf(0.0, GameState.boss_hp - dmg)
	if world and randf() < 0.4:
		world.spawn_spark_burst(boss_pos + Vector2(randf_range(-55, 55), randf_range(-40, 40)), Color(1.0, 0.68, 0.28), 6)
	if GameState.boss_hp <= 0.0:
		GameState.boss_defeated = true
		if world:
			world.spawn_spark_burst(boss_pos, Color(1.0, 0.55, 0.22), 36)
		AudioSynth.play_sfx("explosion")
		GameState.add_log("CORRUPTED ORBITAL FORTRESS DESTROYED!", "good")
		GameState.check_victory()

func _process(delta: float) -> void:
	_sync_count()

	# Orbit boss station slowly
	if not GameState.boss_defeated:
		boss_ang = wrapf(boss_ang + 0.0055 * delta, -PI, PI)
		boss_pos = Vector2(cos(boss_ang), sin(boss_ang)) * boss_orbit_r

	# Spawn occasional hostile raiders once swarm or tier >= 2 activates
	if not GameState.boss_defeated and (GameState.vessel_tier >= 2 or GameState.swarm_fleet >= 20):
		_raider_t += delta
		if _raider_t >= 18.0 and raiders.size() < 6:
			_raider_t = 0.0
			var spawn_p := boss_pos + Vector2(randf_range(-120, 120), randf_range(-120, 120))
			raiders.append({"pos": spawn_p, "vel": Vector2.ZERO, "hp": 60.0})

	for i in range(raiders.size() - 1, -1, -1):
		var rd := raiders[i]
		var target := Vector2(0.0, -PlanetWorld.R_SURFACE - 340.0)
		var to_t: Vector2 = (target - Vector2(rd["pos"])).normalized()
		rd["vel"] = Vector2(rd["vel"]).lerp(to_t * 240.0, delta * 1.4)
		rd["pos"] = Vector2(rd["pos"]) + Vector2(rd["vel"]) * delta

	# Swarm Fleet Doctrine macro effects (1s cadence)
	_doctrine_t += delta
	if _doctrine_t >= 1.0:
		_doctrine_t = 0.0
		var n := GameState.swarm_fleet
		if n > 0:
			match GameState.doctrine:
				GameState.Doctrine.HARVEST:
					var yield_n := maxi(1, int(sqrt(float(n)) * 0.45))
					GameState.add_res(["fe", "cu", "si", "ti"][randi() % 4], yield_n)
				GameState.Doctrine.REPLICATE:
					var growth := maxi(1, int(float(n) * 0.045))
					GameState.swarm_fleet = mini(GameState.SWARM_MAX, GameState.swarm_fleet + growth)
				GameState.Doctrine.DEFEND:
					if not raiders.is_empty():
						damage_raider_near(raiders[0]["pos"], 18.0 + float(n) * 0.15)
				GameState.Doctrine.ASSAULT:
					if not GameState.boss_defeated:
						var dps := 8.0 + sqrt(float(n)) * 3.8 + (45.0 if bool(GameState.megastructures.get("citadel", false)) else 0.0)
						damage_boss(dps)
						if active_count > 0:
							var s_idx := randi() % active_count
							tracers.append({"a": ship_pos[s_idx], "b": boss_pos + Vector2(randf_range(-40, 40), randf_range(-40, 40)), "col": Color(1.0, 0.84, 0.32, 0.9), "life": 0.22})

	# Update GPU MultiMesh2D transforms (streaming golden orbital ribbons!)
	var assaulting := (GameState.doctrine == GameState.Doctrine.ASSAULT and not GameState.boss_defeated)
	for i in range(active_count):
		ship_ang[i] += ship_spd[i] * delta
		var goal := Vector2(cos(ship_ang[i]), sin(ship_ang[i])) * ship_orbit_r[i]
		if assaulting and (i % 3 != 0):
			var sw_a := ship_ang[i] * 5.0 + float(i) * 0.17
			goal = boss_pos + Vector2(cos(sw_a), sin(sw_a)) * (260.0 + float(i % 7) * 55.0)
		var to_g := goal - ship_pos[i]
		var desired := to_g.normalized() * clampf(to_g.length() * 1.1, 180.0, 620.0)
		ship_vel[i] = ship_vel[i].lerp(desired, clampf(delta * 2.4, 0.0, 1.0))
		ship_pos[i] += ship_vel[i] * delta
		var rot := ship_vel[i].angle()
		mm.set_instance_transform_2d(i, Transform2D(rot, ship_pos[i]))
		# Golden luminous tint matching concept art swarm ships!
		var tint := Color(1.0, 0.86, 0.42) if (i % 4 != 0) else Color(0.55, 0.92, 1.0)
		mm.set_instance_color(i, tint)

	for i in range(tracers.size() - 1, -1, -1):
		tracers[i]["life"] -= delta
		if float(tracers[i]["life"]) <= 0.0:
			tracers.remove_at(i)

	queue_redraw()

func _draw() -> void:
	var glow := ArtRegistry.get_tex("glow_soft")
	# Draw Corrupted Orbital Fortress Boss
	if not GameState.boss_defeated:
		if glow:
			draw_texture_rect(glow, Rect2(boss_pos.x - 210, boss_pos.y - 210, 420, 420), false, Color(1.0, 0.22, 0.25, 0.28))
		var ftex := ArtRegistry.get_tex("enemy_fortress")
		if ftex:
			draw_texture_rect(ftex, Rect2(boss_pos.x - 160, boss_pos.y - 120, 320, 240), false)
		else:
			draw_circle(boss_pos, 95.0, Color(0.9, 0.22, 0.28))
		# Boss integrity bar
		var hp_f := clampf(GameState.boss_hp / maxf(1.0, GameState.boss_max_hp), 0.0, 1.0)
		draw_rect(Rect2(boss_pos.x - 86, boss_pos.y - 138, 172, 10), Color(0.08, 0.10, 0.14, 0.9))
		draw_rect(Rect2(boss_pos.x - 84, boss_pos.y - 136, 168 * hp_f, 6), Color(1.0, 0.28, 0.34))

	# Draw Enemy Raiders
	for rd in raiders:
		var rp: Vector2 = rd["pos"]
		draw_circle(rp, 10.0, Color(1.0, 0.26, 0.32))
		draw_arc(rp, 15.0, 0.0, TAU, 16, Color(1.0, 0.45, 0.42, 0.65), 2.0)

	# Draw Plasma Swarm Tracers
	for tr in tracers:
		draw_line(tr["a"], tr["b"], tr["col"], 2.8)
		draw_line(tr["a"], tr["b"], Color(1.0, 0.98, 0.85, 0.9), 1.0)
