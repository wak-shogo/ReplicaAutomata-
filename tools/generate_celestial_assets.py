#!/usr/bin/env python3
"""
Procedural Pixel Art Generator for Star Replica: Automa - Celestial Expansion
Generates high-definition 16-bit Sci-Fi pixel art assets for celestial bodies and exotic space resources:
- Star / Sun (Helios-Prime): Fusion core, solar flares, glowing corona
- Black Hole / Singularity (Gargantua-Zero): Event horizon, glowing accretion disk, photon ring
- Comet (Neowise-Omega): Ice nucleus, long luminous ion tail & dust trail
- Pulsar / Neutron Star: High density cyan core, magnetic loops, relativistic jet beams
- Asteroid: Cratered rock with metallic crystalline veins
- Exotic Resource Icons: Plasma, Dark Matter, Comet Ice, Helium-3, Neutronium
"""

import os
import math
import random
from PIL import Image, ImageDraw

ENV_DIR = "assets/environment"
UI_DIR = "assets/ui"
os.makedirs(ENV_DIR, exist_ok=True)
os.makedirs(UI_DIR, exist_ok=True)

def create_star():
    w, h = 256, 256
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx, cy = w // 2, h // 2
    r_core = 70

    # 1. Corona glow (gradient rings)
    for r in range(120, r_core, -2):
        alpha = int(pow((120 - r) / (120 - r_core), 2.2) * 160)
        col = (255, 140, 20, alpha)
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=col)

    # 2. Solar Prominences / Flares (plasma arcs)
    for i in range(16):
        angle = (i * math.pi * 2) / 16.0 + 0.15 * math.sin(i * 1.5)
        flare_len = r_core + random.randint(25, 48)
        fx = cx + math.cos(angle) * flare_len
        fy = cy + math.sin(angle) * flare_len
        # Curved loop
        mid_angle = angle + 0.12
        mx = cx + math.cos(mid_angle) * (flare_len + 10)
        my = cy + math.sin(mid_angle) * (flare_len + 10)
        d.line([(cx + math.cos(angle)*r_core, cy + math.sin(angle)*r_core), (mx, my), (fx, fy)], fill=(255, 200, 50, 220), width=3)
        d.ellipse([fx - 4, fy - 4, fx + 4, fy + 4], fill=(255, 240, 160, 240))

    # 3. Main Star Core Sphere
    for r in range(r_core, 0, -2):
        factor = 1.0 - (r / float(r_core))
        # Orange to fiery yellow to brilliant white core
        cr = 255
        cg = int(120 + 135 * factor)
        cb = int(30 + 225 * pow(factor, 2.5))
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(cr, cg, cb, 255))

    # Granulation spots
    for _ in range(40):
        ga = random.uniform(0, math.pi * 2)
        gr = random.uniform(0, r_core - 8)
        gx = cx + math.cos(ga) * gr
        gy = cy + math.sin(ga) * gr
        d.ellipse([gx - 3, gy - 3, gx + 3, gy + 3], fill=(255, 235, 120, 180))

    out_p = os.path.join(ENV_DIR, "celestial_sun.png")
    img.save(out_p)
    print(f"Generated {out_p}")

def create_black_hole():
    w, h = 240, 240
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx, cy = w // 2, h // 2
    r_event = 38  # Event Horizon

    # 1. Relativistic Jets (Vertical polar beams)
    for y_offset in [-1, 1]:
        for length in range(15, 110, 2):
            w_beam = max(1, int(10 * (1.0 - length / 110.0)))
            alpha = int((1.0 - length / 110.0) * 180)
            jet_y = cy + y_offset * length
            d.line([(cx - w_beam, jet_y), (cx + w_beam, jet_y)], fill=(0, 240, 255, alpha))

    # 2. Accretion Disk (Tilted glowing rings: neon cyan & burning orange)
    # Background half of disk (drawn behind horizon)
    for r in range(105, r_event + 6, -2):
        factor = (105 - r) / float(105 - r_event)
        alpha = int(pow(factor, 1.4) * 230)
        # Cyan-orange blend
        col = (int(255 * factor), int(100 + 140 * factor), int(255 * (1.0 - factor * 0.6)), alpha)
        rx = r
        ry = int(r * 0.32)
        # Draw upper ellipse (back of disk)
        d.arc([cx - rx, cy - ry - 4, cx + rx, cy + ry - 4], 180, 360, fill=col, width=3)

    # 3. Photon Sphere (Gravitational Lensing Halo around horizon)
    for r in range(r_event + 14, r_event, -1):
        alpha = int((r_event + 14 - r) / 14.0 * 255)
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(255, 180, 50, alpha))

    # 4. Pure Black Event Horizon (Singularity Core)
    d.ellipse([cx - r_event, cy - r_event, cx + r_event, cy + r_event], fill=(0, 0, 0, 255), outline=(0, 220, 255, 255), width=1)

    # 5. Foreground half of Accretion Disk (crossing in front of event horizon)
    for r in range(105, r_event + 6, -2):
        factor = (105 - r) / float(105 - r_event)
        alpha = int(pow(factor, 1.2) * 240)
        col = (int(255 * factor), int(120 + 130 * (1.0 - factor)), int(255 * (1.0 - factor * 0.4)), alpha)
        rx = r
        ry = int(r * 0.32)
        # Front arc (0 to 180 deg)
        d.arc([cx - rx, cy - ry + 4, cx + rx, cy + ry + 4], 0, 180, fill=col, width=3)
        # Highlights
        if r % 8 == 0:
            d.arc([cx - rx + 2, cy - ry + 5, cx + rx - 2, cy + ry + 5], 10, 170, fill=(255, 255, 255, int(alpha * 0.6)), width=1)

    out_p = os.path.join(ENV_DIR, "celestial_blackhole.png")
    img.save(out_p)
    print(f"Generated {out_p}")

