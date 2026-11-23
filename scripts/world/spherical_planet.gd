extends Node2D
class_name SphericalPlanet

# Multi-Planet 360-degree Sliced Voxel Solar System:
# - Central SUN at world (0,0)
# - TERRA-I (starter planet: ONLY fe, cu, si — everything needed to reach space!)
# - LUNA (moon of Terra: sliced voxel interior + caves + Titanium 'ti')
# - IGNIS-I (inner volcanic planet: sliced voxel interior + caves + 'ignis_ore')
# - CRYO-IV (outer glacial planet: sliced voxel interior + caves + 'ice')
# - ASTRA-V (outermost enemy stronghold planet: sliced voxel interior + 6 Bastions + 'astra_shard')

const COLS: int = 900
const ROWS: int = 100
const CHUNKS: int = 30
const CHUNK_COLS: int = 30
const SUB_X: int = 4
const SUB_Y: int = 4

const EX_COLS: int = 360
const EX_ROWS: int = 48
const EX_CHUNKS: int = 12
const EX_CHUNK_COLS: int = 30
const EX_SUB_X: int = 2
const EX_SUB_Y: int = 2
const EX_DA: float = TAU / float(EX_COLS)

const R_CORE: float = 1100.0
const R_SURFACE: float = 3500.0
const R_ATMOS: float = 5900.0
const CELL_H: float = (R_SURFACE - R_CORE) / float(ROWS) # 24.0px
const DA: float = TAU / float(COLS)
const SPAWN_COL: int = 675 # North Pole (-PI/2)

const GRAV_SURF: float = 210.0
const ORIGIN_GM: float = GRAV_SURF * R_SURFACE * R_SURFACE
const SUN_RAD: float = 2200.0
const SUN_GM: float = 2.6e9
const TERRA_ORBIT_R: float = 30500.0

# Ore byte codes: 0=none, 1=fe, 2=cu, 3=si, 4=ti, 5=ignis_ore, 6=ice, 7=astra_shard
const ORE_CODE_TO_ID: Array[String] = ["", "fe", "cu", "si", "ti", "ignis_ore", "ice", "astra_shard"]

var mat: PackedByteArray
var ore: PackedByteArray
var cell_hp: PackedFloat32Array

var chunk_meshes: Array[MeshInstance2D] = []
var chunk_texs: Array[ImageTexture] = []
var dirty_chunks: Array[int] = []

# Real-time Polar Voxel Occupancy Textures for GPU Ray-Traced Sunlight & Cave Shadows!
var terra_occ_img: Image = null
var terra_occ_tex: ImageTexture = null
var extra_occ_img: Image = null
var extra_occ_tex: ImageTexture = null
const EXTRA_OCC_BAND: Dictionary = {"luna": 0, "ignis": 1, "cryo": 2, "astra": 3}

# Sliced Voxel Data & Chunk Meshes for LUNA, IGNIS-I, CRYO-IV, ASTRA-V!
var extra_vox: Dictionary = {} # body_id -> Dictionary
var dirty_extra: Array[Array] = [] # [body_id, chunk_idx]

var crystal_props: Array[Dictionary] = []
var drill_nodes: Array[Dictionary] = [] # includes "body_id", "local_pos"
var _last_bounce_ms: int = -2000

var factory: Node2D = null
var home_root: Node2D = null
var anim_t: float = 0.0

var bodies: Dictionary = {}
var body_order: Array[String] = ["sun", "ignis", "terra", "luna", "cryo", "astra"]
var asteroids: Array[Dictionary] = []

# Enemy Stronghold Bastions on ASTRA-V (must be destroyed by Swarm Fleet to liberate ASTRA-V!)
var astra_bastions: Array[Dictionary] = []

var sparks: Array[Dictionary] = []
var smokes: Array[Dictionary] = []
var popups: Array[Dictionary] = []

# Persistent mined voxel deltas for Browser Save/Load
var carved_terra: Dictionary = {} # "c,r" -> true
var carved_extra: Dictionary = {} # body_id -> {"c,r": true}

func _ready() -> void:
	z_index = 0
	process_physics_priority = -20
	if get_parent() is Node2D and get_parent().name == "HomeSystem":
		home_root = get_parent()
	_init_chunk_nodes()
	_init_occ_textures()
	_init_solar_system()
	generate_planet()
	_init_extra_planets()

func _init_occ_textures() -> void:
	terra_occ_img = Image.create(COLS, ROWS, false, Image.FORMAT_R8)
	terra_occ_tex = ImageTexture.create_from_image(terra_occ_img)
	extra_occ_img = Image.create(EX_COLS, EX_ROWS * 4, false, Image.FORMAT_R8)
	extra_occ_tex = ImageTexture.create_from_image(extra_occ_img)

func _sync_terra_occ_all() -> void:
	if not terra_occ_img: return
	var buf := PackedByteArray()
	buf.resize(COLS * ROWS)
	for i in range(COLS * ROWS):
		var m := int(mat[i])
		buf[i] = 255 if (m == 1 or m == 2 or m == 3) else 0
	terra_occ_img = Image.create_from_data(COLS, ROWS, false, Image.FORMAT_R8, buf)
	terra_occ_tex.update(terra_occ_img)

func _sync_terra_occ_chunk(ci: int) -> void:
	if not terra_occ_img: return
	var base_c := ci * CHUNK_COLS
	for r in range(ROWS):
		var row_off := r * COLS
		for lc in range(CHUNK_COLS):
			var c := base_c + lc
			var m := int(mat[row_off + c])
			var v := 1.0 if (m == 1 or m == 2 or m == 3) else 0.0
			terra_occ_img.set_pixel(c, r, Color(v, 0.0, 0.0, 1.0))
	terra_occ_tex.update(terra_occ_img)

func _sync_extra_occ_body(bid: String) -> void:
	if not extra_occ_img or not extra_vox.has(bid) or not EXTRA_OCC_BAND.has(bid): return
	var band: int = int(EXTRA_OCC_BAND[bid])
	var e_mat: PackedByteArray = extra_vox[bid]["mat"]
	var y_off := band * EX_ROWS
	for r in range(EX_ROWS):
		var row_off := r * EX_COLS
		for c in range(EX_COLS):
			var m := int(e_mat[row_off + c])
			var v := 1.0 if (m == 1 or m == 2 or m == 3) else 0.0
			extra_occ_img.set_pixel(c, y_off + r, Color(v, 0.0, 0.0, 1.0))
	extra_occ_tex.update(extra_occ_img)

func _sync_extra_occ_chunk(bid: String, ci: int) -> void:
	if not extra_occ_img or not extra_vox.has(bid) or not EXTRA_OCC_BAND.has(bid): return
	var band: int = int(EXTRA_OCC_BAND[bid])
	var e_mat: PackedByteArray = extra_vox[bid]["mat"]
	var y_off := band * EX_ROWS
	var base_c := ci * EX_CHUNK_COLS
	for r in range(EX_ROWS):
		var row_off := r * EX_COLS
		for lc in range(EX_CHUNK_COLS):
			var c := base_c + lc
			var m := int(e_mat[row_off + c])
			var v := 1.0 if (m == 1 or m == 2 or m == 3) else 0.0
			extra_occ_img.set_pixel(c, y_off + r, Color(v, 0.0, 0.0, 1.0))
	extra_occ_tex.update(extra_occ_img)

func _init_chunk_nodes() -> void:
	for ci in range(CHUNKS):
		var mi := MeshInstance2D.new()
		mi.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		mi.mesh = _build_ring_mesh(ci, CHUNK_COLS, DA, R_SURFACE, R_CORE)
		var img := Image.create(CHUNK_COLS * SUB_X, ROWS * SUB_Y, false, Image.FORMAT_RGBA8)
		var itex := ImageTexture.create_from_image(img)
		mi.texture = itex
		mi.z_index = 0
		add_child(mi)
		chunk_meshes.append(mi)
		chunk_texs.append(itex)

func _build_ring_mesh(ci: int, c_cols: int, step_da: float, r_surf: float, r_core: float) -> ArrayMesh:
	var a0 := float(ci * c_cols) * step_da
	var a1 := float((ci + 1) * c_cols) * step_da
	var seg_a := 8
	var seg_r := 6
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	for ia in range(seg_a):
		var u0 := float(ia) / float(seg_a)
		var u1 := float(ia + 1) / float(seg_a)
		var ang0 := lerpf(a0, a1, u0)
		var ang1 := lerpf(a0, a1, u1)
		var c0 := cos(ang0); var s0 := sin(ang0)
		var c1 := cos(ang1); var s1 := sin(ang1)
		for ir in range(seg_r):
			var v0 := float(ir) / float(seg_r)
			var v1 := float(ir + 1) / float(seg_r)
			var r0 := lerpf(r_surf, r_core, v0)
			var r1 := lerpf(r_surf, r_core, v1)
			var p00 := Vector2(c0 * r0, s0 * r0)
			var p10 := Vector2(c1 * r0, s1 * r0)
			var p11 := Vector2(c1 * r1, s1 * r1)
			var p01 := Vector2(c0 * r1, s0 * r1)
			verts.append(p00); uvs.append(Vector2(u0, v0))
			verts.append(p10); uvs.append(Vector2(u1, v0))
			verts.append(p11); uvs.append(Vector2(u1, v1))
			verts.append(p00); uvs.append(Vector2(u0, v0))
			verts.append(p11); uvs.append(Vector2(u1, v1))
			verts.append(p01); uvs.append(Vector2(u0, v1))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh

