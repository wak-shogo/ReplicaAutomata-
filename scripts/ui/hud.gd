extends CanvasLayer
class_name GameHUD

# ==============================================================================
# STAR REPLICA: AUTOMA - PIXEL-CYBER TACTICAL HUD
# Modeled cleanly on target_gameplay_concept.jpeg with responsive desktop/mobile
# layout, opaque scrollable Tech Tree Catalog, and zero missing font glyphs.
# ==============================================================================

signal orbit_cam_toggled
signal save_requested
signal reset_requested
signal brake_requested

var top_left_panel: PanelContainer
var top_right_flow: HFlowContainer
var bottom_bar: PanelContainer
var telemetry_panel: PanelContainer
var tech_modal: PanelContainer
var touch_overlay: Control

# Live Label / Control references
var res_labels: Dictionary = {}
var lbl_fleet: Label
var lbl_drones: Label
var btn_craft_drone: Button
var lbl_power: Label
var printer_bar: ProgressBar
var lbl_printer: Label
var doctrine_btns: Dictionary = {}

var active_category: String = "MINE"
var cat_btns: Dictionary = {}
var hotbar_container: HBoxContainer
var tech_list_vbox: VBoxContainer
var tech_summary_lbl: Label

var lbl_zone: Label
var lbl_speed: Label
var log_vbox: VBoxContainer
var log_entries: Array[Dictionary] = []

var btn_orbit_cam: Button
var btn_mute: Button
var btn_pad: Button
var orbit_cam_active: bool = false
var force_touch_pad: bool = false

var player_ref: Node2D
var touch_move_vec: Vector2 = Vector2.ZERO
var touch_mining: bool = false
var icons: Dictionary = {}

const COL_BG = Color(0.045, 0.068, 0.115, 0.92)
const COL_BORDER = Color(0.18, 0.42, 0.65, 0.95)
const COL_ACTIVE = Color(0.22, 0.88, 1.0, 1.0)

func _ready() -> void:
	_load_icons()
	_build_ui()
	_connect_signals()
	get_viewport().size_changed.connect(_on_viewport_resized)
	_on_viewport_resized()
	refresh_all()

func setup(p_player: Node2D) -> void:
	player_ref = p_player

func _load_icons() -> void:
	var paths = {
		"fe": "res://assets/ui/fe.png",
		"cu": "res://assets/ui/cu.png",
		"si": "res://assets/ui/si.png",
		"ti": "res://assets/ui/ti.png",
		"plate_fe": "res://assets/ui/item_plate_fe.png",
		"circuit": "res://assets/ui/item_circuit.png",
		"probe_stock": "res://assets/ui/item_drone_unit.png",
		"energy": "res://assets/ui/energy.png",
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

func _make_panel_style(bg: Color = COL_BG, border: Color = COL_BORDER, bwidth: int = 1, radius: int = 4) -> StyleBoxFlat:
	var sb = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bwidth)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb

func _make_btn_style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 7
	sb.content_margin_right = 7
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb

func _style_button(btn: Button, accent: Color = COL_BORDER) -> void:
	btn.add_theme_stylebox_override("normal", _make_btn_style(Color(0.08, 0.12, 0.20, 0.94), accent))
	btn.add_theme_stylebox_override("hover", _make_btn_style(Color(0.13, 0.22, 0.34, 0.98), COL_ACTIVE))
	btn.add_theme_stylebox_override("pressed", _make_btn_style(Color(0.18, 0.36, 0.52, 1.0), COL_ACTIVE))
	btn.add_theme_font_size_override("font_size", 11)
	btn.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0))