def create_comet():
    w, h = 160, 64
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx, cy = 135, h // 2  # Comet head on the right, tail sweeps to the left

    # 1. Ion Tail & Dust Tail (Sweeping backwards)
    for x in range(cx, 0, -2):
        dist = cx - x
        width = int(6 + dist * 0.32)
        alpha = int(max(0, 220 * (1.0 - dist / float(cx))))
        # Blue ion glow
        d.ellipse([x - 2, cy - width, x + 4, cy + width], fill=(0, 180, 255, int(alpha * 0.5)))
        # Cyan-white dense central tail
        core_w = max(1, int(width * 0.35))
        d.ellipse([x, cy - core_w, x + 3, cy + core_w], fill=(180, 240, 255, alpha))

    # 2. Coma (Luminous halo around nucleus)
    for r in range(24, 0, -2):
        alpha = int((24 - r) / 24.0 * 240)
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(120, 220, 255, alpha))

    # 3. Ice Nucleus (Craggy frozen core)
    d.ellipse([cx - 8, cy - 7, cx + 7, cy + 8], fill=(220, 245, 255, 255), outline=(0, 200, 255, 255))
    d.ellipse([cx - 4, cy - 4, cx + 4, cy + 4], fill=(255, 255, 255, 255))
    d.point([(cx - 2, cy + 2), (cx + 3, cy - 2)], fill=(100, 180, 230, 255))

    out_p = os.path.join(ENV_DIR, "celestial_comet.png")
    img.save(out_p)
    print(f"Generated {out_p}")

def create_pulsar():
    w, h = 128, 128
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx, cy = w // 2, h // 2
    r_core = 14

    # 1. Relativistic Precession Beams (diagonal pulsed beams)
    for angle_deg in [45, 225]:
        rad = math.radians(angle_deg)
        cos_a = math.cos(rad)
        sin_a = math.sin(rad)
        for dist in range(r_core, 60, 2):
            bx = cx + cos_a * dist
            by = cy + sin_a * dist
            alpha = int(240 * (1.0 - dist / 60.0))
            bw = max(1, int(5 * (1.0 - dist / 60.0)))
            d.ellipse([bx - bw, by - bw, bx + bw, by + bw], fill=(0, 255, 240, alpha))
            d.point([(bx, by)], fill=(255, 255, 255, alpha))

    # 2. Magnetic Loop Arcs
    d.arc([cx - 35, cy - 18, cx + 35, cy + 18], 0, 360, fill=(180, 100, 255, 140), width=1)
    d.arc([cx - 24, cy - 28, cx + 24, cy + 28], 0, 360, fill=(180, 100, 255, 140), width=1)

    # 3. High Density Neutron Core
    for r in range(28, 0, -2):
        alpha = int((28 - r) / 28.0 * 200)
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(0, 220, 255, alpha))

    d.ellipse([cx - r_core, cy - r_core, cx + r_core, cy + r_core], fill=(230, 250, 255, 255), outline=(0, 255, 220, 255), width=2)
    d.ellipse([cx - 6, cy - 6, cx + 6, cy + 6], fill=(255, 255, 255, 255))

    out_p = os.path.join(ENV_DIR, "celestial_pulsar.png")
    img.save(out_p)
    print(f"Generated {out_p}")

