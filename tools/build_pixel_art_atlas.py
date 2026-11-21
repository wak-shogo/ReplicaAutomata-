"""
STAR REPLICA: AUTOMA - High-Craft HD-2D Pixel Art Generator
Generates crisp, shaded, beveled 16-bit/HD-2D pixel art sprites, terrain tiles,
ore crystal clusters, industrial buildings, celestial bodies, and item icons
inspired directly by docs/art/target_gameplay_concept.jpeg.
"""
import math
import os
import random
from PIL import Image, ImageDraw

OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "art")
os.makedirs(OUT_DIR, exist_ok=True)
os.makedirs(os.path.join(OUT_DIR, "celestials"), exist_ok=True)


def clamp(v, lo=0, hi=255):
    return max(lo, min(hi, int(v)))


def rgba(r, g, b, a=255):
    return (clamp(r), clamp(g), clamp(b), clamp(a))


def lerp_col(c1, c2, t):
    t = max(0.0, min(1.0, t))
    return tuple(clamp(c1[i] + (c2[i] - c1[i]) * t) for i in range(4))


def hash2(x, y, seed=1337):
    n = (x * 374761393 + y * 668265263 + seed * 1442695041) & 0xFFFFFFFF
    n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((n ^ (n >> 16)) & 0xFFFFFF) / float(0xFFFFFF)


