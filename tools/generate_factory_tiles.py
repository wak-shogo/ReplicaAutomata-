#!/usr/bin/env python3
"""
Deterministic 16-bit pixel-art generator for missing factory tile/machine sprites:
- conveyor_sheet.png (128x32, 4 frames of 32x32): animated steel belt rollers + chevron markers
- lift_shaft_sheet.png (128x32, 4 frames of 32x32): vertical elevator shaft moving upward
- inserter_sheet.png (128x32, 4 frames of 32x32): mechanical robotic arm transfer cycle
- smelter_sheet.png (224x56, 4 frames of 56x56): industrial blast furnace with pulsing magma hearth
- assembler_sheet.png (256x56, 4 frames of 64x56): robotic dual-gantry circuit assembler
- orbital_hub.png (160x80): orbital ring station / replica shipyard anchor above planet
"""

import os
from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "sprites")

DARK_OUTLINE = (12, 16, 24, 255)
STEEL_DARK = (44, 54, 70, 255)
STEEL_MID = (74, 88, 112, 255)
STEEL_LIGHT = (120, 140, 170, 255)
CYAN_GLOW = (50, 225, 255, 255)
AMBER_GLOW = (255, 175, 45, 255)
MAGMA_BRIGHT = (255, 110, 25, 255)
MAGMA_CORE = (255, 220, 90, 255)
GREEN_LED = (70, 235, 130, 255)


def make_conveyor_sheet():
    w, h = 32, 32
    sheet = Image.new("RGBA", (w * 4, h), (0, 0, 0, 0))
    for f in range(4):
        im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        # Belt chassis rails
        d.rectangle([0, 8, 31, 25], fill=DARK_OUTLINE)
        d.rectangle([0, 9, 31, 11], fill=STEEL_LIGHT)
        d.rectangle([0, 22, 31, 24], fill=STEEL_DARK)
        d.rectangle([0, 12, 31, 21], fill=(28, 34, 46, 255))
        # Animated treads & glowing directional chevrons pointing RIGHT
        shift = f * 4
        for x in range(-8, 36, 8):
            rx = x + shift
            d.line([(rx, 13), (rx, 20)], fill=(38, 46, 62, 255), width=1)
            # Chevron
            cx = rx + 2
            for dy in range(-2, 3):
                px = cx + (2 - abs(dy))
                py = 16 + dy
                if 0 <= px < 32:
                    col = AMBER_GLOW if abs(dy) <= 1 else (175, 110, 35, 255)
                    im.putpixel((px, py), col)
        # Support struts underneath
        for sx in (3, 15, 27):
            d.rectangle([sx, 25, sx + 2, 31], fill=STEEL_DARK, outline=DARK_OUTLINE)
        sheet.paste(im, (f * w, 0))
    sheet.save(os.path.join(OUT, "conveyor_sheet.png"))


def make_lift_shaft_sheet():
    w, h = 32, 32
    sheet = Image.new("RGBA", (w * 4, h), (0, 0, 0, 0))
    for f in range(4):
        im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        d.rectangle([6, 0, 25, 31], fill=(18, 24, 34, 235))
        d.rectangle([5, 0, 8, 31], fill=STEEL_MID, outline=DARK_OUTLINE)
        d.rectangle([23, 0, 26, 31], fill=STEEL_MID, outline=DARK_OUTLINE)
        # Moving lift rungs moving UP
        shift = f * 4
        for y in range(-8, 36, 8):
            ry = 31 - (y + shift)
            if 0 <= ry < 32:
                d.line([(9, ry), (22, ry)], fill=STEEL_DARK, width=1)
            # Upward cyan chevron
            cy = ry - 2
            for dx in range(-3, 4):
                px = 16 + dx
                py = cy + abs(dx) // 1
                if 0 <= py < 32:
                    im.putpixel((px, py), CYAN_GLOW if abs(dx) <= 1 else (30, 130, 175, 255))
        sheet.paste(im, (f * w, 0))
    sheet.save(os.path.join(OUT, "lift_shaft_sheet.png"))