func _build_ui() -> void:
	# 1. TOP-LEFT TACTICAL STATUS PANEL
	top_left_panel = PanelContainer.new()
	top_left_panel.position = Vector2(10, 10)
	top_left_panel.add_theme_stylebox_override("panel", _make_panel_style())
	add_child(top_left_panel)

	var tl_vbox = VBoxContainer.new()
	tl_vbox.add_theme_constant_override("separation", 4)
	top_left_panel.add_child(tl_vbox)

	# Row 1: Pixel-Icon Resource Strip
	var res_flow = HFlowContainer.new()
	res_flow.add_theme_constant_override("h_separation", 8)
	res_flow.add_theme_constant_override("v_separation", 2)
	tl_vbox.add_child(res_flow)

	for rk in ["fe", "cu", "si", "ti", "plate_fe", "circuit", "probe_stock"]:
		var item_box = HBoxContainer.new()
		item_box.add_theme_constant_override("separation", 3)
		var tex = TextureRect.new()
		tex.custom_minimum_size = Vector2(16, 16)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tex.texture = icons.get(rk, null)
		var lbl = Label.new()
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0))
		lbl.text = "0"
		item_box.add_child(tex)
		item_box.add_child(lbl)
		res_flow.add_child(item_box)
		res_labels[rk] = lbl

	# Row 2: Drones, Craft Drone Button, Fleet & Power
	var mid_hbox = HFlowContainer.new()
	mid_hbox.add_theme_constant_override("h_separation", 8)
	mid_hbox.add_theme_constant_override("v_separation", 3)
	tl_vbox.add_child(mid_hbox)

	lbl_drones = Label.new()
	lbl_drones.add_theme_font_size_override("font_size", 12)
	lbl_drones.add_theme_color_override("font_color", Color(1.0, 0.82, 0.35))
	mid_hbox.add_child(lbl_drones)

	btn_craft_drone = Button.new()
	_style_button(btn_craft_drone, Color(0.25, 0.85, 0.65))
	btn_craft_drone.pressed.connect(func():
		if GameState.try_craft_drone():
			AudioSynth.play_synth("craft")
		else:
			AudioSynth.play_synth("error")
		refresh_all()
	)
	mid_hbox.add_child(btn_craft_drone)

	lbl_fleet = Label.new()
	lbl_fleet.add_theme_font_size_override("font_size", 12)
	lbl_fleet.add_theme_color_override("font_color", Color(0.35, 0.95, 1.0))
	mid_hbox.add_child(lbl_fleet)

	lbl_power = Label.new()
	lbl_power.add_theme_font_size_override("font_size", 12)
	lbl_power.add_theme_color_override("font_color", Color(0.55, 1.0, 0.65))
	mid_hbox.add_child(lbl_power)

	# Row 3: Macro Replicator Progress + Doctrine Switcher
	var bot_row = HFlowContainer.new()
	bot_row.add_theme_constant_override("h_separation", 6)
	bot_row.add_theme_constant_override("v_separation", 3)
	tl_vbox.add_child(bot_row)

	lbl_printer = Label.new()
	lbl_printer.add_theme_font_size_override("font_size", 11)
	lbl_printer.add_theme_color_override("font_color", Color(0.75, 0.86, 0.96))
	lbl_printer.text = "PRINTER: IDLE"
	bot_row.add_child(lbl_printer)

	printer_bar = ProgressBar.new()
	printer_bar.custom_minimum_size = Vector2(96, 14)
	printer_bar.max_value = 100.0
	printer_bar.show_percentage = false
	var pb_bg = StyleBoxFlat.new()
	pb_bg.bg_color = Color(0.08, 0.11, 0.18, 1.0)
	pb_bg.set_corner_radius_all(3)
	var pb_fill = StyleBoxFlat.new()
	pb_fill.bg_color = Color(0.18, 0.85, 1.0, 1.0)
	pb_fill.set_corner_radius_all(3)
	printer_bar.add_theme_stylebox_override("background", pb_bg)
	printer_bar.add_theme_stylebox_override("fill", pb_fill)
	bot_row.add_child(printer_bar)

	var docs = [
		[GameState.Doctrine.HARVEST, "HARVEST"],
		[GameState.Doctrine.REPLICATE, "REPLICATE"],
		[GameState.Doctrine.DEFEND, "DEFEND"],
		[GameState.Doctrine.ASSAULT, "ASSAULT"],
	]
	for d in docs:
		var db = Button.new()
		db.text = d[1]
		_style_button(db)
		var d_id: int = d[0]
		db.pressed.connect(func():
			GameState.set_doctrine(d_id)
			AudioSynth.play_synth("select")
			refresh_all()
		)
		bot_row.add_child(db)
		doctrine_btns[d_id] = db

	# 2. TOP-RIGHT COMPACT UTILITY BUTTONS
	top_right_flow = HFlowContainer.new()
	top_right_flow.alignment = FlowContainer.ALIGNMENT_END
	top_right_flow.add_theme_constant_override("h_separation", 5)
	top_right_flow.add_theme_constant_override("v_separation", 4)
	add_child(top_right_flow)

	var btn_tech = Button.new()
	btn_tech.text = "TECH / BUILD [B]"
	_style_button(btn_tech, COL_ACTIVE)
	btn_tech.pressed.connect(toggle_tech_modal)
	top_right_flow.add_child(btn_tech)

	btn_orbit_cam = Button.new()
	btn_orbit_cam.text = "ORBIT VIEW [M]"
	_style_button(btn_orbit_cam)
	btn_orbit_cam.pressed.connect(func():
		orbit_cam_active = not orbit_cam_active
		emit_signal("orbit_cam_toggled")
		AudioSynth.play_synth("select")
		refresh_all()
	)
	top_right_flow.add_child(btn_orbit_cam)

	var btn_rot = Button.new()
	btn_rot.text = "FLIP [R]"
	_style_button(btn_rot)
	btn_rot.pressed.connect(func():
		GameState.build_rotation = (GameState.build_rotation + 2) % 4
		AudioSynth.play_synth("click")
		add_log("Belt Direction Flipped", "info")
	)
	top_right_flow.add_child(btn_rot)

	var btn_brake = Button.new()
	btn_brake.text = "BRAKE"
	_style_button(btn_brake)
	btn_brake.pressed.connect(func(): emit_signal("brake_requested"))
	top_right_flow.add_child(btn_brake)

	var btn_save = Button.new()
	btn_save.text = "SAVE"
	_style_button(btn_save)
	btn_save.pressed.connect(func(): emit_signal("save_requested"))
	top_right_flow.add_child(btn_save)

	btn_mute = Button.new()
	btn_mute.text = "AUDIO: ON"
	_style_button(btn_mute)
	btn_mute.pressed.connect(func():
		var m = AudioSynth.toggle_mute()
		btn_mute.text = "AUDIO: OFF" if m else "AUDIO: ON"
	)
	top_right_flow.add_child(btn_mute)

	btn_pad = Button.new()
	btn_pad.text = "PAD"
	_style_button(btn_pad)
	btn_pad.pressed.connect(func():
		force_touch_pad = not force_touch_pad
		_update_touch_pad_visibility()
	)
	top_right_flow.add_child(btn_pad)

	var btn_rst = Button.new()
	btn_rst.text = "RST"
	_style_button(btn_rst, Color(0.85, 0.35, 0.35))
	btn_rst.pressed.connect(func(): emit_signal("reset_requested"))
	top_right_flow.add_child(btn_rst)

	# 3. BOTTOM-CENTER TABBED BUILD HOTBAR
	bottom_bar = PanelContainer.new()
	bottom_bar.add_theme_stylebox_override("panel", _make_panel_style())
	add_child(bottom_bar)

	var bot_vbox = VBoxContainer.new()
	bot_vbox.add_theme_constant_override("separation", 4)
	bottom_bar.add_child(bot_vbox)

	var tab_hbox = HBoxContainer.new()
	tab_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	tab_hbox.add_theme_constant_override("separation", 4)
	bot_vbox.add_child(tab_hbox)

	for cat in [["MINE", "MINE & LOGI"], ["FACTORY", "FACTORY"], ["POWER", "POWER & DEF"], ["SPACE", "SPACE & MEGA"]]:
		var cb = Button.new()
		cb.text = cat[1]
		_style_button(cb)
		var cid: String = cat[0]
		cb.pressed.connect(func():
			active_category = cid
			AudioSynth.play_synth("click")
			_rebuild_hotbar()
			refresh_all()
		)
		tab_hbox.add_child(cb)
		cat_btns[cid] = cb

	var scroll_bar = ScrollContainer.new()
	scroll_bar.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_bar.custom_minimum_size = Vector2(200, 48)
	bot_vbox.add_child(scroll_bar)

	hotbar_container = HBoxContainer.new()
	hotbar_container.alignment = BoxContainer.ALIGNMENT_CENTER
	hotbar_container.add_theme_constant_override("separation", 4)
	scroll_bar.add_child(hotbar_container)

	# 4. BOTTOM-RIGHT TELEMETRY & LOG PANEL
	telemetry_panel = PanelContainer.new()
	telemetry_panel.clip_contents = true
	telemetry_panel.add_theme_stylebox_override("panel", _make_panel_style())
	add_child(telemetry_panel)

	var tel_vbox = VBoxContainer.new()
	tel_vbox.custom_minimum_size = Vector2(264, 0)
	tel_vbox.add_theme_constant_override("separation", 2)
	telemetry_panel.add_child(tel_vbox)

	lbl_zone = Label.new()
	lbl_zone.add_theme_font_size_override("font_size", 11)
	lbl_zone.add_theme_color_override("font_color", Color(0.45, 0.92, 1.0))
	tel_vbox.add_child(lbl_zone)

	lbl_speed = Label.new()
	lbl_speed.add_theme_font_size_override("font_size", 11)
	lbl_speed.add_theme_color_override("font_color", Color(0.85, 0.92, 0.98))
	tel_vbox.add_child(lbl_speed)

	log_vbox = VBoxContainer.new()
	log_vbox.add_theme_constant_override("separation", 1)
	tel_vbox.add_child(log_vbox)

	# 5. OPAQUE RESPONSIVE BLUEPRINT & TECH CATALOG MODAL
	tech_modal = PanelContainer.new()
	tech_modal.visible = false
	tech_modal.clip_contents = true
	tech_modal.add_theme_stylebox_override("panel", _make_panel_style(Color(0.035, 0.05, 0.09, 1.0), COL_ACTIVE, 2, 6))
	add_child(tech_modal)

	var modal_vbox = VBoxContainer.new()
	modal_vbox.add_theme_constant_override("separation", 8)
	tech_modal.add_child(modal_vbox)

	var header_hbox = HBoxContainer.new()
	modal_vbox.add_child(header_hbox)

	var title_lbl = Label.new()
	title_lbl.text = "TECH TREE & BLUEPRINTS"
	title_lbl.clip_text = true
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.add_theme_font_size_override("font_size", 14)
	title_lbl.add_theme_color_override("font_color", COL_ACTIVE)
	header_hbox.add_child(title_lbl)

	var btn_close_modal = Button.new()
	btn_close_modal.text = "CLOSE [ESC]"
	_style_button(btn_close_modal, Color(0.95, 0.35, 0.35))
	btn_close_modal.pressed.connect(func():
		tech_modal.visible = false
		_update_touch_pad_visibility()
	)
	header_hbox.add_child(btn_close_modal)

	tech_summary_lbl = Label.new()
	tech_summary_lbl.add_theme_font_size_override("font_size", 12)
	tech_summary_lbl.add_theme_color_override("font_color", Color(0.82, 0.9, 0.98))
	tech_summary_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	modal_vbox.add_child(tech_summary_lbl)

	var modal_scroll = ScrollContainer.new()
	modal_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	modal_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	modal_vbox.add_child(modal_scroll)

	tech_list_vbox = VBoxContainer.new()
	tech_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tech_list_vbox.add_theme_constant_override("separation", 6)
	modal_scroll.add_child(tech_list_vbox)

	# 6. MOBILE VIRTUAL TOUCH D-PAD + MINE BUTTON
	_build_touch_controls()
	_rebuild_hotbar()

