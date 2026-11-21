extends Node2D

# Deep-space starfield, subtle nebula clouds, and dramatic parallax crescent giant
# inspired by docs/art/target_gameplay_concept.jpeg.

var _stars: Array[Dictionary] = []
var _nebulae: Array[Dictionary] = []
var _t: float = 0.0

func _ready() -> void:
	z_index = -100
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261121
	var tints := [
		Color(0.95, 0.97, 1.0),
		Color(0.75, 0.90, 1.0),
		Color(1.0, 0.92, 0.78),
		Color(0.84, 0.78, 1.0),
	]
	for _i in range(280):
		_stars.append({
			"nx": rng.randf(),
			"ny": rng.randf(),
			"sz": rng.randf_range(1.0, 2.6),
			"phase": rng.randf_range(0.0, TAU),
			"spd": rng.randf_range(0.7, 2.2),
			"col": tints[rng.randi() % tints.size()],
			"par": rng.randf_range(0.012, 0.045),
		})
	for _i in range(7):
		_nebulae.append({
			"nx": rng.randf(),
			"ny": rng.randf(),
			"rad": rng.randf_range(180.0, 420.0),
			"col": Color(0.16, 0.12, 0.34, 0.14) if _i % 2 == 0 else Color(0.07, 0.20, 0.30, 0.14),
		})

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	var vp := get_viewport_rect().size
	var cam := get_viewport().get_camera_2d()
	var cpos := cam.global_position if cam else Vector2.ZERO
	var zoom_inv := (1.0 / maxf(0.02, cam.zoom.x)) if cam else 1.0
	var half := vp * 0.5 * zoom_inv
	var top_left := cpos - half
	var span := half * 2.0

	# Deep cosmic sky base
	draw_rect(Rect2(top_left - Vector2(64, 64), span + Vector2(128, 128)), Color(0.024, 0.032, 0.062, 1.0))

	# Subtle nebula bloom clouds
	var glow := ArtRegistry.get_tex("glow_soft")
	if glow:
		for nb in _nebulae:
			var px := top_left.x + fposmod(float(nb["nx"]) * span.x - cpos.x * 0.015, span.x)
			var py := top_left.y + fposmod(float(nb["ny"]) * span.y - cpos.y * 0.015, span.y)
			var r := float(nb["rad"]) * zoom_inv
			draw_texture_rect(glow, Rect2(px - r, py - r, r * 2.0, r * 2.0), false, nb["col"])

	# Crisp twinkling stars with subtle camera parallax
	for st in _stars:
		var par := float(st["par"])
		var sx := top_left.x + fposmod(float(st["nx"]) * span.x - cpos.x * par, span.x)
		var sy := top_left.y + fposmod(float(st["ny"]) * span.y - cpos.y * par, span.y)
		var tw := 0.62 + 0.38 * sin(_t * float(st["spd"]) + float(st["phase"]))
		var col: Color = st["col"]
		col.a = tw
		var sz := float(st["sz"]) * zoom_inv
		draw_rect(Rect2(sx - sz * 0.5, sy - sz * 0.5, sz, sz), col)

	# Distant dark crescent planet silhouette on upper-left sky (concept art homage!)
	var moon_pos := top_left + Vector2(span.x * 0.23, span.y * 0.24)
	var moon_r := minf(span.x, span.y) * 0.125
	if glow:
		draw_texture_rect(glow, Rect2(moon_pos.x - moon_r * 1.75, moon_pos.y - moon_r * 1.75, moon_r * 3.5, moon_r * 3.5), false, Color(0.24, 0.36, 0.62, 0.22))
	draw_circle(moon_pos, moon_r, Color(0.032, 0.045, 0.082, 0.96))
	draw_arc(moon_pos, moon_r, -PI * 0.92, -PI * 0.06, 48, Color(0.56, 0.74, 0.96, 0.55), 3.0 * zoom_inv)
	draw_arc(moon_pos, moon_r * 0.98, -PI * 0.85, -PI * 0.14, 48, Color(0.32, 0.48, 0.72, 0.30), 6.0 * zoom_inv)
