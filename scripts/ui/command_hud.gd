extends CanvasLayer

# STAR REPLICA: AUTOMA - ミニマル日本語HUD・クラフト製造キュー・研究ツリー・指令パネル・インタラクティブチュートリアル
# すべての主要行動を2〜3タップ以内に収め、メイン画面のボタン数を最小限に整理。

enum Modal { NONE, CRAFT, TECH, COMMAND, DEPOT, GUIDE, BUILDING }

var planet: SphericalPlanet = null
var grid: Node2D = null
var player: Node2D = null
var swarm: Node2D = null
var game_root: Node2D = null

var modal: int = Modal.NONE
var craft_tab: int = 0
var tech_sel: int = 1
var guide_tab: int = 0
var depot_uid: int = -1
var inspect_uid: int = -1
var redrop_armed: bool = false
var anim_t: float = 0.0

# モバイル／タッチ端末専用仮想コントロール（左：移動スティック / 右：方向指定採掘スティック / 2本指ピンチズーム）
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

# 2本指ピンチズーム & ワールド単タップ判定（ピンチ中に誤タップ・誤採掘しない！）
var _pinch_pts: Dictionary = {} # touch_index -> raw screen pos
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

func _hud_vp() -> Vector2:
	var raw := get_viewport().get_visible_rect().size
	if raw.y > raw.x * 1.1:
		touch_ui_active = true
		var s := clampf(raw.x / 520.0, 1.35, 2.6)
		scale = Vector2(s, s)
		return raw / s
	scale = Vector2.ONE
	return raw