func _build_touch_controls() -> void:
	touch_overlay = Control.new()
	touch_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(touch_overlay)

	var dpad_data = [
		["U", Vector2(46, 0), Vector2(0, -1)],
		["D", Vector2(46, 86), Vector2(0, 1)],
		["L", Vector2(2, 43), Vector2(-1, 0)],
		["R", Vector2(90, 43), Vector2(1, 0)],
	]
	for dd in dpad_data:
		var b = Button.new()
		b.text = dd[0]
		b.position = dd[1]
		b.custom_minimum_size = Vector2(40, 40)
		_style_button(b, Color(0.25, 0.72, 0.95, 0.8))
		var dir: Vector2 = dd[2]
		b.button_down.connect(func(): touch_move_vec += dir)
		b.button_up.connect(func(): touch_move_vec = Vector2.ZERO)
		touch_overlay.add_child(b)

	var mine_btn = Button.new()
	mine_btn.text = "MINE"
	mine_btn.position = Vector2(142, 34)
	mine_btn.custom_minimum_size = Vector2(58, 52)
	_style_button(mine_btn, Color(0.35, 0.95, 0.72, 0.9))
	mine_btn.button_down.connect(func(): touch_mining = true)
	mine_btn.button_up.connect(func(): touch_mining = false)
	touch_overlay.add_child(mine_btn)