func _init_solar_system() -> void:
	bodies = {
		"sun": {
			"id": "sun", "name": "恒星ソラリス", "parent": "", "tex": "", "ore": "", "ore_code": 0,
			"orbit_r": 0.0, "ang": 0.0, "spd": 0.0,
			"rad": SUN_RAD, "r_core": 800.0, "atmos_r": 0.0, "soi_r": 1e9,
			"g_surf": 380.0, "gm": SUN_GM,
			"pos": Vector2.ZERO, "prev_pos": Vector2.ZERO, "delta_pos": Vector2.ZERO, "vel": Vector2.ZERO,
			"col": Color(1.0, 0.84, 0.34),
		},
		"ignis": {
			"id": "ignis", "name": "イグニス-I", "parent": "sun", "tex": "moon_ignis", "ore": "ignis_ore", "ore_code": 5,
			"orbit_r": 14000.0, "ang": PI * 0.28, "spd": 0.020,
			"rad": 2400.0, "r_core": 760.0, "atmos_r": 0.0, "soi_r": 4600.0,
			"g_surf": 195.0, "gm": 195.0 * 2400.0 * 2400.0,
			"pos": Vector2.ZERO, "prev_pos": Vector2.ZERO, "delta_pos": Vector2.ZERO, "vel": Vector2.ZERO,
			"col": Color(1.0, 0.48, 0.24),
		},
		"terra": {
			"id": "terra", "name": "テラ-I", "parent": "sun", "tex": "", "ore": "fe", "ore_code": 1,
			"orbit_r": TERRA_ORBIT_R, "ang": PI * 0.50, "spd": 0.013,
			"rad": R_SURFACE, "r_core": R_CORE, "atmos_r": R_ATMOS, "soi_r": 15200.0,
			"g_surf": GRAV_SURF, "gm": ORIGIN_GM,
			"pos": Vector2.ZERO, "prev_pos": Vector2.ZERO, "delta_pos": Vector2.ZERO, "vel": Vector2.ZERO,
			"col": Color(0.42, 0.82, 1.0),
		},
		"luna": {
			"id": "luna", "name": "衛星ルナ", "parent": "terra", "tex": "moon_luna", "ore": "ti", "ore_code": 4,
			"orbit_r": 11600.0, "ang": -PI * 0.64, "spd": 0.016,
			"rad": 1750.0, "r_core": 550.0, "atmos_r": 0.0, "soi_r": 3200.0,
			"g_surf": 175.0, "gm": 175.0 * 1750.0 * 1750.0,
			"pos": Vector2.ZERO, "prev_pos": Vector2.ZERO, "delta_pos": Vector2.ZERO, "vel": Vector2.ZERO,
			"col": Color(0.76, 0.84, 0.96),
		},
		"cryo": {
			"id": "cryo", "name": "クライオ-IV", "parent": "sun", "tex": "moon_cryo", "ore": "ice", "ore_code": 6,
			"orbit_r": 49500.0, "ang": PI * 0.68, "spd": 0.009,
			"rad": 2700.0, "r_core": 860.0, "atmos_r": 0.0, "soi_r": 5200.0,
			"g_surf": 190.0, "gm": 190.0 * 2700.0 * 2700.0,
			"pos": Vector2.ZERO, "prev_pos": Vector2.ZERO, "delta_pos": Vector2.ZERO, "vel": Vector2.ZERO,
			"col": Color(0.56, 0.92, 1.0),
		},
		"astra": {
			"id": "astra", "name": "アストラ-V", "parent": "sun", "tex": "planet_astra", "ore": "astra_shard", "ore_code": 7,
			"orbit_r": 64500.0, "ang": PI * 0.34, "spd": 0.006,
			"rad": 3100.0, "r_core": 980.0, "atmos_r": 0.0, "soi_r": 5800.0,
			"g_surf": 215.0, "gm": 215.0 * 3100.0 * 3100.0,
			"pos": Vector2.ZERO, "prev_pos": Vector2.ZERO, "delta_pos": Vector2.ZERO, "vel": Vector2.ZERO,
			"col": Color(0.78, 0.44, 1.0),
		},
	}
	step_celestials(0.0, true)

func step_celestials(delta: float, snap_init: bool = false) -> void:
	for bid in body_order:
		var b: Dictionary = bodies[bid]
		b["prev_pos"] = b["pos"]
		if bid == "sun":
			b["pos"] = Vector2.ZERO
			b["delta_pos"] = Vector2.ZERO
			b["vel"] = Vector2.ZERO
			continue
		var p_id := String(b["parent"])
		var parent_pos: Vector2 = bodies[p_id]["pos"] if bodies.has(p_id) else Vector2.ZERO
		var parent_vel: Vector2 = bodies[p_id]["vel"] if bodies.has(p_id) else Vector2.ZERO
		b["ang"] = wrapf(float(b["ang"]) + float(b["spd"]) * delta, -PI, PI)
		var a := float(b["ang"])
		var or_r := float(b["orbit_r"])
		var new_p := parent_pos + Vector2(cos(a), sin(a)) * or_r
		b["pos"] = new_p
		if snap_init:
			b["prev_pos"] = new_p
			b["delta_pos"] = Vector2.ZERO
		else:
			b["delta_pos"] = new_p - Vector2(b["prev_pos"])
		b["vel"] = parent_vel + Vector2(-sin(a), cos(a)) * (or_r * float(b["spd"]))

	if home_root:
		home_root.position = bodies["terra"]["pos"]

	var terra_p: Vector2 = bodies["terra"]["pos"]
	for bid in extra_vox.keys():
		var ev: Dictionary = extra_vox[bid]
		var rnode: Node2D = ev["root"]
		rnode.position = Vector2(bodies[bid]["pos"]) - terra_p

	for dn in drill_nodes:
		var bid_d := String(dn.get("body_id", "terra"))
		var b_off := Vector2(bodies[bid_d]["pos"]) - terra_p
		dn["pos"] = b_off + Vector2(dn["local_pos"])

	for ast in asteroids:
		ast["ang"] = wrapf(float(ast["ang"]) + float(ast["spd"]) * delta, -PI, PI)
		ast["rot"] = float(ast["rot"]) + 0.2 * delta
		var a := float(ast["ang"])
		var base_p := terra_p if String(ast.get("parent", "terra")) == "terra" else Vector2.ZERO
		ast["pos"] = base_p + Vector2(cos(a), sin(a)) * float(ast["dist"])

