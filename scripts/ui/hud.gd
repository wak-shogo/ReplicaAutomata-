extends CanvasLayer

# AAA Minimalist Sci-Fi HUD:
# - Compact top resource strip with pixel icons
# - Fighter-Jet circular diegetic arcs (HP left, Fuel/Ion right, VEL/ALT/PWR/G) around vessel
# - Single virtual analog joystick + ABXY 2-click command tree (Build, Printer, Tech DAG, Depot 4-way UI)
# - Responsive layout for both Desktop (1280x720) and Portrait Mobile (412x915)

enum MenuState { NONE, BUILD, PRINTER, TECH, DEPOT }

var world: Node2D = null
var factory: Node2D = null
var player: Node2D = null
var swarm: Node2D = null

var menu_state: int = MenuState.NONE
var build_tab: int = 0
var build_row: int = 0
var tech_sel: int = 1
var depot_uid: int = -1
var self_destruct_armed: bool = false

# Virtual joystick & ABXY touch/mouse tracking
var joy_center: Vector2 = Vector2(118, 595)
var joy_radius: float = 64.0
var joy_vec: Vector2 = Vector2.ZERO
var joy_pointer_id: int = -1
var btn_centers: Dictionary = {} # "A", "B", "X", "Y" -> Vector2
var btn_r: float = 34.0
var hold_a_pointer: int = -1
var hold_b_pointer: int = -1
var stick_nav_cd: float = 0.0

# Clickable hit rects rebuilt every draw frame
var _hit_rects: Array[Dictionary] = []

var draw_root: Control = null

func _ready() -> void:
	layer = 20
	draw_root = Control.new()
	draw_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	draw_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	draw_root.draw.connect(_on_draw_hud)
	add_child(draw_root)

func open_depot(uid: int) -> void:
	depot_uid = uid
	menu_state = MenuState.DEPOT
	self_destruct_armed = false
	draw_root.queue_redraw()

func _hud_size() -> Vector2:
	var raw := get_viewport().get_visible_rect().size
	if raw.y > raw.x * 1.1:
		var s := clampf(raw.x / 540.0, 1.4, 2.6)
		scale = Vector2(s, s)
		return raw / s
	scale = Vector2.ONE
	return raw

func _layout_controls() -> void:
	var vp := _hud_size()
	var portrait := vp.y > vp.x * 1.1
	joy_radius = 52.0 if portrait else 62.0
	btn_r = 28.0 if portrait else 33.0
	joy_center = Vector2(joy_radius + 24.0, vp.y - joy_radius - 38.0)
	var d_sp := 50.0 if portrait else 64.0
	var d_cen := Vector2(vp.x - d_sp - btn_r - 22.0, vp.y - d_sp - btn_r - 40.0)
	btn_centers = {
		"Y": d_cen + Vector2(0, -d_sp),
		"A": d_cen + Vector2(0, d_sp),
		"X": d_cen + Vector2(-d_sp, 0),
		"B": d_cen + Vector2(d_sp, 0),
	}

func _process(delta: float) -> void:
	_layout_controls()
	if stick_nav_cd > 0.0:
		stick_nav_cd = maxf(0.0, stick_nav_cd - delta)

	# Keyboard movement + joystick synthesis
	var kb := Vector2.ZERO
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): kb.x += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):  kb.x -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):  kb.y += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):    kb.y -= 1.0
	if kb.length() > 1.0:
		kb = kb.normalized()

	var eff_stick := joy_vec if joy_vec.length() > 0.1 else kb
	if menu_state != MenuState.NONE:
		_poll_menu_nav(eff_stick)
		if player:
			player.thrust_input = Vector2.ZERO
			player.mining_active = false
	elif player:
		player.thrust_input = eff_stick
		player.braking = (hold_b_pointer != -1) or Input.is_key_pressed(KEY_SHIFT) or Input.is_key_pressed(KEY_B)
		if hold_a_pointer != -1 or Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_E):
			if GameState.selected_tool == "pick":
				player.mining_active = true
		else:
			player.mining_active = false

	draw_root.queue_redraw()

func _poll_menu_nav(s: Vector2) -> void:
	if s.length() < 0.35:
		stick_nav_cd = 0.0
		return
	if stick_nav_cd > 0.0:
		return
	stick_nav_cd = 0.28
	if menu_state == MenuState.BUILD:
		if absf(s.x) >= absf(s.y):
			build_tab = (build_tab + (1 if s.x > 0 else -1) + GameState.BUILD_CATEGORIES.size()) % GameState.BUILD_CATEGORIES.size()
			build_row = 0
			AudioSynth.play_sfx("click")
		else:
			var items: Array = GameState.BUILD_CATEGORIES[build_tab]["items"]
			build_row = (build_row + (1 if s.y > 0 else -1) + items.size()) % items.size()
			AudioSynth.play_sfx("click")
	elif menu_state == MenuState.TECH:
		var step := 1 if (s.x > 0.35 or s.y > 0.35) else -1
		tech_sel = clampi(tech_sel + step, 0, GameState.TECH_ORDER.size() - 1)
		AudioSynth.play_sfx("click")

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event.keycode)
		return

	if event is InputEventScreenTouch:
		var p: Vector2 = event.position / maxf(0.1, scale.x)
		if event.pressed:
			_handle_pointer_down(event.index, p, event.position)
		else:
			_handle_pointer_up(event.index)
	elif event is InputEventScreenDrag:
		_handle_pointer_drag(event.index, event.position / maxf(0.1, scale.x))
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var p: Vector2 = event.position / maxf(0.1, scale.x)
		if event.pressed:
			_handle_pointer_down(-10, p, event.position)
		else:
			_handle_pointer_up(-10)
	elif event is InputEventMouseMotion and joy_pointer_id == -10:
		_handle_pointer_drag(-10, event.position / maxf(0.1, scale.x))

func _handle_key(code: int) -> void:
	match code:
		KEY_T:
			menu_state = MenuState.NONE if menu_state == MenuState.TECH else MenuState.TECH
			AudioSynth.play_sfx("select")
		KEY_M:
			GameState.orbit_camera = not GameState.orbit_camera
			AudioSynth.play_sfx("click")
		KEY_TAB, KEY_X:
			_press_btn("X")
		KEY_Y:
			_press_btn("Y")
		KEY_ESCAPE:
			_press_btn("B")
		KEY_F, KEY_ENTER:
			_press_btn("A")
		KEY_F5:
			GameState.save_to_disk()
		KEY_R:
			GameState.build_dir = -GameState.build_dir
			AudioSynth.play_sfx("click")

