extends CanvasLayer

# Full-screen physically ray-traced sunlight, per-voxel terrain/cave shadows,
# mutual planetary/lunar eclipses, atmospheric spectral sunlight tint, and
# dynamic point lights (player headlamp, mining beam, working factories & orbital modules).
# Runs on CanvasLayer 5 (above World layer 0, strictly below CommandHUD layer 20!).

var planet: SphericalPlanet = null
var grid: Node2D = null
var orbital: Node2D = null
var player: Node2D = null
var cam: Camera2D = null

var _rect: ColorRect = null
var _mat: ShaderMaterial = null
var _t: float = 0.0

const BODY_ORDER: Array[String] = ["terra", "luna", "ignis", "cryo", "astra"]

const BODY_ATMOS_R: Dictionary = {
	"terra": 5900.0,
	"luna":  0.0,
	"ignis": 3250.0,
	"cryo":  3520.0,
	"astra": 3920.0,
}

const BODY_RAYLEIGH: Dictionary = {
	"terra": Vector4(0.00028, 0.00084, 0.00238, 0.28),
	"luna":  Vector4(0.0, 0.0, 0.0, 0.25),
	"ignis": Vector4(0.00145, 0.00056, 0.00018, 0.30),
	"cryo":  Vector4(0.00020, 0.00082, 0.00185, 0.28),
	"astra": Vector4(0.00105, 0.00024, 0.00138, 0.30),
}

const BODY_MIE: Dictionary = {
	"terra": Vector4(0.00046, 0.00034, 0.00022, 0.10),
	"luna":  Vector4(0.0, 0.0, 0.0, 0.10),
	"ignis": Vector4(0.00062, 0.00030, 0.00010, 0.14),
	"cryo":  Vector4(0.00028, 0.00046, 0.00056, 0.12),
	"astra": Vector4(0.00052, 0.00016, 0.00034, 0.14),
}

const BODY_CORE_COL: Dictionary = {
	"terra": Vector4(1.0, 0.44, 0.12, 1.0),
	"luna":  Vector4(0.55, 0.68, 0.92, 0.55),
	"ignis": Vector4(1.0, 0.38, 0.08, 1.25),
	"cryo":  Vector4(0.32, 0.86, 1.0, 0.85),
	"astra": Vector4(0.95, 0.24, 0.62, 0.95),
}

const EXTRA_BAND_IDX: Dictionary = {
	"terra": -1.0,
	"luna":  0.0,
	"ignis": 1.0,
	"cryo":  2.0,
	"astra": 3.0,
}

func _ready() -> void:
	layer = 5
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.color = Color.WHITE
	var sh := load("res://shaders/phys_lighting.gdshader")
	if sh is Shader:
		_mat = ShaderMaterial.new()
		_mat.shader = sh
		_rect.material = _mat
	add_child(_rect)