func _process(delta: float) -> void:
	anim_t += delta
	var vp := _hud_vp()
	joy_r = 52.0
	mine_r = 48.0
	joy_center = Vector2(joy_r + 22.0, vp.y - joy_r - 116.0)
	act_center = Vector2(vp.x - mine_r - 20.0, vp.y - mine_r - 118.0)
	brk_center = Vector2(act_center.x - mine_r - 34.0, vp.y - 134.0)

	# キーボード WASD / 矢印キー ＋ タッチジョイスティック（常に画面方向へ移動！）
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
				if grid:
					grid.hover_world = wp
			else:
				player.aim_world = Vector2.ZERO
				if grid:
					grid.hover_world = player.position
			if grid:
				grid.show_ghost = (modal == Modal.NONE and State.BLD.has(State.selected_tool) and State.get_stock(State.selected_tool) > 0)
		# タップ採掘は廃止！右下採掘スティック（またはPCはSPACEキー）でのみ照射
		player.firing_mine = (modal == Modal.NONE and State.selected_tool == "mine" and (act_pid != -1 or Input.is_key_pressed(KEY_SPACE)))

	root_ctrl.queue_redraw()

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
		# モバイル実機でタッチ直後に発生するエミュレート／ゴーストマウスイベントを完全に無視！
		if event.device == InputEvent.DEVICE_ID_EMULATION or (Time.get_ticks_msec() - _last_touch_ms) < 450:
			return
		var p: Vector2 = event.position / maxf(0.1, scale.x)
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed: _on_down(-10, p, event.position)
			else: _on_up(-10, event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if modal != Modal.NONE:
				modal = Modal.NONE; Sfx.play("click")
			elif State.selected_tool != "mine":
				State.selected_tool = "mine"
				if grid:
					grid.wire_pick_uid = -1
					grid.salvage_armed_uid = -1
				Sfx.play("click")
	elif event is InputEventMouseMotion:
		if event.device == InputEvent.DEVICE_ID_EMULATION or (Time.get_ticks_msec() - _last_touch_ms) < 450:
			return
		var p: Vector2 = event.position / maxf(0.1, scale.x)
		if joy_pid == -10:
			_upd_joy(p)
		elif act_pid == -10:
			_upd_mine_stick(p)

func _on_key(code: int) -> void:
	match code:
		KEY_C:
			modal = Modal.NONE if modal == Modal.CRAFT else Modal.CRAFT
			Sfx.play("select")
		KEY_T:
			modal = Modal.NONE if modal == Modal.TECH else Modal.TECH
			Sfx.play("select")
		KEY_M:
			if modal == Modal.COMMAND:
				modal = Modal.NONE
			else:
				State.orbit_view = not State.orbit_view
				if State.orbit_view: State.tut_opened_orbit = true
			Sfx.play("click")
		KEY_H:
			modal = Modal.NONE if modal == Modal.GUIDE else Modal.GUIDE
			Sfx.play("select")
		KEY_ESCAPE:
			if modal != Modal.NONE: modal = Modal.NONE
			else:
				State.selected_tool = "mine"
				if grid: grid.wire_pick_uid = -1
			Sfx.play("click")
		KEY_R:
			State.build_dir = -State.build_dir
			Sfx.play("click")
			State.add_log("ベルト向き切替: %s" % ("右方向" if State.build_dir > 0 else "左方向"), "info")
		KEY_E:
			if modal == Modal.NONE and grid and player:
				grid.interact_near_player(player.position)

func _on_down(pid: int, pos: Vector2, raw_pos: Vector2) -> void:
	# 1. モバイル仮想コントロール（左：移動スティック / 右：方向指定採掘スティック）
	if touch_ui_active and modal == Modal.NONE:
		if pos.distance_to(joy_center) <= joy_r + 30.0:
			joy_pid = pid; _upd_joy(pos); get_viewport().set_input_as_handled(); return
		if pos.distance_to(act_center) <= mine_r + 24.0:
			act_pid = pid
			_upd_mine_stick(pos)
			if grid and player:
				if State.selected_tool == "mine":
					player.firing_mine = true
				else:
					grid.handle_world_click(player.position)
			get_viewport().set_input_as_handled(); return
		if pos.distance_to(brk_center) <= 30.0:
			brk_pid = pid; get_viewport().set_input_as_handled(); return

	# 2. HUDボタン判定（手前のモーダル優先）
	for i in range(_hits.size() - 1, -1, -1):
		if Rect2(_hits[i]["r"]).has_point(pos):
			_exec(_hits[i])
			get_viewport().set_input_as_handled()
			return

	# 3. ワールド入力：タッチはピンチズーム対応（単タップ離し時に施設詳細／設置／配線／ダブルタップ削除）
	if modal == Modal.NONE and grid:
		if pid == -10:
			var cam := get_viewport().get_camera_2d()
			if cam:
				var wp := cam.get_canvas_transform().affine_inverse() * raw_pos
				if grid.handle_world_click(wp):
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
	if _pinch_pts.has(pid):
		_pinch_pts.erase(pid)
	if pid == _tap_pid:
		var was_tap := (not _pinch_active) and (not _tap_moved) and modal == Modal.NONE and grid != null
		_tap_pid = -1
		if was_tap:
			var cam := get_viewport().get_camera_2d()
			if cam:
				var wp := cam.get_canvas_transform().affine_inverse() * (raw_pos if raw_pos != Vector2.ZERO else _tap_start_raw)
				grid.handle_world_click(wp)
	if _pinch_pts.size() < 2:
		_pinch_dist = 0.0
	if _pinch_pts.is_empty():
		_pinch_active = false

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
		Sfx.play("error")
		State.add_log("先に【研究】で「電力とテスラ」を解放してください。", "warn")
		return
	if tid == "conveyor" and not State.is_unlocked("conveyor"):
		Sfx.play("error")
		State.add_log("先に【研究】で「洞窟物流ライン」を解放してください。", "warn")
		return
	if State.BLD.has(tid) and State.get_stock(tid) <= 0:
		Sfx.play("error")
		State.add_log("在庫がありません。【クラフト】で製造してください。", "warn")
		return
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
			modal = Modal.NONE if modal == Modal.CRAFT else Modal.CRAFT
			if modal == Modal.CRAFT:
				if State.tut_step == 1: craft_tab = 0
				elif State.tut_step == 3: craft_tab = 1
			Sfx.play("select")
		"open_tech":
			modal = Modal.NONE if modal == Modal.TECH else Modal.TECH
			if modal == Modal.TECH and State.tut_step == 2:
				tech_sel = 1
			Sfx.play("select")
		"open_cmd":
			modal = Modal.NONE if modal == Modal.COMMAND else Modal.COMMAND
			Sfx.play("select")
		"open_guide":
			modal = Modal.NONE if modal == Modal.GUIDE else Modal.GUIDE
			Sfx.play("select")
		"close":
			modal = Modal.NONE; redrop_armed = false; Sfx.play("click")
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
				State.add_log("配置モード: %s（地面をタップして設置）" % State.BLD[bid]["name"], "info")
		"tool":
			_pick_tool(String(h["v"]))
		"cancel_tool":
			State.selected_tool = "mine"
			if grid:
				grid.wire_pick_uid = -1
				grid.conveyor_pick_uid = -1
				grid.salvage_armed_uid = -1
			Sfx.play("click")
		"flip_dir":
			State.build_dir = -State.build_dir; Sfx.play("click")
		"tech_sel":
			tech_sel = int(h["v"]); Sfx.play("click")
		"tech_buy":
			State.research(String(h["v"]))
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
		"depot_flt":
			if grid: grid.depot_cycle_filter(depot_uid, String(h["v"]))
		"depot_link_flt":
			if grid: grid.depot_cycle_link_filter(int(h["v"]))
		"depot_conv":
			if grid:
				grid.start_conveyor_from(depot_uid)
				modal = Modal.NONE
		"depot_take":
			if grid: grid.depot_transfer(depot_uid, String(h["v"]), false, 5)
		"bld_collect":
			if grid: grid.building_collect(inspect_uid)
		"bld_feed":
			if grid: grid.building_hand_feed(inspect_uid)
		"bld_flip":
			if grid: grid.building_flip_dir(inspect_uid)
		"bld_recipe":
			if grid: grid.building_cycle_recipe(inspect_uid)
		"bld_wire":
			if grid:
				grid.start_wire_from(inspect_uid)
				modal = Modal.NONE
		"bld_conv":
			if grid:
				grid.start_conveyor_from(inspect_uid)
				modal = Modal.NONE
		"bld_salvage":
			if grid and grid.salvage_by_uid(inspect_uid):
				inspect_uid = -1
				modal = Modal.NONE

func _add_hit(r: Rect2, a: String, v = null) -> void:
	_hits.append({"r": r, "a": a, "v": v})

func _panel(r: Rect2, bg: Color, edge: Color, bw: float = 1.5) -> void:
	root_ctrl.draw_rect(r, bg)
	root_ctrl.draw_rect(r, edge, false, bw)

func _pulse_frame(r: Rect2) -> void:
	var a := 0.65 + 0.35 * sin(anim_t * 6.5)
	var pad := 2.0 + sin(anim_t * 6.5) * 1.5
	root_ctrl.draw_rect(r.grow(pad), Color(1.0, 0.86, 0.24, a), false, 2.6)

# ------------------------------------------------------------------------------
# メイン描画（視界を広く保ちつつ、全操作が2〜3タップで完結）
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
		Modal.CRAFT:    _draw_craft_modal(vp, portrait, font)
		Modal.TECH:     _draw_tech_modal(vp, portrait, font)
		Modal.COMMAND:  _draw_command_modal(vp, portrait, font)
		Modal.DEPOT:    _draw_depot_modal(vp, font)
		Modal.BUILDING: _draw_building_modal(vp, font)
		Modal.GUIDE:    _draw_guide_modal(vp, portrait, font)

	if touch_ui_active and modal == Modal.NONE:
		_draw_touch_controls(font)

	if State.game_won:
		var vr := Rect2(vp.x * 0.5 - 220, 74, 440, 44)
		_panel(vr, Color(0.06, 0.24, 0.16, 0.96), Color(0.36, 1.0, 0.72), 2.2)
		root_ctrl.draw_string(font, Vector2(vr.position.x, vr.position.y + 28), "完全勝利：星系解放＆ワープゲート起動！", HORIZONTAL_ALIGNMENT_CENTER, vr.size.x, 14, Color(0.90, 1.0, 0.94))

# 1. 自機周囲の戦闘機HUD円弧（耐久・燃料・イオン・速度）
func _draw_diegetic_arcs(vp: Vector2, font: Font) -> void:
	if not player or State.orbit_view: return
	var cam := get_viewport().get_camera_2d()
	if not cam or cam.zoom.x < 0.30: return
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
		root_ctrl.draw_string(font, sp + Vector2(rad + 8, 4), "%dm/s" % int(player.velocity.length()), HORIZONTAL_ALIGNMENT_LEFT, 68, 10, Color(0.84, 0.92, 1.0, 0.85))

# 2. 左上スリム状況パネル（資源・電力・艦隊・製造キューミニバー）
func _draw_top_left_status(vp: Vector2, portrait: bool, font: Font) -> void:
	var has_ref := (State.get_r("plate_fe") + State.get_r("wire_cu") + State.get_r("wafer_si") + State.get_r("circuit")) > 0
	var w := 224.0 if not portrait else minf(vp.x - 108.0, 324.0)
	var h := (124.0 if has_ref else 102.0) if not portrait else (106.0 if has_ref else 86.0)
	var r := Rect2(8, 8, w, h)
	_panel(r, Color(0.05, 0.07, 0.12, 0.88), Color(0.24, 0.36, 0.50, 0.86), 1.4)

	var base_items: Array[String] = ["fe", "cu", "si", "ti"]
	var ref_items: Array[String] = ["plate_fe", "wire_cu", "wafer_si", "circuit"]
	var cw := (w - 14.0) / 4.0
	for i in range(4):
		var id: String = base_items[i]
		var x := r.position.x + 7.0 + float(i) * cw
		var y := r.position.y + 8.0
		var ic := ArtReg.get_icon(id)
		if ic: root_ctrl.draw_texture_rect(ic, Rect2(x, y, 14, 14), false)
		root_ctrl.draw_string(font, Vector2(x + 17, y + 12), "%d" % State.get_r(id), HORIZONTAL_ALIGNMENT_LEFT, int(cw - 17), 11, Color(0.95, 0.98, 1.0))

	var y2 := r.position.y + 32.0
	if has_ref:
		for i in range(4):
			var id: String = ref_items[i]
			var x := r.position.x + 7.0 + float(i) * cw
			var ic := ArtReg.get_icon(id)
			if ic: root_ctrl.draw_texture_rect(ic, Rect2(x, y2 - 2, 14, 14), false)
			root_ctrl.draw_string(font, Vector2(x + 17, y2 + 10), "%d" % State.get_r(id), HORIZONTAL_ALIGNMENT_LEFT, int(cw - 17), 11, Color(0.76, 0.94, 1.0))
		y2 += 22.0

	var pcol := Color(0.36, 0.96, 0.64) if (State.pwr_prod >= State.pwr_use and State.pwr_prod > 0.0) else (Color(1.0, 0.80, 0.34) if State.pwr_stored > 10.0 else Color(0.96, 0.44, 0.38))
	var bat_s := " 蓄:%d%%" % int(State.pwr_stored / maxf(1.0, State.pwr_cap) * 100.0) if State.pwr_cap > 1.0 else ""
	root_ctrl.draw_string(font, Vector2(r.position.x + 8, y2 + 10), "電力 %d/%dW%s  ドローン %d/8" % [int(State.pwr_prod), int(State.pwr_use), bat_s, State.attached_drones], HORIZONTAL_ALIGNMENT_LEFT, int(w - 14), 10, pcol)

	y2 += 26.0
	root_ctrl.draw_string(font, Vector2(r.position.x + 8, y2 + 2), "艦隊: %d / 10,000" % State.swarm_fleet, HORIZONTAL_ALIGNMENT_LEFT, int(w - 16), 10, Color(1.0, 0.86, 0.42))
	var br := Rect2(r.position.x + 8, y2 + 8, w - 16, 6)
	root_ctrl.draw_rect(br, Color(0.10, 0.14, 0.22))
	root_ctrl.draw_rect(Rect2(br.position, Vector2(br.size.x * clampf(float(State.swarm_fleet) / 10000.0, 0.0, 1.0), br.size.y)), Color(0.34, 0.86, 1.0))

	# 製造キュー進行中のミニ進捗バー（タップでクラフト画面へ）
	if not State.craft_queue.is_empty():
		var q0: Dictionary = State.craft_queue[0]
		var pct := clampf(1.0 - float(q0["time_left"]) / maxf(0.1, float(q0["total_time"])), 0.0, 1.0)
		var qr := Rect2(8, r.end.y + 6, w, 34)
		_panel(qr, Color(0.06, 0.14, 0.22, 0.92), Color(0.38, 0.92, 1.0), 1.4)
		var extra := " (+%d)" % (State.craft_queue.size() - 1) if State.craft_queue.size() > 1 else ""
		root_ctrl.draw_string(font, Vector2(qr.position.x + 8, qr.position.y + 15), "製造中: %s%s" % [String(q0["name"]), extra], HORIZONTAL_ALIGNMENT_LEFT, int(w - 16), 10, Color.WHITE)
		root_ctrl.draw_rect(Rect2(qr.position.x + 8, qr.position.y + 22, w - 16, 6), Color(0.10, 0.16, 0.24))
		root_ctrl.draw_rect(Rect2(qr.position.x + 8, qr.position.y + 22, (w - 16) * pct, 6), Color(0.34, 0.96, 0.72))
		_add_hit(qr, "open_craft")

# 3. 右上ミニマルメニュー（たった4ボタン！全操作2〜3タップ）
func _draw_top_right_menu(vp: Vector2, portrait: bool, font: Font) -> void:
	var bw := 98.0 if not portrait else 88.0
	var x := vp.x - bw - 8.0
	var y := 8.0
	var tut_f := String(State.get_tutorial_info()["focus"]) if State.tut_enabled else ""

	# 1) クラフトボタン
	var cr := Rect2(x, y, bw, 34)
	var qn := State.craft_queue.size()
	var c_lbl := ("クラフト (%d)" % qn) if qn > 0 else ("クラフト [C]" if not portrait else "クラフト")
	_panel(cr, Color(0.08, 0.20, 0.30, 0.94) if modal == Modal.CRAFT else Color(0.05, 0.09, 0.16, 0.90), Color(0.42, 0.94, 1.0), 1.6)
	root_ctrl.draw_string(font, Vector2(cr.position.x, cr.position.y + 22), c_lbl, HORIZONTAL_ALIGNMENT_CENTER, bw, 11, Color.WHITE)
	if modal == Modal.NONE and (tut_f == "craft_drone" or tut_f == "craft_power"):
		_pulse_frame(cr)
	_add_hit(cr, "open_craft")
	y += 40.0

	# 2) 研究ボタン
	var ready_t := false
	for tid in State.TECH_ORDER:
		if State.can_research(tid): ready_t = true; break
	var tr := Rect2(x, y, bw, 34)
	var t_lbl := "研究 %d/8" % State.unlocked_techs.size()
	_panel(tr, Color(0.12, 0.22, 0.32, 0.94) if modal == Modal.TECH else Color(0.05, 0.09, 0.16, 0.90), Color(1.0, 0.84, 0.32) if ready_t else Color(0.36, 0.78, 1.0), 1.6)
	root_ctrl.draw_string(font, Vector2(tr.position.x, tr.position.y + 22), t_lbl, HORIZONTAL_ALIGNMENT_CENTER, bw, 11, Color(1.0, 0.92, 0.56) if ready_t else Color.WHITE)
	if modal == Modal.NONE and tut_f == "research_power":
		_pulse_frame(tr)
	_add_hit(tr, "open_tech")
	y += 40.0

	# 3) 指令ボタン（軌道マップ・艦隊ドクトリン・メガ構造物・設定）
	var mr := Rect2(x, y, bw, 34)
	_panel(mr, Color(0.14, 0.16, 0.30, 0.94) if (modal == Modal.COMMAND or State.orbit_view) else Color(0.05, 0.09, 0.16, 0.90), Color(0.62, 0.54, 1.0), 1.5)
	root_ctrl.draw_string(font, Vector2(mr.position.x, mr.position.y + 22), "指令・地図" if not State.orbit_view else "通常視点へ", HORIZONTAL_ALIGNMENT_CENTER, bw, 11, Color.WHITE)
	_add_hit(mr, "toggle_orbit" if State.orbit_view else "open_cmd")
	y += 40.0

	# 4) ガイドボタン
	var gr := Rect2(x, y, bw, 28)
	_panel(gr, Color(0.06, 0.14, 0.18, 0.92) if modal == Modal.GUIDE else Color(0.05, 0.08, 0.14, 0.88), Color(0.38, 0.88, 0.74), 1.3)
	root_ctrl.draw_string(font, Vector2(gr.position.x, gr.position.y + 19), "ガイド [H]" if not portrait else "ガイド", HORIZONTAL_ALIGNMENT_CENTER, bw, 10, Color(0.84, 0.96, 0.92))
	_add_hit(gr, "open_guide")

# 4. 上部インタラクティブ・チュートリアル誘導バナー
func _draw_tutorial_banner(vp: Vector2, portrait: bool, font: Font) -> void:
	var info := State.get_tutorial_info()
	var w := minf(vp.x - 16.0, 620.0) if not portrait else (vp.x - 16.0)
	var h := 50.0 if not portrait else 54.0
	var x := (vp.x - w) * 0.5 if not portrait else 8.0
	var y := 8.0 if not portrait else 160.0
	var r := Rect2(x, y, w, h)
	_panel(r, Color(0.05, 0.11, 0.19, 0.92), Color(1.0, 0.84, 0.34, 0.92), 1.6)
	root_ctrl.draw_string(font, Vector2(r.position.x + 10, r.position.y + 18), "【ガイド %s】 %s" % [String(info["step"]), String(info["title"])], HORIZONTAL_ALIGNMENT_LEFT, int(w - 76), 11, Color(1.0, 0.88, 0.40))
	root_ctrl.draw_string(font, Vector2(r.position.x + 10, r.position.y + 38), String(info["hint"]), HORIZONTAL_ALIGNMENT_LEFT, int(w - 20), 10 if portrait else 11, Color(0.94, 0.97, 1.0))

	var hr := Rect2(r.end.x - 54, r.position.y + 4, 48, 18)
	_panel(hr, Color(0.10, 0.14, 0.22, 0.90), Color(0.42, 0.54, 0.68), 1.0)
	root_ctrl.draw_string(font, Vector2(hr.position.x, hr.position.y + 13), "非表示", HORIZONTAL_ALIGNMENT_CENTER, hr.size.x, 9, Color(0.80, 0.88, 0.96))
	_add_hit(hr, "tut_toggle")

# 5. 右下テレメトリ＆ログ（デスクトップのみ）
func _draw_bottom_right_telemetry(vp: Vector2, portrait: bool, font: Font) -> void:
	if portrait: return
	var w := 310.0; var h := 104.0
	var r := Rect2(vp.x - w - 8.0, vp.y - h - 8.0, w, h)
	_panel(r, Color(0.04, 0.06, 0.10, 0.86), Color(0.24, 0.34, 0.48, 0.85), 1.3)
	var g_v: float = float(player.local_g) if player else 1.0
	var at_v: float = float(planet.get_atmos_density(player.position)) if (planet and player) else 1.0
	var vl_v: int = int(player.velocity.length()) if player else 0
	var al_v: int = int(player.get_altitude()) if player else 0
	root_ctrl.draw_string(font, Vector2(r.position.x + 8, r.position.y + 17), "重力 %.2fG  大気 %.2f  速度 %dm/s  高度 %dm" % [g_v, at_v, vl_v, al_v], HORIZONTAL_ALIGNMENT_LEFT, int(w - 14), 10, Color(0.76, 0.88, 0.98))
	root_ctrl.draw_line(Vector2(r.position.x + 6, r.position.y + 25), Vector2(r.end.x - 6, r.position.y + 25), Color(0.22, 0.32, 0.44), 1.0)
	var y := r.position.y + 42.0
	var st := maxi(0, State.logs.size() - 4)
	for i in range(st, State.logs.size()):
		var lg := State.logs[i]
		var c := Color(0.45, 0.96, 0.70) if lg["kind"] == "good" else (Color(1.0, 0.78, 0.34) if lg["kind"] == "warn" else Color(0.86, 0.90, 0.96))
		root_ctrl.draw_string(font, Vector2(r.position.x + 8, y), "・" + String(lg["msg"]), HORIZONTAL_ALIGNMENT_LEFT, int(w - 14), 9, c)
		y += 16.0

# 6. 下部スッキリ所持ツールバー（通常・配線・搬送・削除を常設固定 ＋ クラフト済みの所持装置！）
func _draw_bottom_dock(vp: Vector2, portrait: bool, font: Font) -> void:
	var slots: Array[Dictionary] = [{"id": "mine", "label": "通常"}]
	if State.is_unlocked("wire"):
		slots.append({"id": "wire", "label": "配線"})
	if State.is_unlocked("conveyor"):
		slots.append({"id": "conveyor", "label": "搬送"})
	slots.append({"id": "salvage", "label": "削除"})
	var owned := State.get_owned_buildings()
	for bid in owned:
		slots.append({"id": bid, "label": String(State.BLD[bid]["short"]), "cnt": State.get_stock(bid)})
	if owned.is_empty():
		slots.append({"id": "__craft", "label": "+製造"})

	var slot_sz := 48.0 if portrait else 54.0
	var gap := 6.0
	var max_slots := mini(slots.size(), 9 if not portrait else 8)
	var bar_w := float(max_slots) * (slot_sz + gap) + gap + 10.0
	var bar_h := slot_sz + 14.0
	var bx := (vp.x - bar_w) * 0.5
	var by := vp.y - bar_h - 8.0

	# 配置モード／配線モード／搬送モード／削除モード中の明快ガイドバー
	if modal == Modal.NONE and State.selected_tool != "mine":
		var mw := minf(vp.x - 16.0, 510.0)
		var mr := Rect2((vp.x - mw) * 0.5, by - 36.0, mw, 30.0)
		var bar_col := Color(1.0, 0.44, 0.42) if State.selected_tool == "salvage" else (Color(1.0, 0.80, 0.30) if State.selected_tool == "conveyor" else Color(0.40, 0.96, 0.82))
		_panel(mr, Color(0.06, 0.16, 0.24, 0.94), bar_col, 1.5)
		var msg := ""
		if State.selected_tool == "wire":
			msg = "【配線モード】 発電機 → テスラリレーの順にタップして電線を接続"
		elif State.selected_tool == "conveyor":
			msg = "【搬送モード】 送り元 → 送り先施設をタップで自由接続（距離分の鉄消費）"
		elif State.selected_tool == "salvage":
			msg = "【削除モード】 削除したい施設をダブルタップ（2回タップで回収）"
		elif State.selected_tool == "drill":
			msg = "【配置: 採掘ドリル (残%d)】 光る「硬質鉱床」をタップして設置" % State.get_stock("drill")
		elif State.BLD.has(State.selected_tool):
			msg = "【配置: %s (残%d)】 地面をタップして設置" % [State.BLD[State.selected_tool]["name"], State.get_stock(State.selected_tool)]
		root_ctrl.draw_string(font, Vector2(mr.position.x + 10, mr.position.y + 19), msg, HORIZONTAL_ALIGNMENT_LEFT, int(mw - 70), 10, Color(0.92, 1.0, 0.96))
		var cr := Rect2(mr.end.x - 54, mr.position.y + 4, 48, 22)
		_panel(cr, Color(0.28, 0.09, 0.11, 0.94), Color(1.0, 0.44, 0.44), 1.2)
		root_ctrl.draw_string(font, Vector2(cr.position.x, cr.position.y + 15), "解除", HORIZONTAL_ALIGNMENT_CENTER, cr.size.x, 10, Color.WHITE)
		_add_hit(cr, "cancel_tool")

	var br := Rect2(bx, by, bar_w, bar_h)
	_panel(br, Color(0.05, 0.07, 0.12, 0.92), Color(0.28, 0.40, 0.56, 0.90), 1.5)
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
		_panel(sr, bg, bd, 2.0 if sel else 1.2)

		var tex_k := String(State.BLD[tid]["tex"]) if State.BLD.has(tid) else ("seed_core" if tid == "mine" else "")
		var t := ArtReg.get_t(tex_k) if tex_k != "" else null
		if t:
			var pad := 6.0
			root_ctrl.draw_texture_rect(t, Rect2(sx + pad, sy + 4.0, slot_sz - pad * 2.0, slot_sz - 18.0), false)
		else:
			var sym := "電線" if tid == "wire" else ("搬送" if tid == "conveyor" else ("削除" if tid == "salvage" else "＋"))
			var sc := Color(0.42, 0.96, 1.0) if tid == "wire" else (Color(1.0, 0.80, 0.28) if tid == "conveyor" else (Color(1.0, 0.46, 0.42) if tid == "salvage" else Color(0.45, 1.0, 0.76)))
			root_ctrl.draw_string(font, Vector2(sx, sy + slot_sz * 0.52), sym, HORIZONTAL_ALIGNMENT_CENTER, slot_sz, 12, sc)

		root_ctrl.draw_string(font, Vector2(sx, sy + slot_sz - 4), String(s["label"]), HORIZONTAL_ALIGNMENT_CENTER, slot_sz, 9, Color.WHITE)
		if s.has("cnt"):
			var cr_b := Rect2(sx + slot_sz - 22, sy + 2, 20, 14)
			root_ctrl.draw_rect(cr_b, Color(0.08, 0.26, 0.34, 0.95))
			root_ctrl.draw_string(font, Vector2(cr_b.position.x, cr_b.position.y + 11), "x%d" % int(s["cnt"]), HORIZONTAL_ALIGNMENT_CENTER, 20, 9, Color(0.55, 1.0, 0.82))

		if modal == Modal.NONE:
			if tut_f == "place_power" and (tid == "solar" or tid == "tesla"):
				_pulse_frame(sr)
			elif tut_f == "wire_power" and tid == "wire":
				_pulse_frame(sr)

		if tid == "__craft":
			_add_hit(sr, "open_craft")
		else:
			_add_hit(sr, "tool", tid)

# 7. クラフト＆製造キュー画面 ([C])
func _draw_craft_modal(vp: Vector2, portrait: bool, font: Font) -> void:
	var mw := minf(vp.x - 20.0, 820.0)
	var mh := minf(vp.y - 40.0, 610.0)
	var r := Rect2((vp.x - mw) * 0.5, (vp.y - mh) * 0.5, mw, mh)
	_panel(r, Color(0.04, 0.06, 0.12, 0.97), Color(0.38, 0.90, 1.0), 2.0)

	var spd_pct := int(round((1.0 + float(State.attached_drones) * 0.18) * 100.0))
	root_ctrl.draw_string(font, Vector2(r.position.x + 14, r.position.y + 24), "クラフト・製造ドック（製造速度 %d%%）" % spd_pct, HORIZONTAL_ALIGNMENT_LEFT, int(mw - 90), 13, Color(0.48, 0.96, 1.0))
	var cr := Rect2(r.end.x - 68, r.position.y + 7, 58, 24)
	_panel(cr, Color(0.28, 0.08, 0.10, 0.94), Color(1.0, 0.42, 0.42), 1.4)
	root_ctrl.draw_string(font, Vector2(cr.position.x, cr.position.y + 16), "閉じる", HORIZONTAL_ALIGNMENT_CENTER, cr.size.x, 10, Color.WHITE)
	_add_hit(cr, "close")

	# 4カテゴリタブ
	var ty := r.position.y + 38.0
	var tw := (mw - 24.0) / float(State.CRAFT_TABS.size())
	var tut_f := String(State.get_tutorial_info()["focus"]) if State.tut_enabled else ""
	for ti in range(State.CRAFT_TABS.size()):
		var tr := Rect2(r.position.x + 12.0 + float(ti) * tw, ty, tw - 4.0, 28.0)
		var sel := (ti == craft_tab)
		_panel(tr, Color(0.12, 0.26, 0.38, 0.96) if sel else Color(0.06, 0.09, 0.16, 0.90), Color(0.45, 0.96, 1.0) if sel else Color(0.26, 0.36, 0.50), 1.4)
		root_ctrl.draw_string(font, Vector2(tr.position.x, tr.position.y + 18), String(State.CRAFT_TABS[ti]["label"]), HORIZONTAL_ALIGNMENT_CENTER, tr.size.x, 11, Color.WHITE if sel else Color(0.70, 0.78, 0.88))
		if (tut_f == "craft_drone" and ti == 0 and not sel) or (tut_f == "craft_power" and ti == 1 and not sel):
			_pulse_frame(tr)
		_add_hit(tr, "craft_tab", ti)

	# アイテム一覧領域
	var qh := 94.0
	var list_y := ty + 36.0
	var list_h := mh - (list_y - r.position.y) - qh - 14.0
	var card_w := mw - 24.0

	if craft_tab == 0:
		# 機体・増設タブ：ファブリケータードローン ＋ 推進モジュール
		var y := list_y
		var ch := 88.0
		# カード1: ファブリケータードローン
		var dr := Rect2(r.position.x + 12, y, card_w, ch)
		var can_d := State.can_enqueue_drone()
		var qd := State.count_queued("drone")
		_panel(dr, Color(0.07, 0.14, 0.22, 0.95), Color(0.42, 0.96, 1.0) if can_d else Color(0.28, 0.38, 0.50), 1.6)
		var dt := ArtReg.get_t("fab_drone")
		if dt: root_ctrl.draw_texture_rect(dt, Rect2(dr.position.x + 12, dr.position.y + 18, 48, 48), false)
		var tx := dr.position.x + 72.0
		var bw := 112.0 if not portrait else 92.0
		var info_w := int(card_w - 84.0 - bw)
		var f_desc := 9 if portrait else 10
		root_ctrl.draw_string(font, Vector2(tx, dr.position.y + 22), "ファブリケータードローン（現在 %d/%d機%s）" % [State.attached_drones, State.MAX_DRONES, (" 製造中:%d" % qd) if qd > 0 else ""], HORIZONTAL_ALIGNMENT_LEFT, info_w, 11 if portrait else 12, Color.WHITE)
		root_ctrl.draw_string(font, Vector2(tx, dr.position.y + 42), "完成で自動ドッキング！採掘ビーム+1 & 製造速度+18%", HORIZONTAL_ALIGNMENT_LEFT, info_w, f_desc, Color(0.80, 0.90, 0.98))
		root_ctrl.draw_string(font, Vector2(tx, dr.position.y + 64), "必要資源: %s  |  %.1f秒" % [State.format_cost(State.DRONE_COST), State.DRONE_CRAFT_TIME], HORIZONTAL_ALIGNMENT_LEFT, info_w, f_desc, Color(0.50, 0.98, 0.76) if can_d else Color(1.0, 0.62, 0.50))
		var db := Rect2(dr.end.x - bw - 10, dr.position.y + 22, bw, 44)
		_panel(db, Color(0.08, 0.28, 0.22, 0.96) if can_d else Color(0.09, 0.11, 0.17, 0.90), Color(0.38, 1.0, 0.72) if can_d else Color(0.34, 0.42, 0.52), 1.6)
		root_ctrl.draw_string(font, Vector2(db.position.x, db.position.y + 26), "上限達成" if State.attached_drones >= State.MAX_DRONES else "製造 (+1)", HORIZONTAL_ALIGNMENT_CENTER, bw, 11, Color.WHITE if can_d else Color(0.60, 0.68, 0.76))
		if tut_f == "craft_drone" and can_d:
			_pulse_frame(db)
		if can_d: _add_hit(db, "craft_drone")

		# カード2: 次世代推進モジュール
		y += ch + 12.0
		var nxt := State.propulsion_tier + 1
		var pr := Rect2(r.position.x + 12, y, card_w, ch)
		var pt := ArtReg.get_t("orbital_booster")
		if State.PROPULSION_TIERS.has(nxt):
			var pinfo: Dictionary = State.PROPULSION_TIERS[nxt]
			var can_p := State.can_enqueue_propulsion()
			var req_ok := State.has_tech(String(pinfo["req"]))
			_panel(pr, Color(0.07, 0.14, 0.20, 0.95), Color(0.42, 1.0, 0.74) if can_p else Color(0.28, 0.38, 0.50), 1.6)
			if pt: root_ctrl.draw_texture_rect(pt, Rect2(pr.position.x + 12, pr.position.y + 18, 48, 48), false)
			root_ctrl.draw_string(font, Vector2(tx, pr.position.y + 22), "推進強化: %s（Tier %d）" % [String(pinfo["name"]), nxt], HORIZONTAL_ALIGNMENT_LEFT, info_w, 12, Color.WHITE)
			root_ctrl.draw_string(font, Vector2(tx, pr.position.y + 42), String(pinfo["desc"]), HORIZONTAL_ALIGNMENT_LEFT, info_w, 10, Color(0.80, 0.90, 0.98))
			var status_s := "必要資源: %s  |  %.1f秒" % [State.format_cost(pinfo["cost"]), float(pinfo["craft_time"])] if req_ok else "要研究: 【%s】" % State.TECHS[String(pinfo["req"])]["name"]
			root_ctrl.draw_string(font, Vector2(tx, pr.position.y + 64), status_s, HORIZONTAL_ALIGNMENT_LEFT, info_w, 10, Color(0.50, 0.98, 0.76) if can_p else Color(1.0, 0.74, 0.40))
			var pb := Rect2(pr.end.x - bw - 10, pr.position.y + 22, bw, 44)
			_panel(pb, Color(0.08, 0.28, 0.22, 0.96) if can_p else Color(0.09, 0.11, 0.17, 0.90), Color(0.38, 1.0, 0.72) if can_p else Color(0.34, 0.42, 0.52), 1.6)
			root_ctrl.draw_string(font, Vector2(pb.position.x, pb.position.y + 26), "製造する" if can_p else ("未解放" if not req_ok else "資源不足"), HORIZONTAL_ALIGNMENT_CENTER, bw, 11, Color.WHITE if can_p else Color(0.60, 0.68, 0.76))
			if can_p: _add_hit(pb, "craft_prop")
		else:
			_panel(pr, Color(0.06, 0.20, 0.16, 0.94), Color(0.40, 1.0, 0.72), 1.5)
			root_ctrl.draw_string(font, Vector2(pr.position.x + 18, pr.position.y + 48), "推進機関は最大強化（スウォーム旗艦ドライブ）に到達しています！", HORIZONTAL_ALIGNMENT_LEFT, int(card_w - 36), 12, Color(0.66, 1.0, 0.82))
	else:
		# 建物製造リスト
		var items: Array = State.CRAFT_TABS[craft_tab]["items"]
		var row_h := clampf((list_h - float(items.size() - 1) * 6.0) / float(maxi(1, items.size())), 58.0, 78.0)
		var y := list_y
		for bid_v in items:
			var bid := String(bid_v)
			var info: Dictionary = State.BLD[bid]
			var unl := State.is_unlocked(bid)
			var can_b := State.can_enqueue_building(bid)
			var stock := State.get_stock(bid)
			var qcnt := State.count_queued("building", bid)
			var br := Rect2(r.position.x + 12, y, card_w, row_h)
			_panel(br, Color(0.07, 0.11, 0.18, 0.94) if unl else Color(0.05, 0.06, 0.10, 0.88), Color(0.36, 0.74, 0.94) if can_b else Color(0.24, 0.30, 0.42), 1.3)

			var itex := ArtReg.get_t(String(info["tex"]))
			var isz := minf(42.0, row_h - 14.0)
			if itex:
				root_ctrl.draw_texture_rect(itex, Rect2(br.position.x + 10, br.position.y + (row_h - isz) * 0.5, isz, isz), false, Color.WHITE if unl else Color(0.4, 0.4, 0.45, 0.6))

			var btn_w := 84.0 if not portrait else 74.0
			var has_place := stock > 0
			var right_pad := (btn_w * 2.0 + 18.0) if has_place else (btn_w + 14.0)
			var tx := br.position.x + isz + 18.0
			var tw_i := int(card_w - (isz + 22.0) - right_pad)
			var hdr := "%s（所持:%d%s）" % [String(info["name"]), stock, (" 製造中:%d" % qcnt) if qcnt > 0 else ""]
			root_ctrl.draw_string(font, Vector2(tx, br.position.y + 18), hdr, HORIZONTAL_ALIGNMENT_LEFT, tw_i, 11, Color.WHITE if unl else Color(0.60, 0.66, 0.76))
			root_ctrl.draw_string(font, Vector2(tx, br.position.y + 35), String(info["desc"]), HORIZONTAL_ALIGNMENT_LEFT, tw_i, 9, Color(0.76, 0.86, 0.96))
			var sub := "%s  |  %.1f秒" % [State.format_cost(info["cost"]), float(info["craft_time"])] if unl else "要研究: 【%s】" % State.TECHS[String(info["req"])]["name"]
			root_ctrl.draw_string(font, Vector2(tx, br.position.y + row_h - 8), sub, HORIZONTAL_ALIGNMENT_LEFT, tw_i, 9, Color(0.50, 0.96, 0.74) if can_b else Color(1.0, 0.68, 0.44))

			var by_btn := br.position.y + (row_h - 34.0) * 0.5
			if has_place:
				var pl_r := Rect2(br.end.x - btn_w * 2.0 - 14.0, by_btn, btn_w, 34.0)
				_panel(pl_r, Color(0.10, 0.24, 0.36, 0.96), Color(0.45, 0.96, 1.0), 1.5)
				root_ctrl.draw_string(font, Vector2(pl_r.position.x, pl_r.position.y + 21), "配置する", HORIZONTAL_ALIGNMENT_CENTER, btn_w, 10, Color.WHITE)
				_add_hit(pl_r, "equip_place", bid)

			var mk_r := Rect2(br.end.x - btn_w - 8.0, by_btn, btn_w, 34.0)
			_panel(mk_r, Color(0.08, 0.28, 0.20, 0.96) if can_b else Color(0.09, 0.11, 0.17, 0.90), Color(0.38, 1.0, 0.72) if can_b else Color(0.30, 0.38, 0.48), 1.5)
			root_ctrl.draw_string(font, Vector2(mk_r.position.x, mk_r.position.y + 21), "製造 (+1)" if unl else "未解放", HORIZONTAL_ALIGNMENT_CENTER, btn_w, 10, Color.WHITE if can_b else Color(0.55, 0.62, 0.70))
			if tut_f == "craft_power" and (bid == "solar" or bid == "tesla") and can_b and (stock + qcnt + int(State.tut_placed.get(bid, 0))) == 0:
				_pulse_frame(mk_r)
			if can_b: _add_hit(mk_r, "craft_bld", bid)

			y += row_h + 6.0

	# 下部: 製造キュー（Craft Queue）パネル
	var qr := Rect2(r.position.x + 12, r.end.y - qh - 8, card_w, qh)
	_panel(qr, Color(0.05, 0.08, 0.15, 0.96), Color(0.34, 0.68, 0.92), 1.5)
	root_ctrl.draw_string(font, Vector2(qr.position.x + 10, qr.position.y + 18), "製造キュー（%d/12）  ※キュー内の項目をタップするとキャンセル＆資源返却" % State.craft_queue.size(), HORIZONTAL_ALIGNMENT_LEFT, int(card_w - 20), 10, Color(0.68, 0.88, 1.0))

	if State.craft_queue.is_empty():
		root_ctrl.draw_string(font, Vector2(qr.position.x + 10, qr.position.y + 56), "現在製造中のアイテムはありません。上の「製造 (+1)」からキューに追加しよう！", HORIZONTAL_ALIGNMENT_LEFT, int(card_w - 20), 11, Color(0.58, 0.68, 0.80))
	else:
		var qx := qr.position.x + 10.0
		var qy := qr.position.y + 26.0
		var max_show := mini(State.craft_queue.size(), 5 if not portrait else 3)
		var q_slot_w := (card_w - 20.0 - float(max_show - 1) * 6.0) / float(max_show)
		for qi in range(max_show):
			var q: Dictionary = State.craft_queue[qi]
			var sr := Rect2(qx + float(qi) * (q_slot_w + 6.0), qy, q_slot_w, 58.0)
			var is_head := (qi == 0)
			_panel(sr, Color(0.08, 0.20, 0.28, 0.96) if is_head else Color(0.07, 0.10, 0.17, 0.92), Color(0.40, 1.0, 0.78) if is_head else Color(0.30, 0.42, 0.56), 1.4)
			root_ctrl.draw_string(font, Vector2(sr.position.x + 6, sr.position.y + 17), "#%d %s" % [qi + 1, String(q["name"])], HORIZONTAL_ALIGNMENT_LEFT, int(q_slot_w - 12), 10, Color.WHITE)
			if is_head:
				var pct := clampf(1.0 - float(q["time_left"]) / maxf(0.1, float(q["total_time"])), 0.0, 1.0)
				root_ctrl.draw_string(font, Vector2(sr.position.x + 6, sr.position.y + 34), "残り %.1f秒" % maxf(0.0, float(q["time_left"])), HORIZONTAL_ALIGNMENT_LEFT, int(q_slot_w - 12), 9, Color(0.55, 1.0, 0.82))
				root_ctrl.draw_rect(Rect2(sr.position.x + 6, sr.position.y + 42, q_slot_w - 12, 8), Color(0.10, 0.14, 0.22))
				root_ctrl.draw_rect(Rect2(sr.position.x + 6, sr.position.y + 42, (q_slot_w - 12) * pct, 8), Color(0.36, 0.98, 0.74))
			else:
				root_ctrl.draw_string(font, Vector2(sr.position.x + 6, sr.position.y + 38), "待機中（タップで中止）", HORIZONTAL_ALIGNMENT_LEFT, int(q_slot_w - 12), 9, Color(0.66, 0.76, 0.88))
			_add_hit(sr, "cancel_q", qi)

# 8. Factorio式 技術ツリー研究画面 ([T])
func _draw_tech_modal(vp: Vector2, portrait: bool, font: Font) -> void:
	var mw := minf(vp.x - 20.0, 880.0)
	var mh := minf(vp.y - 60.0, 540.0)
	var r := Rect2((vp.x - mw) * 0.5, (vp.y - mh) * 0.5, mw, mh)
	_panel(r, Color(0.03, 0.05, 0.10, 0.97), Color(0.36, 0.86, 1.0), 2.0)
	root_ctrl.draw_string(font, Vector2(r.position.x + 14, r.position.y + 24), "コロニー技術研究所 // 技術ツリー", HORIZONTAL_ALIGNMENT_LEFT, int(mw - 90), 13, Color(0.48, 0.96, 1.0))

	var cr := Rect2(r.end.x - 68, r.position.y + 7, 58, 24)
	_panel(cr, Color(0.28, 0.08, 0.10, 0.94), Color(1.0, 0.42, 0.42), 1.4)
	root_ctrl.draw_string(font, Vector2(cr.position.x, cr.position.y + 16), "閉じる", HORIZONTAL_ALIGNMENT_CENTER, cr.size.x, 10, Color.WHITE)
	_add_hit(cr, "close")

	var cards: Dictionary = {}
	var dh := 124.0
	var gh := mh - dh - 48.0
	if portrait:
		var cw := (mw - 32.0) * 0.5; var ch := clampf((gh - 28.0) / 4.0, 44.0, 58.0)
		for i in range(State.TECH_ORDER.size()):
			var tid := State.TECH_ORDER[i]
			cards[tid] = Rect2(r.position.x + 12 + float(i % 2) * (cw + 8), r.position.y + 40 + float(i / 2) * (ch + 8), cw, ch)
	else:
		var cw := (mw - 76.0) / 6.0; var ch := 64.0; var rsp := gh / 3.0
		for tid in State.TECH_ORDER:
			var t: Dictionary = State.TECHS[tid]
			cards[tid] = Rect2(r.position.x + 16 + float(int(t["col"])) * (cw + 8), r.position.y + 42 + float(int(t["row"])) * rsp, cw, ch)

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
		root_ctrl.draw_string(font, Vector2(box_r.position.x + 8, box_r.position.y + 22), String(t["name"]), HORIZONTAL_ALIGNMENT_LEFT, int(box_r.size.x - 14), 11, Color.WHITE)
		var st := "研究済" if done else ("研究可能！" if avail else "未解放")
		root_ctrl.draw_string(font, Vector2(box_r.position.x + 8, box_r.end.y - 8), st, HORIZONTAL_ALIGNMENT_LEFT, int(box_r.size.x - 14), 10, Color(0.45, 1.0, 0.72) if done else (Color(1.0, 0.84, 0.34) if avail else Color(0.56, 0.64, 0.76)))
		_add_hit(box_r, "tech_sel", i)

	var sid := State.TECH_ORDER[clampi(tech_sel, 0, State.TECH_ORDER.size() - 1)]
	var td: Dictionary = State.TECHS[sid]
	var dr := Rect2(r.position.x + 12, r.end.y - dh - 10, mw - 24, dh)
	_panel(dr, Color(0.05, 0.08, 0.15, 0.96), Color(0.36, 0.78, 1.0), 1.5)
	var bw := 102.0 if portrait else 156.0
	var tw := int(dr.size.x - bw - 22)
	var fs_h := 10 if portrait else 12
	var fs_b := 9 if portrait else 11
	var fs_s := 9 if portrait else 10
	root_ctrl.draw_string(font, Vector2(dr.position.x + 10, dr.position.y + 22), "%s  |  解放: %s" % [String(td["name"]), "・".join(td["unlocks"])], HORIZONTAL_ALIGNMENT_LEFT, tw, fs_h, Color(0.46, 0.96, 1.0))
	root_ctrl.draw_string(font, Vector2(dr.position.x + 10, dr.position.y + 46), String(td["summary"]), HORIZONTAL_ALIGNMENT_LEFT, tw, fs_b, Color(0.92, 0.95, 1.0))
	root_ctrl.draw_string(font, Vector2(dr.position.x + 10, dr.position.y + 68), "流れ: " + String(td["flow"]), HORIZONTAL_ALIGNMENT_LEFT, tw, fs_s, Color(0.46, 0.96, 0.72))
	var cp: Array[String] = []
	for k in td["cost"].keys(): cp.append("%s %d/%d" % [State.res_name(String(k)), State.get_r(String(k)), int(td["cost"][k])])
	root_ctrl.draw_string(font, Vector2(dr.position.x + 10, dr.position.y + 96), "必要資源: " + ("  ".join(cp) if not cp.is_empty() else "無料"), HORIZONTAL_ALIGNMENT_LEFT, tw, fs_b, Color(1.0, 0.82, 0.36))

	var rb := Rect2(dr.end.x - bw - 10, dr.position.y + 22, bw, dr.size.y - 44)
	var can_r := State.can_research(sid)
	_panel(rb, Color(0.08, 0.28, 0.20, 0.95) if can_r else Color(0.08, 0.11, 0.18, 0.92), Color(0.36, 1.0, 0.72) if can_r else Color(0.34, 0.44, 0.56), 1.8)
	root_ctrl.draw_string(font, Vector2(rb.position.x, rb.position.y + rb.size.y * 0.5 + 5), "研究済" if State.has_tech(sid) else ("研究開始" if can_r else "条件不足"), HORIZONTAL_ALIGNMENT_CENTER, bw, 12, Color.WHITE if can_r else Color(0.6, 0.68, 0.78))
	if can_r and State.tut_enabled and State.tut_step == 2 and sid == "power_grid":
		_pulse_frame(rb)
	if can_r: _add_hit(rb, "tech_buy", sid)

# 9. 指令・軌道マップ・メガ構造物・システムモーダル ([M])
func _draw_command_modal(vp: Vector2, portrait: bool, font: Font) -> void:
	var mw := minf(vp.x - 20.0, 560.0)
	var mh := minf(vp.y - 40.0, 520.0)
	var r := Rect2((vp.x - mw) * 0.5, (vp.y - mh) * 0.5, mw, mh)
	_panel(r, Color(0.04, 0.06, 0.12, 0.97), Color(0.62, 0.54, 1.0), 2.0)
	root_ctrl.draw_string(font, Vector2(r.position.x + 14, r.position.y + 24), "軌道指令センター // マップ・艦隊・巨大構造物", HORIZONTAL_ALIGNMENT_LEFT, int(mw - 90), 13, Color(0.76, 0.68, 1.0))

	var cr := Rect2(r.end.x - 68, r.position.y + 7, 58, 24)
	_panel(cr, Color(0.28, 0.08, 0.10, 0.94), Color(1.0, 0.42, 0.42), 1.4)
	root_ctrl.draw_string(font, Vector2(cr.position.x, cr.position.y + 16), "閉じる", HORIZONTAL_ALIGNMENT_CENTER, cr.size.x, 10, Color.WHITE)
	_add_hit(cr, "close")

	var y := r.position.y + 42.0
	# 軌道全体マップ切替
	var or_r := Rect2(r.position.x + 14, y, mw - 28, 36)
	_panel(or_r, Color(0.08, 0.22, 0.34, 0.96), Color(0.42, 0.92, 1.0), 1.5)
	root_ctrl.draw_string(font, Vector2(or_r.position.x, or_r.position.y + 23), "惑星・衛星 軌道全体マップを開く [M]" if not State.orbit_view else "通常視点に戻る [M]", HORIZONTAL_ALIGNMENT_CENTER, or_r.size.x, 12, Color.WHITE)
	_add_hit(or_r, "toggle_orbit")
	y += 48.0

	# 艦隊ドクトリン（4種）
	root_ctrl.draw_string(font, Vector2(r.position.x + 14, y + 10), "スウォーム艦隊ドクトリン（現在艦隊: %d / 10,000）" % State.swarm_fleet, HORIZONTAL_ALIGNMENT_LEFT, int(mw - 28), 11, Color(1.0, 0.86, 0.42))
	y += 18.0
	var dw := (mw - 28.0 - 18.0) / 4.0
	for i in range(4):
		var dr := Rect2(r.position.x + 14 + float(i) * (dw + 6.0), y, dw, 32)
		var on := (State.doctrine == i)
		_panel(dr, Color(0.14, 0.28, 0.40, 0.96) if on else Color(0.06, 0.09, 0.16, 0.90), Color(1.0, 0.84, 0.34) if on else Color(0.28, 0.38, 0.52), 1.5)
		root_ctrl.draw_string(font, Vector2(dr.position.x, dr.position.y + 21), State.DOCTRINE_NAMES[i], HORIZONTAL_ALIGNMENT_CENTER, dw, 11, Color.WHITE if on else Color(0.72, 0.80, 0.90))
		_add_hit(dr, "doc", i)
	y += 38.0
	root_ctrl.draw_string(font, Vector2(r.position.x + 14, y + 11), "効果: " + State.DOCTRINE_DESCS[State.doctrine], HORIZONTAL_ALIGNMENT_LEFT, int(mw - 28), 10, Color(0.76, 0.88, 0.98))
	y += 26.0

	# 軌道メガストラクチャー建造
	root_ctrl.draw_string(font, Vector2(r.position.x + 14, y + 10), "軌道メガストラクチャー%s" % ("" if State.has_tech("megastructures") else "（要研究: 巨大構造物）"), HORIZONTAL_ALIGNMENT_LEFT, int(mw - 28), 11, Color(0.76, 0.68, 1.0))
	y += 18.0
	for mid in ["elevator", "dyson", "citadel", "warpgate"]:
		var built := bool(State.megastructures[mid])
		var mr := Rect2(r.position.x + 14, y, mw - 28, 44)
		_panel(mr, Color(0.08, 0.26, 0.18, 0.94) if built else Color(0.07, 0.10, 0.17, 0.92), Color(0.36, 1.0, 0.72) if built else Color(0.38, 0.48, 0.64), 1.3)
		root_ctrl.draw_string(font, Vector2(mr.position.x + 10, mr.position.y + 17), String(State.MEGAS[mid]["name"]) + ("【完成】" if built else ""), HORIZONTAL_ALIGNMENT_LEFT, int(mr.size.x - 20), 11, Color.WHITE)
		root_ctrl.draw_string(font, Vector2(mr.position.x + 10, mr.position.y + 34), "%s  |  %s" % [String(State.MEGAS[mid]["desc"]), State.format_cost(State.MEGAS[mid]["cost"])], HORIZONTAL_ALIGNMENT_LEFT, int(mr.size.x - 20), 9, Color(0.74, 0.84, 0.94))
		if not built: _add_hit(mr, "mega_buy", mid)
		y += 48.0

	# システム（効果音・緊急再降下）
	var sy := r.end.y - 44.0
	var hw := (mw - 34.0) * 0.5
	var sr := Rect2(r.position.x + 14, sy, hw, 32)
	_panel(sr, Color(0.06, 0.10, 0.18, 0.92), Color(0.38, 0.56, 0.74), 1.2)
	root_ctrl.draw_string(font, Vector2(sr.position.x, sr.position.y + 20), "効果音: " + ("OFF" if Sfx.muted else "ON"), HORIZONTAL_ALIGNMENT_CENTER, hw, 11, Color.WHITE)
	_add_hit(sr, "mute")

	var rr := Rect2(sr.end.x + 6, sy, hw, 32)
	_panel(rr, Color(0.36, 0.08, 0.10, 0.95) if redrop_armed else Color(0.18, 0.07, 0.09, 0.92), Color(1.0, 0.42, 0.40), 1.2)
	root_ctrl.draw_string(font, Vector2(rr.position.x, rr.position.y + 20), "本当に北極へ戻る？" if redrop_armed else "緊急再降下（詰み復帰）", HORIZONTAL_ALIGNMENT_CENTER, hw, 10 if portrait else 11, Color(1.0, 0.86, 0.86))
	_add_hit(rr, "redrop")

# 10. 全要素インタラクティブガイド画面 ([H])
func _draw_guide_modal(vp: Vector2, portrait: bool, font: Font) -> void:
	var mw := minf(vp.x - 20.0, 680.0)
	var mh := minf(vp.y - 60.0, 440.0)
	var r := Rect2((vp.x - mw) * 0.5, (vp.y - mh) * 0.5, mw, mh)
	_panel(r, Color(0.04, 0.07, 0.13, 0.97), Color(0.38, 0.92, 0.78), 2.0)
	root_ctrl.draw_string(font, Vector2(r.position.x + 14, r.position.y + 24), "操作ガイド ＆ インタラクティブ・チュートリアル", HORIZONTAL_ALIGNMENT_LEFT, int(mw - 90), 13, Color(0.46, 1.0, 0.82))

	var cr := Rect2(r.end.x - 68, r.position.y + 7, 58, 24)
	_panel(cr, Color(0.28, 0.08, 0.10, 0.94), Color(1.0, 0.42, 0.42), 1.4)
	root_ctrl.draw_string(font, Vector2(cr.position.x, cr.position.y + 16), "閉じる", HORIZONTAL_ALIGNMENT_CENTER, cr.size.x, 10, Color.WHITE)
	_add_hit(cr, "close")

	# 現在のチュートリアルステップ表示 & ON/OFFトグル
	var info := State.get_tutorial_info()
	var tr := Rect2(r.position.x + 14, r.position.y + 38, mw - 28, 54)
	_panel(tr, Color(0.06, 0.14, 0.22, 0.94), Color(1.0, 0.84, 0.34), 1.4)
	root_ctrl.draw_string(font, Vector2(tr.position.x + 10, tr.position.y + 20), "現在の目標（%s）: %s" % [String(info["step"]), String(info["title"])], HORIZONTAL_ALIGNMENT_LEFT, int(tr.size.x - 130), 11, Color(1.0, 0.88, 0.40))
	root_ctrl.draw_string(font, Vector2(tr.position.x + 10, tr.position.y + 40), String(info["hint"]), HORIZONTAL_ALIGNMENT_LEFT, int(tr.size.x - 130), 10, Color.WHITE)
	var tb := Rect2(tr.end.x - 116, tr.position.y + 12, 106, 30)
	_panel(tb, Color(0.08, 0.26, 0.20, 0.95) if State.tut_enabled else Color(0.16, 0.10, 0.12, 0.92), Color(0.42, 1.0, 0.74) if State.tut_enabled else Color(0.68, 0.42, 0.44), 1.3)
	root_ctrl.draw_string(font, Vector2(tb.position.x, tb.position.y + 19), "上部表示: ON" if State.tut_enabled else "上部表示: OFF", HORIZONTAL_ALIGNMENT_CENTER, tb.size.x, 10, Color.WHITE)
	_add_hit(tb, "tut_toggle")

	# 6トピック選択ボタン（2行×3列）
	var y := tr.end.y + 12.0
	var bw := (mw - 28.0 - 12.0) / 3.0
	for i in range(State.GUIDE_TOPICS.size()):
		var gx := r.position.x + 14.0 + float(i % 3) * (bw + 6.0)
		var gy := y + float(i / 3) * 36.0
		var gr := Rect2(gx, gy, bw, 30.0)
		var sel := (i == guide_tab)
		_panel(gr, Color(0.12, 0.26, 0.36, 0.96) if sel else Color(0.06, 0.10, 0.17, 0.90), Color(0.42, 0.96, 1.0) if sel else Color(0.28, 0.38, 0.52), 1.3)
		root_ctrl.draw_string(font, Vector2(gr.position.x + 6, gr.position.y + 20), String(State.GUIDE_TOPICS[i]["title"]), HORIZONTAL_ALIGNMENT_LEFT, int(bw - 12), 10 if portrait else 11, Color.WHITE if sel else Color(0.74, 0.84, 0.94))
		_add_hit(gr, "guide_tab", i)

	# 選択トピックの詳細本文
	var body_y := y + 80.0
	var br := Rect2(r.position.x + 14, body_y, mw - 28, r.end.y - body_y - 12.0)
	_panel(br, Color(0.05, 0.08, 0.15, 0.95), Color(0.32, 0.56, 0.74), 1.3)
	var topic: Dictionary = State.GUIDE_TOPICS[clampi(guide_tab, 0, State.GUIDE_TOPICS.size() - 1)]
	root_ctrl.draw_string(font, Vector2(br.position.x + 12, br.position.y + 24), String(topic["title"]), HORIZONTAL_ALIGNMENT_LEFT, int(br.size.x - 24), 13, Color(0.48, 0.96, 1.0))
	var ly := br.position.y + 52.0
	for ln in topic["lines"]:
		root_ctrl.draw_string(font, Vector2(br.position.x + 12, ly), String(ln), HORIZONTAL_ALIGNMENT_LEFT, int(br.size.x - 24), 10 if portrait else 12, Color(0.92, 0.96, 1.0))
		ly += 28.0 if not portrait else 24.0

# 11. カーゴデポ（4方向出力フィルタ付き倉庫）モーダル
func _draw_depot_modal(vp: Vector2, font: Font) -> void:
	if not grid: return
	var snap: Dictionary = grid.get_depot_snap(depot_uid)
	if snap.is_empty(): modal = Modal.NONE; return
	var mw := minf(vp.x - 20.0, 520.0); var mh := 376.0
	var r := Rect2((vp.x - mw) * 0.5, (vp.y - mh) * 0.5, mw, mh)
	_panel(r, Color(0.04, 0.06, 0.12, 0.97), Color(0.38, 0.88, 1.0), 2.0)
	root_ctrl.draw_string(font, Vector2(r.position.x + 14, r.position.y + 24), "カーゴデポ（倉庫） // 在庫 %d / %d" % [int(snap["total"]), int(snap["cap"])], HORIZONTAL_ALIGNMENT_LEFT, int(mw - 86), 13, Color(0.48, 0.96, 1.0))
	var cr := Rect2(r.end.x - 66, r.position.y + 7, 56, 24)
	_panel(cr, Color(0.28, 0.08, 0.10, 0.94), Color(1.0, 0.42, 0.42), 1.4)
	root_ctrl.draw_string(font, Vector2(cr.position.x, cr.position.y + 16), "閉じる", HORIZONTAL_ALIGNMENT_CENTER, cr.size.x, 10, Color.WHITE)
	_add_hit(cr, "close")

	var dr := Rect2(r.position.x + 14, r.position.y + 40, (mw - 34) * 0.56, 30)
	_panel(dr, Color(0.08, 0.22, 0.30, 0.95), Color(0.42, 0.94, 1.0), 1.4)
	root_ctrl.draw_string(font, Vector2(dr.position.x, dr.position.y + 20), "鉱石をすべて預ける", HORIZONTAL_ALIGNMENT_CENTER, dr.size.x, 11, Color.WHITE)
	_add_hit(dr, "depot_all")

	var cvr := Rect2(dr.end.x + 6, r.position.y + 40, (mw - 34) * 0.44, 30)
	_panel(cvr, Color(0.22, 0.16, 0.06, 0.95), Color(1.0, 0.80, 0.30), 1.4)
	root_ctrl.draw_string(font, Vector2(cvr.position.x, cvr.position.y + 20), "ここから搬送接続", HORIZONTAL_ALIGNMENT_CENTER, cvr.size.x, 11, Color.WHITE)
	_add_hit(cvr, "depot_conv")

	var y := r.position.y + 84.0
	var out_links: Array = snap.get("out_links", [])
	root_ctrl.draw_string(font, Vector2(r.position.x + 14, y + 10), "接続中の搬送ライン出力フィルタ（タップで出力資源を切替）：", HORIZONTAL_ALIGNMENT_LEFT, int(mw - 28), 10, Color(1.0, 0.84, 0.36))
	y += 18.0
	if out_links.is_empty():
		var er := Rect2(r.position.x + 14, y, mw - 28, 36)
		_panel(er, Color(0.06, 0.09, 0.15, 0.9), Color(0.28, 0.38, 0.50), 1.2)
		root_ctrl.draw_string(font, Vector2(er.position.x, er.position.y + 22), "出力先の搬送ラインなし（「ここから搬送接続」で溶鉱炉等へ接続）", HORIZONTAL_ALIGNMENT_CENTER, er.size.x, 10, Color(0.68, 0.78, 0.90))
	else:
		var show_n := mini(out_links.size(), 4)
		var fw := (mw - 28.0) / float(show_n)
		for i in range(show_n):
			var lk: Dictionary = out_links[i]
			var fr := Rect2(r.position.x + 14 + float(i) * fw, y, fw - 6, 38)
			var raw_f := String(lk.get("filter", "auto"))
			var fv := "停止" if raw_f == "none" else ("自動" if raw_f == "auto" else State.res_name(raw_f))
			_panel(fr, Color(0.10, 0.22, 0.32, 0.95) if raw_f != "none" else Color(0.06, 0.09, 0.15, 0.9), Color(1.0, 0.80, 0.30) if raw_f != "none" else Color(0.28, 0.38, 0.50), 1.3)
			root_ctrl.draw_string(font, Vector2(fr.position.x, fr.position.y + 15), "→" + String(lk["to_name"]), HORIZONTAL_ALIGNMENT_CENTER, fr.size.x, 9, Color(0.76, 0.88, 1.0))
			root_ctrl.draw_string(font, Vector2(fr.position.x, fr.position.y + 31), fv, HORIZONTAL_ALIGNMENT_CENTER, fr.size.x, 11, Color.WHITE)
			_add_hit(fr, "depot_link_flt", int(lk["idx"]))

	y += 48.0
	var inv: Dictionary = snap["inv"]
	for it in ["fe", "cu", "si", "ti", "plate_fe", "wire_cu", "wafer_si", "circuit"]:
		var cnt := int(inv.get(it, 0))
		root_ctrl.draw_string(font, Vector2(r.position.x + 18, y + 16), "%s ： %d個" % [State.res_name(String(it)), cnt], HORIZONTAL_ALIGNMENT_LEFT, 180, 11, Color.WHITE if cnt > 0 else Color(0.45, 0.52, 0.62))
		var tr := Rect2(r.end.x - 102, y, 86, 21)
		_panel(tr, Color(0.08, 0.22, 0.20, 0.92) if cnt > 0 else Color(0.06, 0.08, 0.12, 0.7), Color(0.36, 0.92, 0.72) if cnt > 0 else Color(0.24, 0.30, 0.38), 1.1)
		root_ctrl.draw_string(font, Vector2(tr.position.x, tr.position.y + 15), "5個取出す", HORIZONTAL_ALIGNMENT_CENTER, tr.size.x, 10, Color.WHITE if cnt > 0 else Color(0.45, 0.50, 0.58))
		if cnt > 0: _add_hit(tr, "depot_take", it)
		y += 24.0

# 11b. 全施設対応：施設の中身・稼働詳細インスペクタ（通常タップで開く！）
func _draw_building_modal(vp: Vector2, font: Font) -> void:
	if not grid: return
	var snap: Dictionary = grid.get_building_snap(inspect_uid)
	if snap.is_empty(): modal = Modal.NONE; return
	var bid := String(snap["id"])
	var mw := minf(vp.x - 20.0, 480.0)
	var mh := 346.0
	var r := Rect2((vp.x - mw) * 0.5, (vp.y - mh) * 0.5, mw, mh)
	_panel(r, Color(0.04, 0.06, 0.12, 0.97), Color(0.38, 0.90, 1.0), 2.0)

	var itex := ArtReg.get_t(String(snap["tex"]))
	if itex:
		root_ctrl.draw_texture_rect(itex, Rect2(r.position.x + 14, r.position.y + 10, 32, 32), false)
	root_ctrl.draw_string(font, Vector2(r.position.x + 54, r.position.y + 30), "%s // 施設詳細" % String(snap["name"]), HORIZONTAL_ALIGNMENT_LEFT, int(mw - 130), 13, Color(0.48, 0.96, 1.0))

	var cr := Rect2(r.end.x - 66, r.position.y + 8, 56, 24)
	_panel(cr, Color(0.28, 0.08, 0.10, 0.94), Color(1.0, 0.42, 0.42), 1.4)
	root_ctrl.draw_string(font, Vector2(cr.position.x, cr.position.y + 16), "閉じる", HORIZONTAL_ALIGNMENT_CENTER, cr.size.x, 10, Color.WHITE)
	_add_hit(cr, "close")

	var y := r.position.y + 52.0
	root_ctrl.draw_string(font, Vector2(r.position.x + 14, y + 12), String(snap["desc"]), HORIZONTAL_ALIGNMENT_LEFT, int(mw - 28), 10, Color(0.80, 0.90, 0.98))
	y += 26.0

	# 稼働・電力ステータス枠
	var st_r := Rect2(r.position.x + 14, y, mw - 28, 56)
	_panel(st_r, Color(0.06, 0.10, 0.17, 0.95), Color(0.26, 0.42, 0.58), 1.2)
	var pwr := float(snap["pwr_ratio"])
	var p_txt := ""
	var p_col := Color(0.45, 0.98, 0.72)
	if bool(snap["is_power"]):
		var links: Array = snap["links"]
		var lnk_s := ("接続先: " + "・".join(links)) if not links.is_empty() else "未配線（【配線】でテスラリレー等と接続）"
		if bid == "battery":
			var pct := int(round(float(snap["battery_kj"]) / maxf(1.0, float(snap["battery_cap"])) * 100.0))
			p_txt = "蓄電量: %d / %d kJ (%d%%)" % [int(snap["battery_kj"]), int(snap["battery_cap"]), pct]
		elif float(snap["gen"]) > 0.1:
			p_txt = "現在発電量: %.0fW（%s）" % [float(snap["gen"]), "通電中" if bool(snap["wired"]) else "未配線のため0W"]
		else:
			p_txt = "電力供給ドーム: %s" % ("稼働中 (配電中)" if pwr > 0.1 else "未通電（発電機と配線してください）")
			if pwr <= 0.1: p_col = Color(1.0, 0.68, 0.36)
		root_ctrl.draw_string(font, Vector2(st_r.position.x + 10, st_r.position.y + 21), p_txt, HORIZONTAL_ALIGNMENT_LEFT, int(st_r.size.x - 20), 11, p_col)
		root_ctrl.draw_string(font, Vector2(st_r.position.x + 10, st_r.position.y + 43), lnk_s, HORIZONTAL_ALIGNMENT_LEFT, int(st_r.size.x - 20), 10, Color(0.74, 0.88, 1.0))
	else:
		var use_w := float(snap["use"])
		if use_w <= 0.01 or pwr > 0.1:
			p_txt = "状態: 稼働中（消費電力 %.0fW）%s" % [use_w, "  ※出力満杯停止中" if bool(snap["blocked"]) else ""]
		else:
			p_txt = "状態: 電力不足（テスラリレーの青い範囲内に設置してください）"
			p_col = Color(1.0, 0.46, 0.40)
		root_ctrl.draw_string(font, Vector2(st_r.position.x + 10, st_r.position.y + 21), p_txt, HORIZONTAL_ALIGNMENT_LEFT, int(st_r.size.x - 20), 10, p_col)
		var sub_info := ""
		if bid == "drill":
			sub_info = "採掘中の鉱脈: %s" % State.res_name(String(snap["ore_target"]))
		elif bid == "belt" or bid == "lift":
			sub_info = "搬送方向: %s" % ("右方向 / 上方向" if int(snap["dir"]) > 0 else "左方向 / 下方向")
		elif bid == "assembler":
			sub_info = "現在の製造レシピ: %s" % State.res_name(String(snap["recipe"]))
		else:
			sub_info = "電力効率: %d%%" % int(round(pwr * 100.0))
		root_ctrl.draw_string(font, Vector2(st_r.position.x + 10, st_r.position.y + 43), sub_info, HORIZONTAL_ALIGNMENT_LEFT, int(st_r.size.x - 20), 10, Color(0.76, 0.90, 1.0))

	y += 66.0
	# 中身（入力バッファ＆出力バッファ）表示
	var buf_r := Rect2(r.position.x + 14, y, mw - 28, 92)
	_panel(buf_r, Color(0.05, 0.08, 0.14, 0.95), Color(0.28, 0.44, 0.62), 1.2)
	var in_d: Dictionary = snap["in_buf"]
	var out_d: Dictionary = snap["out_buf"]
	var in_parts: Array[String] = []
	for k in in_d.keys(): in_parts.append("%s ×%d" % [State.res_name(String(k)), int(in_d[k])])
	var out_parts: Array[String] = []
	for k in out_d.keys(): out_parts.append("%s ×%d" % [State.res_name(String(k)), int(out_d[k])])
	root_ctrl.draw_string(font, Vector2(buf_r.position.x + 10, buf_r.position.y + 22), "内部の材料（入力）: " + ("  ".join(in_parts) if not in_parts.is_empty() else "空"), HORIZONTAL_ALIGNMENT_LEFT, int(buf_r.size.x - 20), 11, Color(0.88, 0.94, 1.0))
	root_ctrl.draw_string(font, Vector2(buf_r.position.x + 10, buf_r.position.y + 52), "内部の完成品（出力）: " + ("  ".join(out_parts) if not out_parts.is_empty() else "空"), HORIZONTAL_ALIGNMENT_LEFT, int(buf_r.size.x - 20), 11, Color(0.46, 0.98, 0.78) if not out_parts.is_empty() else Color(0.60, 0.68, 0.78))
	var conv_out: Array = snap.get("conv_out", [])
	var conv_hint := ("搬送ライン接続先: " + "  ".join(conv_out)) if not conv_out.is_empty() else "※【搬送】で他施設と自由結束すると自動で入出力されます。"
	root_ctrl.draw_string(font, Vector2(buf_r.position.x + 10, buf_r.position.y + 78), conv_hint, HORIZONTAL_ALIGNMENT_LEFT, int(buf_r.size.x - 20), 9, Color(1.0, 0.84, 0.42) if not conv_out.is_empty() else Color(0.64, 0.74, 0.86))

	# 操作アクションボタン列
	y += 102.0
	var acts: Array[Dictionary] = []
	if not out_d.is_empty():
		acts.append({"lbl": "完成品を回収", "a": "bld_collect", "c": Color(0.38, 0.98, 0.74)})
	if bid in ["smelter", "assembler", "gantry_printer"]:
		acts.append({"lbl": "材料を手動投入", "a": "bld_feed", "c": Color(0.42, 0.90, 1.0)})
	if bid == "assembler":
		acts.append({"lbl": "レシピ切替", "a": "bld_recipe", "c": Color(1.0, 0.84, 0.36)})
	if bool(snap.get("is_logi", false)):
		acts.append({"lbl": "搬送ライン接続", "a": "bld_conv", "c": Color(1.0, 0.80, 0.30)})
	if bool(snap["is_power"]):
		acts.append({"lbl": "電線をつなぐ", "a": "bld_wire", "c": Color(0.42, 0.96, 1.0)})

	if not acts.is_empty():
		var aw := (mw - 28.0 - float(acts.size() - 1) * 6.0) / float(acts.size())
		for ai in range(acts.size()):
			var ar := Rect2(r.position.x + 14 + float(ai) * (aw + 6.0), y, aw, 32)
			_panel(ar, Color(0.08, 0.22, 0.30, 0.95), Color(acts[ai]["c"]), 1.4)
			root_ctrl.draw_string(font, Vector2(ar.position.x, ar.position.y + 21), String(acts[ai]["lbl"]), HORIZONTAL_ALIGNMENT_CENTER, aw, 11, Color.WHITE)
			_add_hit(ar, String(acts[ai]["a"]))

	# 下段：この施設を削除・回収ボタン
	var del_r := Rect2(r.position.x + 14, r.end.y - 42, mw - 28, 30)
	_panel(del_r, Color(0.24, 0.08, 0.10, 0.92), Color(1.0, 0.44, 0.42), 1.3)
	root_ctrl.draw_string(font, Vector2(del_r.position.x, del_r.position.y + 19), "この施設を削除・回収して所持リストへ戻す", HORIZONTAL_ALIGNMENT_CENTER, del_r.size.x, 10, Color(1.0, 0.86, 0.86))
	_add_hit(del_r, "bld_salvage")

# 12. タッチ仮想コントロール（左：移動スティック / 右：方向指定採掘スティック！）
func _draw_touch_controls(font: Font) -> void:
	# 左下: 移動ジョイスティック
	root_ctrl.draw_circle(joy_center, joy_r, Color(0.04, 0.08, 0.14, 0.52))
	root_ctrl.draw_arc(joy_center, joy_r, 0.0, TAU, 32, Color(0.36, 0.80, 1.0, 0.74), 2.0)
	var pk := joy_center + joy_vec * (joy_r * 0.62)
	root_ctrl.draw_circle(pk, 18.0, Color(0.10, 0.24, 0.38, 0.88))
	root_ctrl.draw_arc(pk, 18.0, 0.0, TAU, 24, Color(0.45, 0.96, 1.0), 2.0)

	# 右下: ツインスティック採掘パッド（ドラッグした方向へ正確に採掘ビーム照射！）
	if State.selected_tool == "mine":
		root_ctrl.draw_circle(act_center, mine_r, Color(0.04, 0.13, 0.11, 0.56))
		root_ctrl.draw_arc(act_center, mine_r, 0.0, TAU, 32, Color(0.35, 0.96, 0.68, 0.82), 2.2)
		# 十字ガイド目盛
		for a_deg in [0.0, 90.0, 180.0, 270.0]:
			var dv := Vector2.from_angle(deg_to_rad(a_deg))
			root_ctrl.draw_line(act_center + dv * (mine_r - 9.0), act_center + dv * (mine_r - 2.0), Color(0.38, 0.96, 0.76, 0.45), 1.6)
		var mpk := act_center + mine_vec * (mine_r * 0.64)
		if mine_vec.length() > 0.12:
			var md := mine_vec.normalized()
			root_ctrl.draw_line(act_center, act_center + md * (mine_r + 12.0), Color(0.42, 1.0, 0.86, 0.85), 2.6)
		root_ctrl.draw_circle(mpk, 19.0, Color(0.08, 0.28, 0.22, 0.92))
		root_ctrl.draw_arc(mpk, 19.0, 0.0, TAU, 24, Color(0.42, 1.0, 0.80), 2.2)
		root_ctrl.draw_string(font, mpk + Vector2(-20, 4), "採掘", HORIZONTAL_ALIGNMENT_CENTER, 40, 10, Color.WHITE)
	else:
		root_ctrl.draw_circle(act_center, 36.0, Color(0.06, 0.16, 0.14, 0.82))
		root_ctrl.draw_arc(act_center, 36.0, 0.0, TAU, 24, Color(0.35, 0.96, 0.68), 2.2)
		var act_lbl := "接続" if State.selected_tool == "wire" else ("搬送" if State.selected_tool == "conveyor" else ("削除" if State.selected_tool == "salvage" else "設置"))
		root_ctrl.draw_string(font, act_center + Vector2(-30, 5), act_lbl, HORIZONTAL_ALIGNMENT_CENTER, 60, 12, Color.WHITE)

	root_ctrl.draw_circle(brk_center, 25.0, Color(0.18, 0.07, 0.09, 0.80))
	root_ctrl.draw_arc(brk_center, 25.0, 0.0, TAU, 24, Color(1.0, 0.44, 0.42), 2.0)
	root_ctrl.draw_string(font, brk_center + Vector2(-24, 4), "停止", HORIZONTAL_ALIGNMENT_CENTER, 48, 10, Color.WHITE)
