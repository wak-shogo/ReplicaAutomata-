with open('scripts/main.gd', 'r', encoding='utf-8') as f:
    text = f.read()

target = 'player.spawn_resource_popup("Fe", 25)'
replacement = '''player.floating_res_type = "Fe"
\t\tplayer.floating_res_count = 25
\t\tplayer.floating_res_timer = 2.0
\t\tplayer.floating_res_scale = 1.3'''

assert target in text, "target not found"
text = text.replace(target, replacement)

with open('scripts/main.gd', 'w', encoding='utf-8') as f:
    f.write(text)

print("Updated main.gd floating_res popup")
