extends CanvasLayer

# Concept-Art-Faithful Industrial HUD (matching docs/art/target_gameplay_concept.jpeg):
# - Left slim Resource, Power, 10,000 Swarm Fleet & Seed Expansion sidebar
# - Bottom centered Industrial Hotbar with pixel-art building thumbnails & category tabs
# - Right vertical Fleet Doctrine quick-strip
# - Bottom-right Orbital Telemetry (Gravity/Atmos/Vel/Alt) & Activity Log
# - Subtle diegetic HP/Fuel/Ion arcs around Seed Unit
# - Touch controls shown ONLY on mobile/portrait/touch devices (clean desktop view!)

enum Modal { NONE, TECH, DEPOT, MEGA }

var planet: SphericalPlanet = null
var grid: Node2D = null
var player: Node2D = null
var swarm: Node2D = null

var modal: int = Modal.NONE
var hotbar_tab: int = 0
var tech_sel: int = 1
var depot_uid: int = -1
var redrop_armed: bool = false

# Touch / Mobile Virtual Controls (auto-shown on mobile/portrait or first touch)
var touch_ui_active: bool = false
var joy_center: Vector2 = Vector2.ZERO
var joy_r: float = 52.0
var joy_vec: Vector2 = Vector2.ZERO
var joy_pid: int = -1
var act_center: Vector2 = Vector2.ZERO
var brk_center: Vector2 = Vector2.ZERO
var act_pid: int = -1
var brk_pid: int = -1
var mouse_mine_held: bool = false

var _hits: Array[Dictionary] = []
var root_ctrl: Control = null

func _ready() -> void:
	layer = 20
	root_ctrl = Control.new()
	root_ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_ctrl.draw.connect(_on_draw)
	add_child(root_ctrl)

func open_depot(uid: int) -> void:
	depot_uid = uid
	modal = Modal.DEPOT
	root_ctrl.queue_redraw()

func _hud_vp() -> Vector2:
	var raw := get_viewport().get_visible_rect().size
	if raw.y > raw.x * 1.1:
		touch_ui_active = true
		var s := clampf(raw.x / 520.0, 1.35, 2.6)
		scale = Vector2(s, s)
		return raw / s
	scale = Vector2.ONE
	return raw