def make_inserter_sheet():
    w, h = 32, 32
    sheet = Image.new("RGBA", (w * 4, h), (0, 0, 0, 0))
    arm_angles = [(-8, -10), (0, -14), (9, -9), (0, -13)]
    for f in range(4):
        im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        # Pedestal base
        d.rectangle([9, 22, 22, 30], fill=STEEL_DARK, outline=DARK_OUTLINE)
        d.rectangle([11, 20, 20, 24], fill=AMBER_GLOW, outline=DARK_OUTLINE)
        d.rectangle([13, 17, 18, 20], fill=STEEL_LIGHT)
        dx, dy = arm_angles[f]
        elbow = (16 + dx // 2, 14 + dy // 2)
        tip = (16 + dx, 14 + dy)
        d.line([(16, 18), elbow], fill=DARK_OUTLINE, width=4)
        d.line([(16, 18), elbow], fill=AMBER_GLOW, width=2)
        d.line([elbow, tip], fill=DARK_OUTLINE, width=4)
        d.line([elbow, tip], fill=STEEL_LIGHT, width=2)
        d.rectangle([tip[0] - 2, tip[1] - 2, tip[0] + 2, tip[1] + 2], fill=CYAN_GLOW, outline=DARK_OUTLINE)
        sheet.paste(im, (f * w, 0))
    sheet.save(os.path.join(OUT, "inserter_sheet.png"))


def make_smelter_sheet():
    w, h = 56, 56
    sheet = Image.new("RGBA", (w * 4, h), (0, 0, 0, 0))
    for f in range(4):
        im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        # Chimney stack on left
        d.rectangle([10, 3, 21, 22], fill=STEEL_DARK, outline=DARK_OUTLINE)
        d.rectangle([8, 2, 23, 6], fill=STEEL_MID, outline=DARK_OUTLINE)
        # Chimney glow / embers
        if f in (1, 2):
            d.rectangle([12, 0, 19, 2], fill=MAGMA_BRIGHT)
        # Main furnace body
        d.rectangle([6, 18, 49, 53], fill=STEEL_MID, outline=DARK_OUTLINE)
        d.rectangle([8, 20, 47, 25], fill=STEEL_LIGHT)
        # Heavy side pillars
        d.rectangle([6, 22, 12, 53], fill=STEEL_DARK, outline=DARK_OUTLINE)
        d.rectangle([43, 22, 49, 53], fill=STEEL_DARK, outline=DARK_OUTLINE)
        # Hearth opening
        d.rectangle([17, 30, 38, 49], fill=(20, 14, 18, 255), outline=DARK_OUTLINE)
        glow_h = 12 + (f % 2) * 3 + (2 if f == 2 else 0)
        d.rectangle([19, 48 - glow_h, 36, 48], fill=MAGMA_BRIGHT)
        d.rectangle([22, 50 - glow_h, 33, 48], fill=MAGMA_CORE)
        # Slanted grill bars over hearth
        for gx in (21, 27, 33):
            d.line([(gx, 31), (gx, 48)], fill=STEEL_DARK, width=1)
        # Cyan telemetry LED on upper right
        d.rectangle([38, 22, 42, 24], fill=CYAN_GLOW if f % 2 == 0 else GREEN_LED)
        # Base plate
        d.rectangle([4, 51, 51, 55], fill=STEEL_DARK, outline=DARK_OUTLINE)
        sheet.paste(im, (f * w, 0))
    sheet.save(os.path.join(OUT, "smelter_sheet.png"))


def make_assembler_sheet():
    w, h = 64, 56
    sheet = Image.new("RGBA", (w * 4, h), (0, 0, 0, 0))
    arm_offsets = [-6, 0, 6, 0]
    for f in range(4):
        im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        # Precision frame housing
        d.rectangle([4, 16, 59, 53], fill=STEEL_DARK, outline=DARK_OUTLINE)
        d.rectangle([7, 10, 56, 18], fill=STEEL_MID, outline=DARK_OUTLINE)
        # Overhead gantry skylight
        d.rectangle([12, 20, 51, 43], fill=(16, 28, 42, 255), outline=DARK_OUTLINE)
        # Circuit workbench inside
        d.rectangle([16, 37, 47, 42], fill=STEEL_MID)
        d.rectangle([26, 34, 37, 37], fill=GREEN_LED if f % 2 == 0 else CYAN_GLOW)
        # Animated robotic gantry arm
        ax = 32 + arm_offsets[f]
        d.rectangle([ax - 2, 21, ax + 2, 31], fill=AMBER_GLOW, outline=DARK_OUTLINE)
        if f in (1, 3):
            # Weld spark
            d.line([(ax, 31), (ax, 35)], fill=(210, 250, 255, 255), width=2)
        # Top antennas & status light
        d.rectangle([12, 4, 14, 10], fill=STEEL_LIGHT)
        d.rectangle([49, 4, 51, 10], fill=STEEL_LIGHT)
        d.rectangle([12, 3, 14, 5], fill=CYAN_GLOW)
        # Heavy base
        d.rectangle([2, 50, 61, 55], fill=STEEL_MID, outline=DARK_OUTLINE)
        sheet.paste(im, (f * w, 0))
    sheet.save(os.path.join(OUT, "assembler_sheet.png"))


def make_orbital_hub():
    w, h = 160, 80
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    # Central ring/truss
    d.rectangle([16, 36, 143, 45], fill=STEEL_MID, outline=DARK_OUTLINE)
    d.rectangle([24, 39, 135, 42], fill=CYAN_GLOW)
    # Solar wings left & right
    for sx in (6, 122):
        d.rectangle([sx, 14, sx + 30, 65], fill=(20, 48, 92, 255), outline=DARK_OUTLINE)
        for gy in range(18, 64, 8):
            d.line([(sx + 2, gy), (sx + 28, gy)], fill=(55, 115, 185, 255), width=1)
        d.line([(sx + 15, 14), (sx + 15, 65)], fill=STEEL_LIGHT, width=1)
    # Central Spherical Core + Docking Bay
    d.ellipse([54, 12, 105, 67], fill=STEEL_MID, outline=DARK_OUTLINE)
    d.ellipse([62, 20, 97, 59], fill=STEEL_DARK, outline=DARK_OUTLINE)
    d.ellipse([70, 28, 89, 51], fill=(22, 65, 95, 255), outline=CYAN_GLOW)
    d.ellipse([75, 33, 84, 46], fill=(130, 245, 255, 255))
    # Docking spines top & bottom
    d.rectangle([75, 3, 84, 15], fill=STEEL_LIGHT, outline=DARK_OUTLINE)
    d.rectangle([75, 65, 84, 76], fill=STEEL_LIGHT, outline=DARK_OUTLINE)
    d.rectangle([78, 72, 81, 78], fill=AMBER_GLOW)
    im.save(os.path.join(OUT, "orbital_hub.png"))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    make_conveyor_sheet()
    make_lift_shaft_sheet()
    make_inserter_sheet()
    make_smelter_sheet()
    make_assembler_sheet()
    make_orbital_hub()
    print("Generated all factory & orbital pixel sprites successfully.")
