with open('scripts/main.gd', 'r', encoding='utf-8') as f:
    text = f.read()

target = 'var min_dist = grid_manager.HOME_RADIUS + 15.9'
replacement = 'var min_dist = grid_manager.HOME_RADIUS + 14.0'

assert target in text, "target not found"
text = text.replace(target, replacement)

with open('scripts/main.gd', 'w', encoding='utf-8') as f:
    f.write(text)

print("Updated surface clamping threshold in main.gd")