func generate_planet() -> void:
	var n := COLS * ROWS
	mat.resize(n)
	ore.resize(n)
	cell_hp.resize(n)
	crystal_props.clear()
	drill_nodes.clear()
	carved_terra.clear()
	sparks.clear(); smokes.clear(); popups.clear()

	var rng := RandomNumberGenerator.new()
	rng.seed = 20261121

	var warp_x := FastNoiseLite.new()
	warp_x.seed = 20261122
	warp_x.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	warp_x.fractal_type = FastNoiseLite.FRACTAL_FBM
	warp_x.fractal_octaves = 3
	warp_x.frequency = 0.0014

	var warp_y := FastNoiseLite.new()
	warp_y.seed = 20261199
	warp_y.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	warp_y.fractal_type = FastNoiseLite.FRACTAL_FBM
	warp_y.fractal_octaves = 3
	warp_y.frequency = 0.0014

	var cave_n := FastNoiseLite.new()
	cave_n.seed = 20261201
	cave_n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	cave_n.fractal_type = FastNoiseLite.FRACTAL_FBM
	cave_n.fractal_octaves = 4
	cave_n.fractal_lacunarity = 2.05
	cave_n.fractal_gain = 0.52
	cave_n.frequency = 0.0018

	var tunnel_n := FastNoiseLite.new()
	tunnel_n.seed = 20261277
	tunnel_n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	tunnel_n.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	tunnel_n.fractal_octaves = 3
	tunnel_n.frequency = 0.0011

	var hill_n := FastNoiseLite.new()
	hill_n.seed = 20261303
	hill_n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	hill_n.fractal_type = FastNoiseLite.FRACTAL_FBM
	hill_n.fractal_octaves = 3
	hill_n.frequency = 0.0009

	# 1. Carve TERRA-I terrain & domain-warped organic FastNoiseLite caverns
	for c in range(COLS):
		var a := float(c) * DA
		var ca := cos(a); var sa := sin(a)
		var hill := int(round(hill_n.get_noise_2d(ca * R_SURFACE, sa * R_SURFACE) * 3.8))
		var d_spawn := absi(wrap_col(c - SPAWN_COL + COLS / 2) - COLS / 2)
		if d_spawn < 26:
			hill = 0
		var surf_row := clampi(ROWS - 3 + hill, ROWS - 7, ROWS - 1)
		var rego_depth := 8 + int(round(hill_n.get_noise_2d(ca * 2400.0 + 300.0, sa * 2400.0 - 200.0) * 3.5))

		for r in range(ROWS):
			var idx := r * COLS + c
			ore[idx] = 0
			if r > surf_row:
				mat[idx] = 0; cell_hp[idx] = 0.0; continue
			if r < 6:
				mat[idx] = 3; cell_hp[idx] = 999.0; continue

			var rad := R_CORE + (float(r) + 0.5) * CELL_H
			var wx := ca * rad; var wy := sa * rad
			var dx := warp_x.get_noise_2d(wx, wy) * 195.0
			var dy := warp_y.get_noise_2d(wx, wy) * 195.0
			var cn := cave_n.get_noise_2d(wx + dx, wy + dy)
			var tn := tunnel_n.get_noise_2d(wx - dy * 0.55, wy + dx * 0.55)

			var roof_taper := clampf(float(surf_row - 6 - r) / 8.0, 0.0, 1.0)
			var core_taper := clampf(float(r - 7) / 6.0, 0.0, 1.0)
			var chamber_thresh := 0.24 + (1.0 - roof_taper) * 0.38
			if d_spawn < 24 and r >= 64 and r <= surf_row - 8:
				chamber_thresh -= 0.10
			var is_cave := (r >= 8 and r <= surf_row - 6) and (
				cn > chamber_thresh or (tn > 0.78 and roof_taper > 0.45 and core_taper > 0.45)
			)

			if is_cave:
				mat[idx] = 4; cell_hp[idx] = 0.0
			elif r >= surf_row - rego_depth:
				mat[idx] = 1; cell_hp[idx] = 8.0
			else:
				mat[idx] = 2; cell_hp[idx] = 14.0

	# 2. Paint ONLY fe (1), cu (2), si (3) on TERRA-I! (NO Titanium on starter planet -> motivates spaceflight to LUNA!)
	for dc in [-24, -18, -13, -8, -4, 5, 10, 15, 21, 27]:
		var wc := wrap_col(SPAWN_COL + int(dc))
		var sr := get_surface_row(wc)
		var oid := 2 if (int(dc) in [-18, -8, 5, 15, 27]) else 1
		_paint_vein(wc, sr - 1, 2, 2, oid)
	_paint_vein(wrap_col(SPAWN_COL - 6), 76, 3, 2, 3)
	_paint_vein(wrap_col(SPAWN_COL + 8), 75, 3, 2, 3)
	_paint_vein(wrap_col(SPAWN_COL - 16), 72, 3, 2, 1)
	_paint_vein(wrap_col(SPAWN_COL + 18), 71, 3, 2, 2)
	_paint_vein(wrap_col(SPAWN_COL), 52, 4, 3, 3)

	for _i in range(280):
		_paint_vein(rng.randi_range(0, COLS - 1), rng.randi_range(50, ROWS - 4), rng.randi_range(2, 4), rng.randi_range(1, 3), 1)
	for _i in range(240):
		_paint_vein(rng.randi_range(0, COLS - 1), rng.randi_range(40, ROWS - 4), rng.randi_range(2, 3), rng.randi_range(1, 3), 2)
	for _i in range(220):
		_paint_vein(rng.randi_range(0, COLS - 1), rng.randi_range(14, 82), rng.randi_range(2, 4), rng.randi_range(1, 3), 3)

	# 3. Crystal spires on Terra (fe, cu, si ONLY!)
	for c in range(0, COLS, 4):
		var d_sp := absi(wrap_col(c - SPAWN_COL + COLS / 2) - COLS / 2)
		for r in range(12, ROWS - 2):
			var idx := r * COLS + c
			if mat[idx] == 4 and r > 0 and mat[(r - 1) * COLS + c] in [1, 2]:
				var o := int(ore[(r - 1) * COLS + c])
				if o in [1, 2, 3] or (d_sp < 30 and rng.randf() < 0.52):
					var oid: int = o if (o in [1, 2, 3]) else int([3, 3, 1, 2][rng.randi() % 4])
					var p := cell_world_pos(c, r)
					crystal_props.append({"col": c, "row": r, "pos": p, "rot": col_angle(c) + PI * 0.5, "ore": oid, "sc": rng.randf_range(0.85, 1.45)})
	for dc in [-22, -16, -11, -7, -3, 4, 9, 14, 19, 25]:
		var wc := wrap_col(SPAWN_COL + int(dc))
		var sr := get_surface_row(wc)
		var oid := 2 if (int(dc) in [-16, -7, 4, 14, 25]) else 1
		crystal_props.append({"col": wc, "row": sr + 1, "pos": cell_world_pos(wc, sr + 1), "rot": col_angle(wc) + PI * 0.5, "ore": oid, "sc": 0.92})

	# 3b. Bedrock Drill-Only Ore Deposits on TERRA-I (fe, cu, si ONLY!)
	var next_dn_id := 1
	var starter_surf := [[-14, "fe"], [12, "fe"], [-23, "cu"], [23, "cu"]]
	for st in starter_surf:
		var wc := wrap_col(SPAWN_COL + int(st[0]))
		var sr := get_surface_row(wc) + 1
		var pose := get_pose_at(wc, sr)
		drill_nodes.append({
			"id": next_dn_id, "body_id": "terra", "col": wc, "row": sr,
			"local_pos": pose["pos"], "pos": pose["pos"], "normal": pose["normal"], "rot": float(pose["rot"]),
			"ore": String(st[1]),
		})
		next_dn_id += 1
	var starter_cave := [[-11, 74, "si"], [14, 75, "si"], [2, 69, "fe"], [-2, 46, "si"]]
	for scv in starter_cave:
		var wc := wrap_col(SPAWN_COL + int(scv[0]))
		var fr := int(scv[1])
		while fr > 8 and not is_solid(wc, fr - 1): fr -= 1
		while fr < ROWS - 6 and is_solid(wc, fr): fr += 1
		var pose := get_pose_at(wc, fr)
		drill_nodes.append({
			"id": next_dn_id, "body_id": "terra", "col": wc, "row": fr,
			"local_pos": pose["pos"], "pos": pose["pos"], "normal": pose["normal"], "rot": float(pose["rot"]),
			"ore": String(scv[2]),
		})
		next_dn_id += 1
	var g_ores: Array[String] = ["fe", "cu", "si"]
	for i in range(30):
		var c := wrap_col(SPAWN_COL + 42 + i * 28)
		var o_id: String = g_ores[i % g_ores.size()]
		var r := get_surface_row(c) + 1
		if o_id == "si":
			var found_r := -1
			for rr in range(50, 76):
				if rr > 8 and rr < ROWS - 8 and mat[rr * COLS + c] == 4 and is_solid(c, rr - 1):
					found_r = rr; break
			if found_r > 0: r = found_r
		var pose := get_pose_at(c, r)
		drill_nodes.append({
			"id": next_dn_id, "body_id": "terra", "col": c, "row": r,
			"local_pos": pose["pos"], "pos": pose["pos"], "normal": pose["normal"], "rot": float(pose["rot"]),
			"ore": o_id,
		})
		next_dn_id += 1

	# 4. Bake spawn chunks immediately + upload full GPU occupancy texture for ray-traced sunlight!
	_sync_terra_occ_all()
	dirty_chunks.clear()
	var spawn_ci := SPAWN_COL / CHUNK_COLS
	for dci in range(-2, 3):
		_bake_chunk((spawn_ci + dci + CHUNKS) % CHUNKS)
	for ci in range(CHUNKS):
		var dist_c := mini(absi(ci - spawn_ci), CHUNKS - absi(ci - spawn_ci))
		if dist_c > 2:
			dirty_chunks.append(ci)

	# 5. Asteroids (Terra orbit: fe, cu, si; Deep space belt: ti, ignis_ore, ice)
	asteroids.clear()
	var t_cyc: Array[String] = ["si", "cu", "fe"]
	var terra_p: Vector2 = bodies["terra"]["pos"]
	for i in range(80):
		var ang := (-PI * 0.5 + float(i - 8) * 0.055) if i < 14 else rng.randf_range(0.0, TAU)
		var dist := rng.randf_range(R_ATMOS + 260.0, R_ATMOS + 1100.0) if i < 14 else rng.randf_range(R_ATMOS + 450.0, 9600.0)
		var ot: String = t_cyc[i % t_cyc.size()]
		asteroids.append({
			"parent": "terra", "pos": terra_p + Vector2(cos(ang), sin(ang)) * dist,
			"ore": ot, "hp": 60.0, "rad": rng.randf_range(28.0, 46.0),
			"ang": ang, "dist": dist, "spd": rng.randf_range(0.003, 0.007) * (1.0 if i % 2 == 0 else -1.0),
			"rot": rng.randf_range(0.0, TAU),
		})

func _init_extra_planets() -> void:
	# Generate 360-degree sliced voxel cross-sections + organic caves + drill nodes for LUNA, IGNIS, CRYO, ASTRA!
	for old_v in extra_vox.values():
		if is_instance_valid(old_v.get("root", null)):
			old_v["root"].queue_free()
	extra_vox.clear()
	dirty_extra.clear()
	carved_extra.clear()

	var next_dn_id := drill_nodes.size() + 1
	var terra_p := Vector2(bodies["terra"]["pos"])
	var seed_base := 20262000

	for bid in ["luna", "ignis", "cryo", "astra"]:
		seed_base += 101
		var b: Dictionary = bodies[bid]
		var r_surf := float(b["rad"])
		var r_core := float(b["r_core"])
		var ch_h := (r_surf - r_core) / float(EX_ROWS)
		var o_code := int(b["ore_code"])
		var o_str := String(b["ore"])

		var rnode := Node2D.new()
		rnode.name = "Vox_" + bid
		rnode.position = Vector2(b["pos"]) - terra_p
		add_child(rnode)

		var meshes: Array[MeshInstance2D] = []
		var texs: Array[ImageTexture] = []
		for ci in range(EX_CHUNKS):
			var mi := MeshInstance2D.new()
			mi.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			mi.mesh = _build_ring_mesh(ci, EX_CHUNK_COLS, EX_DA, r_surf, r_core)
			var img := Image.create(EX_CHUNK_COLS * EX_SUB_X, EX_ROWS * EX_SUB_Y, false, Image.FORMAT_RGBA8)
			var itex := ImageTexture.create_from_image(img)
			mi.texture = itex
			rnode.add_child(mi)
			meshes.append(mi)
			texs.append(itex)

		var e_mat := PackedByteArray(); e_mat.resize(EX_COLS * EX_ROWS)
		var e_ore := PackedByteArray(); e_ore.resize(EX_COLS * EX_ROWS)
		var e_hp := PackedFloat32Array(); e_hp.resize(EX_COLS * EX_ROWS)

		var cn_noise := FastNoiseLite.new()
		cn_noise.seed = seed_base
		cn_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		cn_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		cn_noise.fractal_octaves = 3
		cn_noise.frequency = 0.0026

		var wx_noise := FastNoiseLite.new()
		wx_noise.seed = seed_base + 37
		wx_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		wx_noise.frequency = 0.0018

		for c in range(EX_COLS):
			var a := float(c) * EX_DA
			var ca := cos(a); var sa := sin(a)
			var hill := int(round(wx_noise.get_noise_2d(ca * r_surf, sa * r_surf) * 2.2))
			var s_row := clampi(EX_ROWS - 2 + hill, EX_ROWS - 5, EX_ROWS - 1)
			for r in range(EX_ROWS):
				var idx := r * EX_COLS + c
				e_ore[idx] = 0
				if r > s_row:
					e_mat[idx] = 0; e_hp[idx] = 0.0; continue
				if r < 4:
					e_mat[idx] = 3; e_hp[idx] = 999.0; continue
				var rad := r_core + (float(r) + 0.5) * ch_h
				var wx := ca * rad; var wy := sa * rad
				var w_off := wx_noise.get_noise_2d(wx, wy) * 140.0
				var cv := cn_noise.get_noise_2d(wx + w_off, wy - w_off)
				var roof_f := clampf(float(s_row - 3 - r) / 5.0, 0.0, 1.0)
				if r >= 6 and r <= s_row - 3 and cv > (0.20 + (1.0 - roof_f) * 0.36):
					e_mat[idx] = 4; e_hp[idx] = 0.0
				elif r >= s_row - 5:
					e_mat[idx] = 1; e_hp[idx] = 9.0
				else:
					e_mat[idx] = 2; e_hp[idx] = 15.0
				# Rich planet-specific ore veins + secondary iron/silicon!
				if e_mat[idx] in [1, 2]:
					var vn := cn_noise.get_noise_2d(wx * 2.3 + 500.0, wy * 2.3 - 500.0)
					if vn > 0.32 or (r == s_row and (c % 18) < 3):
						e_ore[idx] = o_code
					elif vn < -0.44:
						e_ore[idx] = 1 # Fe backup

		extra_vox[bid] = {
			"id": bid, "root": rnode, "r_surf": r_surf, "r_core": r_core, "cell_h": ch_h,
			"mat": e_mat, "ore": e_ore, "hp": e_hp, "meshes": meshes, "texs": texs,
			"ore_code": o_code, "ore_id": o_str,
		}

		# Spawn 10 Bedrock Drill-Only Ore Deposits on each planet (surface + underground caves!)
		for di in range(10):
			var dc := (di * (EX_COLS / 10) + 12) % EX_COLS
			var dr := EX_ROWS - 1
			while dr > 6 and int(e_mat[(dr - 1) * EX_COLS + dc]) in [0, 4]:
				dr -= 1
			var a := (float(dc) + 0.5) * EX_DA
			var rad := r_core + float(dr) * ch_h
			var n_vec := Vector2(cos(a), sin(a))
			var lpos := n_vec * rad
			drill_nodes.append({
				"id": next_dn_id, "body_id": bid, "col": dc, "row": dr,
				"local_pos": lpos, "pos": (Vector2(b["pos"]) - terra_p) + lpos,
				"normal": n_vec, "rot": a + PI * 0.5,
				"ore": o_str if (di % 4 != 3) else "fe",
			})
			next_dn_id += 1

		# Upload GPU occupancy band for ray-traced sunlight & shadows on this planet
		_sync_extra_occ_body(bid)

		# Bake first 3 chunks immediately, queue rest lazily
		for ci in range(EX_CHUNKS):
			if ci < 3:
				_bake_extra_chunk(bid, ci)
			else:
				dirty_extra.append([bid, ci])

	# Initialize 8 Enemy Von Neumann Surface Facilities on ASTRA-V (4 Enemy 3D Printer Factories + 4 Enemy Mass Drivers)!
	astra_bastions.clear()
	var astra_r := float(bodies["astra"]["rad"])
	for bi in range(8):
		var ba := float(bi) * (TAU / 8.0) - PI * 0.5
		var bn := Vector2(cos(ba), sin(ba))
		var is_drv := (bi % 2 == 1)
		astra_bastions.append({
			"idx": bi, "ang": ba, "normal": bn,
			"kind": "enemy_driver" if is_drv else "enemy_printer",
			"name": "敵マスドライバー" if is_drv else "敵3Dプリンタ工場",
			"tex": "mass_driver" if is_drv else "gantry_printer",
			"local_pos": bn * (astra_r + 6.0),
			"hp": 1400.0, "max_hp": 1400.0, "alive": true, "fire_t": float(bi) * 0.45,
		})
	State.astra_bastions_left = 8
	State.enemy_printers_left = 4
	State.enemy_drivers_left = 4
	State.enemy_launch_slow_t = 0.0
	State.astra_liberated = false