def create_asteroid():
    w, h = 48, 48
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx, cy = w // 2, h // 2

    # Craggy polygon points
    points = [
        (cx - 16, cy - 8), (cx - 8, cy - 18), (cx + 8, cy - 17), (cx + 17, cy - 6),
        (cx + 19, cy + 8), (cx + 10, cy + 18), (cx - 6, cy + 19), (cx - 18, cy + 7)
    ]
    d.polygon(points, fill=(65, 75, 88, 255), outline=(100, 120, 145, 255))
    # Crater indentations
    d.ellipse([cx - 8, cy - 6, cx - 1, cy + 1], fill=(42, 50, 62, 255), outline=(30, 38, 48, 255))
    d.ellipse([cx + 4, cy + 3, cx + 11, cy + 10], fill=(42, 50, 62, 255), outline=(30, 38, 48, 255))
    # Metallic/crystalline ore glint
    d.rectangle([cx - 2, cy - 10, cx + 2, cy - 7], fill=(0, 230, 255, 255))
    d.rectangle([cx + 6, cy - 8, cx + 9, cy - 5], fill=(255, 180, 50, 255))

    out_p = os.path.join(ENV_DIR, "celestial_asteroid.png")
    img.save(out_p)
    print(f"Generated {out_p}")

def create_resource_icons():
    # 28x28 Minimal Sci-Fi Pictogram Icons for new exotic resources
    # 1. Plasma (Solar Fire / Pure energy)
    p_img = Image.new("RGBA", (28, 28), (0, 0, 0, 0))
    pd = ImageDraw.Draw(p_img)
    pd.ellipse([4, 4, 23, 23], fill=(255, 140, 20, 255), outline=(255, 230, 80, 255), width=2)
    pd.ellipse([8, 8, 19, 19], fill=(255, 255, 120, 255))
    pd.ellipse([11, 11, 16, 16], fill=(255, 255, 255, 255))
    p_img.save(os.path.join(UI_DIR, "res_plasma.png"))

    # 2. Dark Matter (Singularity / Black Sphere with violet aura)
    dm_img = Image.new("RGBA", (28, 28), (0, 0, 0, 0))
    dmd = ImageDraw.Draw(dm_img)
    dmd.ellipse([2, 2, 25, 25], fill=(80, 0, 120, 160), outline=(180, 60, 255, 255), width=1)
    dmd.ellipse([6, 6, 21, 21], fill=(12, 5, 22, 255), outline=(0, 220, 255, 255), width=1)
    dmd.ellipse([10, 10, 17, 17], fill=(0, 0, 0, 255))
    dmd.point([(13, 13), (14, 14)], fill=(0, 255, 255, 255))
    dm_img.save(os.path.join(UI_DIR, "res_darkmatter.png"))

    # 3. Ice / Deuterium (Comet Ice crystal)
    ice_img = Image.new("RGBA", (28, 28), (0, 0, 0, 0))
    iced = ImageDraw.Draw(ice_img)
    # Diamond crystal
    iced.polygon([(14, 3), (24, 14), (14, 24), (3, 14)], fill=(120, 220, 255, 220), outline=(220, 255, 255, 255))
    iced.line([(14, 3), (14, 24)], fill=(255, 255, 255, 255), width=1)
    iced.line([(3, 14), (24, 14)], fill=(255, 255, 255, 255), width=1)
    ice_img.save(os.path.join(UI_DIR, "res_ice.png"))

    # 4. Helium-3 (Moon / Isotope canister)
    he3_img = Image.new("RGBA", (28, 28), (0, 0, 0, 0))
    he3d = ImageDraw.Draw(he3_img)
    he3d.rounded_rectangle([6, 4, 21, 23], radius=4, fill=(35, 55, 75, 255), outline=(0, 200, 255, 255), width=1)
    he3d.rectangle([9, 8, 18, 19], fill=(0, 180, 240, 255))
    he3d.ellipse([11, 11, 16, 16], fill=(230, 255, 255, 255))
    he3_img.save(os.path.join(UI_DIR, "res_he3.png"))

    # 5. Neutronium (Pulsar / Ultra-dense cube)
    nt_img = Image.new("RGBA", (28, 28), (0, 0, 0, 0))
    ntd = ImageDraw.Draw(nt_img)
    ntd.rectangle([5, 5, 22, 22], fill=(20, 30, 48, 255), outline=(0, 255, 200, 255), width=2)
    ntd.rectangle([9, 9, 18, 18], fill=(0, 255, 230, 255))
    ntd.point([(13, 13), (14, 14)], fill=(255, 255, 255, 255))
    nt_img.save(os.path.join(UI_DIR, "res_neutronium.png"))

    print("Generated exotic resource icons.")

if __name__ == "__main__":
    create_star()
    create_black_hole()
    create_comet()
    create_pulsar()
    create_asteroid()
    create_resource_icons()
    print("ALL CELESTIAL ASSETS GENERATED SUCCESSFULLY!")
