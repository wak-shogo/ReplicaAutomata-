extends CanvasLayer
class_name GameHUD

# ==============================================================================
# STAR REPLICA: AUTOMA - AAA MINIMALIST HUD & 2-CLICK ABXY/JOYSTICK TREE
# Features:
#   - DPR-aware auto-scaling (crisp large text on Desktop & 3x-DPR Mobile)
#   - Bespoke chamfered sci-fi vector polygons (zero plain rounded rectangles)
#   - Open-world circular radar + essential vitals (HP, Shield, Ores, Fleet)
#   - 1 Analog Left Stick + 4 ABXY triggers reaching every feature in <= 2 clicks
# ==============================================================================

signal orbit_cam_toggled
signal save_requested
signal reset_requested
signal brake_requested

enum MenuState { FIELD, BUILD_TREE, CMD_TREE }

const BUILD_BRANCHES: Array[String] = ["MINE", "FACTORY", "POWER", "MEGA"]
const CMD_TABS: Array[String] = ["PRINTER", "SWARM", "SYSTEM"]

var menu_state: int = MenuState.FIELD
var active_branch_idx: int = 0
var active_cmd_tab_idx: int = 0
var cursor_idx: int = 0

var player_ref: Node2D
var world_ref: PlanetWorld
var swarm_ref: SwarmSimulation

var hud_canvas: Control
var icons: Dictionary = {}

# Virtual Joystick & ABXY interaction state
var joy_drag_idx: int = -1
var joy_center: Vector2 = Vector2(110, 500)
var joy_radius: float = 54.0
var joy_vec: Vector2 = Vector2.ZERO

var btn_rects: Dictionary = {} # key -> Rect2 / pos+r
var tree_hitboxes: Array[Dictionary] = [] # {rect: Rect2, action: Callable}
var pressed_flash: Dictionary = {} # key -> float
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
const C_BG = Color(0.035, 0.055, 0.105, 0.88)
const C_BG_DARK = Color(0.02, 0.032, 0.065, 0.94)
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