func _connect_signals() -> void:
	GameState.inventory_changed.connect(refresh_all)
	GameState.state_updated.connect(refresh_all)
	GameState.blueprint_selected.connect(func(_id): _rebuild_hotbar(); refresh_all())
	GameState.log_event.connect(add_log)

func _rebuild_hotbar() -> void:
	for c in hotbar_container.get_children():
		c.queue_free()

	# Always first: PICK / LASER MINE tool
	_add_hotbar_btn("pick", "Mine[Q]", icons.get("pick", null), true)

	for bid in GameState.BUILDINGS.keys():
		var info = GameState.BUILDINGS[bid]
		if info["category"] != active_category:
			continue
		var hk = info["hotkey"]
		var short_name = info["name"].replace("Mining ", "").replace("Conveyor ", "").replace("Ore Lift ", "Lift ").replace("Inserter ", "").replace("Container ", "").replace("Blast ", "").replace("Auto ", "").replace("Macro ", "").replace("Defense ", "").replace("Geothermal ", "Geo ")
		var label = "%s" % short_name
		if hk != "":
			label = "[%s] %s" % [hk, short_name]
		var unlocked = GameState.drones >= int(info.get("req_drones", 0))
		_add_hotbar_btn(bid, label, icons.get(bid, null), unlocked)

	# Always last: DEMOLISH tool
	_add_hotbar_btn("demolish", "Salvage[X]", icons.get("demolish", null), true)

