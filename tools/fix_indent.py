with open('scripts/ui/hud.gd', 'r', encoding='utf-8') as f:
    text = f.read()

bad = '''\t\tif grid_manager:
\t\tgrid_manager.select_tool(tool_id)'''

good = '''\t\tif grid_manager:
\t\t\tgrid_manager.select_tool(tool_id)'''

text = text.replace(bad, good)

with open('scripts/ui/hud.gd', 'w', encoding='utf-8') as f:
    f.write(text)

print("Indentation fixed.")
