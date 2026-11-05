extends CanvasLayer

# STAR REPLICA: AUTOMA - ミニマリスト＆ノンバーバル (文字を使わない) 洗練Sci-Fi UI
# コントローラー/1タップ操作対応 ＆ アイコンピクトグラム駆動

# 左上ミニマルステータス
var fe_label: Label
var cu_label: Label
var ti_label: Label
var si_label: Label
var he3_label: Label
var plasma_label: Label
var ice_label: Label
var dm_label: Label
var nt_label: Label
var hp_bar: ProgressBar
var shield_bar: ProgressBar
var power_bar: ProgressBar
var fleet_bar: ProgressBar
var fleet_lbl: Label

# 下部ツールセレクター
var tool_bar: HBoxContainer
var tool_buttons: Dictionary = {}
var build_mode_indicator: Control
var build_guide_label: Label
var last_synced_tool: String = "none"

# 警報アイコン
var alert_rect: TextureRect
var alert_timer: float = 0.0

# 目標・導線 (Mission Objective Flow)
var objective_panel: PanelContainer
var objective_label: Label
var objective_anim_timer: float = 0.0

# 素材不足アラート
var missing_panel: PanelContainer
var missing_label: Label
var missing_timer: float = 0.0

# 画面外天体ナビ・ロックオン描画オーバーレイ
var nav_overlay: Control
var hud_anim_time: float = 0.0

# メガストラクチャー・ミニマルパレット
var mega_panel: Panel
var is_mega_open: bool = false

var grid_manager: Node2D = null
var main_node: Node2D = null

func _ready() -> void:
	main_node = get_parent()
	grid_manager = get_parent().get_node_or_null("GridManager")
	
	build_minimal_ui()
	
	GameState.resource_changed.connect(_on_resource_changed)
	GameState.fleet_changed.connect(_on_fleet_changed)
	GameState.player_health_changed.connect(_on_player_health_changed)
	GameState.raid_alert.connect(_on_raid_alert)
	GameState.quest_updated.connect(_on_quest_updated)
	GameState.quest_completed.connect(_on_quest_completed)
	
	_update_objective_text()

func _process(delta: float) -> void:
	hud_anim_time += delta
	_update_tool_badges()
	_update_objective_text()
	
	if nav_overlay:
		nav_overlay.queue_redraw()
		
	if missing_timer > 0.0:
		missing_timer -= delta
		if missing_panel:
			missing_panel.visible = (missing_timer > 0.0)

	if grid_manager:
		var cur_tool = grid_manager.selected_tool
		if cur_tool != last_synced_tool:
			last_synced_tool = cur_tool
			_sync_tool_highlights()
			_update_build_mode_visuals()

	if power_bar:
		power_bar.value = GameState.power_ratio * 100.0
		
	if alert_timer > 0.0:
		alert_timer -= delta
		if alert_rect:
			alert_rect.visible = (int(alert_timer * 6.0) % 2 == 0)
			if alert_timer <= 0.0: alert_rect.visible = false

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		# Tab: ビルドモード切替 (コントローラーLB相当の1キー操作)
		if event.keycode == KEY_TAB:
			toggle_build_mode()
		elif event.keycode == KEY_1: _select_tool_by_id("miner")
		elif event.keycode == KEY_2: _select_tool_by_id("belt")
		elif event.keycode == KEY_3: _select_tool_by_id("smelter")
		elif event.keycode == KEY_4: _select_tool_by_id("assembler")
		elif event.keycode == KEY_5: _select_tool_by_id("mass_driver")
		elif event.keycode == KEY_6: _select_tool_by_id("depot")
		elif event.keycode == KEY_7: _select_tool_by_id("turret")
		elif event.keycode == KEY_8: _select_tool_by_id("solar")
		elif event.keycode == KEY_9: _select_tool_by_id("geothermal")
		elif event.keycode == KEY_0: _select_tool_by_id("demolish")

func toggle_build_mode() -> void:
	if not grid_manager: return
	if grid_manager.is_build_mode:
		grid_manager.select_tool("none")
	else:
		grid_manager.select_tool("miner")
	_update_build_mode_visuals()