func _handle_pointer_down(pid: int, pos: Vector2, raw_pos: Vector2) -> void:
	# 1. Check ABXY Diamond buttons first (always responsive!)
	for k in ["A", "B", "X", "Y"]:
		if pos.distance_to(btn_centers[k]) <= btn_r + 10.0:
			if k == "A": hold_a_pointer = pid
			elif k == "B": hold_b_pointer = pid
			_press_btn(k)
			get_viewport().set_input_as_handled()
			return

	# 2. Virtual Analog Joystick
	if pos.distance_to(joy_center) <= joy_radius + 34.0:
		joy_pointer_id = pid
		_update_joy(pos)
		get_viewport().set_input_as_handled()
		return

	# 3. Dynamic HUD hit rects (Tech cards, Build items, Depot buttons, Radar, Tech badge)
	for i in range(_hit_rects.size() - 1, -1, -1):
		var hr := _hit_rects[i]
		if Rect2(hr["rect"]).has_point(pos):
			_execute_hit(hr)
			get_viewport().set_input_as_handled()
			return

	# 4. World Direct Tap (only when no modal is open)
	if menu_state == MenuState.NONE and factory and player:
		var cam := get_viewport().get_camera_2d()
		if cam:
			var world_pos := cam.get_canvas_transform().affine_inverse() * raw_pos
			if factory.try_world_tap(world_pos):
				get_viewport().set_input_as_handled()

func _handle_pointer_drag(pid: int, pos: Vector2) -> void:
	if pid == joy_pointer_id:
		_update_joy(pos)
		get_viewport().set_input_as_handled()

func _handle_pointer_up(pid: int) -> void:
	if pid == joy_pointer_id:
		joy_pointer_id = -1
		joy_vec = Vector2.ZERO
		stick_nav_cd = 0.0
	if pid == hold_a_pointer:
		hold_a_pointer = -1
		if player: player.mining_active = false
	if pid == hold_b_pointer:
		hold_b_pointer = -1

func _update_joy(pos: Vector2) -> void:
	var d := pos - joy_center
	var l := d.length()
	if l > joy_radius:
		d = d / l * joy_radius
	joy_vec = d / maxf(1.0, joy_radius)
	if menu_state != MenuState.NONE:
		_poll_menu_nav(joy_vec)

func _press_btn(b: String) -> void:
	if menu_state == MenuState.NONE:
		match b:
			"A":
				if player: player.trigger_primary_press()
			"B":
				if GameState.selected_tool != "pick":
					GameState.selected_tool = "pick"
					if factory: factory.wire_pick_uid = -1
					AudioSynth.play_sfx("click")
			"X":
				menu_state = MenuState.BUILD
				AudioSynth.play_sfx("select")
			"Y":
				menu_state = MenuState.PRINTER
				self_destruct_armed = false
				AudioSynth.play_sfx("select")
		return

	if b == "B":
		menu_state = MenuState.NONE
		self_destruct_armed = false
		AudioSynth.play_sfx("click")
		return

	if menu_state == MenuState.BUILD:
		if b == "A":
			var items: Array = GameState.BUILD_CATEGORIES[build_tab]["items"]
			var pick := String(items[clampi(build_row, 0, items.size() - 1)])
			_select_build_tool(pick)
		elif b == "X":
			build_tab = (build_tab + 1) % GameState.BUILD_CATEGORIES.size()
			build_row = 0
			AudioSynth.play_sfx("click")
		elif b == "Y":
			GameState.build_dir = -GameState.build_dir
			AudioSynth.play_sfx("click")
	elif menu_state == MenuState.PRINTER:
		if b == "Y":
			if GameState.upgrade_vessel():
				menu_state = MenuState.NONE
		elif b == "X":
			GameState.craft_drone()
		elif b == "A":
			menu_state = MenuState.TECH
			AudioSynth.play_sfx("select")
	elif menu_state == MenuState.TECH:
		if b == "A":
			var tid := GameState.TECH_ORDER[clampi(tech_sel, 0, GameState.TECH_ORDER.size() - 1)]
			GameState.research_tech(tid)
		elif b == "X":
			tech_sel = (tech_sel + 1) % GameState.TECH_ORDER.size()
			AudioSynth.play_sfx("click")
		elif b == "Y":
			tech_sel = (tech_sel - 1 + GameState.TECH_ORDER.size()) % GameState.TECH_ORDER.size()
			AudioSynth.play_sfx("click")

func _select_build_tool(tool_id: String) -> void:
	if not GameState.is_building_unlocked(tool_id):
		AudioSynth.play_sfx("error")
		GameState.add_log("Unlock required Tech first!", "warn")
		return
	GameState.selected_tool = tool_id
	menu_state = MenuState.NONE
	AudioSynth.play_sfx("select")
	if factory: factory.refresh_blueprints()

func _execute_hit(hr: Dictionary) -> void:
	var act := String(hr["act"])
	match act:
		"toggle_orbit":
			GameState.orbit_camera = not GameState.orbit_camera
			AudioSynth.play_sfx("click")
		"open_tech":
			menu_state = MenuState.NONE if menu_state == MenuState.TECH else MenuState.TECH
			AudioSynth.play_sfx("select")
		"close_menu":
			menu_state = MenuState.NONE
			self_destruct_armed = false
			AudioSynth.play_sfx("click")
		"build_tab":
			build_tab = int(hr["val"])
			build_row = 0
			AudioSynth.play_sfx("click")
		"build_pick":
			_select_build_tool(String(hr["val"]))
		"tech_sel":
			tech_sel = int(hr["val"])
			AudioSynth.play_sfx("click")
		"tech_research":
			GameState.research_tech(String(hr["val"]))
		"upgrade_vessel":
			if GameState.upgrade_vessel():
				menu_state = MenuState.NONE
		"craft_drone":
			GameState.craft_drone()
		"set_doctrine":
			GameState.doctrine = int(hr["val"])
			AudioSynth.play_sfx("select")
		"build_mega":
			GameState.build_megastructure(String(hr["val"]))
		"toggle_mute":
			AudioSynth.muted = not AudioSynth.muted
		"self_destruct":
			if not self_destruct_armed:
				self_destruct_armed = true
				AudioSynth.play_sfx("alert")
			else:
				self_destruct_armed = false
				menu_state = MenuState.NONE
				if player: player.self_destruct_respawn()
		"depot_deposit_all":
			if factory: factory.depot_deposit_all(depot_uid)
		"depot_filter":
			if factory: factory.depot_cycle_filter(depot_uid, String(hr["val"]))
		"depot_take":
			if factory: factory.depot_transfer(depot_uid, String(hr["val"]), false, 5)

# ------------------------------------------------------------------------------
# CHAMFERED SCI-FI PANEL DRAWING HELPERS
# ------------------------------------------------------------------------------
func _chamfer_poly(r: Rect2, c: float = 10.0) -> PackedVector2Array:
	var x0 := r.position.x; var y0 := r.position.y
	var x1 := r.end.x; var y1 := r.end.y
	return PackedVector2Array([
		Vector2(x0 + c, y0), Vector2(x1 - c, y0),
		Vector2(x1, y0 + c), Vector2(x1, y1 - c),
		Vector2(x1 - c, y1), Vector2(x0 + c, y1),
		Vector2(x0, y1 - c), Vector2(x0, y0 + c),
	])

