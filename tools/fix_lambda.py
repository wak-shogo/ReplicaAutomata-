with open('scripts/ui/hud.gd', 'r', encoding='utf-8') as f:
    text = f.read()

bad = '''\t\t\ttw_out.finished.connect(func():
\t\t\t\t\t\t)'''

good = '''\t\t\ttw_out.finished.connect(func():
\t\t\t\tif milestone_panel: milestone_panel.visible = false
\t\t\t)'''

assert bad in text, "bad pattern not found"
text = text.replace(bad, good)

with open('scripts/ui/hud.gd', 'w', encoding='utf-8') as f:
    f.write(text)

print("Fixed lambda body in hud.gd")
