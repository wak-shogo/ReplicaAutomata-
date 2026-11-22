extends CanvasLayer

# STAR REPLICA: AUTOMA - ビジュアル重視・大型フォント日本語HUD
# ・ドット絵アイコン＆フロー図解で文字を最小限に抑制
# ・研究ツリーカードタップ → 専用「技術詳細ポップアップ」（右上「閉じる」＋下部横長「研究する」ボタン）
# ・軌道施設インスペクタ＆同一軌道ワンタップ配置対応
# ・モバイル実機シングルタップ保護・2本指ピンチズーム・ツインスティック採掘完全維持

enum Modal { NONE, CRAFT, TECH, COMMAND, DEPOT, GUIDE, BUILDING, ORBITAL, ITEM_TREE }

var planet: SphericalPlanet = null
var grid: Node2D = null
var orbital: Node2D = null
var player: Node2D = null
var swarm: Node2D = null
var game_root: Node2D = null

var modal: int = Modal.NONE
var craft_tab: int = 0
var tech_sel: int = 1
var tech_detail_open: bool = false
var item_tree_sel: String = "circuit"
var guide_tab: int = 0
var depot_uid: int = -1
var inspect_uid: int = -1
var orbital_uid: int = -1
var redrop_armed: bool = false
var anim_t: float = 0.0

# モバイル／タッチ仮想コントロール
var touch_ui_active: bool = false
var _last_touch_ms: int = -10000
var joy_center: Vector2 = Vector2.ZERO
var joy_r: float = 52.0
var joy_vec: Vector2 = Vector2.ZERO
var joy_pid: int = -1
var act_center: Vector2 = Vector2.ZERO
var mine_r: float = 48.0
var mine_vec: Vector2 = Vector2.ZERO
var act_pid: int = -1
var brk_center: Vector2 = Vector2.ZERO
var brk_pid: int = -1

# 2本指ピンチズーム & 単タップ判定
var _pinch_pts: Dictionary = {}
var _pinch_dist: float = 0.0
var _pinch_active: bool = false
var _tap_pid: int = -1
var _tap_start_raw: Vector2 = Vector2.ZERO
var _tap_moved: bool = false

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

func open_building(uid: int) -> void:
	inspect_uid = uid
	modal = Modal.BUILDING
	root_ctrl.queue_redraw()

func open_orbital(uid: int) -> void:
	orbital_uid = uid
	modal = Modal.ORBITAL
	root_ctrl.queue_redraw()

func _hud_vp() -> Vector2:
	var raw := get_viewport().get_visible_rect().size
	if raw.y > raw.x * 1.1:
		touch_ui_active = true
		var s := clampf(raw.x / 500.0, 1.35, 2.6)
		scale = Vector2(s, s)
		return raw / s
	scale = Vector2.ONE
	return raw