func _draw_panel(r: Rect2, bg: Color, border: Color, cut: float = 10.0, bw: float = 1.6) -> void:
	var poly := _chamfer_poly(r, cut)
	draw_root.draw_polygon(poly, PackedColorArray([bg]))
	var closed := PackedVector2Array(poly)
	closed.append(poly[0])
	draw_root.draw_polyline(closed, border, bw)

func _add_hit(r: Rect2, act: String, val = null) -> void:
	_hit_rects.append({"rect": r, "act": act, "val": val})

# ------------------------------------------------------------------------------
# MASTER HUD DRAW CALL
# ------------------------------------------------------------------------------
func _on_draw_hud() -> void:
	if btn_centers.is_empty():
		_layout_controls()
	_hit_rects.clear()
	var vp := _hud_size()
	var portrait := vp.y > vp.x * 1.1
	var font := ThemeDB.fallback_font

	_draw_fighter_craft_hud(vp, font)
	_draw_top_bar(vp, portrait, font)
	_draw_radar_and_tech_badge(vp, portrait, font)
	_draw_logs(vp, portrait, font)

	match menu_state:
		MenuState.BUILD:   _draw_build_menu(vp, portrait, font)
		MenuState.PRINTER: _draw_printer_menu(vp, portrait, font)
		MenuState.TECH:    _draw_tech_tree(vp, portrait, font)
		MenuState.DEPOT:   _draw_depot_modal(vp, portrait, font)

	_draw_joystick_and_abxy(font)

	if GameState.game_won:
		var vr := Rect2(vp.x * 0.5 - 220, 128, 440, 52)
		_draw_panel(vr, Color(0.06, 0.22, 0.16, 0.92), Color(0.32, 1.0, 0.72), 12.0, 2.2)
		draw_root.draw_string(font, Vector2(vr.position.x, vr.position.y + 33), "VICTORY: SECTOR LIBERATED & WARP GATE ONLINE!", HORIZONTAL_ALIGNMENT_CENTER, vr.size.x, 15, Color(0.85, 1.0, 0.92))

# ------------------------------------------------------------------------------
# 1. FIGHTER-JET DIEGETIC CIRCULAR CRAFT HUD
# ------------------------------------------------------------------------------
func _draw_fighter_craft_hud(vp: Vector2, font: Font) -> void:
	if not player or GameState.orbit_camera:
		return
	var cam := get_viewport().get_camera_2d()
	if not cam:
		return
	var sp := (cam.get_canvas_transform() * player.global_position) / maxf(0.1, scale.x)
	if not Rect2(Vector2(-80, -80), vp + Vector2(160, 160)).has_point(sp):
		return

	var rad := 56.0
	var hp_f := clampf(GameState.hp / maxf(1.0, GameState.max_hp), 0.0, 1.0)
	var fuel_f := clampf(GameState.fuel / maxf(1.0, GameState.max_fuel), 0.0, 1.0)
	var ion_f := clampf(GameState.ion_battery / maxf(1.0, GameState.max_ion_battery), 0.0, 1.0)

	# Left Arc: HP / Integrity (130 deg .. 230 deg)
	var a_l0 := deg_to_rad(132.0); var a_l1 := deg_to_rad(228.0)
	draw_root.draw_arc(sp, rad, a_l0, a_l1, 24, Color(0.14, 0.22, 0.30, 0.55), 5.0)
	var hp_col := Color(0.28, 0.94, 0.58, 0.92) if hp_f > 0.4 else Color(1.0, 0.38, 0.32, 0.95)
	draw_root.draw_arc(sp, rad, a_l0, lerpf(a_l0, a_l1, hp_f), 24, hp_col, 4.5)

	# Right Outer Arc: Chemical Rocket Fuel (-48 deg .. +48 deg)
	var a_r0 := deg_to_rad(48.0); var a_r1 := deg_to_rad(-48.0)
	draw_root.draw_arc(sp, rad, a_r1, a_r0, 24, Color(0.14, 0.22, 0.30, 0.55), 5.0)
	if fuel_f > 0.01:
		draw_root.draw_arc(sp, rad, lerpf(a_r0, a_r1, fuel_f), a_r0, 24, Color(1.0, 0.72, 0.22, 0.92), 4.5)

	# Right Inner Arc: Electric Ion Backup Battery
	draw_root.draw_arc(sp, rad - 8.0, a_r1, a_r0, 20, Color(0.10, 0.22, 0.32, 0.45), 2.8)
	if ion_f > 0.01:
		draw_root.draw_arc(sp, rad - 8.0, lerpf(a_r0, a_r1, ion_f), a_r0, 20, Color(0.32, 0.94, 1.0, 0.92), 2.8)

	# Crisp Jet-Fighter Numeric Readouts beside the arcs
	var vel_i := int(round(player.velocity.length()))
	var alt_i := int(round(player.get_altitude()))
	var net_w := int(round(GameState.power_prod - GameState.power_use))
	var alt_str := "ALT %dm" % alt_i if alt_i >= 0 else "DPT %dm" % alt_i
	var pwr_str := "PWR %+dW" % net_w if GameState.power_prod > 0.1 or GameState.power_use > 0.1 else "ION %d%%" % int(ion_f * 100.0)

	draw_root.draw_string(font, sp + Vector2(-rad - 78, -4), "HP %d" % int(GameState.hp), HORIZONTAL_ALIGNMENT_RIGHT, 70, 12, hp_col)
	draw_root.draw_string(font, sp + Vector2(-rad - 78, 12), pwr_str, HORIZONTAL_ALIGNMENT_RIGHT, 70, 11, Color(0.42, 0.92, 1.0))
	draw_root.draw_string(font, sp + Vector2(rad + 10, -4), "V %d" % vel_i, HORIZONTAL_ALIGNMENT_LEFT, 80, 12, Color(0.92, 0.96, 1.0))
	draw_root.draw_string(font, sp + Vector2(rad + 10, 12), alt_str, HORIZONTAL_ALIGNMENT_LEFT, 90, 11, Color(0.82, 0.88, 0.96))
	draw_root.draw_string(font, sp + Vector2(rad + 10, 26), "%.2fG" % player.local_grav_g, HORIZONTAL_ALIGNMENT_LEFT, 70, 10, Color(0.62, 0.76, 0.88))

	# Velocity vector chevron
	if player.velocity.length() > 28.0:
		var vd: Vector2 = Vector2(player.velocity).normalized()
		var vp_p: Vector2 = sp + vd * (rad + 12.0)
		draw_root.draw_circle(vp_p, 3.2, Color(0.45, 0.98, 1.0, 0.85))

