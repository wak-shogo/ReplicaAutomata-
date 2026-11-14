extends Node2D
class_name SwarmSimulation

# ==============================================================================
# STAR REPLICA: AUTOMA - 360-DEGREE SPHERICAL ORBIT 10k SWARM ECS
# Orbits Origin-Prime (0,0), harvests asteroid rings, defends planet horizon,
# self-replicates in space, and sieges the open-world Corrupted Core Hub.
# ==============================================================================

const MAX_FRIENDLY: int = 10000
const MAX_HOSTILE: int = 1200

var world: PlanetWorld

var f_pos: PackedVector2Array = PackedVector2Array()
var f_vel: PackedVector2Array = PackedVector2Array()
var f_active: int = 0

var h_pos: PackedVector2Array = PackedVector2Array()
var h_vel: PackedVector2Array = PackedVector2Array()
var h_hp: PackedFloat32Array = PackedFloat32Array()
var h_active: int = 0

var friendly_mm: MultiMeshInstance2D
var hostile_mm: MultiMeshInstance2D

var boss_pos: Vector2 = Vector2(18500.0, -17200.0)
var tex_boss: Texture2D

var shot_fx: Array[Dictionary] = []
var explode_fx: Array[Dictionary] = []
var sim_time: float = 0.0
var rep_accum: float = 0.0
var harvest_accum: float = 0.0
var wave_timer: float = 0.0

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tex_boss = load("res://assets/sprites/corrupted_core_hub.png")
	_init_multimeshes()
	reset_swarm()

func setup(p_world: PlanetWorld) -> void:
	world = p_world

func _init_multimeshes() -> void:
	f_pos.resize(MAX_FRIENDLY)
	f_vel.resize(MAX_FRIENDLY)
	h_pos.resize(MAX_HOSTILE)
	h_vel.resize(MAX_HOSTILE)
	h_hp.resize(MAX_HOSTILE)

	friendly_mm = MultiMeshInstance2D.new()
	friendly_mm.texture = load("res://assets/sprites/fleet_fighter.png")
	friendly_mm.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var f_mesh = MultiMesh.new()
	f_mesh.transform_format = MultiMesh.TRANSFORM_2D
	var fq = QuadMesh.new()
	fq.size = Vector2(20.0, 20.0)
	f_mesh.mesh = fq
	f_mesh.instance_count = MAX_FRIENDLY
	f_mesh.visible_instance_count = 0
	friendly_mm.multimesh = f_mesh
	add_child(friendly_mm)

	hostile_mm = MultiMeshInstance2D.new()
	var c_tex_path = "res://assets/sprites/corrupted_fighter.png" if ResourceLoader.exists("res://assets/sprites/corrupted_fighter.png") else "res://assets/sprites/hostile_fighter.png"
	hostile_mm.texture = load(c_tex_path)
	hostile_mm.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var h_mesh = MultiMesh.new()
	h_mesh.transform_format = MultiMesh.TRANSFORM_2D
	var hq = QuadMesh.new()
	hq.size = Vector2(24.0, 24.0)
	h_mesh.mesh = hq
	h_mesh.instance_count = MAX_HOSTILE
	h_mesh.visible_instance_count = 0
	hostile_mm.multimesh = h_mesh
	add_child(hostile_mm)

func reset_swarm() -> void:
	f_active = 0
	h_active = 0
	shot_fx.clear()
	explode_fx.clear()
	rep_accum = 0.0
	harvest_accum = 0.0
	wave_timer = 0.0
	if friendly_mm and friendly_mm.multimesh:
		friendly_mm.multimesh.visible_instance_count = 0
	if hostile_mm and hostile_mm.multimesh:
		hostile_mm.multimesh.visible_instance_count = 0
	# Natural enemy guard patrol in deep space around Corrupted Hub
	spawn_hostile_units(24, boss_pos)
	GameState.hostiles_active = h_active
	queue_redraw()

func sync_to_game_state(target_count: int) -> void:
	var clamped = clampi(target_count, 0, MAX_FRIENDLY)
	if clamped > f_active:
		spawn_friendly_units(clamped - f_active, Vector2(0.0, -(PlanetWorld.R_SURFACE + 560.0)))
	elif clamped < f_active:
		f_active = clamped
		friendly_mm.multimesh.visible_instance_count = f_active