func _process(delta: float) -> void:
	anim_t += delta
	var vp := _hud_vp()
	joy_r = 52.0
	mine_r = 48.0
	joy_center = Vector2(joy_r + 20.0, vp.y - joy_r - 122.0)
	act_center = Vector2(vp.x - mine_r - 18.0, vp.y - mine_r - 124.0)
	brk_center = Vector2(act_center.x - mine_r - 34.0, vp.y - 140.0)

	var kb := Vector2.ZERO
	if modal == Modal.NONE:
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): kb.x += 1.0
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):  kb.x -= 1.0
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):  kb.y += 1.0
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):    kb.y -= 1.0
		if kb.length() > 1.0: kb = kb.normalized()

	if player:
		player.move_input = joy_vec if joy_vec.length() > 0.08 else kb
		player.manual_aim_dir = mine_vec if (act_pid != -1 and mine_vec.length() > 0.12) else Vector2.ZERO
		player.braking = (brk_pid != -1) or Input.is_key_pressed(KEY_SHIFT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
		var cam := get_viewport().get_camera_2d()
		if cam:
			if not touch_ui_active:
				var mpos := get_viewport().get_mouse_position()
				var wp := cam.get_canvas_transform().affine_inverse() * mpos
				player.aim_world = wp
				if grid: grid.hover_world = wp
			else:
				player.aim_world = Vector2.ZERO
				if grid: grid.hover_world = player.position
			if grid:
				grid.show_ghost = (modal == Modal.NONE and State.BLD.has(State.selected_tool) and not State.is_orbital_bld(State.selected_tool) and State.get_stock(State.selected_tool) > 0)
		player.firing_mine = (modal == Modal.NONE and State.selected_tool == "mine" and (act_pid != -1 or Input.is_key_pressed(KEY_SPACE)))

	root_ctrl.queue_redraw()

func _handle_world_tap(wp: Vector2) -> bool:
	if orbital and orbital.handle_world_click(wp):
		return true
	if grid and grid.handle_world_click(wp):
		return true
	return false

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		_on_key(event.keycode)
		return

	if event is InputEventScreenTouch:
		touch_ui_active = true
		_last_touch_ms = Time.get_ticks_msec()
		var p: Vector2 = event.position / maxf(0.1, scale.x)
		if event.pressed: _on_down(event.index, p, event.position)
		else: _on_up(event.index, event.position)
	elif event is InputEventScreenDrag:
		touch_ui_active = true
		_last_touch_ms = Time.get_ticks_msec()
		var p: Vector2 = event.position / maxf(0.1, scale.x)
		if event.index == joy_pid:
			_upd_joy(p)
			get_viewport().set_input_as_handled()
		elif event.index == act_pid:
			_upd_mine_stick(p)
			get_viewport().set_input_as_handled()
		elif _pinch_pts.has(event.index):
			_pinch_pts[event.index] = event.position
			if _pinch_pts.size() >= 2:
				var ks := _pinch_pts.keys()
				var new_d: float = Vector2(_pinch_pts[ks[0]]).distance_to(Vector2(_pinch_pts[ks[1]]))
				if _pinch_dist > 12.0 and new_d > 12.0 and game_root:
					game_root.adjust_zoom(new_d / _pinch_dist)
				_pinch_dist = new_d
				_pinch_active = true
				_tap_pid = -1
			elif event.index == _tap_pid and event.position.distance_to(_tap_start_raw) > 22.0:
				_tap_moved = true
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		if event.device == InputEvent.DEVICE_ID_EMULATION or (Time.get_ticks_msec() - _last_touch_ms) < 450:
			return
		var p: Vector2 = event.position / maxf(0.1, scale.x)
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed: _on_down(-10, p, event.position)
			else: _on_up(-10, event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if tech_detail_open:
				tech_detail_open = false; Sfx.play("click")
			elif modal != Modal.NONE:
				modal = Modal.NONE; Sfx.play("click")
			elif State.selected_tool != "mine":
				State.selected_tool = "mine"
				if grid:
					grid.wire_pick_uid = -1; grid.conveyor_pick_uid = -1; grid.salvage_armed_uid = -1
				Sfx.play("click")
	elif event is InputEventMouseMotion:
		if event.device == InputEvent.DEVICE_ID_EMULATION or (Time.get_ticks_msec() - _last_touch_ms) < 450:
			return
		var p: Vector2 = event.position / maxf(0.1, scale.x)
		if joy_pid == -10: _upd_joy(p)
		elif act_pid == -10: _upd_mine_stick(p)

func _on_key(code: int) -> void:
	match code:
		KEY_C:
			tech_detail_open = false
			modal = Modal.NONE if modal == Modal.CRAFT else Modal.CRAFT
			Sfx.play("select")
		KEY_T:
			tech_detail_open = false
			modal = Modal.NONE if modal == Modal.TECH else Modal.TECH
			Sfx.play("select")
		KEY_M:
			tech_detail_open = false
			if modal == Modal.COMMAND:
				modal = Modal.NONE
			else:
				State.orbit_view = not State.orbit_view
				if State.orbit_view: State.tut_opened_orbit = true
			Sfx.play("click")
		KEY_H:
			tech_detail_open = false
			modal = Modal.NONE if modal == Modal.GUIDE else Modal.GUIDE
			Sfx.play("select")
		KEY_I:
			tech_detail_open = false
			modal = Modal.NONE if modal == Modal.ITEM_TREE else Modal.ITEM_TREE
			Sfx.play("select")
		KEY_ESCAPE:
			if tech_detail_open:
				tech_detail_open = false
			elif modal != Modal.NONE:
				modal = Modal.NONE
			else:
				State.selected_tool = "mine"
				if grid: grid.wire_pick_uid = -1; grid.conveyor_pick_uid = -1
			Sfx.play("click")
		KEY_E:
			if modal == Modal.NONE and grid and player:
				grid.interact_near_player(player.position)

func _on_down(pid: int, pos: Vector2, raw_pos: Vector2) -> void:
	if touch_ui_active and modal == Modal.NONE:
		if pos.distance_to(joy_center) <= joy_r + 30.0:
			joy_pid = pid; _upd_joy(pos); get_viewport().set_input_as_handled(); return
		if pos.distance_to(act_center) <= mine_r + 24.0:
			act_pid = pid; _upd_mine_stick(pos)
			if player:
				if State.selected_tool == "mine":
					player.firing_mine = true
				else:
					_handle_world_tap(player.position)
			get_viewport().set_input_as_handled(); return
		if pos.distance_to(brk_center) <= 30.0:
			brk_pid = pid; get_viewport().set_input_as_handled(); return

	for i in range(_hits.size() - 1, -1, -1):
		if Rect2(_hits[i]["r"]).has_point(pos):
			_exec(_hits[i])
			get_viewport().set_input_as_handled()
			return

	if modal == Modal.NONE:
		if pid == -10:
			var cam := get_viewport().get_camera_2d()
			if cam:
				var wp := cam.get_canvas_transform().affine_inverse() * raw_pos
				if _handle_world_tap(wp):
					get_viewport().set_input_as_handled()
		else:
			_pinch_pts[pid] = raw_pos
			if _pinch_pts.size() >= 2:
				var ks := _pinch_pts.keys()
				_pinch_dist = Vector2(_pinch_pts[ks[0]]).distance_to(Vector2(_pinch_pts[ks[1]]))
				_pinch_active = true
				_tap_pid = -1
			else:
				_tap_pid = pid
				_tap_start_raw = raw_pos
				_tap_moved = false

func _on_up(pid: int, raw_pos: Vector2 = Vector2.ZERO) -> void:
	if pid == joy_pid: joy_pid = -1; joy_vec = Vector2.ZERO
	if pid == act_pid: act_pid = -1; mine_vec = Vector2.ZERO
	if pid == brk_pid: brk_pid = -1
	if _pinch_pts.has(pid): _pinch_pts.erase(pid)
	if pid == _tap_pid:
		var was_tap := (not _pinch_active) and (not _tap_moved) and modal == Modal.NONE
		_tap_pid = -1
		if was_tap:
			var cam := get_viewport().get_camera_2d()
			if cam:
				var wp := cam.get_canvas_transform().affine_inverse() * (raw_pos if raw_pos != Vector2.ZERO else _tap_start_raw)
				_handle_world_tap(wp)
	if _pinch_pts.size() < 2: _pinch_dist = 0.0
	if _pinch_pts.is_empty(): _pinch_active = false

func _upd_joy(pos: Vector2) -> void:
	var d := pos - joy_center
	if d.length() > joy_r: d = d.normalized() * joy_r
	joy_vec = d / maxf(1.0, joy_r)

func _upd_mine_stick(pos: Vector2) -> void:
	var d := pos - act_center
	if d.length() > mine_r: d = d.normalized() * mine_r
	mine_vec = d / maxf(1.0, mine_r)

func _pick_tool(tid: String) -> void:
	if tid == "wire" and not State.is_unlocked("wire"):
		Sfx.play("error"); State.add_log("要研究: 電力とテスラ", "warn"); return
	if tid == "conveyor" and not State.is_unlocked("conveyor"):
		Sfx.play("error"); State.add_log("要研究: 洞窟物流ライン", "warn"); return
	if State.BLD.has(tid) and State.get_stock(tid) <= 0:
		Sfx.play("error"); State.add_log("在庫なし（クラフトで製造）", "warn"); return
	State.selected_tool = tid
	if grid:
		if tid != "wire": grid.wire_pick_uid = -1
		if tid != "conveyor": grid.conveyor_pick_uid = -1
		if tid != "salvage": grid.salvage_armed_uid = -1
	Sfx.play("select")

func _exec(h: Dictionary) -> void:
	var act := String(h["a"])
	match act:
		"open_craft":
			tech_detail_open = false
			modal = Modal.NONE if modal == Modal.CRAFT else Modal.CRAFT
			if modal == Modal.CRAFT:
				if State.tut_step == 1: craft_tab = 0
				elif State.tut_step == 3: craft_tab = 1
			Sfx.play("select")
		"open_tech":
			tech_detail_open = false
			modal = Modal.NONE if modal == Modal.TECH else Modal.TECH
			if modal == Modal.TECH and State.tut_step == 2:
				tech_sel = 1
			Sfx.play("select")
		"open_cmd":
			tech_detail_open = false
			modal = Modal.NONE if modal == Modal.COMMAND else Modal.COMMAND
			Sfx.play("select")
		"open_guide":
			tech_detail_open = false
			modal = Modal.NONE if modal == Modal.GUIDE else Modal.GUIDE
			Sfx.play("select")
		"open_item_tree":
			tech_detail_open = false
			modal = Modal.NONE if modal == Modal.ITEM_TREE else Modal.ITEM_TREE
			Sfx.play("select")
		"item_tree_pick":
			item_tree_sel = String(h["v"])
			Sfx.play("click")
		"close":
			modal = Modal.NONE; tech_detail_open = false; redrop_armed = false; Sfx.play("click")
		"close_tech_detail":
			tech_detail_open = false; Sfx.play("click")
		"noop":
			pass
		"craft_tab":
			craft_tab = int(h["v"]); Sfx.play("click")
		"craft_drone":
			State.enqueue_craft("drone", "fab_drone")
		"craft_prop":
			State.enqueue_craft("propulsion", str(State.propulsion_tier + 1))
		"craft_bld":
			State.enqueue_craft("building", String(h["v"]))
		"cancel_q":
			State.cancel_craft(int(h["v"]))
		"equip_place":
			var bid := String(h["v"])
			if State.get_stock(bid) > 0:
				State.selected_tool = bid
				modal = Modal.NONE
				Sfx.play("select")
		"deploy_orb_now":
			if orbital and State.is_orbital_bld(State.selected_tool):
				orbital.deploy_on_player_orbit(State.selected_tool)
		"tool":
			_pick_tool(String(h["v"]))
		"cancel_tool":
			State.selected_tool = "mine"
			if grid:
				grid.wire_pick_uid = -1; grid.conveyor_pick_uid = -1; grid.salvage_armed_uid = -1
			Sfx.play("click")
		"tech_open_card":
			tech_sel = int(h["v"])
			tech_detail_open = true
			Sfx.play("select")
		"tech_buy":
			if State.research(String(h["v"])):
				tech_detail_open = false
		"toggle_orbit":
			State.orbit_view = not State.orbit_view
			if State.orbit_view: State.tut_opened_orbit = true
			modal = Modal.NONE
			Sfx.play("click")
		"doc":
			State.doctrine = int(h["v"]); Sfx.play("select")
		"mega_buy":
			State.build_mega(String(h["v"]))
		"mute":
			Sfx.muted = not Sfx.muted
		"redrop":
			if not redrop_armed: redrop_armed = true; Sfx.play("click")
			else:
				redrop_armed = false; modal = Modal.NONE
				if player: player.emergency_redrop()
		"tut_toggle":
			State.tut_enabled = not State.tut_enabled; Sfx.play("click")
		"guide_tab":
			guide_tab = int(h["v"]); Sfx.play("click")
		"depot_all":
			if grid: grid.depot_deposit_all(depot_uid)
		"depot_link_flt":
			if grid: grid.depot_cycle_link_filter(int(h["v"]))
		"depot_conv":
			if grid:
				grid.start_conveyor_from(depot_uid); modal = Modal.NONE
		"depot_take":
			if grid: grid.depot_transfer(depot_uid, String(h["v"]), false, 5)
		"bld_collect":
			if grid: grid.building_collect(inspect_uid)
		"bld_feed":
			if grid: grid.building_hand_feed(inspect_uid)
		"bld_recipe":
			if grid: grid.building_cycle_recipe(inspect_uid)
		"bld_wire":
			if grid: grid.start_wire_from(inspect_uid); modal = Modal.NONE
		"bld_conv":
			if grid: grid.start_conveyor_from(inspect_uid); modal = Modal.NONE
		"bld_salvage":
			if grid and grid.salvage_by_uid(inspect_uid):
				inspect_uid = -1; modal = Modal.NONE
		"orb_recipe":
			if orbital: orbital.module_cycle_recipe(orbital_uid)
		"orb_feed":
			if orbital: orbital.module_hand_feed(orbital_uid)
		"orb_collect":
			if orbital: orbital.module_collect(orbital_uid)
		"orb_salvage":
			if orbital and orbital.salvage_module(orbital_uid):
				orbital_uid = -1; modal = Modal.NONE

func _add_hit(r: Rect2, a: String, v = null) -> void:
	_hits.append({"r": r, "a": a, "v": v})

func _panel(r: Rect2, bg: Color, edge: Color, bw: float = 1.6) -> void:
	root_ctrl.draw_rect(r, bg)
	root_ctrl.draw_rect(r, edge, false, bw)

func _pulse_frame(r: Rect2) -> void:
	var a := 0.65 + 0.35 * sin(anim_t * 6.5)
	var pad := 2.0 + sin(anim_t * 6.5) * 1.5
	root_ctrl.draw_rect(r.grow(pad), Color(1.0, 0.86, 0.24, a), false, 3.0)

# ------------------------------------------------------------------------------
# PIXEL-ART VISUAL DIAGRAM HELPERS (REPLACE VERBOSE TEXT WITH SPRITES & ARROWS!)
# ------------------------------------------------------------------------------
func _get_visual_tex(key: String) -> Texture2D:
	var t := ArtReg.get_t(key)
	if t != null: return t
	return ArtReg.get_icon(key)

func _draw_cost_icons(pos: Vector2, cost: Dictionary, font: Font, icon_sz: float = 18.0, fs: int = 14, show_have: bool = false) -> void:
	if cost.is_empty():
		root_ctrl.draw_string(font, pos + Vector2(0, icon_sz - 2), "FREE", HORIZONTAL_ALIGNMENT_LEFT, 80, fs, Color(0.45, 1.0, 0.76))
		return
	var x := pos.x
	for k in cost.keys():
		var kn := String(k)
		var need := int(cost[k])
		var have := State.get_r(kn)
		var ok := have >= need
		var ic := ArtReg.get_icon(kn)
		if ic:
			root_ctrl.draw_texture_rect(ic, Rect2(x, pos.y, icon_sz, icon_sz), false)
		var txt := ("%d/%d" % [have, need]) if show_have else ("%d" % need)
		var tw := 68.0 if show_have else 40.0
		root_ctrl.draw_string(font, Vector2(x + icon_sz + 4, pos.y + icon_sz - 2), txt, HORIZONTAL_ALIGNMENT_LEFT, int(tw), fs, Color(0.48, 1.0, 0.76) if ok else Color(1.0, 0.46, 0.42))
		x += icon_sz + tw + 8.0

func _draw_flow_diagram(rect: Rect2, keys: Array, font: Font, labels: Array = []) -> void:
	_panel(rect, Color(0.03, 0.06, 0.12, 0.96), Color(0.28, 0.50, 0.70, 0.85), 1.4)
	var n := keys.size()
	if n == 0: return
	var pad := 14.0
	var step_w := (rect.size.x - pad * 2.0) / float(n)
	var spr_sz := clampf(minf(step_w * 0.56, rect.size.y - (26.0 if not labels.is_empty() else 14.0)), 24.0, 48.0)
	for i in range(n):
		var cx := rect.position.x + pad + (float(i) + 0.5) * step_w
		var cy := rect.position.y + (rect.size.y * 0.42 if not labels.is_empty() else rect.size.y * 0.5)
		var box_r := Rect2(cx - spr_sz * 0.6, cy - spr_sz * 0.6, spr_sz * 1.2, spr_sz * 1.2)
		_panel(box_r, Color(0.07, 0.13, 0.22, 0.92), Color(0.36, 0.76, 0.96, 0.72), 1.2)
		var t := _get_visual_tex(String(keys[i]))
		if t:
			root_ctrl.draw_texture_rect(t, Rect2(cx - spr_sz * 0.48, cy - spr_sz * 0.48, spr_sz * 0.96, spr_sz * 0.96), false)
		if i < labels.size():
			root_ctrl.draw_string(font, Vector2(cx - step_w * 0.48, rect.end.y - 6), String(labels[i]), HORIZONTAL_ALIGNMENT_CENTER, step_w * 0.96, 11, Color(0.86, 0.94, 1.0))
		if i < n - 1:
			var ax0 := box_r.end.x + 4.0
			var ax1 := rect.position.x + pad + (float(i + 1) + 0.5) * step_w - spr_sz * 0.6 - 4.0
			if ax1 > ax0 + 6.0:
				root_ctrl.draw_line(Vector2(ax0, cy), Vector2(ax1, cy), Color(0.42, 0.96, 1.0, 0.92), 2.4)
				root_ctrl.draw_polygon(PackedVector2Array([Vector2(ax1, cy), Vector2(ax1 - 7, cy - 5), Vector2(ax1 - 7, cy + 5)]), PackedColorArray([Color(0.42, 0.96, 1.0)]))

func _draw_recipe_visual(rect: Rect2, in_dict: Dictionary, out_id: String, out_qty: int, font: Font) -> void:
	_panel(rect, Color(0.04, 0.08, 0.15, 0.95), Color(0.32, 0.58, 0.78), 1.3)
	var x := rect.position.x + 12.0
	var cy := rect.position.y + rect.size.y * 0.5
	var idx := 0
	for k in in_dict.keys():
		var kn := String(k)
		var ic := ArtReg.get_icon(kn)
		if ic:
			root_ctrl.draw_texture_rect(ic, Rect2(x, cy - 11, 22, 22), false)
		root_ctrl.draw_string(font, Vector2(x + 25, cy + 6), "×%d" % int(in_dict[k]), HORIZONTAL_ALIGNMENT_LEFT, 36, 14, Color.WHITE)
		x += 62.0
		idx += 1
		if idx < in_dict.size():
			root_ctrl.draw_string(font, Vector2(x - 8, cy + 5), "+", HORIZONTAL_ALIGNMENT_CENTER, 16, 15, Color(0.68, 0.82, 0.96))
			x += 12.0
	# Glowing arrow
	root_ctrl.draw_line(Vector2(x + 2, cy), Vector2(x + 28, cy), Color(0.42, 0.98, 0.80), 2.6)
	root_ctrl.draw_polygon(PackedVector2Array([Vector2(x + 30, cy), Vector2(x + 22, cy - 5), Vector2(x + 22, cy + 5)]), PackedColorArray([Color(0.42, 0.98, 0.80)]))
	x += 38.0
	var oic := ArtReg.get_icon(out_id)
	if oic:
		root_ctrl.draw_texture_rect(oic, Rect2(x, cy - 12, 24, 24), false)
	root_ctrl.draw_string(font, Vector2(x + 28, cy + 6), "%s ×%d" % [State.res_name(out_id), out_qty], HORIZONTAL_ALIGNMENT_LEFT, int(rect.end.x - x - 32), 14, Color(0.52, 1.0, 0.82))

# ------------------------------------------------------------------------------
# メイン描画
# ------------------------------------------------------------------------------
func _on_draw() -> void:
	_hits.clear()
	var vp := _hud_vp()
	var portrait := vp.y > vp.x * 1.1
	var font := ArtReg.get_font()

	_draw_diegetic_arcs(vp, font)
	_draw_top_left_status(vp, portrait, font)
	_draw_top_right_menu(vp, portrait, font)
	if State.tut_enabled and modal == Modal.NONE:
		_draw_tutorial_banner(vp, portrait, font)
	_draw_bottom_right_telemetry(vp, portrait, font)
	_draw_bottom_dock(vp, portrait, font)

	match modal:
		Modal.CRAFT:     _draw_craft_modal(vp, portrait, font)
		Modal.TECH:      _draw_tech_modal(vp, portrait, font)
		Modal.COMMAND:   _draw_command_modal(vp, portrait, font)
		Modal.DEPOT:     _draw_depot_modal(vp, font)
		Modal.BUILDING:  _draw_building_modal(vp, font)
		Modal.ORBITAL:   _draw_orbital_modal(vp, font)
		Modal.GUIDE:     _draw_guide_modal(vp, portrait, font)
		Modal.ITEM_TREE: _draw_item_tree_modal(vp, portrait, font)

	if touch_ui_active and modal == Modal.NONE:
		_draw_touch_controls(font)

	if State.game_won:
		var vr := Rect2(vp.x * 0.5 - 240, 74, 480, 48)
		_panel(vr, Color(0.06, 0.24, 0.16, 0.96), Color(0.36, 1.0, 0.72), 2.2)
		root_ctrl.draw_string(font, Vector2(vr.position.x, vr.position.y + 31), "完全勝利：星系解放＆ワープゲート起動！", HORIZONTAL_ALIGNMENT_CENTER, vr.size.x, 16, Color(0.90, 1.0, 0.94))

# 1. 自機周囲のHUD円弧（耐久・燃料・イオン・軌道ロック表示）
func _draw_diegetic_arcs(vp: Vector2, font: Font) -> void:
	if not player or State.orbit_view: return
	var cam := get_viewport().get_camera_2d()
	if not cam or cam.zoom.x < 0.15: return
	var sp := (cam.get_canvas_transform() * player.global_position) / maxf(0.1, scale.x)
	if not Rect2(Vector2(-60, -60), vp + Vector2(120, 120)).has_point(sp): return
	var rad := 48.0 + float(State.attached_drones) * 2.5
	var hp_f := clampf(State.hp / maxf(1.0, State.max_hp), 0.0, 1.0)
	var fl_f := clampf(State.fuel / maxf(1.0, State.max_fuel), 0.0, 1.0)
	var in_f := clampf(State.ion_bat / maxf(1.0, State.max_ion_bat), 0.0, 1.0)
	var l0 := deg_to_rad(138.0); var l1 := deg_to_rad(222.0)
	root_ctrl.draw_arc(sp, rad, l0, l1, 18, Color(0.15, 0.22, 0.30, 0.45), 3.8)
	root_ctrl.draw_arc(sp, rad, l0, lerpf(l0, l1, hp_f), 18, Color(0.32, 0.92, 0.60, 0.88), 3.8)
	var r0 := deg_to_rad(42.0); var r1 := deg_to_rad(-42.0)
	root_ctrl.draw_arc(sp, rad, r1, r0, 18, Color(0.15, 0.22, 0.30, 0.45), 3.8)
	if fl_f > 0.01:
		root_ctrl.draw_arc(sp, rad, lerpf(r0, r1, fl_f), r0, 18, Color(1.0, 0.72, 0.22, 0.88), 3.8)
	root_ctrl.draw_arc(sp, rad - 6.0, lerpf(r0, r1, in_f), r0, 16, Color(0.34, 0.92, 1.0, 0.88), 2.4)
	if player.on_rails:
		root_ctrl.draw_string(font, sp + Vector2(-56, -rad - 10), "軌道ロック %dm/s" % int(player.velocity.length()), HORIZONTAL_ALIGNMENT_CENTER, 112, 13, Color(0.38, 1.0, 0.92))
	elif player.velocity.length() > 24.0:
		root_ctrl.draw_string(font, sp + Vector2(rad + 8, 5), "%dm/s" % int(player.velocity.length()), HORIZONTAL_ALIGNMENT_LEFT, 80, 13, Color(0.88, 0.95, 1.0, 0.90))

# 2. 左上ステータス（大型アイコン＆くっきり数字＋昼夜・天体・汚染度・研究ポイント1,000達成ゲージ）
func _draw_top_left_status(vp: Vector2, portrait: bool, font: Font) -> void:
	var has_ref := (State.get_r("plate_fe") + State.get_r("wire_cu") + State.get_r("wafer_si") + State.get_r("circuit")) > 0
	var w := 284.0 if not portrait else minf(vp.x - 118.0, 340.0)
	var h := (172.0 if has_ref else 146.0)
	var r := Rect2(8, 8, w, h)
	_panel(r, Color(0.04, 0.07, 0.12, 0.90), Color(0.28, 0.42, 0.58, 0.88), 1.6)

	var base_items: Array[String] = ["fe", "cu", "si", "ti"]
	var ref_items: Array[String] = ["plate_fe", "wire_cu", "wafer_si", "circuit"]
	var cw := (w - 14.0) / 4.0
	for i in range(4):
		var id: String = base_items[i]
		var x := r.position.x + 8.0 + float(i) * cw
		var y := r.position.y + 8.0
		var ic := ArtReg.get_icon(id)
		if ic: root_ctrl.draw_texture_rect(ic, Rect2(x, y, 18, 18), false)
		root_ctrl.draw_string(font, Vector2(x + 21, y + 15), "%d" % State.get_r(id), HORIZONTAL_ALIGNMENT_LEFT, int(cw - 20), 14, Color(0.96, 0.98, 1.0))

	var y2 := r.position.y + 34.0
	if has_ref:
		for i in range(4):
			var id: String = ref_items[i]
			var x := r.position.x + 8.0 + float(i) * cw
			var ic := ArtReg.get_icon(id)
			if ic: root_ctrl.draw_texture_rect(ic, Rect2(x, y2, 18, 18), false)
			root_ctrl.draw_string(font, Vector2(x + 21, y2 + 15), "%d" % State.get_r(id), HORIZONTAL_ALIGNMENT_LEFT, int(cw - 20), 14, Color(0.74, 0.94, 1.0))
		y2 += 26.0

	# 電力＋ドローン（ドット絵アイコン＋くっきり数値）
	var pcol := Color(0.36, 0.98, 0.66) if (State.pwr_prod >= State.pwr_use and State.pwr_prod > 0.0) else (Color(1.0, 0.82, 0.34) if State.pwr_stored > 10.0 else Color(0.98, 0.46, 0.40))
	var t_ic := ArtReg.get_t("tesla")
	if t_ic: root_ctrl.draw_texture_rect(t_ic, Rect2(r.position.x + 8, y2, 16, 20), false)
	var bat_s := " 蓄%d%%" % int(State.pwr_stored / maxf(1.0, State.pwr_cap) * 100.0) if State.pwr_cap > 1.0 else ""
	root_ctrl.draw_string(font, Vector2(r.position.x + 28, y2 + 16), "%d/%dW%s" % [int(State.pwr_prod), int(State.pwr_use), bat_s], HORIZONTAL_ALIGNMENT_LEFT, 146, 13, pcol)
	var d_ic := ArtReg.get_t("fab_drone")
	var dx_ic := r.position.x + w - 72.0
	if d_ic: root_ctrl.draw_texture_rect(d_ic, Rect2(dx_ic, y2 + 1, 18, 18), false)
	root_ctrl.draw_string(font, Vector2(dx_ic + 22, y2 + 16), "%d/8" % State.attached_drones, HORIZONTAL_ALIGNMENT_LEFT, 48, 13, Color(0.76, 0.94, 1.0))

	# 昼夜＆天体＆汚染度＆軌道ステータス
	y2 += 24.0
	var sun_v := planet.get_sunlight_world(player.position) if (planet and player) else 1.0
	var is_day := sun_v > 0.35
	var is_dusk := (not is_day) and sun_v > 0.05
	var sc_p := Vector2(r.position.x + 16, y2 + 10)
	if is_day:
		root_ctrl.draw_circle(sc_p, 6.5, Color(1.0, 0.88, 0.32))
	elif is_dusk:
		root_ctrl.draw_circle(sc_p, 6.5, Color(1.0, 0.56, 0.24))
	else:
		root_ctrl.draw_circle(sc_p, 6.5, Color(0.76, 0.88, 1.0))
		root_ctrl.draw_circle(sc_p + Vector2(3.0, -2.0), 5.0, Color(0.04, 0.07, 0.12))
	var dn_lbl := "昼" if is_day else ("夕" if is_dusk else "夜")
	var b_name: String = String(player.get_active_body_name()) if player else "テラ-I"
	var act_bid: String = String(player.active_body_id) if player else "terra"
	var pol_v := State.get_pollution(act_bid)
	var pol_tag := ("  汚染%d%%" % int(pol_v)) if pol_v >= 1.0 else ""
	var orb_tag := " [軌道ロック]" if (player and player.on_rails) else ""
	root_ctrl.draw_string(font, Vector2(r.position.x + 28, y2 + 15), "%s %s%s%s" % [dn_lbl, b_name, pol_tag, orb_tag], HORIZONTAL_ALIGNMENT_LEFT, int(w - 34), 13, Color(1.0, 0.44, 0.56) if pol_v >= 12.0 else (Color(0.45, 0.98, 0.90) if (player and player.on_rails) else Color(1.0, 0.90, 0.56)))

	# 研究ポイント（明確な日本語表記＋クリア目標1,000ptゲージ！）
	y2 += 23.0
	var rp_cur := State.get_r("sci_pack")
	root_ctrl.draw_string(font, Vector2(r.position.x + 8, y2 + 13), "研究ポイント: %d / %d" % [rp_cur, State.RESEARCH_POINT_GOAL], HORIZONTAL_ALIGNMENT_LEFT, int(w - 16), 13, Color(0.42, 1.0, 0.78))
	var rbar := Rect2(r.position.x + 8, y2 + 18, w - 16, 6)
	root_ctrl.draw_rect(rbar, Color(0.08, 0.14, 0.18))
	root_ctrl.draw_rect(Rect2(rbar.position, Vector2(rbar.size.x * clampf(float(rp_cur) / float(State.RESEARCH_POINT_GOAL), 0.0, 1.0), rbar.size.y)), Color(0.36, 0.98, 0.74))

	# 艦隊ゲージ（プローブアイコン＋ゲージ）
	y2 += 26.0
	var p_ic := ArtReg.get_icon("probe_stock")
	if p_ic: root_ctrl.draw_texture_rect(p_ic, Rect2(r.position.x + 8, y2 - 1, 16, 16), false)
	root_ctrl.draw_string(font, Vector2(r.position.x + 28, y2 + 12), "艦隊 %d / 10,000" % State.swarm_fleet, HORIZONTAL_ALIGNMENT_LEFT, int(w - 36), 13, Color(1.0, 0.86, 0.42))
	var br := Rect2(r.position.x + 8, y2 + 17, w - 16, 6)
	root_ctrl.draw_rect(br, Color(0.10, 0.14, 0.22))
	root_ctrl.draw_rect(Rect2(br.position, Vector2(br.size.x * clampf(float(State.swarm_fleet) / 10000.0, 0.0, 1.0), br.size.y)), Color(0.34, 0.86, 1.0))

	if not State.craft_queue.is_empty():
		var q0: Dictionary = State.craft_queue[0]
		var pct := clampf(1.0 - float(q0["time_left"]) / maxf(0.1, float(q0["total_time"])), 0.0, 1.0)
		var qr := Rect2(8, r.end.y + 6, w, 40)
		_panel(qr, Color(0.06, 0.14, 0.22, 0.94), Color(0.38, 0.92, 1.0), 1.6)
		var extra := " (+%d)" % (State.craft_queue.size() - 1) if State.craft_queue.size() > 1 else ""
		root_ctrl.draw_string(font, Vector2(qr.position.x + 8, qr.position.y + 19), "製造中: %s%s" % [String(q0["name"]), extra], HORIZONTAL_ALIGNMENT_LEFT, int(w - 16), 13, Color.WHITE)
		root_ctrl.draw_rect(Rect2(qr.position.x + 8, qr.position.y + 27, w - 16, 7), Color(0.10, 0.16, 0.24))
		root_ctrl.draw_rect(Rect2(qr.position.x + 8, qr.position.y + 27, (w - 16) * pct, 7), Color(0.34, 0.96, 0.72))
		_add_hit(qr, "open_craft")

# 3. 右上ミニマル4ボタン（見やすい大型ボタン）
func _draw_top_right_menu(vp: Vector2, portrait: bool, font: Font) -> void:
	var bw := 112.0 if not portrait else 100.0
	var x := vp.x - bw - 8.0
	var y := 8.0
	var tut_f := String(State.get_tutorial_info()["focus"]) if State.tut_enabled else ""

	var cr := Rect2(x, y, bw, 38)
	var qn := State.craft_queue.size()
	var c_lbl := ("クラフト(%d)" % qn) if qn > 0 else "クラフト"
	_panel(cr, Color(0.08, 0.22, 0.34, 0.95) if modal == Modal.CRAFT else Color(0.05, 0.09, 0.16, 0.92), Color(0.42, 0.94, 1.0), 1.8)
	root_ctrl.draw_string(font, Vector2(cr.position.x, cr.position.y + 25), c_lbl, HORIZONTAL_ALIGNMENT_CENTER, bw, 14, Color.WHITE)
	if modal == Modal.NONE and (tut_f == "craft_drone" or tut_f == "craft_power"):
		_pulse_frame(cr)
	_add_hit(cr, "open_craft")
	y += 44.0

	var ready_t := false
	for tid in State.TECH_ORDER:
		if State.can_research(tid): ready_t = true; break
	var tr := Rect2(x, y, bw, 38)
	_panel(tr, Color(0.12, 0.22, 0.34, 0.95) if modal == Modal.TECH else Color(0.05, 0.09, 0.16, 0.92), Color(1.0, 0.84, 0.32) if ready_t else Color(0.36, 0.78, 1.0), 1.8)
	root_ctrl.draw_string(font, Vector2(tr.position.x, tr.position.y + 25), "研究 %d/8" % State.unlocked_techs.size(), HORIZONTAL_ALIGNMENT_CENTER, bw, 14, Color(1.0, 0.92, 0.56) if ready_t else Color.WHITE)
	if modal == Modal.NONE and tut_f == "research_power":
		_pulse_frame(tr)
	_add_hit(tr, "open_tech")
	y += 44.0

	var mr := Rect2(x, y, bw, 38)
	_panel(mr, Color(0.14, 0.16, 0.32, 0.95) if (modal == Modal.COMMAND or State.orbit_view) else Color(0.05, 0.09, 0.16, 0.92), Color(0.64, 0.56, 1.0), 1.6)
	root_ctrl.draw_string(font, Vector2(mr.position.x, mr.position.y + 25), "星系地図" if not State.orbit_view else "機体視点", HORIZONTAL_ALIGNMENT_CENTER, bw, 14, Color.WHITE)
	_add_hit(mr, "toggle_orbit" if State.orbit_view else "open_cmd")
	y += 44.0

	var gr := Rect2(x, y, bw, 34)
	_panel(gr, Color(0.06, 0.20, 0.24, 0.95) if modal == Modal.ITEM_TREE else Color(0.05, 0.09, 0.16, 0.90), Color(0.42, 0.96, 0.82), 1.6)
	root_ctrl.draw_string(font, Vector2(gr.position.x, gr.position.y + 23), "レシピ図", HORIZONTAL_ALIGNMENT_CENTER, bw, 14, Color(0.86, 1.0, 0.94))
	_add_hit(gr, "open_item_tree")

# 4. ビジュアル重視のコンパクト目標バー（アイコン＋短い誘導のみ！）
func _draw_tutorial_banner(vp: Vector2, portrait: bool, font: Font) -> void:
	var info := State.get_tutorial_info()
	var w := minf(vp.x - 16.0, 480.0) if not portrait else (vp.x - 16.0)
	var h := 48.0
	var x := (vp.x - w) * 0.5 if not portrait else 8.0
	var y := 8.0 if not portrait else 184.0
	var r := Rect2(x, y, w, h)
	_panel(r, Color(0.05, 0.11, 0.19, 0.92), Color(1.0, 0.84, 0.34, 0.94), 1.8)

	# 目標ステップに合わせたアイコン表示
	var icon_k := "ore_fe"
	match State.tut_step:
		0: icon_k = "ore_fe"
		1: icon_k = "fab_drone"
		2: icon_k = "tesla"
		3, 4: icon_k = "solar"
		5: icon_k = "tesla"
		6: icon_k = "drill"
		7: icon_k = "orbital_booster"
		_: icon_k = "mass_driver"
	var it := _get_visual_tex(icon_k)
	if it:
		root_ctrl.draw_texture_rect(it, Rect2(r.position.x + 8, r.position.y + 8, 32, 32), false)
	root_ctrl.draw_string(font, Vector2(r.position.x + 48, r.position.y + 20), "目標 %s: %s" % [String(info["step"]), String(info["title"])], HORIZONTAL_ALIGNMENT_LEFT, int(w - 114), 14, Color(1.0, 0.90, 0.44))
	if State.tut_step == 0:
		_draw_cost_icons(Vector2(r.position.x + 48, r.position.y + 25), {"fe": 10, "cu": 6}, font, 16.0, 13, true)
	else:
		root_ctrl.draw_string(font, Vector2(r.position.x + 48, r.position.y + 40), String(info["hint"]), HORIZONTAL_ALIGNMENT_LEFT, int(w - 60), 12, Color(0.92, 0.96, 1.0))

	var hr := Rect2(r.end.x - 54, r.position.y + 6, 48, 20)
	_panel(hr, Color(0.10, 0.14, 0.22, 0.90), Color(0.42, 0.54, 0.68), 1.0)
	root_ctrl.draw_string(font, Vector2(hr.position.x, hr.position.y + 15), "隠す", HORIZONTAL_ALIGNMENT_CENTER, hr.size.x, 11, Color(0.84, 0.90, 0.96))
	_add_hit(hr, "tut_toggle")

# 5. 右下テレメトリ（デスクトップ）
func _draw_bottom_right_telemetry(vp: Vector2, portrait: bool, font: Font) -> void:
	if portrait: return
	var w := 330.0; var h := 106.0
	var r := Rect2(vp.x - w - 8.0, vp.y - h - 8.0, w, h)
	_panel(r, Color(0.04, 0.06, 0.10, 0.88), Color(0.24, 0.36, 0.50, 0.88), 1.4)
	var g_v: float = float(player.local_g) if player else 1.0
	var vl_v: int = int(player.velocity.length()) if player else 0
	var al_v: int = int(player.get_altitude()) if player else 0
	root_ctrl.draw_string(font, Vector2(r.position.x + 10, r.position.y + 20), "%.2fG  %dm/s  高度 %dm" % [g_v, vl_v, al_v], HORIZONTAL_ALIGNMENT_LEFT, int(w - 18), 13, Color(0.76, 0.90, 1.0))
	root_ctrl.draw_line(Vector2(r.position.x + 6, r.position.y + 28), Vector2(r.end.x - 6, r.position.y + 28), Color(0.22, 0.32, 0.44), 1.0)
	var y := r.position.y + 47.0
	var st := maxi(0, State.logs.size() - 3)
	for i in range(st, State.logs.size()):
		var lg := State.logs[i]
		var c := Color(0.45, 0.98, 0.72) if lg["kind"] == "good" else (Color(1.0, 0.80, 0.34) if lg["kind"] == "warn" else Color(0.88, 0.92, 0.98))
		root_ctrl.draw_string(font, Vector2(r.position.x + 10, y), String(lg["msg"]), HORIZONTAL_ALIGNMENT_LEFT, int(w - 18), 12, c)
		y += 19.0

# 6. 下部ドック（常設ツール ＋ 所持装置 ＋ 軌道配置ワンタップボタン！）
func _draw_bottom_dock(vp: Vector2, portrait: bool, font: Font) -> void:
	var slots: Array[Dictionary] = [{"id": "mine", "label": "通常"}]
	if State.is_unlocked("wire"): slots.append({"id": "wire", "label": "配線"})
	if State.is_unlocked("conveyor"): slots.append({"id": "conveyor", "label": "搬送"})
	slots.append({"id": "salvage", "label": "削除"})
	var owned := State.get_owned_buildings()
	for bid in owned:
		slots.append({"id": bid, "label": String(State.BLD[bid]["short"]), "cnt": State.get_stock(bid)})
	if owned.is_empty():
		slots.append({"id": "__craft", "label": "+製造"})

	var slot_sz := 54.0 if portrait else 60.0
	var gap := 6.0
	var max_slots := mini(slots.size(), 9 if not portrait else 7)
	var bar_w := float(max_slots) * (slot_sz + gap) + gap + 10.0
	var bar_h := slot_sz + 14.0
	var bx := (vp.x - bar_w) * 0.5
	var by := vp.y - bar_h - 8.0

	if modal == Modal.NONE and State.selected_tool != "mine":
		var is_orb := State.is_orbital_bld(State.selected_tool)
		var in_orb: bool = (player != null and bool(player.is_in_orbit()))
		var mw := minf(vp.x - 16.0, 520.0)
		var mr := Rect2((vp.x - mw) * 0.5, by - 42.0, mw, 36.0)
		var bar_col := Color(1.0, 0.44, 0.42) if State.selected_tool == "salvage" else (Color(0.40, 0.96, 1.0) if is_orb else Color(1.0, 0.84, 0.34))
		_panel(mr, Color(0.06, 0.16, 0.24, 0.95), bar_col, 1.8)
		var msg := ""
		if State.selected_tool == "wire": msg = "配線: 発電機 → テスラ"
		elif State.selected_tool == "conveyor": msg = "搬送: 送り元 → 送り先"
		elif State.selected_tool == "salvage": msg = "削除: 施設を2回タップ"
		elif is_orb:
			msg = "同一軌道へ配置OK！" if in_orb else "宇宙の周回軌道へ入ると配置可"
		elif State.selected_tool == "drill": msg = "光る「ドリル鉱床」をタップ"
		elif State.BLD.has(State.selected_tool): msg = "%s: 地面をタップして設置" % State.BLD[State.selected_tool]["name"]
		var right_res := 162.0 if (is_orb and in_orb) else 66.0
		root_ctrl.draw_string(font, Vector2(mr.position.x + 12, mr.position.y + 23), msg, HORIZONTAL_ALIGNMENT_LEFT, int(mw - right_res - 14), 13, Color.WHITE)
		if is_orb and in_orb:
			var dr := Rect2(mr.end.x - 156, mr.position.y + 4, 92, 28)
			_panel(dr, Color(0.08, 0.32, 0.24, 0.96), Color(0.42, 1.0, 0.78), 1.6)
			root_ctrl.draw_string(font, Vector2(dr.position.x, dr.position.y + 19), "軌道配置", HORIZONTAL_ALIGNMENT_CENTER, dr.size.x, 13, Color.WHITE)
			_add_hit(dr, "deploy_orb_now")
		var cr := Rect2(mr.end.x - 58, mr.position.y + 4, 52, 28)
		_panel(cr, Color(0.28, 0.09, 0.11, 0.94), Color(1.0, 0.44, 0.44), 1.3)
		root_ctrl.draw_string(font, Vector2(cr.position.x, cr.position.y + 19), "解除", HORIZONTAL_ALIGNMENT_CENTER, cr.size.x, 12, Color.WHITE)
		_add_hit(cr, "cancel_tool")

	var br := Rect2(bx, by, bar_w, bar_h)
	_panel(br, Color(0.05, 0.07, 0.12, 0.94), Color(0.28, 0.42, 0.58, 0.92), 1.6)
	var tut_f := String(State.get_tutorial_info()["focus"]) if State.tut_enabled else ""

	for i in range(max_slots):
		var s := slots[i]
		var tid := String(s["id"])
		var sx := bx + 8.0 + float(i) * (slot_sz + gap)
		var sy := by + 7.0
		var sr := Rect2(sx, sy, slot_sz, slot_sz)
		var sel := (State.selected_tool == tid)
		var bg := Color(0.12, 0.28, 0.40, 0.96) if sel else (Color(0.08, 0.18, 0.26, 0.94) if tid == "__craft" else Color(0.07, 0.10, 0.16, 0.92))
		var bd := Color(1.0, 0.84, 0.34) if sel else (Color(0.42, 0.96, 0.80) if State.BLD.has(tid) else Color(0.34, 0.54, 0.72))
		_panel(sr, bg, bd, 2.2 if sel else 1.3)

		var tex_k := String(State.BLD[tid]["tex"]) if State.BLD.has(tid) else ("seed_core" if tid == "mine" else "")
		var t := ArtReg.get_t(tex_k) if tex_k != "" else null
		if t:
			var pad := 6.0
			root_ctrl.draw_texture_rect(t, Rect2(sx + pad, sy + 4.0, slot_sz - pad * 2.0, slot_sz - 20.0), false)
		elif tid == "wire":
			var cx := sx + slot_sz * 0.5; var cy := sy + slot_sz * 0.38
			root_ctrl.draw_polyline(PackedVector2Array([Vector2(cx + 4, cy - 11), Vector2(cx - 5, cy + 1), Vector2(cx + 2, cy + 1), Vector2(cx - 4, cy + 12)]), Color(0.42, 0.96, 1.0), 2.8)
		elif tid == "conveyor":
			var cx := sx + slot_sz * 0.5; var cy := sy + slot_sz * 0.38
			root_ctrl.draw_line(Vector2(cx - 12, cy), Vector2(cx + 9, cy), Color(1.0, 0.80, 0.28), 3.0)
			root_ctrl.draw_polygon(PackedVector2Array([Vector2(cx + 12, cy), Vector2(cx + 3, cy - 6), Vector2(cx + 3, cy + 6)]), PackedColorArray([Color(1.0, 0.80, 0.28)]))
		elif tid == "salvage":
			var cx := sx + slot_sz * 0.5; var cy := sy + slot_sz * 0.38
			root_ctrl.draw_line(Vector2(cx - 8, cy - 8), Vector2(cx + 8, cy + 8), Color(1.0, 0.44, 0.42), 3.0)
			root_ctrl.draw_line(Vector2(cx + 8, cy - 8), Vector2(cx - 8, cy + 8), Color(1.0, 0.44, 0.42), 3.0)
		else:
			root_ctrl.draw_string(font, Vector2(sx, sy + slot_sz * 0.50), "＋", HORIZONTAL_ALIGNMENT_CENTER, slot_sz, 20, Color(0.45, 1.0, 0.76))

		root_ctrl.draw_string(font, Vector2(sx, sy + slot_sz - 4), String(s["label"]), HORIZONTAL_ALIGNMENT_CENTER, slot_sz, 11, Color.WHITE)
		if s.has("cnt"):
			var cr_b := Rect2(sx + slot_sz - 24, sy + 2, 22, 16)
			root_ctrl.draw_rect(cr_b, Color(0.08, 0.28, 0.36, 0.96))
			root_ctrl.draw_string(font, Vector2(cr_b.position.x, cr_b.position.y + 13), "x%d" % int(s["cnt"]), HORIZONTAL_ALIGNMENT_CENTER, 22, 11, Color(0.55, 1.0, 0.82))

		if modal == Modal.NONE:
			if tut_f == "place_power" and (tid == "solar" or tid == "tesla"): _pulse_frame(sr)
			elif tut_f == "wire_power" and tid == "wire": _pulse_frame(sr)

		if tid == "__craft": _add_hit(sr, "open_craft")
		else: _add_hit(sr, "tool", tid)

# 7. クラフト＆製造キュー画面（5タブ・大型フォント・アイコンコスト表示！）
func _draw_craft_modal(vp: Vector2, portrait: bool, font: Font) -> void:
	var mw := minf(vp.x - 16.0, 860.0)
	var mh := minf(vp.y - 32.0, 640.0)
	var r := Rect2((vp.x - mw) * 0.5, (vp.y - mh) * 0.5, mw, mh)
	_panel(r, Color(0.04, 0.06, 0.12, 0.98), Color(0.38, 0.90, 1.0), 2.2)

	var spd_pct := int(round((1.0 + float(State.attached_drones) * 0.18) * 100.0))
	root_ctrl.draw_string(font, Vector2(r.position.x + 16, r.position.y + 28), "クラフト（速度 %d%%）" % spd_pct, HORIZONTAL_ALIGNMENT_LEFT, int(mw - 104), 17, Color(0.48, 0.96, 1.0))
	var cr := Rect2(r.end.x - 78, r.position.y + 8, 68, 30)
	_panel(cr, Color(0.28, 0.08, 0.10, 0.95), Color(1.0, 0.42, 0.42), 1.6)
	root_ctrl.draw_string(font, Vector2(cr.position.x, cr.position.y + 20), "閉じる", HORIZONTAL_ALIGNMENT_CENTER, cr.size.x, 13, Color.WHITE)
	_add_hit(cr, "close")

	# 5カテゴリタブ（機体 / 電力 / 物流 / 加工 / 軌道施設！）
	var ty := r.position.y + 46.0
	var tw := (mw - 24.0) / float(State.CRAFT_TABS.size())
	var tut_f := String(State.get_tutorial_info()["focus"]) if State.tut_enabled else ""
	for ti in range(State.CRAFT_TABS.size()):
		var tr := Rect2(r.position.x + 12.0 + float(ti) * tw, ty, tw - 4.0, 34.0)
		var sel := (ti == craft_tab)
		_panel(tr, Color(0.12, 0.28, 0.40, 0.96) if sel else Color(0.06, 0.09, 0.16, 0.90), Color(0.45, 0.96, 1.0) if sel else Color(0.28, 0.40, 0.56), 1.6)
		root_ctrl.draw_string(font, Vector2(tr.position.x, tr.position.y + 23), String(State.CRAFT_TABS[ti]["label"]), HORIZONTAL_ALIGNMENT_CENTER, tr.size.x, 12 if portrait else 14, Color.WHITE if sel else Color(0.72, 0.80, 0.90))
		if (tut_f == "craft_drone" and ti == 0 and not sel) or (tut_f == "craft_power" and ti == 1 and not sel):
			_pulse_frame(tr)
		_add_hit(tr, "craft_tab", ti)

	var qh := 96.0
	var list_y := ty + 42.0
	var list_h := mh - (list_y - r.position.y) - qh - 16.0
	var card_w := mw - 24.0

	if craft_tab == 0:
		var y := list_y
		var ch := 102.0
		var dr := Rect2(r.position.x + 12, y, card_w, ch)
		var can_d := State.can_enqueue_drone()
		var qd := State.count_queued("drone")
		_panel(dr, Color(0.07, 0.14, 0.22, 0.95), Color(0.42, 0.96, 1.0) if can_d else Color(0.28, 0.38, 0.50), 1.8)
		var dt := ArtReg.get_t("fab_drone")
		if dt: root_ctrl.draw_texture_rect(dt, Rect2(dr.position.x + 14, dr.position.y + 22, 56, 56), false)
		var tx := dr.position.x + 82.0
		var bw := 116.0 if not portrait else 96.0
		var info_w := int(card_w - 96.0 - bw)
		root_ctrl.draw_string(font, Vector2(tx, dr.position.y + 26), "ドローン増設（%d/%d%s）" % [State.attached_drones, State.MAX_DRONES, (" +%d" % qd) if qd > 0 else ""], HORIZONTAL_ALIGNMENT_LEFT, info_w, 15, Color.WHITE)
		root_ctrl.draw_string(font, Vector2(tx, dr.position.y + 49), "採掘ビーム+1  製造速度+18%%  %.1f秒" % State.DRONE_CRAFT_TIME, HORIZONTAL_ALIGNMENT_LEFT, info_w, 13, Color(0.74, 0.92, 1.0))
		_draw_cost_icons(Vector2(tx, dr.position.y + 66), State.DRONE_COST, font, 18.0, 14)
		var db := Rect2(dr.end.x - bw - 10, dr.position.y + 24, bw, 52)
		_panel(db, Color(0.08, 0.30, 0.22, 0.96) if can_d else Color(0.09, 0.11, 0.17, 0.90), Color(0.38, 1.0, 0.72) if can_d else Color(0.34, 0.42, 0.52), 1.8)
		root_ctrl.draw_string(font, Vector2(db.position.x, db.position.y + 32), "最大" if State.attached_drones >= State.MAX_DRONES else "製造", HORIZONTAL_ALIGNMENT_CENTER, bw, 15, Color.WHITE if can_d else Color(0.60, 0.68, 0.76))
		if tut_f == "craft_drone" and can_d: _pulse_frame(db)
		if can_d: _add_hit(db, "craft_drone")

		y += ch + 14.0
		var nxt := State.propulsion_tier + 1
		var pr := Rect2(r.position.x + 12, y, card_w, ch)
		var pt := ArtReg.get_t("orbital_booster")
		if State.PROPULSION_TIERS.has(nxt):
			var pinfo: Dictionary = State.PROPULSION_TIERS[nxt]
			var can_p := State.can_enqueue_propulsion()
			var req_ok := State.has_tech(String(pinfo["req"]))
			_panel(pr, Color(0.07, 0.14, 0.20, 0.95), Color(0.42, 1.0, 0.74) if can_p else Color(0.28, 0.38, 0.50), 1.8)
			if pt: root_ctrl.draw_texture_rect(pt, Rect2(pr.position.x + 14, pr.position.y + 22, 56, 56), false)
			root_ctrl.draw_string(font, Vector2(tx, pr.position.y + 26), "%s（Tier %d）" % [String(pinfo["name"]), nxt], HORIZONTAL_ALIGNMENT_LEFT, info_w, 15, Color.WHITE)
			if req_ok:
				root_ctrl.draw_string(font, Vector2(tx, pr.position.y + 49), "宇宙軌道・他惑星航行  %.1f秒" % float(pinfo["craft_time"]), HORIZONTAL_ALIGNMENT_LEFT, info_w, 13, Color(0.74, 0.92, 1.0))
				_draw_cost_icons(Vector2(tx, pr.position.y + 66), pinfo["cost"], font, 18.0, 14)
			else:
				root_ctrl.draw_string(font, Vector2(tx, pr.position.y + 56), "要研究: %s" % State.TECHS[String(pinfo["req"])]["name"], HORIZONTAL_ALIGNMENT_LEFT, info_w, 14, Color(1.0, 0.74, 0.40))
			var pb := Rect2(pr.end.x - bw - 10, pr.position.y + 24, bw, 52)
			_panel(pb, Color(0.08, 0.30, 0.22, 0.96) if can_p else Color(0.09, 0.11, 0.17, 0.90), Color(0.38, 1.0, 0.72) if can_p else Color(0.34, 0.42, 0.52), 1.8)
			root_ctrl.draw_string(font, Vector2(pb.position.x, pb.position.y + 32), "製造" if can_p else ("未解放" if not req_ok else "不足"), HORIZONTAL_ALIGNMENT_CENTER, bw, 15, Color.WHITE if can_p else Color(0.60, 0.68, 0.76))
			if can_p: _add_hit(pb, "craft_prop")
		else:
			_panel(pr, Color(0.06, 0.20, 0.16, 0.94), Color(0.40, 1.0, 0.72), 1.6)
			root_ctrl.draw_string(font, Vector2(pr.position.x + 20, pr.position.y + 56), "★ 推進機関 最大強化済み", HORIZONTAL_ALIGNMENT_LEFT, int(card_w - 40), 16, Color(0.66, 1.0, 0.82))
	else:
		var items: Array = State.CRAFT_TABS[craft_tab]["items"]
		var row_h := clampf((list_h - float(items.size() - 1) * 8.0) / float(maxi(1, items.size())), 66.0, 88.0)
		var y := list_y
		for bid_v in items:
			var bid := String(bid_v)
			var info: Dictionary = State.BLD[bid]
			var unl := State.is_unlocked(bid)
			var can_b := State.can_enqueue_building(bid)
			var stock := State.get_stock(bid)
			var qcnt := State.count_queued("building", bid)
			var br := Rect2(r.position.x + 12, y, card_w, row_h)
			_panel(br, Color(0.07, 0.11, 0.18, 0.95) if unl else Color(0.05, 0.06, 0.10, 0.88), Color(0.36, 0.78, 0.96) if can_b else Color(0.24, 0.30, 0.42), 1.5)

			var itex := ArtReg.get_t(String(info["tex"]))
			var isz := minf(48.0, row_h - 14.0)
			if itex:
				root_ctrl.draw_texture_rect(itex, Rect2(br.position.x + 12, br.position.y + (row_h - isz) * 0.5, isz, isz), false, Color.WHITE if unl else Color(0.4, 0.4, 0.45, 0.55))

			var btn_w := 86.0 if not portrait else 74.0
			var has_place := stock > 0
			var right_pad := (btn_w * 2.0 + 20.0) if has_place else (btn_w + 14.0)
			var tx := br.position.x + isz + 22.0
			var tw_i := int(card_w - (isz + 26.0) - right_pad)
			var hdr := "%s（x%d%s）" % [String(info["name"]), stock, (" +%d" % qcnt) if qcnt > 0 else ""]
			root_ctrl.draw_string(font, Vector2(tx, br.position.y + 23), hdr, HORIZONTAL_ALIGNMENT_LEFT, tw_i, 14, Color.WHITE if unl else Color(0.60, 0.66, 0.76))
			if unl:
				_draw_cost_icons(Vector2(tx, br.position.y + row_h - 26.0), info["cost"], font, 17.0, 13)
			else:
				root_ctrl.draw_string(font, Vector2(tx, br.position.y + row_h - 12.0), "要研究: %s" % State.TECHS[String(info["req"])]["name"], HORIZONTAL_ALIGNMENT_LEFT, tw_i, 13, Color(1.0, 0.72, 0.42))

			var by_btn := br.position.y + (row_h - 40.0) * 0.5
			if has_place:
				var pl_r := Rect2(br.end.x - btn_w * 2.0 - 16.0, by_btn, btn_w, 40.0)
				_panel(pl_r, Color(0.10, 0.24, 0.36, 0.96), Color(0.45, 0.96, 1.0), 1.6)
				root_ctrl.draw_string(font, Vector2(pl_r.position.x, pl_r.position.y + 26), "配置", HORIZONTAL_ALIGNMENT_CENTER, btn_w, 14, Color.WHITE)
				_add_hit(pl_r, "equip_place", bid)

			var mk_r := Rect2(br.end.x - btn_w - 8.0, by_btn, btn_w, 40.0)
			_panel(mk_r, Color(0.08, 0.30, 0.22, 0.96) if can_b else Color(0.09, 0.11, 0.17, 0.90), Color(0.38, 1.0, 0.72) if can_b else Color(0.30, 0.38, 0.48), 1.6)
			root_ctrl.draw_string(font, Vector2(mk_r.position.x, mk_r.position.y + 26), "製造" if unl else "未解放", HORIZONTAL_ALIGNMENT_CENTER, btn_w, 14, Color.WHITE if can_b else Color(0.55, 0.62, 0.70))
			if tut_f == "craft_power" and (bid == "solar" or bid == "tesla") and can_b and (stock + qcnt + int(State.tut_placed.get(bid, 0))) == 0:
				_pulse_frame(mk_r)
			if can_b: _add_hit(mk_r, "craft_bld", bid)
			y += row_h + 8.0

	# 製造キュー
	var qr := Rect2(r.position.x + 12, r.end.y - qh - 10, card_w, qh)
	_panel(qr, Color(0.05, 0.08, 0.15, 0.96), Color(0.34, 0.68, 0.92), 1.6)
	root_ctrl.draw_string(font, Vector2(qr.position.x + 12, qr.position.y + 21), "製造キュー（%d/12）  タップで取消" % State.craft_queue.size(), HORIZONTAL_ALIGNMENT_LEFT, int(card_w - 24), 13, Color(0.68, 0.90, 1.0))
	if State.craft_queue.is_empty():
		root_ctrl.draw_string(font, Vector2(qr.position.x + 12, qr.position.y + 58), "製造待機なし", HORIZONTAL_ALIGNMENT_LEFT, int(card_w - 24), 14, Color(0.56, 0.66, 0.78))
	else:
		var qx := qr.position.x + 10.0
		var qy := qr.position.y + 28.0
		var max_show := mini(State.craft_queue.size(), 5 if not portrait else 3)
		var q_slot_w := (card_w - 20.0 - float(max_show - 1) * 6.0) / float(max_show)
		for qi in range(max_show):
			var q: Dictionary = State.craft_queue[qi]
			var sr := Rect2(qx + float(qi) * (q_slot_w + 6.0), qy, q_slot_w, 60.0)
			var is_head := (qi == 0)
			_panel(sr, Color(0.08, 0.22, 0.30, 0.96) if is_head else Color(0.07, 0.10, 0.17, 0.92), Color(0.40, 1.0, 0.78) if is_head else Color(0.30, 0.42, 0.56), 1.5)
			root_ctrl.draw_string(font, Vector2(sr.position.x + 8, sr.position.y + 20), String(q["name"]), HORIZONTAL_ALIGNMENT_LEFT, int(q_slot_w - 14), 12, Color.WHITE)
			if is_head:
				var pct := clampf(1.0 - float(q["time_left"]) / maxf(0.1, float(q["total_time"])), 0.0, 1.0)
				root_ctrl.draw_string(font, Vector2(sr.position.x + 8, sr.position.y + 38), "%.1f秒" % maxf(0.0, float(q["time_left"])), HORIZONTAL_ALIGNMENT_LEFT, int(q_slot_w - 14), 12, Color(0.55, 1.0, 0.82))
				root_ctrl.draw_rect(Rect2(sr.position.x + 8, sr.position.y + 45, q_slot_w - 16, 8), Color(0.10, 0.14, 0.22))
				root_ctrl.draw_rect(Rect2(sr.position.x + 8, sr.position.y + 45, (q_slot_w - 16) * pct, 8), Color(0.36, 0.98, 0.74))
			else:
				root_ctrl.draw_string(font, Vector2(sr.position.x + 8, sr.position.y + 42), "待機 #%d" % (qi + 1), HORIZONTAL_ALIGNMENT_LEFT, int(q_slot_w - 14), 12, Color(0.68, 0.78, 0.90))
			_add_hit(sr, "cancel_q", qi)

# 8. 技術ツリー ([T]) ＋ タップで開く専用「技術詳細ポップアップ」（右上閉じる＋下部横長「研究する」！）
func _draw_tech_modal(vp: Vector2, portrait: bool, font: Font) -> void:
	var mw := minf(vp.x - 16.0, 920.0)
	var mh := minf(vp.y - 40.0, 560.0)
	var r := Rect2((vp.x - mw) * 0.5, (vp.y - mh) * 0.5, mw, mh)
	_panel(r, Color(0.03, 0.05, 0.10, 0.98), Color(0.36, 0.86, 1.0), 2.2)
	root_ctrl.draw_string(font, Vector2(r.position.x + 16, r.position.y + 28), "技術ツリー（カードをタップで詳細）", HORIZONTAL_ALIGNMENT_LEFT, int(mw - 104), 17, Color(0.48, 0.96, 1.0))

	var cr := Rect2(r.end.x - 78, r.position.y + 8, 68, 30)
	_panel(cr, Color(0.28, 0.08, 0.10, 0.95), Color(1.0, 0.42, 0.42), 1.6)
	root_ctrl.draw_string(font, Vector2(cr.position.x, cr.position.y + 20), "閉じる", HORIZONTAL_ALIGNMENT_CENTER, cr.size.x, 13, Color.WHITE)
	if not tech_detail_open:
		_add_hit(cr, "close")

	var cards: Dictionary = {}
	var gh := mh - 62.0
	if portrait:
		var cw := (mw - 36.0) * 0.5
		var ch := clampf((gh - 36.0) / 4.0, 82.0, 110.0)
		for i in range(State.TECH_ORDER.size()):
			var tid := State.TECH_ORDER[i]
			cards[tid] = Rect2(r.position.x + 14 + float(i % 2) * (cw + 8), r.position.y + 48 + float(i / 2) * (ch + 10), cw, ch)
	else:
		var cw := (mw - 86.0) / 6.0
		var ch := 112.0
		var rsp := gh / 3.0
		for tid in State.TECH_ORDER:
			var t: Dictionary = State.TECHS[tid]
			cards[tid] = Rect2(r.position.x + 18 + float(int(t["col"])) * (cw + 10), r.position.y + 52 + float(int(t["row"])) * rsp, cw, ch)

	for tid in State.TECH_ORDER:
		for rq in State.TECHS[tid]["req"]:
			if cards.has(rq):
				var col := Color(0.35, 0.96, 0.68, 0.88) if State.has_tech(tid) else Color(0.32, 0.46, 0.64, 0.58)
				root_ctrl.draw_line(Rect2(cards[rq]).get_center(), Rect2(cards[tid]).get_center(), col, 2.6)

	for i in range(State.TECH_ORDER.size()):
		var tid := State.TECH_ORDER[i]
		var t: Dictionary = State.TECHS[tid]
		var box_r: Rect2 = cards[tid]
		var done := State.has_tech(tid)
		var avail := State.can_research(tid)
		var bg := Color(0.06, 0.22, 0.16, 0.96) if done else (Color(0.10, 0.20, 0.34, 0.96) if avail else Color(0.06, 0.09, 0.15, 0.94))
		var bd := Color(0.36, 1.0, 0.72) if done else (Color(1.0, 0.84, 0.34) if avail else Color(0.28, 0.38, 0.52))
		_panel(box_r, bg, bd, 2.2 if avail else 1.5)

		# Pixel-art representative sprite right on the Tech Card!
		var icon_t := _get_visual_tex(String(t.get("icon", "seed_core")))
		var isz := 38.0 if portrait else 42.0
		if icon_t:
			root_ctrl.draw_texture_rect(icon_t, Rect2(box_r.position.x + (box_r.size.x - isz) * 0.5, box_r.position.y + 8, isz, isz), false, Color.WHITE if (done or avail) else Color(0.65, 0.70, 0.80, 0.85))
		root_ctrl.draw_string(font, Vector2(box_r.position.x + 6, box_r.position.y + isz + 28), String(t["name"]), HORIZONTAL_ALIGNMENT_CENTER, int(box_r.size.x - 12), 13, Color.WHITE)
		var st := "✓ 済" if done else ("★ 研究可" if avail else "未解放")
		root_ctrl.draw_string(font, Vector2(box_r.position.x + 6, box_r.end.y - 8), st, HORIZONTAL_ALIGNMENT_CENTER, int(box_r.size.x - 12), 12, Color(0.45, 1.0, 0.72) if done else (Color(1.0, 0.86, 0.36) if avail else Color(0.58, 0.68, 0.80)))
		if not tech_detail_open:
			if avail and State.tut_enabled and State.tut_step == 2 and tid == "power_grid":
				_pulse_frame(box_r)
			_add_hit(box_r, "tech_open_card", i)

	# 専用「技術詳細ポップアップウィンドウ」（右上「閉じる」＋ドット絵フロー図解＋下部横長「研究する」ボタン！）
	if tech_detail_open:
		root_ctrl.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.0, 0.0, 0.0, 0.58))
		_add_hit(Rect2(Vector2.ZERO, vp), "close_tech_detail")

		var sid := State.TECH_ORDER[clampi(tech_sel, 0, State.TECH_ORDER.size() - 1)]
		var td: Dictionary = State.TECHS[sid]
		var pw := minf(vp.x - 24.0, 580.0)
		var ph := minf(vp.y - 44.0, 440.0)
		var pr := Rect2((vp.x - pw) * 0.5, (vp.y - ph) * 0.5, pw, ph)
		_panel(pr, Color(0.04, 0.08, 0.15, 0.99), Color(0.42, 0.94, 1.0), 2.6)
		_add_hit(pr, "noop") # Block backdrop click inside popup

		# タイトル＆右上「閉じる」ボタン
		var icon_h := _get_visual_tex(String(td.get("icon", "seed_core")))
		if icon_h:
			root_ctrl.draw_texture_rect(icon_h, Rect2(pr.position.x + 16, pr.position.y + 12, 36, 36), false)
		root_ctrl.draw_string(font, Vector2(pr.position.x + 62, pr.position.y + 36), String(td["name"]), HORIZONTAL_ALIGNMENT_LEFT, int(pw - 160), 19, Color(0.48, 0.98, 1.0))

		var pcr := Rect2(pr.end.x - 84, pr.position.y + 12, 72, 32)
		_panel(pcr, Color(0.32, 0.09, 0.11, 0.96), Color(1.0, 0.44, 0.44), 1.8)
		root_ctrl.draw_string(font, Vector2(pcr.position.x, pcr.position.y + 22), "閉じる", HORIZONTAL_ALIGNMENT_CENTER, pcr.size.x, 14, Color.WHITE)
		_add_hit(pcr, "close_tech_detail")

		# 解放アイテム・施設ドット絵一覧
		var y := pr.position.y + 62.0
		var u_keys: Array = td.get("unlock_keys", [])
		var u_names: Array = td.get("unlocks", [])
		root_ctrl.draw_string(font, Vector2(pr.position.x + 18, y + 14), "解放される設備・装備", HORIZONTAL_ALIGNMENT_LEFT, int(pw - 36), 13, Color(0.74, 0.90, 1.0))
		y += 22.0
		var ur := Rect2(pr.position.x + 16, y, pw - 32, 84)
		_panel(ur, Color(0.06, 0.10, 0.18, 0.95), Color(0.28, 0.48, 0.68), 1.4)
		var un := maxi(1, u_keys.size())
		var uw := ur.size.x / float(un)
		for ui in range(u_keys.size()):
			var ucx := ur.position.x + (float(ui) + 0.5) * uw
			var ut := _get_visual_tex(String(u_keys[ui]))
			if ut:
				root_ctrl.draw_texture_rect(ut, Rect2(ucx - 22, ur.position.y + 8, 44, 44), false)
			var ulbl := String(u_names[ui]) if ui < u_names.size() else String(u_keys[ui])
			root_ctrl.draw_string(font, Vector2(ur.position.x + float(ui) * uw, ur.end.y - 8), ulbl, HORIZONTAL_ALIGNMENT_CENTER, uw, 12, Color.WHITE)

		# ドット絵フロー図解（文字を減らし視覚で伝える！）
		y = ur.end.y + 14.0
		root_ctrl.draw_string(font, Vector2(pr.position.x + 18, y + 14), "しくみ図解", HORIZONTAL_ALIGNMENT_LEFT, int(pw - 36), 13, Color(0.48, 0.98, 0.78))
		y += 20.0
		var fr := Rect2(pr.position.x + 16, y, pw - 32, 86)
		_draw_flow_diagram(fr, td.get("flow_keys", []), font)
		root_ctrl.draw_string(font, Vector2(pr.position.x + 18, fr.end.y + 20), String(td["summary"]), HORIZONTAL_ALIGNMENT_LEFT, int(pw - 36), 13, Color(0.92, 0.96, 1.0))

		# コストアイコン列
		var cost_y := pr.end.y - 104.0
		root_ctrl.draw_string(font, Vector2(pr.position.x + 18, cost_y + 14), "必要資源:", HORIZONTAL_ALIGNMENT_LEFT, 82, 14, Color(1.0, 0.86, 0.40))
		_draw_cost_icons(Vector2(pr.position.x + 98, cost_y - 2), td["cost"], font, 20.0, 15, true)

		# 下部の横長・大型「研究する」ボタン！
		var done_d := State.has_tech(sid)
		var can_r := State.can_research(sid)
		var rb := Rect2(pr.position.x + 16, pr.end.y - 68, pw - 32, 54)
		_panel(rb, Color(0.08, 0.34, 0.24, 0.98) if can_r else (Color(0.06, 0.20, 0.16, 0.94) if done_d else Color(0.10, 0.12, 0.18, 0.94)),
			Color(0.40, 1.0, 0.74) if can_r else (Color(0.36, 0.88, 0.66) if done_d else Color(0.36, 0.44, 0.56)), 2.2)
		var btn_txt := "✓ 研究済み" if done_d else ("研究する" if can_r else "条件・資源不足")
		root_ctrl.draw_string(font, Vector2(rb.position.x, rb.position.y + 34), btn_txt, HORIZONTAL_ALIGNMENT_CENTER, rb.size.x, 18, Color.WHITE if (can_r or done_d) else Color(0.62, 0.70, 0.80))
		if can_r and State.tut_enabled and State.tut_step == 2 and sid == "power_grid":
			_pulse_frame(rb)
		if can_r:
			_add_hit(rb, "tech_buy", sid)

