extends CanvasLayer

# STAR REPLICA: AUTOMA - ミニマリスト＆ノンバーバル (文字を使わない) 洗練Sci-Fi UI
# コントローラー/1タップ操作対応 ＆ アイコンピクトグラム駆動 ＆ プログレッシブ・ディスクロージャー

# 上部レスポンシブバー＆資源バッジコンテナ
var top_bar_node: MarginContainer
var res_badge_containers: Dictionary = {}

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
var stat_row_node: HBoxContainer
var right_top_buttons: HBoxContainer

# 画面左側ズームクラスタ
var zoom_cluster_node: VBoxContainer

# 下部ツールセレクター
var tool_bar: HBoxContainer
var tool_buttons: Dictionary = {}
var build_mode_indicator: Control
var build_guide_label: Label
var last_synced_tool: String = "none"
var mega_btn_node: Button

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
var player_node: CharacterBody2D = null

# スマホ・タッチ操作盤 (Virtual Controls)
var vstick_base: Control
var vstick_active: bool = false
var vstick_touch_id: int = -1
var vstick_knob_pos: Vector2 = Vector2.ZERO

var action_cluster_node: Control
var btn_touch_mine: Button
var btn_touch_brake: Button
var btn_touch_build: Button
var btn_touch_drone: Button
var btn_touch_map: Button
var build_bar_panel: PanelContainer

# 休眠探査機・起動ガイダンスオーバーレイ (DORMANT STATE)
var boot_guide_overlay: Control
var boot_prompt_lbl: Label

func _ready() -> void:
	main_node = get_parent()
	grid_manager = get_parent().get_node_or_null("GridManager")
	player_node = get_parent().get_node_or_null("Player")
	
	build_minimal_ui()
	
	GameState.story_phase_changed.connect(_on_story_phase_changed)
	GameState.resource_changed.connect(_on_resource_changed)
	GameState.fleet_changed.connect(_on_fleet_changed)
	GameState.player_health_changed.connect(_on_player_health_changed)
	GameState.raid_alert.connect(_on_raid_alert)
	GameState.quest_updated.connect(_on_quest_updated)
	GameState.quest_completed.connect(_on_quest_completed)
	
	get_tree().root.size_changed.connect(_adjust_responsive_layout)
	_adjust_responsive_layout()
	
	_update_progressive_ui(GameState.story_phase)
	_update_objective_text()

func _on_story_phase_changed(new_phase: int) -> void:
	_update_progressive_ui(new_phase)
	_update_objective_text()