# ------------------------------------------------------------------------------
# 2. TOP COMPACT TELEMETRY STRIP
# ------------------------------------------------------------------------------
func _draw_top_bar(vp: Vector2, portrait: bool, font: Font) -> void:
	var bar_w := minf(vp.x - 122.0, 560.0) if not portrait else (vp.x - 108.0)
	var bar_h := 88.0 if portrait else 82.0
	var r := Rect2(12, 10, bar_w, bar_h)
	_draw_panel(r, Color(0.04, 0.06, 0.11, 0.86), Color(0.24, 0.56, 0.82, 0.78), 10.0)

	# Row 1: Compact Resource Icons & Counts
	var items: Array[String] = ["fe", "cu", "si", "ti", "plate_fe", "wire_cu", "wafer_si", "circuit"]
	var step_x := (bar_w - 20.0) / float(items.size())
	var y_ic := r.position.y + 12.0
	for i in range(items.size()):
		var id: String = items[i]
		var x := r.position.x + 12.0 + float(i) * step_x
		var ic := ArtRegistry.get_item_icon(id)
		if ic:
			draw_root.draw_texture_rect(ic, Rect2(x, y_ic, 16, 16), false)
		draw_root.draw_string(font, Vector2(x + 19, y_ic + 13), str(GameState.get_res(id)), HORIZONTAL_ALIGNMENT_LEFT, int(step_x - 18), 12 if portrait else 13, Color(0.94, 0.97, 1.0))

	# Row 2: Wired Local Power Grid + Night Battery + Swarm Fleet + Drones
	var pwr_col := Color(0.32, 0.96, 0.68) if (GameState.power_prod >= GameState.power_use and GameState.power_prod > 0.0) else (Color(0.98, 0.78, 0.32) if GameState.power_stored > 10.0 else Color(0.98, 0.42, 0.36))
	var bat_pct := int(round(GameState.power_stored / maxf(1.0, GameState.power_cap) * 100.0)) if GameState.power_cap > 1.0 else 0
	var y_r2 := r.position.y + 49.0
	draw_root.draw_string(font, Vector2(r.position.x + 12, y_r2), "PWR %d/%dW" % [int(round(GameState.power_prod)), int(round(GameState.power_use))], HORIZONTAL_ALIGNMENT_LEFT, 120, 12, pwr_col)
	draw_root.draw_string(font, Vector2(r.position.x + 126, y_r2), "BAT:%d%%" % bat_pct if GameState.power_cap > 1.0 else "WIRE:%d" % GameState.wire_count, HORIZONTAL_ALIGNMENT_LEFT, 85, 12, Color(0.42, 0.92, 1.0))
	draw_root.draw_string(font, Vector2(r.position.x + 212, y_r2), "FLEET:%d" % GameState.swarm_fleet, HORIZONTAL_ALIGNMENT_LEFT, 100, 12, Color(1.0, 0.84, 0.36))
	if not portrait:
		draw_root.draw_string(font, Vector2(r.position.x + 318, y_r2), "DRN:%d" % GameState.drones, HORIZONTAL_ALIGNMENT_LEFT, 70, 12, Color(0.95, 0.72, 0.34))

	# Row 3: Active Tool & Vessel Tier
	var tier_short := String(GameState.VESSEL_TIERS[GameState.vessel_tier]["short"])
	var tool_lbl := "MINE/ACT" if GameState.selected_tool == "pick" else GameState.selected_tool.to_upper()
	draw_root.draw_string(font, Vector2(r.position.x + 12, r.position.y + 72.0), "%s | %s | DIR:%s" % [tool_lbl, tier_short, "CW" if GameState.build_dir > 0 else "CCW"], HORIZONTAL_ALIGNMENT_LEFT, int(bar_w - 24), 11, Color(0.68, 0.82, 0.96))

# ------------------------------------------------------------------------------
# 3. TOP-RIGHT ORBITAL RADAR & TECH TREE BADGE
# ------------------------------------------------------------------------------
func _draw_radar_and_tech_badge(vp: Vector2, portrait: bool, font: Font) -> void:
	var rr := 36.0 if portrait else 42.0
	var rc := Vector2(vp.x - rr - 14.0, rr + 12.0)
	draw_root.draw_circle(rc, rr, Color(0.03, 0.05, 0.09, 0.88))
	draw_root.draw_arc(rc, rr, 0.0, TAU, 36, Color(0.32, 0.74, 1.0, 0.78), 1.8)
	# Origin planet disc in radar center
	var sc := (rr - 6.0) / 26000.0
	draw_root.draw_circle(rc, PlanetWorld.R_SURFACE * sc, Color(0.36, 0.56, 0.78, 0.75))
	if world:
		for m in world.moons:
			draw_root.draw_circle(rc + Vector2(m["pos"]) * sc, 2.5, Color(0.85, 0.88, 1.0))
	if swarm and not GameState.boss_defeated:
		draw_root.draw_circle(rc + swarm.boss_pos * sc, 3.2, Color(1.0, 0.28, 0.34))
	if player:
		draw_root.draw_circle(rc + player.position * sc, 3.0, Color(0.32, 1.0, 0.68))
	_add_hit(Rect2(rc - Vector2(rr, rr), Vector2(rr * 2.0, rr * 2.0)), "toggle_orbit")

	# Tech Badge right below radar (glows amber when a tech can be researched!)
	var ready_tech := false
	for tid in GameState.TECH_ORDER:
		if GameState.can_research(tid):
			ready_tech = true
			break
	var tw := 88.0 if portrait else 102.0
	var tr := Rect2(vp.x - tw - 10.0, rc.y + rr + 8.0, tw, 28.0)
	var tb_col := Color(1.0, 0.74, 0.24) if ready_tech else Color(0.32, 0.78, 1.0)
	_draw_panel(tr, Color(0.05, 0.08, 0.14, 0.90), tb_col, 6.0, 1.8)
	draw_root.draw_string(font, Vector2(tr.position.x, tr.position.y + 19.0), "TECH %d/%d [T]" % [GameState.unlocked_techs.size(), GameState.TECH_ORDER.size()], HORIZONTAL_ALIGNMENT_CENTER, tr.size.x, 11 if portrait else 12, Color(0.95, 0.98, 1.0))
	_add_hit(tr, "open_tech")

func _draw_logs(vp: Vector2, portrait: bool, font: Font) -> void:
	if menu_state != MenuState.NONE or GameState.logs.is_empty():
		return
	var y := 108.0 if portrait else 104.0
	var start_i := maxi(0, GameState.logs.size() - 3)
	for i in range(start_i, GameState.logs.size()):
		var entry := GameState.logs[i]
		var col := Color(0.45, 0.96, 0.72) if entry["kind"] == "good" else (Color(1.0, 0.78, 0.36) if entry["kind"] == "warn" else Color(0.75, 0.86, 0.96))
		draw_root.draw_string(font, Vector2(16, y), "> " + String(entry["msg"]), HORIZONTAL_ALIGNMENT_LEFT, int(vp.x - 130.0), 11, col)
		y += 16.0