# 9. 星系地図・艦隊ドクトリン・メガ構造物 ([M])
func _draw_command_modal(vp: Vector2, portrait: bool, font: Font) -> void:
	var mw := minf(vp.x - 16.0, 580.0)
	var mh := minf(vp.y - 32.0, 540.0)
	var r := Rect2((vp.x - mw) * 0.5, (vp.y - mh) * 0.5, mw, mh)
	_panel(r, Color(0.04, 0.06, 0.12, 0.98), Color(0.62, 0.54, 1.0), 2.2)
	root_ctrl.draw_string(font, Vector2(r.position.x + 16, r.position.y + 28), "星系指令・艦隊マップ", HORIZONTAL_ALIGNMENT_LEFT, int(mw - 104), 17, Color(0.76, 0.68, 1.0))
	var cr := Rect2(r.end.x - 78, r.position.y + 8, 68, 30)
	_panel(cr, Color(0.28, 0.08, 0.10, 0.95), Color(1.0, 0.42, 0.42), 1.6)
	root_ctrl.draw_string(font, Vector2(cr.position.x, cr.position.y + 20), "閉じる", HORIZONTAL_ALIGNMENT_CENTER, cr.size.x, 13, Color.WHITE)
	_add_hit(cr, "close")

	var y := r.position.y + 48.0
	var or_r := Rect2(r.position.x + 14, y, mw - 28, 42)
	_panel(or_r, Color(0.08, 0.24, 0.36, 0.96), Color(0.42, 0.92, 1.0), 1.8)
	root_ctrl.draw_string(font, Vector2(or_r.position.x, or_r.position.y + 27), "太陽系全体マップを開く" if not State.orbit_view else "機体視点へ戻る", HORIZONTAL_ALIGNMENT_CENTER, or_r.size.x, 15, Color.WHITE)
	_add_hit(or_r, "toggle_orbit")
	y += 52.0

	root_ctrl.draw_string(font, Vector2(r.position.x + 14, y + 14), "艦隊ドクトリン（%d / 10,000）" % State.swarm_fleet, HORIZONTAL_ALIGNMENT_LEFT, int(mw - 28), 14, Color(1.0, 0.86, 0.42))
	y += 22.0
	var dw := (mw - 28.0 - 18.0) / 4.0
	for i in range(4):
		var dr := Rect2(r.position.x + 14 + float(i) * (dw + 6.0), y, dw, 36)
		var on := (State.doctrine == i)
		_panel(dr, Color(0.14, 0.28, 0.42, 0.96) if on else Color(0.06, 0.09, 0.16, 0.90), Color(1.0, 0.84, 0.34) if on else Color(0.28, 0.38, 0.52), 1.6)
		root_ctrl.draw_string(font, Vector2(dr.position.x, dr.position.y + 24), State.DOCTRINE_NAMES[i], HORIZONTAL_ALIGNMENT_CENTER, dw, 14, Color.WHITE if on else Color(0.72, 0.80, 0.90))
		_add_hit(dr, "doc", i)
	y += 46.0

	root_ctrl.draw_string(font, Vector2(r.position.x + 14, y + 14), "軌道メガストラクチャー", HORIZONTAL_ALIGNMENT_LEFT, int(mw - 28), 14, Color(0.76, 0.68, 1.0))
	y += 22.0
	for mid in ["elevator", "dyson", "citadel", "warpgate"]:
		var built := bool(State.megastructures[mid])
		var mr := Rect2(r.position.x + 14, y, mw - 28, 48)
		_panel(mr, Color(0.08, 0.26, 0.18, 0.94) if built else Color(0.07, 0.10, 0.17, 0.92), Color(0.36, 1.0, 0.72) if built else Color(0.38, 0.48, 0.64), 1.4)
		root_ctrl.draw_string(font, Vector2(mr.position.x + 12, mr.position.y + 20), String(State.MEGAS[mid]["name"]) + (" ✓" if built else ""), HORIZONTAL_ALIGNMENT_LEFT, int(mr.size.x - 24), 14, Color.WHITE)
		_draw_cost_icons(Vector2(mr.position.x + 12, mr.position.y + 26), State.MEGAS[mid]["cost"], font, 16.0, 12)
		if not built: _add_hit(mr, "mega_buy", mid)
		y += 54.0

	var sy := r.end.y - 48.0
	var hw := (mw - 34.0) * 0.5
	var sr := Rect2(r.position.x + 14, sy, hw, 36)
	_panel(sr, Color(0.06, 0.10, 0.18, 0.92), Color(0.38, 0.56, 0.74), 1.4)
	root_ctrl.draw_string(font, Vector2(sr.position.x, sr.position.y + 24), "効果音: " + ("OFF" if Sfx.muted else "ON"), HORIZONTAL_ALIGNMENT_CENTER, hw, 14, Color.WHITE)
	_add_hit(sr, "mute")

	var rr := Rect2(sr.end.x + 6, sy, hw, 36)
	_panel(rr, Color(0.36, 0.08, 0.10, 0.95) if redrop_armed else Color(0.18, 0.07, 0.09, 0.92), Color(1.0, 0.42, 0.40), 1.4)
	root_ctrl.draw_string(font, Vector2(rr.position.x, rr.position.y + 24), "本当に帰還？" if redrop_armed else "北極へ緊急帰還", HORIZONTAL_ALIGNMENT_CENTER, hw, 14, Color(1.0, 0.86, 0.86))
	_add_hit(rr, "redrop")

