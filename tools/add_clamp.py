with open('scripts/entities/player.gd', 'r', encoding='utf-8') as f:
    text = f.read()

target = '''			move_and_slide()

			# ---------------------------------------------------------
			# 地表タッチ判定 -> 惑星表面への自動アタッチ固定
			# ---------------------------------------------------------
			var to_ship = global_position - prim_pos
			var cur_r = to_ship.length()
			var normal = to_ship / cur_r if cur_r > 0.001 else Vector2.UP'''

replacement = '''			move_and_slide()

			# ---------------------------------------------------------
			# 地表タッチ判定 -> 惑星表面への自動アタッチ固定
			# ---------------------------------------------------------
			var to_ship = global_position - prim_pos
			var cur_r = to_ship.length()
			var normal = to_ship / cur_r if cur_r > 0.001 else Vector2.UP
			if prim_kind != "sun" and prim_kind != "blackhole" and cur_r < min_radius:
				global_position = prim_pos + normal * min_radius
				cur_r = min_radius'''

assert target.replace('\r\n', '\n') in text.replace('\r\n', '\n'), "target not found in player.gd"
text = text.replace('\r\n', '\n').replace(target.replace('\r\n', '\n'), replacement)

with open('scripts/entities/player.gd', 'w', encoding='utf-8') as f:
    f.write(text)

print("Added hard surface collision clamping to player.gd")