func _bake_extra_chunk(bid: String, ci: int) -> void:
	if not extra_vox.has(bid): return
	var ev: Dictionary = extra_vox[bid]
	var w := EX_CHUNK_COLS * EX_SUB_X
	var h := EX_ROWS * EX_SUB_Y
	var data := PackedByteArray(); data.resize(w * h * 4)
	var base_c := ci * EX_CHUNK_COLS
	var e_mat: PackedByteArray = ev["mat"]
	var e_ore: PackedByteArray = ev["ore"]

	# Planet-specific crust / deep rock / core / ore color themes!
	var c_crust := Vector3i(154, 164, 186)
	var c_deep  := Vector3i(28, 34, 48)
	var c_core  := Vector3i(120, 224, 255)
	var c_cave  := Vector3i(14, 18, 28)
	match bid:
		"ignis":
			c_crust = Vector3i(164, 58, 34); c_deep = Vector3i(52, 20, 16); c_core = Vector3i(255, 168, 38); c_cave = Vector3i(26, 10, 10)
		"cryo":
			c_crust = Vector3i(118, 206, 242); c_deep = Vector3i(24, 54, 86); c_core = Vector3i(164, 246, 255); c_cave = Vector3i(10, 24, 42)
		"astra":
			c_crust = Vector3i(104, 62, 152); c_deep = Vector3i(34, 20, 56); c_core = Vector3i(238, 68, 255); c_cave = Vector3i(16, 10, 30)

	for r in range(EX_ROWS):
		var y_base := (EX_ROWS - 1 - r) * EX_SUB_Y
		var core_glow := clampf(float(10 - r) / 10.0, 0.0, 1.0)
		for lc in range(EX_CHUNK_COLS):
			var c := base_c + lc
			var idx := r * EX_COLS + c
			var m := int(e_mat[idx])
			if m == 0: continue
			var o := int(e_ore[idx])
			var solid := (m in [1, 2, 3])
			var open_bot := (r > 0) and (int(e_mat[(r - 1) * EX_COLS + c]) in [0, 4])
			var open_l := int(e_mat[r * EX_COLS + ((c - 1 + EX_COLS) % EX_COLS)]) in [0, 4]

			for sy in range(EX_SUB_Y):
				var py := y_base + sy
				for sx in range(EX_SUB_X):
					var px := lc * EX_SUB_X + sx
					var hv := ((c * EX_SUB_X + sx) * 374761393 + (r * EX_SUB_Y + sy) * 668265263) & 0xFFFF
					var n := float(hv % 100) / 100.0
					var rr_c := 0; var gg_c := 0; var bb_c := 0
					if m == 4:
						rr_c = c_cave.x + int(n * 8.0 + core_glow * float(c_core.x) * 0.25)
						gg_c = c_cave.y + int(n * 8.0 + core_glow * float(c_core.y) * 0.22)
						bb_c = c_cave.z + int(n * 8.0 + core_glow * float(c_core.z) * 0.22)
					elif m == 3:
						rr_c = clampi(c_core.x + int(n * 35.0), 0, 255)
						gg_c = clampi(c_core.y + int(n * 35.0), 0, 255)
						bb_c = clampi(c_core.z + int(n * 35.0), 0, 255)
					elif m == 1:
						rr_c = clampi(c_crust.x + int(n * 28.0), 0, 255)
						gg_c = clampi(c_crust.y + int(n * 28.0), 0, 255)
						bb_c = clampi(c_crust.z + int(n * 28.0), 0, 255)
					else:
						rr_c = clampi(c_deep.x + int(n * 22.0 + core_glow * 42.0), 0, 255)
						gg_c = clampi(c_deep.y + int(n * 22.0 + core_glow * 24.0), 0, 255)
						bb_c = clampi(c_deep.z + int(n * 22.0 + core_glow * 32.0), 0, 255)
					if solid and m != 3 and ((open_bot and sy == EX_SUB_Y - 1) or (open_l and sx == 0)):
						rr_c = int(rr_c * 0.35); gg_c = int(gg_c * 0.35); bb_c = int(bb_c * 0.38)
					if o > 0 and n > 0.58:
						var oc := ore_col(ORE_CODE_TO_ID[o])
						rr_c = int(rr_c * 0.38 + oc.r * 255.0 * 0.62)
						gg_c = int(gg_c * 0.38 + oc.g * 255.0 * 0.62)
						bb_c = int(bb_c * 0.38 + oc.b * 255.0 * 0.62)
					var off := (py * w + px) * 4
					data[off] = rr_c; data[off + 1] = gg_c; data[off + 2] = bb_c; data[off + 3] = 255

	var img := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)
	var tex_arr: Array = ev["texs"]
	tex_arr[ci].update(img)
	_sync_extra_occ_chunk(bid, ci)

func _paint_vein(c0: int, r0: int, rc: int, rr: int, oid: int) -> void:
	for dr in range(-rr, rr + 1):
		var r := r0 + dr
		if r < 7 or r >= ROWS: continue
		for dc in range(-rc, rc + 1):
			if absf(float(dc)) / maxf(1.0, float(rc)) + absf(float(dr)) / maxf(1.0, float(rr)) > 1.4:
				continue
			var wc := wrap_col(c0 + dc)
			var idx := r * COLS + wc
			if mat[idx] in [1, 2]:
				ore[idx] = oid

func _bake_chunk(ci: int) -> void:
	var w := CHUNK_COLS * SUB_X
	var h := ROWS * SUB_Y
	var data := PackedByteArray()
	data.resize(w * h * 4)
	var base_c := ci * CHUNK_COLS

	for r in range(ROWS):
		var y_base := (ROWS - 1 - r) * SUB_Y
		var lava_glow := clampf(float(16 - r) / 16.0, 0.0, 1.0)
		for lc in range(CHUNK_COLS):
			var c := base_c + lc
			var idx := r * COLS + c
			var m := int(mat[idx])
			if m == 0: continue
			var o := int(ore[idx])
			var solid := (m == 1 or m == 2 or m == 3)
			var open_top := (r + 1 >= ROWS) or (int(mat[(r + 1) * COLS + c]) in [0, 4])
			var open_bot := (r > 0) and (int(mat[(r - 1) * COLS + c]) in [0, 4])
			var open_l := int(mat[r * COLS + wrap_col(c - 1)]) in [0, 4]
			var open_r := int(mat[r * COLS + wrap_col(c + 1)]) in [0, 4]

			for sy in range(SUB_Y):
				var py := y_base + sy
				for sx in range(SUB_X):
					var px := lc * SUB_X + sx
					var h_v := ((c * SUB_X + sx) * 374761393 + (r * SUB_Y + sy) * 668265263) & 0xFFFF
					var n := float(h_v % 100) / 100.0
					var rr_c := 0; var gg_c := 0; var bb_c := 0; var aa_c := 255

					if m == 4:
						var base_b := 12 + int(n * 9.0)
						rr_c = base_b + int(lava_glow * 74.0)
						gg_c = base_b + 3 + int(lava_glow * 24.0)
						bb_c = base_b + 10
					elif m == 3:
						if n > 0.72: rr_c = 255; gg_c = 242; bb_c = 148
						elif n > 0.36: rr_c = 255; gg_c = 152; bb_c = 28
						else: rr_c = 224; gg_c = 62; bb_c = 14
					elif m == 1:
						var strata := 12 if ((r + int(n * 2.0)) % 3 == 0) else 0
						rr_c = 166 + int(n * 38.0) - strata
						gg_c = 132 + int(n * 32.0) - strata
						bb_c = 86 + int(n * 22.0) - strata
						if open_top and sy == 0:
							rr_c = clampi(rr_c + 34, 0, 255)
							gg_c = clampi(gg_c + 30, 0, 255)
							bb_c = clampi(bb_c + 18, 0, 255)
					else:
						var rock := 24 + int(n * 24.0)
						rr_c = rock + int(lava_glow * 64.0)
						gg_c = rock + 5 + int(lava_glow * 22.0)
						bb_c = rock + 16

					if solid and m != 3:
						if (open_bot and sy == SUB_Y - 1) or (open_l and sx == 0) or (open_r and sx == SUB_X - 1):
							rr_c = int(rr_c * 0.32); gg_c = int(gg_c * 0.32); bb_c = int(bb_c * 0.36)
						elif open_top and sy == 0 and m == 2:
							rr_c = clampi(rr_c + 22, 0, 255); gg_c = clampi(gg_c + 26, 0, 255); bb_c = clampi(bb_c + 34, 0, 255)

					if o > 0 and n > 0.80:
						var or_r := 0; var or_g := 0; var or_b := 0
						match o:
							1: or_r = 228; or_g = 86;  or_b = 70
							2: or_r = 242; or_g = 172; or_b = 64
							3: or_r = 76;  or_g = 216; or_b = 252
							4: or_r = 176; or_g = 112; or_b = 242
						rr_c = int(rr_c * 0.52 + or_r * 0.48)
						gg_c = int(gg_c * 0.52 + or_g * 0.48)
						bb_c = int(bb_c * 0.52 + or_b * 0.48)

					var off := (py * w + px) * 4
					data[off] = rr_c; data[off + 1] = gg_c; data[off + 2] = bb_c; data[off + 3] = aa_c

	var img := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)
	chunk_texs[ci].update(img)
	_sync_terra_occ_chunk(ci)

