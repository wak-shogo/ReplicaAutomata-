extends Node2D
class_name SphericalPlanet

# Fine-grained 24px-voxel 360-degree Spherical Open-World Planet rendered via
# 30 GPU-cached pixel-art curved ring chunks (90x200px each -> 8px crisp HD-2D texels).
# Produces smooth undulating sandstone hills, deep carved organic subterranean caverns,
# glowing cyan/crimson/amber crystal pockets, molten lava ocean core, orbiting moons & asteroids!

const COLS: int = 900
const ROWS: int = 100
const CHUNKS: int = 30
const CHUNK_COLS: int = 30 # 900 / 30
const SUB_X: int = 4       # 120px per chunk horizontally (crisp HD-2D texels)
const SUB_Y: int = 4       # 400px per chunk vertically

const R_CORE: float = 1100.0
const R_SURFACE: float = 3500.0
const R_ATMOS: float = 5900.0
const CELL_H: float = (R_SURFACE - R_CORE) / float(ROWS) # 24.0px
const DA: float = TAU / float(COLS)
const SPAWN_COL: int = 675 # North Pole (-PI/2)

const GRAV_SURF: float = 210.0
const ORIGIN_GM: float = GRAV_SURF * R_SURFACE * R_SURFACE

# Material byte codes: 0=sky, 1=regolith, 2=basalt, 3=magma, 4=cave_backwall
# Ore byte codes: 0=none, 1=fe, 2=cu, 3=si, 4=ti
var mat: PackedByteArray
var ore: PackedByteArray
var cell_hp: PackedFloat32Array

# Chunk GPU MeshInstances & Textures
var chunk_meshes: Array[MeshInstance2D] = []
var chunk_texs: Array[ImageTexture] = []
var dirty_chunks: Array[int] = []

# Large glowing decorative/mineable crystal clusters embedded in caves & crust
var crystal_props: Array[Dictionary] = []

# Celestials & VFX
var factory: Node2D = null
var sun_angle: float = -PI * 0.44
var anim_t: float = 0.0
var moons: Array[Dictionary] = []
var asteroids: Array[Dictionary] = []
var sparks: Array[Dictionary] = []
var smokes: Array[Dictionary] = []
var popups: Array[Dictionary] = []

func _ready() -> void:
	z_index = 0
	_init_chunk_nodes()
	generate_planet()

func _init_chunk_nodes() -> void:
	for ci in range(CHUNKS):
		var mi := MeshInstance2D.new()
		mi.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		mi.mesh = _build_ring_mesh(ci)
		var img := Image.create(CHUNK_COLS * SUB_X, ROWS * SUB_Y, false, Image.FORMAT_RGBA8)
		var itex := ImageTexture.create_from_image(img)
		mi.texture = itex
		mi.z_index = 0
		add_child(mi)
		chunk_meshes.append(mi)
		chunk_texs.append(itex)

func _build_ring_mesh(ci: int) -> ArrayMesh:
	var a0 := float(ci * CHUNK_COLS) * DA
	var a1 := float((ci + 1) * CHUNK_COLS) * DA
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
			var r0 := lerpf(R_SURFACE, R_CORE, v0)
			var r1 := lerpf(R_SURFACE, R_CORE, v1)
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

