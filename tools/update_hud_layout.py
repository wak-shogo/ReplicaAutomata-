import re

with open('scripts/ui/hud.gd', 'r', encoding='utf-8') as f:
    code = f.read()

# 1. Action cluster button texts
code = code.replace('btn_touch_mine.text = "PWR\\nMINE"', 'btn_touch_mine.text = "MINE"')
code = code.replace('btn_touch_brake.text = "STOP\\nSTOP"', 'btn_touch_brake.text = "STOP"')
code = code.replace('btn_touch_build.text = "[BUILD]\\nBUILD"', 'btn_touch_build.text = "BUILD"')
code = code.replace('btn_touch_drone.text = "[+]\\nREPLICATE"', 'btn_touch_drone.text = "REPL\\nDRONE"')

# 2. open_tech_tree_modal
old_open_modal = '''func open_tech_tree_modal() -> void:
	if not tech_tree_modal: return
	# スマホ縦持ち・横持ちレスポンシブ列数調整
	var grid = tech_tree_modal.find_child("TechTreeGrid", true, false)
	if grid:
		var vp = get_viewport()
		if vp:
			var vp_size = vp.get_visible_rect().size
			grid.columns = 1 if vp_size.x < 720.0 else 2
	# 所持資源ラベルの更新
	var res_box = tech_tree_modal.find_child("TechTreeResBar", true, false)
	if res_box:
		var res_types = ["Fe", "Cu", "Ti", "Si"]
		for rk in res_types:
			var lbl = res_box.find_child("ResLbl_" + rk, true, false)
			if lbl:
				lbl.text = "%s: %d" % [rk, GameState.resources.get(rk, 0)]
	_update_tech_tree_cards_affordability()
	tech_tree_modal.visible = true
	AudioSynth.play_synth("click")'''

new_open_modal = '''func open_tech_tree_modal() -> void:
	if not tech_tree_modal: return
	var vp = get_viewport()
	var vp_size = vp.get_visible_rect().size if vp else Vector2(1280, 720)
	var is_portrait = (vp_size.x < vp_size.y or vp_size.x < 720.0)
	
	if is_portrait:
		tech_tree_modal.anchor_left = 0.02
		tech_tree_modal.anchor_right = 0.98
		tech_tree_modal.anchor_top = 0.02
		tech_tree_modal.anchor_bottom = 0.96
	else:
		tech_tree_modal.anchor_left = 0.06
		tech_tree_modal.anchor_right = 0.94
		tech_tree_modal.anchor_top = 0.04
		tech_tree_modal.anchor_bottom = 0.94
	tech_tree_modal.offset_left = 0
	tech_tree_modal.offset_top = 0
	tech_tree_modal.offset_right = 0
	tech_tree_modal.offset_bottom = 0
	
	var grid = tech_tree_modal.find_child("TechTreeGrid", true, false)
	if grid:
		grid.columns = 1 if is_portrait else 2
		
	# 所持資源ラベルの更新
	var res_box = tech_tree_modal.find_child("TechTreeResBar", true, false)
	if res_box:
		var res_types = ["Fe", "Cu", "Ti", "Si"]
		for rk in res_types:
			var lbl = res_box.find_child("ResLbl_" + rk, true, false)
			if lbl:
				lbl.text = "%s: %d" % [rk, GameState.resources.get(rk, 0)]
	_update_tech_tree_cards_affordability()
	tech_tree_modal.visible = true
	AudioSynth.play_synth("click")'''

assert old_open_modal.replace('\r\n', '\n') in code.replace('\r\n', '\n'), "old_open_modal not found"
code = code.replace('\r\n', '\n').replace(old_open_modal.replace('\r\n', '\n'), new_open_modal)

# 3. _build_tech_tree_modal
# Find from func _build_tech_tree_modal() to the end of _create_tech_tree_card
build_pattern = re.compile(r'func _build_tech_tree_modal\(\) -> void:.*?(?=func _adjust_responsive_layout)', re.DOTALL)

