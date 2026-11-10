with open('scripts/main.gd', 'r', encoding='utf-8') as f:
    text = f.read()

target = 'hud.show_missing_res_alert(player.global_position, "Cu", 15)'
replacement = 'hud.show_missing_res_alert("Cu (-15)")'

assert target in text, "target not found"
text = text.replace(target, replacement)

with open('scripts/main.gd', 'w', encoding='utf-8') as f:
    f.write(text)

print("Updated show_missing_res_alert in main.gd")