func generate_planet() -> void:
	var n := COLS * ROWS
	mat.resize(n)
	ore.resize(n)
	cell_hp.resize(n)
	crystal_props.clear()
	sparks.clear(); smokes.clear(); popups.clear()

	var rng := RandomNumberGenerator.new()
	rng.seed = 20261121

	# 1. Carve natural undulating hills, thick warm sandstone regolith, deep organic caverns & magma floor!
	for c in range(COLS):
		var a := float(c) * DA
		var hill := int(round(sin(a * 11.0) * 1.4 + cos(a * 23.0) * 0.9))
		# Keep North Pole landing site gently leveled for a dramatic factory skyline!
		var d_spawn := absi(wrap_col(c - SPAWN_COL + COLS / 2) - COLS / 2)
		if d_spawn < 26:
			hill = 0
		var surf_row := clampi(ROWS - 3 + hill, ROWS - 6, ROWS - 1)
		var rego_depth := 8 + int(round(sin(a * 17.0) * 2.0))

		for r in range(ROWS):
			var idx := r * COLS + c
			ore[idx] = 0
			if r > surf_row:
				mat[idx] = 0
				cell_hp[idx] = 0.0
				continue
			if r < 6:
				mat[idx] = 3 # Incandescent magma sea!
				cell_hp[idx] = 999.0
				continue

			# Smooth multi-octave organic subterranean cavern system (tapered roof = zero flat slits!)
			var cv := (
				sin(a * 18.0 + float(r) * 0.24) * 0.44
				+ cos(a * 37.0 - float(r) * 0.34) * 0.34
				+ sin(a * 9.0 + float(r) * 0.15) * 0.22
			) - maxf(0.0, float(r - (surf_row - 11)) * 0.15)
			# Carve organic arched subterranean crystal grottos below North Pole crust!
			var dc_s := float(wrap_col(c - SPAWN_COL + COLS / 2) - COLS / 2)
			var wob := sin(dc_s * 0.42) * 1.4 + cos(float(r) * 0.55) * 1.1
			var g1 := ((dc_s + 11.0) / 8.5) * ((dc_s + 11.0) / 8.5) + ((float(r) - 79.0 + wob) / 6.0) * ((float(r) - 79.0 + wob) / 6.0)
			var g2 := ((dc_s - 2.0) / 7.5) * ((dc_s - 2.0) / 7.5) + ((float(r) - 74.0 - wob * 0.8) / 5.8) * ((float(r) - 74.0 - wob * 0.8) / 5.8)
			var g3 := ((dc_s - 15.0) / 9.0) * ((dc_s - 15.0) / 9.0) + ((float(r) - 80.0 + wob * 0.7) / 6.2) * ((float(r) - 80.0 + wob * 0.7) / 6.2)
			var near_cave := (g1 < 1.0 or g2 < 1.0 or g3 < 1.0) and r <= surf_row - 7
			var is_cave := ((r >= 10 and r <= surf_row - 7 and cv > 0.38) or near_cave)
			if is_cave:
				mat[idx] = 4 # Shaded cave backwall
				cell_hp[idx] = 0.0
			elif r >= surf_row - rego_depth:
				mat[idx] = 1 # Warm desert sandstone regolith
				cell_hp[idx] = 8.0
			else:
				mat[idx] = 2 # Dark volcanic cavern basalt
				cell_hp[idx] = 14.0

	# 2. Paint organic mineral & crystal veins across the entire 360-degree planet
	# Rich starter surface & shallow cave Fe/Cu/Si right around North Pole!
	for dc in [-24, -18, -13, -8, -4, 5, 10, 15, 21, 27]:
		var wc := wrap_col(SPAWN_COL + int(dc))
		var sr := get_surface_row(wc)
		var oid := 2 if (int(dc) in [-18, -8, 5, 15, 27]) else 1
		_paint_vein(wc, sr - 1, 2, 2, oid)
	# Glowing cyan Silicon quartz crystal veins inside starter caverns right below spawn!
	_paint_vein(wrap_col(SPAWN_COL - 6), 76, 3, 2, 3)
	_paint_vein(wrap_col(SPAWN_COL + 8), 75, 3, 2, 3)
	_paint_vein(wrap_col(SPAWN_COL - 16), 72, 3, 2, 1)
	_paint_vein(wrap_col(SPAWN_COL + 18), 71, 3, 2, 1)
	_paint_vein(wrap_col(SPAWN_COL), 50, 4, 3, 4)

	# Global distributed mineral veins across all 900 columns
	for _i in range(260):
		_paint_vein(rng.randi_range(0, COLS - 1), rng.randi_range(64, ROWS - 4), rng.randi_range(2, 4), rng.randi_range(1, 3), 1)
	for _i in range(210):
		_paint_vein(rng.randi_range(0, COLS - 1), rng.randi_range(50, ROWS - 4), rng.randi_range(2, 3), rng.randi_range(1, 3), 2)
	for _i in range(170):
		_paint_vein(rng.randi_range(0, COLS - 1), rng.randi_range(24, 82), rng.randi_range(2, 4), rng.randi_range(1, 3), 3)
	for _i in range(110):
		_paint_vein(rng.randi_range(0, COLS - 1), rng.randi_range(10, 56), rng.randi_range(2, 4), rng.randi_range(2, 3), 4)

	# 3. Spawn glowing HD-2D crystal spire props on cavern floors & surface mineral outcrops!
	for c in range(0, COLS, 4):
		var d_sp := absi(wrap_col(c - SPAWN_COL + COLS / 2) - COLS / 2)
		for r in range(12, ROWS - 2):
			var idx := r * COLS + c
			if mat[idx] == 4 and r > 0 and mat[(r - 1) * COLS + c] in [1, 2]:
				var o := int(ore[(r - 1) * COLS + c])
				if o > 0 or (d_sp < 30 and rng.randf() < 0.52):
					var oid: int = o if o > 0 else int([3, 3, 1, 2][rng.randi() % 4])
					var p := cell_world_pos(c, r)
					crystal_props.append({"col": c, "row": r, "pos": p, "rot": col_angle(c) + PI * 0.5, "ore": oid, "sc": rng.randf_range(0.85, 1.45)})
	# Also spawn visible surface mineral outcrops near North Pole so starter ores shine right on frame 1!
	for dc in [-22, -16, -11, -7, -3, 4, 9, 14, 19, 25]:
		var wc := wrap_col(SPAWN_COL + int(dc))
		var sr := get_surface_row(wc)
		var oid := 2 if (int(dc) in [-16, -7, 4, 14, 25]) else 1
		crystal_props.append({"col": wc, "row": sr + 1, "pos": cell_world_pos(wc, sr + 1), "rot": col_angle(wc) + PI * 0.5, "ore": oid, "sc": 0.92})

	# 4. Bake spawn-visible chunks immediately (< 45ms!), queue remaining chunks lazily
	dirty_chunks.clear()
	var spawn_ci := SPAWN_COL / CHUNK_COLS
	for dci in range(-2, 3):
		_bake_chunk((spawn_ci + dci + CHUNKS) % CHUNKS)
	for ci in range(CHUNKS):
		var dist_c := mini(absi(ci - spawn_ci), CHUNKS - absi(ci - spawn_ci))
		if dist_c > 2:
			dirty_chunks.append(ci)

	# 5. Orbiting Moons & Natural Asteroid Belt
	moons = [
		{"name": "LUNA-PRIME", "tex": "moon_luna", "ore": "ti",  "orbit_r": 9400.0,  "ang": -PI * 0.68, "spd": 0.009,  "rad": 360.0, "gm": 90.0 * 360.0 * 360.0, "pos": Vector2.ZERO},
		{"name": "IGNIS-IX",   "tex": "moon_ignis","ore": "fe",  "orbit_r": 12200.0, "ang": -PI * 0.22, "spd": -0.007, "rad": 320.0, "gm": 80.0 * 320.0 * 320.0, "pos": Vector2.ZERO},
		{"name": "CRYO-IV",    "tex": "moon_cryo", "ore": "ice", "orbit_r": 14800.0, "ang": PI * 0.42,  "spd": 0.005,  "rad": 340.0, "gm": 85.0 * 340.0 * 340.0, "pos": Vector2.ZERO},
	]
	_update_moons(0.0)

	asteroids.clear()
	var cyc: Array[String] = ["si", "cu", "fe", "ti"]
	for i in range(140):
		var ang := (-PI * 0.5 + float(i - 8) * 0.045) if i < 18 else rng.randf_range(0.0, TAU)
		var dist := rng.randf_range(R_ATMOS + 260.0, R_ATMOS + 950.0) if i < 18 else rng.randf_range(R_ATMOS + 400.0, 15500.0)
		var ot: String = cyc[i % cyc.size()]
		asteroids.append({
			"pos": Vector2(cos(ang), sin(ang)) * dist,
			"ore": ot, "hp": 60.0, "rad": rng.randf_range(28.0, 48.0),
			"ang": ang, "dist": dist, "spd": rng.randf_range(0.0025, 0.006) * (1.0 if i % 2 == 0 else -1.0),
			"rot": rng.randf_range(0.0, TAU),
		})

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
	var w := CHUNK_COLS * SUB_X # 90
	var h := ROWS * SUB_Y       # 200
	var data := PackedByteArray()
	data.resize(w * h * 4)
	var base_c := ci * CHUNK_COLS

	for r in range(ROWS):
		var y_base := (ROWS - 1 - r) * SUB_Y # r=ROWS-1 is top of image (y=0)
		var lava_glow := clampf(float(16 - r) / 16.0, 0.0, 1.0)
		for lc in range(CHUNK_COLS):
			var c := base_c + lc
			var idx := r * COLS + c
			var m := int(mat[idx])
			if m == 0:
				continue
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
						# Moody dark subterranean cave backwall + magma floor bounce-glow
						var base_b := 12 + int(n * 9.0)
						rr_c = base_b + int(lava_glow * 74.0)
						gg_c = base_b + 3 + int(lava_glow * 24.0)
						bb_c = base_b + 10
					elif m == 3:
						# Molten incandescent magma core
						if n > 0.72: rr_c = 255; gg_c = 242; bb_c = 148
						elif n > 0.36: rr_c = 255; gg_c = 152; bb_c = 28
						else: rr_c = 224; gg_c = 62; bb_c = 14
					elif m == 1:
						# Warm sandstone / desert ochre regolith matching concept art!
						var strata := 12 if ((r + int(n * 2.0)) % 3 == 0) else 0
						rr_c = 166 + int(n * 38.0) - strata
						gg_c = 132 + int(n * 32.0) - strata
						bb_c = 86 + int(n * 22.0) - strata
						if open_top and sy == 0:
							rr_c = clampi(rr_c + 34, 0, 255)
							gg_c = clampi(gg_c + 30, 0, 255)
							bb_c = clampi(bb_c + 18, 0, 255)
					else:
						# Deep dark volcanic cave basalt
						var rock := 24 + int(n * 24.0)
						rr_c = rock + int(lava_glow * 64.0)
						gg_c = rock + 5 + int(lava_glow * 22.0)
						bb_c = rock + 16

					# Organic dark contour outline on any solid rock edge facing sky or cave!
					if solid and m != 3:
						if (open_bot and sy == SUB_Y - 1) or (open_l and sx == 0) or (open_r and sx == SUB_X - 1):
							rr_c = int(rr_c * 0.32); gg_c = int(gg_c * 0.32); bb_c = int(bb_c * 0.36)
						elif open_top and sy == 0 and m == 2:
							rr_c = clampi(rr_c + 22, 0, 255); gg_c = clampi(gg_c + 26, 0, 255); bb_c = clampi(bb_c + 34, 0, 255)

					# Subtle mineral ore glint blended naturally into rock (crystal props shine as primary focal ore!)
					if o > 0 and n > 0.80:
						var or_r := 0; var or_g := 0; var or_b := 0
						match o:
							1: or_r = 228; or_g = 86;  or_b = 70  # Iron glint
							2: or_r = 242; or_g = 172; or_b = 64  # Copper glint
							3: or_r = 76;  or_g = 216; or_b = 252 # Silicon glint
							4: or_r = 176; or_g = 112; or_b = 242 # Titanium glint
						rr_c = int(rr_c * 0.52 + or_r * 0.48)
						gg_c = int(gg_c * 0.52 + or_g * 0.48)
						bb_c = int(bb_c * 0.52 + or_b * 0.48)

					var off := (py * w + px) * 4
					data[off] = rr_c
					data[off + 1] = gg_c
					data[off + 2] = bb_c
					data[off + 3] = aa_c

	var img := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)
	chunk_texs[ci].update(img)