func _add_hotbar_btn(tool_id: String, text_lbl: String, icon_tex: Texture2D, unlocked: bool) -> void:
	var b = Button.new()
	b.text = text_lbl
	if icon_tex:
		b.icon = icon_tex
		b.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var is_sel = (GameState.selected_tool == tool_id)
	var border = COL_ACTIVE if is_sel else (COL_BORDER if unlocked else Color(0.45, 0.32, 0.25))
	var bg = Color(0.14, 0.30, 0.46, 0.98) if is_sel else Color(0.06, 0.09, 0.16, 0.94)
	b.add_theme_stylebox_override("normal", _make_btn_style(bg, border))
	b.add_theme_stylebox_override("hover", _make_btn_style(Color(0.14, 0.24, 0.36, 0.98), COL_ACTIVE))
	b.add_theme_font_size_override("font_size", 11)
	b.add_theme_color_override("font_color", Color(1, 1, 1) if unlocked else Color(0.7, 0.6, 0.5))
	b.pressed.connect(func():
		GameState.set_tool(tool_id)
		AudioSynth.play_synth("click")
	)
	hotbar_container.add_child(b)

func _rebuild_tech_catalog() -> void:
	for c in tech_list_vbox.get_children():
		c.queue_free()

	tech_summary_lbl.text = "DOCKED DRONES: %d/%d  |  Fe:%d  Cu:%d  Si:%d  Ti:%d  Plate:%d  Circ:%d  |  Click a facility to project blue Blueprint Ghosts on valid slots." % [
		GameState.drones, GameState.max_drones,
		GameState.fe, GameState.cu, GameState.si, GameState.ti,
		GameState.plate_fe, GameState.circuit
	]

	for bid in GameState.BUILDINGS.keys():
		var info = GameState.BUILDINGS[bid]
		var req_d = int(info.get("req_drones", 0))
		var unlocked = GameState.drones >= req_d
		var can_pay = GameState.can_afford(info["cost"])

		var card = PanelContainer.new()
		var c_border = Color(0.24, 0.82, 0.98) if (unlocked and can_pay) else (Color(0.85, 0.45, 0.28) if unlocked else Color(0.38, 0.38, 0.44))
		card.add_theme_stylebox_override("panel", _make_panel_style(Color(0.06, 0.088, 0.145, 0.98), c_border, 1, 4))
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tech_list_vbox.add_child(card)

		var card_vbox = VBoxContainer.new()
		card_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card_vbox.add_theme_constant_override("separation", 4)
		card.add_child(card_vbox)

		var top_row = HBoxContainer.new()
		top_row.add_theme_constant_override("separation", 8)
		card_vbox.add_child(top_row)

		var icon_rect = TextureRect.new()
		icon_rect.custom_minimum_size = Vector2(28, 28)
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon_rect.texture = icons.get(bid, null)
		top_row.add_child(icon_rect)

		var nl = Label.new()
		nl.text = "%s [%s]" % [info["name"], info["category"]]
		nl.clip_text = true
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nl.add_theme_font_size_override("font_size", 13)
		nl.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0))
		top_row.add_child(nl)

		var sel_btn = Button.new()
		sel_btn.text = "SELECT"
		_style_button(sel_btn, COL_ACTIVE if unlocked else Color(0.45, 0.35, 0.35))
		sel_btn.pressed.connect(func():
			active_category = info["category"]
			GameState.set_tool(bid)
			tech_modal.visible = false
			_update_touch_pad_visibility()
			AudioSynth.play_synth("select")
		)
		top_row.add_child(sel_btn)

		var meta_r = HFlowContainer.new()
		meta_r.add_theme_constant_override("h_separation", 8)
		card_vbox.add_child(meta_r)

		var pwr = float(info["power"])
		var pl = Label.new()
		pl.text = ("+%d kW" % int(pwr)) if pwr >= 0 else ("%d kW" % int(pwr))
		pl.add_theme_font_size_override("font_size", 11)
		pl.add_theme_color_override("font_color", Color(0.45, 1.0, 0.6) if pwr >= 0 else Color(1.0, 0.72, 0.35))
		meta_r.add_child(pl)

		var status_l = Label.new()
		status_l.add_theme_font_size_override("font_size", 11)
		if not unlocked:
			status_l.text = "LOCKED (NEED %d DRONES)" % req_d
			status_l.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35))
		elif can_pay:
			status_l.text = "READY TO BUILD"
			status_l.add_theme_color_override("font_color", Color(0.35, 1.0, 0.7))
		else:
			status_l.text = GameState.get_missing_text(info["cost"])
			status_l.add_theme_color_override("font_color", Color(1.0, 0.38, 0.38))
		meta_r.add_child(status_l)

		var cost_parts: PackedStringArray = []
		for ck in info["cost"].keys():
			cost_parts.append("%s:%d" % [ck.to_upper(), int(info["cost"][ck])])
		var desc_l = Label.new()
		desc_l.text = "Cost: %s  |  %s %s" % [" ".join(cost_parts), info["desc"], info["usage"]]
		desc_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_l.add_theme_font_size_override("font_size", 11)
		desc_l.add_theme_color_override("font_color", Color(0.75, 0.84, 0.94))
		card_vbox.add_child(desc_l)