func spawn_friendly_units(count: int, origin: Vector2) -> void:
	var n = mini(count, MAX_FRIENDLY - f_active)
	for _i in range(n):
		var ang = float(f_active) * 2.39996 + randf_range(-0.2, 0.2)
		var rad = randf_range(60.0, 950.0 if count > 10 else 140.0)
		var p = origin + Vector2(cos(ang), sin(ang)) * rad
		if p.length() < PlanetWorld.R_SURFACE + 380.0:
			p = p.normalized() * (PlanetWorld.R_SURFACE + 420.0)
		f_pos[f_active] = p
		f_vel[f_active] = Vector2(-p.y, p.x).normalized() * randf_range(260.0, 480.0)
		f_active += 1
	friendly_mm.multimesh.visible_instance_count = f_active

func spawn_hostile_units(count: int, origin: Vector2) -> void:
	var n = mini(count, MAX_HOSTILE - h_active)
	for _i in range(n):
		var ang = randf_range(0.0, TAU)
		var rad = randf_range(28.0, 140.0)
		h_pos[h_active] = origin + Vector2(cos(ang), sin(ang)) * rad
		h_vel[h_active] = Vector2(cos(ang), sin(ang)) * randf_range(80.0, 145.0)
		h_hp[h_active] = 35.0
		h_active += 1
	hostile_mm.multimesh.visible_instance_count = h_active
	GameState.hostiles_active = h_active

func find_nearest_hostile(from_pos: Vector2, max_range: float) -> Vector2:
	var best = Vector2.ZERO
	var best_d2 = max_range * max_range
	for i in range(h_active):
		var d2 = _dist2(from_pos, h_pos[i])
		if d2 < best_d2:
			best_d2 = d2
			best = h_pos[i]
	return best

func damage_hostile_near(at_pos: Vector2, dmg: float) -> void:
	for i in range(h_active - 1, -1, -1):
		if h_pos[i].distance_to(at_pos) < 38.0:
			h_hp[i] -= dmg
			if h_hp[i] <= 0.0:
				_remove_hostile(i, at_pos)
			return

func _remove_hostile(idx: int, fx_pos: Vector2) -> void:
	explode_fx.append({"pos": fx_pos, "life": 0.35, "col": Color(1.0, 0.38, 0.28)})
	var last = h_active - 1
	if idx != last:
		h_pos[idx] = h_pos[last]
		h_vel[idx] = h_vel[last]
		h_hp[idx] = h_hp[last]
	h_active = last
	hostile_mm.multimesh.visible_instance_count = h_active
	GameState.hostiles_active = h_active
	GameState.hostiles_defeated += 1

func _dist2(a: Vector2, b: Vector2) -> float:
	var dx = a.x - b.x
	var dy = a.y - b.y
	return dx * dx + dy * dy