# 10. 図解ガイド画面（ドット絵フロー図解メイン！）
func _draw_guide_modal(vp: Vector2, portrait: bool, font: Font) -> void:
	var mw := minf(vp.x - 16.0, 720.0)
	var mh := minf(vp.y - 40.0, 480.0)
	var r := Rect2((vp.x - mw) * 0.5, (vp.y - mh) * 0.5, mw, mh)
	_panel(r, Color(0.04, 0.07, 0.13, 0.98), Color(0.38, 0.92, 0.78), 2.2)
	root_ctrl.draw_string(font, Vector2(r.position.x + 16, r.position.y + 28), "図解プレイガイド", HORIZONTAL_ALIGNMENT_LEFT, int(mw - 210), 17, Color(0.46, 1.0, 0.82))
	var itr_b := Rect2(r.end.x - 196, r.position.y + 8, 110, 30)
	_panel(itr_b, Color(0.08, 0.24, 0.28, 0.95), Color(0.42, 0.96, 0.84), 1.5)
	root_ctrl.draw_string(font, Vector2(itr_b.position.x, itr_b.position.y + 20), "レシピ図へ", HORIZONTAL_ALIGNMENT_CENTER, itr_b.size.x, 13, Color.WHITE)
	_add_hit(itr_b, "open_item_tree")
	var cr := Rect2(r.end.x - 78, r.position.y + 8, 68, 30)
	_panel(cr, Color(0.28, 0.08, 0.10, 0.95), Color(1.0, 0.42, 0.42), 1.6)
	root_ctrl.draw_string(font, Vector2(cr.position.x, cr.position.y + 20), "閉じる", HORIZONTAL_ALIGNMENT_CENTER, cr.size.x, 13, Color.WHITE)
	_add_hit(cr, "close")

	var vis_guides: Array[Dictionary] = [
		{"tab": "採掘・ドローン", "keys": ["seed_core", "ore_fe", "fab_drone"], "lbls": ["採掘スティック", "鉱石獲得", "ドローン増設"], "note": "左下移動 / 右下採掘 / 2本指ズーム（常に機体中心）"},
		{"tab": "昼夜と電力網", "keys": ["solar", "battery", "tesla"], "lbls": ["昼発電", "夜間蓄電", "電線で配電"], "note": "夜間はソーラー停止！バッテリーと地熱で安定稼働"},
		{"tab": "鉱床と搬送", "keys": ["drill", "depot", "smelter"], "lbls": ["硬質鉱床専用", "自由結束搬送", "精錬"], "note": "施設タップで中身確認 / 削除モードは2回タップ"},
		{"tab": "ケプラー軌道", "keys": ["orbital_booster", "moon_luna", "orb_power"], "lbls": ["宇宙へ離脱", "月へ着陸OK", "軌道ロック"], "note": "入力停止で軌道ロック！近点で速く遠点で遅い実物理"},
		{"tab": "軌道採掘工場", "keys": ["orb_laser", "orb_collector", "orb_station", "quantum_core"], "lbls": ["レーザー採掘", "落下前に回収", "軌道クラフト", "量子コア"], "note": "同一軌道に配置！未回収資源は重力で星へ落下"},
		{"tab": "艦隊と勝利", "keys": ["gantry_printer", "mass_driver", "enemy_station"], "lbls": ["量産", "10,000機射出", "要塞撃破"], "note": "汚染要塞撃破 ＋ ワープゲート建造で星系解放！"},
	]

	var y := r.position.y + 48.0
	var bw := (mw - 28.0 - 12.0) / 3.0
	for i in range(vis_guides.size()):
		var gx := r.position.x + 14.0 + float(i % 3) * (bw + 6.0)
		var gy := y + float(i / 3) * 40.0
		var gr := Rect2(gx, gy, bw, 34.0)
		var sel := (i == guide_tab)
		_panel(gr, Color(0.12, 0.28, 0.38, 0.96) if sel else Color(0.06, 0.10, 0.17, 0.90), Color(0.42, 0.96, 1.0) if sel else Color(0.28, 0.38, 0.52), 1.5)
		root_ctrl.draw_string(font, Vector2(gr.position.x, gr.position.y + 23), String(vis_guides[i]["tab"]), HORIZONTAL_ALIGNMENT_CENTER, bw, 13, Color.WHITE if sel else Color(0.74, 0.84, 0.94))
		_add_hit(gr, "guide_tab", i)

	var g: Dictionary = vis_guides[clampi(guide_tab, 0, vis_guides.size() - 1)]
	var dr := Rect2(r.position.x + 14, y + 92, mw - 28, 150)
	_draw_flow_diagram(dr, g["keys"], font, g["lbls"])
	root_ctrl.draw_string(font, Vector2(r.position.x + 18, dr.end.y + 34), String(g["note"]), HORIZONTAL_ALIGNMENT_CENTER, int(mw - 36), 15, Color(0.92, 0.98, 1.0))

	var tb := Rect2(r.position.x + 14, r.end.y - 54, mw - 28, 40)
	_panel(tb, Color(0.08, 0.26, 0.20, 0.95) if State.tut_enabled else Color(0.16, 0.10, 0.12, 0.92), Color(0.42, 1.0, 0.74) if State.tut_enabled else Color(0.68, 0.42, 0.44), 1.5)
	root_ctrl.draw_string(font, Vector2(tb.position.x, tb.position.y + 26), "上部ガイド表示: ON" if State.tut_enabled else "上部ガイド表示: OFF", HORIZONTAL_ALIGNMENT_CENTER, tb.size.x, 14, Color.WHITE)
	_add_hit(tb, "tut_toggle")