new_build_and_cards = '''func _build_tech_tree_modal() -> void:
	tech_tree_modal = Panel.new()
	tech_tree_modal.name = "TechTreeModal"
	tech_tree_modal.visible = false
	tech_tree_modal.clip_contents = true
	tech_tree_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	tech_tree_modal.anchor_left = 0.03
	tech_tree_modal.anchor_top = 0.03
	tech_tree_modal.anchor_right = 0.97
	tech_tree_modal.anchor_bottom = 0.95
	tech_tree_modal.offset_left = 0
	tech_tree_modal.offset_top = 0
	tech_tree_modal.offset_right = 0
	tech_tree_modal.offset_bottom = 0
	
	var sb_modal = StyleBoxFlat.new()
	sb_modal.bg_color = Color(0.02, 0.04, 0.09, 0.98)
	sb_modal.border_color = Color(0.0, 1.8, 2.5, 0.85)
	sb_modal.set_border_width_all(2)
	sb_modal.set_corner_radius_all(10)
	sb_modal.shadow_color = Color(0.0, 1.2, 2.0, 0.5)
	sb_modal.shadow_size = 16
	tech_tree_modal.add_theme_stylebox_override("panel", sb_modal)
	add_child(tech_tree_modal)
	
	var main_vbox = VBoxContainer.new()
	main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_vbox.offset_left = 10
	main_vbox.offset_top = 8
	main_vbox.offset_right = -10
	main_vbox.offset_bottom = -8
	main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_theme_constant_override("separation", 6)
	tech_tree_modal.add_child(main_vbox)
	
	# ヘッダー (コンパクト＆見切れ防止)
	var header_hbox = HBoxContainer.new()
	header_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(header_hbox)
	
	var title_vbox = VBoxContainer.new()
	title_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_vbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_vbox.add_theme_constant_override("separation", 1)
	header_hbox.add_child(title_vbox)
	
	var title_lbl = Label.new()
	title_lbl.text = "BLUEPRINT CATALOG"
	title_lbl.add_theme_font_size_override("font_size", 13)
	title_lbl.add_theme_color_override("font_color", Color(0.0, 2.4, 3.0))
	title_vbox.add_child(title_lbl)
	
	var sub_lbl = Label.new()
	sub_lbl.text = "Select a facility. Tap blue ghost on surface to construct."
	sub_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub_lbl.add_theme_font_size_override("font_size", 9)
	sub_lbl.add_theme_color_override("font_color", Color(0.6, 0.8, 0.95))
	title_vbox.add_child(sub_lbl)
	
	var btn_close = Button.new()
	btn_close.text = "CLOSE X"
	btn_close.custom_minimum_size = Vector2(68, 28)
	btn_close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb_cls = StyleBoxFlat.new()
	sb_cls.bg_color = Color(0.2, 0.05, 0.08, 0.9)
	sb_cls.border_color = Color(2.5, 0.3, 0.3, 0.8)
	sb_cls.set_border_width_all(1)
	sb_cls.set_corner_radius_all(6)
	btn_close.add_theme_stylebox_override("normal", sb_cls)
	btn_close.add_theme_color_override("font_color", Color(2.5, 0.5, 0.5))
	btn_close.pressed.connect(func():
		tech_tree_modal.visible = false
		AudioSynth.play_synth("click")
	)
	header_hbox.add_child(btn_close)
	
	var sep = HSeparator.new()
	main_vbox.add_child(sep)
	
	# 現在の所持資材バー (Current Inventory Status)
	var res_hbox = HBoxContainer.new()
	res_hbox.name = "TechTreeResBar"
	res_hbox.add_theme_constant_override("separation", 14)
	main_vbox.add_child(res_hbox)
	
	var res_types = ["Fe", "Cu", "Ti", "Si"]
	for rk in res_types:
		var r_lbl = Label.new()
		r_lbl.name = "ResLbl_" + rk
		r_lbl.text = "%s: %d" % [rk, GameState.resources.get(rk, 0)]
		r_lbl.add_theme_font_size_override("font_size", 10)
		r_lbl.add_theme_color_override("font_color", Color(0.2, 2.2, 2.8))
		res_hbox.add_child(r_lbl)
	
	var sep2 = HSeparator.new()
	main_vbox.add_child(sep2)
	
	# スクロール
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main_vbox.add_child(scroll)
	
	var grid = GridContainer.new()
	grid.name = "TechTreeGrid"
	grid.columns = 1
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)
	
	var catalog_data = [
		{
			"id": "miner",
			"name": "MINING DRILL",
			"icon": "res://assets/ui/tool_drill.png",
			"cost": "Fe: 20, Cu: 10 | Power: -15 kW",
			"desc": "Place on ore veins. Automatically extracts raw ore and outputs to rear conveyor belt."
		},
		{
			"id": "smelter",
			"name": "ELECTRIC SMELTER",
			"icon": "res://assets/ui/tool_smelter.png",
			"cost": "Fe: 30, Cu: 15 | Power: -22 kW",
			"desc": "Smelts incoming Fe/Cu ores into refined industrial metal plates."
		},
		{
			"id": "belt",
			"name": "CONVEYOR BELT",
			"icon": "res://assets/ui/tool_belt.png",
			"cost": "Fe: 6 (Pack of 5)",
			"desc": "Connects facilities. High-speed smooth logistics line to transport items without jamming."
		},
		{
			"id": "assembler",
			"name": "AUTO ASSEMBLER",
			"icon": "res://assets/ui/tool_assembler.png",
			"cost": "Fe: 40, Cu: 20, Si: 10 | Power: -28 kW",
			"desc": "Combines plates and microchips to automatically mass-produce autonomous drones and advanced parts."
		},
		{
			"id": "solar",
			"name": "SOLAR ARRAY",
			"icon": "res://assets/ui/tool_solar.png",
			"cost": "Si: 15, Cu: 10 | Power: +35 kW",
			"desc": "Absorbs sunlight to provide clean power. Ineffective during planetary night."
		},
		{
			"id": "geothermal",
			"name": "GEOTHERMAL PLANT",
			"icon": "res://assets/ui/tool_geothermal.png",
			"cost": "Fe: 60, Ti: 20 | Power: +130 kW",
			"desc": "Taps planetary core magma energy. Supplies massive constant baseload power day and night."
		},
		{
			"id": "turret",
			"name": "DEFENSE TURRET",
			"icon": "res://assets/ui/tool_turret.png",
			"cost": "Fe: 30, Ti: 15 | Power: -10 kW",
			"desc": "Automatically locks onto incoming hostile bombers and raiders within 650px with pulse lasers."
		},
		{
			"id": "depot",
			"name": "LOGISTICS DEPOT",
			"icon": "res://assets/ui/tool_depot.png",
			"cost": "Fe: 25 | Capacity: 10,000",
			"desc": "Stores mass minerals and products to buffer factory production surges."
		},
		{
			"id": "mass_driver",
			"name": "ORBITAL MASS DRIVER",
			"icon": "res://assets/ui/tool_mass_driver.png",
			"cost": "Fe: 80, Ti: 40, Si: 30 | Power: -35 kW",
			"desc": "Launches manufactured drones into space orbit at hypervelocity to expand the 10,000-unit Swarm."
		},
		{
			"id": "demolish",
			"name": "DEMOLISH TOOL",
			"icon": "res://assets/ui/tool_demolish.png",
			"cost": "FREE (100% Refund)",
			"desc": "Dismantle existing buildings or blueprints to reclaim construction space and materials."
		}
	]
	
	tech_tree_cards.clear()
	for item in catalog_data:
		var card = _create_tech_tree_card(item)
		grid.add_child(card)

func _create_tech_tree_card(item: Dictionary) -> Button:
	var btn = Button.new()
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0, 92)
	
	var sb_n = StyleBoxFlat.new()
	sb_n.bg_color = Color(0.04, 0.08, 0.15, 0.9)
	sb_n.border_color = Color(0.0, 1.2, 1.8, 0.5)
	sb_n.set_border_width_all(1)
	sb_n.set_corner_radius_all(6)
	
	var sb_h = StyleBoxFlat.new()
	sb_h.bg_color = Color(0.06, 0.14, 0.25, 0.95)
	sb_h.border_color = Color(0.0, 2.2, 3.0, 0.9)
	sb_h.set_border_width_all(2)
	sb_h.set_corner_radius_all(6)
	
	btn.add_theme_stylebox_override("normal", sb_n)
	btn.add_theme_stylebox_override("hover", sb_h)
	btn.add_theme_stylebox_override("pressed", sb_h)
	
	var h_box = HBoxContainer.new()
	h_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	h_box.offset_left = 8
	h_box.offset_top = 6
	h_box.offset_right = -8
	h_box.offset_bottom = -6
	h_box.add_theme_constant_override("separation", 8)
	btn.add_child(h_box)
	
	var tex_icon = load(item["icon"])
	if tex_icon:
		var trect = TextureRect.new()
		trect.texture = tex_icon
		trect.custom_minimum_size = Vector2(34, 34)
		trect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		trect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		trect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		h_box.add_child(trect)
		
	var v_box = VBoxContainer.new()
	v_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v_box.add_theme_constant_override("separation", 2)
	h_box.add_child(v_box)
	
	var lbl_name = Label.new()
	var is_rec = (GameState.story_phase == GameState.StoryPhase.BUILD_MINER and item["id"] == "miner")
	lbl_name.text = ("[*] [REC] " if is_rec else "") + item["name"]
	lbl_name.add_theme_font_size_override("font_size", 11)
	lbl_name.add_theme_color_override("font_color", Color(2.5, 2.2, 0.4) if is_rec else Color(1.8, 2.4, 2.8))
	v_box.add_child(lbl_name)
	
	var lbl_cost = Label.new()
	lbl_cost.text = "COST: %s" % item["cost"]
	lbl_cost.add_theme_font_size_override("font_size", 9)
	lbl_cost.add_theme_color_override("font_color", Color(0.0, 2.0, 2.8))
	v_box.add_child(lbl_cost)
	
	var lbl_status = Label.new()
	lbl_status.text = "[OK] READY"
	lbl_status.add_theme_font_size_override("font_size", 9)
	lbl_status.add_theme_color_override("font_color", Color(0.2, 2.5, 1.2))
	v_box.add_child(lbl_status)
	
	var lbl_desc = Label.new()
	lbl_desc.text = item["desc"]
	lbl_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_desc.add_theme_font_size_override("font_size", 8.5)
	lbl_desc.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	v_box.add_child(lbl_desc)
	
	btn.pressed.connect(func():
		_on_tech_tree_item_selected(item["id"])
	)

	tech_tree_cards.append({
		"btn": btn,
		"id": item["id"],
		"status_lbl": lbl_status,
		"sb_n": sb_n
	})
	return btn

'''

