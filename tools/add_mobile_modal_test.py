with open('scripts/main.gd', 'r', encoding='utf-8') as f:
    text = f.read()

target = '''func _run_test_tech_tree_modal() -> void:
	print("TEST PHASE 3: TECH TREE BLUEPRINT CATALOG MODAL (RESPONSIVE & NO OVERFLOW)")
	if player:
		player.is_mining = false
	if hud:
		hud.open_tech_tree_modal()
		
		# モーダルが見切れていないかのアサーション
		var vp_rect = get_viewport().get_visible_rect()
		var modal = hud.tech_tree_modal
		assert(modal != null, "CRITICAL ERROR: Tech tree modal not found!")
		var m_rect = modal.get_global_rect()
		print("ASSERTION: Tech tree modal rect -> pos: (%.1f, %.1f), size: (%.1f, %.1f), vp_size: (%.1f, %.1f)" % [
			m_rect.position.x, m_rect.position.y, m_rect.size.x, m_rect.size.y, vp_rect.size.x, vp_rect.size.y
		])
		assert(m_rect.position.x >= 0, "CRITICAL ERROR: Modal left edge is off-screen!")
		assert(m_rect.end.x <= vp_rect.size.x + 2.0, "CRITICAL ERROR: Modal right edge overflows screen width!")
		assert(m_rect.end.y <= vp_rect.size.y + 2.0, "CRITICAL ERROR: Modal bottom edge overflows screen height!")
	
	get_tree().create_timer(0.5).timeout.connect(func():
		_save_test_screen("docs/art/test_03_tech_tree_modal.png")
		_run_test_insufficient_resource_alert()
	)'''

replacement = '''func _run_test_tech_tree_modal() -> void:
	print("TEST PHASE 3: TECH TREE BLUEPRINT CATALOG MODAL (DESKTOP & MOBILE TEST)")
	if player:
		player.is_mining = false
	if hud:
		hud.open_tech_tree_modal()
		var vp_rect = get_viewport().get_visible_rect()
		var modal = hud.tech_tree_modal
		assert(modal != null, "CRITICAL ERROR: Tech tree modal not found!")
		var m_rect = modal.get_global_rect()
		print("ASSERTION (DESKTOP 1280x720): Modal rect -> pos: (%.1f, %.1f), size: (%.1f, %.1f), vp_size: (%.1f, %.1f)" % [
			m_rect.position.x, m_rect.position.y, m_rect.size.x, m_rect.size.y, vp_rect.size.x, vp_rect.size.y
		])
		assert(m_rect.position.x >= 0, "CRITICAL ERROR: Modal left edge is off-screen!")
		assert(m_rect.end.x <= vp_rect.size.x + 2.0, "CRITICAL ERROR: Modal right edge overflows screen width!")
		assert(m_rect.end.y <= vp_rect.size.y + 2.0, "CRITICAL ERROR: Modal bottom edge overflows screen height!")
	
	get_tree().create_timer(0.4).timeout.connect(func():
		_save_test_screen("docs/art/test_03_tech_tree_modal.png")
		# スマホ縦画面 (390 x 844 iPhone/Android 実機相当解像度) への動的リサイズ検証
		DisplayServer.window_set_size(Vector2i(390, 844))
		get_tree().create_timer(0.5).timeout.connect(func():
			if hud:
				hud._adjust_responsive_layout()
				hud.open_tech_tree_modal()
				var vp_m = get_viewport().get_visible_rect()
				var modal_m = hud.tech_tree_modal
				var mr = modal_m.get_global_rect()
				print("ASSERTION (MOBILE PORTRAIT 390x844): Modal rect -> pos: (%.1f, %.1f), size: (%.1f, %.1f), vp_size: (%.1f, %.1f)" % [
					mr.position.x, mr.position.y, mr.size.x, mr.size.y, vp_m.size.x, vp_m.size.y
				])
				assert(mr.position.x >= 0, "CRITICAL ERROR: Mobile modal left edge is off-screen!")
				assert(mr.end.x <= vp_m.size.x + 2.0, "CRITICAL ERROR: Mobile modal right edge overflows screen width!")
				assert(mr.end.y <= vp_m.size.y + 2.0, "CRITICAL ERROR: Mobile modal bottom edge overflows screen height!")
				_save_test_screen("docs/art/test_03_tech_tree_mobile_portrait.png")
				
				# 元のデスクトップ解像度に戻す
				DisplayServer.window_set_size(Vector2i(1280, 720))
				get_tree().create_timer(0.4).timeout.connect(func():
					hud._adjust_responsive_layout()
					_run_test_insufficient_resource_alert()
				)
		)
	)'''

assert target.replace('\r\n', '\n') in text.replace('\r\n', '\n'), "target not found"
text = text.replace('\r\n', '\n').replace(target.replace('\r\n', '\n'), replacement)

with open('scripts/main.gd', 'w', encoding='utf-8') as f:
    f.write(text)

print("Added mobile portrait 390x844 test to main.gd")
