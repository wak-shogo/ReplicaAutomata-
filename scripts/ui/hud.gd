extends CanvasLayer
class_name GameHUD

# ==============================================================================
# STAR REPLICA: AUTOMA - AAA MINIMALIST HUD, FACTORIO TECH TREE & DEPOT FILTER UI
#   - Responsive DPR-aware scaling (Desktop 1280x720 + Mobile Portrait 412x915)
#   - 1 Analog Left Stick + 4 ABXY triggers reaching every feature cleanly
#   - Full-Screen Factorio-Style TECH_TREE DAG with interactive info cards
#   - Cargo Depot Inventory & 4-Way Output Filter Modal (DEPOT_UI)
# ==============================================================================

signal orbit_cam_toggled
signal save_requested
signal reset_requested
signal brake_requested

enum MenuState { FIELD, BUILD_TREE, CMD_TREE, TECH_TREE, DEPOT_UI }

const BUILD_BRANCHES: Array[String] = ["MINE", "FACTORY", "POWER", "MEGA"]
const CMD_TABS: Array[String] = ["PRINTER", "SWARM", "SYSTEM"]

var menu_state: int = MenuState.FIELD
var active_branch_idx: int = 0
var active_cmd_tab_idx: int = 0
var cursor_idx: int = 0
var selected_tech_id: String = "tesla_grid"

var player_ref: Node2D
var world_ref: PlanetWorld
var swarm_ref: SwarmSimulation
var _factory_signal_bound: bool = false

var hud_canvas: Control
var icons: Dictionary = {}

# Virtual Joystick & ABXY interaction state
var joy_drag_idx: int = -1
var joy_center: Vector2 = Vector2(110, 500)
var joy_radius: float = 54.0
var joy_vec: Vector2 = Vector2.ZERO

var btn_rects: Dictionary = {}
var field_hitboxes: Array[Dictionary] = []
var tree_hitboxes: Array[Dictionary] = []
var pressed_flash: Dictionary = {}
var held_btn: String = ""
var held_btn_idx: int = -1
var last_pointer_press_ms: int = 0

var orbit_cam_active: bool = false
var status_banner: String = ""
var status_banner_col: Color = Color(0.35, 0.95, 1.0)
var status_banner_t: float = 0.0
var stick_nav_cd: float = 0.0
var anim_time: float = 0.0
var telemetry_t: float = 0.0

# AAA Sci-Fi Color Palette
const C_BG = Color(0.035, 0.055, 0.105, 0.90)
const C_BG_DARK = Color(0.02, 0.032, 0.065, 0.95)
const C_STEEL = Color(0.20, 0.42, 0.65, 0.92)
const C_CYAN = Color(0.22, 0.92, 1.0, 1.0)
const C_EMERALD = Color(0.28, 0.96, 0.68, 1.0)
const C_AMBER = Color(1.0, 0.72, 0.25, 1.0)
const C_CRIMSON = Color(1.0, 0.28, 0.34, 1.0)
const C_TEXT = Color(0.94, 0.97, 1.0, 1.0)
const C_MUTED = Color(0.62, 0.76, 0.90, 1.0)

func _ready() -> void:
	_load_icons()
	hud_canvas = Control.new()
	hud_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_canvas.draw.connect(_on_hud_draw)
	add_child(hud_canvas)

	GameState.log_event.connect(_on_log_event)
	get_viewport().size_changed.connect(_on_viewport_resized)
	_on_viewport_resized()

func setup(p_player: Node2D, p_world: PlanetWorld = null, p_swarm: SwarmSimulation = null) -> void:
	player_ref = p_player
	world_ref = p_world
	swarm_ref = p_swarm
	_try_bind_factory_signal()

func _try_bind_factory_signal() -> void:
	if _factory_signal_bound or not player_ref or not ("factory" in player_ref) or not player_ref.factory:
		return
	var fac = player_ref.factory
	if fac.has_signal("depot_opened") and not fac.depot_opened.is_connected(_on_depot_opened):
		fac.depot_opened.connect(_on_depot_opened)
	_factory_signal_bound = true

func _on_depot_opened(uid: int) -> void:
	if player_ref and ("factory" in player_ref) and player_ref.factory:
		player_ref.factory.selected_depot_uid = uid
	menu_state = MenuState.DEPOT_UI
	cursor_idx = 0
	if hud_canvas:
		hud_canvas.queue_redraw()

func _load_icons() -> void:
	var paths = {
		"fe": "res://assets/ui/fe.png",
		"cu": "res://assets/ui/cu.png",
		"si": "res://assets/ui/si.png",
		"ti": "res://assets/ui/ti.png",
		"ice": "res://assets/ui/si.png",
		"plate_fe": "res://assets/ui/item_plate_fe.png",
		"wire_cu": "res://assets/ui/item_wire_cu.png",
		"wafer_si": "res://assets/ui/item_silicon_wafer.png",
		"circuit": "res://assets/ui/item_circuit.png",
		"alloy": "res://assets/ui/item_alloy.png",
		"probe_stock": "res://assets/ui/item_drone_unit.png",
		"pick": "res://assets/ui/tool_pick.png",
		"demolish": "res://assets/ui/tool_demolish.png",
	}
	for k in paths.keys():
		if ResourceLoader.exists(paths[k]):
			icons[k] = load(paths[k])
	for bid in GameState.BUILDINGS.keys():
		var ip = GameState.BUILDINGS[bid].get("icon", "")
		if ip != "" and ResourceLoader.exists(ip):
			icons[bid] = load(ip)

func _on_log_event(msg: String, level: String) -> void:
	status_banner = msg
	status_banner_t = 3.2
	match level:
		"good": status_banner_col = C_EMERALD
		"warn": status_banner_col = C_AMBER
		"error": status_banner_col = C_CRIMSON
		_: status_banner_col = C_CYAN

func _on_viewport_resized() -> void:
	var win = get_tree().root
	var win_sz = Vector2(DisplayServer.window_get_size())
	if win_sz.x < 10.0:
		win_sz = get_viewport().get_visible_rect().size
	var min_dim = minf(win_sz.x, win_sz.y)
	var scale_f = clampf(min_dim / 520.0, 0.85, 2.50)
	if absf(win.content_scale_factor - scale_f) > 0.04:
		win.content_scale_factor = scale_f

	var vp = get_viewport().get_visible_rect().size
	joy_radius = clampf(minf(vp.x, vp.y) * 0.102, 42.0, 56.0)
	var d = clampf(joy_radius * 0.90, 40.0, 52.0)
	var r = clampf(d * 0.45, 19.0, 25.0)
	var bottom_margin = 26.0
	joy_center = Vector2(joy_radius + 24.0, vp.y - joy_radius - bottom_margin - 6.0)

	var pad_center = Vector2(vp.x - d - r - 22.0, vp.y - d - r - bottom_margin)
	btn_rects = {
		"Y": {"pos": pad_center + Vector2(0, -d), "r": r},
		"X": {"pos": pad_center + Vector2(-d, 0), "r": r},
		"B": {"pos": pad_center + Vector2(d, 0), "r": r},
		"A": {"pos": pad_center + Vector2(0, d), "r": r},
	}
	if hud_canvas:
		hud_canvas.queue_redraw()

func refresh_all() -> void:
	if hud_canvas:
		hud_canvas.queue_redraw()