func _process(_delta: float) -> void:
	var vp := _hud_vp()
	joy_r = 50.0
	joy_center = Vector2(joy_r + 22.0, vp.y - joy_r - 108.0)
	act_center = Vector2(vp.x - 56.0, vp.y - 148.0)
	brk_center = Vector2(vp.x - 122.0, vp.y - 126.0)

	# Keyboard WASD / Arrows + Touch Joystick -> Player Movement
	var kb := Vector2.ZERO
	if modal == Modal.NONE:
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): kb.x += 1.0
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):  kb.x -= 1.0
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):  kb.y += 1.0
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):    kb.y -= 1.0
		if kb.length() > 1.0: kb = kb.normalized()

	if player:
		player.move_input = joy_vec if joy_vec.length() > 0.1 else kb
		player.braking = (brk_pid != -1) or Input.is_key_pressed(KEY_SHIFT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
		var cam := get_viewport().get_camera_2d()
		if cam:
			var mpos := get_viewport().get_mouse_position()
			var wp := cam.get_canvas_transform().affine_inverse() * mpos
			player.aim_world = wp
			if grid:
				grid.hover_world = wp
				grid.show_ghost = (modal == Modal.NONE and State.BLD.has(State.selected_tool))
		player.firing_mine = (modal == Modal.NONE and State.selected_tool == "mine" and (mouse_mine_held or act_pid != -1 or Input.is_key_pressed(KEY_SPACE)))

	root_ctrl.queue_redraw()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		_on_key(event.keycode)
		return

	if event is InputEventScreenTouch:
		touch_ui_active = true
		var p: Vector2 = event.position / maxf(0.1, scale.x)
		if event.pressed: _on_down(event.index, p, event.position)
		else: _on_up(event.index)
	elif event is InputEventScreenDrag:
		if event.index == joy_pid:
			_upd_joy(event.position / maxf(0.1, scale.x))
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var p: Vector2 = event.position / maxf(0.1, scale.x)
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed: _on_down(-10, p, event.position)
			else: _on_up(-10)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if modal != Modal.NONE:
				modal = Modal.NONE; Sfx.play("click")
			elif State.selected_tool != "mine":
				State.selected_tool = "mine"
				if grid: grid.wire_pick_uid = -1
				Sfx.play("click")
	elif event is InputEventMouseMotion and joy_pid == -10:
		_upd_joy(event.position / maxf(0.1, scale.x))

func _on_key(code: int) -> void:
	match code:
		KEY_T:
			modal = Modal.NONE if modal == Modal.TECH else Modal.TECH
			Sfx.play("select")
		KEY_G:
			modal = Modal.NONE if modal == Modal.MEGA else Modal.MEGA
			Sfx.play("select")
		KEY_M:
			State.orbit_view = not State.orbit_view
			Sfx.play("click")
		KEY_ESCAPE:
			if modal != Modal.NONE: modal = Modal.NONE
			else: State.selected_tool = "mine"
			Sfx.play("click")
		KEY_R:
			State.build_dir = -State.build_dir
			Sfx.play("click")
		KEY_E:
			if modal == Modal.NONE and grid and player:
				grid.interact_near_player(player.position)
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7:
			var idx := code - KEY_1
			var items: Array = State.HOTBAR_TABS[hotbar_tab]["items"]
			if idx >= 0 and idx < items.size():
				_pick_tool(String(items[idx]))

func _on_down(pid: int, pos: Vector2, raw_pos: Vector2) -> void:
	# 1. Touch Virtual Controls (active only on mobile/touch)
	if touch_ui_active and modal == Modal.NONE:
		if pos.distance_to(joy_center) <= joy_r + 28.0:
			joy_pid = pid; _upd_joy(pos); get_viewport().set_input_as_handled(); return
		if pos.distance_to(act_center) <= 36.0:
			act_pid = pid
			if grid and player:
				if State.selected_tool == "mine":
					if not grid.interact_near_player(player.position):
						player.firing_mine = true
				else:
					grid.handle_world_click(player.position)
			get_viewport().set_input_as_handled(); return
		if pos.distance_to(brk_center) <= 30.0:
			brk_pid = pid; get_viewport().set_input_as_handled(); return

	# 2. HUD Hit Rects (reverse draw order = top modal first)
	for i in range(_hits.size() - 1, -1, -1):
		if Rect2(_hits[i]["r"]).has_point(pos):
			_exec(_hits[i])
			get_viewport().set_input_as_handled()
			return

	# 3. Direct World Interaction (Mine / Build / Wire / Tap Depot or Smelter!)
	if modal == Modal.NONE and grid:
		var cam := get_viewport().get_camera_2d()
		if cam:
			var wp := cam.get_canvas_transform().affine_inverse() * raw_pos
			if grid.handle_world_click(wp):
				get_viewport().set_input_as_handled()
				return
			if State.selected_tool == "mine" and pid == -10:
				mouse_mine_held = true

func _on_up(pid: int) -> void:
	if pid == joy_pid: joy_pid = -1; joy_vec = Vector2.ZERO
	if pid == act_pid: act_pid = -1
	if pid == brk_pid: brk_pid = -1
	if pid == -10: mouse_mine_held = false

func _upd_joy(pos: Vector2) -> void:
	var d := pos - joy_center
	if d.length() > joy_r: d = d.normalized() * joy_r
	joy_vec = d / maxf(1.0, joy_r)

func _pick_tool(tid: String) -> void:
	if not State.is_unlocked(tid):
		Sfx.play("error")
		State.add_log("Research required for %s (open Tech [T])." % tid.to_upper(), "warn")
		return
	State.selected_tool = tid
	Sfx.play("select")

func _exec(h: Dictionary) -> void:
	var act := String(h["a"])
	match act:
		"tab": hotbar_tab = int(h["v"]); Sfx.play("click")
		"tool": _pick_tool(String(h["v"]))
		"open_tech": modal = Modal.NONE if modal == Modal.TECH else Modal.TECH; Sfx.play("select")
		"open_mega": modal = Modal.NONE if modal == Modal.MEGA else Modal.MEGA; Sfx.play("select")
		"toggle_orbit": State.orbit_view = not State.orbit_view; Sfx.play("click")
		"close": modal = Modal.NONE; redrop_armed = false; Sfx.play("click")
		"dock_drone": State.dock_new_drone()
		"up_prop": State.upgrade_propulsion()
		"doc": State.doctrine = int(h["v"]); Sfx.play("select")
		"mute": Sfx.muted = not Sfx.muted
		"redrop":
			if not redrop_armed: redrop_armed = true; Sfx.play("click")
			else: redrop_armed = false; if player: player.emergency_redrop()
		"tech_sel": tech_sel = int(h["v"]); Sfx.play("click")
		"tech_buy": State.research(String(h["v"]))
		"mega_buy": State.build_mega(String(h["v"]))
		"depot_all": if grid: grid.depot_deposit_all(depot_uid)
		"depot_flt": if grid: grid.depot_cycle_filter(depot_uid, String(h["v"]))
		"depot_take": if grid: grid.depot_transfer(depot_uid, String(h["v"]), false, 5)

func _add_hit(r: Rect2, a: String, v = null) -> void:
	_hits.append({"r": r, "a": a, "v": v})

func _panel(r: Rect2, bg: Color, edge: Color, bw: float = 1.5) -> void:
	root_ctrl.draw_rect(r, bg)
	root_ctrl.draw_rect(r, edge, false, bw)

# ------------------------------------------------------------------------------
# MASTER DRAW (MATCHING CONCEPT ART VISUAL HIERARCHY!)
# ------------------------------------------------------------------------------
func _on_draw() -> void:
	_hits.clear()
	var vp := _hud_vp()
	var portrait := vp.y > vp.x * 1.1
	var font := ThemeDB.fallback_font

	_draw_diegetic_arcs(vp, font)
	_draw_left_sidebar(vp, portrait, font)
	_draw_right_strip(vp, portrait, font)
	_draw_bottom_right_telemetry(vp, portrait, font)
	_draw_bottom_hotbar(vp, portrait, font)

	match modal:
		Modal.TECH:  _draw_tech_modal(vp, portrait, font)
		Modal.DEPOT: _draw_depot_modal(vp, font)
		Modal.MEGA:  _draw_mega_modal(vp, font)

	if touch_ui_active and modal == Modal.NONE:
		_draw_touch_controls(font)

	if State.game_won:
		var vr := Rect2(vp.x * 0.5 - 210, 16, 420, 44)
		_panel(vr, Color(0.06, 0.22, 0.15, 0.94), Color(0.35, 1.0, 0.72), 2.0)
		root_ctrl.draw_string(font, Vector2(vr.position.x, vr.position.y + 28), "VICTORY: SECTOR LIBERATED & WARP GATE ONLINE!", HORIZONTAL_ALIGNMENT_CENTER, vr.size.x, 14, Color(0.88, 1.0, 0.94))

# 1. Subtle Fighter-Jet Diegetic Arcs around Seed Unit
func _draw_diegetic_arcs(vp: Vector2, font: Font) -> void:
	if not player or State.orbit_view: return
	var cam := get_viewport().get_camera_2d()
	if not cam: return
	var sp := (cam.get_canvas_transform() * player.global_position) / maxf(0.1, scale.x)
	if not Rect2(Vector2(-60, -60), vp + Vector2(120, 120)).has_point(sp): return
	var rad := 46.0 + float(State.attached_drones) * 2.5
	var hp_f := clampf(State.hp / maxf(1.0, State.max_hp), 0.0, 1.0)
	var fl_f := clampf(State.fuel / maxf(1.0, State.max_fuel), 0.0, 1.0)
	var in_f := clampf(State.ion_bat / maxf(1.0, State.max_ion_bat), 0.0, 1.0)
	var l0 := deg_to_rad(138.0); var l1 := deg_to_rad(222.0)
	root_ctrl.draw_arc(sp, rad, l0, l1, 18, Color(0.15, 0.22, 0.30, 0.45), 3.5)
	root_ctrl.draw_arc(sp, rad, l0, lerpf(l0, l1, hp_f), 18, Color(0.32, 0.92, 0.60, 0.85), 3.5)
	var r0 := deg_to_rad(42.0); var r1 := deg_to_rad(-42.0)
	root_ctrl.draw_arc(sp, rad, r1, r0, 18, Color(0.15, 0.22, 0.30, 0.45), 3.5)
	if fl_f > 0.01:
		root_ctrl.draw_arc(sp, rad, lerpf(r0, r1, fl_f), r0, 18, Color(1.0, 0.72, 0.22, 0.85), 3.5)
	root_ctrl.draw_arc(sp, rad - 6.0, lerpf(r0, r1, in_f), r0, 16, Color(0.34, 0.92, 1.0, 0.85), 2.2)
	if player.velocity.length() > 24.0:
		root_ctrl.draw_string(font, sp + Vector2(rad + 8, 4), "%dm/s" % int(player.velocity.length()), HORIZONTAL_ALIGNMENT_LEFT, 60, 10, Color(0.84, 0.92, 1.0, 0.85))

# 2. Left Slim Tactical Sidebar (Concept Art Upper-Left!)
func _draw_left_sidebar(vp: Vector2, portrait: bool, font: Font) -> void:
	var w := 196.0 if not portrait else minf(vp.x - 16.0, 320.0)
	var h := 274.0 if not portrait else 124.0
	var r := Rect2(8, 8, w, h)
	_panel(r, Color(0.05, 0.07, 0.12, 0.88), Color(0.24, 0.34, 0.48, 0.85), 1.4)

	var items: Array[String] = ["fe", "cu", "si", "ti", "plate_fe", "wire_cu", "wafer_si", "circuit"]
	var cols := 2 if not portrait else 4
	var cw := (w - 16.0) / float(cols)
	for i in range(items.size()):
		var id: String = items[i]
		var x := r.position.x + 8.0 + float(i % cols) * cw
		var y := r.position.y + 8.0 + float(i / cols) * 20.0
		var ic := ArtReg.get_icon(id)
		if ic: root_ctrl.draw_texture_rect(ic, Rect2(x, y, 14, 14), false)
		root_ctrl.draw_string(font, Vector2(x + 18, y + 12), "%d" % State.get_r(id), HORIZONTAL_ALIGNMENT_LEFT, int(cw - 20), 12, Color(0.94, 0.97, 1.0))

	var y2 := r.position.y + (94.0 if not portrait else 54.0)
	var pcol := Color(0.36, 0.96, 0.64) if (State.pwr_prod >= State.pwr_use and State.pwr_prod > 0.0) else (Color(1.0, 0.80, 0.34) if State.pwr_stored > 10.0 else Color(0.96, 0.44, 0.38))
	var bat_s := " BAT:%d%%" % int(State.pwr_stored / maxf(1.0, State.pwr_cap) * 100.0) if State.pwr_cap > 1.0 else ""
	root_ctrl.draw_string(font, Vector2(r.position.x + 8, y2), "PWR %d/%dW%s" % [int(State.pwr_prod), int(State.pwr_use), bat_s], HORIZONTAL_ALIGNMENT_LEFT, int(w - 16), 11, pcol)

	# FLEET: X / 10,000 Progress Bar (iconic concept art element!)
	y2 += 16.0
	root_ctrl.draw_string(font, Vector2(r.position.x + 8, y2), "FLEET: %d / 10,000" % State.swarm_fleet, HORIZONTAL_ALIGNMENT_LEFT, int(w - 16), 11, Color(1.0, 0.86, 0.42))
	var br := Rect2(r.position.x + 8, y2 + 5, w - 16, 7)
	root_ctrl.draw_rect(br, Color(0.10, 0.14, 0.22))
	root_ctrl.draw_rect(Rect2(br.position, Vector2(br.size.x * clampf(float(State.swarm_fleet) / 10000.0, 0.0, 1.0), br.size.y)), Color(0.34, 0.86, 1.0))

	if portrait:
		# Compact action row on mobile
		var bw := (w - 20.0) * 0.5
		var bd := Rect2(r.position.x + 8, y2 + 18, bw, 24)
		_panel(bd, Color(0.08, 0.18, 0.26, 0.92), Color(0.40, 0.90, 1.0), 1.2)
		root_ctrl.draw_string(font, Vector2(bd.position.x, bd.position.y + 16), "+DRONE (%d/8)" % State.attached_drones, HORIZONTAL_ALIGNMENT_CENTER, bw, 10, Color.WHITE)
		_add_hit(bd, "dock_drone")
		var bp := Rect2(r.position.x + 12 + bw, y2 + 18, bw, 24)
		_panel(bp, Color(0.10, 0.22, 0.18, 0.92), Color(0.40, 0.96, 0.72), 1.2)
		root_ctrl.draw_string(font, Vector2(bp.position.x, bp.position.y + 16), "+DRIVE (T%d)" % State.propulsion_tier, HORIZONTAL_ALIGNMENT_CENTER, bw, 10, Color.WHITE)
		_add_hit(bp, "up_prop")
		return

	# Active Printers gauge + Seed Expansion Actions (Desktop)
	y2 += 24.0
	root_ctrl.draw_string(font, Vector2(r.position.x + 8, y2), "PRINTERS: %d / %d  |  WIRES: %d" % [State.active_printers, State.total_printers, State.wire_count], HORIZONTAL_ALIGNMENT_LEFT, int(w - 16), 10, Color(0.72, 0.84, 0.96))

	# Dock Fabricator Drone button (Core DESIGN_SPECIFICATION.md progression!)
	y2 += 12.0
	var can_dr := State.attached_drones < State.MAX_DRONES and State.can_afford(State.DRONE_COST)
	var dr := Rect2(r.position.x + 8, y2, w - 16, 34)
	_panel(dr, Color(0.08, 0.20, 0.30, 0.94) if can_dr else Color(0.07, 0.10, 0.16, 0.9), Color(0.42, 0.94, 1.0) if can_dr else Color(0.26, 0.34, 0.46), 1.4)
	root_ctrl.draw_string(font, Vector2(dr.position.x + 8, dr.position.y + 14), "+ DOCK DRONE (%d/%d)" % [State.attached_drones, State.MAX_DRONES], HORIZONTAL_ALIGNMENT_LEFT, int(dr.size.x - 12), 11, Color.WHITE)
	root_ctrl.draw_string(font, Vector2(dr.position.x + 8, dr.position.y + 28), "FE:10 CU:6  (+1 Beam)", HORIZONTAL_ALIGNMENT_LEFT, int(dr.size.x - 12), 10, Color(0.58, 0.92, 0.82) if can_dr else Color(0.62, 0.68, 0.78))
	_add_hit(dr, "dock_drone")

	# Mount Orbital Booster / Propulsion Tier button
	y2 += 40.0
	var can_up := State.can_upgrade_propulsion()
	var pr := Rect2(r.position.x + 8, y2, w - 16, 34)
	_panel(pr, Color(0.08, 0.24, 0.18, 0.94) if can_up else Color(0.07, 0.10, 0.16, 0.9), Color(0.40, 1.0, 0.72) if can_up else Color(0.26, 0.34, 0.46), 1.4)
	var nxt := State.propulsion_tier + 1
	if State.PROPULSION_TIERS.has(nxt):
		var ti: Dictionary = State.PROPULSION_TIERS[nxt]
		root_ctrl.draw_string(font, Vector2(pr.position.x + 8, pr.position.y + 14), "+ %s" % String(ti["name"]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, int(pr.size.x - 12), 10, Color.WHITE)
		var cs: Array[String] = []
		for k in ti["cost"].keys(): cs.append("%s:%d" % [String(k).to_upper().substr(0, 3), int(ti["cost"][k])])
		root_ctrl.draw_string(font, Vector2(pr.position.x + 8, pr.position.y + 28), " ".join(cs), HORIZONTAL_ALIGNMENT_LEFT, int(pr.size.x - 12), 9, Color(0.60, 0.96, 0.80) if can_up else Color(0.64, 0.68, 0.76))
		_add_hit(pr, "up_prop")
	else:
		root_ctrl.draw_string(font, Vector2(pr.position.x + 8, pr.position.y + 21), "FLAGSHIP MAX DRIVE", HORIZONTAL_ALIGNMENT_LEFT, int(pr.size.x - 12), 11, Color(0.48, 1.0, 0.78))

	# Tech Tree + Megastructures quick buttons
	y2 += 40.0
	var ready_t := false
	for tid in State.TECH_ORDER:
		if State.can_research(tid): ready_t = true; break
	var tr := Rect2(r.position.x + 8, y2, (w - 20) * 0.52, 26)
	_panel(tr, Color(0.10, 0.18, 0.28, 0.94), Color(1.0, 0.82, 0.32) if ready_t else Color(0.36, 0.78, 1.0), 1.5)
	root_ctrl.draw_string(font, Vector2(tr.position.x, tr.position.y + 17), "TECH %d/8 [T]" % State.unlocked_techs.size(), HORIZONTAL_ALIGNMENT_CENTER, tr.size.x, 10, Color.WHITE)
	_add_hit(tr, "open_tech")

	var mr := Rect2(tr.end.x + 4, y2, (w - 20) * 0.48, 26)
	_panel(mr, Color(0.08, 0.12, 0.20, 0.92), Color(0.56, 0.44, 0.88), 1.4)
	root_ctrl.draw_string(font, Vector2(mr.position.x, mr.position.y + 17), "MEGA [G]", HORIZONTAL_ALIGNMENT_CENTER, mr.size.x, 10, Color.WHITE)
	_add_hit(mr, "open_mega")

# 3. Right Slim Quick-Command Strip (Concept Art Right Edge!)
func _draw_right_strip(vp: Vector2, portrait: bool, font: Font) -> void:
	var bw := 66.0 if not portrait else 58.0
	var x := vp.x - bw - 8.0
	var y := 10.0 if not portrait else 138.0
	var docs := ["HARV", "REPL", "DEF", "ASLT"]
	for i in range(4):
		var r := Rect2(x, y, bw, 24)
		var on := (State.doctrine == i)
		_panel(r, Color(0.14, 0.26, 0.38, 0.92) if on else Color(0.05, 0.07, 0.12, 0.86), Color(1.0, 0.82, 0.34) if on else Color(0.26, 0.36, 0.48), 1.3)
		root_ctrl.draw_string(font, Vector2(r.position.x, r.position.y + 16), docs[i], HORIZONTAL_ALIGNMENT_CENTER, bw, 10, Color.WHITE if on else Color(0.70, 0.78, 0.88))
		_add_hit(r, "doc", i)
		y += 28.0
	var mr := Rect2(x, y + 4, bw, 24)
	_panel(mr, Color(0.08, 0.16, 0.26, 0.92) if State.orbit_view else Color(0.05, 0.07, 0.12, 0.86), Color(0.40, 0.88, 1.0), 1.3)
	root_ctrl.draw_string(font, Vector2(mr.position.x, mr.position.y + 16), "ORBIT [M]", HORIZONTAL_ALIGNMENT_CENTER, bw, 9, Color.WHITE)
	_add_hit(mr, "toggle_orbit")
	y += 32.0
	if portrait:
		var tr := Rect2(x, y, bw, 24)
		_panel(tr, Color(0.10, 0.18, 0.28, 0.92), Color(1.0, 0.82, 0.34), 1.3)
		root_ctrl.draw_string(font, Vector2(tr.position.x, tr.position.y + 16), "TECH %d/8" % State.unlocked_techs.size(), HORIZONTAL_ALIGNMENT_CENTER, bw, 9, Color.WHITE)
		_add_hit(tr, "open_tech")
		y += 28.0
	var sr := Rect2(x, y, bw, 22)
	_panel(sr, Color(0.05, 0.07, 0.12, 0.86), Color(0.32, 0.44, 0.56), 1.1)
	root_ctrl.draw_string(font, Vector2(sr.position.x, sr.position.y + 15), "SFX:" + ("OFF" if Sfx.muted else "ON"), HORIZONTAL_ALIGNMENT_CENTER, bw, 9, Color(0.8, 0.86, 0.94))
	_add_hit(sr, "mute")
	y += 26.0
	var rr := Rect2(x, y, bw, 22)
	_panel(rr, Color(0.34, 0.08, 0.10, 0.92) if redrop_armed else Color(0.16, 0.06, 0.08, 0.85), Color(1.0, 0.38, 0.36), 1.1)
	root_ctrl.draw_string(font, Vector2(rr.position.x, rr.position.y + 15), "SURE?" if redrop_armed else "RE-DROP", HORIZONTAL_ALIGNMENT_CENTER, bw, 9, Color(1.0, 0.84, 0.84))
	_add_hit(rr, "redrop")

# 4. Bottom-Right Orbital Telemetry + Alert Log (Concept Art Bottom-Right!)
func _draw_bottom_right_telemetry(vp: Vector2, portrait: bool, font: Font) -> void:
	if portrait: return
	var w := 296.0; var h := 134.0
	var r := Rect2(vp.x - w - 8.0, vp.y - h - 8.0, w, h)
	_panel(r, Color(0.04, 0.06, 0.10, 0.86), Color(0.24, 0.34, 0.48, 0.85), 1.3)
	var g_v: float = float(player.local_g) if player else 1.0
	var at_v: float = float(planet.get_atmos_density(player.position)) if (planet and player) else 1.0
	var vl_v: int = int(player.velocity.length()) if player else 0
	var al_v: int = int(player.get_altitude()) if player else 0
	root_ctrl.draw_string(font, Vector2(r.position.x + 8, r.position.y + 16), "GRAV: %.2fG   ATMOS: %.2f" % [g_v, at_v], HORIZONTAL_ALIGNMENT_LEFT, int(w - 16), 10, Color(0.76, 0.88, 0.98))
	root_ctrl.draw_string(font, Vector2(r.position.x + 8, r.position.y + 31), "VEL: %dm/s    ALT: %dm" % [vl_v, al_v], HORIZONTAL_ALIGNMENT_LEFT, int(w - 16), 10, Color(0.76, 0.88, 0.98))
	root_ctrl.draw_line(Vector2(r.position.x + 6, r.position.y + 39), Vector2(r.end.x - 6, r.position.y + 39), Color(0.22, 0.32, 0.44), 1.0)
	var y := r.position.y + 54.0
	var st := maxi(0, State.logs.size() - 5)
	for i in range(st, State.logs.size()):
		var lg := State.logs[i]
		var c := Color(0.45, 0.96, 0.70) if lg["kind"] == "good" else (Color(1.0, 0.78, 0.34) if lg["kind"] == "warn" else Color(0.84, 0.86, 0.92))
		root_ctrl.draw_string(font, Vector2(r.position.x + 8, y), "! " + String(lg["msg"]), HORIZONTAL_ALIGNMENT_LEFT, int(w - 14), 9, c)
		y += 15.0

# 5. Bottom-Center Industrial Hotbar with Actual Pixel-Art Building Icons!
func _draw_bottom_hotbar(vp: Vector2, portrait: bool, font: Font) -> void:
	var items: Array = State.HOTBAR_TABS[hotbar_tab]["items"]
	var slot_sz := 44.0 if portrait else 52.0
	var gap := 6.0
	var bar_w := float(items.size()) * (slot_sz + gap) + gap + 12.0
	var bar_h := slot_sz + 32.0
	var bx := (vp.x - bar_w) * 0.5 if not portrait else (vp.x - bar_w) * 0.5
	var by := vp.y - bar_h - 8.0
	var br := Rect2(bx, by, bar_w, bar_h)
	_panel(br, Color(0.05, 0.07, 0.12, 0.92), Color(0.28, 0.40, 0.56, 0.90), 1.6)

	# Category tabs on top edge of hotbar
	var tw := (bar_w - 16.0) / float(State.HOTBAR_TABS.size())
	for ti in range(State.HOTBAR_TABS.size()):
		var tr := Rect2(bx + 8.0 + float(ti) * tw, by + 4.0, tw - 4.0, 20.0)
		var sel := (ti == hotbar_tab)
		_panel(tr, Color(0.14, 0.24, 0.36, 0.95) if sel else Color(0.06, 0.09, 0.15, 0.85), Color(0.44, 0.94, 1.0) if sel else Color(0.22, 0.32, 0.44), 1.2)
		root_ctrl.draw_string(font, Vector2(tr.position.x, tr.position.y + 14.0), String(State.HOTBAR_TABS[ti]["label"]), HORIZONTAL_ALIGNMENT_CENTER, tr.size.x, 9 if portrait else 10, Color.WHITE if sel else Color(0.68, 0.76, 0.88))
		_add_hit(tr, "tab", ti)

	# Pixel-art tool & building slots
	var sy := by + 28.0
	for i in range(items.size()):
		var tid := String(items[i])
		var sx := bx + 8.0 + float(i) * (slot_sz + gap)
		var sr := Rect2(sx, sy, slot_sz, slot_sz)
		var unl := State.is_unlocked(tid)
		var sel := (State.selected_tool == tid)
		var bg := Color(0.12, 0.26, 0.38, 0.95) if sel else Color(0.07, 0.10, 0.16, 0.92)
		var bd := Color(1.0, 0.84, 0.34) if sel else (Color(0.34, 0.56, 0.74) if unl else Color(0.36, 0.20, 0.22))
		_panel(sr, bg, bd, 2.0 if sel else 1.2)

		var tex_k := String(State.BLD[tid]["tex"]) if State.BLD.has(tid) else ("seed_core" if tid == "mine" else "")
		var t := ArtReg.get_t(tex_k) if tex_k != "" else null
		if t:
			var pad := 6.0
			var mod := Color.WHITE if unl else Color(0.4, 0.4, 0.45, 0.65)
			root_ctrl.draw_texture_rect(t, Rect2(sx + pad, sy + pad, slot_sz - pad * 2.0, slot_sz - pad * 2.0 - 8.0), false, mod)
		else:
			var short_t := "WIRE" if tid == "wire" else "SALV"
			root_ctrl.draw_string(font, Vector2(sx, sy + slot_sz * 0.52), short_t, HORIZONTAL_ALIGNMENT_CENTER, slot_sz, 11, Color(0.45, 0.96, 1.0) if tid == "wire" else Color(1.0, 0.48, 0.42))

		var lbl := "MINE" if tid == "mine" else ("WIRE" if tid == "wire" else ("DEL" if tid == "salvage" else String(State.BLD[tid]["name"]).substr(0, 6).to_upper()))
		root_ctrl.draw_string(font, Vector2(sx, sy + slot_sz - 3), lbl, HORIZONTAL_ALIGNMENT_CENTER, slot_sz, 8, Color.WHITE if unl else Color(0.55, 0.55, 0.60))
		root_ctrl.draw_string(font, Vector2(sx + 3, sy + 10), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, 14, 9, Color(0.62, 0.76, 0.90))
		_add_hit(sr, "tool", tid)

# 6. Factorio-Style Tech Tree Modal ([T])
func _draw_tech_modal(vp: Vector2, portrait: bool, font: Font) -> void:
	var mw := minf(vp.x - 24.0, 880.0)
	var mh := minf(vp.y - 110.0, 520.0)
	var r := Rect2((vp.x - mw) * 0.5, (vp.y - mh) * 0.5 - 20.0, mw, mh)
	_panel(r, Color(0.03, 0.05, 0.10, 0.96), Color(0.36, 0.86, 1.0), 2.0)
	root_ctrl.draw_string(font, Vector2(r.position.x + 14, r.position.y + 22), "COLONY RESEARCH LAB // TECH TREE DAG", HORIZONTAL_ALIGNMENT_LEFT, int(mw - 90), 13, Color(0.48, 0.96, 1.0))

	var cr := Rect2(r.end.x - 68, r.position.y + 6, 58, 22)
	_panel(cr, Color(0.28, 0.08, 0.10, 0.92), Color(1.0, 0.42, 0.42), 1.4)
	root_ctrl.draw_string(font, Vector2(cr.position.x, cr.position.y + 15), "CLOSE", HORIZONTAL_ALIGNMENT_CENTER, cr.size.x, 10, Color.WHITE)
	_add_hit(cr, "close")

	var cards: Dictionary = {}
	var dh := 112.0
	var gh := mh - dh - 44.0
	if portrait:
		var cw := (mw - 34.0) * 0.5; var ch := clampf((gh - 28.0) / 4.0, 42.0, 56.0)
		for i in range(State.TECH_ORDER.size()):
			var tid := State.TECH_ORDER[i]
			cards[tid] = Rect2(r.position.x + 12 + float(i % 2) * (cw + 8), r.position.y + 36 + float(i / 2) * (ch + 8), cw, ch)
	else:
		var cw := (mw - 76.0) / 6.0; var ch := 64.0; var rsp := gh / 3.0
		for tid in State.TECH_ORDER:
			var t: Dictionary = State.TECHS[tid]
			cards[tid] = Rect2(r.position.x + 16 + float(int(t["col"])) * (cw + 8), r.position.y + 40 + float(int(t["row"])) * rsp, cw, ch)

	for tid in State.TECH_ORDER:
		for rq in State.TECHS[tid]["req"]:
			if cards.has(rq):
				var col := Color(0.35, 0.96, 0.68, 0.85) if State.has_tech(tid) else Color(0.32, 0.46, 0.64, 0.55)
				root_ctrl.draw_line(Rect2(cards[rq]).get_center(), Rect2(cards[tid]).get_center(), col, 2.0)

	for i in range(State.TECH_ORDER.size()):
		var tid := State.TECH_ORDER[i]; var t: Dictionary = State.TECHS[tid]; var box_r: Rect2 = cards[tid]
		var done := State.has_tech(tid); var avail := State.can_research(tid); var sel := (i == tech_sel)
		var bg := Color(0.06, 0.22, 0.16, 0.95) if done else (Color(0.10, 0.20, 0.34, 0.95) if sel else Color(0.06, 0.09, 0.15, 0.92))
		var bd := Color(0.36, 1.0, 0.72) if done else (Color(1.0, 0.84, 0.34) if avail else (Color(0.42, 0.94, 1.0) if sel else Color(0.26, 0.36, 0.48)))
		_panel(box_r, bg, bd, 2.2 if sel else 1.2)
		root_ctrl.draw_string(font, Vector2(box_r.position.x + 8, box_r.position.y + 20), String(t["name"]), HORIZONTAL_ALIGNMENT_LEFT, int(box_r.size.x - 14), 11, Color.WHITE)
		var st := "UNLOCKED" if done else ("READY!" if avail else "LOCKED")
		root_ctrl.draw_string(font, Vector2(box_r.position.x + 8, box_r.end.y - 8), st, HORIZONTAL_ALIGNMENT_LEFT, int(box_r.size.x - 14), 10, Color(0.45, 1.0, 0.72) if done else (Color(1.0, 0.84, 0.34) if avail else Color(0.56, 0.64, 0.76)))
		_add_hit(box_r, "tech_sel", i)

	var sid := State.TECH_ORDER[clampi(tech_sel, 0, State.TECH_ORDER.size() - 1)]
	var td: Dictionary = State.TECHS[sid]
	var dr := Rect2(r.position.x + 12, r.end.y - dh - 10, mw - 24, dh)
	_panel(dr, Color(0.05, 0.08, 0.15, 0.96), Color(0.36, 0.78, 1.0), 1.5)
	var bw := 98.0 if portrait else 160.0
	var tw := int(dr.size.x - bw - 22)
	var fs_h := 10 if portrait else 12
	var fs_b := 9 if portrait else 11
	var fs_s := 9 if portrait else 10
	root_ctrl.draw_string(font, Vector2(dr.position.x + 10, dr.position.y + 20), "%s | %s" % [String(td["name"]).to_upper(), ", ".join(td["unlocks"])], HORIZONTAL_ALIGNMENT_LEFT, tw, fs_h, Color(0.46, 0.96, 1.0))
	root_ctrl.draw_string(font, Vector2(dr.position.x + 10, dr.position.y + 42), String(td["summary"]), HORIZONTAL_ALIGNMENT_LEFT, tw, fs_b, Color(0.92, 0.95, 1.0))
	root_ctrl.draw_string(font, Vector2(dr.position.x + 10, dr.position.y + 62), "Flow: " + String(td["flow"]), HORIZONTAL_ALIGNMENT_LEFT, tw, fs_s, Color(0.46, 0.96, 0.72))
	var cp: Array[String] = []
	for k in td["cost"].keys(): cp.append("%s %d/%d" % [String(k).to_upper(), State.get_r(String(k)), int(td["cost"][k])])
	root_ctrl.draw_string(font, Vector2(dr.position.x + 10, dr.position.y + 88), "Cost: " + (" | ".join(cp) if not cp.is_empty() else "FREE"), HORIZONTAL_ALIGNMENT_LEFT, tw, fs_b, Color(1.0, 0.82, 0.36))

	var rb := Rect2(dr.end.x - bw - 10, dr.position.y + 20, bw, dr.size.y - 40)
	var can_r := State.can_research(sid)
	_panel(rb, Color(0.08, 0.28, 0.20, 0.95) if can_r else Color(0.08, 0.11, 0.18, 0.92), Color(0.36, 1.0, 0.72) if can_r else Color(0.34, 0.44, 0.56), 1.8)
	root_ctrl.draw_string(font, Vector2(rb.position.x, rb.position.y + rb.size.y * 0.5 + 5), "UNLOCKED" if State.has_tech(sid) else ("RESEARCH" if can_r else "LOCKED"), HORIZONTAL_ALIGNMENT_CENTER, bw, 12, Color.WHITE if can_r else Color(0.6, 0.68, 0.78))
	if can_r: _add_hit(rb, "tech_buy", sid)

# 7. Cargo Depot 4-Way Filter Modal
func _draw_depot_modal(vp: Vector2, font: Font) -> void:
	if not grid: return
	var snap: Dictionary = grid.get_depot_snap(depot_uid)
	if snap.is_empty(): modal = Modal.NONE; return
	var mw := minf(vp.x - 24.0, 520.0); var mh := 356.0
	var r := Rect2((vp.x - mw) * 0.5, (vp.y - mh) * 0.5 - 20.0, mw, mh)
	_panel(r, Color(0.04, 0.06, 0.12, 0.96), Color(0.38, 0.88, 1.0), 2.0)
	root_ctrl.draw_string(font, Vector2(r.position.x + 14, r.position.y + 22), "CARGO DEPOT // %d / %d" % [int(snap["total"]), int(snap["cap"])], HORIZONTAL_ALIGNMENT_LEFT, int(mw - 86), 13, Color(0.48, 0.96, 1.0))
	var cr := Rect2(r.end.x - 66, r.position.y + 6, 56, 22)
	_panel(cr, Color(0.28, 0.08, 0.10, 0.92), Color(1.0, 0.42, 0.42), 1.4)
	root_ctrl.draw_string(font, Vector2(cr.position.x, cr.position.y + 15), "CLOSE", HORIZONTAL_ALIGNMENT_CENTER, cr.size.x, 10, Color.WHITE)
	_add_hit(cr, "close")

	var dr := Rect2(r.position.x + 14, r.position.y + 38, mw - 28, 30)
	_panel(dr, Color(0.08, 0.22, 0.30, 0.95), Color(0.42, 0.94, 1.0), 1.4)
	root_ctrl.draw_string(font, Vector2(dr.position.x, dr.position.y + 20), "DEPOSIT ALL ORES", HORIZONTAL_ALIGNMENT_CENTER, dr.size.x, 11, Color.WHITE)
	_add_hit(dr, "depot_all")

	var y := r.position.y + 80.0
	root_ctrl.draw_string(font, Vector2(r.position.x + 14, y + 10), "4-WAY BELT OUTPUT FILTERS (Tap to cycle):", HORIZONTAL_ALIGNMENT_LEFT, int(mw - 28), 10, Color(1.0, 0.84, 0.36))
	y += 16.0
	var dirs: Array[String] = ["left", "right", "up", "down"]
	var fw := (mw - 28.0) / 4.0; var flts: Dictionary = snap["out_filters"]
	for i in range(4):
		var dk: String = dirs[i]
		var fr := Rect2(r.position.x + 14 + float(i) * fw, y, fw - 6, 34)
		var fv := String(flts.get(dk, "none")).to_upper()
		_panel(fr, Color(0.10, 0.22, 0.32, 0.95) if fv != "NONE" else Color(0.06, 0.09, 0.15, 0.9), Color(0.42, 0.94, 1.0) if fv != "NONE" else Color(0.28, 0.38, 0.50), 1.3)
		root_ctrl.draw_string(font, Vector2(fr.position.x, fr.position.y + 14), dk.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, fr.size.x, 9, Color(0.72, 0.82, 0.94))
		root_ctrl.draw_string(font, Vector2(fr.position.x, fr.position.y + 28), fv, HORIZONTAL_ALIGNMENT_CENTER, fr.size.x, 10, Color.WHITE)
		_add_hit(fr, "depot_flt", dk)

	y += 44.0
	var inv: Dictionary = snap["inv"]
	for it in ["fe", "cu", "si", "ti", "plate_fe", "wire_cu", "wafer_si", "circuit"]:
		var cnt := int(inv.get(it, 0))
		root_ctrl.draw_string(font, Vector2(r.position.x + 18, y + 15), "%s : %d" % [String(it).to_upper(), cnt], HORIZONTAL_ALIGNMENT_LEFT, 160, 11, Color.WHITE if cnt > 0 else Color(0.45, 0.52, 0.62))
		var tr := Rect2(r.end.x - 96, y, 80, 20)
		_panel(tr, Color(0.08, 0.22, 0.20, 0.92) if cnt > 0 else Color(0.06, 0.08, 0.12, 0.7), Color(0.36, 0.92, 0.72) if cnt > 0 else Color(0.24, 0.30, 0.38), 1.1)
		root_ctrl.draw_string(font, Vector2(tr.position.x, tr.position.y + 14), "TAKE 5", HORIZONTAL_ALIGNMENT_CENTER, tr.size.x, 10, Color.WHITE if cnt > 0 else Color(0.45, 0.50, 0.58))
		if cnt > 0: _add_hit(tr, "depot_take", it)
		y += 23.0

# 8. Megastructures Modal
func _draw_mega_modal(vp: Vector2, font: Font) -> void:
	var mw := minf(vp.x - 24.0, 480.0); var mh := 260.0
	var r := Rect2((vp.x - mw) * 0.5, (vp.y - mh) * 0.5 - 20.0, mw, mh)
	_panel(r, Color(0.04, 0.06, 0.12, 0.96), Color(0.62, 0.48, 0.96), 2.0)
	root_ctrl.draw_string(font, Vector2(r.position.x + 14, r.position.y + 22), "ORBITAL MEGASTRUCTURES", HORIZONTAL_ALIGNMENT_LEFT, int(mw - 86), 13, Color(0.76, 0.64, 1.0))
	var cr := Rect2(r.end.x - 66, r.position.y + 6, 56, 22)
	_panel(cr, Color(0.28, 0.08, 0.10, 0.92), Color(1.0, 0.42, 0.42), 1.4)
	root_ctrl.draw_string(font, Vector2(cr.position.x, cr.position.y + 15), "CLOSE", HORIZONTAL_ALIGNMENT_CENTER, cr.size.x, 10, Color.WHITE)
	_add_hit(cr, "close")
	var y := r.position.y + 42.0
	for mid in ["elevator", "dyson", "citadel", "warpgate"]:
		var built := bool(State.megastructures[mid])
		var mr := Rect2(r.position.x + 14, y, mw - 28, 44)
		_panel(mr, Color(0.08, 0.26, 0.18, 0.92) if built else Color(0.07, 0.10, 0.17, 0.92), Color(0.36, 1.0, 0.72) if built else Color(0.40, 0.52, 0.68), 1.4)
		var cs: Array[String] = []
		for k in State.MEGAS[mid]["cost"].keys(): cs.append("%s:%d" % [String(k).to_upper(), int(State.MEGAS[mid]["cost"][k])])
		root_ctrl.draw_string(font, Vector2(mr.position.x + 10, mr.position.y + 17), String(State.MEGAS[mid]["name"]) + (" [COMPLETE]" if built else ""), HORIZONTAL_ALIGNMENT_LEFT, int(mr.size.x - 20), 12, Color.WHITE)
		root_ctrl.draw_string(font, Vector2(mr.position.x + 10, mr.position.y + 34), "Cost: " + " ".join(cs), HORIZONTAL_ALIGNMENT_LEFT, int(mr.size.x - 20), 10, Color(0.70, 0.82, 0.94))
		if not built: _add_hit(mr, "mega_buy", mid)
		y += 50.0

# 9. Touch Controls (Mobile / Touch Devices ONLY!)
func _draw_touch_controls(font: Font) -> void:
	root_ctrl.draw_circle(joy_center, joy_r, Color(0.04, 0.08, 0.14, 0.52))
	root_ctrl.draw_arc(joy_center, joy_r, 0.0, TAU, 32, Color(0.36, 0.80, 1.0, 0.72), 2.0)
	var pk := joy_center + joy_vec * (joy_r * 0.62)
	root_ctrl.draw_circle(pk, 18.0, Color(0.10, 0.24, 0.38, 0.88))
	root_ctrl.draw_arc(pk, 18.0, 0.0, TAU, 24, Color(0.45, 0.96, 1.0), 2.0)

	root_ctrl.draw_circle(act_center, 32.0, Color(0.06, 0.16, 0.14, 0.80))
	root_ctrl.draw_arc(act_center, 32.0, 0.0, TAU, 24, Color(0.35, 0.96, 0.68), 2.2)
	root_ctrl.draw_string(font, act_center + Vector2(-28, 4), "ACT" if State.selected_tool == "mine" else "USE", HORIZONTAL_ALIGNMENT_CENTER, 56, 12, Color.WHITE)

	root_ctrl.draw_circle(brk_center, 24.0, Color(0.18, 0.07, 0.09, 0.78))
	root_ctrl.draw_arc(brk_center, 24.0, 0.0, TAU, 24, Color(1.0, 0.44, 0.42), 2.0)
	root_ctrl.draw_string(font, brk_center + Vector2(-22, 4), "BRK", HORIZONTAL_ALIGNMENT_CENTER, 44, 10, Color.WHITE)