func _process(delta: float) -> void:
	sim_time += delta
	if GameState.fleet_count != f_active:
		sync_to_game_state(GameState.fleet_count)

	var doc = GameState.current_doctrine

	if f_active > 0:
		if doc == GameState.Doctrine.HARVEST and world and world.asteroids.size() > 0:
			harvest_accum += delta * (0.95 + sqrt(float(f_active)) * 0.55)
			if harvest_accum >= 1.0:
				var gain = int(harvest_accum)
				harvest_accum -= float(gain)
				GameState.add_res(["fe", "cu", "si", "ti"][int(sim_time) % 4], gain)
		elif doc == GameState.Doctrine.REPLICATE:
			var g_mult = 2.6 if GameState.megastructures["warpgate"] else 1.0
			var d_mult = 1.6 if GameState.megastructures["dyson"] else 1.0
			rep_accum += delta * (0.14 + float(f_active) * 0.048) * g_mult * d_mult
			if rep_accum >= 1.0 and GameState.fleet_count < MAX_FRIENDLY:
				var batch = clampi(int(rep_accum), 1, 25)
				rep_accum -= float(batch)
				if GameState.fe >= 2:
					GameState.add_res("fe", -2)
					GameState.add_fleet_units(batch)
					AudioSynth.play_synth("replicate")
				elif GameState.megastructures["warpgate"]:
					GameState.add_fleet_units(batch)

	if not GameState.boss_defeated and f_active >= 6:
		wave_timer += delta
		if wave_timer >= 18.0 and h_active < 120:
			wave_timer = 0.0
			spawn_hostile_units(mini(16, 4 + f_active / 12), boss_pos)

	var f_mesh = friendly_mm.multimesh
	var ast_count = world.asteroids.size() if world else 0
	var combat_shots = 0

	for i in range(f_active):
		var p = f_pos[i]
		var v = f_vel[i]
		var phi = float(i) * 2.39996 + sim_time * 0.25
		var ring_r = PlanetWorld.R_ATMOS_OUTER + 420.0 + float(i % 15) * 90.0
		var wing_off = Vector2(cos(phi), sin(phi)) * (140.0 + float(i % 13) * 45.0)
		var target = Vector2(cos(phi), sin(phi)) * ring_r

		match doc:
			GameState.Doctrine.HARVEST:
				if ast_count > 0:
					target = world.asteroids[i % ast_count]["pos"] + wing_off * 0.5
			GameState.Doctrine.REPLICATE:
				var ra = sim_time * 0.45 + float(i) * 0.11
				target = Vector2(cos(ra), sin(ra)) * (PlanetWorld.R_SURFACE + 1400.0 + float(i % 12) * 85.0)
			GameState.Doctrine.DEFEND:
				var da = sim_time * 0.55 + float(i) * 0.19
				target = Vector2(cos(da), sin(da)) * (PlanetWorld.R_SURFACE + 520.0 + float(i % 9) * 65.0)
			GameState.Doctrine.ASSAULT:
				if h_active > 0:
					target = h_pos[i % h_active] + wing_off * 0.75
				elif not GameState.boss_defeated:
					target = boss_pos + wing_off * 0.8

		var to_tgt = target - p
		var dist = to_tgt.length()
		if dist > 6.0:
			var steer = (to_tgt / dist) * 760.0 - v
			v += steer.limit_length(820.0 * delta)
		v = v.limit_length(780.0)
		p += v * delta

		# Planetary surface clearance so ships orbit around 10x sphere cleanly
		if p.length() < PlanetWorld.R_SURFACE + 280.0:
			p = p.normalized() * (PlanetWorld.R_SURFACE + 290.0)

		f_pos[i] = p
		f_vel[i] = v
		f_mesh.set_instance_transform_2d(i, Transform2D(v.angle() + PI * 0.5, p))

		if combat_shots < 12 and (i + int(sim_time * 20.0)) % 9 == 0:
			if h_active > 0:
				var hi = i % h_active
				if _dist2(p, h_pos[hi]) < 280.0 * 280.0:
					combat_shots += 1
					var dmg_mult = 2.0 if GameState.megastructures["citadel"] else 1.0
					h_hp[hi] -= 18.0 * dmg_mult * delta * 8.0
					shot_fx.append({"from": p, "to": h_pos[hi], "life": 0.11, "col": Color(0.3, 0.95, 1.0)})
					if h_hp[hi] <= 0.0:
						_remove_hostile(hi, h_pos[hi])
			elif doc == GameState.Doctrine.ASSAULT and not GameState.boss_defeated and _dist2(p, boss_pos) < 300.0 * 300.0:
				combat_shots += 1
				var boss_dmg = 12.0 * (2.0 if GameState.megastructures["citadel"] else 1.0) * delta * 6.0
				GameState.boss_hp = maxf(0.0, GameState.boss_hp - boss_dmg)
				shot_fx.append({"from": p, "to": boss_pos, "life": 0.12, "col": Color(0.35, 0.95, 1.0)})
				if GameState.boss_hp <= 0.0 and not GameState.boss_defeated:
					_on_boss_defeated()

	var h_mesh = hostile_mm.multimesh
	for i in range(h_active):
		var p = h_pos[i]
		var v = h_vel[i]
		var tgt = boss_pos + Vector2(cos(sim_time + float(i)), sin(sim_time * 1.2 + float(i))) * 160.0
		if f_active >= 6 and (i % 3 == 0):
			tgt = f_pos[i % f_active]
		var dir = (tgt - p).normalized()
		v = v.lerp(dir * 140.0, clampf(2.2 * delta, 0.0, 1.0))
		p += v * delta
		if p.length() < PlanetWorld.R_SURFACE + 90.0:
			p = p.normalized() * (PlanetWorld.R_SURFACE + 92.0)
		h_pos[i] = p
		h_vel[i] = v
		h_mesh.set_instance_transform_2d(i, Transform2D(v.angle() + PI * 0.5, p))

	for si in range(shot_fx.size() - 1, -1, -1):
		shot_fx[si]["life"] -= delta
		if shot_fx[si]["life"] <= 0.0:
			shot_fx.remove_at(si)
	for ei in range(explode_fx.size() - 1, -1, -1):
		explode_fx[ei]["life"] -= delta
		if explode_fx[ei]["life"] <= 0.0:
			explode_fx.remove_at(ei)

	queue_redraw()