func toggle_tech_modal() -> void:
	tech_modal.visible = not tech_modal.visible
	if tech_modal.visible:
		tech_modal.move_to_front()
		_rebuild_tech_catalog()
		_layout_tech_modal()
		AudioSynth.play_synth("select")
	_update_touch_pad_visibility()

func add_log(msg: String, level: String = "info") -> void:
	var col = Color(0.75, 0.88, 1.0)
	if level == "good": col = Color(0.4, 1.0, 0.68)
	elif level == "warn": col = Color(1.0, 0.78, 0.35)
	elif level == "error": col = Color(1.0, 0.35, 0.35)

	log_entries.append({"text": msg, "col": col, "life": 14.0})
	if log_entries.size() > 4:
		log_entries.remove_at(0)
	_refresh_log_ui()

func _refresh_log_ui() -> void:
	for c in log_vbox.get_children():
		log_vbox.remove_child(c)
		c.queue_free()
	for e in log_entries:
		var l = Label.new()
		l.text = "> " + e["text"]
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(260, 0)
		l.add_theme_font_size_override("font_size", 10)
		l.add_theme_color_override("font_color", e["col"])
		log_vbox.add_child(l)
	call_deferred("_position_telemetry")

func refresh_all() -> void:
	for rk in res_labels.keys():
		res_labels[rk].text = str(GameState.get_res(rk))

	lbl_drones.text = "DRONES:%d/%d" % [GameState.drones, GameState.max_drones]
	var dcost = GameState.get_drone_craft_cost()
	var dc_parts: PackedStringArray = []
	for k in dcost.keys():
		dc_parts.append("%d%s" % [int(dcost[k]), k.capitalize()])
	btn_craft_drone.text = "+DRONE (%s)" % " ".join(dc_parts)
	btn_craft_drone.disabled = GameState.drones >= GameState.max_drones

	lbl_fleet.text = "FLEET:%d/10000" % GameState.fleet_count
	lbl_power.text = "PWR:%d/%dkW (%d%%)" % [int(GameState.power_use), int(GameState.power_gen), int(GameState.power_ratio * 100.0)]

	if GameState.printer_active:
		lbl_printer.text = "REPLICATOR:%d%%" % int(GameState.printer_progress * 100.0)
	else:
		lbl_printer.text = "PRINTER:OFFLINE"
	printer_bar.value = GameState.printer_progress * 100.0

	for d_id in doctrine_btns.keys():
		var b: Button = doctrine_btns[d_id]
		var act = (GameState.current_doctrine == d_id)
		_style_button(b, COL_ACTIVE if act else COL_BORDER)

	for cid in cat_btns.keys():
		var cb: Button = cat_btns[cid]
		_style_button(cb, COL_ACTIVE if cid == active_category else COL_BORDER)

	if btn_orbit_cam:
		_style_button(btn_orbit_cam, COL_ACTIVE if orbit_cam_active else COL_BORDER)

	if tech_modal.visible:
		_rebuild_tech_catalog()

