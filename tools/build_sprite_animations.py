#!/usr/bin/env python3
"""
Builds genuine 4-frame pixel-art sprite sheets from the AI-generated pixel sprites:
- mass_driver_sheet.png (560x110, 4 frames of 140x110): Idle -> Base Charge -> Overcharge -> Recoil & Muzzle Flash
- mining_drill_sheet.png (160x56, 4 frames of 40x56): Spiral bit phase rotation + hydraulic vibration + excavation sparks
- factory_hall_sheet.png (448x72, 4 frames of 112x72): Furnace window plasma glow cycle + roof piston movement + chimney embers
- player_core_sheet.png (192x48, 4 frames of 48x48): Reactor core pulse + corner thruster flicker
- fabricator_drone_sheet.png (96x24, 4 frames of 24x24): Welding arc discharge animation
"""

import os
from PIL import Image

base_sprites = "C:/Users/wakazaki shogo/git/StarReplica-Automa/assets/sprites"

def clamp_idx(v, lo, hi):
    return max(lo, min(hi, v))

def build_mass_driver_sheet():
    base = Image.open(f"{base_sprites}/mass_driver_ramp.png").convert("RGBA")
    w, h = base.size
    sheet = Image.new("RGBA", (w * 4, h), (0, 0, 0, 0))
    sheet.paste(base, (0, 0))

    def mod_frame(img, region_fn, boost, recoil_dx=0, recoil_dy=0, muzzle_flash=False):
        out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        src_px = img.load()
        out_px = out.load()
        for y in range(h):
            for x in range(w):
                if (recoil_dx != 0 or recoil_dy != 0) and y < 72 and x > 32:
                    sx, sy = x - recoil_dx, y - recoil_dy
                    r, g, b, a = src_px[sx, sy] if (0 <= sx < w and 0 <= sy < h) else (0, 0, 0, 0)
                else:
                    r, g, b, a = src_px[x, y]
                if a > 0 and region_fn(x, y):
                    if b > r + 15 or g > r + 15:
                        r = min(255, int(r + boost * 0.8))
                        g = min(255, int(g + boost))
                        b = min(255, int(b + boost))
                    elif r > 60 and g > 60 and b > 60:
                        g = min(255, int(g + boost * 0.35))
                        b = min(255, int(b + boost * 0.5))
                out_px[x, y] = (r, g, b, a)
        if muzzle_flash:
            tip_x, tip_y = int(w * 0.82), int(h * 0.18)
            for y in range(h // 2):
                for x in range(w // 2, w):
                    if out_px[x, y][3] > 0 and (x - y) > (tip_x - tip_y):
                        tip_x, tip_y = x, y
            flash_offsets = [
                (0,0,(255,255,255,255)), (1,0,(255,255,255,255)), (-1,0,(255,255,255,255)),
                (0,1,(255,255,255,255)), (0,-1,(255,255,255,255)),
                (2,0,(120,245,255,255)), (-2,0,(120,245,255,255)), (0,2,(120,245,255,255)), (0,-2,(120,245,255,255)),
                (1,1,(180,250,255,255)), (-1,-1,(180,250,255,255)), (1,-1,(180,250,255,255)), (-1,1,(180,250,255,255)),
                (3,-1,(0,210,255,255)), (4,-2,(0,210,255,255)), (-3,1,(0,210,255,255)),
                (2,-3,(255,220,80,255)), (-2,3,(255,220,80,255)),
            ]
            for dx, dy, col in flash_offsets:
                fx, fy = tip_x + dx, tip_y + dy
                if 0 <= fx < w and 0 <= fy < h:
                    out_px[fx, fy] = col
        return out

    sheet.paste(mod_frame(base, lambda x, y: 30 <= x <= 85 and 35 <= y <= 85, boost=85), (w, 0))
    sheet.paste(mod_frame(base, lambda x, y: 45 <= x <= 135 and 5 <= y <= 75, boost=130), (w * 2, 0))
    sheet.paste(mod_frame(base, lambda x, y: y < 80, boost=150, recoil_dx=-3, recoil_dy=3, muzzle_flash=True), (w * 3, 0))
    sheet.save(f"{base_sprites}/mass_driver_sheet.png")
    print("Saved mass_driver_sheet.png")

def build_mining_drill_sheet():
    base = Image.open(f"{base_sprites}/mining_drill.png").convert("RGBA")
    w, h = base.size
    sheet = Image.new("RGBA", (w * 4, h), (0, 0, 0, 0))
    src_px = base.load()
    for frame in range(4):
        f_img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        f_px = f_img.load()
        vib_y = 1 if (frame % 2 == 1) else 0
        for y in range(h):
            row_opaque = [x for x in range(w) if src_px[x, y][3] > 0 and src_px[x, y][:3] != (10, 14, 24)]
            for x in range(w):
                sy = clamp_idx(y - vib_y, 0, h - 1) if y < h // 2 else y
                r, g, b, a = src_px[x, sy]
                if y >= h // 2 and len(row_opaque) >= 4 and x in row_opaque[1:-1]:
                    span = row_opaque[1:-1]
                    sx = span[(span.index(x) + frame * 2) % len(span)]
                    r, g, b, a = src_px[sx, y]
                f_px[x, y] = (r, g, b, a)
        spark_patterns = [
            [(-3, -2, (0,240,255,255)), (3, -1, (255,200,50,255))],
            [(-5, -4, (255,200,50,255)), (4, -3, (0,240,255,255)), (0, -1, (255,255,255,255))],
            [(-2, -3, (255,140,30,255)), (5, -5, (0,240,255,255))],
            [(-4, -1, (0,240,255,255)), (2, -4, (255,230,90,255)), (0, -2, (255,255,255,255))],
        ]
        cx, cy = w // 2, h - 3
        for dx, dy, scol in spark_patterns[frame]:
            if 0 <= cx + dx < w and 0 <= cy + dy < h:
                f_px[cx + dx, cy + dy] = scol
        sheet.paste(f_img, (w * frame, 0))
    sheet.save(f"{base_sprites}/mining_drill_sheet.png")
    print("Saved mining_drill_sheet.png")

def build_factory_hall_sheet():
    base = Image.open(f"{base_sprites}/factory_hall.png").convert("RGBA")
    w, h = base.size
    sheet = Image.new("RGBA", (w * 4, h), (0, 0, 0, 0))
    src_px = base.load()
    
    # Find smokestack top x positions automatically
    stack_tops = []
    for x in range(10, w - 10):
        for y in range(2, 22):
            if src_px[x, y][3] > 0:
                if not stack_tops or abs(x - stack_tops[-1][0]) > 14:
                    stack_tops.append((x, y))
                break
    if not stack_tops:
        stack_tops = [(72, 10), (88, 12)]

    for frame in range(4):
        f_img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        f_px = f_img.load()
        piston_dy = [0, -1, -2, -1][frame]
        
        for y in range(h):
            for x in range(w):
                sy = clamp_idx(y - piston_dy, 0, h - 1) if (22 <= y <= 40 and 18 <= x <= 68) else y
                r, g, b, a = src_px[x, sy]
                if a > 0:
                    # Furnace / glowing pixels: dramatic 4-stage plasma cycle (Deep Red -> Orange -> White-Hot Yellow -> Amber)
                    if r > b + 12 and r >= 55:
                        if frame == 0:
                            r, g, b = min(255, r + 40), g, b
                        elif frame == 1:
                            r, g, b = min(255, r + 115), min(255, g + 65), min(255, b + 15)
                        elif frame == 2:
                            r, g, b = 255, min(255, g + 155), min(255, b + 75)
                        elif frame == 3:
                            r, g, b = min(255, r + 85), min(255, g + 40), min(255, b + 10)
                f_px[x, y] = (r, g, b, a)
                
        # Animated pixel-art smoke puffs & embers rising from smokestacks
        for sx, sy in stack_tops[:2]:
            puff_y = max(2, sy - 2 - frame * 2)
            puff_x = sx + (frame % 2)
            for dx, dy in [(0,0), (1,0), (-1,0), (0,-1), (1,-1), (2,-1)]:
                px, py = puff_x + dx, puff_y + dy
                if 0 <= px < w and 0 <= py < h:
                    f_px[px, py] = (255, 200, 60, 255) if (dx == 0 and dy == 0 and frame in (1, 2)) else (150, 165, 185, 235)
        sheet.paste(f_img, (w * frame, 0))
    sheet.save(f"{base_sprites}/factory_hall_sheet.png")
    print("Saved factory_hall_sheet.png")

def build_player_and_drone_sheets():
    for name in ("player_core", "fabricator_drone"):
        base = Image.open(f"{base_sprites}/{name}.png").convert("RGBA")
        w, h = base.size
        sheet = Image.new("RGBA", (w * 4, h), (0, 0, 0, 0))
        src_px = base.load()
        for frame in range(4):
            f_img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
            f_px = f_img.load()
            boost = [0, 40, 80, 30][frame]
            for y in range(h):
                for x in range(w):
                    r, g, b, a = src_px[x, y]
                    if a > 0 and (b > r + 15 or g > r + 15 or (r > 160 and g > 120)):
                        r = min(255, r + boost // 2)
                        g = min(255, g + boost)
                        b = min(255, b + boost)
                    f_px[x, y] = (r, g, b, a)
            sheet.paste(f_img, (w * frame, 0))
        sheet.save(f"{base_sprites}/{name}_sheet.png")
        print(f"Saved {name}_sheet.png")

if __name__ == "__main__":
    build_mass_driver_sheet()
    build_mining_drill_sheet()
    build_factory_hall_sheet()
    build_player_and_drone_sheets()