func _update_moons(delta: float) -> void:
	for m in moons:
		m["ang"] = float(m["ang"]) + float(m["spd"]) * delta
		var a := float(m["ang"])
		m["pos"] = Vector2(cos(a), sin(a)) * float(m["orbit_r"])

func _process(delta: float) -> void:
	anim_t += delta
	sun_angle = wrapf(sun_angle + 0.0014 * delta, -PI, PI)
	_update_moons(delta)

	# Lazily bake 1 queued chunk per frame (keeps WebAssembly locked 60 FPS!)
	if not dirty_chunks.is_empty():
		var ci := int(dirty_chunks.pop_front())
		_bake_chunk(ci)

	for ast in asteroids:
		ast["ang"] = float(ast["ang"]) + float(ast["spd"]) * delta
		ast["rot"] = float(ast["rot"]) + 0.2 * delta
		var a := float(ast["ang"])
		ast["pos"] = Vector2(cos(a), sin(a)) * float(ast["dist"])

	for i in range(sparks.size() - 1, -1, -1):
		sparks[i]["pos"] += sparks[i]["vel"] * delta
		sparks[i]["vel"] += compute_gravity(sparks[i]["pos"]) * delta * 0.22
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
# POLAR COORDINATES, GRAVITY & FINE VOXEL COLLISION
# ------------------------------------------------------------------------------
static func wrap_col(c: int) -> int:
	return ((c % COLS) + COLS) % COLS