func _process(delta: float) -> void:
	if player_ref and player_ref.has_method("set_virtual_input"):
		player_ref.set_virtual_input(touch_move_vec, touch_mining)

		var spd = int(player_ref.velocity.length())
		var py = player_ref.position.y
		if py < -52.0:
			lbl_zone.text = "ZONE: ORBIT +%dm (INERTIAL)" % int(absf(py) * 0.5)
		elif py > 28.0:
			lbl_zone.text = "ZONE: CAVERN -%dm (ROCK)" % int(py * 0.5)
		else:
			lbl_zone.text = "ZONE: SURFACE HORIZON (ANCHORED)"
		lbl_speed.text = "VEL:%d u/s | SWARM:%d | HOST:%d" % [spd, GameState.fleet_count, GameState.hostiles_active]

	var changed = false
	for i in range(log_entries.size() - 1, -1, -1):
		log_entries[i]["life"] -= delta
		if log_entries[i]["life"] <= 0.0:
			log_entries.remove_at(i)
			changed = true
	if changed:
		_refresh_log_ui()

func _on_viewport_resized() -> void:
	var vp = get_viewport().get_visible_rect().size
	var narrow = vp.x < 780.0

	top_left_panel.position = Vector2(8, 8)
	top_left_panel.size = Vector2(minf(vp.x - 16.0, 520.0 if not narrow else vp.x - 16.0), 0)

	var tr_w = minf(vp.x * 0.44, 520.0) if not narrow else (vp.x - 16.0)
	top_right_flow.size = Vector2(tr_w, 44.0)
	if narrow:
		top_right_flow.position = Vector2(8.0, top_left_panel.position.y + maxf(94.0, top_left_panel.size.y) + 8.0)
		top_right_flow.alignment = FlowContainer.ALIGNMENT_BEGIN
	else:
		top_right_flow.position = Vector2(vp.x - tr_w - 8.0, 8.0)
		top_right_flow.alignment = FlowContainer.ALIGNMENT_END

	var bar_w = clampf(vp.x - (340.0 if not narrow else 16.0), 300.0, 920.0)
	bottom_bar.size = Vector2(bar_w, 86.0)
	if narrow:
		bottom_bar.position = Vector2((vp.x - bar_w) * 0.5, vp.y - 94.0)
	else:
		bottom_bar.position = Vector2(maxf(12.0, (vp.x - 310.0 - bar_w) * 0.5), vp.y - 94.0)

	telemetry_panel.visible = not narrow
	_position_telemetry()
	_layout_tech_modal()
	_update_touch_pad_visibility()