func _update_build_mode_visuals() -> void:
	if not grid_manager: return
	var is_bm = grid_manager.is_build_mode
	if build_mode_indicator:
		build_mode_indicator.modulate = Color(0.0, 2.5, 3.0) if is_bm else Color(0.4, 0.4, 0.4, 0.5)
	if build_guide_label:
		build_guide_label.visible = is_bm

func build_minimal_ui() -> void:
	# 共通透明Sci-Fiスタイル
	var sb_slot = StyleBoxFlat.new()
	sb_slot.bg_color = Color(0.05, 0.08, 0.14, 0.85)
	sb_slot.border_color = Color(0.0, 0.85, 1.0, 0.5)
	sb_slot.set_border_width_all(1)
	sb_slot.set_corner_radius_all(3)

	# ========================================================
	# 0. 全画面ナビゲーション・ロックオン描画オーバーレイ
	# ========================================================
	nav_overlay = Control.new()
	nav_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	nav_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nav_overlay.draw.connect(_on_nav_overlay_draw)
	add_child(nav_overlay)

	# ========================================================
	# 1. 左上: 超ミニマル・ピクトグラムステータス
	# ========================================================
	var tl_container = VBoxContainer.new()
	tl_container.position = Vector2(20, 16)
	tl_container.add_theme_constant_override("separation", 6)
	add_child(tl_container)

	# 資源行 (アイコン＋数字のみ)
	var res_hbox = HBoxContainer.new()
	res_hbox.add_theme_constant_override("separation", 12)
	tl_container.add_child(res_hbox)

	fe_label = create_res_badge(res_hbox, "res://assets/ui/fe.png", str(GameState.resources["Fe"]), Color(0.3, 0.85, 1.0))
	cu_label = create_res_badge(res_hbox, "res://assets/ui/cu.png", str(GameState.resources["Cu"]), Color(1.0, 0.65, 0.2))
	ti_label = create_res_badge(res_hbox, "res://assets/ui/ti.png", str(GameState.resources["Ti"]), Color(0.85, 0.45, 1.0))
	si_label = create_res_badge(res_hbox, "res://assets/ui/si.png", str(GameState.resources["Si"]), Color(0.2, 1.0, 0.7))
	
	# 宇宙天体固有資源 (月He3, 太陽Plasma, 彗星Ice, 特異点DarkMatter, パルサーNeutronium)
	he3_label = create_res_badge(res_hbox, "res://assets/ui/res_he3.png", str(GameState.resources.get("He3", 0)), Color(0.2, 0.9, 1.0))
	plasma_label = create_res_badge(res_hbox, "res://assets/ui/res_plasma.png", str(GameState.resources.get("Plasma", 0)), Color(1.0, 0.75, 0.2))
	ice_label = create_res_badge(res_hbox, "res://assets/ui/res_ice.png", str(GameState.resources.get("Ice", 0)), Color(0.4, 0.9, 1.0))
	dm_label = create_res_badge(res_hbox, "res://assets/ui/res_darkmatter.png", str(GameState.resources.get("DarkMatter", 0)), Color(0.8, 0.4, 1.0))
	nt_label = create_res_badge(res_hbox, "res://assets/ui/res_neutronium.png", str(GameState.resources.get("Neutronium", 0)), Color(0.2, 1.0, 0.8))

	# 自機HP＆シールド極細デュアルバー
	var hp_vbox = VBoxContainer.new()
	hp_vbox.add_theme_constant_override("separation", 2)
	tl_container.add_child(hp_vbox)

	shield_bar = ProgressBar.new()
	shield_bar.custom_minimum_size = Vector2(180, 4)
	shield_bar.value = 100.0
	shield_bar.show_percentage = false
	shield_bar.modulate = Color(0.0, 1.8, 2.8)
	hp_vbox.add_child(shield_bar)

	hp_bar = ProgressBar.new()
	hp_bar.custom_minimum_size = Vector2(180, 5)
	hp_bar.value = 100.0
	hp_bar.show_percentage = false
	hp_bar.modulate = Color(0.2, 2.0, 0.6)
	hp_vbox.add_child(hp_bar)

	# 電力＆スウォーム艦隊
	var stat_hbox = HBoxContainer.new()
	stat_hbox.add_theme_constant_override("separation", 14)
	tl_container.add_child(stat_hbox)

	var p_hbox = HBoxContainer.new()
	var p_ico = TextureRect.new()
	p_ico.texture = load("res://assets/ui/energy.png")
	p_ico.custom_minimum_size = Vector2(14, 14)
	p_ico.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	p_hbox.add_child(p_ico)
	power_bar = ProgressBar.new()
	power_bar.custom_minimum_size = Vector2(65, 5)
	power_bar.value = 100.0
	power_bar.show_percentage = false
	power_bar.modulate = Color(1.0, 0.85, 0.2)
	p_hbox.add_child(power_bar)
	stat_hbox.add_child(p_hbox)

	var f_hbox = HBoxContainer.new()
	var f_ico = TextureRect.new()
	f_ico.texture = load("res://assets/sprites/fleet_fighter.png")
	f_ico.custom_minimum_size = Vector2(14, 14)
	f_ico.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	f_hbox.add_child(f_ico)
	fleet_lbl = Label.new()
	fleet_lbl.text = "0"
	fleet_lbl.add_theme_font_size_override("font_size", 10)
	fleet_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	f_hbox.add_child(fleet_lbl)
	stat_hbox.add_child(f_hbox)

	# ========================================================
	# 2. 上部中央: ピクトグラム・コントロールバー (文字ゼロ)
	# ========================================================
	var tc_hbox = HBoxContainer.new()
	tc_hbox.position = Vector2(620, 16)
	tc_hbox.add_theme_constant_override("separation", 8)
	add_child(tc_hbox)

	# ドクトリン3種ピクトグラム [回収 / 増殖 / 総攻撃]
	var btn_h = create_icon_btn("res://assets/ui/tool_pick.png", "HARVEST", func(): GameState.set_fleet_doctrine("HARVEST"))
	var btn_m = create_icon_btn("res://assets/ui/item_drone_unit.png", "MULTIPLY", func(): GameState.set_fleet_doctrine("MULTIPLY"))
	var btn_a = create_icon_btn("res://assets/sprites/hostile_fighter.png", "ASSAULT", func(): GameState.set_fleet_doctrine("ASSAULT"))
	btn_a.modulate = Color(2.5, 0.5, 0.5)
	tc_hbox.add_child(btn_h)
	tc_hbox.add_child(btn_m)
	tc_hbox.add_child(btn_a)

	var sep = VSeparator.new()
	tc_hbox.add_child(sep)

	# カメラ自機復帰 ＆ 全体マップピクトグラム
	var btn_snap = create_icon_btn("res://assets/sprites/player_core_sheet.png", "SNAP_CAMERA", func():
		if main_node and main_node.has_method("snap_camera_to_player"): main_node.snap_camera_to_player()
	)
	var btn_map = create_icon_btn("res://assets/environment/planet_large.png", "MAP", func():
		if main_node and main_node.has_method("toggle_map_view"): main_node.toggle_map_view()
	)
	tc_hbox.add_child(btn_snap)
	tc_hbox.add_child(btn_map)

	# クイックセーブピクトグラム
	var btn_save = create_icon_btn("res://assets/ui/circuit.png" if ResourceLoader.exists("res://assets/ui/circuit.png") else "res://assets/ui/item_circuit.png", "SAVE", func():
		SaveManager.save_game(false)
	)
	tc_hbox.add_child(btn_save)

	# ========================================================
	# 2.5 上部中央: ミニマル目標導線バッジ (Current Objective Flow)
	# ========================================================
	objective_panel = PanelContainer.new()
	objective_panel.position = Vector2(600, 56)
	objective_panel.custom_minimum_size = Vector2(300, 26)
	var sb_obj = StyleBoxFlat.new()
	sb_obj.bg_color = Color(0.04, 0.08, 0.16, 0.85)
	sb_obj.border_color = Color(0.0, 1.8, 2.5, 0.6)
	sb_obj.set_border_width_all(1)
	sb_obj.set_corner_radius_all(3)
	objective_panel.add_theme_stylebox_override("panel", sb_obj)

	objective_label = Label.new()
	objective_label.text = "[ ⛏️ ➔ 💎 Fe: 0 / 40 ]"
	objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	objective_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	objective_label.add_theme_font_size_override("font_size", 10)
	objective_label.add_theme_color_override("font_color", Color(0.0, 2.2, 2.8))
	objective_panel.add_child(objective_label)
	add_child(objective_panel)

	# 素材不足警告バッジ (画面中央)
	missing_panel = PanelContainer.new()
	missing_panel.position = Vector2(680, 480)
	missing_panel.custom_minimum_size = Vector2(160, 32)
	var sb_miss = StyleBoxFlat.new()
	sb_miss.bg_color = Color(0.18, 0.04, 0.04, 0.9)
	sb_miss.border_color = Color(2.5, 0.3, 0.3, 0.8)
	sb_miss.set_border_width_all(1)
	sb_miss.set_corner_radius_all(3)
	missing_panel.add_theme_stylebox_override("panel", sb_miss)

	missing_label = Label.new()
	missing_label.text = "⚠️ INSUFFICIENT MATERIAL"
	missing_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	missing_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	missing_label.add_theme_font_size_override("font_size", 10)
	missing_label.add_theme_color_override("font_color", Color(2.5, 0.6, 0.6))
	missing_panel.add_child(missing_label)
	missing_panel.visible = false
	add_child(missing_panel)

	# ========================================================
	# 3. 下部中央: ノンバーバル・スリムツールパレット (コントローラーLB/RB対応)
	# ========================================================
	var bc_container = HBoxContainer.new()
	bc_container.position = Vector2(430, 840)
	bc_container.add_theme_constant_override("separation", 6)
	add_child(bc_container)

	# LB ガイドバッジ
	var lb_lbl = Label.new()
	lb_lbl.text = "LB"
	lb_lbl.add_theme_font_size_override("font_size", 9)
	lb_lbl.add_theme_color_override("font_color", Color(0.0, 0.8, 1.0, 0.5))
	lb_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bc_container.add_child(lb_lbl)

	# ビルドモードON/OFF表示インジケータ
	build_mode_indicator = Panel.new()
	build_mode_indicator.custom_minimum_size = Vector2(6, 42)
	build_mode_indicator.modulate = Color(0.4, 0.4, 0.4, 0.5)
	bc_container.add_child(build_mode_indicator)

	var tools = [
		{"id": "miner", "icon": "tool_drill"},
		{"id": "belt", "icon": "tool_belt"},
		{"id": "smelter", "icon": "tool_smelter"},
		{"id": "assembler", "icon": "tool_assembler"},
		{"id": "mass_driver", "icon": "tool_mass_driver"},
		{"id": "depot", "icon": "tool_depot"},
		{"id": "turret", "icon": "tool_turret"},
		{"id": "solar", "icon": "tool_solar"},
		{"id": "geothermal", "icon": "tool_geothermal"},
		{"id": "demolish", "icon": "tool_demolish"}
	]

	for t in tools:
		var slot_p = PanelContainer.new()
		slot_p.custom_minimum_size = Vector2(40, 42)
		slot_p.add_theme_stylebox_override("panel", sb_slot)

		var b = Button.new()
		b.icon = load("res://assets/ui/%s.png" % t["icon"])
		b.flat = true
		b.custom_minimum_size = Vector2(38, 40)
		b.pressed.connect(func(): _select_tool_by_id(t["id"]))
		slot_p.add_child(b)

		# 所持数バッジ（数字のみ）
		var count_lbl = Label.new()
		count_lbl.text = "0"
		count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count_lbl.position = Vector2(10, 24)
		count_lbl.size = Vector2(26, 14)
		count_lbl.add_theme_font_size_override("font_size", 9)
		count_lbl.add_theme_color_override("font_color", Color(0.2, 1.0, 0.6))
		slot_p.add_child(count_lbl)

		bc_container.add_child(slot_p)
		tool_buttons[t["id"]] = {"btn": b, "lbl": count_lbl, "panel": slot_p}

	# RB ガイドバッジ
	var rb_lbl = Label.new()
	rb_lbl.text = "RB"
	rb_lbl.add_theme_font_size_override("font_size", 9)
	rb_lbl.add_theme_color_override("font_color", Color(0.0, 0.8, 1.0, 0.5))
	rb_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bc_container.add_child(rb_lbl)

	# メガストラクチャー展開ボタン (右端)
	var mega_btn = Button.new()
	mega_btn.icon = load("res://assets/ui/icon_elevator.png")
	mega_btn.custom_minimum_size = Vector2(42, 42)
	mega_btn.pressed.connect(toggle_mega_palette)
	bc_container.add_child(mega_btn)

	# ビルド操作ガイド（ノンバーバル極小ピクトグラム）
	build_guide_label = Label.new()
	build_guide_label.text = "[RT/A] 🔨    [LT/B] ❌"
	build_guide_label.position = Vector2(720, 816)
	build_guide_label.add_theme_font_size_override("font_size", 10)
	build_guide_label.add_theme_color_override("font_color", Color(0.0, 1.8, 2.5, 0.75))
	build_guide_label.visible = false
	add_child(build_guide_label)

	# 4. 空爆襲来警告ピクトグラム (中央上部)
	alert_rect = TextureRect.new()
	alert_rect.texture = load("res://assets/sprites/corrupted_bomber.png")
	alert_rect.position = Vector2(780, 75)
	alert_rect.custom_minimum_size = Vector2(40, 40)
	alert_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	alert_rect.modulate = Color(3.0, 0.3, 0.3)
	alert_rect.visible = false
	add_child(alert_rect)

	# 5. メガストラクチャー・ミニマルパレット構築
	_build_minimal_mega_palette(sb_slot)

	# 6. 右下: 極ミニマル操作ガイド (半透明)
	var guide_box = PanelContainer.new()
	guide_box.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	guide_box.anchor_left = 1.0
	guide_box.anchor_right = 1.0
	guide_box.anchor_top = 1.0
	guide_box.anchor_bottom = 1.0
	guide_box.offset_left = -340.0
	guide_box.offset_top = -24.0
	guide_box.offset_right = -16.0
	guide_box.offset_bottom = -6.0
	var sb_guide = StyleBoxFlat.new()
	sb_guide.bg_color = Color(0.02, 0.04, 0.07, 0.6)
	sb_guide.set_corner_radius_all(3)
	guide_box.add_theme_stylebox_override("panel", sb_guide)
	var guide_lbl = Label.new()
	guide_lbl.text = "WASD/🎮: MOVE | L-CLICK: MINE | TAB/Y: BUILD | SHIFT: BRAKE"
	guide_lbl.add_theme_font_size_override("font_size", 9)
	guide_lbl.add_theme_color_override("font_color", Color(0.35, 0.65, 0.8, 0.65))
	guide_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	guide_box.add_child(guide_lbl)
	add_child(guide_box)