static func col_angle(c: int) -> float:
	return (float(wrap_col(c)) + 0.5) * DA

static func row_r(r: int) -> float:
	return R_CORE + (float(r) + 0.5) * CELL_H

func world_to_cell(pos: Vector2) -> Vector2i:
	var a := atan2(pos.y, pos.x)
	if a < 0.0: a += TAU
	var c := wrap_col(int(floor(a / DA)))
	var r := int(floor((pos.length() - R_CORE) / CELL_H))
	return Vector2i(c, r)

func cell_world_pos(c: int, r: int) -> Vector2:
	var a := col_angle(c)
	var rad := row_r(r)
	return Vector2(cos(a) * rad, sin(a) * rad)

func is_solid(c: int, r: int) -> bool:
	if r < 6: return true # Molten core floor
	if r >= ROWS: return false
	var m := int(mat[r * COLS + wrap_col(c)])
	return m == 1 or m == 2 or m == 3

func get_ore_id(c: int, r: int) -> String:
	if r < 0 or r >= ROWS: return ""
	match int(ore[r * COLS + wrap_col(c)]):
		1: return "fe"
		2: return "cu"
		3: return "si"
		4: return "ti"
		_: return ""

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
	return {"col": wc, "row": r, "ang": a, "r": rad, "pos": n * rad, "normal": n, "rot": a + PI * 0.5}