# ------------------------------------------------------------------------------
# 4. 2-CLICK BUILD MENU ([X])
# ------------------------------------------------------------------------------
func _draw_build_menu(vp: Vector2, portrait: bool, font: Font) -> void:
	var mw := minf(vp.x - 28.0, 540.0)
	var mh := 340.0
	var r := Rect2((vp.x - mw) * 0.5, 108.0, mw, mh)
	_draw_panel(r, Color(0.04, 0.06, 0.12, 0.95), Color(0.32, 0.86, 1.0), 12.0, 2.0)

	# Category tabs
	var tab_w := (mw - 24.0) / float(GameState.BUILD_CATEGORIES.size())
	for i in range(GameState.BUILD_CATEGORIES.size()):
		var tr := Rect2(r.position.x + 12.0 + float(i) * tab_w, r.position.y + 12.0, tab_w - 6.0, 30.0)
		var sel := (i == build_tab)
		_draw_panel(tr, Color(0.10, 0.24, 0.36, 0.95) if sel else Color(0.06, 0.09, 0.16, 0.85), Color(0.42, 0.96, 1.0) if sel else Color(0.24, 0.38, 0.52), 6.0)
		draw_root.draw_string(font, Vector2(tr.position.x, tr.position.y + 20.0), String(GameState.BUILD_CATEGORIES[i]["label"]), HORIZONTAL_ALIGNMENT_CENTER, tr.size.x, 12, Color.WHITE if sel else Color(0.72, 0.82, 0.92))
		_add_hit(tr, "build_tab", i)

	# Items in active category
	var items: Array = GameState.BUILD_CATEGORIES[build_tab]["items"]
	var y := r.position.y + 52.0
	for i in range(items.size()):
		var id := String(items[i])
		var ir := Rect2(r.position.x + 14.0, y, mw - 28.0, 42.0)
		var unlocked := GameState.is_building_unlocked(id)
		var sel := (i == build_row)
		var bg := Color(0.10, 0.20, 0.32, 0.92) if sel else Color(0.06, 0.09, 0.15, 0.86)
		var bd := Color(0.38, 0.96, 1.0) if (sel and unlocked) else (Color(0.24, 0.42, 0.56) if unlocked else Color(0.45, 0.24, 0.26))
		_draw_panel(ir, bg, bd, 6.0, 1.8 if sel else 1.2)

		var title := "Power Wire (Tap Solar <-> Tesla)" if id == "wire" else ("Salvage / Demolish" if id == "demolish" else String(GameState.BUILDINGS[id]["name"]))
		var cost_str := ""
		if GameState.BUILDINGS.has(id):
			var c: Dictionary = GameState.BUILDINGS[id]["cost"]
			var parts: Array[String] = []
			for ck in c.keys():
				parts.append("%s:%d" % [String(ck).to_upper(), int(c[ck])])
			cost_str = " | ".join(parts)
		var sub := cost_str if unlocked else "LOCKED (Research Tech Tree [T])"
		if id == "wire" and unlocked: sub = "Free cable - links Solar/Battery/Geo to Tesla"
		elif id == "demolish": sub = "Refunds 50% materials"

		draw_root.draw_string(font, Vector2(ir.position.x + 12, ir.position.y + 18), title, HORIZONTAL_ALIGNMENT_LEFT, int(ir.size.x - 24), 13, Color.WHITE if unlocked else Color(0.55, 0.58, 0.65))
		draw_root.draw_string(font, Vector2(ir.position.x + 12, ir.position.y + 34), sub, HORIZONTAL_ALIGNMENT_LEFT, int(ir.size.x - 24), 10 if portrait else 11, Color(0.58, 0.90, 0.78) if unlocked else Color(0.95, 0.48, 0.44))
		_add_hit(ir, "build_pick", id)
		y += 46.0