func _process(delta: float) -> void:
	hud_anim_time += delta
	_update_tool_badges()
	_update_objective_text()
	
	if nav_overlay and nav_overlay.visible:
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

	if power_bar and power_bar.is_visible_in_tree():
		power_bar.value = GameState.power_ratio * 100.0
		
	if alert_timer > 0.0:
		alert_timer -= delta
		if alert_rect:
			alert_rect.visible = (int(alert_timer * 6.0) % 2 == 0)
			if alert_timer <= 0.0: alert_rect.visible = false

	# ドローン合体可能時のパルス発光 (DRONEボタン)
	if btn_touch_drone and btn_touch_drone.visible:
		var can_attach = false
		if GameState.attached_drones == 0:
			can_attach = GameState.resources.get("Fe", 0) >= 40
		else:
			can_attach = GameState.resources.get("Fe", 0) >= 30 and GameState.resources.get("Si", 0) >= 15
			
		if can_attach and GameState.attached_drones < GameState.max_attached_drones:
			var pulse = (sin(hud_anim_time * 8.0) * 0.5 + 0.5)
			btn_touch_drone.modulate = Color(1.0 + pulse * 1.5, 2.0 + pulse * 1.5, 1.5 + pulse * 1.5)
		else:
			btn_touch_drone.modulate = Color.WHITE

	# 休眠探査機ガイダンスのパルス点滅
	if boot_guide_overlay and boot_guide_overlay.visible and boot_prompt_lbl:
		var b_pulse = (sin(hud_anim_time * 5.0) * 0.5 + 0.5)
		boot_prompt_lbl.modulate = Color(1.0, 1.0, 1.0, 0.4 + b_pulse * 0.6)

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
	sb_slot.set_corner_radius_all(4)

	# ========================================================
	# 0. 全画面ナビゲーション・ロックオン描画オーバーレイ
	# ========================================================
	nav_overlay = Control.new()
	nav_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	nav_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nav_overlay.draw.connect(_on_nav_overlay_draw)
	add_child(nav_overlay)

	# ========================================================
	# 1. 上部レスポンシブバー (PRESET_TOP_WIDE)
	# ========================================================
	var top_bar = MarginContainer.new()
	top_bar_node = top_bar
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.anchor_left = 0.0
	top_bar.anchor_right = 1.0
	top_bar.anchor_top = 0.0
	top_bar.anchor_bottom = 0.0
	top_bar.offset_left = 12.0
	top_bar.offset_top = 10.0
	top_bar.offset_right = -12.0
	top_bar.offset_bottom = 110.0
	add_child(top_bar)

	var top_vbox = VBoxContainer.new()
	top_vbox.add_theme_constant_override("separation", 4)
	top_bar.add_child(top_vbox)

	# 1行目: 資源バッジ一覧 (9種を中央揃え)
	var res_hbox = HBoxContainer.new()
	res_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	res_hbox.add_theme_constant_override("separation", 6)
	top_vbox.add_child(res_hbox)

	fe_label = create_res_badge(res_hbox, "res://assets/ui/fe.png", str(GameState.resources["Fe"]), Color(0.3, 0.85, 1.0), "Fe")
	cu_label = create_res_badge(res_hbox, "res://assets/ui/cu.png", str(GameState.resources["Cu"]), Color(1.0, 0.65, 0.2), "Cu")
	ti_label = create_res_badge(res_hbox, "res://assets/ui/ti.png", str(GameState.resources["Ti"]), Color(0.85, 0.45, 1.0), "Ti")
	si_label = create_res_badge(res_hbox, "res://assets/ui/si.png", str(GameState.resources["Si"]), Color(0.2, 1.0, 0.7), "Si")
	he3_label = create_res_badge(res_hbox, "res://assets/ui/res_he3.png", str(GameState.resources.get("He3", 0)), Color(0.2, 0.9, 1.0), "He3")
	plasma_label = create_res_badge(res_hbox, "res://assets/ui/res_plasma.png", str(GameState.resources.get("Plasma", 0)), Color(1.0, 0.75, 0.2), "Plasma")
	ice_label = create_res_badge(res_hbox, "res://assets/ui/res_ice.png", str(GameState.resources.get("Ice", 0)), Color(0.4, 0.9, 1.0), "Ice")
	dm_label = create_res_badge(res_hbox, "res://assets/ui/res_darkmatter.png", str(GameState.resources.get("DarkMatter", 0)), Color(0.8, 0.4, 1.0), "DarkMatter")
	nt_label = create_res_badge(res_hbox, "res://assets/ui/res_neutronium.png", str(GameState.resources.get("Neutronium", 0)), Color(0.2, 1.0, 0.8), "Neutronium")

	# 2行目: ステータスバー (左) ＋ 伸縮スペーサー ＋ 操作ボタン (右)
	var stat_row = HBoxContainer.new()
	stat_row_node = stat_row
	stat_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	stat_row.add_theme_constant_override("separation", 8)
	top_vbox.add_child(stat_row)

	var stat_hbox = HBoxContainer.new()
	stat_hbox.add_theme_constant_override("separation", 6)
	stat_row.add_child(stat_hbox)

	var hp_vbox = VBoxContainer.new()
	hp_vbox.add_theme_constant_override("separation", 2)
	stat_hbox.add_child(hp_vbox)

	shield_bar = ProgressBar.new()
	shield_bar.custom_minimum_size = Vector2(90, 4)
	shield_bar.value = 100.0
	shield_bar.show_percentage = false
	shield_bar.modulate = Color(0.0, 1.8, 2.8)
	hp_vbox.add_child(shield_bar)

	hp_bar = ProgressBar.new()
	hp_bar.custom_minimum_size = Vector2(90, 5)
	hp_bar.value = 100.0
	hp_bar.show_percentage = false
	hp_bar.modulate = Color(0.2, 2.0, 0.6)
	hp_vbox.add_child(hp_bar)

	var p_hbox = HBoxContainer.new()
	var p_ico = TextureRect.new()
	p_ico.texture = load("res://assets/ui/energy.png")
	p_ico.custom_minimum_size = Vector2(14, 14)
	p_ico.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	p_hbox.add_child(p_ico)
	power_bar = ProgressBar.new()
	power_bar.custom_minimum_size = Vector2(40, 5)
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

	# 伸縮スペーサー (左側のステータスと右側の操作ボタンを両端に均等配置)
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stat_row.add_child(spacer)

	# 右側: ドクトリン・カメラ・セーブ操作ボタン (文字バッジ式で巨大テクスチャ誤爆防止)
	var right_hbox = HBoxContainer.new()
	right_top_buttons = right_hbox
	right_hbox.alignment = BoxContainer.ALIGNMENT_END
	right_hbox.add_theme_constant_override("separation", 5)
	stat_row.add_child(right_hbox)

	var sb_top_btn = StyleBoxFlat.new()
	sb_top_btn.bg_color = Color(0.04, 0.08, 0.16, 0.85)
	sb_top_btn.border_color = Color(0.0, 1.8, 2.5, 0.6)
	sb_top_btn.set_border_width_all(1)
	sb_top_btn.set_corner_radius_all(4)

	var btn_h = Button.new()
	btn_h.text = "H"
	btn_h.custom_minimum_size = Vector2(26, 24)
	btn_h.add_theme_stylebox_override("normal", sb_top_btn)
	btn_h.add_theme_font_size_override("font_size", 10)
	btn_h.pressed.connect(func(): GameState.set_fleet_doctrine("HARVEST"))
	right_hbox.add_child(btn_h)

	var btn_m = Button.new()
	btn_m.text = "M"
	btn_m.custom_minimum_size = Vector2(26, 24)
	btn_m.add_theme_stylebox_override("normal", sb_top_btn)
	btn_m.add_theme_font_size_override("font_size", 10)
	btn_m.pressed.connect(func(): GameState.set_fleet_doctrine("MULTIPLY"))
	right_hbox.add_child(btn_m)

	var btn_a = Button.new()
	btn_a.text = "A"
	btn_a.custom_minimum_size = Vector2(26, 24)
	var sb_a = sb_top_btn.duplicate()
	sb_a.border_color = Color(2.5, 0.4, 0.4, 0.8)
	btn_a.add_theme_stylebox_override("normal", sb_a)
	btn_a.add_theme_font_size_override("font_size", 10)
	btn_a.add_theme_color_override("font_color", Color(2.5, 0.6, 0.6))
	btn_a.pressed.connect(func(): GameState.set_fleet_doctrine("ASSAULT"))
	right_hbox.add_child(btn_a)

	var btn_snap = Button.new()
	btn_snap.text = "CORE"
	btn_snap.custom_minimum_size = Vector2(36, 24)
	btn_snap.add_theme_stylebox_override("normal", sb_top_btn)
	btn_snap.add_theme_font_size_override("font_size", 9)
	btn_snap.pressed.connect(func(): if main_node and main_node.has_method("snap_camera_to_player"): main_node.snap_camera_to_player())
	right_hbox.add_child(btn_snap)

	var btn_map = Button.new()
	btn_map.text = "MAP"
	btn_map.custom_minimum_size = Vector2(32, 24)
	btn_map.add_theme_stylebox_override("normal", sb_top_btn)
	btn_map.add_theme_font_size_override("font_size", 9)
	btn_map.pressed.connect(func(): if main_node and main_node.has_method("toggle_map_view"): main_node.toggle_map_view())
	right_hbox.add_child(btn_map)

	var btn_save = Button.new()
	btn_save.text = "SAVE"
	btn_save.custom_minimum_size = Vector2(34, 24)
	btn_save.add_theme_stylebox_override("normal", sb_top_btn)
	btn_save.add_theme_font_size_override("font_size", 9)
	btn_save.pressed.connect(func(): SaveManager.save_game(false))
	right_hbox.add_child(btn_save)

	# 3行目: 目標導線バッジ (中央配置)
	var top_row3 = HBoxContainer.new()
	top_row3.alignment = BoxContainer.ALIGNMENT_CENTER
	top_vbox.add_child(top_row3)

	objective_panel = PanelContainer.new()
	objective_panel.custom_minimum_size = Vector2(320, 32)
	var sb_obj = StyleBoxFlat.new()
	sb_obj.bg_color = Color(0.04, 0.08, 0.16, 0.85)
	sb_obj.border_color = Color(0.0, 1.8, 2.5, 0.7)
	sb_obj.set_border_width_all(1)
	sb_obj.set_corner_radius_all(4)
	objective_panel.add_theme_stylebox_override("panel", sb_obj)

	objective_label = Label.new()
	objective_label.text = "[ MISSION: MINE Fe (0 / 40) ]"
	objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	objective_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	objective_label.add_theme_font_size_override("font_size", 13)
	objective_label.add_theme_color_override("font_color", Color(0.0, 2.2, 2.8))
	objective_panel.add_child(objective_label)
	top_row3.add_child(objective_panel)

	# 素材不足警告バッジ (画面中央)
	missing_panel = PanelContainer.new()
	missing_panel.set_anchors_preset(Control.PRESET_CENTER)
	missing_panel.anchor_left = 0.5
	missing_panel.anchor_right = 0.5
	missing_panel.anchor_top = 0.5
	missing_panel.anchor_bottom = 0.5
	missing_panel.offset_left = -90.0
	missing_panel.offset_top = -20.0
	missing_panel.offset_right = 90.0
	missing_panel.offset_bottom = 20.0
	var sb_miss = StyleBoxFlat.new()
	sb_miss.bg_color = Color(0.18, 0.04, 0.04, 0.9)
	sb_miss.border_color = Color(2.5, 0.3, 0.3, 0.8)
	sb_miss.set_border_width_all(1)
	sb_miss.set_corner_radius_all(3)
	missing_panel.add_theme_stylebox_override("panel", sb_miss)

	missing_label = Label.new()
	missing_label.text = "INSUFFICIENT MATERIAL"
	missing_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	missing_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	missing_label.add_theme_font_size_override("font_size", 10)
	missing_label.add_theme_color_override("font_color", Color(2.5, 0.6, 0.6))
	missing_panel.add_child(missing_label)
	missing_panel.visible = false
	add_child(missing_panel)

	# 空爆警告
	# 空爆襲来警告アラートアイコン (中央上部のナビ・ミッション干渉を完全排除し、右上ステータス下に配置)
	alert_rect = TextureRect.new()
	alert_rect.texture = load("res://assets/sprites/corrupted_bomber.png")
	alert_rect.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	alert_rect.anchor_left = 1.0
	alert_rect.anchor_right = 1.0
	alert_rect.anchor_top = 0.0
	alert_rect.anchor_bottom = 0.0
	alert_rect.offset_left = -160.0
	alert_rect.offset_top = 64.0
	alert_rect.offset_right = -124.0
	alert_rect.offset_bottom = 100.0
	alert_rect.custom_minimum_size = Vector2(36, 36)
	alert_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	alert_rect.modulate = Color(3.0, 0.3, 0.3)
	alert_rect.visible = false
	add_child(alert_rect)

	# ========================================================
	# 2. 画面左側: ズームボタンクラスタ (Zoom Buttons)
	# ========================================================
	var zoom_cluster = VBoxContainer.new()
	zoom_cluster_node = zoom_cluster
	zoom_cluster.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	zoom_cluster.anchor_left = 0.0
	zoom_cluster.anchor_top = 0.45
	zoom_cluster.anchor_bottom = 0.45
	zoom_cluster.offset_left = 16.0
	zoom_cluster.offset_top = -60.0
	zoom_cluster.offset_right = 68.0
	zoom_cluster.offset_bottom = 60.0
	zoom_cluster.add_theme_constant_override("separation", 10)
	add_child(zoom_cluster)

	var sb_circle_btn = StyleBoxFlat.new()
	sb_circle_btn.bg_color = Color(0.04, 0.08, 0.15, 0.75)
	sb_circle_btn.border_color = Color(0.0, 1.8, 2.5, 0.6)
	sb_circle_btn.set_border_width_all(1)
	sb_circle_btn.set_corner_radius_all(24)

	var btn_zin = Button.new()
	btn_zin.text = "+"
	btn_zin.custom_minimum_size = Vector2(46, 46)
	btn_zin.add_theme_font_size_override("font_size", 28)
	btn_zin.add_theme_color_override("font_color", Color(0.0, 2.5, 3.0))
	btn_zin.add_theme_stylebox_override("normal", sb_circle_btn)
	btn_zin.pressed.connect(func(): if main_node and main_node.has_method("zoom_in"): main_node.zoom_in())
	zoom_cluster.add_child(btn_zin)

	var btn_zout = Button.new()
	btn_zout.text = "-"
	btn_zout.custom_minimum_size = Vector2(46, 46)
	btn_zout.add_theme_font_size_override("font_size", 28)
	btn_zout.add_theme_color_override("font_color", Color(0.0, 2.5, 3.0))
	btn_zout.add_theme_stylebox_override("normal", sb_circle_btn)
	btn_zout.pressed.connect(func(): if main_node and main_node.has_method("zoom_out"): main_node.zoom_out())
	zoom_cluster.add_child(btn_zout)

	# ========================================================
	# 3. 画面左下: スマホ用バーチャルジョイスティック (Virtual Joystick)
	# ========================================================
	vstick_base = Control.new()
	vstick_base.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	vstick_base.anchor_left = 0.0
	vstick_base.anchor_right = 0.0
	vstick_base.anchor_top = 1.0
	vstick_base.anchor_bottom = 1.0
	vstick_base.offset_left = 12.0
	vstick_base.offset_top = -180.0
	vstick_base.offset_right = 172.0
	vstick_base.offset_bottom = -20.0
	vstick_base.mouse_filter = Control.MOUSE_FILTER_PASS
	vstick_base.draw.connect(_on_vstick_draw)
	vstick_base.gui_input.connect(_on_vstick_gui_input)
	add_child(vstick_base)

	# ========================================================
	# 4. 画面右下: スマホ用アクションボタンクラスタ (Action Button Cluster)
	# ========================================================
	var action_cluster = Control.new()
	action_cluster_node = action_cluster
	action_cluster.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	action_cluster.anchor_left = 1.0
	action_cluster.anchor_right = 1.0
	action_cluster.anchor_top = 1.0
	action_cluster.anchor_bottom = 1.0
	action_cluster.offset_left = -190.0
	action_cluster.offset_top = -210.0
	action_cluster.offset_right = -10.0
	action_cluster.offset_bottom = -10.0
	action_cluster.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(action_cluster)

	# [MINE] 採掘ボタン (大・右下最前面)
	var sb_mine = StyleBoxFlat.new()
	sb_mine.bg_color = Color(0.02, 0.12, 0.22, 0.9)
	sb_mine.border_color = Color(0.0, 2.5, 3.0, 0.95)
	sb_mine.set_border_width_all(2)
	sb_mine.set_corner_radius_all(44)

	btn_touch_mine = Button.new()
	btn_touch_mine.text = "MINE"
	btn_touch_mine.position = Vector2(92, 100)
	btn_touch_mine.custom_minimum_size = Vector2(88, 88)
	btn_touch_mine.add_theme_stylebox_override("normal", sb_mine)
	btn_touch_mine.add_theme_font_size_override("font_size", 16)
	btn_touch_mine.add_theme_color_override("font_color", Color(0.0, 2.5, 3.0))
	btn_touch_mine.button_down.connect(func(): if player_node: player_node.touch_mining_active = true)
	btn_touch_mine.button_up.connect(func(): if player_node: player_node.touch_mining_active = false)
	action_cluster.add_child(btn_touch_mine)

	# [BRAKE] 緊急ブレーキボタン (中・MINEの上)
	var sb_brake = StyleBoxFlat.new()
	sb_brake.bg_color = Color(0.2, 0.04, 0.04, 0.9)
	sb_brake.border_color = Color(2.5, 0.3, 0.3, 0.9)
	sb_brake.set_border_width_all(2)
	sb_brake.set_corner_radius_all(32)

	btn_touch_brake = Button.new()
	btn_touch_brake.text = "BRAKE"
	btn_touch_brake.position = Vector2(104, 26)
	btn_touch_brake.custom_minimum_size = Vector2(64, 64)
	btn_touch_brake.add_theme_stylebox_override("normal", sb_brake)
	btn_touch_brake.add_theme_font_size_override("font_size", 12)
	btn_touch_brake.add_theme_color_override("font_color", Color(2.5, 0.7, 0.7))
	btn_touch_brake.button_down.connect(func(): if player_node: player_node.touch_braking_active = true)
	btn_touch_brake.button_up.connect(func(): if player_node: player_node.touch_braking_active = false)
	action_cluster.add_child(btn_touch_brake)

	# [BUILD] ビルドモード切替ボタン (中・MINEの左)
	var sb_bld = StyleBoxFlat.new()
	sb_bld.bg_color = Color(0.04, 0.09, 0.16, 0.9)
	sb_bld.border_color = Color(0.0, 1.8, 2.5, 0.8)
	sb_bld.set_border_width_all(2)
	sb_bld.set_corner_radius_all(34)

	btn_touch_build = Button.new()
	btn_touch_build.text = "BUILD"
	btn_touch_build.position = Vector2(12, 112)
	btn_touch_build.custom_minimum_size = Vector2(68, 68)
	btn_touch_build.add_theme_stylebox_override("normal", sb_bld)
	btn_touch_build.add_theme_font_size_override("font_size", 13)
	btn_touch_build.add_theme_color_override("font_color", Color(0.0, 2.2, 2.8))
	btn_touch_build.pressed.connect(toggle_build_mode)
	action_cluster.add_child(btn_touch_build)

	# [DRONE] ドローン合体ボタン (小・BUILDの上)
	var sb_drn = StyleBoxFlat.new()
	sb_drn.bg_color = Color(0.03, 0.14, 0.1, 0.9)
	sb_drn.border_color = Color(0.2, 2.0, 0.7, 0.8)
	sb_drn.set_border_width_all(2)
	sb_drn.set_corner_radius_all(30)

	btn_touch_drone = Button.new()
	btn_touch_drone.text = "DRONE"
	btn_touch_drone.position = Vector2(22, 38)
	btn_touch_drone.custom_minimum_size = Vector2(60, 60)
	btn_touch_drone.add_theme_stylebox_override("normal", sb_drn)
	btn_touch_drone.add_theme_font_size_override("font_size", 11)
	btn_touch_drone.add_theme_color_override("font_color", Color(0.2, 2.2, 0.8))
	btn_touch_drone.pressed.connect(func():
		if GameState.attach_drone(): AudioSynth.play_synth("build")
	)
	action_cluster.add_child(btn_touch_drone)

	# ========================================================
	# 5. 下部中央: レスポンシブ建築ツールバー (Scrollable for Mobile)
	# ========================================================
	build_bar_panel = PanelContainer.new()
	build_bar_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	build_bar_panel.anchor_left = 0.0
	build_bar_panel.anchor_right = 1.0
	build_bar_panel.anchor_top = 1.0
	build_bar_panel.anchor_bottom = 1.0
	build_bar_panel.offset_left = 12.0
	build_bar_panel.offset_right = -12.0
	build_bar_panel.offset_top = -262.0
	build_bar_panel.offset_bottom = -204.0
	var sb_bar = StyleBoxFlat.new()
	sb_bar.bg_color = Color(0.03, 0.05, 0.09, 0.85)
	sb_bar.border_color = Color(0.0, 1.5, 2.2, 0.6)
	sb_bar.set_border_width_all(1)
	sb_bar.set_corner_radius_all(4)
	build_bar_panel.add_theme_stylebox_override("panel", sb_bar)
	add_child(build_bar_panel)

	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	build_bar_panel.add_child(scroll)

	var bc_container = HBoxContainer.new()
	bc_container.add_theme_constant_override("separation", 6)
	scroll.add_child(bc_container)

	# ビルドモードON/OFF表示インジケータ
	build_mode_indicator = Panel.new()
	build_mode_indicator.custom_minimum_size = Vector2(5, 46)
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
		slot_p.custom_minimum_size = Vector2(48, 50)
		slot_p.add_theme_stylebox_override("panel", sb_slot)

		var b = Button.new()
		b.icon = load("res://assets/ui/%s.png" % t["icon"])
		b.flat = true
		b.expand_icon = true
		b.custom_minimum_size = Vector2(46, 48)
		b.pressed.connect(func(): _select_tool_by_id(t["id"]))
		slot_p.add_child(b)

		# 所持数バッジ（数字のみ）
		var count_lbl = Label.new()
		count_lbl.text = "0"
		count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count_lbl.position = Vector2(10, 28)
		count_lbl.size = Vector2(34, 16)
		count_lbl.add_theme_font_size_override("font_size", 10)
		count_lbl.add_theme_color_override("font_color", Color(0.2, 1.0, 0.6))
		slot_p.add_child(count_lbl)

		bc_container.add_child(slot_p)
		tool_buttons[t["id"]] = {"btn": b, "lbl": count_lbl, "panel": slot_p}

	# メガストラクチャー展開ボタン (右端)
	var mega_btn = Button.new()
	mega_btn_node = mega_btn
	mega_btn.icon = load("res://assets/ui/icon_elevator.png")
	mega_btn.expand_icon = true
	mega_btn.custom_minimum_size = Vector2(48, 50)
	mega_btn.pressed.connect(toggle_mega_palette)
	bc_container.add_child(mega_btn)

	# ビルド操作ガイド（ノンバーバル極小ピクトグラム）
	build_guide_label = Label.new()
	build_guide_label.text = "TAP GROUND TO PLACE BLUEPRINT"
	build_guide_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	build_guide_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	build_guide_label.anchor_top = 1.0
	build_guide_label.anchor_bottom = 1.0
	build_guide_label.offset_top = -288.0
	build_guide_label.offset_bottom = -268.0
	build_guide_label.add_theme_font_size_override("font_size", 11)
	build_guide_label.add_theme_color_override("font_color", Color(0.0, 2.0, 2.8, 0.85))
	build_guide_label.visible = false
	add_child(build_guide_label)

	# 6. メガストラクチャー・ミニマルパレット構築
	_build_minimal_mega_palette(sb_slot)

	# ========================================================
	# 7. 休眠探査機・再起動ガイダンス (DORMANT STATE OVERLAY)
	# ========================================================
	boot_guide_overlay = Control.new()
	boot_guide_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	boot_guide_overlay.mouse_filter = Control.MOUSE_FILTER_PASS
	boot_guide_overlay.gui_input.connect(func(ev):
		if (ev is InputEventMouseButton and ev.pressed) or (ev is InputEventScreenTouch and ev.pressed):
			if player_node and player_node.has_method("wake_up_probe"):
				player_node.wake_up_probe()
	)
	add_child(boot_guide_overlay)

	var boot_vbox = VBoxContainer.new()
	boot_vbox.set_anchors_preset(Control.PRESET_CENTER)
	boot_vbox.anchor_left = 0.5
	boot_vbox.anchor_right = 0.5
	boot_vbox.anchor_top = 0.5
	boot_vbox.anchor_bottom = 0.5
	boot_vbox.offset_left = -200.0
	boot_vbox.offset_top = 60.0
	boot_vbox.offset_right = 200.0
	boot_vbox.offset_bottom = 140.0
	boot_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	boot_vbox.add_theme_constant_override("separation", 6)
	boot_guide_overlay.add_child(boot_vbox)

	var b_tag = Label.new()
	b_tag.text = ">>> DORMANT AUTOMA PROBE <<<"
	b_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b_tag.add_theme_font_size_override("font_size", 13)
	b_tag.add_theme_color_override("font_color", Color(0.0, 2.2, 2.8))
	boot_vbox.add_child(b_tag)

	boot_prompt_lbl = Label.new()
	boot_prompt_lbl.text = "[ TAP SCREEN TO INITIALIZE CORE ]"
	boot_prompt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boot_prompt_lbl.add_theme_font_size_override("font_size", 14)
	boot_prompt_lbl.add_theme_color_override("font_color", Color(2.5, 2.5, 2.5))
	boot_vbox.add_child(boot_prompt_lbl)