func _on_boss_defeated() -> void:
	GameState.boss_defeated = true
	if GameState.megastructures["warpgate"]:
		GameState.game_won = true
		GameState.emit_signal("log_event", "COLONY VICTORY: CORRUPTED HUB LIBERATED!", "good")
	else:
		GameState.emit_signal("log_event", "CORRUPTED CORE HUB LIBERATED!", "good")
	AudioSynth.play_synth("victory")
	for _i in range(20):
		explode_fx.append({
			"pos": boss_pos + Vector2(randf_range(-80.0, 80.0), randf_range(-80.0, 80.0)),
			"life": 0.7,
			"col": Color(1.0, 0.75, 0.35),
		})
	GameState.add_res("ti", 150)
	GameState.add_res("circuit", 50)

func _draw() -> void:
	var font = ThemeDB.fallback_font
	if not GameState.boss_defeated:
		# HD-2D Boss Glow Halo, Rotating Energy Ring & Escort Bombers/Cruisers
		var pulse = 0.85 + 0.15 * sin(sim_time * 3.5)
		draw_circle(boss_pos, 145.0 * pulse, Color(0.95, 0.14, 0.28, 0.18))
		draw_arc(boss_pos, 118.0, sim_time * 0.7, sim_time * 0.7 + 2.4, 28, Color(1.0, 0.30, 0.36, 0.65), 3.0)
		draw_arc(boss_pos, 118.0, sim_time * 0.7 + PI, sim_time * 0.7 + PI + 2.4, 28, Color(1.0, 0.30, 0.36, 0.65), 3.0)
		for k in range(3):
			var ka = sim_time * 0.55 + float(k) * (TAU / 3.0)
			var kp = boss_pos + Vector2(cos(ka), sin(ka)) * 118.0
			draw_circle(kp, 8.0, Color(1.0, 0.38, 0.38, 0.92))
		if tex_boss:
			var bsz = tex_boss.get_size() * 1.35
			draw_texture_rect(tex_boss, Rect2(boss_pos - bsz * 0.5, bsz), false)
		if font:
			draw_string(font, boss_pos + Vector2(-72, -108), "CORRUPTED CORE HUB", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.42, 0.36))
			var br = Rect2(boss_pos + Vector2(-68, -94), Vector2(136, 10))
			draw_rect(br, Color(0.1, 0.05, 0.08, 0.92))
			draw_rect(Rect2(br.position, Vector2(br.size.x * clampf(GameState.boss_hp / GameState.boss_max_hp, 0.0, 1.0), 10)), Color(1.0, 0.25, 0.28))

	# Friendly & Hostile Exhaust Contrails (HD-2D ship crispness)
	for i in range(mini(f_active, 60)):
		var tail = f_pos[i] - f_vel[i].normalized() * 12.0
		draw_line(f_pos[i], tail, Color(0.28, 0.92, 1.0, 0.42), 2.0)
	for i in range(mini(h_active, 40)):
		var tail = h_pos[i] - h_vel[i].normalized() * 14.0
		draw_line(h_pos[i], tail, Color(1.0, 0.30, 0.34, 0.45), 2.0)

	for s in shot_fx:
		var a = clampf(s["life"] / 0.12, 0.0, 1.0)
		var c: Color = s["col"]
		c.a = a
		draw_line(s["from"], s["to"], c, 1.8)

	for e in explode_fx:
		var a = clampf(e["life"] / 0.7, 0.0, 1.0)
		var c: Color = e["col"]
		c.a = a
		draw_circle(e["pos"], (1.0 - a) * 32.0 + 4.0, c)