func toggle_tech_modal() -> void:
	if menu_state != MenuState.TECH_TREE:
		menu_state = MenuState.TECH_TREE
		cursor_idx = 0
		AudioSynth.play_synth("select")
	else:
		menu_state = MenuState.FIELD
		AudioSynth.play_synth("click")

func _process(delta: float) -> void:
	_try_bind_factory_signal()
	anim_time += delta
	if status_banner_t > 0.0:
		status_banner_t -= delta
	if stick_nav_cd > 0.0:
		stick_nav_cd -= delta
	for k in pressed_flash.keys():
		pressed_flash[k] = maxf(0.0, float(pressed_flash[k]) - delta)

	if menu_state != MenuState.FIELD:
		if player_ref and player_ref.has_method("set_virtual_input"):
			player_ref.set_virtual_input(Vector2.ZERO, false, false)
		_poll_menu_stick()
	else:
		if held_btn == "A":
			pressed_flash["A"] = 0.08
		elif held_btn == "B":
			pressed_flash["B"] = 0.08
		if player_ref and player_ref.has_method("set_virtual_input"):
			var brake_held = (held_btn == "B" and GameState.selected_tool == "pick")
			player_ref.set_virtual_input(joy_vec, (held_btn == "A") or (pressed_flash.get("A", 0.0) > 0.0), brake_held)

	if hud_canvas:
		hud_canvas.queue_redraw()

	if OS.has_feature("web") and player_ref:
		telemetry_t += delta
		if telemetry_t >= 0.25:
			telemetry_t = 0.0
			var near_ast := {}
			if world_ref and world_ref.asteroids.size() > 0:
				var best_d := 1e9
				for a in world_ref.asteroids:
					var d := float(a["pos"].distance_to(player_ref.position))
					if d < best_d:
						best_d = d
						near_ast = {"x": int(a["pos"].x), "y": int(a["pos"].y), "ore": a["ore"], "d": int(d)}
			var fac = player_ref.factory if ("factory" in player_ref) else null
			var gs: Dictionary = fac.grid_summary if fac else {}
			var payload := {
				"fe": GameState.fe, "cu": GameState.cu, "si": GameState.si, "ti": GameState.ti, "ice": GameState.ice,
				"plate_fe": GameState.plate_fe, "wire_cu": GameState.wire_cu, "wafer_si": GameState.wafer_si,
				"circuit": GameState.circuit, "alloy": GameState.alloy, "sci_pack": GameState.sci_pack,
				"probe_stock": GameState.probe_stock,
				"eng": GameState.engine_tier, "spd": int(GameState.get_flight_speed()),
				"hp": int(GameState.player_hp), "fuel": int(GameState.player_fuel), "bat": int(GameState.player_battery),
				"pwr_prod": int(GameState.power_gen), "pwr_use": int(GameState.power_use),
				"pwr_stored": int(GameState.power_stored),
				"wires": int(gs.get("wires", 0)), "teslas_on": int(gs.get("teslas_on", 0)),
				"techs": GameState.unlocked_techs.keys(),
				"vel": int(player_ref.velocity.length()),
				"vx": int(player_ref.velocity.x), "vy": int(player_ref.velocity.y),
				"grav": snappedf(player_ref.current_g_norm, 0.01),
				"on_ground": player_ref.is_anchored_surface,
				"rot": snappedf(player_ref.rotation, 0.02),
				"drones": GameState.drones, "fleet": GameState.fleet_count, "launches": GameState.total_launches,
				"doc": GameState.current_doctrine, "tool": GameState.selected_tool, "menu": menu_state,
				"px": int(player_ref.position.x), "py": int(player_ref.position.y),
				"alt": int(maxf(0.0, player_ref.position.length() - PlanetWorld.R_SURFACE)),
				"r": int(player_ref.position.length()),
				"boss_hp": int(GameState.boss_hp), "boss_dead": GameState.boss_defeated,
				"won": GameState.game_won,
				"mega": GameState.megastructures,
				"orbit_cam": orbit_cam_active,
				"bldg": fac.buildings.size() if fac else 0,
				"belts_items": fac.belt_items.size() if fac else 0,
				"near_ast": near_ast,
			}
			JavaScriptBridge.eval("window.__hudTelemetry = %s;" % JSON.stringify(payload))

