import os

replacements = {
    # Symbols to ASCII
    "\u2714": "[OK]",      # ✔
    "\u274c": "[!]",       # ❌
    "\u2715": "X",         # ✕
    "\u2726": "[+]",       # ✦
    "\u2605": "[*]",       # ★
    "\u25bc": "[v]",       # ▼
    "\u25b2": "[^]",       # ▲
    "\u26a1": "PWR",       # ⚡
    "\U0001f6e0": "[BUILD]", # 🛠
    "\U0001f6d1": "STOP",   # 🛑
    "\u26a0": "[!]",       # ⚠
}

targets = [
    'scripts/entities/player.gd',
    'scripts/entities/swarm_simulation.gd',
    'scripts/factory/grid_manager.gd',
    'scripts/ui/hud.gd',
]

for t in targets:
    if not os.path.exists(t):
        continue
    with open(t, 'r', encoding='utf-8') as f:
        content = f.read()
    
    orig = content
    for k, v in replacements.items():
        content = content.replace(k, v)
        
    if content != orig:
        with open(t, 'w', encoding='utf-8') as f:
            f.write(content)
        print(f"Updated {t}")

print("Replacements complete.")