# ------------------------------------------------------------------------------
# 5. 2-CLICK ONBOARD 3D PRINTER & COMMAND MENU ([Y])
# ------------------------------------------------------------------------------
func _draw_printer_menu(vp: Vector2, portrait: bool, font: Font) -> void:
	var mw := minf(vp.x - 28.0, 560.0)
	var mh := 390.0 if portrait else 360.0
	var r := Rect2((vp.x - mw) * 0.5, 108.0, mw, mh)
	_draw_panel(r, Color(0.04, 0.06, 0.12, 0.95), Color(1.0, 0.78, 0.30), 12.0, 2.0)
	draw_root.draw_string(font, Vector2(r.position.x + 16, r.position.y + 24), "ONBOARD 3D PRINTER // VESSEL & SWARM COMMAND", HORIZONTAL_ALIGNMENT_LEFT, int(mw - 86), 13, Color(1.0, 0.86, 0.45))

	var close_r := Rect2(r.end.x - 68, r.position.y + 8, 58, 24)
	_draw_panel(close_r, Color(0.28, 0.08, 0.10, 0.9), Color(1.0, 0.42, 0.42), 5.0)
	draw_root.draw_string(font, Vector2(close_r.position.x, close_r.position.y + 16), "CLOSE", HORIZONTAL_ALIGNMENT_CENTER, close_r.size.x, 11, Color.WHITE)
	_add_hit(close_r, "close_menu")

	var y := r.position.y + 42.0
	# Slot 1 [Y]: Print Next Vessel Evolution Module
	var nxt := GameState.vessel_tier + 1
	var r1 := Rect2(r.position.x + 14, y, mw - 28, 52)
	var can_up := GameState.can_upgrade_vessel()
	_draw_panel(r1, Color(0.08, 0.22, 0.20, 0.92) if can_up else Color(0.07, 0.09, 0.15, 0.90), Color(0.36, 1.0, 0.72) if can_up else Color(0.32, 0.40, 0.52), 8.0)
	if GameState.VESSEL_TIERS.has(nxt):
		var ti: Dictionary = GameState.VESSEL_TIERS[nxt]
		var cs: Array[String] = []
		for ck in ti["cost"].keys(): cs.append("%s:%d" % [String(ck).to_upper(), int(ti["cost"][ck])])
		draw_root.draw_string(font, Vector2(r1.position.x + 12, r1.position.y + 20), "[Y] PRINT %s" % String(ti["name"]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, int(r1.size.x - 24), 13, Color.WHITE)
		draw_root.draw_string(font, Vector2(r1.position.x + 12, r1.position.y + 39), "Cost: %s  (Req: %s)" % [" ".join(cs), String(ti["req_tech"])], HORIZONTAL_ALIGNMENT_LEFT, int(r1.size.x - 24), 11, Color(0.55, 0.95, 0.80) if can_up else Color(0.85, 0.65, 0.55))
		_add_hit(r1, "upgrade_vessel")
	else:
		draw_root.draw_string(font, Vector2(r1.position.x + 12, r1.position.y + 30), "VESSEL AT MAX EVOLUTION (WARP MK-III)", HORIZONTAL_ALIGNMENT_LEFT, int(r1.size.x - 24), 13, Color(0.45, 1.0, 0.78))
	y += 60.0

	# Slot 2 [X]: Craft Fabricator Drone
	var r2 := Rect2(r.position.x + 14, y, mw - 28, 44)
	var can_dr := GameState.drones < GameState.MAX_DRONES and GameState.can_afford(GameState.DRONE_COST)
	_draw_panel(r2, Color(0.08, 0.16, 0.26, 0.92) if can_dr else Color(0.07, 0.09, 0.15, 0.90), Color(0.38, 0.90, 1.0) if can_dr else Color(0.28, 0.36, 0.48), 8.0)
	draw_root.draw_string(font, Vector2(r2.position.x + 12, r2.position.y + 27), "[X] CRAFT FABRICATOR DRONE (%d/%d)  -  FE:12 CU:6" % [GameState.drones, GameState.MAX_DRONES], HORIZONTAL_ALIGNMENT_LEFT, int(r2.size.x - 24), 12, Color.WHITE)
	_add_hit(r2, "craft_drone")
	y += 52.0

	# Slot 3: Swarm Fleet Doctrines (4 compact buttons)
	draw_root.draw_string(font, Vector2(r.position.x + 16, y + 12), "SWARM FLEET DOCTRINE:", HORIZONTAL_ALIGNMENT_LEFT, 200, 11, Color(0.70, 0.84, 0.96))
	y += 18.0
	var doc_names := ["HARVEST", "REPLICATE", "DEFEND", "ASSAULT"]
	var dw := (mw - 28.0) / 4.0
	for i in range(4):
		var dr := Rect2(r.position.x + 14 + float(i) * dw, y, dw - 6, 30)
		var on := (GameState.doctrine == i)
		_draw_panel(dr, Color(0.14, 0.28, 0.42, 0.95) if on else Color(0.06, 0.09, 0.15, 0.9), Color(1.0, 0.82, 0.32) if on else Color(0.28, 0.40, 0.54), 5.0)
		draw_root.draw_string(font, Vector2(dr.position.x, dr.position.y + 20), doc_names[i], HORIZONTAL_ALIGNMENT_CENTER, dr.size.x, 11, Color.WHITE if on else Color(0.72, 0.80, 0.90))
		_add_hit(dr, "set_doctrine", i)
	y += 38.0

	# Slot 4: Megastructures (4 compact buttons)
	draw_root.draw_string(font, Vector2(r.position.x + 16, y + 12), "ORBITAL MEGASTRUCTURES (Req: Megastructures Tech):", HORIZONTAL_ALIGNMENT_LEFT, int(mw - 32), 11, Color(0.70, 0.84, 0.96))
	y += 18.0
	var mids: Array[String] = ["elevator", "dyson", "citadel", "warpgate"]
	var mw_b := (mw - 28.0) / 2.0
	for i in range(4):
		var mid: String = mids[i]
		var built := bool(GameState.megastructures.get(mid, false))
		var bx := r.position.x + 14 + float(i % 2) * mw_b
		var by := y + float(i / 2) * 34.0
		var mr := Rect2(bx, by, mw_b - 6, 28)
		_draw_panel(mr, Color(0.08, 0.26, 0.18, 0.9) if built else Color(0.07, 0.10, 0.16, 0.9), Color(0.36, 1.0, 0.68) if built else Color(0.34, 0.46, 0.62), 5.0)
		var lbl := String(GameState.MEGA_DEFS[mid]["name"]) + (" [OK]" if built else "")
		draw_root.draw_string(font, Vector2(mr.position.x, mr.position.y + 19), lbl, HORIZONTAL_ALIGNMENT_CENTER, mr.size.x, 11, Color.WHITE)
		_add_hit(mr, "build_mega", mid)
	y += 76.0

	# Bottom System Row: Tech Tree [A], Audio Toggle, Anti-Softlock Self-Destruct Re-Drop
	var sw_b := (mw - 28.0) / 3.0
	var b_tech := Rect2(r.position.x + 14, y, sw_b - 6, 32)
	_draw_panel(b_tech, Color(0.08, 0.18, 0.30, 0.92), Color(0.38, 0.92, 1.0), 6.0)
	draw_root.draw_string(font, Vector2(b_tech.position.x, b_tech.position.y + 21), "[A] TECH TREE", HORIZONTAL_ALIGNMENT_CENTER, b_tech.size.x, 11, Color.WHITE)
	_add_hit(b_tech, "open_tech")

	var b_snd := Rect2(r.position.x + 14 + sw_b, y, sw_b - 6, 32)
	_draw_panel(b_snd, Color(0.07, 0.12, 0.20, 0.92), Color(0.45, 0.64, 0.82), 6.0)
	draw_root.draw_string(font, Vector2(b_snd.position.x, b_snd.position.y + 21), "AUDIO: " + ("OFF" if AudioSynth.muted else "ON"), HORIZONTAL_ALIGNMENT_CENTER, b_snd.size.x, 11, Color.WHITE)
	_add_hit(b_snd, "toggle_mute")

	var b_sd := Rect2(r.position.x + 14 + sw_b * 2.0, y, sw_b - 6, 32)
	_draw_panel(b_sd, Color(0.36, 0.08, 0.10, 0.95) if self_destruct_armed else Color(0.20, 0.08, 0.10, 0.90), Color(1.0, 0.38, 0.36), 6.0)
	draw_root.draw_string(font, Vector2(b_sd.position.x, b_sd.position.y + 21), "CONFIRM RE-DROP!" if self_destruct_armed else "RE-DROP CAPSULE", HORIZONTAL_ALIGNMENT_CENTER, b_sd.size.x, 10, Color(1.0, 0.85, 0.85))
	_add_hit(b_sd, "self_destruct")

# ------------------------------------------------------------------------------
# 6. FACTORIO-STYLE TECH TREE DAG ([T])
# ------------------------------------------------------------------------------
func _draw_tech_tree(vp: Vector2, portrait: bool, font: Font) -> void:
	# Keep completely clear of Left Joystick & Right ABXY Diamond on both Desktop and Portrait Mobile!
	var r := Rect2(12.0, 104.0, vp.x - 24.0, vp.y - 285.0) if portrait else Rect2(176.0, 98.0, vp.x - 418.0, vp.y - 122.0)
	_draw_panel(r, Color(0.03, 0.05, 0.10, 0.96), Color(0.32, 0.86, 1.0), 14.0, 2.0)
	draw_root.draw_string(font, Vector2(r.position.x + 16, r.position.y + 24), "COLONY RESEARCH LAB // TECH TREE DAG", HORIZONTAL_ALIGNMENT_LEFT, int(r.size.x - 95), 14 if not portrait else 12, Color(0.45, 0.96, 1.0))

	var close_r := Rect2(r.end.x - 74, r.position.y + 8, 62, 24)
	_draw_panel(close_r, Color(0.28, 0.08, 0.10, 0.92), Color(1.0, 0.42, 0.42), 5.0)
	draw_root.draw_string(font, Vector2(close_r.position.x, close_r.position.y + 16), "CLOSE", HORIZONTAL_ALIGNMENT_CENTER, close_r.size.x, 11, Color.WHITE)
	_add_hit(close_r, "close_menu")

	# Compute node card rects (2-col vertical DAG on portrait, 6-col horizontal DAG on desktop)
	var card_rects: Dictionary = {}
	var detail_h := 122.0 if portrait else 112.0
	var graph_h := r.size.y - detail_h - 46.0
	if portrait:
		var cw := (r.size.x - 36.0) * 0.5
		var ch := clampf((graph_h - 32.0) / 4.0, 44.0, 62.0)
		for i in range(GameState.TECH_ORDER.size()):
			var tid := GameState.TECH_ORDER[i]
			var cx := r.position.x + 14.0 + float(i % 2) * (cw + 8.0)
			var cy := r.position.y + 40.0 + float(i / 2) * (ch + 8.0)
			card_rects[tid] = Rect2(cx, cy, cw, ch)
	else:
		var cw := (r.size.x - 80.0) / 6.0
		var ch := 66.0
		var row_sp := graph_h / 3.0
		for i in range(GameState.TECH_ORDER.size()):
			var tid := GameState.TECH_ORDER[i]
			var t: Dictionary = GameState.TECH_TREE[tid]
			var cx := r.position.x + 18.0 + float(int(t["col"])) * (cw + 9.0)
			var cy := r.position.y + 42.0 + float(int(t["row"])) * row_sp
			card_rects[tid] = Rect2(cx, cy, cw, ch)

	# Draw DAG dependency connector lines first
	for tid in GameState.TECH_ORDER:
		var t: Dictionary = GameState.TECH_TREE[tid]
		var dst: Rect2 = card_rects[tid]
		for req in t["req"]:
			if card_rects.has(req):
				var src: Rect2 = card_rects[req]
				var unlocked := GameState.has_tech(tid)
				var col := Color(0.32, 0.96, 0.68, 0.85) if unlocked else Color(0.30, 0.46, 0.64, 0.55)
				draw_root.draw_line(src.get_center(), dst.get_center(), col, 2.2)

	# Draw each Tech Node card
	for i in range(GameState.TECH_ORDER.size()):
		var tid := GameState.TECH_ORDER[i]
		var t: Dictionary = GameState.TECH_TREE[tid]
		var cr: Rect2 = card_rects[tid]
		var done := GameState.has_tech(tid)
		var avail := GameState.can_research(tid)
		var sel := (i == tech_sel)
		var bg := Color(0.06, 0.22, 0.16, 0.95) if done else (Color(0.10, 0.20, 0.34, 0.95) if sel else Color(0.06, 0.09, 0.15, 0.92))
		var bd := Color(0.36, 1.0, 0.72) if done else (Color(1.0, 0.82, 0.32) if avail else (Color(0.42, 0.94, 1.0) if sel else Color(0.26, 0.34, 0.46)))
		_draw_panel(cr, bg, bd, 7.0, 2.4 if sel else 1.4)
		draw_root.draw_string(font, Vector2(cr.position.x + 8, cr.position.y + 22), String(t["name"]), HORIZONTAL_ALIGNMENT_LEFT, int(cr.size.x - 16), 11 if portrait else 12, Color.WHITE)
		var st := "UNLOCKED" if done else ("READY!" if avail else "LOCKED")
		var st_col := Color(0.42, 1.0, 0.72) if done else (Color(1.0, 0.84, 0.34) if avail else Color(0.55, 0.64, 0.76))
		draw_root.draw_string(font, Vector2(cr.position.x + 8, cr.position.y + cr.size.y - 10), st, HORIZONTAL_ALIGNMENT_LEFT, int(cr.size.x - 16), 10, st_col)
		_add_hit(cr, "tech_sel", i)

	# Detail Inspector Card at Bottom
	var sel_id := GameState.TECH_ORDER[clampi(tech_sel, 0, GameState.TECH_ORDER.size() - 1)]
	var st_d: Dictionary = GameState.TECH_TREE[sel_id]
	var dr := Rect2(r.position.x + 12.0, r.end.y - detail_h - 10.0, r.size.x - 24.0, detail_h)
	_draw_panel(dr, Color(0.05, 0.08, 0.15, 0.96), Color(0.34, 0.78, 1.0), 8.0)

	var btn_w := 126.0 if portrait else 168.0
	var txt_w := int(dr.size.x - btn_w - 28.0)
	draw_root.draw_string(font, Vector2(dr.position.x + 12, dr.position.y + 22), "%s  |  Unlocks: %s" % [String(st_d["name"]).to_upper(), ", ".join(st_d["unlocks"])], HORIZONTAL_ALIGNMENT_LEFT, txt_w, 12, Color(0.45, 0.96, 1.0))
	draw_root.draw_string(font, Vector2(dr.position.x + 12, dr.position.y + 44), String(st_d["summary"]), HORIZONTAL_ALIGNMENT_LEFT, txt_w, 11, Color(0.92, 0.95, 1.0))
	draw_root.draw_string(font, Vector2(dr.position.x + 12, dr.position.y + 66), "Flow: " + String(st_d["flow"]), HORIZONTAL_ALIGNMENT_LEFT, txt_w, 10, Color(0.45, 0.96, 0.72))

	var cost_parts: Array[String] = []
	for ck in st_d["cost"].keys():
		cost_parts.append("%s %d/%d" % [String(ck).to_upper(), GameState.get_res(String(ck)), int(st_d["cost"][ck])])
	var cost_txt := "Cost: " + (" | ".join(cost_parts) if not cost_parts.is_empty() else "FREE (Starter)")
	draw_root.draw_string(font, Vector2(dr.position.x + 12, dr.position.y + 92), cost_txt, HORIZONTAL_ALIGNMENT_LEFT, txt_w, 11, Color(1.0, 0.80, 0.36))

	var rb := Rect2(dr.end.x - btn_w - 10.0, dr.position.y + 22.0, btn_w, dr.size.y - 44.0)
	var can_r := GameState.can_research(sel_id)
	var is_u := GameState.has_tech(sel_id)
	_draw_panel(rb, Color(0.08, 0.28, 0.20, 0.95) if can_r else Color(0.08, 0.11, 0.18, 0.92), Color(0.36, 1.0, 0.72) if can_r else Color(0.34, 0.44, 0.56), 8.0, 2.0)
	var blbl := "UNLOCKED" if is_u else ("RESEARCH [A]" if can_r else "LOCKED")
	draw_root.draw_string(font, Vector2(rb.position.x, rb.position.y + rb.size.y * 0.5 + 5), blbl, HORIZONTAL_ALIGNMENT_CENTER, rb.size.x, 12, Color.WHITE if can_r else Color(0.62, 0.70, 0.80))
	if can_r:
		_add_hit(rb, "tech_research", sel_id)

# ------------------------------------------------------------------------------
# 7. CARGO DEPOT INVENTORY & 4-WAY BELT FILTER UI
# ------------------------------------------------------------------------------
func _draw_depot_modal(vp: Vector2, _portrait: bool, font: Font) -> void:
	if not factory: return
	var snap: Dictionary = factory.get_depot_snapshot(depot_uid)
	if snap.is_empty():
		menu_state = MenuState.NONE
		return
	var mw := minf(vp.x - 28.0, 560.0)
	var mh := 370.0
	var r := Rect2((vp.x - mw) * 0.5, 112.0, mw, mh)
	_draw_panel(r, Color(0.04, 0.06, 0.12, 0.96), Color(0.36, 0.88, 1.0), 12.0, 2.0)
	draw_root.draw_string(font, Vector2(r.position.x + 16, r.position.y + 24), "CARGO DEPOT // %d / %d ITEMS" % [int(snap["total"]), int(snap["cap"])], HORIZONTAL_ALIGNMENT_LEFT, int(mw - 90), 13, Color(0.45, 0.96, 1.0))

	var close_r := Rect2(r.end.x - 70, r.position.y + 8, 58, 24)
	_draw_panel(close_r, Color(0.28, 0.08, 0.10, 0.92), Color(1.0, 0.42, 0.42), 5.0)
	draw_root.draw_string(font, Vector2(close_r.position.x, close_r.position.y + 16), "CLOSE", HORIZONTAL_ALIGNMENT_CENTER, close_r.size.x, 11, Color.WHITE)
	_add_hit(close_r, "close_menu")

	# Deposit All Ores button
	var dep_r := Rect2(r.position.x + 16, r.position.y + 40, mw - 32, 32)
	_draw_panel(dep_r, Color(0.08, 0.22, 0.28, 0.95), Color(0.42, 0.96, 1.0), 6.0)
	draw_root.draw_string(font, Vector2(dep_r.position.x, dep_r.position.y + 21), "DEPOSIT ALL ORES FROM SHIP", HORIZONTAL_ALIGNMENT_CENTER, dep_r.size.x, 12, Color.WHITE)
	_add_hit(dep_r, "depot_deposit_all")

	# 4-Way Directional Belt Output Filters
	var y := r.position.y + 84.0
	draw_root.draw_string(font, Vector2(r.position.x + 16, y + 12), "4-WAY BELT OUTPUT FILTERS (Tap to cycle resource):", HORIZONTAL_ALIGNMENT_LEFT, int(mw - 32), 11, Color(1.0, 0.84, 0.36))
	y += 18.0
	var dirs: Array[String] = ["left", "right", "up", "down"]
	var fw := (mw - 32.0) / 4.0
	var flts: Dictionary = snap["out_filters"]
	for i in range(4):
		var dk: String = dirs[i]
		var fr := Rect2(r.position.x + 16 + float(i) * fw, y, fw - 6, 36)
		var fv := String(flts.get(dk, "none")).to_upper()
		_draw_panel(fr, Color(0.10, 0.20, 0.30, 0.95) if fv != "NONE" else Color(0.06, 0.09, 0.15, 0.9), Color(0.42, 0.96, 1.0) if fv != "NONE" else Color(0.28, 0.38, 0.50), 6.0)
		draw_root.draw_string(font, Vector2(fr.position.x, fr.position.y + 15), dk.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, fr.size.x, 10, Color(0.72, 0.82, 0.94))
		draw_root.draw_string(font, Vector2(fr.position.x, fr.position.y + 30), fv, HORIZONTAL_ALIGNMENT_CENTER, fr.size.x, 11, Color.WHITE)
		_add_hit(fr, "depot_filter", dk)

	# Stored items list with TAKE 5 buttons
	y += 48.0
	var inv: Dictionary = snap["inv"]
	var show_items := ["fe", "cu", "si", "ti", "plate_fe", "wire_cu", "wafer_si", "circuit"]
	for it in show_items:
		var cnt := int(inv.get(it, 0))
		draw_root.draw_string(font, Vector2(r.position.x + 20, y + 16), "%s : %d" % [it.to_upper(), cnt], HORIZONTAL_ALIGNMENT_LEFT, 160, 12, Color.WHITE if cnt > 0 else Color(0.45, 0.52, 0.62))
		var tr := Rect2(r.end.x - 102, y, 86, 22)
		_draw_panel(tr, Color(0.08, 0.22, 0.20, 0.92) if cnt > 0 else Color(0.06, 0.08, 0.12, 0.7), Color(0.36, 0.92, 0.72) if cnt > 0 else Color(0.24, 0.30, 0.38), 4.0)
		draw_root.draw_string(font, Vector2(tr.position.x, tr.position.y + 15), "TAKE 5", HORIZONTAL_ALIGNMENT_CENTER, tr.size.x, 10, Color.WHITE if cnt > 0 else Color(0.45, 0.50, 0.58))
		if cnt > 0:
			_add_hit(tr, "depot_take", it)
		y += 24.0

# ------------------------------------------------------------------------------
# 8. VIRTUAL ANALOG JOYSTICK + CHAMFERED ABXY DIAMOND
# ------------------------------------------------------------------------------
func _draw_joystick_and_abxy(font: Font) -> void:
	# Left Joystick base ring + glowing octagonal thumb puck
	draw_root.draw_circle(joy_center, joy_radius, Color(0.04, 0.08, 0.15, 0.55))
	draw_root.draw_arc(joy_center, joy_radius, 0.0, TAU, 36, Color(0.32, 0.78, 1.0, 0.72), 2.0)
	var puck := joy_center + joy_vec * (joy_radius * 0.65)
	_draw_panel(Rect2(puck - Vector2(20, 20), Vector2(40, 40)), Color(0.08, 0.22, 0.36, 0.88), Color(0.45, 0.98, 1.0), 10.0, 2.2)

	# Context-aware labels for ABXY Diamond
	var lbls := {"A": "MINE/USE", "B": "BRAKE", "X": "BUILD", "Y": "PRINTER"}
	if menu_state == MenuState.NONE and GameState.selected_tool != "pick":
		lbls["A"] = "WIRE" if GameState.selected_tool == "wire" else ("SALVAGE" if GameState.selected_tool == "demolish" else "PLACE")
		lbls["B"] = "CANCEL"
	elif menu_state == MenuState.BUILD:
		lbls = {"A": "EQUIP", "B": "CLOSE", "X": "TAB", "Y": "FLIP"}
	elif menu_state == MenuState.PRINTER:
		lbls = {"A": "TECH", "B": "CLOSE", "X": "DRONE", "Y": "UPGRADE"}
	elif menu_state == MenuState.TECH:
		lbls = {"A": "RESEARCH", "B": "CLOSE", "X": "NEXT", "Y": "PREV"}
	elif menu_state == MenuState.DEPOT:
		lbls = {"A": "OK", "B": "CLOSE", "X": "", "Y": ""}

	var bcols := {
		"A": Color(0.32, 0.96, 0.68),
		"B": Color(1.0, 0.42, 0.42),
		"X": Color(0.36, 0.88, 1.0),
		"Y": Color(1.0, 0.80, 0.32),
	}
	for k in ["A", "B", "X", "Y"]:
		var c: Vector2 = btn_centers[k]
		var br := Rect2(c - Vector2(btn_r, btn_r), Vector2(btn_r * 2.0, btn_r * 2.0))
		_draw_panel(br, Color(0.04, 0.08, 0.14, 0.82), bcols[k], 12.0, 2.2)
		draw_root.draw_string(font, Vector2(br.position.x, c.y + 6), k, HORIZONTAL_ALIGNMENT_CENTER, br.size.x, 18, bcols[k])
		if lbls[k] != "":
			draw_root.draw_string(font, Vector2(c.x - 42, c.y + btn_r + 14), lbls[k], HORIZONTAL_ALIGNMENT_CENTER, 84, 10, Color(0.86, 0.92, 0.98))