# 10b. 完全網羅アイテム＆施設レシピツリー画面 ([I] または右上「レシピ図」ボタン)
func _draw_item_tree_modal(vp: Vector2, portrait: bool, font: Font) -> void:
	var mw := minf(vp.x - 12.0, 1120.0)
	var mh := minf(vp.y - 24.0, 670.0)
	var r := Rect2((vp.x - mw) * 0.5, (vp.y - mh) * 0.5, mw, mh)
	_panel(r, Color(0.03, 0.05, 0.10, 0.98), Color(0.40, 0.96, 0.84), 2.2)

	root_ctrl.draw_string(font, Vector2(r.position.x + 16, r.position.y + 28), "アイテム＆施設レシピツリー（カードをタップで経路ハイライト）", HORIZONTAL_ALIGNMENT_LEFT, int(mw - 210), 16 if not portrait else 13, Color(0.48, 1.0, 0.86))
	var gb := Rect2(r.end.x - 192, r.position.y + 8, 106, 30)
	_panel(gb, Color(0.08, 0.20, 0.30, 0.95), Color(0.42, 0.90, 1.0), 1.5)
	root_ctrl.draw_string(font, Vector2(gb.position.x, gb.position.y + 20), "操作ガイド", HORIZONTAL_ALIGNMENT_CENTER, gb.size.x, 13, Color.WHITE)
	_add_hit(gb, "open_guide")

	var cr := Rect2(r.end.x - 78, r.position.y + 8, 68, 30)
	_panel(cr, Color(0.28, 0.08, 0.10, 0.95), Color(1.0, 0.42, 0.42), 1.6)
	root_ctrl.draw_string(font, Vector2(cr.position.x, cr.position.y + 20), "閉じる", HORIZONTAL_ALIGNMENT_CENTER, cr.size.x, 13, Color.WHITE)
	_add_hit(cr, "close")

	# 列ヘッダ (Col 0..6)
	var col_titles := ["1.惑星原石", "2.採掘/溶鉱炉", "3.基礎素材", "4.組立機/電力", "5.回路/合金", "6.高度/軌道局", "7.最終/研究pt"]
	var gx := r.position.x + 10.0
	var gy := r.position.y + 44.0
	var gw := mw - 20.0
	var detail_h := 94.0
	var gh := mh - 48.0 - detail_h - 12.0
	var col_w := gw / 7.0
	var row_h := (gh - 24.0) / 7.0

	for ci in range(7):
		var cx := gx + float(ci) * col_w
		root_ctrl.draw_string(font, Vector2(cx, gy + 14), col_titles[ci], HORIZONTAL_ALIGNMENT_CENTER, col_w, 10 if portrait else 12, Color(0.68, 0.88, 1.0))

	var node_rects: Dictionary = {}
	var node_map: Dictionary = {}
	for nd in State.ITEM_TREE_NODES:
		var nid := String(nd["id"])
		node_map[nid] = nd
		var c_idx := int(nd["col"])
		var r_idx := int(nd["row"])
		var cw_box := col_w - (6.0 if portrait else 12.0)
		var ch_box := row_h - 5.0
		var bx := gx + float(c_idx) * col_w + (col_w - cw_box) * 0.5
		var by := gy + 22.0 + float(r_idx) * row_h
		node_rects[nid] = Rect2(bx, by, cw_box, ch_box)

	# 選択カードの上流チェーン（一番左の原石 → 精錬器 → 中間素材 → 組立機 → 選択アイテム！）を再帰的に全て収集
	var up_nodes: Dictionary = {}
	var q_up: Array[String] = [item_tree_sel]
	while not q_up.is_empty():
		var cur_id: String = String(q_up.pop_front())
		var pars: Array = State.ITEM_UPSTREAM_PARENTS.get(cur_id, [])
		for p_v in pars:
			var pid := String(p_v)
			if not up_nodes.has(pid):
				up_nodes[pid] = true
				q_up.append(pid)

	var down_nodes: Dictionary = {}
	for ed in State.ITEM_TREE_EDGES:
		if String(ed[0]) == item_tree_sel:
			down_nodes[String(ed[1])] = true

	# 1) 背景の非アクティブ接続エッジを先に描画
	for ed in State.ITEM_TREE_EDGES:
		var u := String(ed[0]); var v := String(ed[1])
		if not node_rects.has(u) or not node_rects.has(v): continue
		var is_up_edge := (u == item_tree_sel or up_nodes.has(u)) and (v == item_tree_sel or up_nodes.has(v))
		var is_out_edge := (u == item_tree_sel and down_nodes.has(v))
		if is_up_edge or is_out_edge: continue
		var ru: Rect2 = node_rects[u]; var rv: Rect2 = node_rects[v]
		var p1 := Vector2(ru.end.x, ru.get_center().y)
		var p2 := Vector2(rv.position.x, rv.get_center().y)
		var mid_x := (p1.x + p2.x) * 0.5
		root_ctrl.draw_polyline(PackedVector2Array([p1, Vector2(mid_x, p1.y), Vector2(mid_x, p2.y), p2]), Color(0.28, 0.40, 0.54, 0.28), 1.2)

	# 2) 全資源・全施設カード描画
	for nd in State.ITEM_TREE_NODES:
		var nid := String(nd["id"])
		var nr: Rect2 = node_rects[nid]
		var is_sel := (nid == item_tree_sel)
		var is_in := up_nodes.has(nid)
		var is_out := down_nodes.has(nid)
		var is_fac := String(nd["kind"]) == "fac"
		var bg := Color(0.16, 0.34, 0.46, 0.99) if is_sel else (Color(0.09, 0.24, 0.34, 0.98) if is_in else (Color(0.08, 0.18, 0.26, 0.95) if is_fac else Color(0.06, 0.10, 0.17, 0.94)))
		var bd := Color(1.0, 0.92, 0.36) if is_sel else (Color(0.32, 0.98, 1.0) if is_in else (Color(1.0, 0.78, 0.28) if is_out else (Color(0.34, 0.62, 0.82, 0.75) if is_fac else Color(0.24, 0.36, 0.50, 0.75))))
		_panel(nr, bg, bd, 2.5 if (is_sel or is_in or is_out) else 1.2)

		var it := _get_visual_tex(String(nd["icon"]))
		var isz := clampf(nr.size.y - 10.0, 16.0, 28.0)
		if it:
			root_ctrl.draw_texture_rect(it, Rect2(nr.position.x + 5, nr.position.y + (nr.size.y - isz) * 0.5, isz, isz), false)
		var tx := nr.position.x + isz + 9.0
		var tw_c := int(maxf(20.0, nr.size.x - isz - 12.0))
		root_ctrl.draw_string(font, Vector2(tx, nr.position.y + nr.size.y * 0.46), String(nd["name"]), HORIZONTAL_ALIGNMENT_LEFT, tw_c, 10 if portrait else 12, Color.WHITE)
		root_ctrl.draw_string(font, Vector2(tx, nr.position.y + nr.size.y * 0.84), String(nd["sub"]), HORIZONTAL_ALIGNMENT_LEFT, tw_c, 9 if portrait else 10, Color(0.68, 0.88, 1.0) if is_fac else Color(0.55, 0.98, 0.80))
		_add_hit(nr, "item_tree_pick", nid)

	# 2b) アクティブな上流チェーン（青線: 原石→溶鉱炉→鉄板/銅線→組立機→完成品）＆下流エッジ（黄線）を最前面にくっきり描画！
	for ed in State.ITEM_TREE_EDGES:
		var u := String(ed[0]); var v := String(ed[1])
		if not node_rects.has(u) or not node_rects.has(v): continue
		var is_up_edge := (u == item_tree_sel or up_nodes.has(u)) and (v == item_tree_sel or up_nodes.has(v))
		var is_out_edge := (u == item_tree_sel and down_nodes.has(v))
		if not is_up_edge and not is_out_edge: continue
		var ru: Rect2 = node_rects[u]; var rv: Rect2 = node_rects[v]
		var p1 := Vector2(ru.end.x, ru.get_center().y)
		var p2 := Vector2(rv.position.x, rv.get_center().y)
		var lcol := Color(0.32, 0.98, 1.0, 0.98) if is_up_edge else Color(1.0, 0.84, 0.28, 0.96)
		var mid_x := (p1.x + p2.x) * 0.5
		root_ctrl.draw_polyline(PackedVector2Array([p1, Vector2(mid_x, p1.y), Vector2(mid_x, p2.y), p2]), lcol, 3.0)
		root_ctrl.draw_polygon(PackedVector2Array([p2, p2 + Vector2(-8, -5), p2 + Vector2(-8, 5)]), PackedColorArray([lcol]))

	# 3) 下部：選択カードの詳細工程＆必要材料チェーン表示
	var dr := Rect2(r.position.x + 12, r.end.y - detail_h - 8, mw - 24, detail_h)
	_panel(dr, Color(0.05, 0.09, 0.16, 0.98), Color(0.42, 0.94, 1.0), 1.8)
	var sel_nd: Dictionary = node_map.get(item_tree_sel, State.ITEM_TREE_NODES[0])
	var sit := _get_visual_tex(String(sel_nd["icon"]))
	if sit:
		root_ctrl.draw_texture_rect(sit, Rect2(dr.position.x + 14, dr.position.y + 18, 56, 56), false)

	var in_names: Array[String] = []
	var out_names: Array[String] = []
	for ed in State.ITEM_TREE_EDGES:
		if String(ed[1]) == item_tree_sel and node_map.has(String(ed[0])):
			in_names.append(String(node_map[String(ed[0])]["name"]))
		if String(ed[0]) == item_tree_sel and node_map.has(String(ed[1])):
			out_names.append(String(node_map[String(ed[1])]["name"]))

	var dtx := dr.position.x + 84.0
	var dtw := int(dr.size.x - 96.0)
	var kind_tag := "【施設・装備】" if String(sel_nd["kind"]) == "fac" else ("【資源・加工品】（現在の所持: %d）" % State.get_r(item_tree_sel))
	root_ctrl.draw_string(font, Vector2(dtx, dr.position.y + 26), "%s  %s" % [String(sel_nd["name"]), kind_tag], HORIZONTAL_ALIGNMENT_LEFT, dtw, 16, Color(1.0, 0.90, 0.42))
	root_ctrl.draw_string(font, Vector2(dtx, dr.position.y + 52), "製造・入手工程:  " + String(sel_nd["recipe"]), HORIZONTAL_ALIGNMENT_LEFT, dtw, 14, Color(0.92, 0.98, 1.0))
	var chain_s := ("入力元(青線): " + ("・".join(in_names) if not in_names.is_empty() else "原石採掘")) + "    →    出力・用途先(黄線): " + ("・".join(out_names) if not out_names.is_empty() else "最終目標")
	root_ctrl.draw_string(font, Vector2(dtx, dr.position.y + 78), chain_s, HORIZONTAL_ALIGNMENT_LEFT, dtw, 13, Color(0.46, 0.98, 0.84))

