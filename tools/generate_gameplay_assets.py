#!/usr/bin/env python3
"""
Procedural Pixel Art Generator for Star Replica: Automa Expansion
Generates high-definition 16-bit style Sci-Fi pixel art sprites:
- Mega-structures: Orbital Space Elevator, Dyson Ring Segment, Orbital Citadel, Stellar Warp Gate
- Corrupted Replica Entities: Corrupted Core Hub, Corrupted Flagship Cruiser
- Intermediate Crafting Items: Iron Plate, Copper Wire, Silicon Wafer, Microchip Circuit, Titan Alloy, Drone Unit
- Mega-structure Icons
"""

import os
import math
from PIL import Image, ImageDraw

SPRITES_DIR = "assets/sprites"
UI_DIR = "assets/ui"
ENV_DIR = "assets/environment"

os.makedirs(SPRITES_DIR, exist_ok=True)
os.makedirs(UI_DIR, exist_ok=True)
os.makedirs(ENV_DIR, exist_ok=True)

def create_space_elevator():
    # 96x160 pixel art orbital space elevator anchor station
    w, h = 96, 160
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    
    # Tether cables extending downwards
    for x in [42, 45, 50, 53]:
        d.line([(x, 70), (x, h - 1)], fill=(40, 70, 95, 230), width=1)
    d.line([(47, 70), (47, h - 1)], fill=(0, 220, 255, 240), width=2)
    
    # Lower tether clamps & docking rings
    for y in [90, 115, 140]:
        d.rectangle([38, y, 57, y + 6], fill=(25, 38, 55, 255), outline=(0, 180, 240, 255))
        d.rectangle([44, y + 2, 51, y + 4], fill=(0, 255, 220, 255))
        
    # Main orbital habitat station (Hexagonal heavy ring)
    # Upper ring
    d.polygon([(24, 25), (71, 25), (88, 48), (71, 72), (24, 72), (7, 48)], fill=(18, 26, 40, 255), outline=(50, 85, 125, 255))
    d.polygon([(30, 32), (65, 32), (78, 48), (65, 65), (30, 65), (17, 48)], fill=(12, 18, 28, 255), outline=(0, 200, 255, 255))
    
    # Central core reactor
    d.ellipse([36, 36, 59, 59], fill=(10, 35, 55, 255), outline=(0, 255, 230, 255))
    d.ellipse([42, 42, 53, 53], fill=(0, 230, 255, 255))
    d.ellipse([45, 45, 50, 50], fill=(230, 255, 255, 255))
    
    # Solar sails / radiator panels
    for sx in [2, 78]:
        d.rectangle([sx, 40, sx + 15, 56], fill=(15, 45, 80, 220), outline=(0, 150, 220, 255))
        d.line([(sx + 5, 40), (sx + 5, 56)], fill=(0, 220, 255, 255))
        d.line([(sx + 10, 40), (sx + 10, 56)], fill=(0, 220, 255, 255))
        
    # Communication spire
    d.line([(47, 8), (47, 25)], fill=(0, 200, 255, 255), width=2)
    d.rectangle([45, 4, 49, 8], fill=(255, 200, 50, 255))
    
    img.save(os.path.join(SPRITES_DIR, "megastructure_elevator.png"))
    print("Generated megastructure_elevator.png")