func _physics_process(delta: float) -> void:
	step_celestials(delta)

func _process(delta: float) -> void:
	anim_t += delta
	if not dirty_chunks.is_empty():
		var ci := int(dirty_chunks.pop_front())
		_bake_chunk(ci)
	elif not dirty_extra.is_empty():
		var pair: Array = dirty_extra.pop_front()
		_bake_extra_chunk(String(pair[0]), int(pair[1]))

	for i in range(sparks.size() - 1, -1, -1):
		sparks[i]["pos"] += sparks[i]["vel"] * delta
		var lp: Vector2 = sparks[i]["pos"]
		if lp.length() > 10.0:
			sparks[i]["vel"] += (-lp.normalized() * GRAV_SURF) * delta * 0.22
		sparks[i]["life"] -= delta
		if float(sparks[i]["life"]) <= 0.0: sparks.remove_at(i)

	for i in range(smokes.size() - 1, -1, -1):
		smokes[i]["pos"] += smokes[i]["vel"] * delta
		smokes[i]["rad"] += 15.0 * delta
		smokes[i]["life"] -= delta
		if float(smokes[i]["life"]) <= 0.0: smokes.remove_at(i)

	for i in range(popups.size() - 1, -1, -1):
		popups[i]["pos"] += popups[i]["vel"] * delta
		popups[i]["life"] -= delta
		if float(popups[i]["life"]) <= 0.0: popups.remove_at(i)

	queue_redraw()

# ------------------------------------------------------------------------------
# MULTI-PLANET VOXEL QUERIES & COORDINATES
# ------------------------------------------------------------------------------
func get_body(bid: String) -> Dictionary:
	return bodies.get(bid, bodies["terra"])

func get_terra_pos() -> Vector2:
	return Vector2(bodies["terra"]["pos"])

func to_terra_local(world_pos: Vector2) -> Vector2:
	return world_pos - Vector2(bodies["terra"]["pos"])

func to_world_pos(local_pos: Vector2) -> Vector2:
	return Vector2(bodies["terra"]["pos"]) + local_pos

func get_sun_dir() -> Vector2:
	var tp := Vector2(bodies["terra"]["pos"])
	return (-tp).normalized() if tp.length() > 1.0 else Vector2.UP

func get_sunlight_local(local_pos: Vector2) -> float:
	var sd := get_sun_dir()
	var up := local_pos.normalized() if local_pos.length() > 1.0 else Vector2.UP
	return clampf((up.dot(sd) + 0.08) / 0.65, 0.0, 1.0)

func get_sunlight(pos_or_local: Vector2) -> float:
	return get_sunlight_local(pos_or_local)

func get_sunlight_world(world_pos: Vector2) -> float:
	var b := get_dominant_body(world_pos)
	var bid := String(b["id"])
	if bid == "sun":
		return 1.0
	var bp: Vector2 = b["pos"]
	var sd := (-bp).normalized() if bp.length() > 1.0 else Vector2.UP
	var rel := world_pos - bp
	if rel.length() <= float(b["rad"]) + 380.0:
		return clampf((rel.normalized().dot(sd) + 0.08) / 0.65, 0.0, 1.0)
	var proj := rel.dot(sd)
	if proj < 0.0:
		var perp := (rel - sd * proj).length()
		if perp < float(b["rad"]) * 0.96:
			return 0.0
	return 1.0

func get_dominant_body(world_pos: Vector2) -> Dictionary:
	var luna: Dictionary = bodies["luna"]
	if world_pos.distance_to(Vector2(luna["pos"])) <= float(luna["soi_r"]):
		return luna
	for bid in ["terra", "ignis", "cryo", "astra"]:
		var b: Dictionary = bodies[bid]
		if world_pos.distance_to(Vector2(b["pos"])) <= float(b["soi_r"]):
			return b
	return bodies["sun"]

func compute_gravity_for(world_pos: Vector2, body_id: String) -> Vector2:
	var b: Dictionary = bodies.get(body_id, bodies["terra"])
	var rel := world_pos - Vector2(b["pos"])
	var r := rel.length()
	if r < 20.0:
		return Vector2.ZERO
	var rad := float(b["rad"])
	var g_mag := (float(b["g_surf"]) * (r / rad)) if (r < rad) else (float(b["gm"]) / (r * r))
	return (-rel / r) * g_mag

func compute_gravity(world_pos: Vector2) -> Vector2:
	var b := get_dominant_body(world_pos)
	return compute_gravity_for(world_pos, String(b["id"]))

func get_atmos_density_world(world_pos: Vector2) -> float:
	var tp := Vector2(bodies["terra"]["pos"])
	var r := world_pos.distance_to(tp)
	if r >= R_ATMOS: return 0.0
	return clampf(1.0 - maxf(0.0, r - R_SURFACE) / (R_ATMOS - R_SURFACE), 0.0, 1.0)

func get_atmos_density(pos: Vector2) -> float:
	return get_atmos_density_world(pos)

# Extra planet voxel queries (for LUNA, IGNIS-I, CRYO-IV, ASTRA-V!)
static func wrap_ex_col(c: int) -> int:
	return ((c % EX_COLS) + EX_COLS) % EX_COLS

func extra_local_to_cell(bid: String, rel_pos: Vector2) -> Vector2i:
	if not extra_vox.has(bid): return Vector2i.ZERO
	var ev: Dictionary = extra_vox[bid]
	var a := atan2(rel_pos.y, rel_pos.x)
	if a < 0.0: a += TAU
	var c := wrap_ex_col(int(floor(a / EX_DA)))
	var r := int(floor((rel_pos.length() - float(ev["r_core"])) / float(ev["cell_h"])))
	return Vector2i(c, r)

func is_extra_solid(bid: String, c: int, r: int) -> bool:
	if not extra_vox.has(bid): return false
	if r < 4: return true
	if r >= EX_ROWS: return false
	var e_mat: PackedByteArray = extra_vox[bid]["mat"]
	var m := int(e_mat[r * EX_COLS + wrap_ex_col(c)])
	return m in [1, 2, 3]

func get_extra_surface_row(bid: String, c: int) -> int:
	if not extra_vox.has(bid): return EX_ROWS - 2
	var e_mat: PackedByteArray = extra_vox[bid]["mat"]
	var wc := wrap_ex_col(c)
	for r in range(EX_ROWS - 1, 3, -1):
		if int(e_mat[r * EX_COLS + wc]) in [1, 2]:
			return r
	return 4

func get_body_pose_at(bid: String, c: int, r: int) -> Dictionary:
	if bid == "terra" or not extra_vox.has(bid):
		var p := get_pose_at(c, r)
		p["body_id"] = "terra"
		p["local_pos"] = p["pos"]
		return p
	var ev: Dictionary = extra_vox[bid]
	var wc := wrap_ex_col(c)
	var a := (float(wc) + 0.5) * EX_DA
	var rad := float(ev["r_core"]) + float(r) * float(ev["cell_h"])
	var n := Vector2(cos(a), sin(a))
	var lpos := n * rad
	var b_off := Vector2(bodies[bid]["pos"]) - Vector2(bodies["terra"]["pos"])
	return {
		"body_id": bid, "col": wc, "row": r, "ang": a, "r": rad,
		"local_pos": lpos, "pos": b_off + lpos, "normal": n, "rot": a + PI * 0.5
	}

func check_celestial_hit(world_pos: Vector2, rad: float = 18.0) -> Dictionary:
	# Only SUN is a simple sphere now; LUNA/IGNIS/CRYO/ASTRA use real sliced voxel collision!
	var b: Dictionary = bodies["sun"]
	var bp: Vector2 = b["pos"]
	var lim := float(b["rad"]) + rad
	var diff := world_pos - bp
	var d := diff.length()
	if d < lim and d > 0.1:
		return {"hit": true, "body_id": "sun", "normal": diff / d, "push": bp + (diff / d) * lim, "body": b}
	return {"hit": false}

func sync_astra_facility_counts() -> void:
	var p_cnt := 0
	var d_cnt := 0
	for bst in astra_bastions:
		if not bool(bst["alive"]): continue
		if String(bst.get("kind", "enemy_printer")) == "enemy_driver":
			d_cnt += 1
		else:
			p_cnt += 1
	State.enemy_printers_left = p_cnt
	State.enemy_drivers_left = d_cnt
	State.astra_bastions_left = p_cnt + d_cnt
	if p_cnt + d_cnt == 0 and not State.astra_liberated:
		State.astra_liberated = true
		Sfx.play("research")
		State.add_log("敵中枢惑星アストラ-Vの敵工場・敵マスドライバーを全滅させ制圧しました！上陸・採掘が可能に！", "good")

func damage_astra_facility(idx: int, dmg: float) -> bool:
	if idx < 0 or idx >= astra_bastions.size():
		return false
	var bst: Dictionary = astra_bastions[idx]
	if not bool(bst["alive"]):
		return false
	bst["hp"] = maxf(0.0, float(bst["hp"]) - dmg)
	if float(bst["hp"]) <= 0.0:
		bst["alive"] = false
		var wp := Vector2(bodies["astra"]["pos"]) + Vector2(bst["local_pos"])
		spawn_sparks_world(wp, Color(1.0, 0.38, 0.22), 28)
		Sfx.play("boom")
		# 施設破壊で60秒間（1分間）敵マスドライバーの射出速度を大幅遅延！
		State.enemy_launch_slow_t = 60.0
		sync_astra_facility_counts()
		var fname := String(bst.get("name", "敵施設"))
		if State.enemy_printers_left == 0 or State.enemy_drivers_left == 0:
			State.add_log("アストラ-Vの「%s」を破壊！敵工場または射出機が全滅し、敵スウォームの増産が完全停止しました！" % fname, "good")
		else:
			State.add_log("アストラ-Vの「%s」を破壊！1分間、敵の射出が大幅減速！（残存: 敵工場%d / 敵射出機%d）" % [fname, State.enemy_printers_left, State.enemy_drivers_left], "good")
		return true
	return false

func damage_astra_bastions(dmg: float) -> void:
	if State.astra_liberated: return
	for i in range(astra_bastions.size()):
		if bool(astra_bastions[i]["alive"]):
			damage_astra_facility(i, dmg)
	sync_astra_facility_counts()

static func wrap_col(c: int) -> int:
	return ((c % COLS) + COLS) % COLS

