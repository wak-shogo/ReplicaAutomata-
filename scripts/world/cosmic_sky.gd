extends Node2D

# Deep-space cosmic backdrop: pure starry cosmos, subtle distant nebulae,
# heliocentric orbital rings, and Sun label (actual Sun photosphere/corona and
# physically-traced Rayleigh+Mie atmospheric skies are rendered by PhysAtmosphere!).

var planet: SphericalPlanet = null
var _stars: Array[Dictionary] = []
var _t: float = 0.0

func _ready() -> void:
	z_index = -100
	var rng := RandomNumberGenerator.new()
	rng.seed = 11212026
	var cols := [
		Color(0.96, 0.98, 1.0),
		Color(0.76, 0.90, 1.0),
		Color(1.0, 0.90, 0.74),
		Color(0.84, 0.76, 1.0),
	]
	for _i in range(380):
		_stars.append({
			"nx": rng.randf(),
			"ny": rng.randf(),
			"sz": rng.randf_range(1.0, 2.5),
			"ph": rng.randf_range(0.0, TAU),
			"sp": rng.randf_range(0.6, 2.0),
			"c": cols[rng.randi() % cols.size()],
			"par": rng.randf_range(0.008, 0.032),
		})

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	var vp := get_viewport_rect().size
	var cam := get_viewport().get_camera_2d()
	var cpos := cam.get_screen_center_position() if cam else Vector2.ZERO
	var z := cam.zoom.x if cam else 1.0
	var z_inv := 1.0 / maxf(0.008, z)
	var half := vp * 0.5 * z_inv
	var tl := cpos - half
	var span := half * 2.0

	# Deep vacuum space backdrop (daytime sky is painted physically over this by PhysAtmosphere!)
	var bg_col := Color(0.012, 0.016, 0.034, 1.0)
	draw_rect(Rect2(tl - Vector2(60, 60) * z_inv, span + Vector2(120, 120) * z_inv), bg_col)

	var glow := ArtReg.get_t("glow")
	if glow:
		var n1 := tl + Vector2(span.x * 0.16, span.y * 0.25)
		var r1 := span.x * 0.24
		draw_texture_rect(glow, Rect2(n1.x - r1, n1.y - r1, r1 * 2.0, r1 * 2.0), false, Color(0.24, 0.14, 0.38, 0.16))
		var n2 := tl + Vector2(span.x * 0.74, span.y * 0.20)
		var r2 := span.x * 0.22
		draw_texture_rect(glow, Rect2(n2.x - r2, n2.y - r2, r2 * 2.0, r2 * 2.0), false, Color(0.08, 0.24, 0.40, 0.16))

	# Twinkling stars (naturally masked by bright daytime Rayleigh sky on top, crisp at night & in space!)
	for s in _stars:
		var par := float(s["par"])
		var sx := tl.x + fposmod(float(s["nx"]) * span.x - cpos.x * par, span.x)
		var sy := tl.y + fposmod(float(s["ny"]) * span.y - cpos.y * par, span.y)
		var c: Color = s["c"]
		c.a = 0.58 + 0.42 * sin(_t * float(s["sp"]) + float(s["ph"]))
		var sz := float(s["sz"]) * z_inv
		draw_rect(Rect2(sx - sz * 0.5, sy - sz * 0.5, sz, sz), c)

	# Heliocentric Solar System Orbital Rings (visible when zooming out!)
	if planet and z < 0.22:
		for bid in ["ignis", "terra", "cryo", "astra"]:
			var b: Dictionary = planet.bodies[bid]
			var bc: Color = b["col"]
			bc.a = clampf((0.22 - z) / 0.14, 0.0, 1.0) * 0.28
			draw_arc(Vector2.ZERO, float(b["orbit_r"]), 0.0, TAU, 160, bc, 1.8 * z_inv)

	# Sun name label when zoomed out (fixed 16px glyph size + transform scale to avoid FreeType atlas thrash!)
	var sun_r := SphericalPlanet.SUN_RAD
	var vrect := Rect2(tl - Vector2(sun_r * 3.0, sun_r * 3.0), span + Vector2(sun_r * 6.0, sun_r * 6.0))
	if vrect.has_point(Vector2.ZERO) and z < 0.18:
		var font := ArtReg.get_font()
		draw_set_transform(Vector2(0.0, -sun_r - 22.0 * z_inv), 0.0, Vector2(z_inv, z_inv))
		draw_string(font, Vector2(-120.0, 0.0), "恒星ソラリス", HORIZONTAL_ALIGNMENT_CENTER, 240, 16, Color(1.0, 0.92, 0.58))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