func compute_gravity(pos: Vector2) -> Vector2:
	var r := pos.length()
	var acc := Vector2.ZERO
	if r > 40.0:
		var gm := (GRAV_SURF * (r / R_SURFACE)) if r < R_SURFACE else (ORIGIN_GM / (r * r))
		if r > 17000.0:
			gm *= clampf(1.0 - (r - 17000.0) / 5000.0, 0.0, 1.0)
		acc += (-pos / r) * gm
	for m in moons:
		var dv: Vector2 = m["pos"] - pos
		var d := dv.length()
		var mr := float(m["rad"])
		if d > mr * 0.8 and d < mr * 9.0:
			acc += (dv / d) * (float(m["gm"]) / (d * d))
	return acc

func get_atmos_density(pos: Vector2) -> float:
	var r := pos.length()
	if r >= R_ATMOS: return 0.0 # Zero drag in vacuum space!
	return clampf(1.0 - maxf(0.0, r - R_SURFACE) / (R_ATMOS - R_SURFACE), 0.0, 1.0)

func get_sunlight(pos: Vector2) -> float:
	var sd := Vector2(cos(sun_angle), sin(sun_angle))
	var up := pos.normalized() if pos.length() > 1.0 else Vector2.UP
	return clampf((up.dot(sd) + 0.20) / 0.88, 0.0, 1.0)

func check_moon_hit(pos: Vector2, rad: float = 20.0) -> Dictionary:
	for m in moons:
		var mp: Vector2 = m["pos"]
		var lim := float(m["rad"]) + rad
		var diff := pos - mp
		var d := diff.length()
		if d < lim and d > 0.1:
			return {"hit": true, "normal": diff / d, "push": mp + (diff / d) * lim, "moon": m}
	return {"hit": false}