func _adjust_responsive_layout() -> void:
	var vp_rect = get_viewport().get_visible_rect()
	var is_portrait = (vp_rect.size.x < vp_rect.size.y)
	if is_portrait:
		if build_bar_panel:
			build_bar_panel.offset_left = 12.0
			build_bar_panel.offset_right = -12.0
			build_bar_panel.offset_top = -262.0
			build_bar_panel.offset_bottom = -204.0
		if build_guide_label:
			build_guide_label.offset_top = -288.0
			build_guide_label.offset_bottom = -268.0
	else:
		if build_bar_panel:
			build_bar_panel.offset_left = 180.0
			build_bar_panel.offset_right = -190.0
			build_bar_panel.offset_top = -68.0
			build_bar_panel.offset_bottom = -12.0
		if build_guide_label:
			build_guide_label.offset_top = -94.0
			build_guide_label.offset_bottom = -74.0

# ========================================================
# バーチャルジョイスティック描画 ＆ タッチ入力ハンドラー
# ========================================================
func _on_vstick_draw() -> void:
	if not vstick_base: return
	var center = vstick_base.size * 0.5
	# 外枠リング (HDR Glow)
	vstick_base.draw_arc(center, 54.0, 0, TAU, 36, Color(0.0, 2.0, 2.8, 0.5), 2.5)
	vstick_base.draw_circle(center, 54.0, Color(0.02, 0.05, 0.12, 0.5))
	
	# スティックノブ
	var knob_p = center + vstick_knob_pos
	vstick_base.draw_circle(knob_p, 24.0, Color(0.0, 2.4, 3.0, 0.85))
	vstick_base.draw_arc(knob_p, 24.0, 0, TAU, 28, Color(2.5, 2.5, 2.5, 0.95), 2.0)
	
	# 中央方向ガイド十字線
	vstick_base.draw_line(center - Vector2(12, 0), center + Vector2(12, 0), Color(0.0, 1.8, 2.5, 0.4), 1.5)
	vstick_base.draw_line(center - Vector2(0, 12), center + Vector2(0, 12), Color(0.0, 1.8, 2.5, 0.4), 1.5)