# 11. カーゴデポ（倉庫）モーダル
func _draw_depot_modal(vp: Vector2, font: Font) -> void:
	if not grid: return
	var snap: Dictionary = grid.get_depot_snap(depot_uid)
	if snap.is_empty(): modal = Modal.NONE; return
	var mw := minf(vp.x - 16.0, 540.0); var mh := 430.0
	var r := Rect2((vp.x - mw) * 0.5, (vp.y - mh) * 0.5, mw, mh)
	_panel(r, Color(0.04, 0.06, 0.12, 0.98), Color(0.38, 0.88, 1.0), 2.2)
	root_ctrl.draw_string(font, Vector2(r.position.x + 16, r.position.y + 28), "倉庫（%d / %d）" % [int(snap["total"]), int(snap["cap"])], HORIZONTAL_ALIGNMENT_LEFT, int(mw - 104), 17, Color(0.48, 0.96, 1.0))
	var cr := Rect2(r.end.x - 78, r.position.y + 8, 68, 30)
	_panel(cr, Color(0.28, 0.08, 0.10, 0.95), Color(1.0, 0.42, 0.42), 1.6)
	root_ctrl.draw_string(font, Vector2(cr.position.x, cr.position.y + 20), "閉じる", HORIZONTAL_ALIGNMENT_CENTER, cr.size.x, 13, Color.WHITE)
	_add_hit(cr, "close")

	var dr := Rect2(r.position.x + 14, r.position.y + 46, (mw - 34) * 0.54, 36)
	_panel(dr, Color(0.08, 0.22, 0.32, 0.95), Color(0.42, 0.94, 1.0), 1.5)
	root_ctrl.draw_string(font, Vector2(dr.position.x, dr.position.y + 24), "鉱石を全て預ける", HORIZONTAL_ALIGNMENT_CENTER, dr.size.x, 13, Color.WHITE)
	_add_hit(dr, "depot_all")

	var cvr := Rect2(dr.end.x + 6, r.position.y + 46, (mw - 34) * 0.46, 36)
	_panel(cvr, Color(0.22, 0.16, 0.06, 0.95), Color(1.0, 0.80, 0.30), 1.5)
	root_ctrl.draw_string(font, Vector2(cvr.position.x, cvr.position.y + 24), "搬送接続 →", HORIZONTAL_ALIGNMENT_CENTER, cvr.size.x, 13, Color.WHITE)
	_add_hit(cvr, "depot_conv")

	var y := r.position.y + 94.0
	var out_links: Array = snap.get("out_links", [])
	if not out_links.is_empty():
		var show_n := mini(out_links.size(), 4)
		var fw := (mw - 28.0) / float(show_n)
		for i in range(show_n):
			var lk: Dictionary = out_links[i]
			var fr := Rect2(r.position.x + 14 + float(i) * fw, y, fw - 6, 44)
			var raw_f := String(lk.get("filter", "auto"))
			var fv := "停止" if raw_f == "none" else ("自動" if raw_f == "auto" else State.res_name(raw_f))
			_panel(fr, Color(0.10, 0.22, 0.32, 0.95) if raw_f != "none" else Color(0.06, 0.09, 0.15, 0.9), Color(1.0, 0.80, 0.30) if raw_f != "none" else Color(0.28, 0.38, 0.50), 1.4)
			root_ctrl.draw_string(font, Vector2(fr.position.x, fr.position.y + 17), "→ " + String(lk["to_name"]), HORIZONTAL_ALIGNMENT_CENTER, fr.size.x, 11, Color(0.76, 0.88, 1.0))
			root_ctrl.draw_string(font, Vector2(fr.position.x, fr.position.y + 36), fv, HORIZONTAL_ALIGNMENT_CENTER, fr.size.x, 13, Color.WHITE)
			_add_hit(fr, "depot_link_flt", int(lk["idx"]))
		y += 54.0

	var inv: Dictionary = snap["inv"]
	for it in ["fe", "cu", "si", "ti", "plate_fe", "wire_cu", "wafer_si", "circuit"]:
		var cnt := int(inv.get(it, 0))
		var ic := ArtReg.get_icon(String(it))
		if ic: root_ctrl.draw_texture_rect(ic, Rect2(r.position.x + 16, y + 3, 20, 20), false)
		root_ctrl.draw_string(font, Vector2(r.position.x + 42, y + 19), "%s  ×%d" % [State.res_name(String(it)), cnt], HORIZONTAL_ALIGNMENT_LEFT, 220, 14, Color.WHITE if cnt > 0 else Color(0.45, 0.52, 0.62))
		var tr := Rect2(r.end.x - 108, y, 92, 26)
		_panel(tr, Color(0.08, 0.24, 0.20, 0.92) if cnt > 0 else Color(0.06, 0.08, 0.12, 0.7), Color(0.36, 0.92, 0.72) if cnt > 0 else Color(0.24, 0.30, 0.38), 1.2)
		root_ctrl.draw_string(font, Vector2(tr.position.x, tr.position.y + 18), "5個取出", HORIZONTAL_ALIGNMENT_CENTER, tr.size.x, 12, Color.WHITE if cnt > 0 else Color(0.45, 0.50, 0.58))
		if cnt > 0: _add_hit(tr, "depot_take", it)
		y += 30.0