assert build_pattern.search(code) is not None, "build_pattern not found"
code = build_pattern.sub(new_build_and_cards, code)

# 4. _adjust_responsive_layout: ensure modal adjusts
old_adj = '''	if tech_tree_modal:
		var grid = tech_tree_modal.find_child("TechTreeGrid", true, false)
		if grid:
			grid.columns = 1 if is_portrait else 2'''

new_adj = '''	if tech_tree_modal:
		var grid = tech_tree_modal.find_child("TechTreeGrid", true, false)
		if grid:
			grid.columns = 1 if is_portrait else 2
		if is_portrait:
			tech_tree_modal.anchor_left = 0.02
			tech_tree_modal.anchor_right = 0.98
			tech_tree_modal.anchor_top = 0.02
			tech_tree_modal.anchor_bottom = 0.96
		else:
			tech_tree_modal.anchor_left = 0.06
			tech_tree_modal.anchor_right = 0.94
			tech_tree_modal.anchor_top = 0.04
			tech_tree_modal.anchor_bottom = 0.94
		tech_tree_modal.offset_left = 0
		tech_tree_modal.offset_top = 0
		tech_tree_modal.offset_right = 0
		tech_tree_modal.offset_bottom = 0'''

assert old_adj in code, "old_adj not found"
code = code.replace(old_adj, new_adj)

with open('scripts/ui/hud.gd', 'w', encoding='utf-8') as f:
    f.write(code)

print("hud.gd successfully updated.")