# ------------------------------------------------------------------------------
# SMOOTH ORGANIC MULTI-BEAM MINING (CARVES ROUNDED TUNNELS, NEVER UGLY BLOCKS!)
# ------------------------------------------------------------------------------
func find_mine_target(pos: Vector2, aim_world: Vector2, max_range: float = 260.0) -> Dictionary:
	if pos.length() > R_SURFACE + 240.0:
		var bi := -1; var bd := max_range + 140.0
		for i in range(asteroids.size()):
			var d := pos.distance_to(asteroids[i]["pos"]) - float(asteroids[i]["rad"])
			if d < bd: bd = d; bi = i
		if bi >= 0:
			return {"kind": "asteroid", "idx": bi, "pos": asteroids[bi]["pos"], "ore": asteroids[bi]["ore"]}
		for i in range(moons.size()):
			var mp: Vector2 = moons[i]["pos"]
			var d := pos.distance_to(mp) - float(moons[i]["rad"])
			if d < max_range + 120.0:
				return {"kind": "moon", "idx": i, "pos": mp + (pos - mp).normalized() * float(moons[i]["rad"]), "ore": moons[i]["ore"]}
		return {}

	var pc := world_to_cell(pos)
	var best_s := 1e9
	var best_c := -1; var best_r := -1; var best_p := Vector2.ZERO
	for dr in range(-7, 7):
		var r := pc.y + dr
		if r < 6 or r >= ROWS: continue
		for dc in range(-8, 9):
			var wc := wrap_col(pc.x + dc)
			if not is_solid(wc, r): continue
			if factory != null and factory.is_foundation_protected(wc, r): continue
			var cp := cell_world_pos(wc, r)
			var d := cp.distance_to(pos)
			if d > max_range: continue
			var sc := d
			if int(ore[r * COLS + wc]) > 0: sc -= 55.0
			if aim_world.length() > 0.2:
				sc -= (cp - pos).normalized().dot(aim_world.normalized()) * 85.0
			if sc < best_s:
				best_s = sc; best_c = wc; best_r = r; best_p = cp
	if best_c >= 0:
		return {"kind": "voxel", "col": best_c, "row": best_r, "pos": best_p, "ore": get_ore_id(best_c, best_r)}
	return {}

func damage_target(tgt: Dictionary, dmg: float) -> bool:
	if tgt.is_empty(): return false
	var kind := String(tgt["kind"])
	if kind == "voxel":
		var c0 := int(tgt["col"]); var r0 := int(tgt["row"])
		var carved := false
		var touched_chunks: Dictionary = {}
		# Carve smooth circular 2-voxel radius organic scoop!
		for dr in range(-1, 2):
			var r := r0 + dr
			if r < 6 or r >= ROWS: continue
			for dc in range(-1, 2):
				if abs(dc) + abs(dr) > 2: continue
				var wc := wrap_col(c0 + dc)
				if not is_solid(wc, r): continue
				if factory != null and factory.is_foundation_protected(wc, r): continue
				var idx := r * COLS + wc
				cell_hp[idx] -= dmg
				if cell_hp[idx] <= 0.0:
					var o_str := get_ore_id(wc, r)
					mat[idx] = 4 if r < ROWS - 5 else 0
					ore[idx] = 0
					cell_hp[idx] = 0.0
					touched_chunks[wc / CHUNK_COLS] = true
					touched_chunks[wrap_col(wc - 1) / CHUNK_COLS] = true
					touched_chunks[wrap_col(wc + 1) / CHUNK_COLS] = true
					carved = true
					if o_str != "":
						State.add_r(o_str, 4)
						spawn_popup(cell_world_pos(wc, r), "+4 %s" % o_str.to_upper(), ore_col(o_str))
					elif randf() < 0.35:
						State.add_r("fe", 1)
		if carved:
			Sfx.play("mine")
			spawn_sparks(tgt["pos"], ore_col(String(tgt.get("ore", "fe"))), 8)
			# Also harvest any crystal prop right on carved voxels
			for pi in range(crystal_props.size() - 1, -1, -1):
				if Vector2(crystal_props[pi]["pos"]).distance_to(Vector2(tgt["pos"])) <= 52.0:
					var o_n: String = ["", "fe", "cu", "si", "ti"][int(crystal_props[pi]["ore"])]
					State.add_r(o_n, 8)
					spawn_popup(crystal_props[pi]["pos"], "+8 %s" % o_n.to_upper(), ore_col(o_n))
					crystal_props.remove_at(pi)
			for ci in touched_chunks.keys():
				_bake_chunk(int(ci))
		return carved
	elif kind == "asteroid":
		var i := int(tgt["idx"])
		if i < 0 or i >= asteroids.size(): return false
		asteroids[i]["hp"] = float(asteroids[i]["hp"]) - dmg
		if randf() < 0.35: spawn_sparks(asteroids[i]["pos"], ore_col(String(asteroids[i]["ore"])), 3)
		if float(asteroids[i]["hp"]) <= 0.0:
			var o_n := String(asteroids[i]["ore"])
			State.add_r(o_n, 22)
			Sfx.play("mine")
			spawn_sparks(asteroids[i]["pos"], ore_col(o_n), 14)
			spawn_popup(asteroids[i]["pos"], "+22 %s" % o_n.to_upper(), ore_col(o_n))
			asteroids.remove_at(i)
			return true
	elif kind == "moon":
		var o_n := String(moons[int(tgt["idx"])]["ore"])
		if randf() < dmg * 0.05:
			State.add_r(o_n, 3)
			Sfx.play("mine")
			spawn_sparks(tgt["pos"], ore_col(o_n), 6)
			spawn_popup(tgt["pos"], "+3 %s" % o_n.to_upper(), ore_col(o_n))
			return true
	return false