# 11b. 地上施設詳細インスペクタ（アイコン＋進捗バー重視！）
func _draw_building_modal(vp: Vector2, font: Font) -> void:
	if not grid: return
	var snap: Dictionary = grid.get_building_snap(inspect_uid)
	if snap.is_empty(): modal = Modal.NONE; return
	var bid := String(snap["id"])
	var mw := minf(vp.x - 16.0, 500.0)
	var mh := 366.0
	var r := Rect2((vp.x - mw) * 0.5, (vp.y - mh) * 0.5, mw, mh)
	_panel(r, Color(0.04, 0.06, 0.12, 0.98), Color(0.38, 0.90, 1.0), 2.2)

	var itex := ArtReg.get_t(String(snap["tex"]))
	if itex: root_ctrl.draw_texture_rect(itex, Rect2(r.position.x + 14, r.position.y + 10, 38, 38), false)
	root_ctrl.draw_string(font, Vector2(r.position.x + 60, r.position.y + 34), String(snap["name"]), HORIZONTAL_ALIGNMENT_LEFT, int(mw - 150), 18, Color(0.48, 0.96, 1.0))
	var cr := Rect2(r.end.x - 78, r.position.y + 10, 68, 30)
	_panel(cr, Color(0.28, 0.08, 0.10, 0.95), Color(1.0, 0.42, 0.42), 1.6)
	root_ctrl.draw_string(font, Vector2(cr.position.x, cr.position.y + 20), "閉じる", HORIZONTAL_ALIGNMENT_CENTER, cr.size.x, 13, Color.WHITE)
	_add_hit(cr, "close")

	var y := r.position.y + 56.0
	var st_r := Rect2(r.position.x + 14, y, mw - 28, 68)
	_panel(st_r, Color(0.06, 0.10, 0.17, 0.95), Color(0.28, 0.44, 0.62), 1.4)
	var pwr := float(snap["pwr_ratio"])
	var p_col := Color(0.45, 0.98, 0.72)
	var hp_s := "  [耐久HP %d/%d]" % [int(snap.get("hp", 150.0)), int(snap.get("max_hp", 150.0))]
	var p_txt := ""
	if bool(snap["is_power"]):
		if bid == "battery":
			p_txt = "蓄電 %d / %d kJ%s" % [int(snap["battery_kj"]), int(snap["battery_cap"]), hp_s]
		elif float(snap["gen"]) > 0.1:
			p_txt = "発電 %.0fW（%s）%s" % [float(snap["gen"]), "通電" if bool(snap["wired"]) else "未配線", hp_s]
		else:
			p_txt = "テスラ配電: %s%s" % ["稼働中" if pwr > 0.1 else "未通電", hp_s]
			if pwr <= 0.1: p_col = Color(1.0, 0.68, 0.36)
	else:
		if float(snap["use"]) <= 0.01 or pwr > 0.1:
			p_txt = "稼働中（%d%%）%s%s" % [int(round(pwr * 100.0)), hp_s, " ※満杯" if bool(snap["blocked"]) else ""]
		else:
			p_txt = "電力不足（テスラ範囲外）" + hp_s
			p_col = Color(1.0, 0.46, 0.40)
	root_ctrl.draw_string(font, Vector2(st_r.position.x + 12, st_r.position.y + 24), p_txt, HORIZONTAL_ALIGNMENT_LEFT, int(st_r.size.x - 24), 14, p_col)

	if bid == "assembler":
		var rec_k := String(snap["recipe"])
		var rdata: Dictionary = State.ASSEMBLER_RECIPES.get(rec_k, State.ASSEMBLER_RECIPES["circuit"])
		_draw_recipe_visual(Rect2(st_r.position.x + 10, st_r.position.y + 30, st_r.size.x - 20, 32), rdata["in"], String(rdata["out"]), int(rdata["qty"]), font)
	elif bool(snap.get("has_prog", false)):
		var pg := clampf(float(snap.get("prog", 0.0)), 0.0, 1.0)
		var pgr := Rect2(st_r.position.x + 12, st_r.position.y + 40, st_r.size.x - 24, 16)
		root_ctrl.draw_rect(pgr, Color(0.08, 0.14, 0.22))
		root_ctrl.draw_rect(Rect2(pgr.position, Vector2(pgr.size.x * pg, pgr.size.y)), Color(1.0, 0.72, 0.22) if bid == "smelter" else Color(0.36, 0.96, 0.74))
		root_ctrl.draw_rect(pgr, Color(0.38, 0.56, 0.72), false, 1.2)

	y += 76.0
	var buf_r := Rect2(r.position.x + 14, y, mw - 28, 98)
	_panel(buf_r, Color(0.05, 0.08, 0.14, 0.95), Color(0.28, 0.44, 0.62), 1.4)
	var in_d: Dictionary = snap["in_buf"]
	var out_d: Dictionary = snap["out_buf"]
	root_ctrl.draw_string(font, Vector2(buf_r.position.x + 12, buf_r.position.y + 26), "入力:", HORIZONTAL_ALIGNMENT_LEFT, 54, 14, Color(0.76, 0.88, 1.0))
	if in_d.is_empty():
		root_ctrl.draw_string(font, Vector2(buf_r.position.x + 68, buf_r.position.y + 26), "空", HORIZONTAL_ALIGNMENT_LEFT, 60, 14, Color(0.50, 0.58, 0.68))
	else:
		_draw_cost_icons(Vector2(buf_r.position.x + 68, buf_r.position.y + 10), in_d, font, 20.0, 14)

	root_ctrl.draw_string(font, Vector2(buf_r.position.x + 12, buf_r.position.y + 66), "出力:", HORIZONTAL_ALIGNMENT_LEFT, 54, 14, Color(0.46, 0.98, 0.78))
	if out_d.is_empty():
		root_ctrl.draw_string(font, Vector2(buf_r.position.x + 68, buf_r.position.y + 66), "空", HORIZONTAL_ALIGNMENT_LEFT, 60, 14, Color(0.50, 0.58, 0.68))
	else:
		_draw_cost_icons(Vector2(buf_r.position.x + 68, buf_r.position.y + 50), out_d, font, 20.0, 14)

	y += 108.0
	var acts: Array[Dictionary] = []
	if not out_d.is_empty(): acts.append({"lbl": "回収", "a": "bld_collect", "c": Color(0.38, 0.98, 0.74)})
	if bid in ["smelter", "assembler", "gantry_printer"]: acts.append({"lbl": "材料投入", "a": "bld_feed", "c": Color(0.42, 0.90, 1.0)})
	if bid == "assembler": acts.append({"lbl": "レシピ: %s" % State.res_name(String(snap["recipe"])), "a": "bld_recipe", "c": Color(1.0, 0.84, 0.36)})
	if bool(snap.get("is_logi", false)): acts.append({"lbl": "搬送接続", "a": "bld_conv", "c": Color(1.0, 0.80, 0.30)})
	if bool(snap["is_power"]): acts.append({"lbl": "配線", "a": "bld_wire", "c": Color(0.42, 0.96, 1.0)})

	if not acts.is_empty():
		var aw := (mw - 28.0 - float(acts.size() - 1) * 6.0) / float(acts.size())
		for ai in range(acts.size()):
			var ar := Rect2(r.position.x + 14 + float(ai) * (aw + 6.0), y, aw, 42)
			_panel(ar, Color(0.08, 0.22, 0.30, 0.95), Color(acts[ai]["c"]), 1.6)
			root_ctrl.draw_string(font, Vector2(ar.position.x, ar.position.y + 27), String(acts[ai]["lbl"]), HORIZONTAL_ALIGNMENT_CENTER, aw, 14, Color.WHITE)
			_add_hit(ar, String(acts[ai]["a"]))

	var del_r := Rect2(r.position.x + 14, r.end.y - 48, mw - 28, 36)
	_panel(del_r, Color(0.26, 0.08, 0.10, 0.94), Color(1.0, 0.44, 0.42), 1.5)
	root_ctrl.draw_string(font, Vector2(del_r.position.x, del_r.position.y + 24), "削除・回収", HORIZONTAL_ALIGNMENT_CENTER, del_r.size.x, 14, Color(1.0, 0.86, 0.86))
	_add_hit(del_r, "bld_salvage")