func create_res_badge(parent: Node, icon_p: String, init_v: String, col: Color) -> Label:
	var h = HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	
	var ico = TextureRect.new()
	ico.texture = load(icon_p)
	ico.custom_minimum_size = Vector2(16, 16)
	ico.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	h.add_child(ico)

	var lbl = Label.new()
	lbl.text = init_v
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", col)
	h.add_child(lbl)

	parent.add_child(h)
	return lbl

func create_icon_btn(icon_p: String, _tip: String, on_click: Callable) -> Button:
	var b = Button.new()
	if ResourceLoader.exists(icon_p):
		b.icon = load(icon_p)
	b.custom_minimum_size = Vector2(34, 34)
	b.pressed.connect(on_click)
	return b

func _build_minimal_mega_palette(sb_slot: StyleBoxFlat) -> void:
	mega_panel = Panel.new()
	mega_panel.position = Vector2(660, 765)
	mega_panel.size = Vector2(280, 68)
	mega_panel.visible = false
	add_child(mega_panel)

	var mh = HBoxContainer.new()
	mh.position = Vector2(10, 10)
	mh.add_theme_constant_override("separation", 10)
	mega_panel.add_child(mh)

	var mega_list = [
		{"id": "elevator", "icon": "icon_elevator"},
		{"id": "dyson", "icon": "icon_dyson"},
		{"id": "citadel", "icon": "icon_citadel"},
		{"id": "warpgate", "icon": "icon_warpgate"}
	]
	for m in mega_list:
		var slot = PanelContainer.new()
		slot.custom_minimum_size = Vector2(46, 46)
		slot.add_theme_stylebox_override("panel", sb_slot)

		var b = Button.new()
		b.icon = load("res://assets/ui/%s.png" % m["icon"])
		b.custom_minimum_size = Vector2(44, 44)
		b.pressed.connect(func():
			GameState.start_megastructure(m["id"])
			toggle_mega_palette()
		)
		slot.add_child(b)
		mh.add_child(slot)

