with open('scripts/ui/hud.gd', 'r', encoding='utf-8') as f:
    text = f.read()

# 1. sb_modal bg_color to 100% opaque
text = text.replace('sb_modal.bg_color = Color(0.02, 0.04, 0.09, 0.98)', 'sb_modal.bg_color = Color(0.012, 0.025, 0.05, 1.0)')

# 2. In open_tech_tree_modal: hide objective and milestone to prevent any background bleed
target_open = '''	_update_tech_tree_cards_affordability()
	tech_tree_modal.visible = true'''

replacement_open = '''	_update_tech_tree_cards_affordability()
	if objective_label: objective_label.visible = false
	if milestone_panel: milestone_panel.visible = false
	tech_tree_modal.visible = true'''

assert target_open in text, "target_open not found"
text = text.replace(target_open, replacement_open)

# 3. When closing modal: restore objective
target_close_fn = '''	btn_close.pressed.connect(func():
		tech_tree_modal.visible = false
		AudioSynth.play_synth("click")
	)'''

replacement_close_fn = '''	btn_close.pressed.connect(func():
		tech_tree_modal.visible = false
		if objective_label: objective_label.visible = true
		if milestone_panel and milestone_timer > 0.0: milestone_panel.visible = true
		AudioSynth.play_synth("click")
	)'''

assert target_close_fn in text, "target_close_fn not found"
text = text.replace(target_close_fn, replacement_close_fn)

# 4. In _on_tech_tree_item_selected: restore objective
target_sel = '''	if tech_tree_modal:
		tech_tree_modal.visible = false'''

replacement_sel = '''	if tech_tree_modal:
		tech_tree_modal.visible = false
		if objective_label: objective_label.visible = true
		if milestone_panel and milestone_timer > 0.0: milestone_panel.visible = true'''

assert target_sel in text, "target_sel not found"
text = text.replace(target_sel, replacement_sel)

# 5. In toggle_build_mode: restore objective
target_toggle = '''	if tech_tree_modal and tech_tree_modal.visible:
		tech_tree_modal.visible = false
		AudioSynth.play_synth("click")
		return'''

replacement_toggle = '''	if tech_tree_modal and tech_tree_modal.visible:
		tech_tree_modal.visible = false
		if objective_label: objective_label.visible = true
		if milestone_panel and milestone_timer > 0.0: milestone_panel.visible = true
		AudioSynth.play_synth("click")
		return'''

assert target_toggle in text, "target_toggle not found"
text = text.replace(target_toggle, replacement_toggle)

with open('scripts/ui/hud.gd', 'w', encoding='utf-8') as f:
    f.write(text)

print("Opaque modal and clean objective toggle added to hud.gd")