func _load_icons() -> void:
	var paths = {
		"fe": "res://assets/ui/fe.png",
		"cu": "res://assets/ui/cu.png",
		"si": "res://assets/ui/si.png",
		"ti": "res://assets/ui/ti.png",
		"plate_fe": "res://assets/ui/item_plate_fe.png",
		"circuit": "res://assets/ui/item_circuit.png",
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
	# DPR-aware auto-scale so Desktop (1600x900), Mobile (390x844), AND 3x Mobile (1080x2400)
	# all render crisp readable AAA typography & thumb-friendly ABXY pads!
	var min_dim = minf(win_sz.x, win_sz.y)
	var scale_f = clampf(min_dim / 520.0, 0.90, 2.55)
	if absf(win.content_scale_factor - scale_f) > 0.04:
		win.content_scale_factor = scale_f

	var vp = get_viewport().get_visible_rect().size
	joy_radius = clampf(minf(vp.x, vp.y) * 0.105, 44.0, 58.0)
	var d = clampf(joy_radius * 0.92, 42.0, 54.0)
	var r = clampf(d * 0.46, 20.0, 26.0)
	var bottom_margin = 28.0
	joy_center = Vector2(joy_radius + 26.0, vp.y - joy_radius - bottom_margin - 6.0)

	# Bottom-Right ABXY Diamond cluster layout (bottom-safe so 'A' badge never clips viewport)
	var pad_center = Vector2(vp.x - d - r - 24.0, vp.y - d - r - bottom_margin)
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
	if menu_state == MenuState.FIELD:
		menu_state = MenuState.BUILD_TREE
		cursor_idx = 0
		AudioSynth.play_synth("select")
	else:
		menu_state = MenuState.FIELD

func _process(delta: float) -> void:
	anim_time += delta
	if status_banner_t > 0.0:
		status_banner_t -= delta
	if stick_nav_cd > 0.0:
		stick_nav_cd -= delta
	for k in pressed_flash.keys():
		pressed_flash[k] = maxf(0.0, float(pressed_flash[k]) - delta)

	# When inside a command tree, Left Stick navigates tree nodes instead of moving ship!
	if menu_state != MenuState.FIELD:
		if player_ref and player_ref.has_method("set_virtual_input"):
			player_ref.set_virtual_input(Vector2.ZERO, false)
		_poll_menu_stick()
	else:
		if held_btn == "A":
			pressed_flash["A"] = 0.08
		if player_ref and player_ref.has_method("set_virtual_input"):
			player_ref.set_virtual_input(joy_vec, (held_btn == "A") or (pressed_flash.get("A", 0.0) > 0.0))

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
			var payload := {
				"fe": GameState.fe, "cu": GameState.cu, "si": GameState.si, "ti": GameState.ti,
				"plate_fe": GameState.plate_fe, "circuit": GameState.circuit, "probe_stock": GameState.probe_stock,
				"eng": GameState.engine_tier, "spd": int(GameState.get_flight_speed()),
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
				"bldg": player_ref.factory.buildings.size() if ("factory" in player_ref and player_ref.factory) else 0,
				"near_ast": near_ast,
			}
			JavaScriptBridge.eval("window.__hudTelemetry = %s;" % JSON.stringify(payload))

func _poll_menu_stick() -> void:
	var j = joy_vec + Vector2(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
	# Instant cooldown reset on stick release so rapid discrete flicks never drop
	if j.length() < 0.25:
		stick_nav_cd = 0.0
		return
	if stick_nav_cd > 0.0:
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
	# 1. Screen Touch / Mouse Drag for Analog Stick, ABXY Diamond & Tree Petals
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

	# 2. Physical Gamepad & Keyboard ABXY Bindings
	elif event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_A: _trigger_abxy("A"); get_viewport().set_input_as_handled()
			JOY_BUTTON_B: _trigger_abxy("B"); get_viewport().set_input_as_handled()
			JOY_BUTTON_X: _trigger_abxy("X"); get_viewport().set_input_as_handled()
			JOY_BUTTON_Y: _trigger_abxy("Y"); get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
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
	if now_ms - last_pointer_press_ms < 120:
		return false

	# Check ABXY Diamond buttons first
	for k in ["A", "B", "X", "Y"]:
		var bd = btn_rects.get(k, null)
		if bd and pos.distance_to(bd["pos"]) <= float(bd["r"]) + 8.0:
			last_pointer_press_ms = now_ms
			held_btn = k
			held_btn_idx = idx
			_trigger_abxy(k)
			return true

	# Check Left Analog Joystick zone (active in BOTH field & menu tree tab/row navigation!)
	if pos.distance_to(joy_center) <= joy_radius * 1.45:
		joy_drag_idx = idx
		_update_joy_from_pos(pos)
		return true

	# Check 2-Click Tree Node hitboxes when menu is open
	if menu_state != MenuState.FIELD:
		for hb in tree_hitboxes:
			if hb["rect"].has_point(pos):
				last_pointer_press_ms = now_ms
				hb["action"].call()
				return true
		# Tapping backdrop outside tree closes cleanly
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

	# Universal B = Back / Cancel Tool / Space Brake!
	if btn == "B":
		AudioSynth.play_synth("click")
		if menu_state != MenuState.FIELD:
			menu_state = MenuState.FIELD
		elif GameState.selected_tool != "pick":
			GameState.set_tool("pick")
		else:
			emit_signal("brake_requested")
		return

	# Field Level (0 clicks)
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

	# Depth-1 Tabbed Tree (Any function reachable in at most 2 clicks via Stick + ABXY!)
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
				var req_d = int(info.get("req_drones", 0))
				var unlocked = GameState.drones >= req_d
				var can_pay = GameState.can_afford(info["cost"])
				var cost_s: PackedStringArray = []
				for ck in info["cost"].keys(): cost_s.append("%s:%d" % [ck.to_upper(), int(info["cost"][ck])])
				var st = ("READY | " + " ".join(cost_s)) if (unlocked and can_pay) else ("LOCK (%d Drones)" % req_d if not unlocked else GameState.get_missing_text(info["cost"]) + " | " + " ".join(cost_s))
				var target_bid: String = bid
				out.append({
					"label": info["name"],
					"sub": st,
					"col": C_EMERALD if (unlocked and can_pay) else (C_AMBER if unlocked else C_CRIMSON),
					"icon": icons.get(bid, null),
					"action": func():
						GameState.set_tool(target_bid)
						menu_state = MenuState.FIELD
						AudioSynth.play_synth("select")
				})
			if cur_branch == "MEGA":
				out.append({
					"label": "Salvage Tool",
					"sub": "Deconstruct & refund 50%",
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
					var ec: PackedStringArray = []
					for k in eng_info["cost"].keys(): ec.append("%d %s" % [int(eng_info["cost"][k]), k.to_upper()])
					var can_e = GameState.can_afford(eng_info["cost"])
					out.append({
						"label": "PRINT: %s (%s)" % [eng_info["name"].to_upper(), " ".join(ec)],
						"sub": eng_info["desc"] if can_e else GameState.get_missing_text(eng_info["cost"]) + " | " + eng_info["desc"],
						"col": C_EMERALD if can_e else C_AMBER,
						"icon": icons.get("pick", null),
						"action": func():
							if GameState.try_print_engine(): AudioSynth.play_synth("craft")
							else: AudioSynth.play_synth("error")
							menu_state = MenuState.FIELD
					})
				else:
					out.append({
						"label": "PROPULSION: WARP CORE Mk-III MAX",
						"sub": "Top flight speed 520 u/s active",
						"col": C_CYAN,
						"icon": icons.get("pick", null),
						"action": func(): menu_state = MenuState.FIELD
					})

				var dcost = GameState.get_drone_craft_cost()
				var dc: PackedStringArray = []
				for k in dcost.keys(): dc.append("%d %s" % [int(dcost[k]), k.to_upper()])
				out.append({"label": "CRAFT DRONE (%s)" % " ".join(dc), "sub": "Dock +1 Drone (%d/%d) & unlock tech" % [GameState.drones, GameState.max_drones], "col": C_EMERALD if GameState.can_afford(dcost) else C_AMBER, "icon": icons.get("probe_stock", null), "action": func():
					if GameState.try_craft_drone(): AudioSynth.play_synth("craft")
					else: AudioSynth.play_synth("error")
					menu_state = MenuState.FIELD
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
				out.append({"label": "SAVE COLONY", "sub": "Persist planet, factory & fleet", "col": C_EMERALD, "icon": null, "action": func(): emit_signal("save_requested"); menu_state = MenuState.FIELD})
				out.append({"label": "TOGGLE AUDIO", "sub": "Audio: %s" % ("MUTED" if AudioSynth.is_muted else "ACTIVE"), "col": C_CYAN, "icon": null, "action": func(): AudioSynth.toggle_mute(); menu_state = MenuState.FIELD})
				out.append({"label": "FLIP BELT DIR", "sub": "Reverse Arc Conveyor orientation", "col": C_AMBER, "icon": null, "action": func(): GameState.build_rotation = -GameState.build_rotation; AudioSynth.play_synth("click"); menu_state = MenuState.FIELD})
				out.append({"label": "RESET COLONY", "sub": "Start fresh 1-Seed survival", "col": C_CRIMSON, "icon": null, "action": func(): emit_signal("reset_requested"); menu_state = MenuState.FIELD})
	return out

func _draw_chamfer_panel(rect: Rect2, fill: Color, border: Color, cut: float = 10.0, stroke: float = 1.6) -> void:
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

	# 1. TOP-LEFT AAA CHAMFERED VITALS & RESOURCE PANEL
	var narrow = vp.x < 680.0
	var tl_w = minf(vp.x - 118.0, 396.0)
	var tl_h = 122.0 if narrow else 116.0
	var tl_rect = Rect2(12, 12, tl_w, tl_h)
	_draw_chamfer_panel(tl_rect, C_BG, C_STEEL, 12.0, 1.8)

	# Accent top bevel strip & corner bracket ticks
	hud_canvas.draw_line(Vector2(28, 12), Vector2(tl_w * 0.58, 12), C_CYAN, 2.5)
	hud_canvas.draw_line(Vector2(tl_rect.end.x - 24, tl_rect.end.y), Vector2(tl_rect.end.x - 10, tl_rect.end.y), C_AMBER, 2.0)

	# HP & Shield Segmented Bars
	var hp_r = clampf(GameState.player_hp / GameState.player_max_hp, 0.0, 1.0)
	var sh_r = clampf(GameState.player_shield / GameState.player_max_shield, 0.0, 1.0)
	hud_canvas.draw_string(font, Vector2(26, 33), "HP %d" % int(GameState.player_hp), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_EMERALD)
	var bar1_w = clampf(tl_w * 0.25, 64.0, 96.0)
	hud_canvas.draw_rect(Rect2(82, 22, bar1_w, 10), C_BG_DARK)
	hud_canvas.draw_rect(Rect2(82, 22, bar1_w * hp_r, 10), C_EMERALD)

	var sh_x = 82.0 + bar1_w + 12.0
	hud_canvas.draw_string(font, Vector2(sh_x, 33), "SHD %d" % int(GameState.player_shield), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_CYAN)
	var bar2_x = sh_x + 62.0
	var bar2_w = maxf(46.0, tl_rect.end.x - 14.0 - bar2_x)
	hud_canvas.draw_rect(Rect2(bar2_x, 22, bar2_w, 10), C_BG_DARK)
	hud_canvas.draw_rect(Rect2(bar2_x, 22, bar2_w * sh_r, 10), C_CYAN)

	# Resource Icons & Large Crisp Counts
	var res_keys = ["fe", "cu", "si", "ti", "plate_fe", "circuit"]
	var rx = 24.0
	var step_x = (tl_w - 24.0) / float(res_keys.size())
	for rk in res_keys:
		var ic: Texture2D = icons.get(rk, null)
		if ic:
			hud_canvas.draw_texture_rect(ic, Rect2(rx, 45, 20, 20), false)
		hud_canvas.draw_string(font, Vector2(rx + 23, 61), str(GameState.get_res(rk)), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, C_TEXT)
		rx += step_x

	# Drones / Swarm Fleet / Power summary
	var pwr_col = C_EMERALD if GameState.power_ratio >= 0.99 else C_AMBER
	hud_canvas.draw_string(font, Vector2(26, 87), "DRONES %d/%d" % [GameState.drones, GameState.max_drones], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, C_AMBER)
	hud_canvas.draw_string(font, Vector2(148, 87), "FLEET %d" % GameState.fleet_count, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, C_CYAN)
	hud_canvas.draw_string(font, Vector2(246, 87), "PWR %d/%dkW" % [int(GameState.power_use), int(GameState.power_gen)], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, pwr_col)

	# Active Module / Velocity / Gravity / Atmosphere Telemetry inside Cluster
	var doc_names = ["HARVEST", "REPLICATE", "DEFEND", "ASSAULT"]
	var eng_lbl = "CAPSULE" if GameState.engine_tier == 0 else ("MK-1 LANDER" if GameState.engine_tier == 1 else ("MK-2 APOLLO" if GameState.engine_tier == 2 else "MK-3 WARP"))
	var alt_m = int(maxf(0.0, player_ref.position.length() - PlanetWorld.R_SURFACE)) if player_ref else 0
	var vel_live = int(player_ref.velocity.length()) if player_ref else 0
	var g_live = player_ref.current_g_norm if player_ref else 0.92
	var tname = "LASER" if GameState.selected_tool == "pick" else ("SALVAGE" if GameState.selected_tool == "demolish" else GameState.BUILDINGS.get(GameState.selected_tool, {}).get("name", "TOOL"))
	var alt_str = ("ALT %d/3600m" % alt_m) if (player_ref and player_ref.position.length() > PlanetWorld.R_SURFACE + 28.0 and player_ref.position.length() <= PlanetWorld.R_ATMOS_OUTER) else ("SPACE" if (player_ref and player_ref.position.length() > PlanetWorld.R_ATMOS_OUTER) else doc_names[GameState.current_doctrine])
	hud_canvas.draw_string(font, Vector2(26, 111), "%s | %s | V:%d %.2fg | %s" % [tname.to_upper(), eng_lbl, vel_live, g_live, alt_str], HORIZONTAL_ALIGNMENT_LEFT, int(tl_w - 36), 11, C_MUTED)

	# 2. TOP-RIGHT OPEN-WORLD RADAR MINIMAP
	var rad_r = 40.0 if narrow else 46.0
	var rad_c = Vector2(vp.x - rad_r - 16.0, rad_r + 14.0)
	hud_canvas.draw_circle(rad_c, rad_r + 2.0, C_BG_DARK)
	hud_canvas.draw_arc(rad_c, rad_r + 2.0, 0.0, TAU, 36, C_STEEL, 1.8)
	hud_canvas.draw_arc(rad_c, rad_r * 0.45, 0.0, TAU, 24, Color(0.18, 0.32, 0.48, 0.45), 1.0)
	# Origin-Prime scaled center dot + atmosphere ring
	hud_canvas.draw_circle(rad_c, 4.5, Color(0.32, 0.72, 0.95))
	var map_scale = rad_r / PlanetWorld.WORLD_LIMIT_R
	hud_canvas.draw_arc(rad_c, maxf(6.0, PlanetWorld.R_ATMOS_OUTER * map_scale), 0.0, TAU, 24, Color(0.22, 0.78, 1.0, 0.4), 1.0)
	if world_ref:
		for cbody in world_ref.celestials:
			var cp = rad_c + cbody["pos"] * map_scale
			hud_canvas.draw_circle(cp, 2.2, C_AMBER)
	if swarm_ref and not GameState.boss_defeated:
		hud_canvas.draw_circle(rad_c + swarm_ref.boss_pos * map_scale, 3.0, C_CRIMSON)
	if player_ref:
		var pp = rad_c + player_ref.position * map_scale
		hud_canvas.draw_circle(pp, 3.2, C_EMERALD)
	var zone_lbl = "GROUND" if GameState.engine_tier == 0 else ("SPACE" if (player_ref and player_ref.position.length() > PlanetWorld.R_ATMOS_OUTER) else ("ATMOS" if (player_ref and player_ref.position.length() > PlanetWorld.R_SURFACE + 28.0) else "PLANET"))
	var zsz = font.get_string_size(zone_lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
	hud_canvas.draw_string(font, Vector2(rad_c.x - zsz.x * 0.5, rad_c.y + rad_r + 16.0), zone_lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, C_CYAN)

	# 3. STATUS BANNER / VICTORY BANNER
	if GameState.game_won:
		var vw = minf(vp.x - 40.0, 440.0)
		var vrect = Rect2((vp.x - vw) * 0.5, tl_rect.end.y + 10.0, vw, 34.0)
		_draw_chamfer_panel(vrect, Color(0.04, 0.14, 0.10, 0.96), C_EMERALD, 8.0, 2.0)
		hud_canvas.draw_string(font, vrect.position + Vector2(14, 22), "VICTORY: WARP GATE & CORE HUB COMPLETE!", HORIZONTAL_ALIGNMENT_LEFT, int(vw - 24), 13, C_EMERALD)
	elif status_banner_t > 0.0:
		var bw = minf(vp.x - 40.0, 420.0)
		var brect = Rect2((vp.x - bw) * 0.5, tl_rect.end.y + 10.0, bw, 30.0)
		_draw_chamfer_panel(brect, Color(0.03, 0.05, 0.09, 0.92), status_banner_col, 7.0, 1.5)
		hud_canvas.draw_string(font, brect.position + Vector2(14, 20), status_banner, HORIZONTAL_ALIGNMENT_LEFT, int(bw - 24), 13, status_banner_col)

	# 4. BOTTOM-LEFT ANALOG JOYSTICK
	hud_canvas.draw_circle(joy_center, joy_radius, Color(0.03, 0.06, 0.11, 0.72))
	hud_canvas.draw_arc(joy_center, joy_radius, 0.0, TAU, 32, C_CYAN if joy_drag_idx != -1 else C_STEEL, 2.0)
	hud_canvas.draw_arc(joy_center, joy_radius * 0.5, 0.0, TAU, 24, Color(0.22, 0.45, 0.65, 0.35), 1.0)
	var stick_pos = joy_center + joy_vec * (joy_radius * 0.65)
	_draw_octagon_btn(stick_pos, 18.0, Color(0.10, 0.25, 0.42, 0.95), C_CYAN, C_CYAN, joy_vec.length() > 0.1)

	# 5. BOTTOM-RIGHT AAA ABXY ACTION DIAMOND (Strictly NO duplicate labels!)
	var labels = {
		"A": "PLACE" if (GameState.selected_tool in GameState.BUILDINGS) else ("SALVAGE" if GameState.selected_tool == "demolish" else "MINE"),
		"B": "CANCEL" if GameState.selected_tool != "pick" else "BRAKE",
		"X": "BUILD" if menu_state == MenuState.FIELD else "PICK 2",
		"Y": "PRINTER" if menu_state == MenuState.FIELD else "PICK 1",
	}
	if menu_state != MenuState.FIELD:
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

	# 6. 2-CLICK TABBED COMMAND & BUILD TREE OVERLAY (Appears cleanly above controls)
	tree_hitboxes.clear()
	if menu_state != MenuState.FIELD:
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

		# Category Tabs (Interactive + L-Stick Left/Right)
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
			hud_canvas.draw_string(font, Vector2(tx, ny + row_h * 0.80), nd["sub"], HORIZONTAL_ALIGNMENT_LEFT, int(mw - 68), 10 if row_h < 44.0 else 10, C_MUTED)
			tree_hitboxes.append({"rect": nrect, "action": nd["action"]})

func is_blocking_world_input() -> bool:
	if menu_state != MenuState.FIELD:
		return true
	var mp = get_viewport().get_mouse_position()
	if mp.distance_to(joy_center) <= joy_radius * 1.45:
		return true
	for k in ["A", "B", "X", "Y"]:
		var bd = btn_rects.get(k, null)
		if bd and mp.distance_to(bd["pos"]) <= float(bd["r"]) + 10.0:
			return true
	return false