func _on_vstick_gui_input(event: InputEvent) -> void:
	if not vstick_base: return
	var center = vstick_base.size * 0.5
	var max_r = 50.0
	
	if event is InputEventScreenTouch:
		if event.pressed:
			vstick_active = true
			vstick_touch_id = event.index
			_update_vstick_pos(event.position, center, max_r)
		elif event.index == vstick_touch_id:
			_reset_vstick()
			
	elif event is InputEventScreenDrag:
		if event.index == vstick_touch_id:
			_update_vstick_pos(event.position, center, max_r)
			
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				vstick_active = true
				_update_vstick_pos(event.position, center, max_r)
			else:
				_reset_vstick()
				
	elif event is InputEventMouseMotion and vstick_active:
		_update_vstick_pos(event.position, center, max_r)

func _update_vstick_pos(pos: Vector2, center: Vector2, max_radius: float) -> void:
	var diff = pos - center
	if diff.length() > max_radius:
		diff = diff.normalized() * max_radius
	vstick_knob_pos = diff
	var vec = diff / max_radius
	if player_node:
		player_node.touch_thrust_vec = vec
	vstick_base.queue_redraw()

func _reset_vstick() -> void:
	vstick_active = false
	vstick_touch_id = -1
	vstick_knob_pos = Vector2.ZERO
	if player_node:
		player_node.touch_thrust_vec = Vector2.ZERO
	vstick_base.queue_redraw()

