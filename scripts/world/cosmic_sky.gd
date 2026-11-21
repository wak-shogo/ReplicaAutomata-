extends Node2D

# Deep-space cosmic backdrop matching docs/art/target_gameplay_concept.jpeg:
# rich starfield, subtle purple-teal nebulae, dark-lit upper-left crescent planet,
# and distant sunlit moon on the upper right.

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
	for _i in range(320):
		_stars.append({
			"nx": rng.randf(),
			"ny": rng.randf(),
			"sz": rng.randf_range(1.0, 2.5),
			"ph": rng.randf_range(0.0, TAU),
			"sp": rng.randf_range(0.6, 2.0),
			"c": cols[rng.randi() % cols.size()],
			"par": rng.randf_range(0.01, 0.04),
		})

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	var vp := get_viewport_rect().size
	var cam := get_viewport().get_camera_2d()
	var cpos := cam.global_position if cam else Vector2.ZERO
	var z_inv := 1.0 / maxf(0.02, cam.zoom.x if cam else 1.0)
	var half := vp * 0.5 * z_inv
	var tl := cpos - half
	var span := half * 2.0

	# Deep midnight space gradient fill
	draw_rect(Rect2(tl - Vector2(40, 40), span + Vector2(80, 80)), Color(0.022, 0.030, 0.058, 1.0))

	# Subtle violet/cyan nebula haze matching concept art left sky
	var glow := ArtReg.get_t("glow")
	if glow:
		var n1 := tl + Vector2(span.x * 0.16, span.y * 0.25)
		var r1 := span.x * 0.24
		draw_texture_rect(glow, Rect2(n1.x - r1, n1.y - r1, r1 * 2.0, r1 * 2.0), false, Color(0.24, 0.14, 0.36, 0.18))
		var n2 := tl + Vector2(span.x * 0.72, span.y * 0.22)
		var r2 := span.x * 0.22
		draw_texture_rect(glow, Rect2(n2.x - r2, n2.y - r2, r2 * 2.0, r2 * 2.0), false, Color(0.08, 0.22, 0.34, 0.16))

	# Twinkling stars
	for s in _stars:
		var par := float(s["par"])
		var sx := tl.x + fposmod(float(s["nx"]) * span.x - cpos.x * par, span.x)
		var sy := tl.y + fposmod(float(s["ny"]) * span.y - cpos.y * par, span.y)
		var c: Color = s["c"]
		c.a = 0.58 + 0.42 * sin(_t * float(s["sp"]) + float(s["ph"]))
		var sz := float(s["sz"]) * z_inv
		draw_rect(Rect2(sx - sz * 0.5, sy - sz * 0.5, sz, sz), c)

	# Iconic dark crescent gas giant on upper-left sky (target_gameplay_concept.jpeg!)
	var mp := tl + Vector2(span.x * 0.22, span.y * 0.18)
	var mr := minf(span.x, span.y) * 0.135
	if glow:
		draw_texture_rect(glow, Rect2(mp.x - mr * 1.6, mp.y - mr * 1.6, mr * 3.2, mr * 3.2), false, Color(0.26, 0.40, 0.68, 0.22))
	draw_circle(mp, mr, Color(0.025, 0.036, 0.062, 0.98))
	draw_arc(mp, mr, -PI * 0.65, PI * 0.25, 48, Color(0.54, 0.72, 0.94, 0.55), 3.0 * z_inv)
	draw_arc(mp, mr * 0.98, -PI * 0.55, PI * 0.15, 48, Color(0.32, 0.48, 0.72, 0.28), 6.0 * z_inv)