static func ore_col(o: String) -> Color:
	match o:
		"fe": return Color(0.95, 0.36, 0.34)
		"cu": return Color(0.98, 0.68, 0.24)
		"si": return Color(0.32, 0.88, 1.0)
		"ti": return Color(0.76, 0.46, 1.0)
		"ice": return Color(0.64, 0.92, 1.0)
		_: return Color(0.76, 0.82, 0.90)

func spawn_sparks(pos: Vector2, col: Color, cnt: int = 8) -> void:
	for _i in range(cnt):
		var a := randf_range(0.0, TAU)
		sparks.append({"pos": pos, "vel": Vector2(cos(a), sin(a)) * randf_range(40, 165), "col": col, "life": randf_range(0.22, 0.52), "sz": randf_range(2.0, 3.8)})
	if sparks.size() > 240: sparks = sparks.slice(sparks.size() - 240)

func spawn_smoke(pos: Vector2, normal: Vector2, col: Color = Color(0.74, 0.78, 0.86, 0.40)) -> void:
	smokes.append({"pos": pos, "vel": normal * randf_range(22, 48) + Vector2(-normal.y, normal.x) * randf_range(-16, 16), "col": col, "rad": randf_range(8, 13), "life": randf_range(1.2, 2.2), "max_l": 2.2})
	if smokes.size() > 95: smokes.pop_front()

func spawn_popup(pos: Vector2, txt: String, col: Color) -> void:
	var up := pos.normalized() if pos.length() > 1.0 else Vector2.UP
	popups.append({"pos": pos + up * 16.0, "vel": up * 34.0, "txt": txt, "col": col, "life": 1.15})
	if popups.size() > 36: popups.pop_front()