def create_dyson_ring():
    # 180x110 pixel art Dyson Ring Segment with plasma collector mirrors
    w, h = 180, 110
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    
    # Curved megastructure beam
    for r in range(120, 134):
        d.arc([w//2 - r, 20, w//2 + r, 20 + r * 2], start=210, end=330, fill=(30 + (r%3)*10, 45 + (r%3)*10, 70, 255))
    # Superconductor power line
    d.arc([w//2 - 127, 20, w//2 + 127, 20 + 254], start=210, end=330, fill=(255, 180, 40, 255), width=2)
    
    # 5 Giant Solar Collector Arrays
    for i in range(5):
        angle = math.radians(220 + i * 25)
        cx = int(w//2 + 127 * math.cos(angle))
        cy = int(147 + 127 * math.sin(angle))
        
        # Mirror panel
        d.rectangle([cx - 12, cy - 14, cx + 12, cy + 14], fill=(16, 28, 48, 255), outline=(0, 200, 255, 255))
        d.rectangle([cx - 8, cy - 10, cx + 8, cy + 10], fill=(255, 140, 20, 220), outline=(255, 230, 80, 255))
        d.ellipse([cx - 4, cy - 4, cx + 4, cy + 4], fill=(255, 255, 255, 255))
        
    # Central High-Energy Plasma Collector Hub
    chx, chy = w // 2, 28
    d.polygon([(chx - 24, chy + 12), (chx + 24, chy + 12), (chx + 32, chy - 12), (chx - 32, chy - 12)], 
              fill=(22, 35, 58, 255), outline=(0, 220, 255, 255))
    d.ellipse([chx - 12, chy - 10, chx + 12, chy + 10], fill=(255, 220, 50, 255), outline=(255, 255, 255, 255))
    
    img.save(os.path.join(SPRITES_DIR, "megastructure_dyson.png"))
    print("Generated megastructure_dyson.png")

def create_orbital_citadel():
    # 128x128 heavy defense orbital fortress
    w, h = 128, 128
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    
    cx, cy = w // 2, h // 2
    # Heavy octagonal citadel hull
    pts = []
    for a in range(8):
        ang = a * (math.pi / 4.0) + (math.pi / 8.0)
        pts.append((cx + int(54 * math.cos(ang)), cy + int(54 * math.sin(ang))))
    d.polygon(pts, fill=(20, 28, 42, 255), outline=(60, 95, 140, 255))
    
    # Armor plates layering
    pts_inner = []
    for a in range(8):
        ang = a * (math.pi / 4.0) + (math.pi / 8.0)
        pts_inner.append((cx + int(40 * math.cos(ang)), cy + int(40 * math.sin(ang))))
    d.polygon(pts_inner, fill=(12, 18, 30, 255), outline=(0, 220, 255, 255))
    
    # 4 Heavy Defense Turrets
    for ang in [0, math.pi/2, math.pi, 3*math.pi/2]:
        tx = cx + int(48 * math.cos(ang))
        ty = cy + int(48 * math.sin(ang))
        d.ellipse([tx - 8, ty - 8, tx + 8, ty + 8], fill=(30, 45, 68, 255), outline=(0, 180, 240, 255))
        d.line([(tx, ty), (tx + int(14 * math.cos(ang)), ty + int(14 * math.sin(ang)))], fill=(0, 255, 255, 255), width=3)
        
    # Central Quantum Shield Core
    d.ellipse([cx - 20, cy - 20, cx + 20, cy + 20], fill=(8, 32, 54, 255), outline=(0, 255, 220, 255))
    d.ellipse([cx - 10, cy - 10, cx + 10, cy + 10], fill=(0, 230, 255, 255), outline=(255, 255, 255, 255))
    
    img.save(os.path.join(SPRITES_DIR, "megastructure_citadel.png"))
    print("Generated megastructure_citadel.png")

def create_warp_gate():
    # 130x130 Stellar Warp Gate / Heavy Accelerator
    w, h = 130, 130
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    
    cx, cy = w // 2, h // 2
    # Outer Superconductor Ring
    d.ellipse([cx - 58, cy - 58, cx + 58, cy + 58], fill=None, outline=(35, 55, 85, 255), width=6)
    d.ellipse([cx - 56, cy - 56, cx + 56, cy + 56], fill=None, outline=(0, 220, 255, 255), width=2)
    
    # 6 Accelerator Emitters
    for i in range(6):
        ang = i * (math.pi / 3.0)
        px = cx + int(56 * math.cos(ang))
        py = cy + int(56 * math.sin(ang))
        d.rectangle([px - 6, py - 6, px + 6, py + 6], fill=(20, 32, 50, 255), outline=(255, 180, 30, 255))
        d.line([(px, py), (cx + int(32 * math.cos(ang)), cy + int(32 * math.sin(ang)))], fill=(0, 255, 240, 200), width=2)
        
    # Event Horizon Singularity (Purple / Blue Event Spiral)
    d.ellipse([cx - 28, cy - 28, cx + 28, cy + 28], fill=(15, 8, 30, 255), outline=(180, 60, 255, 255))
    d.ellipse([cx - 16, cy - 16, cx + 16, cy + 16], fill=(140, 30, 240, 255), outline=(230, 150, 255, 255))
    d.ellipse([cx - 6, cy - 6, cx + 6, cy + 6], fill=(255, 255, 255, 255))
    
    img.save(os.path.join(SPRITES_DIR, "megastructure_warpgate.png"))
    print("Generated megastructure_warpgate.png")

def create_corrupted_core_hub():
    # 120x120 Corrupted Swarm Hive Core Boss Base
    w, h = 120, 120
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    
    cx, cy = w // 2, h // 2
    # Spiky organic-mechanical hull
    pts = []
    for a in range(12):
        r = 52 if a % 2 == 0 else 34
        ang = a * (math.pi / 6.0)
        pts.append((cx + int(r * math.cos(ang)), cy + int(r * math.sin(ang))))
    d.polygon(pts, fill=(35, 10, 18, 255), outline=(160, 25, 45, 255))
    
    # Internal dark plating
    pts2 = []
    for a in range(12):
        r = 38 if a % 2 == 0 else 24
        ang = a * (math.pi / 6.0)
        pts2.append((cx + int(r * math.cos(ang)), cy + int(r * math.sin(ang))))
    d.polygon(pts2, fill=(20, 5, 10, 255), outline=(255, 40, 60, 255))
    
    # Pulsing Crimson Eye
    d.ellipse([cx - 18, cy - 18, cx + 18, cy + 18], fill=(60, 5, 15, 255), outline=(255, 50, 70, 255))
    d.ellipse([cx - 11, cy - 11, cx + 11, cy + 11], fill=(255, 20, 40, 255), outline=(255, 180, 180, 255))
    d.ellipse([cx - 4, cy - 4, cx + 4, cy + 4], fill=(255, 255, 255, 255))
    
    img.save(os.path.join(SPRITES_DIR, "corrupted_core_hub.png"))
    print("Generated corrupted_core_hub.png")

def create_corrupted_cruiser():
    # 48x48 Corrupted Carrier Cruiser
    w, h = 48, 48
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    
    pts = [(24, 4), (42, 22), (36, 42), (24, 34), (12, 42), (6, 22)]
    d.polygon(pts, fill=(30, 8, 14, 255), outline=(220, 30, 50, 255))
    d.rectangle([20, 14, 28, 26], fill=(255, 40, 60, 255), outline=(255, 180, 180, 255))
    
    img.save(os.path.join(SPRITES_DIR, "corrupted_cruiser.png"))
    print("Generated corrupted_cruiser.png")

def create_item_icons():
    # 24x24 icons for crafting
    items = {
        "item_plate_fe": (lambda d: [
            d.polygon([(4, 6), (18, 6), (20, 18), (6, 18)], fill=(65, 85, 110, 255), outline=(0, 210, 255, 255)),
            d.line([(7, 10), (16, 10)], fill=(180, 230, 255, 255)),
            d.line([(7, 14), (17, 14)], fill=(120, 160, 200, 255))
        ]),
        "item_wire_cu": (lambda d: [
            d.ellipse([4, 4, 20, 20], fill=None, outline=(220, 110, 30, 255), width=3),
            d.ellipse([7, 7, 17, 17], fill=None, outline=(255, 165, 60, 255), width=2),
            d.rectangle([10, 2, 14, 8], fill=(255, 200, 100, 255))
        ]),
        "item_silicon_wafer": (lambda d: [
            d.polygon([(6, 2), (18, 2), (22, 6), (22, 18), (18, 22), (6, 22), (2, 18), (2, 6)], 
                      fill=(15, 38, 48, 255), outline=(0, 255, 180, 255)),
            d.line([(6, 12), (18, 12)], fill=(0, 240, 210, 255)),
            d.line([(12, 6), (12, 18)], fill=(0, 240, 210, 255))
        ]),
        "item_circuit": (lambda d: [
            d.rectangle([3, 4, 21, 20], fill=(18, 50, 35, 255), outline=(50, 180, 90, 255)),
            d.rectangle([8, 8, 16, 16], fill=(15, 20, 25, 255), outline=(255, 215, 0, 255)),
            # golden pins
            [d.line([(x, 2), (x, 4)], fill=(255, 215, 0, 255)) for x in [6, 10, 14, 18]],
            [d.line([(x, 20), (x, 22)], fill=(255, 215, 0, 255)) for x in [6, 10, 14, 18]]
        ]),
        "item_alloy": (lambda d: [
            d.polygon([(3, 14), (12, 4), (21, 14), (12, 20)], fill=(90, 45, 125, 255), outline=(210, 120, 255, 255)),
            d.polygon([(6, 13), (12, 7), (18, 13), (12, 18)], fill=(130, 65, 180, 255), outline=(255, 200, 255, 255))
        ]),
        "item_drone_unit": (lambda d: [
            d.ellipse([7, 7, 17, 17], fill=(12, 24, 38, 255), outline=(0, 220, 255, 255)),
            d.ellipse([10, 10, 14, 14], fill=(0, 240, 255, 255)),
            d.line([(4, 12), (7, 12)], fill=(0, 200, 255, 255), width=2),
            d.line([(17, 12), (20, 12)], fill=(0, 200, 255, 255), width=2),
            d.line([(12, 4), (12, 7)], fill=(0, 200, 255, 255), width=2),
            d.line([(12, 17), (12, 20)], fill=(0, 200, 255, 255), width=2)
        ]),
        "icon_elevator": (lambda d: [
            d.rectangle([8, 2, 16, 7], fill=(0, 200, 255, 255)),
            d.line([(12, 7), (12, 22)], fill=(0, 255, 255, 255), width=2),
            d.rectangle([9, 13, 15, 17], fill=(255, 200, 50, 255))
        ]),
        "icon_dyson": (lambda d: [
            d.arc([2, 4, 22, 24], start=190, end=350, fill=(255, 180, 40, 255), width=3),
            d.ellipse([9, 9, 15, 15], fill=(255, 240, 80, 255))
        ]),
        "icon_citadel": (lambda d: [
            d.rectangle([5, 5, 19, 19], fill=(20, 30, 48, 255), outline=(0, 220, 255, 255)),
            d.ellipse([9, 9, 15, 15], fill=(0, 240, 255, 255)),
            d.line([(12, 2), (12, 5)], fill=(0, 255, 255, 255), width=2),
            d.line([(12, 19), (12, 22)], fill=(0, 255, 255, 255), width=2)
        ]),
        "icon_warpgate": (lambda d: [
            d.ellipse([3, 3, 21, 21], fill=(18, 10, 35, 255), outline=(180, 60, 255, 255), width=2),
            d.ellipse([8, 8, 16, 16], fill=(140, 30, 240, 255), outline=(255, 255, 255, 255))
        ])
    }
    
    for name, draw_fn in items.items():
        img = Image.new("RGBA", (24, 24), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        draw_fn(d)
        img.save(os.path.join(UI_DIR, f"{name}.png"))
        print(f"Generated UI icon: {name}.png")

def create_defense_turret():
    # 32x32 Ground-based Railgun Defense Turret
    w, h = 32, 32
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # Heavy base
    d.polygon([(4, 28), (27, 28), (23, 20), (8, 20)], fill=(20, 30, 48, 255), outline=(0, 200, 255, 255))
    # Turret dome
    d.ellipse([9, 12, 22, 25], fill=(12, 20, 35, 255), outline=(0, 255, 220, 255))
    # Dual Railgun Barrels pointing up
    d.line([(13, 14), (13, 2)], fill=(0, 240, 255, 255), width=2)
    d.line([(18, 14), (18, 2)], fill=(0, 240, 255, 255), width=2)
    # Muzzle flash capacitor
    d.rectangle([11, 2, 20, 5], fill=(255, 220, 50, 255))
    img.save(os.path.join(SPRITES_DIR, "defense_turret.png"))
    print("Generated defense_turret.png")

def create_corrupted_bomber():
    # 36x36 Corrupted Dive Bomber
    w, h = 36, 36
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # Forward-swept menacing red hull
    pts = [(18, 32), (32, 10), (28, 4), (18, 14), (8, 4), (4, 10)]
    d.polygon(pts, fill=(35, 8, 15, 255), outline=(255, 40, 60, 255))
    # Plasma bomb payload
    d.ellipse([14, 16, 22, 24], fill=(255, 30, 50, 255), outline=(255, 220, 100, 255))
    img.save(os.path.join(SPRITES_DIR, "corrupted_bomber.png"))
    print("Generated corrupted_bomber.png")

def create_geothermal_plant():
    # 40x48 Magma Geothermal Power Station
    w, h = 40, 48
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # Heat sink base
    d.rectangle([6, 26, 34, 46], fill=(28, 16, 12, 255), outline=(255, 100, 20, 255))
    # Heat pipes into magma
    for px in [12, 20, 28]:
        d.line([(px, 32), (px, 47)], fill=(255, 140, 20, 255), width=2)
    # Steam turbine generator top
    d.polygon([(10, 26), (30, 26), (25, 8), (15, 8)], fill=(18, 28, 42, 255), outline=(0, 220, 255, 255))
    d.ellipse([16, 12, 24, 20], fill=(0, 255, 220, 255))
    img.save(os.path.join(SPRITES_DIR, "geothermal_plant.png"))
    print("Generated geothermal_plant.png")

def create_solar_array():
    # 44x24 Ground Solar Panel Array
    w, h = 44, 24
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # Stand legs
    d.line([(8, 22), (16, 12)], fill=(60, 80, 100, 255), width=2)
    d.line([(36, 22), (28, 12)], fill=(60, 80, 100, 255), width=2)
    # Angled photovoltaic blue panel
    d.polygon([(4, 12), (40, 12), (36, 4), (8, 4)], fill=(10, 35, 75, 255), outline=(0, 200, 255, 255))
    # Grid lines
    for gx in [14, 22, 30]:
        d.line([(gx, 4), (gx - 2, 12)], fill=(0, 240, 255, 220))
    img.save(os.path.join(SPRITES_DIR, "solar_array.png"))
    print("Generated solar_array.png")

def create_extra_ui_icons():
    icons = {
        "tool_turret": (lambda d: [
            d.polygon([(3, 20), (20, 20), (17, 14), (6, 14)], fill=(20, 30, 45, 255), outline=(0, 200, 255, 255)),
            d.ellipse([7, 8, 16, 17], fill=(12, 22, 38, 255), outline=(0, 255, 220, 255)),
            d.line([(10, 10), (10, 2)], fill=(0, 240, 255, 255), width=2),
            d.line([(13, 10), (13, 2)], fill=(0, 240, 255, 255), width=2)
        ]),
        "tool_geothermal": (lambda d: [
            d.rectangle([4, 12, 19, 21], fill=(40, 15, 10, 255), outline=(255, 110, 30, 255)),
            d.line([(8, 14), (8, 21)], fill=(255, 160, 40, 255), width=2),
            d.line([(15, 14), (15, 21)], fill=(255, 160, 40, 255), width=2),
            d.polygon([(6, 12), (17, 12), (14, 4), (9, 4)], fill=(20, 30, 45, 255), outline=(0, 220, 255, 255))
        ]),
        "tool_solar": (lambda d: [
            d.polygon([(2, 16), (21, 16), (19, 7), (4, 7)], fill=(12, 40, 80, 255), outline=(0, 220, 255, 255)),
            d.line([(11, 7), (11, 16)], fill=(0, 255, 255, 255)),
            d.line([(6, 19), (10, 16)], fill=(80, 100, 120, 255), width=2),
            d.line([(17, 19), (13, 16)], fill=(80, 100, 120, 255), width=2)
        ])
    }
    for name, draw_fn in icons.items():
        img = Image.new("RGBA", (24, 24), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        draw_fn(d)
        img.save(os.path.join(UI_DIR, f"{name}.png"))
        print(f"Generated UI icon: {name}.png")

if __name__ == "__main__":
    create_space_elevator()
    create_dyson_ring()
    create_orbital_citadel()
    create_warp_gate()
    create_corrupted_core_hub()
    create_corrupted_cruiser()
    create_item_icons()
    create_defense_turret()
    create_corrupted_bomber()
    create_geothermal_plant()
    create_solar_array()
    create_extra_ui_icons()
    print("ALL EXPANSION SPRITES GENERATED SUCCESSFULLY!")