func toggle_mega_palette() -> void:
	is_mega_open = not is_mega_open
	if mega_panel: mega_panel.visible = is_mega_open
	AudioSynth.play_synth("click")

func _sync_tool_highlights() -> void:
	if not grid_manager: return
	for tid in tool_buttons.keys():
		var item = tool_buttons[tid]
		if tid == grid_manager.selected_tool:
			item["panel"].modulate = Color(0.0, 2.5, 3.0)
		else:
			item["panel"].modulate = Color.WHITE

func _select_tool_by_id(tool_id: String) -> void:
	if grid_manager:
		grid_manager.select_tool(tool_id)
		_sync_tool_highlights()
		_update_build_mode_visuals()

func _update_tool_badges() -> void:
	for tid in tool_buttons.keys():
		var item = tool_buttons[tid]
		if tid == "demolish":
			item["lbl"].text = ""
			continue
		var count = GameState.items.get(tid, 0)
		item["lbl"].text = str(count)
		if count > 0:
			item["lbl"].add_theme_color_override("font_color", Color(0.2, 1.0, 0.6))
		else:
			item["lbl"].add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))

func _on_resource_changed(type: String, amount: int) -> void:
	match type:
		"Fe": if fe_label: fe_label.text = str(amount)
		"Cu": if cu_label: cu_label.text = str(amount)
		"Ti": if ti_label: ti_label.text = str(amount)
		"Si": if si_label: si_label.text = str(amount)
		"He3": if he3_label: he3_label.text = str(amount)
		"Plasma": if plasma_label: plasma_label.text = str(amount)
		"Ice": if ice_label: ice_label.text = str(amount)
		"DarkMatter": if dm_label: dm_label.text = str(amount)
		"Neutronium": if nt_label: nt_label.text = str(amount)