func _poll_menu_stick() -> void:
	var j = joy_vec + Vector2(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
	if j.length() < 0.25:
		stick_nav_cd = 0.0
		return
	if stick_nav_cd > 0.0:
		return
	if menu_state == MenuState.TECH_TREE:
		var idx = GameState.TECH_ORDER.find(selected_tech_id)
		if idx < 0: idx = 0
		if absf(j.x) > 0.55 and absf(j.x) >= absf(j.y):
			idx = clampi(idx + (1 if j.x > 0.0 else -1), 0, GameState.TECH_ORDER.size() - 1)
			selected_tech_id = GameState.TECH_ORDER[idx]
			stick_nav_cd = 0.34
			AudioSynth.play_synth("click")
		elif absf(j.y) > 0.55:
			idx = clampi(idx + (2 if j.y > 0.0 else -2), 0, GameState.TECH_ORDER.size() - 1)
			selected_tech_id = GameState.TECH_ORDER[idx]
			stick_nav_cd = 0.34
			AudioSynth.play_synth("click")
		return

	if absf(j.x) > 0.55 and absf(j.x) >= absf(j.y):
		var tab_step = 1 if j.x > 0.0 else -1
		if menu_state == MenuState.BUILD_TREE:
			active_branch_idx = posmod(active_branch_idx + tab_step, BUILD_BRANCHES.size())
			cursor_idx = 0
			stick_nav_cd = 0.38
			AudioSynth.play_synth("click")
		elif menu_state == MenuState.CMD_TREE:
			active_cmd_tab_idx = posmod(active_cmd_tab_idx + tab_step, CMD_TABS.size())
			cursor_idx = 0
			stick_nav_cd = 0.38
			AudioSynth.play_synth("click")
	elif absf(j.y) > 0.45:
		var step = 1 if j.y > 0.45 else -1
		var items = _get_active_tree_nodes()
		if items.size() > 0:
			cursor_idx = posmod(cursor_idx + step, items.size())
			stick_nav_cd = 0.38
			AudioSynth.play_synth("click")

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			if _handle_pointer_press(event.position, event.index):
				get_viewport().set_input_as_handled()
		else:
			if event.index == joy_drag_idx:
				joy_drag_idx = -1
				joy_vec = Vector2.ZERO
				stick_nav_cd = 0.0
				get_viewport().set_input_as_handled()
			if event.index == held_btn_idx:
				held_btn = ""
				held_btn_idx = -1
	elif event is InputEventScreenDrag:
		if event.index == joy_drag_idx:
			_update_joy_from_pos(event.position)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _handle_pointer_press(event.position, 99):
				get_viewport().set_input_as_handled()
		else:
			if joy_drag_idx == 99:
				joy_drag_idx = -1
				joy_vec = Vector2.ZERO
				stick_nav_cd = 0.0
			if held_btn_idx == 99:
				held_btn = ""
				held_btn_idx = -1
	elif event is InputEventMouseMotion and joy_drag_idx == 99:
		_update_joy_from_pos(event.position)

	elif event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_A: _trigger_abxy("A"); get_viewport().set_input_as_handled()
			JOY_BUTTON_B: _trigger_abxy("B"); get_viewport().set_input_as_handled()
			JOY_BUTTON_X: _trigger_abxy("X"); get_viewport().set_input_as_handled()
			JOY_BUTTON_Y: _trigger_abxy("Y"); get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_T:
				toggle_tech_modal()
				get_viewport().set_input_as_handled()
			KEY_J, KEY_SPACE, KEY_ENTER:
				if menu_state != MenuState.FIELD or GameState.selected_tool != "pick":
					_trigger_abxy("A")
					get_viewport().set_input_as_handled()
			KEY_K, KEY_ESCAPE:
				_trigger_abxy("B")
				get_viewport().set_input_as_handled()
			KEY_L, KEY_E, KEY_B:
				_trigger_abxy("X")
				get_viewport().set_input_as_handled()
			KEY_I, KEY_F, KEY_TAB:
				_trigger_abxy("Y")
				get_viewport().set_input_as_handled()

func _handle_pointer_press(pos: Vector2, idx: int) -> bool:
	var now_ms = Time.get_ticks_msec()
	if now_ms - last_pointer_press_ms < 100:
		return false

	for k in ["A", "B", "X", "Y"]:
		var bd = btn_rects.get(k, null)
		if bd and pos.distance_to(bd["pos"]) <= float(bd["r"]) + 8.0:
			last_pointer_press_ms = now_ms
			held_btn = k
			held_btn_idx = idx
			_trigger_abxy(k)
			return true

	if pos.distance_to(joy_center) <= joy_radius * 1.45:
		joy_drag_idx = idx
		_update_joy_from_pos(pos)
		return true

	for fhb in field_hitboxes:
		if fhb["rect"].has_point(pos):
			last_pointer_press_ms = now_ms
			fhb["action"].call()
			return true

	if menu_state != MenuState.FIELD:
		for hb in tree_hitboxes:
			if hb["rect"].has_point(pos):
				last_pointer_press_ms = now_ms
				hb["action"].call()
				return true
		last_pointer_press_ms = now_ms
		menu_state = MenuState.FIELD
		return true

	return false

func _update_joy_from_pos(pos: Vector2) -> void:
	var delta = pos - joy_center
	var d = delta.length()
	if d > 4.0:
		joy_vec = delta / maxf(d, joy_radius)
		if joy_vec.length() > 1.0:
			joy_vec = joy_vec.normalized()
		if menu_state != MenuState.FIELD:
			_poll_menu_stick()
	else:
		joy_vec = Vector2.ZERO

func _trigger_abxy(btn: String) -> void:
	pressed_flash[btn] = 0.20

	if btn == "B":
		AudioSynth.play_synth("click")
		if menu_state != MenuState.FIELD:
			menu_state = MenuState.FIELD
		elif GameState.selected_tool != "pick":
			GameState.set_tool("pick")
		else:
			emit_signal("brake_requested")
		return

	if menu_state == MenuState.FIELD:
		match btn:
			"A":
				if player_ref and player_ref.has_method("trigger_primary_action"):
					player_ref.trigger_primary_action()
			"X":
				menu_state = MenuState.BUILD_TREE
				active_branch_idx = 0
				cursor_idx = 0
				AudioSynth.play_synth("select")
			"Y":
				menu_state = MenuState.CMD_TREE
				active_cmd_tab_idx = 0
				cursor_idx = 0
				AudioSynth.play_synth("select")
		return

	if menu_state == MenuState.TECH_TREE:
		if btn == "A":
			if GameState.try_research_tech(selected_tech_id):
				AudioSynth.play_synth("craft")
			else:
				AudioSynth.play_synth("error")
		return

	if menu_state == MenuState.DEPOT_UI:
		return

	var nodes = _get_active_tree_nodes()
	match btn:
		"A":
			if cursor_idx >= 0 and cursor_idx < nodes.size():
				nodes[cursor_idx]["action"].call()
		"Y":
			if nodes.size() >= 1: nodes[0]["action"].call()
		"X":
			if nodes.size() >= 2: nodes[1]["action"].call()

func _get_active_tree_nodes() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	match menu_state:
		MenuState.BUILD_TREE:
			var cur_branch = BUILD_BRANCHES[active_branch_idx]
			for bid in GameState.BUILDINGS.keys():
				var info = GameState.BUILDINGS[bid]
				if info["branch"] != cur_branch: continue
				var req_t: String = String(info.get("req_tech", "basic_mining"))
				var unlocked = GameState.is_building_unlocked(bid)
				var can_pay = GameState.can_afford(info["cost"])
				var cost_s: PackedStringArray = []
				for ck in info["cost"].keys(): cost_s.append("%s:%d" % [String(ck).to_upper(), int(info["cost"][ck])])
				var t_lbl: String = String(GameState.TECH_TREE.get(req_t, {}).get("name", req_t))
				var st = ("READY | " + " ".join(cost_s)) if (unlocked and can_pay) else ("LOCK [Tech: %s]" % t_lbl if not unlocked else GameState.get_missing_text(info["cost"]) + " | " + " ".join(cost_s))
				var target_bid: String = bid
				out.append({
					"label": info["name"],
					"sub": st,
					"col": C_EMERALD if (unlocked and can_pay) else (C_AMBER if unlocked else C_CRIMSON),
					"icon": icons.get(bid, null),
					"action": func():
						if not unlocked:
							selected_tech_id = req_t
							menu_state = MenuState.TECH_TREE
							AudioSynth.play_synth("select")
							return
						GameState.set_tool(target_bid)
						menu_state = MenuState.FIELD
						AudioSynth.play_synth("select")
				})
			if cur_branch == "POWER":
				out.append({
					"label": "Power Wire Link",
					"sub": "Tap Solar/Geo then tap Tesla Coil to energize",
					"col": C_CYAN,
					"icon": icons.get("tesla", null),
					"action": func():
						GameState.set_tool("wire")
						menu_state = MenuState.FIELD
						AudioSynth.play_synth("select")
				})
			if cur_branch == "MEGA":
				out.append({
					"label": "Salvage Tool",
					"sub": "Deconstruct facility & refund 50%",
					"col": C_CRIMSON,
					"icon": icons.get("demolish", null),
					"action": func():
						GameState.set_tool("demolish")
						menu_state = MenuState.FIELD
						AudioSynth.play_synth("select")
				})
		MenuState.CMD_TREE:
			if active_cmd_tab_idx == 0:
				var eng_info = GameState.get_next_engine_info()
				if not eng_info.is_empty():
					var next_t = GameState.engine_tier + 1
					var req_t = String(eng_info.get("req_tech", ""))
					var eng_ok = GameState.is_engine_unlocked(next_t)
					var ec: PackedStringArray = []
					for k in eng_info["cost"].keys(): ec.append("%d %s" % [int(eng_info["cost"][k]), String(k).to_upper()])
					var can_e = eng_ok and GameState.can_afford(eng_info["cost"])
					var sub_txt = ("TECH LOCKED: %s" % GameState.TECH_TREE.get(req_t, {}).get("name", req_t)) if not eng_ok else (eng_info["desc"] if can_e else GameState.get_missing_text(eng_info["cost"]) + " | " + eng_info["desc"])
					out.append({
						"label": "PRINT: %s (%s)" % [eng_info["name"].to_upper(), " ".join(ec)],
						"sub": sub_txt,
						"col": C_EMERALD if can_e else (C_AMBER if eng_ok else C_CRIMSON),
						"icon": icons.get("pick", null),
						"action": func():
							if not eng_ok and req_t != "":
								selected_tech_id = req_t
								menu_state = MenuState.TECH_TREE
								AudioSynth.play_synth("select")
								return
							if GameState.try_print_engine(): AudioSynth.play_synth("craft")
							else: AudioSynth.play_synth("error")
							menu_state = MenuState.FIELD
					})
				else:
					out.append({
						"label": "PROPULSION: WARP ASCENT Mk-III MAX",
						"sub": "Interplanetary escape drive active",
						"col": C_CYAN,
						"icon": icons.get("pick", null),
						"action": func(): menu_state = MenuState.FIELD
					})

				var dcost = GameState.get_drone_craft_cost()
				var dc: PackedStringArray = []
				for k in dcost.keys(): dc.append("%d %s" % [int(dcost[k]), String(k).to_upper()])
				out.append({
					"label": "CRAFT HELPER DRONE (%s)" % " ".join(dc),
					"sub": "+18%% Factory Speed (%d/%d Drones)" % [GameState.drones, GameState.max_drones],
					"col": C_EMERALD if GameState.can_afford(dcost) else C_AMBER,
					"icon": icons.get("probe_stock", null),
					"action": func():
						if GameState.try_craft_drone(): AudioSynth.play_synth("craft")
						else: AudioSynth.play_synth("error")
						menu_state = MenuState.FIELD
				})
				out.append({
					"label": "OPEN TECH TREE [%d/%d]" % [GameState.unlocked_techs.size(), GameState.TECH_ORDER.size()],
					"sub": "Research Tesla Grid, Belts, Metallurgy, Rocket & Swarm",
					"col": C_CYAN,
					"icon": icons.get("circuit", null),
					"action": func():
						menu_state = MenuState.TECH_TREE
						AudioSynth.play_synth("select")
				})
			elif active_cmd_tab_idx == 1:
				var docs = [
					[GameState.Doctrine.HARVEST, "SWARM: HARVEST", "Mine orbital asteroids passively"],
					[GameState.Doctrine.REPLICATE, "SWARM: REPLICATE", "Multiply Swarm fleet in orbit"],
					[GameState.Doctrine.DEFEND, "SWARM: DEFEND", "Guard Origin-Prime perimeter"],
					[GameState.Doctrine.ASSAULT, "SWARM: ASSAULT", "Raid Corrupted Core Hub"],
				]
				for d in docs:
					var did: int = d[0]
					out.append({"label": d[1], "sub": d[2], "col": C_CYAN if GameState.current_doctrine == did else C_MUTED, "icon": null, "action": func():
						GameState.set_doctrine(did)
						menu_state = MenuState.FIELD
						AudioSynth.play_synth("select")
					})
			else:
				out.append({"label": "ORBIT CAMERA", "sub": "Toggle Wide Spherical System Camera", "col": C_AMBER, "icon": null, "action": func():
					orbit_cam_active = not orbit_cam_active
					emit_signal("orbit_cam_toggled")
					menu_state = MenuState.FIELD
					AudioSynth.play_synth("select")
				})
				out.append({"label": "REDEPLOY CAPSULE", "sub": "Emergency self-destruct & respawn at North Pole", "col": C_CRIMSON, "icon": null, "action": func():
					if player_ref and player_ref.has_method("redeploy_capsule"):
						player_ref.redeploy_capsule()
					menu_state = MenuState.FIELD
				})
				out.append({"label": "SAVE COLONY", "sub": "Persist planet, factory & fleet", "col": C_EMERALD, "icon": null, "action": func(): emit_signal("save_requested"); menu_state = MenuState.FIELD})
				out.append({"label": "TOGGLE AUDIO", "sub": "Audio: %s" % ("MUTED" if AudioSynth.is_muted else "ACTIVE"), "col": C_CYAN, "icon": null, "action": func(): AudioSynth.toggle_mute(); menu_state = MenuState.FIELD})
				out.append({"label": "RESET COLONY", "sub": "Start fresh 1-Seed survival", "col": C_CRIMSON, "icon": null, "action": func(): emit_signal("reset_requested"); menu_state = MenuState.FIELD})
	return out

func _draw_chamfer_panel(rect: Rect2, fill: Color, border: Color, cut: float = 10.0, stroke: float = 1.6) -> void:
	if rect.size.x < 4.0 or rect.size.y < 4.0:
		return
	cut = clampf(cut, 1.0, minf(rect.size.x, rect.size.y) * 0.35)
	var x0 = rect.position.x
	var y0 = rect.position.y
	var x1 = x0 + rect.size.x
	var y1 = y0 + rect.size.y
	var pts = PackedVector2Array([
		Vector2(x0 + cut, y0), Vector2(x1 - cut, y0), Vector2(x1, y0 + cut),
		Vector2(x1, y1 - cut), Vector2(x1 - cut, y1), Vector2(x0 + cut, y1),
		Vector2(x0, y1 - cut), Vector2(x0, y0 + cut), Vector2(x0 + cut, y0),
	])
	hud_canvas.draw_colored_polygon(pts.slice(0, 8), fill)
	hud_canvas.draw_polyline(pts, border, stroke, true)

func _draw_octagon_btn(center: Vector2, r: float, fill: Color, border: Color, glow_col: Color, active: bool) -> void:
	var pts = PackedVector2Array()
	for i in range(9):
		var a = (float(i) * TAU / 8.0) + PI / 8.0
		pts.append(center + Vector2(cos(a), sin(a)) * r)
	if active:
		hud_canvas.draw_circle(center, r + 5.0, Color(glow_col.r, glow_col.g, glow_col.b, 0.25))
	hud_canvas.draw_colored_polygon(pts.slice(0, 8), fill)
	hud_canvas.draw_polyline(pts, glow_col if active else border, 2.4 if active else 1.6, true)

func _on_hud_draw() -> void:
	var vp = get_viewport().get_visible_rect().size
	var font = ThemeDB.fallback_font
	if not font:
		return

	field_hitboxes.clear()
	tree_hitboxes.clear()

	# 1. TOP-LEFT AAA CHAMFERED VITALS & RESOURCE PANEL
	var narrow = vp.x < 680.0
	var tl_w = minf(vp.x - 116.0, 424.0)
	var tl_h = 134.0 if narrow else 128.0
	var tl_rect = Rect2(12, 12, tl_w, tl_h)
	_draw_chamfer_panel(tl_rect, C_BG, C_STEEL, 12.0, 1.8)
	hud_canvas.draw_line(Vector2(28, 12), Vector2(tl_w * 0.58, 12), C_CYAN, 2.5)
	hud_canvas.draw_line(Vector2(tl_rect.end.x - 24, tl_rect.end.y), Vector2(tl_rect.end.x - 10, tl_rect.end.y), C_AMBER, 2.0)

	# Row 1: HP | FUEL | ION BATTERY
	var hp_r = clampf(GameState.player_hp / GameState.player_max_hp, 0.0, 1.0)
	var fu_r = clampf(GameState.player_fuel / GameState.player_max_fuel, 0.0, 1.0)
	var ba_r = clampf(GameState.player_battery / GameState.player_max_battery, 0.0, 1.0)
	var bar_w = clampf((tl_w - 50.0) / 3.0 - 38.0, 32.0, 68.0)

	hud_canvas.draw_string(font, Vector2(22, 33), "HP", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, C_EMERALD)
	hud_canvas.draw_rect(Rect2(46, 23, bar_w, 9), C_BG_DARK)
	hud_canvas.draw_rect(Rect2(46, 23, bar_w * hp_r, 9), C_EMERALD)

	var fx = 54.0 + bar_w
	hud_canvas.draw_string(font, Vector2(fx, 33), "FUEL", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, C_AMBER)
	hud_canvas.draw_rect(Rect2(fx + 38, 23, bar_w, 9), C_BG_DARK)
	hud_canvas.draw_rect(Rect2(fx + 38, 23, bar_w * fu_r, 9), C_AMBER)

	var bx = fx + 46.0 + bar_w
	hud_canvas.draw_string(font, Vector2(bx, 33), "ION", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, C_CYAN)
	hud_canvas.draw_rect(Rect2(bx + 30, 23, maxf(24.0, tl_rect.end.x - 12.0 - (bx + 30.0)), 9), C_BG_DARK)
	hud_canvas.draw_rect(Rect2(bx + 30, 23, maxf(24.0, tl_rect.end.x - 12.0 - (bx + 30.0)) * ba_r, 9), C_CYAN)

	# Row 2: 8 Key Materials cleanly visible (Fe, Cu, Si, Ti | Plate, Wire, Circuit, Alloy)
	var res_keys = ["fe", "cu", "si", "ti", "plate_fe", "wire_cu", "circuit", "alloy"]
	var rx = 20.0
	var step_x = (tl_w - 18.0) / float(res_keys.size())
	for rk in res_keys:
		var ic: Texture2D = icons.get(rk, null)
		if ic:
			hud_canvas.draw_texture_rect(ic, Rect2(rx, 43, 18, 18), false)
		hud_canvas.draw_string(font, Vector2(rx + 20, 58), str(GameState.get_res(rk)), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_TEXT)
		rx += step_x

	# Row 3: Drones / Fleet / Grid Power (Local Grids!)
	var fac = player_ref.factory if (player_ref and ("factory" in player_ref)) else null
	var gs: Dictionary = fac.grid_summary if fac else {}
	var pwr_col = C_EMERALD if GameState.power_gen >= GameState.power_use and GameState.power_gen > 0.0 else (C_AMBER if GameState.power_gen > 0.0 else C_CRIMSON)
	hud_canvas.draw_string(font, Vector2(22, 84), "PWR %d/%dW" % [int(GameState.power_gen), int(GameState.power_use)], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, pwr_col)
	hud_canvas.draw_string(font, Vector2(142, 84), "WIRE:%d" % int(gs.get("wires", 0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_CYAN)
	hud_canvas.draw_string(font, Vector2(218, 84), "FLEET:%d" % GameState.fleet_count, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_CYAN)
	hud_canvas.draw_string(font, Vector2(312, 84), "DRN:%d" % GameState.drones, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_AMBER)

	# Row 4: Vessel / Active Tool / Altitude Telemetry
	var eng_lbl = "CAPSULE" if GameState.engine_tier == 0 else ("MK-1 LANDER" if GameState.engine_tier == 1 else ("MK-2 APOLLO" if GameState.engine_tier == 2 else "MK-3 WARP"))
	var alt_m = int(player_ref.position.length() - PlanetWorld.R_SURFACE) if player_ref else 0
	var vel_live = int(player_ref.velocity.length()) if player_ref else 0
	var tname = "MINE/ACT" if GameState.selected_tool == "pick" else ("WIRE LINK" if GameState.selected_tool == "wire" else ("SALVAGE" if GameState.selected_tool == "demolish" else GameState.BUILDINGS.get(GameState.selected_tool, {}).get("name", "TOOL")))
	var alt_str = ("SPACE" if (player_ref and player_ref.position.length() > PlanetWorld.R_ATMOS_OUTER) else ("ALT %dm" % alt_m))
	hud_canvas.draw_string(font, Vector2(22, 110), "%s | %s | V:%d | %s" % [tname.to_upper(), eng_lbl, vel_live, alt_str], HORIZONTAL_ALIGNMENT_LEFT, int(tl_w - 28), 11, C_MUTED)

	# 2. TOP-RIGHT OPEN-WORLD RADAR MINIMAP + [TECH TREE] PILL
	var rad_r = 38.0 if narrow else 44.0
	var rad_c = Vector2(vp.x - rad_r - 16.0, rad_r + 14.0)
	hud_canvas.draw_circle(rad_c, rad_r + 2.0, C_BG_DARK)
	hud_canvas.draw_arc(rad_c, rad_r + 2.0, 0.0, TAU, 36, C_STEEL, 1.8)
	hud_canvas.draw_arc(rad_c, rad_r * 0.45, 0.0, TAU, 24, Color(0.18, 0.32, 0.48, 0.45), 1.0)
	hud_canvas.draw_circle(rad_c, 4.5, Color(0.32, 0.72, 0.95))
	var map_scale = rad_r / PlanetWorld.WORLD_LIMIT_R
	hud_canvas.draw_arc(rad_c, maxf(6.0, PlanetWorld.R_ATMOS_OUTER * map_scale), 0.0, TAU, 24, Color(0.22, 0.78, 1.0, 0.4), 1.0)
	if world_ref:
		for cbody in world_ref.celestials:
			hud_canvas.draw_circle(rad_c + cbody["pos"] * map_scale, 2.2, C_AMBER)
	if swarm_ref and not GameState.boss_defeated:
		hud_canvas.draw_circle(rad_c + swarm_ref.boss_pos * map_scale, 3.0, C_CRIMSON)
	if player_ref:
		hud_canvas.draw_circle(rad_c + player_ref.position * map_scale, 3.2, C_EMERALD)

	var tech_rect = Rect2(rad_c.x - 48.0, rad_c.y + rad_r + 8.0, 96.0, 24.0)
	var tech_open = (menu_state == MenuState.TECH_TREE)
	_draw_chamfer_panel(tech_rect, Color(0.08, 0.22, 0.36, 0.95) if tech_open else C_BG_DARK, C_CYAN if tech_open else C_AMBER, 6.0, 1.8)
	hud_canvas.draw_string(font, tech_rect.position + Vector2(10, 17), "TECH %d/%d [T]" % [GameState.unlocked_techs.size(), GameState.TECH_ORDER.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, C_TEXT)
	field_hitboxes.append({"rect": tech_rect, "action": func(): toggle_tech_modal()})

	# 3. STATUS BANNER / VICTORY BANNER
	if GameState.game_won:
		var vw = minf(vp.x - 40.0, 440.0)
		var vrect = Rect2((vp.x - vw) * 0.5, tl_rect.end.y + 8.0, vw, 34.0)
		_draw_chamfer_panel(vrect, Color(0.04, 0.14, 0.10, 0.96), C_EMERALD, 8.0, 2.0)
		hud_canvas.draw_string(font, vrect.position + Vector2(14, 22), "VICTORY: WARP GATE & CORE HUB LIBERATED!", HORIZONTAL_ALIGNMENT_LEFT, int(vw - 24), 13, C_EMERALD)
	elif status_banner_t > 0.0:
		var bw = minf(vp.x - 40.0, 440.0)
		var brect = Rect2((vp.x - bw) * 0.5, tl_rect.end.y + 8.0, bw, 30.0)
		_draw_chamfer_panel(brect, Color(0.03, 0.05, 0.09, 0.92), status_banner_col, 7.0, 1.5)
		hud_canvas.draw_string(font, brect.position + Vector2(14, 20), status_banner, HORIZONTAL_ALIGNMENT_LEFT, int(bw - 24), 12, status_banner_col)

	# 4. BOTTOM-LEFT ANALOG JOYSTICK
	hud_canvas.draw_circle(joy_center, joy_radius, Color(0.03, 0.06, 0.11, 0.72))
	hud_canvas.draw_arc(joy_center, joy_radius, 0.0, TAU, 32, C_CYAN if joy_drag_idx != -1 else C_STEEL, 2.0)
	hud_canvas.draw_arc(joy_center, joy_radius * 0.5, 0.0, TAU, 24, Color(0.22, 0.45, 0.65, 0.35), 1.0)
	var stick_pos = joy_center + joy_vec * (joy_radius * 0.65)
	_draw_octagon_btn(stick_pos, 18.0, Color(0.10, 0.25, 0.42, 0.95), C_CYAN, C_CYAN, joy_vec.length() > 0.1)

	# 5. BOTTOM-RIGHT AAA ABXY ACTION DIAMOND
	var labels = {
		"A": "WIRE" if GameState.selected_tool == "wire" else ("PLACE" if (GameState.selected_tool in GameState.BUILDINGS) else ("SALVAGE" if GameState.selected_tool == "demolish" else "MINE/USE")),
		"B": "CANCEL" if GameState.selected_tool != "pick" else "BRAKE",
		"X": "BUILD" if menu_state == MenuState.FIELD else "PICK 2",
		"Y": "PRINTER" if menu_state == MenuState.FIELD else "PICK 1",
	}
	if menu_state == MenuState.TECH_TREE:
		labels["A"] = "RESEARCH"
		labels["B"] = "CLOSE"
	elif menu_state != MenuState.FIELD:
		labels["A"] = "CONFIRM"
		labels["B"] = "CLOSE"
	var cols = {"A": C_EMERALD, "B": C_CRIMSON, "X": C_CYAN, "Y": C_AMBER}
	for k in ["Y", "X", "B", "A"]:
		var bd = btn_rects[k]
		var bp: Vector2 = bd["pos"]
		var br: float = bd["r"]
		var fl = pressed_flash.get(k, 0.0) > 0.0
		_draw_octagon_btn(bp, br, Color(0.05, 0.09, 0.16, 0.92), C_STEEL, cols[k], fl)
		var ksz = font.get_string_size(k, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
		hud_canvas.draw_string(font, Vector2(bp.x - ksz.x * 0.5, bp.y + ksz.y * 0.24), k, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, cols[k])
		var ltxt: String = labels[k]
		var lsz = font.get_string_size(ltxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10)
		var lrect = Rect2(bp.x - lsz.x * 0.5 - 5.0, bp.y + br + 3.0, lsz.x + 10.0, 14.0)
		hud_canvas.draw_rect(lrect, Color(0.02, 0.04, 0.08, 0.84))
		hud_canvas.draw_string(font, Vector2(bp.x - lsz.x * 0.5, bp.y + br + 13.0), ltxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, C_TEXT)

	# 6. ACTIVE OVERLAY SCREENS
	if menu_state == MenuState.TECH_TREE:
		_draw_tech_tree_modal(vp, font, tl_rect)
	elif menu_state == MenuState.DEPOT_UI:
		_draw_depot_modal(vp, font, tl_rect)
	elif menu_state != MenuState.FIELD:
		_draw_command_or_build_tree(vp, font, tl_rect)

func _draw_tech_tree_modal(vp: Vector2, font: Font, tl_rect: Rect2) -> void:
	var y_top = float(btn_rects["Y"]["pos"].y) - float(btn_rects["Y"]["r"])
	var controls_top_y = minf(joy_center.y - joy_radius, y_top)
	var pw = minf(vp.x - 24.0, 820.0)
	var max_h = maxf(250.0, controls_top_y - (tl_rect.end.y + 8.0) - 8.0)
	var px = (vp.x - pw) * 0.5
	var py = tl_rect.end.y + 6.0
	var prect = Rect2(px, py, pw, max_h)
	_draw_chamfer_panel(prect, C_BG_DARK, C_CYAN, 14.0, 2.2)

	hud_canvas.draw_string(font, Vector2(px + 18, py + 23), "COLONY RESEARCH LAB // TECH TREE DAG [TAP CARD -> RESEARCH]", HORIZONTAL_ALIGNMENT_LEFT, int(pw - 96), 13, C_CYAN)
	var close_r = Rect2(px + pw - 74.0, py + 6.0, 62.0, 22.0)
	_draw_chamfer_panel(close_r, Color(0.22, 0.06, 0.09, 0.9), C_CRIMSON, 5.0, 1.4)
	hud_canvas.draw_string(font, close_r.position + Vector2(12, 15), "CLOSE", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, C_TEXT)
	tree_hitboxes.append({"rect": close_r, "action": func(): menu_state = MenuState.FIELD})

	# Compute responsive card rects per DAG (6 columns x 3 rows on wide, 2 columns x 4 rows on narrow mobile)
	var cols_n = 2 if vp.x < 680.0 else 6
	var rows_n = 4 if cols_n == 2 else 3
	var insp_h = clampf(max_h * 0.30, 84.0, 100.0)
	var area_h = max_h - 36.0 - insp_h - 10.0
	var gap_x = 6.0 if cols_n == 6 else 10.0
	var gap_y = 6.0 if rows_n == 3 else 8.0
	var cw = (pw - 28.0 - float(cols_n - 1) * gap_x) / float(cols_n)
	var ch = clampf((area_h - float(rows_n - 1) * gap_y) / float(rows_n), 32.0, 52.0)

	var node_centers: Dictionary = {}
	var node_rects: Dictionary = {}
	for i in range(GameState.TECH_ORDER.size()):
		var tid = GameState.TECH_ORDER[i]
		var tnode = GameState.TECH_TREE[tid]
		var gx = i % cols_n if cols_n == 2 else clampi(int(tnode.get("col", i % 6)), 0, 5)
		var gy = i / cols_n if cols_n == 2 else clampi(int(tnode.get("row", 1)), 0, 2)
		var x = px + 14.0 + float(gx) * (cw + gap_x)
		var y = py + 34.0 + float(gy) * (ch + gap_y)
		var cr = Rect2(x, y, cw, ch)
		node_rects[tid] = cr
		node_centers[tid] = cr.position + cr.size * 0.5

	# Draw DAG dependency wires behind cards
	for tid in GameState.TECH_ORDER:
		for req in GameState.TECH_TREE[tid].get("req", []):
			if node_centers.has(req) and node_centers.has(tid):
				var done_line = GameState.is_tech_unlocked(req)
				hud_canvas.draw_line(node_centers[req], node_centers[tid], C_EMERALD if done_line else Color(0.28, 0.42, 0.58, 0.65), 2.2 if done_line else 1.5)

	# Draw Tech Cards
	for tid in GameState.TECH_ORDER:
		var tinfo = GameState.TECH_TREE[tid]
		var cr: Rect2 = node_rects[tid]
		var done = GameState.is_tech_unlocked(tid)
		var req_ok = GameState.are_tech_reqs_met(tid)
		var afford = GameState.can_afford(tinfo["cost"])
		var sel = (tid == selected_tech_id)
		var border_c = C_EMERALD if done else (C_CYAN if sel else (C_AMBER if req_ok else Color(0.32, 0.38, 0.48)))
		var fill_c = Color(0.05, 0.18, 0.14, 0.95) if done else (Color(0.09, 0.18, 0.30, 0.96) if sel else Color(0.04, 0.07, 0.12, 0.95))
		_draw_chamfer_panel(cr, fill_c, border_c, 7.0, 2.2 if sel else 1.4)
		var st_str = "UNLOCKED" if done else ("READY" if (req_ok and afford) else ("NEED RES" if req_ok else "LOCKED"))
		hud_canvas.draw_string(font, cr.position + Vector2(8, ch * 0.42), tinfo["name"], HORIZONTAL_ALIGNMENT_LEFT, int(cw - 14), 10 if cols_n == 6 else 11, C_TEXT)
		hud_canvas.draw_string(font, cr.position + Vector2(8, ch * 0.78), st_str, HORIZONTAL_ALIGNMENT_LEFT, int(cw - 14), 10, border_c)
		var cap_tid: String = tid
		tree_hitboxes.append({"rect": cr, "action": func():
			selected_tech_id = cap_tid
			AudioSynth.play_synth("click")
		})

	# Bottom Tech Card Inspector & Research Trigger
	var sel_t = GameState.TECH_TREE.get(selected_tech_id, GameState.TECH_TREE["basic_mining"])
	var insp_r = Rect2(px + 14.0, py + max_h - insp_h - 8.0, pw - 28.0, insp_h)
	_draw_chamfer_panel(insp_r, Color(0.03, 0.06, 0.11, 0.96), C_STEEL, 8.0, 1.5)
	var is_done = GameState.is_tech_unlocked(selected_tech_id)
	var cost_parts: PackedStringArray = []
	for ck in sel_t["cost"].keys():
		cost_parts.append("%s: %d/%d" % [String(ck).to_upper(), GameState.get_res(ck), int(sel_t["cost"][ck])])
	var unlock_names: PackedStringArray = []
	for ub in sel_t.get("unlocks_bld", []):
		unlock_names.append(String(GameState.BUILDINGS.get(ub, {}).get("name", ub)))
	var unl_txt = "All Starter Tools" if unlock_names.is_empty() else ", ".join(unlock_names)
	hud_canvas.draw_string(font, insp_r.position + Vector2(12, 20), "%s  |  Unlocks: %s" % [sel_t["name"].to_upper(), unl_txt], HORIZONTAL_ALIGNMENT_LEFT, int(insp_r.size.x - 156), 12, C_CYAN)
	hud_canvas.draw_string(font, insp_r.position + Vector2(12, 40), String(sel_t.get("summary", "")), HORIZONTAL_ALIGNMENT_LEFT, int(insp_r.size.x - 156), 11, C_TEXT)
	hud_canvas.draw_string(font, insp_r.position + Vector2(12, 60), "Flow: " + String(sel_t.get("flow", "")), HORIZONTAL_ALIGNMENT_LEFT, int(insp_r.size.x - 156), 10, C_EMERALD)
	hud_canvas.draw_string(font, insp_r.position + Vector2(12, 84), "Cost: " + ("FREE / STARTER" if cost_parts.is_empty() else " | ".join(cost_parts)), HORIZONTAL_ALIGNMENT_LEFT, int(insp_r.size.x - 156), 11, C_AMBER)

	var res_btn = Rect2(insp_r.end.x - 142.0, insp_r.position.y + 18.0, 130.0, 62.0)
	var can_res = (not is_done) and GameState.are_tech_reqs_met(selected_tech_id) and GameState.can_afford(sel_t["cost"])
	_draw_chamfer_panel(res_btn, Color(0.06, 0.24, 0.16, 0.96) if can_res else Color(0.06, 0.09, 0.14, 0.92), C_EMERALD if can_res else C_MUTED, 8.0, 2.0)
	var blbl = "DONE" if is_done else ("RESEARCH [A]" if can_res else "LOCKED")
	hud_canvas.draw_string(font, res_btn.position + Vector2(14, 37), blbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_EMERALD if can_res else C_MUTED)
	tree_hitboxes.append({"rect": res_btn, "action": func():
		if GameState.try_research_tech(selected_tech_id): AudioSynth.play_synth("craft")
		else: AudioSynth.play_synth("error")
	})

func _draw_depot_modal(vp: Vector2, font: Font, tl_rect: Rect2) -> void:
	var fac = player_ref.factory if (player_ref and ("factory" in player_ref)) else null
	if not fac:
		menu_state = MenuState.FIELD
		return
	var snap: Dictionary = fac.get_depot_snapshot(fac.selected_depot_uid)
	if snap.is_empty():
		menu_state = MenuState.FIELD
		return
	var uid = int(snap["uid"])
	var pw = minf(vp.x - 24.0, 520.0)
	var y_top = float(btn_rects["Y"]["pos"].y) - float(btn_rects["Y"]["r"])
	var controls_top_y = minf(joy_center.y - joy_radius, y_top)
	var ph = clampf(controls_top_y - (tl_rect.end.y + 10.0) - 10.0, 260.0, 460.0)
	var px = (vp.x - pw) * 0.5
	var py = tl_rect.end.y + 8.0
	var prect = Rect2(px, py, pw, ph)
	_draw_chamfer_panel(prect, C_BG_DARK, C_AMBER, 14.0, 2.2)
	hud_canvas.draw_string(font, Vector2(px + 16, py + 24), "CARGO DEPOT #%d  [%d/%d] // INV & 4-WAY FILTERS" % [uid, int(snap["total"]), int(snap["cap"])], HORIZONTAL_ALIGNMENT_LEFT, int(pw - 92), 12, C_AMBER)

	var close_r = Rect2(px + pw - 74.0, py + 6.0, 62.0, 22.0)
	_draw_chamfer_panel(close_r, Color(0.22, 0.06, 0.09, 0.9), C_CRIMSON, 5.0, 1.4)
	hud_canvas.draw_string(font, close_r.position + Vector2(12, 15), "CLOSE", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, C_TEXT)
	tree_hitboxes.append({"rect": close_r, "action": func(): menu_state = MenuState.FIELD})

	# Deposit All Ores quick action
	var dep_all_r = Rect2(px + 14.0, py + 34.0, pw - 28.0, 26.0)
	_draw_chamfer_panel(dep_all_r, Color(0.06, 0.16, 0.24, 0.95), C_CYAN, 6.0, 1.4)
	hud_canvas.draw_string(font, dep_all_r.position + Vector2(12, 18), "DEPOSIT ALL ORES FROM SHIP INTO DEPOT", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, C_CYAN)
	tree_hitboxes.append({"rect": dep_all_r, "action": func(): fac.depot_deposit_all_ores(uid)})

	# 4-Direction Belt Filter Selector Row
	hud_canvas.draw_string(font, Vector2(px + 16, py + 76), "OUTPUT FILTERS (TAP DIRECTION TO CYCLE ITEM):", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, C_MUTED)
	var dirs = ["left", "right", "up", "down"]
	var dw = (pw - 36.0) / 4.0
	var filters: Dictionary = snap["out_filters"]
	for di in range(dirs.size()):
		var dk = dirs[di]
		var fval = String(filters.get(dk, "none"))
		var fr = Rect2(px + 14.0 + float(di) * (dw + 4.0), py + 82.0, dw, 32.0)
		_draw_chamfer_panel(fr, Color(0.05, 0.14, 0.20, 0.95), C_EMERALD if fval != "none" else C_STEEL, 6.0, 1.5)
		hud_canvas.draw_string(font, fr.position + Vector2(6, 14), dk.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, C_MUTED)
		hud_canvas.draw_string(font, fr.position + Vector2(6, 27), fval.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, int(dw - 10), 11, C_EMERALD if fval != "none" else C_CRIMSON)
		var cap_dk: String = dk
		tree_hitboxes.append({"rect": fr, "action": func(): fac.depot_cycle_filter(uid, cap_dk)})

	# Depot vs Ship Transfer List
	var items_show = ["fe", "cu", "si", "ti", "plate_fe", "wire_cu", "wafer_si", "circuit", "alloy", "sci_pack"]
	var iy = py + 122.0
	var rh = clampf((ph - 130.0) / float(items_show.size()), 18.0, 26.0)
	var inv: Dictionary = snap["inv"]
	for it in items_show:
		if iy + rh > py + ph - 6.0:
			break
		var d_cnt = int(inv.get(it, 0))
		var p_cnt = GameState.get_res(it)
		hud_canvas.draw_string(font, Vector2(px + 18, iy + rh * 0.72), "%-8s  DEPOT:%d  SHIP:%d" % [String(it).to_upper(), d_cnt, p_cnt], HORIZONTAL_ALIGNMENT_LEFT, int(pw - 150), 11, C_TEXT if d_cnt > 0 else C_MUTED)
		var cap_it: String = it
		var r_take = Rect2(px + pw - 122.0, iy + 1.0, 50.0, rh - 2.0)
		_draw_chamfer_panel(r_take, Color(0.06, 0.14, 0.22), C_CYAN, 4.0, 1.0)
		hud_canvas.draw_string(font, r_take.position + Vector2(6, rh * 0.68), "TAKE5", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, C_CYAN)
		tree_hitboxes.append({"rect": r_take, "action": func(): fac.depot_transfer(uid, cap_it, false, 5)})

		var r_put = Rect2(px + pw - 68.0, iy + 1.0, 50.0, rh - 2.0)
		_draw_chamfer_panel(r_put, Color(0.06, 0.18, 0.14), C_EMERALD, 4.0, 1.0)
		hud_canvas.draw_string(font, r_put.position + Vector2(8, rh * 0.68), "PUT5", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, C_EMERALD)
		tree_hitboxes.append({"rect": r_put, "action": func(): fac.depot_transfer(uid, cap_it, true, 5)})
		iy += rh

func _draw_command_or_build_tree(vp: Vector2, font: Font, tl_rect: Rect2) -> void:
	var nodes = _get_active_tree_nodes()
	var mw = minf(vp.x - 24.0, 444.0)
	var tab_h = 26.0
	var y_top = float(btn_rects["Y"]["pos"].y) - float(btn_rects["Y"]["r"])
	var controls_top_y = minf(joy_center.y - joy_radius, y_top)
	var max_avail_h = maxf(160.0, (controls_top_y - 14.0) - (tl_rect.end.y + 8.0))
	var row_h = clampf((max_avail_h - 46.0 - tab_h) / maxf(1.0, float(nodes.size())) - 5.0, 36.0, 52.0)
	var gap_y = 4.0 if row_h < 44.0 else 6.0
	var mh = 42.0 + tab_h + float(nodes.size()) * (row_h + gap_y)
	var mx = clampf(vp.x - mw - 18.0, 12.0, (vp.x - mw) * 0.5)
	var my = clampf(controls_top_y - mh - 14.0, tl_rect.end.y + 8.0, maxf(tl_rect.end.y + 8.0, controls_top_y - mh - 12.0))
	var mrect = Rect2(mx, my, mw, mh)
	_draw_chamfer_panel(mrect, C_BG_DARK, C_CYAN, 14.0, 2.0)

	var header = "BUILD TREE [2-CLICK | L-STICK TAB]" if menu_state == MenuState.BUILD_TREE else "ONBOARD 3D PRINTER & CMD [2-CLICK]"
	hud_canvas.draw_string(font, Vector2(mx + 16, my + 24), header, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_CYAN)

	var tabs: Array[String] = BUILD_BRANCHES if menu_state == MenuState.BUILD_TREE else CMD_TABS
	var cur_tab: int = active_branch_idx if menu_state == MenuState.BUILD_TREE else active_cmd_tab_idx
	var tw = (mw - 24.0) / float(tabs.size())
	for ti in range(tabs.size()):
		var trect = Rect2(mx + 12.0 + float(ti) * tw, my + 32.0, tw - 4.0, tab_h)
		var is_active_t = (ti == cur_tab)
		_draw_chamfer_panel(trect, Color(0.10, 0.24, 0.38, 0.96) if is_active_t else Color(0.04, 0.07, 0.13, 0.92), C_CYAN if is_active_t else C_STEEL, 6.0, 1.8 if is_active_t else 1.0)
		var tlbl = tabs[ti]
		var tsz = font.get_string_size(tlbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
		hud_canvas.draw_string(font, Vector2(trect.position.x + (trect.size.x - tsz.x) * 0.5, trect.position.y + 18.0), tlbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, C_TEXT if is_active_t else C_MUTED)
		var tab_idx: int = ti
		tree_hitboxes.append({"rect": trect, "action": func():
			if menu_state == MenuState.BUILD_TREE: active_branch_idx = tab_idx
			else: active_cmd_tab_idx = tab_idx
			cursor_idx = 0
			AudioSynth.play_synth("click")
		})

	for i in range(nodes.size()):
		var nd = nodes[i]
		var ny = my + 38.0 + tab_h + float(i) * (row_h + gap_y)
		var nrect = Rect2(mx + 12.0, ny, mw - 24.0, row_h)
		var sel = (i == cursor_idx)
		var nc: Color = nd["col"]
		_draw_chamfer_panel(nrect, Color(0.08, 0.16, 0.28, 0.96) if sel else Color(0.04, 0.07, 0.13, 0.95), C_CYAN if sel else nc, 8.0, 2.2 if sel else 1.2)
		if nd["icon"]:
			var isz = minf(28.0, row_h - 10.0)
			hud_canvas.draw_texture_rect(nd["icon"], Rect2(nrect.position + Vector2(10, (row_h - isz) * 0.5), Vector2(isz, isz)), false)
		var tx = nrect.position.x + (46.0 if nd["icon"] else 14.0)
		var qbadge = "[Y] " if i == 0 else ("[X] " if i == 1 else ("[A] " if sel else ""))
		hud_canvas.draw_string(font, Vector2(tx, ny + row_h * 0.42), qbadge + nd["label"], HORIZONTAL_ALIGNMENT_LEFT, int(mw - 68), 13 if row_h < 44.0 else 14, C_TEXT if sel else nc)
		hud_canvas.draw_string(font, Vector2(tx, ny + row_h * 0.80), nd["sub"], HORIZONTAL_ALIGNMENT_LEFT, int(mw - 68), 10, C_MUTED)
		tree_hitboxes.append({"rect": nrect, "action": nd["action"]})

func is_blocking_world_input() -> bool:
	if menu_state != MenuState.FIELD:
		return true
	var mp = get_viewport().get_mouse_position()
	if mp.distance_to(joy_center) <= joy_radius * 1.45:
		return true
	for fhb in field_hitboxes:
		if fhb["rect"].has_point(mp):
			return true
	for k in ["A", "B", "X", "Y"]:
		var bd = btn_rects.get(k, null)
		if bd and mp.distance_to(bd["pos"]) <= float(bd["r"]) + 10.0:
			return true
	return false