func create_res_badge(parent: Node, icon_p: String, init_v: String, col: Color, res_key: String = "") -> Label:
	var h = HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	
	var ico = TextureRect.new()
	ico.texture = load(icon_p)
	ico.custom_minimum_size = Vector2(20, 20)
	ico.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	h.add_child(ico)

	var lbl = Label.new()
	lbl.text = init_v
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", col)
	h.add_child(lbl)

	parent.add_child(h)
	if res_key != "":
		res_badge_containers[res_key] = h
	return lbl

func _update_progressive_ui(phase: int) -> void:
	if boot_guide_overlay:
		boot_guide_overlay.visible = (phase == GameState.StoryPhase.DORMANT)

	# 0. DORMANT: 全UI非表示
	if phase == GameState.StoryPhase.DORMANT:
		if top_bar_node: top_bar_node.visible = false
		if zoom_cluster_node: zoom_cluster_node.visible = false
		if vstick_base: vstick_base.visible = false
		if action_cluster_node: action_cluster_node.visible = false
		if build_bar_panel: build_bar_panel.visible = false
		if nav_overlay: nav_overlay.visible = false
		return

	# 1. MOVE 以降: 上部バーとジョイスティック開放
	if top_bar_node: top_bar_node.visible = true
	if vstick_base: vstick_base.visible = true
	if zoom_cluster_node: zoom_cluster_node.visible = (phase >= GameState.StoryPhase.SPACE)
	if nav_overlay: nav_overlay.visible = (phase >= GameState.StoryPhase.SPACE)
	if action_cluster_node: action_cluster_node.visible = (phase >= GameState.StoryPhase.MINE)
	if build_bar_panel: build_bar_panel.visible = (phase >= GameState.StoryPhase.BUILD_MINER)

	# ステータス行 (HP, Shield, Energy) と 右上ボタン (H, M, A, Core, Map, Save)
	if stat_row_node: stat_row_node.visible = (phase >= GameState.StoryPhase.FACTORY)
	if right_top_buttons: right_top_buttons.visible = (phase >= GameState.StoryPhase.SPACE)

	# 資源バッジの段階的表示
	for r_id in res_badge_containers.keys():
		var b_node = res_badge_containers[r_id]
		if r_id == "Fe":
			b_node.visible = (phase >= GameState.StoryPhase.MINE)
		elif r_id in ["Cu", "Si"]:
			b_node.visible = (phase >= GameState.StoryPhase.FACTORY)
		else:
			b_node.visible = (phase >= GameState.StoryPhase.SPACE)

	# アクションボタンの段階的表示
	if btn_touch_mine:
		btn_touch_mine.visible = (phase >= GameState.StoryPhase.MINE)
	if btn_touch_drone:
		btn_touch_drone.visible = (phase >= GameState.StoryPhase.DRONE)
	if btn_touch_build:
		btn_touch_build.visible = (phase >= GameState.StoryPhase.BUILD_MINER)
	if btn_touch_brake:
		btn_touch_brake.visible = (phase >= GameState.StoryPhase.FACTORY)

	# 建築ツールの段階的表示
	for t_id in tool_buttons.keys():
		var slot_panel = tool_buttons[t_id]["panel"]
		if t_id == "miner":
			slot_panel.visible = (phase >= GameState.StoryPhase.BUILD_MINER)
		elif t_id in ["belt", "smelter", "solar"]:
			slot_panel.visible = (phase >= GameState.StoryPhase.FACTORY)
		else:
			slot_panel.visible = (phase >= GameState.StoryPhase.SPACE)

	if mega_btn_node:
		mega_btn_node.visible = (phase >= GameState.StoryPhase.SPACE)