func _on_fleet_changed(current: int, _max_val: int) -> void:
	if fleet_lbl: fleet_lbl.text = str(current)

func _on_player_health_changed(hp: float, max_hp: float, shield: float, max_shield: float) -> void:
	if hp_bar:
		hp_bar.max_value = max_hp
		hp_bar.value = hp
	if shield_bar:
		shield_bar.max_value = max_shield
		shield_bar.value = shield

func _on_raid_alert(_is_active: bool, _msg: String) -> void:
	if alert_rect:
		alert_rect.visible = true
		alert_timer = 4.0

# ========================================================
# 目標・導線 (Mission Flow) ＆ 画面外天体ナビゲーション
# ========================================================
func _on_quest_updated(_idx: int, _info: Dictionary) -> void:
	_update_objective_text()
	AudioSynth.play_synth("build")

func _on_quest_completed(_idx: int, _info: Dictionary) -> void:
	AudioSynth.play_synth("victory")
	if objective_panel:
		objective_panel.modulate = Color(0.2, 2.5, 0.6)
		get_tree().create_timer(0.6).timeout.connect(func():
			if objective_panel: objective_panel.modulate = Color.WHITE
		)

func show_missing_res_alert(res_name: String) -> void:
	if missing_panel and missing_label:
		missing_label.text = "⚠️ NEED: %s" % res_name
		missing_panel.visible = true
		missing_timer = 1.2
		AudioSynth.play_synth("alert")