func _process(delta: float) -> void:
	_t += delta
	if not _mat or not planet:
		return

	var cpos := cam.get_screen_center_position() if cam else Vector2.ZERO
	var czoom := cam.zoom.x if cam else 1.0
	var vp := get_viewport().get_visible_rect().size

	_mat.set_shader_parameter("u_cam_pos", cpos)
	_mat.set_shader_parameter("u_cam_zoom", czoom)
	_mat.set_shader_parameter("u_vp_size", vp)
	_mat.set_shader_parameter("u_time", _t)
	_mat.set_shader_parameter("u_sun_rad", SphericalPlanet.SUN_RAD)

	if planet.terra_occ_tex:
		_mat.set_shader_parameter("u_terra_occ", planet.terra_occ_tex)
	if planet.extra_occ_tex:
		_mat.set_shader_parameter("u_extra_occ", planet.extra_occ_tex)

	var geoms: Array[Vector4] = []
	var voxs: Array[Vector4] = []
	var ccols: Array[Vector4] = []
	var rays: Array[Vector4] = []
	var mies: Array[Vector4] = []

	for bid in BODY_ORDER:
		var b: Dictionary = planet.bodies.get(bid, {})
		var bp: Vector2 = b.get("pos", Vector2.ZERO)
		var rad: float = float(b.get("rad", 1000.0))
		var r_core: float = float(b.get("r_core", 400.0))
		var cc: Vector4 = BODY_CORE_COL[bid]
		geoms.append(Vector4(bp.x, bp.y, rad, float(BODY_ATMOS_R[bid])))
		voxs.append(Vector4(r_core, SphericalPlanet.CELL_H, float(EXTRA_BAND_IDX[bid]), cc.w))
		ccols.append(Vector4(cc.x, cc.y, cc.z, 1.0))
		rays.append(BODY_RAYLEIGH[bid])
		mies.append(BODY_MIE[bid])

	_mat.set_shader_parameter("u_body_geom", geoms)
	_mat.set_shader_parameter("u_body_vox", voxs)
	_mat.set_shader_parameter("u_body_core_col", ccols)
	_mat.set_shader_parameter("u_body_rayleigh", rays)
	_mat.set_shader_parameter("u_body_mie", mies)

	# Gather up to 32 nearest active dynamic point lights in world space
	var l_pr: Array[Vector4] = []
	var l_cl: Array[Vector4] = []

	# 1. Player Seed Unit headlamp & thruster glow (keeps player + underground mining readable!)
	if player:
		var p_rad := 440.0 if player.get_altitude() < 260.0 else 320.0
		l_pr.append(Vector4(player.global_position.x, player.global_position.y, p_rad, 0.88))
		l_cl.append(Vector4(0.76, 0.94, 1.0, 1.0))
		if player.firing_mine and player.beam_end_world != Vector2.ZERO:
			l_pr.append(Vector4(player.beam_end_world.x, player.beam_end_world.y, 260.0, 1.05))
			l_cl.append(Vector4(0.42, 0.96, 1.0, 1.0))

	# 2. Active working planetary facilities near the camera!
	var view_r := maxf(vp.x, vp.y) / maxf(0.02, czoom) * 0.85 + 480.0
	if grid and grid.buildings.size() > 0:
		var terra_p := planet.get_terra_pos()
		for b in grid.buildings:
			if l_pr.size() >= 28:
				break
			var wp := terra_p + Vector2(b["pos"])
			if wp.distance_to(cpos) > view_r:
				continue
			var bid := String(b["id"])
			var pwr := float(b["pwr_ratio"])
			var n := Vector2(b["normal"])
			var lp := wp + n * 38.0
			if bid == "tesla" and pwr > 0.1:
				l_pr.append(Vector4(wp.x + n.x * 66.0, wp.y + n.y * 66.0, 320.0, 0.85))
				l_cl.append(Vector4(0.32, 0.92, 1.0, 1.0))
			elif bid == "smelter" and pwr > 0.1 and not b["in_buf"].is_empty():
				var flk := 0.88 + 0.14 * sin(_t * 14.0 + float(b["uid"]))
				l_pr.append(Vector4(lp.x, lp.y, 300.0, 0.95 * flk))
				l_cl.append(Vector4(1.0, 0.52, 0.14, 1.0))
			elif bid == "geothermal" and float(b.get("pipe_prog", 1.0)) >= 1.0:
				var flk := 0.90 + 0.12 * sin(_t * 9.0 + float(b["uid"]))
				l_pr.append(Vector4(lp.x, lp.y, 330.0, 0.92 * flk))
				l_cl.append(Vector4(1.0, 0.46, 0.12, 1.0))
			elif bid == "gantry_printer" and pwr > 0.1:
				l_pr.append(Vector4(wp.x + n.x * 46.0, wp.y + n.y * 46.0, 310.0, 0.78))
				l_cl.append(Vector4(0.36, 0.92, 1.0, 1.0))
			elif bid == "mass_driver" and pwr > 0.1:
				var flash := float(b.get("fire_flash", 0.0))
				l_pr.append(Vector4(wp.x + n.x * 62.0, wp.y + n.y * 62.0, 290.0 + flash * 260.0, 0.62 + flash * 1.15))
				l_cl.append(Vector4(0.46, 0.94, 1.0, 1.0))
			elif bid == "assembler" and pwr > 0.1 and not b["in_buf"].is_empty():
				l_pr.append(Vector4(lp.x, lp.y, 240.0, 0.68))
				l_cl.append(Vector4(0.42, 0.98, 0.74, 1.0))
			elif bid == "battery" and float(b["battery_kj"]) > 20.0:
				l_pr.append(Vector4(lp.x, lp.y, 200.0, 0.52))
				l_cl.append(Vector4(0.28, 0.96, 0.68, 1.0))
			elif bid == "drill" and pwr > 0.1:
				l_pr.append(Vector4(lp.x, lp.y, 210.0, 0.58))
				l_cl.append(Vector4(1.0, 0.78, 0.28, 1.0))

	# 3. Active Orbital Modules near camera
	if orbital and orbital.modules.size() > 0:
		for m in orbital.modules:
			if l_pr.size() >= 32:
				break
			var mp := Vector2(m["pos"])
			if mp.distance_to(cpos) > view_r:
				continue
			l_pr.append(Vector4(mp.x, mp.y, 260.0, 0.65))
			l_cl.append(Vector4(0.45, 0.92, 1.0, 1.0))

	var l_cnt := l_pr.size()
	while l_pr.size() < 32:
		l_pr.append(Vector4.ZERO)
		l_cl.append(Vector4.ZERO)

	_mat.set_shader_parameter("u_light_count", l_cnt)
	_mat.set_shader_parameter("u_light_pos_rad", l_pr)
	_mat.set_shader_parameter("u_light_col", l_cl)