# ------------------------------------------------------------------------------
# OVERLAYS: ATMOSPHERE HALO, MAGMA CORE, GLOWING CRYSTAL GROTTOES, MOONS, VFX
# ------------------------------------------------------------------------------
func _draw() -> void:
	var cam := get_viewport().get_camera_2d()
	var cpos := cam.global_position if cam else Vector2(0, -R_SURFACE)
	var vp := get_viewport_rect().size
	var z := cam.zoom.x if cam else 1.0
	var half := (vp * 0.5) / maxf(0.02, z) + Vector2(360, 360)
	var vrect := Rect2(cpos - half, half * 2.0)
	var glow := ArtReg.get_t("glow")

	# 1. Atmospheric Rayleigh Scattering Halo around planet
	for b in range(6):
		var t := float(b) / 6.0
		draw_circle(Vector2.ZERO, lerpf(R_SURFACE, R_ATMOS, 1.0 - t), Color(0.11, 0.24, 0.46, 0.06 + t * 0.04))
	draw_arc(Vector2.ZERO, R_ATMOS, 0.0, TAU, 128, Color(0.28, 0.62, 0.92, 0.22), 2.5 / maxf(0.04, z))

	# 2. Molten Magma Core Sea at center (r <= R_CORE)
	if vrect.intersects(Rect2(-R_CORE - 400, -R_CORE - 400, (R_CORE + 400) * 2.0, (R_CORE + 400) * 2.0)):
		if glow:
			var gr := R_CORE * 1.55
			draw_texture_rect(glow, Rect2(-gr, -gr, gr * 2.0, gr * 2.0), false, Color(1.0, 0.42, 0.08, 0.42))
		draw_circle(Vector2.ZERO, R_CORE, Color(0.98, 0.44, 0.08))
		draw_circle(Vector2.ZERO, R_CORE * 0.72, Color(1.0, 0.76, 0.20))
		draw_circle(Vector2.ZERO, R_CORE * 0.42, Color(1.0, 0.94, 0.62))
		draw_arc(Vector2.ZERO, R_CORE, 0.0, TAU, 96, Color(1.0, 0.86, 0.36, 0.9), 8.0)

	# 3. Large Glowing Subterranean & Surface Crystal Spires (concept art centerpiece!)
	var pnames := ["", "ore_fe", "ore_cu", "crystal_si", "ore_ti"]
	var onames := ["", "fe", "cu", "si", "ti"]
	for pr in crystal_props:
		var pp: Vector2 = pr["pos"]
		if not vrect.has_point(pp): continue
		var oid := int(pr["ore"])
		var sc := float(pr["sc"])
		if glow:
			var gc := ore_col(onames[oid])
			gc.a = 0.42 if oid == 3 else 0.26
			var gr := 46.0 * sc
			draw_texture_rect(glow, Rect2(pp.x - gr, pp.y - gr, gr * 2.0, gr * 2.0), false, gc)
		var pt := ArtReg.get_t(pnames[oid])
		if pt:
			var sz := pt.get_size() * sc
			draw_set_transform(pp, float(pr["rot"]), Vector2.ONE)
			draw_texture_rect(pt, Rect2(-sz.x * 0.5, -sz.y * 0.75, sz.x, sz.y), false)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 4. Orbiting Moons & Orbital Rings
	for m in moons:
		var mp: Vector2 = m["pos"]
		var mr := float(m["rad"])
		if z < 0.25:
			draw_arc(Vector2.ZERO, float(m["orbit_r"]), 0.0, TAU, 96, Color(0.32, 0.54, 0.82, 0.18), 2.0 / maxf(0.02, z))
		if not vrect.intersects(Rect2(mp.x - mr - 100, mp.y - mr - 100, (mr + 100) * 2.0, (mr + 100) * 2.0)): continue
		if glow:
			draw_texture_rect(glow, Rect2(mp.x - mr * 1.4, mp.y - mr * 1.4, mr * 2.8, mr * 2.8), false, Color(0.45, 0.72, 1.0, 0.16))
		var mt := ArtReg.get_t(String(m["tex"]))
		if mt: draw_texture_rect(mt, Rect2(mp.x - mr, mp.y - mr, mr * 2.0, mr * 2.0), false)

	# 5. Orbital Asteroids
	for ast in asteroids:
		var ap: Vector2 = ast["pos"]
		if not vrect.has_point(ap): continue
		var ar := float(ast["rad"])
		var at := ArtReg.get_t("ast_" + String(ast["ore"]))
		if at:
			draw_set_transform(ap, float(ast["rot"]), Vector2.ONE)
			draw_texture_rect(at, Rect2(-ar, -ar, ar * 2.0, ar * 2.0), false)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 6. Smoke Plumes, Sparks & Popups
	for sm in smokes:
		var a := clampf(float(sm["life"]) / float(sm["max_l"]), 0.0, 1.0)
		var c: Color = sm["col"]; c.a *= a
		var r := float(sm["rad"]) * 1.7
		if glow: draw_texture_rect(glow, Rect2(sm["pos"].x - r, sm["pos"].y - r, r * 2.0, r * 2.0), false, c)
	for sp in sparks:
		var c: Color = sp["col"]; c.a = clampf(float(sp["life"]) * 2.0, 0.0, 1.0)
		var sz := float(sp["sz"])
		draw_rect(Rect2(sp["pos"] - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), c)
	var font := ThemeDB.fallback_font
	for pp in popups:
		var c: Color = pp["col"]; c.a = clampf(float(pp["life"]), 0.0, 1.0)
		draw_string(font, pp["pos"], String(pp["txt"]), HORIZONTAL_ALIGNMENT_CENTER, -1, 14, c)