func _update_objective_text() -> void:
	if not objective_label: return
	if GameState.quest_index >= GameState.quest_list.size():
		objective_label.text = "★ SYSTEM LIBERATED: ALL OBJECTIVES COMPLETE ★"
		objective_label.add_theme_color_override("font_color", Color(0.2, 2.2, 0.8))
		return
		
	var q = GameState.quest_list[GameState.quest_index]
	var txt = ""
	match q.get("req_type"):
		"resource":
			var cur = GameState.resources.get(q.get("target_res", "Fe"), 0)
			txt = "%s: %d / %d" % [q.get("short", ""), cur, q.get("target_val", 0)]
		"drone":
			txt = "%s (%d/%d)" % [q.get("short", ""), GameState.attached_drones, q.get("target_val", 1)]
		"building":
			txt = "%s" % [q.get("short", "")]
		"fleet":
			txt = "%s (%d/%d)" % [q.get("short", ""), GameState.fleet_count, q.get("target_val", 100)]
		"celestial_any":
			var cur_p = GameState.resources.get("Plasma", 0) + GameState.resources.get("Ice", 0)
			txt = "%s (%d/%d)" % [q.get("short", ""), cur_p, q.get("target_val", 5)]
		"megastructure":
			txt = "%s" % [q.get("short", "")]
		"liberation":
			txt = "%s (HP: %.0f)" % [q.get("short", ""), GameState.hostile_core_health]
			
	objective_label.text = "[ %s ]" % txt