static func col_angle(c: int) -> float:
	return (float(wrap_col(c)) + 0.5) * DA

static func row_r(r: int) -> float:
	return R_CORE + (float(r) + 0.5) * CELL_H

func world_to_cell(local_pos: Vector2) -> Vector2i:
	var a := atan2(local_pos.y, local_pos.x)
	if a < 0.0: a += TAU
	var c := wrap_col(int(floor(a / DA)))
	var r := int(floor((local_pos.length() - R_CORE) / CELL_H))
	return Vector2i(c, r)

func world_pos_to_cell(world_pos: Vector2) -> Vector2i:
	return world_to_cell(to_terra_local(world_pos))

func cell_world_pos(c: int, r: int) -> Vector2:
	var a := col_angle(c)
	var rad := row_r(r)
	return Vector2(cos(a) * rad, sin(a) * rad)

func is_solid(c: int, r: int) -> bool:
	if r < 6: return true
	if r >= ROWS: return false
	var m := int(mat[r * COLS + wrap_col(c)])
	return m == 1 or m == 2 or m == 3

func get_ore_id(c: int, r: int) -> String:
	if r < 0 or r >= ROWS: return ""
	var code := int(ore[r * COLS + wrap_col(c)])
	if code > 0 and code < ORE_CODE_TO_ID.size():
		return ORE_CODE_TO_ID[code]
	return ""

func get_surface_row(c: int) -> int:
	var wc := wrap_col(c)
	for r in range(ROWS - 1, 5, -1):
		if int(mat[r * COLS + wc]) in [1, 2]:
			return r
	return 6

func get_pose_at(c: int, r: int) -> Dictionary:
	var wc := wrap_col(c)
	var a := col_angle(wc)
	var rad := R_CORE + float(r) * CELL_H
	var n := Vector2(cos(a), sin(a))
	return {"body_id": "terra", "col": wc, "row": r, "ang": a, "r": rad, "local_pos": n * rad, "pos": n * rad, "normal": n, "rot": a + PI * 0.5}

func is_drill_node_protected(col: int, row: int, bid: String = "terra") -> bool:
	var cols_n := COLS if bid == "terra" else EX_COLS
	var wc := ((col % cols_n) + cols_n) % cols_n
	for dn in drill_nodes:
		if String(dn.get("body_id", "terra")) != bid: continue
		var dr := int(dn["row"])
		if row < dr - 3 or row > dr: continue
		var dc := absi(((wc - int(dn["col"]) + cols_n / 2) % cols_n + cols_n) % cols_n - cols_n / 2)
		if dc <= 2:
			return true
	return false

func find_nearest_drill_node(terra_local_pos: Vector2, max_d: float = 175.0) -> Dictionary:
	var best: Dictionary = {}
	var bd := max_d
	for dn in drill_nodes:
		var d := Vector2(dn["pos"]).distance_to(terra_local_pos)
		if d < bd:
			bd = d; best = dn
	return best

func sample_surface_ore_under(world_pos: Vector2) -> Dictionary:
	var b := get_dominant_body(world_pos)
	var bid := String(b["id"])
	if bid == "sun": return {}
	var bp: Vector2 = b["pos"]
	var rel := world_pos - bp
	var dist := rel.length()
	var alt := dist - float(b["rad"])
	if alt > 5200.0 or dist < 10.0: return {}
	var n := rel / dist
	if bid == "terra":
		var a := atan2(n.y, n.x)
		if a < 0.0: a += TAU
		var c := wrap_col(int(floor(a / DA)))
		var sr := get_surface_row(c)
		var surf_local := cell_world_pos(c, sr)
		var o := get_ore_id(c, sr - 1)
		if o == "":
			var dn := find_nearest_drill_node(surf_local, 420.0)
			o = String(dn["ore"]) if not dn.is_empty() else (["fe", "cu", "si"][(c / 15) % 3])
		return {"body_id": "terra", "world_pos": bp + surf_local, "normal": n, "ore": o}
	else:
		var surf_w := bp + n * float(b["rad"])
		return {"body_id": bid, "world_pos": surf_w, "normal": n, "ore": String(b["ore"])}

# ------------------------------------------------------------------------------
# DIRECTIONAL RAYCAST MULTI-BEAM MINING (ALL 5 SLICED VOXEL PLANETS + ASTEROIDS!)
# ------------------------------------------------------------------------------
func find_mine_target(world_pos: Vector2, aim_dir: Vector2, max_range: float = 260.0) -> Dictionary:
	var dom := get_dominant_body(world_pos)
	var dom_id := String(dom["id"])
	var dom_p := Vector2(dom["pos"])
	var terra_p := Vector2(bodies["terra"]["pos"])
	var rel_dom := world_pos - dom_p
	var dir := aim_dir.normalized() if aim_dir.length() > 0.05 else (-rel_dom.normalized() if rel_dom.length() > 1.0 else Vector2.DOWN)
	var step_d := 8.0
	var d := 14.0
	var in_space := rel_dom.length() > float(dom["rad"]) + 220.0
	var space_reach := max_range + (180.0 if in_space else 0.0)

	while d <= space_reach:
		var wp := world_pos + dir * d
		var lp_terra := wp - terra_p

		# 0. Bedrock Drill Nodes on ANY planet
		if d <= max_range + 14.0:
			for dn in drill_nodes:
				if Vector2(dn["pos"]).distance_to(lp_terra) <= 26.0:
					return {"kind": "drill_node", "pos": terra_p + Vector2(dn["pos"]), "ore": dn["ore"]}

		# 1. Terra Crystal Spires & Voxels
		if dom_id == "terra":
			if d <= max_range + 16.0 and lp_terra.length() <= R_SURFACE + 90.0:
				for pi in range(crystal_props.size()):
					var pr: Dictionary = crystal_props[pi]
					if Vector2(pr["pos"]).distance_to(lp_terra) <= 24.0 * float(pr.get("sc", 1.0)):
						var o_n: String = ORE_CODE_TO_ID[int(pr["ore"])]
						return {"kind": "crystal", "idx": pi, "pos": terra_p + Vector2(pr["pos"]), "ore": o_n}
			if d <= max_range and lp_terra.length() <= R_SURFACE + 28.0:
				var cell := world_to_cell(lp_terra)
				if is_solid(cell.x, cell.y):
					if is_drill_node_protected(cell.x, cell.y, "terra"):
						return {"kind": "drill_node", "pos": wp, "ore": "fe"}
					if factory == null or not factory.is_foundation_protected(cell.x, cell.y, "terra"):
						return {"kind": "voxel", "body_id": "terra", "col": cell.x, "row": cell.y, "pos": wp, "ore": get_ore_id(cell.x, cell.y)}
					return {}

		# 2. Extra Sliced Voxel Planets (LUNA, IGNIS-I, CRYO-IV, ASTRA-V)
		elif extra_vox.has(dom_id) and d <= max_range + 20.0:
			var rel_b := wp - dom_p
			var ev: Dictionary = extra_vox[dom_id]
			if rel_b.length() <= float(ev["r_surf"]) + 28.0:
				var ecell := extra_local_to_cell(dom_id, rel_b)
				if is_extra_solid(dom_id, ecell.x, ecell.y):
					if dom_id == "astra" and not State.astra_liberated:
						return {"kind": "astra_shield", "pos": wp, "ore": "astra_shard"}
					if is_drill_node_protected(ecell.x, ecell.y, dom_id):
						return {"kind": "drill_node", "pos": wp, "ore": ev["ore_id"]}
					if factory == null or not factory.is_foundation_protected(ecell.x, ecell.y, dom_id):
						var o_c := int(ev["ore"][ecell.y * EX_COLS + wrap_ex_col(ecell.x)])
						var o_s := ORE_CODE_TO_ID[o_c] if (o_c > 0 and o_c < ORE_CODE_TO_ID.size()) else String(ev["ore_id"])
						return {"kind": "extra_voxel", "body_id": dom_id, "col": ecell.x, "row": ecell.y, "pos": wp, "ore": o_s}
					return {}

		# 3. Asteroids
		if in_space:
			for ai in range(asteroids.size()):
				var ast: Dictionary = asteroids[ai]
				if Vector2(ast["pos"]).distance_to(wp) <= float(ast["rad"]) + 12.0:
					return {"kind": "asteroid", "idx": ai, "pos": wp, "ore": ast["ore"]}

		d += step_d
	return {}