def vnoise(x, y, scale=8.0, seed=1337):
    fx = x / scale
    fy = y / scale
    ix = int(math.floor(fx))
    iy = int(math.floor(fy))
    tx = fx - ix
    ty = fy - iy
    tx = tx * tx * (3.0 - 2.0 * tx)
    ty = ty * ty * (3.0 - 2.0 * ty)
    a = hash2(ix, iy, seed)
    b = hash2(ix + 1, iy, seed)
    c = hash2(ix, iy + 1, seed)
    d = hash2(ix + 1, iy + 1, seed)
    return (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty


def add_outline(img, outline_col=(10, 14, 22, 255)):
    w, h = img.size
    src = img.load()
    out = img.copy()
    dst = out.load()
    for y in range(h):
        for x in range(w):
            if src[x, y][3] > 20:
                continue
            for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and src[nx, ny][3] > 180:
                    dst[x, y] = outline_col
                    break
    return out


def panel_box(draw, x0, y0, x1, y1, base, hi, lo, border=(14, 18, 28, 255), rivets=True):
    draw.rectangle([x0, y0, x1, y1], fill=base, outline=border)
    if x1 - x0 >= 3 and y1 - y0 >= 3:
        draw.line([x0 + 1, y0 + 1, x1 - 1, y0 + 1], fill=hi)
        draw.line([x0 + 1, y0 + 1, x0 + 1, y1 - 1], fill=hi)
        draw.line([x0 + 1, y1 - 1, x1 - 1, y1 - 1], fill=lo)
        draw.line([x1 - 1, y0 + 1, x1 - 1, y1 - 1], fill=lo)
    if rivets and (x1 - x0) >= 8 and (y1 - y0) >= 8:
        for rx in (x0 + 2, x1 - 2):
            for ry in (y0 + 2, y1 - 2):
                draw.point((rx, ry), fill=lo)


def draw_hazard_stripe(draw, x0, y0, x1, y1):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            stripe = ((x + y) // 2) % 2 == 0
            draw.point((x, y), fill=(224, 168, 36, 255) if stripe else (28, 30, 36, 255))


# ------------------------------------------------------------------------------
# 1. SEAMLESS TERRAIN TILES (64x64)
# ------------------------------------------------------------------------------
def pnoise(x, y, period=64, freq=3.0, seed=1337):
    """Truly seamless toroidal periodic noise on [0, period)."""
    u = (x % period) / float(period) * math.tau
    v = (y % period) / float(period) * math.tau
    # Sample 2D periodic trig-warped value noise
    cx, sx = math.cos(u) * freq, math.sin(u) * freq
    cy, sy = math.cos(v) * freq, math.sin(v) * freq
    return (
        vnoise(cx + 31.0, cy + 17.0, 1.35, seed) * 0.5
        + vnoise(sx + 53.0, sy + 29.0, 1.35, seed + 17) * 0.5
    )


def make_terrain_tiles():
    # Regolith: warm sandstone/ochre matching concept art upper crust (100% seamless!)
    im = Image.new("RGBA", (64, 64))
    px = im.load()
    pal_reg = [
        (114, 84, 54, 255),
        (142, 108, 70, 255),
        (170, 134, 88, 255),
        (196, 158, 108, 255),
        (216, 180, 130, 255),
    ]
    for y in range(64):
        strata = math.sin((y / 64.0) * math.tau * 2.0) * 0.14
        for x in range(64):
            n = (
                pnoise(x, y, 64, 2.2, 101) * 0.55
                + pnoise(x, y, 64, 5.5, 102) * 0.30
                + hash2(x, y, 103) * 0.15
                + strata
            )
            idx = clamp(n * len(pal_reg), 0, len(pal_reg) - 1)
            px[x, y] = pal_reg[idx]
            if hash2(x, y, 109) > 0.968:
                px[x, y] = (86, 62, 40, 255)
    im.save(os.path.join(OUT_DIR, "terrain_regolith.png"))

    # Basalt: dark blue-slate fractured cavern crust (100% seamless!)
    im = Image.new("RGBA", (64, 64))
    px = im.load()
    pal_bas = [
        (18, 22, 30, 255),
        (26, 32, 44, 255),
        (36, 44, 58, 255),
        (48, 58, 74, 255),
        (60, 72, 90, 255),
    ]
    for y in range(64):
        for x in range(64):
            n = (
                pnoise(x, y, 64, 2.4, 201) * 0.52
                + pnoise(x, y, 64, 6.0, 202) * 0.33
                + hash2(x, y, 203) * 0.15
            )
            crack = abs(pnoise(x, y, 64, 3.6, 208) - 0.5)
            if crack < 0.032:
                px[x, y] = (12, 15, 22, 255)
            else:
                idx = clamp(n * len(pal_bas), 0, len(pal_bas) - 1)
                px[x, y] = pal_bas[idx]
    im.save(os.path.join(OUT_DIR, "terrain_basalt.png"))

    # Cavern Backwall: moody dark parallax stone behind carved tunnels
    im = Image.new("RGBA", (64, 64))
    px = im.load()
    pal_bw = [
        (9, 11, 16, 255),
        (13, 16, 23, 255),
        (18, 22, 31, 255),
        (23, 28, 39, 255),
    ]
    for y in range(64):
        for x in range(64):
            n = pnoise(x, y, 64, 2.5, 301) * 0.65 + hash2(x, y, 302) * 0.35
            idx = clamp(n * len(pal_bw), 0, len(pal_bw) - 1)
            px[x, y] = pal_bw[idx]
    im.save(os.path.join(OUT_DIR, "terrain_backwall.png"))

    # Magma Core: incandescent lava convection ocean
    im = Image.new("RGBA", (64, 64))
    px = im.load()
    pal_mag = [
        (140, 26, 8, 255),
        (206, 56, 12, 255),
        (245, 118, 20, 255),
        (255, 186, 42, 255),
        (255, 238, 128, 255),
        (255, 252, 210, 255),
    ]
    for y in range(64):
        for x in range(64):
            n = (
                pnoise(x, y, 64, 2.0, 401) * 0.55
                + pnoise(x, y, 64, 4.8, 402) * 0.35
                + hash2(x, y, 403) * 0.10
            )
            idx = clamp(n * len(pal_mag), 0, len(pal_mag) - 1)
            px[x, y] = pal_mag[idx]
    im.save(os.path.join(OUT_DIR, "terrain_magma.png"))


# ------------------------------------------------------------------------------
# 2. GLOWING ORE & CRYSTAL CLUSTERS (32x32)
# ------------------------------------------------------------------------------
def make_ore_clusters():
    specs = {
        "ore_fe": (
            (110, 22, 26, 255),
            (188, 38, 42, 255),
            (242, 82, 74, 255),
            (255, 186, 174, 255),
            "shards",
        ),
        "ore_cu": (
            (126, 64, 18, 255),
            (208, 118, 32, 255),
            (248, 176, 62, 255),
            (255, 232, 162, 255),
            "nodules",
        ),
        "ore_si": (
            (18, 96, 138, 255),
            (46, 178, 228, 255),
            (118, 232, 255, 255),
            (225, 252, 255, 255),
            "spires",
        ),
        "ore_ti": (
            (72, 34, 128, 255),
            (132, 68, 214, 255),
            (194, 126, 255, 255),
            (242, 218, 255, 255),
            "spires",
        ),
    }
    for name, (c_lo, c_mid, c_hi, c_spec, shape) in specs.items():
        im = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        # Base rock bed
        d.polygon([(5, 27), (9, 21), (16, 19), (24, 21), (28, 27)], fill=(38, 44, 56, 255))
        if shape == "spires":
            crystals = [
                [(10, 24), (7, 13), (11, 8), (14, 14), (14, 24)],
                [(15, 25), (14, 7), (17, 3), (21, 9), (19, 25)],
                [(19, 25), (22, 12), (26, 10), (26, 18), (23, 25)],
                [(6, 25), (4, 18), (7, 16), (10, 23)],
            ]
            for poly in crystals:
                d.polygon(poly, fill=c_mid)
                # Left lit facet
                d.polygon([poly[0], poly[1], poly[2], ((poly[0][0] + poly[2][0]) // 2 + 1, poly[0][1])], fill=c_hi)
                # Specular ridge
                d.line([poly[1], poly[2]], fill=c_spec)
        elif shape == "shards":
            shards = [
                [(7, 25), (5, 16), (10, 11), (14, 18), (12, 25)],
                [(13, 26), (12, 10), (18, 6), (22, 14), (19, 26)],
                [(19, 25), (21, 14), (27, 13), (27, 22), (22, 25)],
            ]
            for poly in shards:
                d.polygon(poly, fill=c_lo)
                d.polygon([poly[0], poly[1], poly[2], poly[3]], fill=c_mid)
                d.line([poly[1], poly[2]], fill=c_hi)
                d.point(poly[2], fill=c_spec)
        else:
            # Copper metallic nodules
            for cx, cy, rx, ry in [(11, 20, 5, 4), (18, 15, 6, 5), (23, 21, 5, 4), (15, 22, 5, 4)]:
                d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=c_lo)
                d.ellipse([cx - rx + 1, cy - ry + 1, cx + rx - 1, cy + ry - 1], fill=c_mid)
                d.ellipse([cx - rx + 2, cy - ry + 1, cx + 1, cy], fill=c_hi)
                d.point((cx - 1, cy - ry + 2), fill=c_spec)
        im = add_outline(im, (10, 13, 20, 255))
        im.save(os.path.join(OUT_DIR, f"{name}.png"))


# ------------------------------------------------------------------------------
# 3. INDUSTRIAL PIXEL-ART BUILDINGS (Matching target_gameplay_concept.jpeg!)
# ------------------------------------------------------------------------------
def make_buildings():
    STEEL_DK = (40, 48, 62, 255)
    STEEL_MD = (68, 80, 98, 255)
    STEEL_LT = (108, 124, 146, 255)
    STEEL_HI = (156, 174, 196, 255)
    DARK = (14, 18, 28, 255)
    CYAN_DK = (22, 118, 162, 255)
    CYAN = (64, 214, 255, 255)
    CYAN_HI = (196, 248, 255, 255)
    AMBER = (242, 154, 42, 255)
    FIRE = (255, 214, 86, 255)

    # 1) Solar Array (64x48)
    im = Image.new("RGBA", (64, 48), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    panel_box(d, 20, 38, 44, 46, STEEL_MD, STEEL_LT, STEEL_DK)
    d.rectangle([29, 22, 35, 39], fill=STEEL_MD, outline=DARK)
    d.line([31, 23, 31, 38], fill=STEEL_LT)
    # Angled photovoltaic wing
    wing = [(4, 22), (56, 8), (60, 18), (8, 32)]
    d.polygon(wing, fill=(18, 48, 96, 255), outline=DARK)
    d.line([5, 22, 56, 9], fill=STEEL_HI)
    d.line([8, 31, 59, 18], fill=STEEL_DK)
    # Grid cells on solar panel
    for i in range(1, 8):
        t = i / 8.0
        x0 = int(4 + (56 - 4) * t)
        y0 = int(22 + (8 - 22) * t)
        x1 = int(8 + (60 - 8) * t)
        y1 = int(32 + (18 - 32) * t)
        d.line([x0, y0, x1, y1], fill=(56, 148, 224, 255))
    d.line([6, 27, 58, 13], fill=(56, 148, 224, 255))
    # Specular sheen
    d.line([14, 20, 26, 17], fill=(154, 226, 255, 255))
    d.line([34, 15, 44, 12], fill=(154, 226, 255, 255))
    im = add_outline(im)
    im.save(os.path.join(OUT_DIR, "bld_solar.png"))

    # 2) Tesla Coil Tower (48x64)
    im = Image.new("RGBA", (48, 64), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    panel_box(d, 8, 52, 40, 62, STEEL_MD, STEEL_LT, STEEL_DK)
    draw_hazard_stripe(d, 10, 58, 38, 60)
    # Tapered tower body with copper windings
    d.polygon([(14, 52), (18, 24), (30, 24), (34, 52)], fill=STEEL_DK, outline=DARK)
    for y in range(28, 50, 4):
        d.rectangle([16, y, 32, y + 2], fill=(196, 112, 44, 255), outline=DARK)
        d.line([18, y, 26, y], fill=(246, 176, 86, 255))
    # Brass insulator rings
    d.rectangle([13, 21, 35, 25], fill=STEEL_LT, outline=DARK)
    d.rectangle([16, 17, 32, 20], fill=STEEL_HI, outline=DARK)
    # Glowing plasma orb
    d.ellipse([15, 3, 33, 19], fill=CYAN_DK, outline=DARK)
    d.ellipse([17, 5, 31, 17], fill=CYAN)
    d.ellipse([20, 6, 27, 12], fill=CYAN_HI)
    im = add_outline(im)
    im.save(os.path.join(OUT_DIR, "bld_tesla.png"))

    # 3) Power Bank Battery (48x48)
    im = Image.new("RGBA", (48, 48), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    panel_box(d, 4, 10, 44, 45, STEEL_MD, STEEL_LT, STEEL_DK)
    panel_box(d, 8, 6, 18, 11, STEEL_LT, STEEL_HI, STEEL_DK, rivets=False)
    panel_box(d, 30, 6, 40, 11, STEEL_LT, STEEL_HI, STEEL_DK, rivets=False)
    # Dual glowing capacitor tubes
    for bx in (10, 26):
        d.rectangle([bx, 15, bx + 12, 38], fill=(16, 26, 36, 255), outline=DARK)
        for by in range(18, 36, 4):
            d.rectangle([bx + 2, by, bx + 10, by + 2], fill=(48, 232, 168, 255))
            d.line([bx + 2, by, bx + 6, by], fill=(176, 255, 224, 255))
    draw_hazard_stripe(d, 8, 41, 40, 43)
    im = add_outline(im)
    im.save(os.path.join(OUT_DIR, "bld_battery.png"))

    # 4) Geothermal Plant (64x64)
    im = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    panel_box(d, 6, 28, 58, 58, STEEL_MD, STEEL_LT, STEEL_DK)
    # Bore pipes & cooling stacks
    panel_box(d, 10, 8, 22, 30, STEEL_DK, STEEL_MD, DARK, rivets=False)
    panel_box(d, 42, 12, 54, 30, STEEL_DK, STEEL_MD, DARK, rivets=False)
    # Glowing magma heat exchanger core
    d.rectangle([22, 24, 42, 50], fill=(96, 24, 12, 255), outline=DARK)
    d.rectangle([25, 27, 39, 47], fill=(236, 94, 22, 255))
    d.rectangle([28, 31, 36, 43], fill=FIRE)
    # Horizontal cooling ribs
    for ry in (30, 36, 42):
        d.line([23, ry, 41, ry], fill=STEEL_DK)
    # Deep bore drill shaft at bottom
    d.rectangle([26, 56, 38, 63], fill=STEEL_LT, outline=DARK)
    im = add_outline(im)
    im.save(os.path.join(OUT_DIR, "bld_geothermal.png"))

    # 5) Mining Drill (48x64)
    im = Image.new("RGBA", (48, 64), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    # Heavy gantry legs
    panel_box(d, 6, 18, 14, 52, STEEL_MD, STEEL_LT, STEEL_DK, rivets=False)
    panel_box(d, 34, 18, 42, 52, STEEL_MD, STEEL_LT, STEEL_DK, rivets=False)
    # Motor head housing
    panel_box(d, 4, 8, 44, 26, (76, 86, 104, 255), STEEL_HI, STEEL_DK)
    draw_hazard_stripe(d, 8, 21, 40, 24)
    # Glowing amber status core
    d.rectangle([19, 12, 29, 18], fill=AMBER, outline=DARK)
    d.rectangle([21, 13, 27, 16], fill=FIRE)
    # Steel auger cone
    d.polygon([(16, 27), (32, 27), (28, 52), (24, 61), (20, 52)], fill=STEEL_LT, outline=DARK)
    for ay in range(31, 55, 5):
        d.line([18, ay, 30, ay + 2], fill=STEEL_DK)
        d.line([19, ay - 1, 29, ay + 1], fill=STEEL_HI)
    im = add_outline(im)
    im.save(os.path.join(OUT_DIR, "bld_drill.png"))

    # 6) Conveyor Belt (4 frames horizontal 32x16 -> 128x16 strip)
    im = Image.new("RGBA", (128, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    for f in range(4):
        ox = f * 32
        d.rectangle([ox, 4, ox + 31, 14], fill=STEEL_DK, outline=DARK)
        d.line([ox + 1, 5, ox + 30, 5], fill=STEEL_LT)
        d.rectangle([ox + 1, 6, ox + 30, 11], fill=(28, 34, 44, 255))
        # Animated chevrons/rollers
        for k in range(-1, 5):
            cx = ox + ((k * 8 + f * 2) % 32)
            if ox + 2 <= cx <= ox + 28:
                d.line([cx, 7, cx + 2, 9], fill=CYAN)
                d.line([cx + 2, 9, cx, 11], fill=CYAN)
        # Support feet
        d.rectangle([ox + 3, 12, ox + 7, 15], fill=STEEL_MD, outline=DARK)
        d.rectangle([ox + 24, 12, ox + 28, 15], fill=STEEL_MD, outline=DARK)
    im.save(os.path.join(OUT_DIR, "bld_belt.png"))

    # 7) Vertical Lift Shaft (4 frames 24x32 -> 96x32 strip)
    im = Image.new("RGBA", (96, 32), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    for f in range(4):
        ox = f * 24
        d.rectangle([ox + 2, 0, ox + 21, 31], fill=(22, 28, 38, 255), outline=DARK)
        d.rectangle([ox + 2, 0, ox + 5, 31], fill=STEEL_MD, outline=DARK)
        d.rectangle([ox + 18, 0, ox + 21, 31], fill=STEEL_MD, outline=DARK)
        for k in range(4):
            ry = (k * 8 - f * 2) % 32
            d.line([ox + 6, ry, ox + 17, ry], fill=STEEL_LT)
            if k % 2 == 0:
                d.line([ox + 9, ry + 1, ox + 14, ry + 1], fill=CYAN)
    im.save(os.path.join(OUT_DIR, "bld_lift.png"))

    # 8) Cargo Depot: Stacked Corrugated Shipping Containers (64x48, straight from concept art!)
    im = Image.new("RGBA", (64, 48), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    containers = [
        (3, 25, 33, 45, (148, 46, 46, 255), (192, 74, 68, 255), (96, 26, 28, 255)),   # Crimson
        (33, 25, 61, 45, (44, 88, 138, 255), (76, 132, 188, 255), (26, 54, 92, 255)),  # Cobalt
        (10, 7, 42, 25, (62, 108, 72, 255), (98, 152, 104, 255), (36, 68, 44, 255)),   # Olive
        (42, 11, 60, 25, (172, 118, 44, 255), (218, 162, 74, 255), (112, 74, 24, 255)),# Amber
    ]
    for x0, y0, x1, y1, base, hi, lo in containers:
        panel_box(d, x0, y0, x1, y1, base, hi, lo, rivets=False)
        for cx in range(x0 + 3, x1 - 2, 3):
            d.line([cx, y0 + 2, cx, y1 - 2], fill=lo)
            d.line([cx + 1, y0 + 2, cx + 1, y1 - 2], fill=hi)
    # Platform base
    panel_box(d, 2, 43, 62, 47, STEEL_MD, STEEL_LT, STEEL_DK, rivets=False)
    im = add_outline(im)
    im.save(os.path.join(OUT_DIR, "bld_depot.png"))

    # 9) Blast Smelter (64x64, twin chimneys + molten firebox matching concept art!)
    im = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    # Twin tall smokestacks
    panel_box(d, 10, 4, 20, 32, STEEL_MD, STEEL_LT, STEEL_DK, rivets=False)
    panel_box(d, 24, 8, 34, 32, STEEL_MD, STEEL_LT, STEEL_DK, rivets=False)
    d.rectangle([9, 4, 21, 8], fill=STEEL_LT, outline=DARK)
    d.rectangle([23, 8, 35, 12], fill=STEEL_LT, outline=DARK)
    # Main furnace hall
    panel_box(d, 4, 26, 60, 61, STEEL_MD, STEEL_LT, STEEL_DK)
    # Side hopper & silo
    panel_box(d, 42, 18, 56, 44, (84, 96, 114, 255), STEEL_HI, STEEL_DK)
    # Glowing molten furnace window
    d.rectangle([10, 36, 36, 54], fill=(82, 22, 10, 255), outline=DARK)
    d.rectangle([12, 38, 34, 52], fill=(238, 92, 18, 255))
    d.rectangle([15, 41, 31, 50], fill=FIRE)
    for gx in (18, 24, 30):
        d.line([gx, 37, gx, 53], fill=STEEL_DK)
    draw_hazard_stripe(d, 6, 56, 58, 59)
    im = add_outline(im)
    im.save(os.path.join(OUT_DIR, "bld_smelter.png"))

    # 10) Auto Assembler (64x48)
    im = Image.new("RGBA", (64, 48), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    panel_box(d, 4, 14, 60, 46, STEEL_MD, STEEL_LT, STEEL_DK)
    panel_box(d, 14, 6, 50, 15, STEEL_LT, STEEL_HI, STEEL_DK, rivets=False)
    # Clean-room assembly bay window
    d.rectangle([10, 20, 44, 38], fill=(16, 26, 38, 255), outline=DARK)
    # Robotic arm inside
    d.line([16, 21, 24, 30], fill=AMBER, width=2)
    d.line([24, 30, 32, 27], fill=FIRE, width=2)
    d.rectangle([26, 33, 38, 37], fill=(48, 218, 128, 255))
    # Status console on right
    d.rectangle([48, 20, 56, 34], fill=(18, 34, 46, 255), outline=DARK)
    d.rectangle([50, 22, 54, 26], fill=CYAN)
    d.rectangle([50, 29, 54, 32], fill=(64, 242, 140, 255))
    draw_hazard_stripe(d, 6, 41, 58, 44)
    im = add_outline(im)
    im.save(os.path.join(OUT_DIR, "bld_assembler.png"))

    # 11) Macro 3D Printer Gantry (96x72, straight from concept art left-center!)
    im = Image.new("RGBA", (96, 72), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    # Heavy concrete/steel pad
    panel_box(d, 4, 58, 92, 70, STEEL_MD, STEEL_LT, STEEL_DK)
    draw_hazard_stripe(d, 8, 64, 88, 68)
    # Giant outer gantry frame columns & top bridge
    panel_box(d, 8, 8, 20, 60, STEEL_LT, STEEL_HI, STEEL_DK)
    panel_box(d, 76, 8, 88, 60, STEEL_LT, STEEL_HI, STEEL_DK)
    panel_box(d, 6, 6, 90, 18, STEEL_LT, STEEL_HI, STEEL_DK)
    # Truss cross-bracing
    for y in range(20, 54, 10):
        d.line([10, y, 18, y + 8], fill=STEEL_DK)
        d.line([78, y, 86, y + 8], fill=STEEL_DK)
    # Overhead print head carriage & holographic probe
    panel_box(d, 36, 16, 60, 26, STEEL_MD, STEEL_HI, STEEL_DK, rivets=False)
    d.polygon([(44, 26), (52, 26), (62, 56), (34, 56)], fill=(40, 198, 255, 80))
    d.line([48, 26, 48, 54], fill=CYAN_HI)
    # Mini probe silhouette being printed inside gantry
    d.polygon([(48, 34), (42, 48), (48, 45), (54, 48)], fill=CYAN, outline=CYAN_HI)
    im = add_outline(im)
    im.save(os.path.join(OUT_DIR, "bld_printer.png"))

    # 12) Orbital Mass Driver Railgun (96x80, 45-degree launch rail straight from concept art!)
    im = Image.new("RGBA", (96, 80), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    # Heavy anchored breech & recoil base
    panel_box(d, 6, 56, 66, 77, STEEL_MD, STEEL_LT, STEEL_DK)
    draw_hazard_stripe(d, 10, 71, 62, 75)
    # Angled support hydraulic struts
    d.line([42, 58, 64, 34], fill=STEEL_LT, width=4)
    d.line([54, 58, 72, 42], fill=STEEL_MD, width=3)
    # 45-deg superconducting twin launch rail
    rail_outer = [(14, 62), (76, 6), (86, 16), (24, 72)]
    d.polygon(rail_outer, fill=STEEL_MD, outline=DARK)
    d.line([15, 61, 76, 7], fill=STEEL_HI, width=2)
    d.line([24, 71, 85, 16], fill=STEEL_DK, width=2)
    # Inner glowing cyan rail channel & induction rings
    d.line([20, 65, 80, 12], fill=CYAN, width=2)
    for t in (0.18, 0.34, 0.50, 0.66, 0.82):
        rx = int(19 + (80 - 19) * t)
        ry = int(66 + (11 - 66) * t)
        d.line([rx - 5, ry - 5, rx + 5, ry + 5], fill=STEEL_HI, width=2)
        d.point((rx, ry), fill=CYAN_HI)
    # Capacitor pod on left
    panel_box(d, 10, 44, 24, 58, STEEL_DK, STEEL_LT, DARK, rivets=False)
    d.rectangle([13, 47, 21, 53], fill=AMBER)
    im = add_outline(im)
    im.save(os.path.join(OUT_DIR, "bld_mass_driver.png"))

    # 13) Defense Turret (48x48)
    im = Image.new("RGBA", (48, 48), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    panel_box(d, 6, 33, 42, 46, STEEL_MD, STEEL_LT, STEEL_DK)
    draw_hazard_stripe(d, 9, 41, 39, 44)
    panel_box(d, 13, 27, 35, 34, STEEL_DK, STEEL_MD, DARK, rivets=False)
    d.pieslice([11, 13, 37, 39], 180, 360, fill=STEEL_LT, outline=DARK)
    d.arc([13, 15, 35, 37], 200, 320, fill=STEEL_HI)
    # Twin barrels aimed up-right
    d.line([26, 20, 43, 5], fill=STEEL_HI, width=3)
    d.line([29, 24, 45, 10], fill=STEEL_MD, width=3)
    d.ellipse([18, 19, 27, 28], fill=(242, 54, 68, 255), outline=DARK)
    d.point((21, 22), fill=(255, 212, 212, 255))
    im = add_outline(im)
    im.save(os.path.join(OUT_DIR, "bld_turret.png"))


# ------------------------------------------------------------------------------
# 4. CELESTIAL BODIES & ENEMY ORBITAL FORTRESS
# ------------------------------------------------------------------------------
def make_sphere_planet(filename, size, base_col, hi_col, dark_col, crater_col, seed):
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    px = im.load()
    r = size * 0.46
    cx = cy = size * 0.5
    rng = random.Random(seed)
    craters = [(rng.uniform(-0.6, 0.6), rng.uniform(-0.6, 0.6), rng.uniform(0.08, 0.22)) for _ in range(9)]
    for y in range(size):
        for x in range(size):
            dx = (x - cx) / r
            dy = (y - cy) / r
            d2 = dx * dx + dy * dy
            if d2 > 1.0:
                continue
            dz = math.sqrt(max(0.0, 1.0 - d2))
            # Directional sun lighting from upper-right
            lit = dx * 0.55 - dy * 0.62 + dz * 0.56
            n = vnoise(x, y, size * 0.14, seed) * 0.6 + vnoise(x, y, size * 0.05, seed + 5) * 0.4
            col = lerp_col(base_col, hi_col, n)
            for crx, cry, crr in craters:
                cd = math.hypot(dx - crx, dy - cry)
                if cd < crr:
                    col = lerp_col(col, crater_col, 0.55)
                elif cd < crr * 1.18:
                    col = lerp_col(col, hi_col, 0.25)
            shade = max(0.10, min(1.15, lit * 0.95 + 0.18))
            col = lerp_col(dark_col, col, shade)
            # Subtle atmospheric rim highlight on lit edge
            if d2 > 0.84 and lit > 0.1:
                col = lerp_col(col, hi_col, 0.45)
            px[x, y] = (col[0], col[1], col[2], 255)
    im.save(os.path.join(OUT_DIR, "celestials", filename))


def make_celestials():
    make_sphere_planet("luna.png", 96, (108, 122, 148, 255), (186, 204, 232, 255), (14, 18, 30, 255), (62, 72, 92, 255), 701)
    make_sphere_planet("ignis.png", 96, (158, 62, 34, 255), (255, 162, 64, 255), (28, 12, 12, 255), (255, 212, 82, 255), 702)
    make_sphere_planet("cryo.png", 96, (72, 148, 186, 255), (192, 242, 255, 255), (14, 28, 48, 255), (42, 92, 134, 255), 703)

    # 4 Asteroid ore variants (36x36)
    ast_specs = [
        ("ast_fe.png", (76, 72, 78, 255), (234, 72, 68, 255), 801),
        ("ast_cu.png", (78, 72, 66, 255), (246, 168, 52, 255), 802),
        ("ast_si.png", (62, 74, 88, 255), (72, 224, 255, 255), 803),
        ("ast_ti.png", (68, 64, 86, 255), (188, 112, 255, 255), 804),
    ]
    for fname, rock, ore, seed in ast_specs:
        im = Image.new("RGBA", (36, 36), (0, 0, 0, 0))
        px = im.load()
        rng = random.Random(seed)
        lumps = [(rng.uniform(0, math.tau), rng.uniform(0.10, 0.24)) for _ in range(4)]
        for y in range(36):
            for x in range(36):
                dx, dy = (x - 18) / 14.0, (y - 18) / 14.0
                ang = math.atan2(dy, dx)
                rad = 0.88 + sum(amp * math.cos(ang * (i + 2) + ph) for i, (ph, amp) in enumerate(lumps)) * 0.45
                d = math.hypot(dx, dy)
                if d > rad:
                    continue
                lit = max(0.22, min(1.2, 0.72 + dx * 0.4 - dy * 0.5))
                n = vnoise(x, y, 4.5, seed)
                col = lerp_col((26, 28, 36, 255), rock, lit * (0.7 + n * 0.5))
                if n > 0.74 and d < rad * 0.82:
                    col = lerp_col(col, ore, 0.88)
                px[x, y] = (col[0], col[1], col[2], 255)
        im = add_outline(im)
        im.save(os.path.join(OUT_DIR, "celestials", fname))

    # Corrupted Enemy Orbital Fortress (128x96, inspired by top-right station in concept art!)
    im = Image.new("RGBA", (128, 96), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    # Giant angled twin solar/radiator wings
    d.polygon([(8, 12), (48, 38), (38, 52), (4, 24)], fill=(38, 48, 72, 255), outline=(12, 16, 24, 255))
    d.polygon([(80, 44), (120, 70), (112, 84), (72, 58)], fill=(38, 48, 72, 255), outline=(12, 16, 24, 255))
    d.polygon([(78, 12), (118, 36), (110, 48), (70, 24)], fill=(48, 58, 86, 255), outline=(12, 16, 24, 255))
    d.polygon([(14, 58), (52, 76), (46, 88), (8, 68)], fill=(48, 58, 86, 255), outline=(12, 16, 24, 255))
    # Wing struts on all 4 solar/radiator panels + metallic truss connectors
    d.line([34, 36, 48, 42], fill=(128, 140, 164, 255), width=3)
    d.line([80, 42, 94, 36], fill=(128, 140, 164, 255), width=3)
    d.line([34, 62, 48, 56], fill=(128, 140, 164, 255), width=3)
    d.line([80, 56, 94, 62], fill=(128, 140, 164, 255), width=3)
    for i in range(4):
        t = (i + 1) / 5.0
        d.line([int(8 + 40 * t), int(12 + 26 * t), int(4 + 34 * t), int(24 + 28 * t)], fill=(92, 118, 164, 255))
        d.line([int(80 + 40 * t), int(44 + 26 * t), int(72 + 40 * t), int(58 + 26 * t)], fill=(92, 118, 164, 255))
        d.line([int(78 + 40 * t), int(12 + 24 * t), int(70 + 40 * t), int(24 + 24 * t)], fill=(92, 118, 164, 255))
        d.line([int(14 + 38 * t), int(58 + 18 * t), int(8 + 38 * t), int(68 + 20 * t)], fill=(92, 118, 164, 255))
    # Armored central citadel hull
    d.polygon([(48, 22), (80, 22), (90, 48), (80, 74), (48, 74), (38, 48)], fill=(64, 70, 88, 255), outline=(14, 16, 24, 255))
    d.polygon([(52, 28), (76, 28), (84, 48), (76, 68), (52, 68), (44, 48)], fill=(44, 48, 62, 255))
    # Glowing crimson corrupted reactor core
    d.ellipse([52, 36, 76, 60], fill=(142, 18, 32, 255), outline=(24, 10, 16, 255))
    d.ellipse([56, 40, 72, 56], fill=(255, 56, 68, 255))
    d.ellipse([60, 44, 68, 52], fill=(255, 212, 186, 255))
    # Defense gun sponsons
    for gx, gy in [(42, 36), (82, 36), (42, 58), (82, 58)]:
        d.rectangle([gx, gy, gx + 6, gy + 6], fill=(118, 128, 148, 255), outline=(14, 16, 24, 255))
        d.point((gx + 3, gy + 3), fill=(255, 86, 86, 255))
    im = add_outline(im)
    im.save(os.path.join(OUT_DIR, "celestials", "enemy_fortress.png"))


# ------------------------------------------------------------------------------
# 5. CRISP 16x16 RESOURCE & ITEM ICON STRIP (12 icons -> 192x16)
# ------------------------------------------------------------------------------
def make_item_icons():
    # Order: 0:fe, 1:cu, 2:si, 3:ti, 4:plate_fe, 5:wire_cu, 6:wafer_si, 7:circuit, 8:alloy, 9:sci_pack, 10:probe, 11:ice
    im = Image.new("RGBA", (192, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)

    def ox(i): return i * 16

    # 0: Fe ore (crimson hematite chunk)
    x = ox(0)
    d.polygon([(x + 3, 12), (x + 2, 7), (x + 7, 3), (x + 13, 5), (x + 13, 11), (x + 8, 13)], fill=(196, 46, 48, 255), outline=(22, 14, 18, 255))
    d.polygon([(x + 4, 7), (x + 7, 4), (x + 10, 6), (x + 7, 9)], fill=(255, 118, 104, 255))
    # 1: Cu ore (amber nugget)
    x = ox(1)
    d.ellipse([x + 2, 4, x + 13, 13], fill=(214, 124, 34, 255), outline=(24, 16, 10, 255))
    d.ellipse([x + 4, 5, x + 9, 9], fill=(255, 206, 98, 255))
    # 2: Si ore (cyan quartz crystal)
    x = ox(2)
    d.polygon([(x + 5, 13), (x + 4, 6), (x + 8, 2), (x + 12, 6), (x + 11, 13)], fill=(48, 198, 242, 255), outline=(12, 24, 38, 255))
    d.line([x + 7, 4, x + 6, 11], fill=(214, 252, 255, 255))
    # 3: Ti ore (violet crystal)
    x = ox(3)
    d.polygon([(x + 4, 13), (x + 3, 7), (x + 8, 2), (x + 13, 7), (x + 12, 13)], fill=(154, 82, 232, 255), outline=(20, 12, 34, 255))
    d.line([x + 7, 4, x + 6, 10], fill=(238, 206, 255, 255))
    # 4: Iron Plate
    x = ox(4)
    d.rectangle([x + 2, 3, x + 13, 12], fill=(138, 158, 182, 255), outline=(18, 24, 36, 255))
    d.line([x + 3, 4, x + 12, 4], fill=(214, 230, 248, 255))
    d.point((x + 4, 5), fill=(58, 70, 88, 255))
    d.point((x + 11, 10), fill=(58, 70, 88, 255))
    # 5: Copper Wire coil
    x = ox(5)
    d.ellipse([x + 2, 2, x + 13, 13], fill=(224, 126, 42, 255), outline=(28, 16, 10, 255))
    d.ellipse([x + 5, 5, x + 10, 10], fill=(24, 28, 38, 255))
    d.arc([x + 3, 3, x + 12, 12], 200, 340, fill=(255, 208, 112, 255))
    # 6: Silicon Wafer
    x = ox(6)
    d.ellipse([x + 2, 2, x + 13, 13], fill=(42, 146, 208, 255), outline=(14, 24, 38, 255))
    d.line([x + 4, 6, x + 11, 6], fill=(154, 236, 255, 255))
    d.line([x + 4, 9, x + 11, 9], fill=(154, 236, 255, 255))
    d.line([x + 8, 4, x + 8, 11], fill=(154, 236, 255, 255))
    # 7: Circuit Chip
    x = ox(7)
    d.rectangle([x + 3, 3, x + 12, 12], fill=(28, 136, 76, 255), outline=(12, 28, 18, 255))
    d.rectangle([x + 5, 5, x + 10, 10], fill=(26, 32, 42, 255))
    for p in (4, 7, 10):
        d.point((x + p, 2), fill=(248, 204, 76, 255))
        d.point((x + p, 13), fill=(248, 204, 76, 255))
    # 8: Titanium Alloy
    x = ox(8)
    d.polygon([(x + 3, 12), (x + 6, 3), (x + 13, 3), (x + 10, 12)], fill=(184, 152, 236, 255), outline=(24, 16, 40, 255))
    d.line([x + 6, 4, x + 12, 4], fill=(246, 234, 255, 255))
    # 9: Science Pack
    x = ox(9)
    d.polygon([(x + 6, 3), (x + 9, 3), (x + 13, 13), (x + 2, 13)], fill=(66, 236, 178, 255), outline=(14, 30, 26, 255))
    d.line([x + 7, 4, x + 5, 11], fill=(214, 255, 240, 255))
    # 10: Replica Probe
    x = ox(10)
    d.polygon([(x + 8, 2), (x + 3, 13), (x + 8, 10), (x + 13, 13)], fill=(255, 206, 76, 255), outline=(28, 20, 12, 255))
    d.point((x + 8, 6), fill=(116, 242, 255, 255))
    # 11: Ice
    x = ox(11)
    d.polygon([(x + 3, 9), (x + 8, 2), (x + 13, 9), (x + 8, 14)], fill=(144, 224, 255, 255), outline=(18, 42, 64, 255))
    d.point((x + 7, 6), fill=(244, 254, 255, 255))

    im.save(os.path.join(OUT_DIR, "icon_items.png"))


# ------------------------------------------------------------------------------
# 6. SOFT RADIAL GLOW FOR HD-2D ADDITIVE LIGHTING (128x128)
# ------------------------------------------------------------------------------
def make_glow():
    im = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    px = im.load()
    for y in range(128):
        for x in range(128):
            d = math.hypot(x - 63.5, y - 63.5) / 63.5
            if d < 1.0:
                a = ((1.0 - d) ** 2.4) * 255.0
                px[x, y] = (255, 255, 255, clamp(a))
    im.save(os.path.join(OUT_DIR, "glow_soft.png"))


def make_contact_sheet():
    # Generate a quick visual review sheet in scratch/ so we can inspect all sprites immediately!
    sheet = Image.new("RGBA", (540, 260), (12, 16, 26, 255))
    names = [
        "terrain_regolith.png", "terrain_basalt.png", "terrain_backwall.png", "terrain_magma.png",
        "ore_fe.png", "ore_cu.png", "ore_si.png", "ore_ti.png",
        "bld_solar.png", "bld_tesla.png", "bld_battery.png", "bld_geothermal.png",
        "bld_drill.png", "bld_depot.png", "bld_smelter.png", "bld_assembler.png",
        "bld_printer.png", "bld_mass_driver.png", "bld_turret.png",
    ]
    x, y, row_h = 8, 8, 0
    for n in names:
        im = Image.open(os.path.join(OUT_DIR, n))
        if x + im.width + 8 > sheet.width:
            x = 8
            y += row_h + 10
            row_h = 0
        sheet.alpha_composite(im, (x, y))
        x += im.width + 8
        row_h = max(row_h, im.height)
    fort = Image.open(os.path.join(OUT_DIR, "celestials", "enemy_fortress.png"))
    sheet.alpha_composite(fort, (sheet.width - fort.width - 8, sheet.height - fort.height - 8))
    sheet.save(os.path.join(OUT_DIR, "_atlas_preview.png"))


if __name__ == "__main__":
    make_terrain_tiles()
    make_ore_clusters()
    make_buildings()
    make_celestials()
    make_item_icons()
    make_glow()
    print("Generated all HD-2D pixel-art assets in:", OUT_DIR)