func _position_telemetry() -> void:
	if not telemetry_panel or not telemetry_panel.visible:
		return
	var vp = get_viewport().get_visible_rect().size
	var h = clampf(telemetry_panel.get_combined_minimum_size().y, 88.0, 140.0)
	telemetry_panel.size = Vector2(284.0, h)
	telemetry_panel.position = Vector2(vp.x - 294.0, vp.y - h - 10.0)

func _layout_tech_modal() -> void:
	var vp = get_viewport().get_visible_rect().size
	var mw = minf(vp.x - 16.0, 860.0)
	var mh = minf(vp.y - 36.0, 620.0)
	tech_modal.size = Vector2(mw, mh)
	tech_modal.position = Vector2((vp.x - mw) * 0.5, (vp.y - mh) * 0.5)

func _update_touch_pad_visibility() -> void:
	var vp = get_viewport().get_visible_rect().size
	var show_pad = (not tech_modal.visible) and (force_touch_pad or OS.has_feature("mobile") or vp.x < 780.0)
	touch_overlay.visible = show_pad
	if show_pad:
		touch_overlay.position = Vector2(10.0, vp.y - 230.0)

func is_blocking_world_input() -> bool:
	if tech_modal.visible:
		return true
	var mp = get_viewport().get_mouse_position()
	for p in [top_left_panel, top_right_flow, bottom_bar, telemetry_panel]:
		if p and p.visible and p.get_global_rect().has_point(mp):
			return true
	if touch_overlay.visible and Rect2(touch_overlay.position, Vector2(210, 140)).has_point(mp):
		return true
	return false