func _on_nav_overlay_draw() -> void:
	if not nav_overlay or not main_node: return
	var camera = main_node.get_node_or_null("Camera2D")
	var player = main_node.get_node_or_null("Player")
	if not camera or not player: return

	var vp_size = nav_overlay.size
	var cam_p = camera.global_position
	var zoom = camera.zoom
	var half_w = (vp_size.x * 0.5) / zoom.x
	var half_h = (vp_size.y * 0.5) / zoom.y
	var screen_center = vp_size * 0.5

	# ナビ対象天体リスト
	var targets: Array[Dictionary] = [
		{"name": "HOME", "pos": Vector2(800.0, 1070.0), "col": Color(0.2, 0.8, 1.0), "icon": "🌍"},
		{"name": "SUN", "pos": Vector2(800.0, -850.0), "col": Color(1.0, 0.7, 0.1), "icon": "☀️"},
		{"name": "SINGULARITY", "pos": Vector2(2300.0, -350.0), "col": Color(0.8, 0.3, 1.0), "icon": "🕳️"},
		{"name": "PULSAR", "pos": Vector2(-700.0, -350.0), "col": Color(0.1, 1.0, 0.8), "icon": "⚡"},
		{"name": "BOSS CORE", "pos": Vector2(1380.0, 150.0), "col": Color(1.0, 0.2, 0.2), "icon": "👾"}
	]
	
	if grid_manager and not grid_manager.moon_body.is_empty():
		targets.append({"name": "LUNA", "pos": grid_manager.moon_body.get("pos", Vector2.ZERO), "col": Color(0.3, 0.9, 1.0), "icon": "🌙"})
	if grid_manager and not grid_manager.comet_body.is_empty():
		targets.append({"name": "COMET", "pos": grid_manager.comet_body.get("pos", Vector2.ZERO), "col": Color(0.4, 0.9, 1.0), "icon": "☄️"})

	for t in targets:
		var t_pos: Vector2 = t["pos"]
		var diff = t_pos - cam_p
		var in_screen = (abs(diff.x) < half_w - 50.0 and abs(diff.y) < half_h - 50.0)
		var p_dist = player.global_position.distance_to(t_pos)

		if in_screen:
			# 画面内：近接採掘可能な場合、ロックオンレティクル描画
			if p_dist < 450.0:
				var screen_tpos = screen_center + diff * zoom
				var ret_col = t["col"]
				nav_overlay.draw_arc(screen_tpos, 32.0, 0, TAU, 24, ret_col * Color(1, 1, 1, 0.6), 1.5)
				nav_overlay.draw_line(screen_tpos - Vector2(38, 0), screen_tpos - Vector2(24, 0), ret_col, 2.0)
				nav_overlay.draw_line(screen_tpos + Vector2(24, 0), screen_tpos + Vector2(38, 0), ret_col, 2.0)
				nav_overlay.draw_line(screen_tpos - Vector2(0, 38), screen_tpos - Vector2(0, 24), ret_col, 2.0)
				nav_overlay.draw_line(screen_tpos + Vector2(0, 24), screen_tpos + Vector2(0, 38), ret_col, 2.0)
				nav_overlay.draw_string(ThemeDB.fallback_font, screen_tpos + Vector2(-36, 46), "⌖ LOCK-ON: %s" % t["name"], HORIZONTAL_ALIGNMENT_CENTER, -1, 9, ret_col)
		else:
			# 画面外：画面端にポインターアイコン＋距離を描画
			var dir = diff.normalized()
			# 画面四辺の境界との交点を計算
			var edge_margin = 38.0
			var max_dx = screen_center.x - edge_margin
			var max_dy = screen_center.y - edge_margin
			var scale_x = max_dx / maxf(0.001, abs(dir.x))
			var scale_y = max_dy / maxf(0.001, abs(dir.y))
			var scale_factor = minf(scale_x, scale_y)
			var marker_p = screen_center + dir * scale_factor
			if marker_p.y < 54.0 and abs(marker_p.x - screen_center.x) < 170.0:
				marker_p.y = 54.0

			var m_col: Color = t["col"]
			nav_overlay.draw_circle(marker_p, 4.0, m_col)
			nav_overlay.draw_line(marker_p, marker_p + dir * 8.0, m_col, 2.0)
			
			var dist_km = p_dist / 100.0
			var dist_str = "%.1fkm" % dist_km if dist_km >= 1.0 else "%.0fm" % p_dist
			var lbl = "%s %s" % [t["icon"], dist_str]
			nav_overlay.draw_string(ThemeDB.fallback_font, marker_p - Vector2(24, 8), lbl, HORIZONTAL_ALIGNMENT_CENTER, -1, 9, m_col * Color(1.5, 1.5, 1.5, 0.9))

	# ========================================================
	# 最優先: 現在のクエスト目標地点へのオフスクリーン矢印誘導
	# ========================================================
	if grid_manager and grid_manager.has_method("get_current_mission_waypoint_info"):
		var m_info = grid_manager.get_current_mission_waypoint_info()
		if not m_info.is_empty():
			var m_pos: Vector2 = m_info["pos"]
			var m_diff = m_pos - cam_p
			var m_in_screen = (abs(m_diff.x) < half_w - 40.0 and abs(m_diff.y) < half_h - 40.0)
			var m_pdist = player.global_position.distance_to(m_pos)
			var m_col: Color = m_info.get("color", Color(0.0, 2.5, 3.0))

			if not m_in_screen:
				# 画面外：画面端にパルスするターゲットマーカーを描画
				var dir = m_diff.normalized()
				var edge_margin = 46.0
				var max_dx = screen_center.x - edge_margin
				var max_dy = screen_center.y - edge_margin
				var scale_factor = minf(max_dx / maxf(0.001, abs(dir.x)), max_dy / maxf(0.001, abs(dir.y)))
				var marker_p = screen_center + dir * scale_factor

				var pulse = (sin(hud_anim_time * 6.0) * 0.5 + 0.5)
				var p_col = m_col * Color(1.0 + pulse * 1.5, 1.0 + pulse * 1.5, 1.0 + pulse * 1.5, 1.0)
				
				# 菱形アイコン
				var sz = 7.0 + pulse * 3.0
				var poly = PackedVector2Array([
					marker_p + Vector2(0, -sz),
					marker_p + Vector2(sz, 0),
					marker_p + Vector2(0, sz),
					marker_p + Vector2(-sz, 0)
				])
				nav_overlay.draw_colored_polygon(poly, p_col)
				nav_overlay.draw_polyline(poly, Color.WHITE, 1.5)
				nav_overlay.draw_line(marker_p, marker_p + dir * 12.0, Color.WHITE, 2.0)

				var m_dist_km = m_pdist / 100.0
				var m_dist_str = "%.1fkm" % m_dist_km if m_dist_km >= 1.0 else "%.0fm" % m_pdist
				var m_txt = "🎯 %s [%s]" % [m_info.get("name", "MISSION"), m_dist_str]
				nav_overlay.draw_string(ThemeDB.fallback_font, marker_p - Vector2(40, 14), m_txt, HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color(2.5, 2.5, 1.2))
