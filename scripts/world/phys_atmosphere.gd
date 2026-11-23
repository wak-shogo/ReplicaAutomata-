extends Node2D

# Renders physically-traced Rayleigh + Mie Atmospheric Scattering across all planets
# plus limb-darkened animated Solar Photosphere & Corona at world origin (0, 0).
# Placed at z_index = -50 (above CosmicSky stars, behind planets & terrain!).

var planet: SphericalPlanet = null
var _mat: ShaderMaterial = null
var _t: float = 0.0

const BODY_ORDER: Array[String] = ["terra", "luna", "ignis", "cryo", "astra"]

# Physical Rayleigh (beta_R, H_R_ratio) and Mie (beta_M_rgb, H_M_ratio) per planet
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

func _ready() -> void:
	z_index = -50
	var sh := load("res://shaders/phys_atmosphere.gdshader")
	if sh is Shader:
		_mat = ShaderMaterial.new()
		_mat.shader = sh
		material = _mat

func _process(delta: float) -> void:
	_t += delta
	if _mat and planet:
		var geoms: Array[Vector4] = []
		var rays: Array[Vector4] = []
		var mies: Array[Vector4] = []
		for bid in BODY_ORDER:
			var b: Dictionary = planet.bodies.get(bid, {})
			var bp: Vector2 = b.get("pos", Vector2.ZERO)
			var rad: float = float(b.get("rad", 1000.0))
			geoms.append(Vector4(bp.x, bp.y, rad, float(BODY_ATMOS_R[bid])))
			rays.append(BODY_RAYLEIGH[bid])
			mies.append(BODY_MIE[bid])
		_mat.set_shader_parameter("u_time", _t)
		_mat.set_shader_parameter("u_sun_rad", SphericalPlanet.SUN_RAD)
		_mat.set_shader_parameter("u_body_geom", geoms)
		_mat.set_shader_parameter("u_body_rayleigh", rays)
		_mat.set_shader_parameter("u_body_mie", mies)
	queue_redraw()

func _draw() -> void:
	var vp := get_viewport_rect().size
	var cam := get_viewport().get_camera_2d()
	var cpos := cam.get_screen_center_position() if cam else Vector2.ZERO
	var z := cam.zoom.x if cam else 1.0
	var z_inv := 1.0 / maxf(0.005, z)
	var half := vp * 0.5 * z_inv + Vector2(90.0, 90.0) * z_inv
	draw_rect(Rect2(cpos - half, half * 2.0), Color.WHITE)