func create_icon_btn(icon_p: String, _tip: String, on_click: Callable) -> Button:
	var b = Button.new()
	if ResourceLoader.exists(icon_p):
		b.icon = load(icon_p)
		b.expand_icon = true
	b.custom_minimum_size = Vector2(32, 32)
	b.pressed.connect(on_click)
	return b

func _build_minimal_mega_palette(sb_slot: StyleBoxFlat) -> void:
	mega_panel = Panel.new()
	mega_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	mega_panel.anchor_left = 0.5
	mega_panel.anchor_right = 0.5
	mega_panel.anchor_top = 1.0
	mega_panel.anchor_bottom = 1.0
	mega_panel.offset_left = -150.0
	mega_panel.offset_right = 150.0
	mega_panel.offset_top = -155.0
	mega_panel.offset_bottom = -85.0
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
		slot.custom_minimum_size = Vector2(50, 50)
		slot.add_theme_stylebox_override("panel", sb_slot)

		var b = Button.new()
		b.icon = load("res://assets/ui/%s.png" % m["icon"])
		b.custom_minimum_size = Vector2(48, 48)
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
	var target_lbl: Label = null
	var flash_col = Color(1.5, 2.5, 1.2)
	match type:
		"Fe": 
			if fe_label: target_lbl = fe_label
		"Cu": 
			if cu_label: target_lbl = cu_label
		"Ti": 
			if ti_label: target_lbl = ti_label
		"Si": 
			if si_label: target_lbl = si_label
		"He3": 
			if he3_label: target_lbl = he3_label
		"Plasma": 
			if plasma_label: target_lbl = plasma_label
		"Ice": 
			if ice_label: target_lbl = ice_label
		"DarkMatter": 
			if dm_label: target_lbl = dm_label
		"Neutronium": 
			if nt_label: target_lbl = nt_label

	if target_lbl:
		target_lbl.text = str(amount)
		# 採掘・生産フィードバック (ポップアップバンプ ＆ フラッシュ)
		var p_badge = target_lbl.get_parent()
		if p_badge and is_inside_tree():
			var tw = create_tween().set_parallel(true)
			p_badge.pivot_offset = p_badge.size * 0.5
			p_badge.scale = Vector2(1.22, 1.22)
			target_lbl.add_theme_color_override("font_color", flash_col)
			tw.tween_property(p_badge, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(target_lbl, "theme_override_colors/font_color", Color(1.0, 1.0, 1.0), 0.3)

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
		missing_label.text = "NEED: %s" % res_name
		missing_panel.visible = true
		missing_timer = 1.2
		AudioSynth.play_synth("alert")

func _update_objective_text() -> void:
	if not objective_label: return
	
	match GameState.story_phase:
		GameState.StoryPhase.DORMANT:
			objective_label.text = "[ >>> TAP SCREEN TO INITIALIZE AUTOMA CORE <<< ]"
			objective_label.add_theme_color_override("font_color", Color(0.2, 2.0, 2.8))
			return
		GameState.StoryPhase.MOVE:
			objective_label.text = "[ STEP 1: ENGAGE THRUSTERS - MOVE WITH JOYSTICK / WASD ]"
			objective_label.add_theme_color_override("font_color", Color(0.0, 2.4, 3.0))
			return
		GameState.StoryPhase.MINE:
			var cur_fe = GameState.resources.get("Fe", 0)
			objective_label.text = "[ STEP 2: HOLD [MINE] OVER Fe VEIN (%d / 40) ]" % mini(40, cur_fe)
			objective_label.add_theme_color_override("font_color", Color(0.3, 2.2, 2.8))
			return
		GameState.StoryPhase.DRONE:
			objective_label.text = "[ STEP 3: TAP [DRONE] TO 3D-PRINT SUB-UNIT (COST: 40 Fe) ]"
			objective_label.add_theme_color_override("font_color", Color(0.2, 2.5, 1.0))
			return
		GameState.StoryPhase.BUILD_MINER:
			objective_label.text = "[ STEP 4: TAP [BUILD] & PLACE DRILL ON Fe VEIN ]"
			objective_label.add_theme_color_override("font_color", Color(0.0, 2.2, 2.8))
			return
		GameState.StoryPhase.FACTORY:
			objective_label.text = "[ STEP 5: BUILD BELT & SMELTER TO AUTOMATE PRODUCTION ]"
			objective_label.add_theme_color_override("font_color", Color(1.0, 2.0, 0.4))
			return
		GameState.StoryPhase.SPACE:
			if GameState.quest_index >= GameState.quest_list.size():
				objective_label.text = "[ SYSTEM LIBERATED: CONQUER THE STARS ]"
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
			objective_label.add_theme_color_override("font_color", Color(0.0, 2.2, 2.8))

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

	# ナビ対象天体リスト (星系の主要天体 Key Solar Bodies のみに厳格選定)
	var targets: Array[Dictionary] = []
	if grid_manager:
		targets.append({"name": "HOME", "pos": grid_manager.HOME_CENTER, "col": Color(0.2, 0.8, 1.0), "icon": "[HOME]"})
		targets.append({"name": "SUN", "pos": grid_manager.SUN_POS, "col": Color(1.0, 0.7, 0.1), "icon": "[SUN]"})
		
		# 1. 母星の公式衛星 LUNA-PRIME のみ
		if not grid_manager.moon_body.is_empty():
			targets.append({"name": "LUNA", "pos": grid_manager.moon_body.get("pos", Vector2.ZERO), "col": Color(0.3, 0.9, 1.0), "icon": "[LUNA]"})
			
		# 2. 彗星 COMET-NEOWISE
		if not grid_manager.comet_body.is_empty():
			targets.append({"name": "COMET", "pos": grid_manager.comet_body.get("pos", Vector2.ZERO), "col": Color(0.4, 0.9, 1.0), "icon": "[COMET]"})
			
		# 3. 特異天体 (ブラックホール Gargantua & パルサー Pulsar-X)
		for p in grid_manager.active_planets:
			var pid = p.get("id", "")
			if pid == "GARGANTUA-ZERO":
				targets.append({"name": "HOLE", "pos": p["pos"], "col": Color(0.8, 0.3, 1.0), "icon": "[HOLE]"})
			elif pid == "PULSAR-X":
				targets.append({"name": "PULSAR", "pos": p["pos"], "col": Color(0.1, 1.0, 0.8), "icon": "[PULSAR]"})
		
		# 4. 敵ボス要塞 (宇宙進出フェーズ以降かつ遠距離表示)
		if GameState.story_phase >= GameState.StoryPhase.SPACE:
			targets.append({"name": "BOSS", "pos": grid_manager.SUN_POS + Vector2(7600.0, -1200.0), "col": Color(1.0, 0.25, 0.25), "icon": "[BOSS]"})

	# 画面外マーカーの角度ファンアウト（重なり回避）バッファ
	var placed_marker_angles: Array[float] = []
	var placed_screen_marker_positions: Array[Vector2] = []

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
				nav_overlay.draw_string(ThemeDB.fallback_font, screen_tpos + Vector2(-36, 46), "LOCK-ON: %s" % t["name"], HORIZONTAL_ALIGNMENT_CENTER, -1, 9, ret_col)
		else:
			# 画面外：画面端にポインターアイコン＋距離を描画 (角度ファンアウトによる完全デコリジョン)
			var base_dir = diff.normalized()
			var base_angle = atan2(base_dir.y, base_dir.x)
			
			# 他の配置済みマーカーとの角度近接判定 ＆ ファンアウト
			var spread_angle = base_angle
			for placed_a in placed_marker_angles:
				var diff_a = angle_difference(spread_angle, placed_a)
				if abs(diff_a) < 0.24: # 約14度以内なら左右に押し出し
					var push_sign = 1.0 if diff_a >= 0.0 else -1.0
					spread_angle += push_sign * (0.24 - abs(diff_a))
			placed_marker_angles.append(spread_angle)
			
			var dir = Vector2(cos(spread_angle), sin(spread_angle))
			var edge_margin = 38.0
			var max_dx = screen_center.x - edge_margin
			var max_dy = screen_center.y - edge_margin
			var scale_x = max_dx / maxf(0.001, abs(dir.x))
			var scale_y = max_dy / maxf(0.001, abs(dir.y))
			var scale_factor = minf(scale_x, scale_y)
			var marker_p = screen_center + dir * scale_factor
			
			# 上部UIバー＆ナラティブ目的バナーとの干渉完全回避 (Safe Zone クランプ)
			if marker_p.y < 118.0 and abs(marker_p.x - screen_center.x) < 280.0:
				marker_p.y = 118.0

			# 左下バーチャルジョイスティック領域の完全回避
			if marker_p.x < 230.0 and marker_p.y > vp_size.y - 230.0:
				if marker_p.x < 115.0:
					marker_p.y = vp_size.y - 235.0
				else:
					marker_p.x = 235.0

			# 右下アクションボタンクラスタ領域の完全回避
			if marker_p.x > vp_size.x - 230.0 and marker_p.y > vp_size.y - 230.0:
				if marker_p.x > vp_size.x - 115.0:
					marker_p.y = vp_size.y - 235.0
				else:
					marker_p.x = vp_size.x - 235.0

			# 下部ビルドパレットバー領域の完全回避
			if marker_p.y > vp_size.y - 85.0 and abs(marker_p.x - screen_center.x) < 380.0:
				marker_p.y = vp_size.y - 88.0

			# 他のマーカーとのX/Yスクリーン座標デコリジョン (最低84pxの横間隔を強制保証)
			for existing_p in placed_screen_marker_positions:
				if abs(marker_p.y - existing_p.y) < 20.0 and abs(marker_p.x - existing_p.x) < 86.0:
					var shift = (86.0 - abs(marker_p.x - existing_p.x))
					if marker_p.x >= existing_p.x:
						marker_p.x += shift
					else:
						marker_p.x -= shift
			placed_screen_marker_positions.append(marker_p)

			var dist_km = p_dist / 100.0
			var dist_str = "%.1fkm" % dist_km if dist_km >= 1.0 else "%.0fm" % p_dist
			var lbl = "%s %s" % [t["icon"], dist_str]
			var lbl_size = Vector2(80.0, 16.0)
			var lbl_rect = Rect2(marker_p - Vector2(40, 12), lbl_size)
			
			var m_col: Color = t["col"]
			nav_overlay.draw_circle(marker_p, 3.5, m_col)
			nav_overlay.draw_line(marker_p, marker_p + dir * 7.0, m_col, 2.0)
			nav_overlay.draw_string(ThemeDB.fallback_font, lbl_rect.position + Vector2(0, 11), lbl, HORIZONTAL_ALIGNMENT_CENTER, int(lbl_size.x), 9, m_col * Color(1.4, 1.4, 1.4, 0.95))

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
				# 画面外：画面端にパルスするターゲットマーカーを描画 (Safe Zone クランプ適用)
				var dir = m_diff.normalized()
				var edge_margin = 46.0
				var max_dx = screen_center.x - edge_margin
				var max_dy = screen_center.y - edge_margin
				var scale_factor = minf(max_dx / maxf(0.001, abs(dir.x)), max_dy / maxf(0.001, abs(dir.y)))
				var marker_p = screen_center + dir * scale_factor
				
				# 上部UI Safe Zone 回避
				if marker_p.y < 120.0 and abs(marker_p.x - screen_center.x) < 280.0:
					marker_p.y = 120.0

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
				var m_txt = "GOAL: %s [%s]" % [m_info.get("name", "MISSION"), m_dist_str]
				nav_overlay.draw_string(ThemeDB.fallback_font, marker_p - Vector2(40, 14), m_txt, HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color(2.5, 2.5, 1.2))