# 11c. 軌道施設インスペクタ（軌道発電・軌道採掘レーザー・軌道回収・軌道クラフト局！）
func _draw_orbital_modal(vp: Vector2, font: Font) -> void:
	if not orbital: return
	var snap: Dictionary = orbital.get_module_snap(orbital_uid)
	if snap.is_empty(): modal = Modal.NONE; return
	var bid := String(snap["id"])
	var mw := minf(vp.x - 16.0, 500.0)
	var mh := 374.0
	var r := Rect2((vp.x - mw) * 0.5, (vp.y - mh) * 0.5, mw, mh)
	_panel(r, Color(0.04, 0.07, 0.14, 0.98), Color(0.42, 0.96, 1.0), 2.2)

	var itex := ArtReg.get_t(String(snap["tex"]))
	if itex: root_ctrl.draw_texture_rect(itex, Rect2(r.position.x + 14, r.position.y + 10, 42, 42), false)
	root_ctrl.draw_string(font, Vector2(r.position.x + 64, r.position.y + 36), String(snap["name"]), HORIZONTAL_ALIGNMENT_LEFT, int(mw - 150), 17, Color(0.48, 0.98, 1.0))
	var cr := Rect2(r.end.x - 78, r.position.y + 10, 68, 30)
	_panel(cr, Color(0.28, 0.08, 0.10, 0.95), Color(1.0, 0.42, 0.42), 1.6)
	root_ctrl.draw_string(font, Vector2(cr.position.x, cr.position.y + 20), "閉じる", HORIZONTAL_ALIGNMENT_CENTER, cr.size.x, 13, Color.WHITE)
	_add_hit(cr, "close")

	var y := r.position.y + 62.0
	var pwr := int(round(float(snap["pwr_ratio"]) * 100.0))
	var status_s := "軌道出力 %d%%" % pwr
	if bid == "orb_collector": status_s += "  |  累計回収: %d" % int(snap["collected"])
	elif bid == "orb_laser" and String(snap["laser_ore"]) != "": status_s += "  |  採掘中: %s" % State.res_name(String(snap["laser_ore"]))
	root_ctrl.draw_string(font, Vector2(r.position.x + 16, y + 18), status_s, HORIZONTAL_ALIGNMENT_LEFT, int(mw - 32), 15, Color(0.46, 1.0, 0.80))
	y += 30.0

	if bid == "orb_station":
		var rinfo: Dictionary = snap["recipe_info"]
		if not rinfo.is_empty():
			var rec_r := Rect2(r.position.x + 14, y, mw - 28, 52)
			_draw_recipe_visual(rec_r, rinfo["in"], String(rinfo["out"]), int(rinfo["qty"]), font)
			y += 60.0
		var pg := clampf(float(snap["prog"]), 0.0, 1.0)
		var pgr := Rect2(r.position.x + 14, y, mw - 28, 16)
		root_ctrl.draw_rect(pgr, Color(0.08, 0.14, 0.22))
		root_ctrl.draw_rect(Rect2(pgr.position, Vector2(pgr.size.x * pg, pgr.size.y)), Color(0.42, 0.98, 0.82))
		root_ctrl.draw_rect(pgr, Color(0.38, 0.56, 0.72), false, 1.2)
		y += 28.0
		var in_d: Dictionary = snap["in_buf"]
		root_ctrl.draw_string(font, Vector2(r.position.x + 16, y + 18), "入力在庫:", HORIZONTAL_ALIGNMENT_LEFT, 86, 14, Color(0.76, 0.90, 1.0))
		if in_d.is_empty():
			root_ctrl.draw_string(font, Vector2(r.position.x + 104, y + 18), "回収モジュールから自動受信待ち", HORIZONTAL_ALIGNMENT_LEFT, int(mw - 120), 13, Color(0.58, 0.68, 0.80))
		else:
			_draw_cost_icons(Vector2(r.position.x + 104, y + 2), in_d, font, 19.0, 14)
		y += 40.0
		var hw := (mw - 34.0) * 0.5
		var rr := Rect2(r.position.x + 14, y, hw, 42)
		_panel(rr, Color(0.10, 0.22, 0.34, 0.96), Color(1.0, 0.84, 0.36), 1.6)
		root_ctrl.draw_string(font, Vector2(rr.position.x, rr.position.y + 27), "レシピ切替", HORIZONTAL_ALIGNMENT_CENTER, hw, 14, Color.WHITE)
		_add_hit(rr, "orb_recipe")
		var fr := Rect2(rr.end.x + 6, y, hw, 42)
		_panel(fr, Color(0.08, 0.28, 0.24, 0.96), Color(0.42, 0.96, 1.0), 1.6)
		root_ctrl.draw_string(font, Vector2(fr.position.x, fr.position.y + 27), "材料を手動投入", HORIZONTAL_ALIGNMENT_CENTER, hw, 14, Color.WHITE)
		_add_hit(fr, "orb_feed")
	else:
		var flow_k := ["orb_power", "tesla"] if bid == "orb_power" else (["orb_laser", "ore_fe", "orb_collector"] if bid == "orb_laser" else ["orb_collector", "orb_station", "quantum_core"])
		_draw_flow_diagram(Rect2(r.position.x + 14, y, mw - 28, 120), flow_k, font)

	var del_r := Rect2(r.position.x + 14, r.end.y - 52, mw - 28, 38)
	_panel(del_r, Color(0.26, 0.08, 0.10, 0.94), Color(1.0, 0.44, 0.42), 1.5)
	root_ctrl.draw_string(font, Vector2(del_r.position.x, del_r.position.y + 25), "軌道施設を回収", HORIZONTAL_ALIGNMENT_CENTER, del_r.size.x, 14, Color(1.0, 0.86, 0.86))
	_add_hit(del_r, "orb_salvage")

# 12. タッチ仮想コントロール（移動スティック / 方向指定採掘スティック）
func _draw_touch_controls(font: Font) -> void:
	root_ctrl.draw_circle(joy_center, joy_r, Color(0.04, 0.08, 0.14, 0.54))
	root_ctrl.draw_arc(joy_center, joy_r, 0.0, TAU, 32, Color(0.36, 0.80, 1.0, 0.78), 2.2)
	var pk := joy_center + joy_vec * (joy_r * 0.62)
	root_ctrl.draw_circle(pk, 19.0, Color(0.10, 0.24, 0.38, 0.90))
	root_ctrl.draw_arc(pk, 19.0, 0.0, TAU, 24, Color(0.45, 0.96, 1.0), 2.2)

	if State.selected_tool == "mine":
		root_ctrl.draw_circle(act_center, mine_r, Color(0.04, 0.13, 0.11, 0.58))
		root_ctrl.draw_arc(act_center, mine_r, 0.0, TAU, 32, Color(0.35, 0.96, 0.68, 0.84), 2.4)
		for a_deg in [0.0, 90.0, 180.0, 270.0]:
			var dv := Vector2.from_angle(deg_to_rad(a_deg))
			root_ctrl.draw_line(act_center + dv * (mine_r - 9.0), act_center + dv * (mine_r - 2.0), Color(0.38, 0.96, 0.76, 0.45), 1.8)
		var mpk := act_center + mine_vec * (mine_r * 0.64)
		if mine_vec.length() > 0.12:
			var md := mine_vec.normalized()
			root_ctrl.draw_line(act_center, act_center + md * (mine_r + 12.0), Color(0.42, 1.0, 0.86, 0.88), 2.8)
		root_ctrl.draw_circle(mpk, 20.0, Color(0.08, 0.28, 0.22, 0.94))
		root_ctrl.draw_arc(mpk, 20.0, 0.0, TAU, 24, Color(0.42, 1.0, 0.80), 2.2)
		root_ctrl.draw_string(font, mpk + Vector2(-22, 5), "採掘", HORIZONTAL_ALIGNMENT_CENTER, 44, 12, Color.WHITE)
	else:
		root_ctrl.draw_circle(act_center, 38.0, Color(0.06, 0.16, 0.14, 0.86))
		root_ctrl.draw_arc(act_center, 38.0, 0.0, TAU, 24, Color(0.35, 0.96, 0.68), 2.4)
		var act_lbl := "接続" if State.selected_tool == "wire" else ("搬送" if State.selected_tool == "conveyor" else ("削除" if State.selected_tool == "salvage" else "設置"))
		root_ctrl.draw_string(font, act_center + Vector2(-30, 6), act_lbl, HORIZONTAL_ALIGNMENT_CENTER, 60, 14, Color.WHITE)

	root_ctrl.draw_circle(brk_center, 26.0, Color(0.18, 0.07, 0.09, 0.82))
	root_ctrl.draw_arc(brk_center, 26.0, 0.0, TAU, 24, Color(1.0, 0.44, 0.42), 2.2)
	root_ctrl.draw_string(font, brk_center + Vector2(-24, 5), "停止", HORIZONTAL_ALIGNMENT_CENTER, 48, 12, Color.WHITE)