func damage_target(tgt: Dictionary, dmg: float) -> bool:
	if tgt.is_empty(): return false
	var kind := String(tgt["kind"])
	var wpos: Vector2 = Vector2(tgt["pos"])
	var lpos := to_terra_local(wpos)
	if kind == "astra_shield":
		var now_s := Time.get_ticks_msec()
		if now_s - _last_bounce_ms > 950:
			_last_bounce_ms = now_s
			Sfx.play("error")
			spawn_popup(lpos, "敵防衛シールド！（艦隊の「強襲」で制圧しよう）", Color(1.0, 0.36, 0.42))
		return false
	if kind == "drill_node":
		if randf() < 0.35:
			spawn_sparks(lpos, Color(0.86, 0.92, 1.0), 3)
		var now := Time.get_ticks_msec()
		if now - _last_bounce_ms > 950:
			_last_bounce_ms = now
			Sfx.play("click")
			spawn_popup(lpos, "硬質鉱床（採掘ドリル専用）", Color(1.0, 0.84, 0.36))
		return false
	if kind == "crystal":
		var pi := int(tgt["idx"])
		if pi < 0 or pi >= crystal_props.size(): return false
		var pr: Dictionary = crystal_props[pi]
		pr["hp"] = float(pr.get("hp", 10.0)) - dmg
		var o_n: String = ORE_CODE_TO_ID[int(pr["ore"])]
		if randf() < 0.45:
			spawn_sparks(pr["pos"], ore_col(o_n), 4)
		if float(pr["hp"]) <= 0.0:
			State.add_r(o_n, 8)
			Sfx.play("mine")
			spawn_sparks(pr["pos"], ore_col(o_n), 12)
			spawn_popup(pr["pos"], "+8 %s" % State.res_name(o_n), ore_col(o_n))
			crystal_props.remove_at(pi)
			return true
		return false
	if kind == "voxel":
		var c0 := int(tgt["col"]); var r0 := int(tgt["row"])
		var carved := false
		var touched_chunks: Dictionary = {}
		for dr in range(-1, 2):
			var r := r0 + dr
			if r < 6 or r >= ROWS: continue
			for dc in range(-1, 2):
				if abs(dc) + abs(dr) > 2: continue
				var wc := wrap_col(c0 + dc)
				if not is_solid(wc, r): continue
				if is_drill_node_protected(wc, r, "terra"): continue
				if factory != null and factory.is_foundation_protected(wc, r, "terra"): continue
				var idx := r * COLS + wc
				cell_hp[idx] -= dmg
				if cell_hp[idx] <= 0.0:
					var o_str := get_ore_id(wc, r)
					mat[idx] = 4 if r < ROWS - 5 else 0
					ore[idx] = 0
					cell_hp[idx] = 0.0
					carved_terra["%d,%d" % [wc, r]] = true
					touched_chunks[wc / CHUNK_COLS] = true
					touched_chunks[wrap_col(wc - 1) / CHUNK_COLS] = true
					touched_chunks[wrap_col(wc + 1) / CHUNK_COLS] = true
					carved = true
					if o_str != "":
						State.add_r(o_str, 4)
						spawn_popup(cell_world_pos(wc, r), "+4 %s" % State.res_name(o_str), ore_col(o_str))
					elif randf() < 0.35:
						State.add_r("fe", 1)
		if carved:
			Sfx.play("mine")
			spawn_sparks(lpos, ore_col(String(tgt.get("ore", "fe"))), 8)
			for pi in range(crystal_props.size() - 1, -1, -1):
				if Vector2(crystal_props[pi]["pos"]).distance_to(lpos) <= 52.0:
					var o_n: String = ORE_CODE_TO_ID[int(crystal_props[pi]["ore"])]
					State.add_r(o_n, 8)
					spawn_popup(crystal_props[pi]["pos"], "+8 %s" % State.res_name(o_n), ore_col(o_n))
					crystal_props.remove_at(pi)
			for ci in touched_chunks.keys():
				_bake_chunk(int(ci))
		return carved
	if kind == "extra_voxel":
		var bid := String(tgt["body_id"])
		if not extra_vox.has(bid): return false
		var ev: Dictionary = extra_vox[bid]
		var e_mat: PackedByteArray = ev["mat"]
		var e_ore: PackedByteArray = ev["ore"]
		var e_hp: PackedFloat32Array = ev["hp"]
		var c0 := int(tgt["col"]); var r0 := int(tgt["row"])
		var carved_e := false
		var touched_e: Dictionary = {}
		for dr in range(-1, 2):
			var r := r0 + dr
			if r < 4 or r >= EX_ROWS: continue
			for dc in range(-1, 2):
				if abs(dc) + abs(dr) > 2: continue
				var wc := wrap_ex_col(c0 + dc)
				if not is_extra_solid(bid, wc, r): continue
				if is_drill_node_protected(wc, r, bid): continue
				if factory != null and factory.is_foundation_protected(wc, r, bid): continue
				var idx := r * EX_COLS + wc
				e_hp[idx] -= dmg
				if e_hp[idx] <= 0.0:
					var oc := int(e_ore[idx])
					var o_str := ORE_CODE_TO_ID[oc] if (oc > 0 and oc < ORE_CODE_TO_ID.size()) else String(ev["ore_id"])
					e_mat[idx] = 4 if r < EX_ROWS - 3 else 0
					e_ore[idx] = 0
					e_hp[idx] = 0.0
					if not carved_extra.has(bid): carved_extra[bid] = {}
					carved_extra[bid]["%d,%d" % [wc, r]] = true
					touched_e[wc / EX_CHUNK_COLS] = true
					touched_e[wrap_ex_col(wc - 1) / EX_CHUNK_COLS] = true
					touched_e[wrap_ex_col(wc + 1) / EX_CHUNK_COLS] = true
					carved_e = true
					State.add_r(o_str, 4)
					spawn_popup(lpos, "+4 %s" % State.res_name(o_str), ore_col(o_str))
		if carved_e:
			Sfx.play("mine")
			spawn_sparks(lpos, ore_col(String(tgt.get("ore", "ti"))), 8)
			for ci in touched_e.keys():
				_bake_extra_chunk(bid, int(ci))
		return carved_e
	elif kind == "asteroid":
		var i := int(tgt["idx"])
		if i < 0 or i >= asteroids.size(): return false
		asteroids[i]["hp"] = float(asteroids[i]["hp"]) - dmg
		if randf() < 0.35: spawn_sparks(lpos, ore_col(String(asteroids[i]["ore"])), 3)
		if float(asteroids[i]["hp"]) <= 0.0:
			var o_n := String(asteroids[i]["ore"])
			State.add_r(o_n, 22)
			Sfx.play("mine")
			spawn_sparks(lpos, ore_col(o_n), 14)
			spawn_popup(lpos, "+22 %s" % State.res_name(o_n), ore_col(o_n))
			asteroids.remove_at(i)
			return true
	return false

static func ore_col(o: String) -> Color:
	match o:
		"fe": return Color(0.95, 0.36, 0.34)
		"cu": return Color(0.98, 0.68, 0.24)
		"si": return Color(0.32, 0.88, 1.0)
		"ti": return Color(0.76, 0.46, 1.0)
		"ignis_ore": return Color(1.0, 0.44, 0.16)
		"ice": return Color(0.64, 0.92, 1.0)
		"astra_shard": return Color(0.88, 0.32, 1.0)
		"plasma_cell": return Color(1.0, 0.72, 0.20)
		"cryo_rod": return Color(0.38, 0.94, 1.0)
		"quantum_core": return Color(0.48, 0.92, 1.0)
		"antimatter": return Color(1.0, 0.32, 0.66)
		"dyson_panel": return Color(1.0, 0.84, 0.28)
		"sci_pack": return Color(0.36, 1.0, 0.76)
		_: return Color(0.76, 0.82, 0.90)

func spawn_sparks(local_pos: Vector2, col: Color, cnt: int = 8) -> void:
	for _i in range(cnt):
		var a := randf_range(0.0, TAU)
		sparks.append({"pos": local_pos, "vel": Vector2(cos(a), sin(a)) * randf_range(40, 165), "col": col, "life": randf_range(0.22, 0.52), "sz": randf_range(2.0, 3.8)})
	if sparks.size() > 240: sparks = sparks.slice(sparks.size() - 240)

func spawn_sparks_world(world_pos: Vector2, col: Color, cnt: int = 8) -> void:
	spawn_sparks(to_terra_local(world_pos), col, cnt)

func spawn_smoke(local_pos: Vector2, normal: Vector2, col: Color = Color(0.74, 0.78, 0.86, 0.40)) -> void:
	smokes.append({"pos": local_pos, "vel": normal * randf_range(22, 48) + Vector2(-normal.y, normal.x) * randf_range(-16, 16), "col": col, "rad": randf_range(8, 13), "life": randf_range(1.2, 2.2), "max_l": 2.2})
	if smokes.size() > 95: smokes.pop_front()

func spawn_popup(local_pos: Vector2, txt: String, col: Color) -> void:
	var up := local_pos.normalized() if local_pos.length() > 1.0 else Vector2.UP
	popups.append({"pos": local_pos + up * 16.0, "vel": up * 34.0, "txt": txt, "col": col, "life": 1.15})
	if popups.size() > 36: popups.pop_front()

func spawn_popup_world(world_pos: Vector2, txt: String, col: Color) -> void:
	spawn_popup(to_terra_local(world_pos), txt, col)

