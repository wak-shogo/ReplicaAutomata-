extends Node2D

# Deep-space cosmic backdrop + Heliocentric Solar System Sun at world (0, 0),
# heliocentric planetary orbit rings, and dynamic local Day/Night sky tint.

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
	for _i in range(340):
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
	var cpos := cam.global_position if cam else Vector2.ZERO
	var z := cam.zoom.x if cam else 1.0
	var z_inv := 1.0 / maxf(0.008, z)
	var half := vp * 0.5 * z_inv
	var tl := cpos - half
	var span := half * 2.0

	# Dynamic Day/Night sky base tint when near Terra's surface
	var day_f := 0.0
	if planet:
		var atmos := planet.get_atmos_density_world(cpos)
		if atmos > 0.05 and z > 0.25:
			var sun_l := planet.get_sunlight_world(cpos)
			day_f = atmos * sun_l
	var bg_col := Color(0.020, 0.028, 0.056, 1.0).lerp(Color(0.052, 0.115, 0.220, 1.0), day_f * 0.85)
	draw_rect(Rect2(tl - Vector2(60, 60) * z_inv, span + Vector2(120, 120) * z_inv), bg_col)

	var glow := ArtReg.get_t("glow")
	if glow:
		var n1 := tl + Vector2(span.x * 0.16, span.y * 0.25)
		var r1 := span.x * 0.24
		draw_texture_rect(glow, Rect2(n1.x - r1, n1.y - r1, r1 * 2.0, r1 * 2.0), false, Color(0.24, 0.14, 0.36, 0.18 * (1.0 - day_f * 0.4)))
		var n2 := tl + Vector2(span.x * 0.74, span.y * 0.20)
		var r2 := span.x * 0.22
		draw_texture_rect(glow, Rect2(n2.x - r2, n2.y - r2, r2 * 2.0, r2 * 2.0), false, Color(0.08, 0.24, 0.38, 0.18))
		# Warm golden daylight sky glow toward the real Sun direction when inside Terra's daytime sky!
		if day_f > 0.12 and planet:
			var sdir := planet.get_sun_dir()
			var sp_sky := cpos + sdir * (minf(span.x, span.y) * 0.42)
			var sr_sky := maxf(span.x, span.y) * 0.52
			draw_texture_rect(glow, Rect2(sp_sky.x - sr_sky, sp_sky.y - sr_sky, sr_sky * 2.0, sr_sky * 2.0), false, Color(1.0, 0.78, 0.42, 0.18 * day_f))

	# Twinkling stars (subtler in bright daytime sky, brilliant at night & in space!)
	var star_vis := 1.0 - day_f * 0.45
	for s in _stars:
		var par := float(s["par"])
		var sx := tl.x + fposmod(float(s["nx"]) * span.x - cpos.x * par, span.x)
		var sy := tl.y + fposmod(float(s["ny"]) * span.y - cpos.y * par, span.y)
		var c: Color = s["c"]
		c.a = (0.58 + 0.42 * sin(_t * float(s["sp"]) + float(s["ph"]))) * star_vis
		var sz := float(s["sz"]) * z_inv
		draw_rect(Rect2(sx - sz * 0.5, sy - sz * 0.5, sz, sz), c)

	# Heliocentric Solar System Orbital Rings (visible when zooming out!)
	if planet and z < 0.22:
		for bid in ["ignis", "terra", "cryo", "astra"]:
			var b: Dictionary = planet.bodies[bid]
			var bc: Color = b["col"]
			bc.a = clampf((0.22 - z) / 0.14, 0.0, 1.0) * 0.26
			draw_arc(Vector2.ZERO, float(b["orbit_r"]), 0.0, TAU, 160, bc, 1.8 * z_inv)

	# Blazing Central SUN at World Origin (0, 0)!
	var sun_r := SphericalPlanet.SUN_RAD
	var vrect := Rect2(tl - Vector2(sun_r * 3.0, sun_r * 3.0), span + Vector2(sun_r * 6.0, sun_r * 6.0))
	if vrect.has_point(Vector2.ZERO):
		var pulse := 1.0 + sin(_t * 2.2) * 0.04
		if glow:
			var cr1 := sun_r * 3.4 * pulse
			draw_texture_rect(glow, Rect2(-cr1, -cr1, cr1 * 2.0, cr1 * 2.0), false, Color(1.0, 0.56, 0.14, 0.36))
			var cr2 := sun_r * 2.0 * pulse
			draw_texture_rect(glow, Rect2(-cr2, -cr2, cr2 * 2.0, cr2 * 2.0), false, Color(1.0, 0.84, 0.34, 0.62))
		draw_circle(Vector2.ZERO, sun_r, Color(1.0, 0.68, 0.18))
		draw_circle(Vector2.ZERO, sun_r * 0.82, Color(1.0, 0.88, 0.42))
		draw_circle(Vector2.ZERO, sun_r * 0.56, Color(1.0, 0.98, 0.82))
		draw_arc(Vector2.ZERO, sun_r * 1.02, 0.0, TAU, 96, Color(1.0, 0.94, 0.64, 0.85), maxf(16.0, 2.5 * z_inv))
		if z < 0.18:
			var font := ArtReg.get_font()
			draw_string(font, Vector2(-120.0 * z_inv, -sun_r - 22.0 * z_inv), "恒星ソラリス", HORIZONTAL_ALIGNMENT_CENTER, int(240.0 * z_inv), int(clampf(16.0 * z_inv, 14.0, 900.0)), Color(1.0, 0.92, 0.58))