# ------------------------------------------------------------------------------
# RENDERING: TERRA + EXTRA SLICED PLANET CORES, DRILL NODES, DAY/NIGHT & BASTIONS
# ------------------------------------------------------------------------------
func _draw() -> void:
	var cam := get_viewport().get_camera_2d()
	var cpos_l := to_terra_local(cam.global_position) if cam else Vector2(0, -R_SURFACE)
	var vp := get_viewport_rect().size
	var z := cam.zoom.x if cam else 1.0
	var half := (vp * 0.5) / maxf(0.008, z) + Vector2(600, 600)
	var vrect := Rect2(cpos_l - half, half * 2.0)
	var glow := ArtReg.get_t("glow")
	var sun_dir := get_sun_dir()
	var sun_ang := sun_dir.angle()
	var terra_p := Vector2(bodies["terra"]["pos"])

	# 1. Atmospheric Scattering is now rendered physically via Rayleigh+Mie shader in PhysAtmosphere!

	# 2. Terra Molten Magma Core
	if vrect.intersects(Rect2(-R_CORE - 400, -R_CORE - 400, (R_CORE + 400) * 2.0, (R_CORE + 400) * 2.0)):
		if glow:
			var gr := R_CORE * 1.55
			draw_texture_rect(glow, Rect2(-gr, -gr, gr * 2.0, gr * 2.0), false, Color(1.0, 0.42, 0.08, 0.42))
		draw_circle(Vector2.ZERO, R_CORE, Color(0.98, 0.44, 0.08))
		draw_circle(Vector2.ZERO, R_CORE * 0.72, Color(1.0, 0.76, 0.20))
		draw_circle(Vector2.ZERO, R_CORE * 0.42, Color(1.0, 0.94, 0.62))
		draw_arc(Vector2.ZERO, R_CORE, 0.0, TAU, 96, Color(1.0, 0.86, 0.36, 0.9), 8.0)

	# 2b. Extra Sliced Voxel Planets' Glowing Inner Cores & Pollution Haze!
	for bid in extra_vox.keys():
		var b: Dictionary = bodies[bid]
		var b_off := Vector2(b["pos"]) - terra_p
		var r_surf := float(b["rad"])
		var r_core := float(b["r_core"])
		if not vrect.intersects(Rect2(b_off.x - r_surf * 1.5, b_off.y - r_surf * 1.5, r_surf * 3.0, r_surf * 3.0)):
			continue
		var c_col: Color = b["col"]
		if glow:
			draw_texture_rect(glow, Rect2(b_off.x - r_core * 1.5, b_off.y - r_core * 1.5, r_core * 3.0, r_core * 3.0), false, Color(c_col.r, c_col.g, c_col.b, 0.42))
		draw_circle(b_off, r_core, c_col.darkened(0.15))
		draw_circle(b_off, r_core * 0.65, c_col.lightened(0.35))
		draw_circle(b_off, r_core * 0.35, Color(0.96, 0.98, 1.0))
		# Pollution haze aura if factory pollution > 5% on this planet!
		var pol := State.get_pollution(bid)
		if pol > 2.0:
			var pa := clampf(pol / 100.0, 0.08, 0.52)
			draw_arc(b_off, r_surf + 95.0, 0.0, TAU, 64, Color(0.86, 0.22, 0.48, pa), 38.0)
		# Enemy Stronghold Shield & Operating Enemy Factories / Mass Drivers on ASTRA-V!
		if bid == "astra" and not State.astra_liberated:
			var sh_p := 0.45 + 0.22 * sin(anim_t * 4.5)
			draw_arc(b_off, r_surf + 125.0, 0.0, TAU, 72, Color(1.0, 0.18, 0.32, sh_p), 8.0)
			# Draw crimson conveyor conduits between paired enemy 3D printers (even) and enemy mass drivers (odd)
			for pair_i in range(0, astra_bastions.size() - 1, 2):
				var b_pr: Dictionary = astra_bastions[pair_i]
				var b_dr: Dictionary = astra_bastions[pair_i + 1]
				if bool(b_pr["alive"]) and bool(b_dr["alive"]):
					var a0 := float(b_pr["ang"]); var a1 := float(b_dr["ang"])
					draw_arc(b_off, r_surf + 22.0, a0, a1, 14, Color(1.0, 0.26, 0.36, 0.78), 6.0)
					var pkt_t := fposmod(anim_t * 0.8 + float(pair_i) * 0.25, 1.0)
					var pa_m := lerpf(a0, a1, pkt_t)
					draw_circle(b_off + Vector2(cos(pa_m), sin(pa_m)) * (r_surf + 22.0), 7.0, Color(1.0, 0.72, 0.30))
			var fnt_e := ArtReg.get_font()
			for bst in astra_bastions:
				if not bool(bst["alive"]): continue
				var bp_l := b_off + Vector2(bst["local_pos"])
				var brot := float(bst["ang"]) + PI * 0.5
				var is_drv := String(bst.get("kind", "")) == "enemy_driver"
				var e_key := "mass_driver" if is_drv else "gantry_printer"
				var e_active := (State.enemy_printers_left > 0 and State.enemy_drivers_left > 0)
				var e_frame := (1 + (int(floor(anim_t * (6.0 if is_drv else 8.0) + float(bst["idx"]))) % 5)) if e_active else 0
				var ft_e := ArtReg.get_anim(e_key, e_frame)
				draw_set_transform(bp_l, brot, Vector2.ONE)
				draw_rect(Rect2(-68, -4, 136, 12), Color(0.24, 0.06, 0.10, 0.96))
				draw_rect(Rect2(-68, -4, 136, 3), Color(1.0, 0.32, 0.42))
				if ft_e:
					var fw := 142.0; var fh := 116.0 if is_drv else 102.0
					draw_texture_rect(ft_e, Rect2(-fw * 0.5, -fh, fw, fh), false, Color(1.0, 0.42, 0.48))
				var bf := clampf(float(bst["hp"]) / maxf(1.0, float(bst["max_hp"])), 0.0, 1.0)
				draw_rect(Rect2(-48, -132, 96, 8), Color(0.08, 0.06, 0.10, 0.94))
				draw_rect(Rect2(-47, -131, 94 * bf, 6), Color(1.0, 0.26, 0.34))
				if fnt_e:
					draw_string(fnt_e, Vector2(-70, -138), String(bst.get("name", "敵施設")), HORIZONTAL_ALIGNMENT_CENTER, 140, 12, Color(1.0, 0.66, 0.72))
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 3. Terra Crystal Spires
	var pnames := ["", "ore_fe", "ore_cu", "crystal_si", "ore_ti"]
	if z >= 0.14:
		for pr in crystal_props:
			var pp: Vector2 = pr["pos"]
			if not vrect.has_point(pp): continue
			var oid := int(pr["ore"])
			var sc := float(pr["sc"])
			if glow:
				var gc := ore_col(ORE_CODE_TO_ID[oid])
				gc.a = 0.42 if oid == 3 else 0.26
				var gr := 46.0 * sc
				draw_texture_rect(glow, Rect2(pp.x - gr, pp.y - gr, gr * 2.0, gr * 2.0), false, gc)
			var pt := ArtReg.get_t(pnames[oid])
			if pt:
				var sz := pt.get_size() * sc
				draw_set_transform(pp, float(pr["rot"]), Vector2.ONE)
				draw_texture_rect(pt, Rect2(-sz.x * 0.5, -sz.y * 0.75, sz.x, sz.y), false)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 3b. Bedrock Drill-Only Ore Deposits across ALL 5 planets!
	var font_dn := ArtReg.get_font()
	var placing_drill := (State.selected_tool == "drill")
	if z >= 0.10:
		for dn in drill_nodes:
			var dp: Vector2 = dn["pos"]
			if not vrect.has_point(dp): continue
			var oc := ore_col(String(dn["ore"]))
			var pulse := 0.72 + 0.28 * sin(anim_t * 3.8 + float(dn["id"]))
			if glow:
				var gc := oc; gc.a = (0.52 if placing_drill else 0.32) * pulse
				draw_texture_rect(glow, Rect2(dp.x - 54, dp.y - 54, 108, 108), false, gc)
			draw_set_transform(dp, float(dn["rot"]), Vector2.ONE)
			draw_rect(Rect2(-30, -4, 60, 14), Color(0.11, 0.14, 0.20, 0.96))
			draw_rect(Rect2(-30, -4, 60, 3), Color(0.56, 0.64, 0.76))
			draw_rect(Rect2(-24, -10, 48, 8), Color(0.18, 0.22, 0.30))
			draw_rect(Rect2(-20, -9, 40, 5), oc * pulse)
			var dn_ore := String(dn["ore"])
			var dn_tex_id := "ore_fe" if dn_ore == "fe" else ("ore_cu" if dn_ore == "cu" else ("crystal_si" if dn_ore in ["si", "ice"] else "ore_ti"))
			var dn_tex := ArtReg.get_t(dn_tex_id)
			if dn_tex:
				var dn_mod := Color.WHITE if dn_ore in ["fe", "cu", "si", "ti"] else oc.lightened(0.28)
				draw_texture_rect(dn_tex, Rect2(-26, -42, 52, 42), false, dn_mod)
			if placing_drill:
				var pr := 42.0 + sin(anim_t * 6.5) * 5.0
				draw_arc(Vector2(0, -10), pr, 0.0, TAU, 28, Color(1.0, 0.88, 0.32, 0.92), 2.6)
			if z >= 0.36:
				var ic := ArtReg.get_icon(dn_ore)
				if ic:
					draw_texture_rect(ic, Rect2(-32, -58, 18, 18), false)
				draw_string(font_dn, Vector2(-12, -44), "ドリル鉱床", HORIZONTAL_ALIGNMENT_LEFT, 86, 11, Color(1.0, 0.90, 0.44) if placing_drill else Color(0.86, 0.92, 1.0, 0.88))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 4. Physical Sunlight, Per-Voxel Terrain/Cave Shadows & Eclipses are ray-traced in PhysLighting!

	# 5. Smoke Plumes, Sparks & Popups
	for sm in smokes:
		var a := clampf(float(sm["life"]) / float(sm["max_l"]), 0.0, 1.0)
		var c: Color = sm["col"]; c.a *= a
		var r := float(sm["rad"]) * 1.7
		if glow: draw_texture_rect(glow, Rect2(sm["pos"].x - r, sm["pos"].y - r, r * 2.0, r * 2.0), false, c)
	for sp in sparks:
		var c: Color = sp["col"]; c.a = clampf(float(sp["life"]) * 2.0, 0.0, 1.0)
		var sz := float(sp["sz"])
		draw_rect(Rect2(sp["pos"] - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), c)
	for pp in popups:
		var c: Color = pp["col"]; c.a = clampf(float(pp["life"]), 0.0, 1.0)
		draw_string(font_dn, pp["pos"], String(pp["txt"]), HORIZONTAL_ALIGNMENT_CENTER, -1, 14, c)

func export_save_data() -> Dictionary:
	var angs: Dictionary = {}
	for bid in body_order:
		angs[bid] = float(bodies[bid]["ang"])
	var bsts: Array = []
	for bst in astra_bastions:
		bsts.append({"hp": float(bst["hp"]), "alive": bool(bst["alive"])})
	var ct: Array = []
	for k in carved_terra.keys():
		ct.append(String(k))
	var ce: Dictionary = {}
	for bid in carved_extra.keys():
		var arr: Array = []
		for k in carved_extra[bid].keys():
			arr.append(String(k))
		ce[String(bid)] = arr
	return {
		"body_angles": angs,
		"carved_terra": ct,
		"carved_extra": ce,
		"astra_bastions": bsts,
	}

func import_save_data(d: Dictionary) -> void:
	if d.is_empty(): return
	var angs: Dictionary = d.get("body_angles", {})
	for bid in angs.keys():
		if bodies.has(String(bid)):
			bodies[String(bid)]["ang"] = float(angs[bid])
	step_celestials(0.0, true)

	# Restore carved Terra voxels
	var touched_t: Dictionary = {}
	for k_v in d.get("carved_terra", []):
		var ks := String(k_v)
		var ps := ks.split(",")
		if ps.size() != 2: continue
		var wc := wrap_col(int(ps[0]))
		var r := clampi(int(ps[1]), 6, ROWS - 1)
		var idx := r * COLS + wc
		mat[idx] = 4 if r < ROWS - 5 else 0
		ore[idx] = 0
		cell_hp[idx] = 0.0
		carved_terra[ks] = true
		touched_t[wc / CHUNK_COLS] = true
	for ci in touched_t.keys():
		_bake_chunk(int(ci))
	_sync_terra_occ_all()

	# Restore carved extra planet voxels
	var ce: Dictionary = d.get("carved_extra", {})
	for bid_v in ce.keys():
		var bid := String(bid_v)
		if not extra_vox.has(bid): continue
		var ev: Dictionary = extra_vox[bid]
		var e_mat: PackedByteArray = ev["mat"]
		var e_ore: PackedByteArray = ev["ore"]
		var e_hp: PackedFloat32Array = ev["hp"]
		if not carved_extra.has(bid): carved_extra[bid] = {}
		var touched_e: Dictionary = {}
		for k_v in ce[bid_v]:
			var ks := String(k_v)
			var ps := ks.split(",")
			if ps.size() != 2: continue
			var wc := wrap_ex_col(int(ps[0]))
			var r := clampi(int(ps[1]), 4, EX_ROWS - 1)
			var idx := r * EX_COLS + wc
			e_mat[idx] = 4 if r < EX_ROWS - 3 else 0
			e_ore[idx] = 0
			e_hp[idx] = 0.0
			carved_extra[bid][ks] = true
			touched_e[wc / EX_CHUNK_COLS] = true
		for ci in touched_e.keys():
			_bake_extra_chunk(bid, int(ci))
		_sync_extra_occ_body(bid)

	# Restore ASTRA-V enemy facilities
	var bsts: Array = d.get("astra_bastions", [])
	for i in range(mini(bsts.size(), astra_bastions.size())):
		if bsts[i] is Dictionary:
			astra_bastions[i]["hp"] = float(bsts[i].get("hp", 1400.0))
			astra_bastions[i]["alive"] = bool(bsts[i].get("alive", true))
	sync_astra_facility_counts()
