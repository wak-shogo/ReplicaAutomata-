"""
STAR REPLICA: AUTOMA - True Concept-Art HD-2D Pixel Art Asset Generator
Generates rich, multi-layered 16-bit/HD-2D pixel art sprites directly faithful
to docs/art/target_gameplay_concept.jpeg and docs/DESIGN_SPECIFICATION.md.
"""
import math
import os
import random
from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "sprites")
os.makedirs(OUT, exist_ok=True)


def clamp(v, lo=0, hi=255):
    return max(lo, min(hi, int(v)))


def lerp_c(a, b, t):
    t = max(0.0, min(1.0, t))
    return tuple(clamp(a[i] + (b[i] - a[i]) * t) for i in range(4))


def hash2(x, y, seed=1337):
    n = (x * 374761393 + y * 668265263 + seed * 1442695041) & 0xFFFFFFFF
    n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((n ^ (n >> 16)) & 0xFFFFFF) / float(0xFFFFFF)


def vnoise(x, y, scale=8.0, seed=1337):
    fx, fy = x / scale, y / scale
    ix, iy = int(math.floor(fx)), int(math.floor(fy))
    tx, ty = fx - ix, fy - iy
    tx = tx * tx * (3.0 - 2.0 * tx)
    ty = ty * ty * (3.0 - 2.0 * ty)
    a = hash2(ix, iy, seed)
    b = hash2(ix + 1, iy, seed)
    c = hash2(ix, iy + 1, seed)
    d = hash2(ix + 1, iy + 1, seed)
    return (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty


def outline(img, col=(9, 12, 18, 255)):
    w, h = img.size
    src = img.load()
    res = img.copy()
    dst = res.load()
    for y in range(h):
        for x in range(w):
            if src[x, y][3] > 24:
                continue
            for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and src[nx, ny][3] > 180:
                    dst[x, y] = col
                    break
    return res


def box(d, x0, y0, x1, y1, base, hi, lo, edge=(12, 15, 22, 255), rivets=True):
    d.rectangle([x0, y0, x1, y1], fill=base, outline=edge)
    if x1 - x0 >= 4 and y1 - y0 >= 4:
        d.line([x0 + 1, y0 + 1, x1 - 1, y0 + 1], fill=hi)
        d.line([x0 + 1, y0 + 1, x0 + 1, y1 - 1], fill=hi)
        d.line([x0 + 1, y1 - 1, x1 - 1, y1 - 1], fill=lo)
        d.line([x1 - 1, y0 + 1, x1 - 1, y1 - 1], fill=lo)
    if rivets and (x1 - x0) >= 10 and (y1 - y0) >= 10:
        for rx in (x0 + 2, x1 - 2):
            for ry in (y0 + 2, y1 - 2):
                d.point((rx, ry), fill=lo)


def hazard(d, x0, y0, x1, y1):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            on = ((x + y) // 2) % 2 == 0
            d.point((x, y), fill=(232, 174, 42, 255) if on else (26, 28, 34, 255))


# Palette
DK = (12, 15, 22, 255)
S1 = (38, 46, 60, 255)
S2 = (66, 78, 96, 255)
S3 = (108, 124, 146, 255)
S4 = (158, 176, 198, 255)
CY1 = (20, 118, 168, 255)
CY2 = (62, 214, 255, 255)
CY3 = (206, 250, 255, 255)
AM1 = (176, 94, 26, 255)
AM2 = (242, 154, 44, 255)
AM3 = (255, 224, 108, 255)


def make_hero_sprites():
    # 1) Seed Unit Core (40x40) - Armored industrial autonomous replicator core
    im = Image.new("RGBA", (40, 40), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    # 4 corner drone docking sockets
    for sx, sy in [(6, 6), (30, 6), (6, 30), (30, 30)]:
        d.rectangle([sx, sy, sx + 4, sy + 4], fill=AM2, outline=DK)
    # Main octagonal chassis
    hull = [(12, 5), (28, 5), (35, 12), (35, 28), (28, 35), (12, 35), (5, 28), (5, 12)]
    d.polygon(hull, fill=S2, outline=DK)
    d.polygon([(14, 7), (26, 7), (32, 13), (32, 26), (26, 32), (14, 32), (8, 26), (8, 13)], fill=S3)
    d.polygon([(15, 9), (25, 9), (30, 14), (30, 25), (25, 30), (15, 30), (10, 25), (10, 14)], fill=S1)
    # Specular bevel top-left
    d.line([13, 6, 27, 6], fill=S4)
    d.line([6, 13, 12, 7], fill=S4)
    # Central glowing cyan AI optic core
    d.ellipse([13, 13, 27, 27], fill=CY1, outline=DK)
    d.ellipse([15, 15, 25, 25], fill=CY2)
    d.ellipse([17, 16, 22, 21], fill=CY3)
    # Golden armor accents on sides
    d.rectangle([7, 17, 11, 23], fill=AM2, outline=DK)
    d.rectangle([29, 17, 33, 23], fill=AM2, outline=DK)
    # Bottom micro-ion thruster vents
    d.rectangle([14, 34, 18, 38], fill=S2, outline=DK)
    d.rectangle([22, 34, 26, 38], fill=S2, outline=DK)
    outline(im).save(os.path.join(OUT, "seed_core.png"))

    # 2) Fabricator Drone (24x24) - Physically docks onto Seed Unit!
    im = Image.new("RGBA", (24, 24), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.polygon([(7, 4), (17, 4), (20, 9), (20, 15), (17, 19), (7, 19), (4, 15), (4, 9)], fill=AM2, outline=DK)
    d.rectangle([7, 6, 17, 16], fill=S2, outline=DK)
    d.line([8, 7, 16, 7], fill=S4)
    d.ellipse([9, 8, 15, 14], fill=CY2, outline=DK)
    d.point((11, 10), fill=CY3)
    # Articulated welding pinchers
    d.line([6, 17, 4, 22], fill=S4, width=2)
    d.line([18, 17, 20, 22], fill=S4, width=2)
    outline(im).save(os.path.join(OUT, "fab_drone.png"))

    # 3) Orbital Booster Skirt (52x56) - Bolts onto Seed Unit for space flight!
    im = Image.new("RGBA", (52, 56), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    # Side cryo propellant tanks
    box(d, 3, 18, 13, 42, (214, 220, 230, 255), (248, 250, 255, 255), S3, rivets=False)
    box(d, 39, 18, 49, 42, (214, 220, 230, 255), (248, 250, 255, 255), S3, rivets=False)
    d.rectangle([4, 26, 12, 30], fill=AM2)
    d.rectangle([40, 26, 48, 30], fill=AM2)
    # Gold-foil thruster truss ring
    d.polygon([(12, 34), (40, 34), (44, 44), (8, 44)], fill=AM2, outline=DK)
    d.line([13, 35, 39, 35], fill=AM3)
    # Twin flared rocket bells
    for bx in (18, 34):
        d.polygon([(bx - 5, 44), (bx + 5, 44), (bx + 8, 54), (bx - 8, 54)], fill=S1, outline=DK)
        d.line([bx - 4, 45, bx - 6, 53], fill=S3)
    outline(im).save(os.path.join(OUT, "orbital_booster.png"))


def make_buildings():
    # 1) Stacked Corrugated Shipping Container Depot (96x56, concept art left!)
    im = Image.new("RGBA", (96, 56), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    box(d, 2, 48, 94, 54, S2, S3, S1, rivets=False)
    hazard(d, 5, 50, 91, 52)
    stacks = [
        (4, 28, 46, 48, (158, 46, 46, 255), (204, 78, 70, 255), (96, 24, 26, 255)),
        (47, 28, 92, 48, (42, 86, 142, 255), (76, 134, 198, 255), (24, 52, 92, 255)),
        (12, 8, 56, 28, (58, 108, 72, 255), (94, 156, 108, 255), (34, 66, 42, 255)),
        (57, 12, 88, 28, (176, 122, 44, 255), (226, 168, 76, 255), (112, 74, 24, 255)),
    ]
    for x0, y0, x1, y1, base, hi, lo in stacks:
        box(d, x0, y0, x1, y1, base, hi, lo, rivets=False)
        for cx in range(x0 + 4, x1 - 3, 4):
            d.line([cx, y0 + 2, cx, y1 - 2], fill=lo)
            d.line([cx + 1, y0 + 2, cx + 1, y1 - 2], fill=hi)
    outline(im).save(os.path.join(OUT, "depot.png"))

    # 2) Giant Steel Gantry 3D Macro Printer (128x92, concept art left-center!)
    im = Image.new("RGBA", (128, 92), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    box(d, 4, 76, 124, 90, S2, S3, S1)
    hazard(d, 8, 83, 120, 87)
    # Massive steel truss columns & overhead bridge
    box(d, 10, 8, 26, 78, S3, S4, S1)
    box(d, 102, 8, 118, 78, S3, S4, S1)
    box(d, 6, 6, 122, 22, S3, S4, S1)
    for y in range(24, 72, 12):
        d.line([12, y, 24, y + 10], fill=S1, width=2)
        d.line([104, y, 116, y + 10], fill=S1, width=2)
    # Side operator booth
    box(d, 26, 52, 46, 76, S2, S3, S1, rivets=False)
    d.rectangle([30, 57, 42, 65], fill=CY2, outline=DK)
    # Overhead laser print carriage & glowing hologram spacecraft
    box(d, 52, 20, 84, 34, S2, S4, S1, rivets=False)
    d.polygon([(62, 34), (74, 34), (88, 74), (48, 74)], fill=(54, 208, 255, 76))
    d.line([68, 34, 68, 72], fill=CY3, width=2)
    d.polygon([(68, 44), (58, 66), (68, 60), (78, 66)], fill=AM3, outline=CY3)
    outline(im).save(os.path.join(OUT, "gantry_printer.png"))

    # 3) Blast Smelter (84x84, dual smokestacks + glowing molten hearth!)
    im = Image.new("RGBA", (84, 84), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    box(d, 12, 4, 26, 42, S2, S3, S1, rivets=False)
    box(d, 30, 10, 44, 42, S2, S3, S1, rivets=False)
    d.rectangle([10, 4, 28, 9], fill=S3, outline=DK)
    d.rectangle([28, 10, 46, 15], fill=S3, outline=DK)
    # Main industrial furnace hall + pipe silo
    box(d, 6, 34, 78, 82, S2, S3, S1)
    box(d, 56, 22, 74, 58, S3, S4, S1)
    d.line([44, 28, 56, 28], fill=S4, width=3)
    # Glowing molten furnace window with grate
    d.rectangle([14, 46, 48, 70], fill=(84, 22, 10, 255), outline=DK)
    d.rectangle([16, 48, 46, 68], fill=(242, 96, 18, 255))
    d.rectangle([20, 52, 42, 66], fill=AM3)
    for gx in range(22, 44, 6):
        d.line([gx, 47, gx, 69], fill=S1, width=2)
    hazard(d, 8, 75, 76, 79)
    outline(im).save(os.path.join(OUT, "smelter.png"))

    # 4) Auto Assembler (80x64)
    im = Image.new("RGBA", (80, 64), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    box(d, 4, 18, 76, 62, S2, S3, S1)
    box(d, 16, 8, 64, 19, S3, S4, S1, rivets=False)
    d.rectangle([12, 26, 56, 50], fill=(16, 26, 38, 255), outline=DK)
    d.line([20, 28, 32, 39], fill=AM2, width=3)
    d.line([32, 39, 44, 35], fill=AM3, width=2)
    d.rectangle([34, 42, 50, 48], fill=(46, 226, 134, 255))
    d.rectangle([60, 26, 70, 46], fill=(16, 32, 44, 255), outline=DK)
    d.rectangle([62, 29, 68, 34], fill=CY2)
    d.rectangle([62, 38, 68, 43], fill=(64, 242, 144, 255))
    hazard(d, 6, 55, 74, 59)
    outline(im).save(os.path.join(OUT, "assembler.png"))

    # 5) 45-Deg Tilted Superconducting Mass Driver Railgun (128x108, hero centerpiece!)
    im = Image.new("RGBA", (128, 108), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    # Heavy anchored concrete/steel bunker breech
    box(d, 6, 76, 84, 105, S2, S3, S1)
    hazard(d, 10, 97, 80, 102)
    # Hydraulic elevation struts
    d.line([52, 78, 86, 44], fill=S3, width=5)
    d.line([68, 78, 94, 54], fill=S2, width=4)
    # Long 45-degree twin-rail electromagnetic barrel truss
    barrel = [(16, 84), (104, 6), (118, 20), (30, 98)]
    d.polygon(barrel, fill=S2, outline=DK)
    d.line([17, 83, 104, 7], fill=S4, width=3)
    d.line([30, 97, 117, 20], fill=S1, width=3)
    # Inner glowing cyan induction channel + accelerator coil collars
    d.line([24, 89, 110, 14], fill=CY2, width=3)
    for t in (0.14, 0.28, 0.42, 0.56, 0.70, 0.84, 0.94):
        rx = int(24 + (110 - 24) * t)
        ry = int(89 + (14 - 89) * t)
        d.line([rx - 7, ry - 7, rx + 7, ry + 7], fill=S4, width=3)
        d.ellipse([rx - 2, ry - 2, rx + 2, ry + 2], fill=CY3)
    # Orange breech plasma capacitor pod
    box(d, 10, 56, 30, 78, S1, S3, DK, rivets=False)
    d.rectangle([14, 61, 26, 71], fill=AM2, outline=DK)
    d.rectangle([16, 63, 24, 69], fill=AM3)
    outline(im).save(os.path.join(OUT, "mass_driver.png"))

    # 6) Subterranean Mining Drill Rig (56x76)
    im = Image.new("RGBA", (56, 76), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    box(d, 6, 22, 16, 62, S2, S3, S1, rivets=False)
    box(d, 40, 22, 50, 62, S2, S3, S1, rivets=False)
    box(d, 4, 8, 52, 30, S3, S4, S1)
    hazard(d, 8, 24, 48, 28)
    d.rectangle([22, 12, 34, 20], fill=AM2, outline=DK)
    d.rectangle([24, 14, 32, 18], fill=AM3)
    # Spiral steel drill auger
    d.polygon([(18, 31), (38, 31), (33, 62), (28, 73), (23, 62)], fill=S3, outline=DK)
    for ay in range(36, 66, 6):
        d.line([20, ay, 36, ay + 3], fill=S1, width=2)
        d.line([21, ay - 1, 35, ay + 2], fill=S4)
    outline(im).save(os.path.join(OUT, "drill.png"))

    # 7) Conveyor Belt (4 frames 32x14 -> 128x14) & Vertical Lift (4 frames 18x32 -> 72x32)
    im = Image.new("RGBA", (128, 14), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    for f in range(4):
        ox = f * 32
        d.rectangle([ox, 2, ox + 31, 12], fill=S1, outline=DK)
        d.line([ox + 1, 3, ox + 30, 3], fill=S3)
        d.rectangle([ox + 1, 4, ox + 30, 9], fill=(24, 30, 40, 255))
        for k in range(-1, 5):
            cx = ox + ((k * 8 + f * 2) % 32)
            if ox + 2 <= cx <= ox + 28:
                d.line([cx, 5, cx + 2, 7], fill=CY2)
                d.line([cx + 2, 7, cx, 9], fill=CY2)
    im.save(os.path.join(OUT, "belt.png"))

    im = Image.new("RGBA", (72, 32), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    for f in range(4):
        ox = f * 18
        d.rectangle([ox + 1, 0, ox + 16, 31], fill=(20, 26, 36, 255), outline=DK)
        d.rectangle([ox + 1, 0, ox + 4, 31], fill=S2, outline=DK)
        d.rectangle([ox + 13, 0, ox + 16, 31], fill=S2, outline=DK)
        for k in range(4):
            ry = (k * 8 - f * 2) % 32
            d.line([ox + 5, ry, ox + 12, ry], fill=S3)
            if k % 2 == 0:
                d.line([ox + 7, ry + 1, ox + 10, ry + 1], fill=CY2)
    im.save(os.path.join(OUT, "lift.png"))

    # 8) Solar Array (72x52)
    im = Image.new("RGBA", (72, 52), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    box(d, 22, 41, 50, 50, S2, S3, S1)
    d.rectangle([33, 24, 39, 42], fill=S2, outline=DK)
    d.polygon([(4, 24), (64, 8), (68, 20), (8, 36)], fill=(18, 50, 102, 255), outline=DK)
    d.line([5, 24, 64, 9], fill=S4, width=2)
    for i in range(1, 8):
        t = i / 8.0
        d.line([int(4 + 60 * t), int(24 - 16 * t), int(8 + 60 * t), int(36 - 16 * t)], fill=(58, 152, 228, 255))
    d.line([6, 30, 66, 14], fill=(58, 152, 228, 255))
    outline(im).save(os.path.join(OUT, "solar.png"))

    # 9) Tesla Power Relay (52x76)
    im = Image.new("RGBA", (52, 76), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    box(d, 8, 62, 44, 74, S2, S3, S1)
    hazard(d, 10, 68, 42, 72)
    d.polygon([(15, 62), (20, 26), (32, 26), (37, 62)], fill=S1, outline=DK)
    for y in range(30, 59, 5):
        d.rectangle([17, y, 35, y + 3], fill=AM1, outline=DK)
        d.line([19, y, 29, y], fill=AM3)
    d.rectangle([13, 22, 39, 27], fill=S3, outline=DK)
    d.ellipse([16, 4, 36, 22], fill=CY1, outline=DK)
    d.ellipse([18, 6, 34, 20], fill=CY2)
    d.ellipse([21, 8, 29, 14], fill=CY3)
    outline(im).save(os.path.join(OUT, "tesla.png"))

    # 10) Power Bank Battery (56x54)
    im = Image.new("RGBA", (56, 54), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    box(d, 4, 12, 52, 51, S2, S3, S1)
    box(d, 8, 6, 20, 13, S3, S4, S1, rivets=False)
    box(d, 36, 6, 48, 13, S3, S4, S1, rivets=False)
    for bx in (10, 23, 36):
        d.rectangle([bx, 18, bx + 10, 42], fill=(14, 24, 34, 255), outline=DK)
        for by in range(20, 40, 4):
            d.rectangle([bx + 2, by, bx + 8, by + 2], fill=(48, 236, 168, 255))
    hazard(d, 8, 46, 48, 49)
    outline(im).save(os.path.join(OUT, "battery.png"))

    # 11) Geothermal Magma Plant (76x72)
    im = Image.new("RGBA", (76, 72), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    box(d, 6, 30, 70, 66, S2, S3, S1)
    box(d, 10, 8, 24, 32, S1, S2, DK, rivets=False)
    box(d, 52, 12, 66, 32, S1, S2, DK, rivets=False)
    d.rectangle([26, 26, 50, 56], fill=(96, 24, 12, 255), outline=DK)
    d.rectangle([29, 29, 47, 53], fill=(240, 96, 20, 255))
    d.rectangle([33, 34, 43, 48], fill=AM3)
    d.rectangle([30, 64, 46, 71], fill=S3, outline=DK)
    outline(im).save(os.path.join(OUT, "geothermal.png"))

    # 12) Laser Turret (56x56)
    im = Image.new("RGBA", (56, 56), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    box(d, 6, 38, 50, 54, S2, S3, S1)
    hazard(d, 9, 48, 47, 51)
    box(d, 15, 31, 41, 39, S1, S2, DK, rivets=False)
    d.pieslice([13, 14, 43, 44], 180, 360, fill=S3, outline=DK)
    d.line([30, 23, 50, 6], fill=S4, width=4)
    d.line([33, 28, 52, 12], fill=S2, width=3)
    d.ellipse([21, 22, 31, 32], fill=(244, 56, 68, 255), outline=DK)
    d.point((24, 25), fill=(255, 220, 220, 255))
    outline(im).save(os.path.join(OUT, "turret.png"))

    # 13) Orbital Power Satellite (76x56) - dual golden-blue solar wings + microwave transmitter dish
    im = Image.new("RGBA", (76, 56), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    # Left & Right solar wing arrays
    d.rectangle([2, 14, 24, 34], fill=(18, 56, 118, 255), outline=DK)
    d.rectangle([52, 14, 74, 34], fill=(18, 56, 118, 255), outline=DK)
    for gx in (8, 14, 20, 58, 64, 70):
        d.line([gx, 15, gx, 33], fill=(64, 174, 244, 255))
    d.line([3, 24, 23, 24], fill=(64, 174, 244, 255))
    d.line([53, 24, 73, 24], fill=(64, 174, 244, 255))
    # Struts
    d.rectangle([23, 21, 53, 27], fill=S3, outline=DK)
    # Central reactor core + gold microwave dish below
    box(d, 28, 10, 48, 36, S2, S3, S1)
    d.ellipse([33, 16, 43, 26], fill=AM2, outline=DK)
    d.ellipse([35, 18, 41, 24], fill=AM3)
    d.pieslice([26, 34, 50, 52], 180, 360, fill=AM1, outline=DK)
    d.ellipse([35, 42, 41, 48], fill=CY2, outline=DK)
    outline(im).save(os.path.join(OUT, "orb_power.png"))

    # 14) Orbital Mining Laser (64x68) - heavy orbital lens cannon aimed downward
    im = Image.new("RGBA", (64, 68), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    # Cooling radiator fins
    d.polygon([(4, 14), (20, 10), (20, 32), (6, 28)], fill=S1, outline=DK)
    d.polygon([(60, 14), (44, 10), (44, 32), (58, 28)], fill=S1, outline=DK)
    for ry in (16, 22, 27):
        d.line([6, ry, 18, ry], fill=CY1)
        d.line([46, ry, 58, ry], fill=CY1)
    # Armored body + capacitor rings
    box(d, 18, 6, 46, 38, S2, S3, S1)
    hazard(d, 20, 10, 44, 14)
    d.rectangle([25, 18, 39, 32], fill=(16, 40, 56, 255), outline=DK)
    d.ellipse([27, 20, 37, 30], fill=CY2)
    d.ellipse([30, 22, 34, 26], fill=CY3)
    # Focusing barrel + glowing emerald-cyan lens
    box(d, 22, 38, 42, 54, S1, S2, DK, rivets=False)
    d.rectangle([20, 44, 44, 48], fill=AM2, outline=DK)
    d.polygon([(24, 54), (40, 54), (36, 64), (28, 64)], fill=CY1, outline=DK)
    d.rectangle([29, 57, 35, 63], fill=(96, 255, 214, 255))
    outline(im).save(os.path.join(OUT, "orb_laser.png"))

    # 15) Orbital Collector Module (68x64) - magnetic tractor scoop with glowing prongs
    im = Image.new("RGBA", (68, 64), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    box(d, 16, 8, 52, 34, S2, S3, S1)
    d.rectangle([22, 14, 46, 28], fill=(16, 34, 48, 255), outline=DK)
    d.rectangle([24, 16, 44, 22], fill=(56, 232, 186, 255))
    # Tractor arms curving downward like a wide catcher funnel
    d.polygon([(14, 28), (22, 28), (16, 54), (6, 48)], fill=S3, outline=DK)
    d.polygon([(46, 28), (54, 28), (62, 48), (52, 54)], fill=S3, outline=DK)
    d.ellipse([6, 48, 16, 58], fill=CY2, outline=DK)
    d.ellipse([52, 48, 62, 58], fill=CY2, outline=DK)
    # Magnetic field arc inside scoop
    d.arc([14, 34, 54, 60], 10, 170, fill=(84, 248, 226, 255), width=2)
    d.arc([20, 40, 48, 56], 15, 165, fill=CY3, width=2)
    outline(im).save(os.path.join(OUT, "orb_collector.png"))

    # 16) Orbital Craft Station (92x76) - ring-station orbital nanofactory
    im = Image.new("RGBA", (92, 76), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    # Outer habitat/factory ring
    d.ellipse([8, 12, 84, 64], fill=S1, outline=DK)
    d.ellipse([18, 20, 74, 56], fill=(0, 0, 0, 0), outline=DK)
    # Cross truss spokes
    d.rectangle([12, 34, 80, 42], fill=S2, outline=DK)
    d.rectangle([41, 14, 51, 62], fill=S2, outline=DK)
    # Left & Right fabrication pods
    box(d, 4, 26, 22, 50, S2, S3, S1)
    box(d, 70, 26, 88, 50, S2, S3, S1)
    d.rectangle([8, 32, 18, 44], fill=CY1, outline=DK)
    d.rectangle([74, 32, 84, 44], fill=AM2, outline=DK)
    # Central Zero-G Nanofactory Core
    box(d, 30, 22, 62, 54, S3, S4, S1)
    d.ellipse([36, 28, 56, 48], fill=(32, 22, 64, 255), outline=DK)
    d.ellipse([40, 32, 52, 44], fill=(164, 108, 255, 255))
    d.ellipse([43, 35, 49, 41], fill=CY3)
    # Top antenna mast
    d.line([46, 2, 46, 14], fill=S4, width=2)
    d.ellipse([43, 1, 49, 7], fill=CY2, outline=DK)
    outline(im).save(os.path.join(OUT, "orb_station.png"))


def make_crystals_and_celestials():
    # Large dramatic subterranean crystal clusters matching target_gameplay_concept.jpeg!
    crys = {
        "crystal_si": ((22, 118, 168, 255), (68, 212, 255, 255), (218, 252, 255, 255)),
        "ore_fe": ((124, 22, 28, 255), (232, 54, 52, 255), (255, 192, 178, 255)),
        "ore_cu": ((136, 68, 18, 255), (242, 162, 48, 255), (255, 236, 168, 255)),
        "ore_ti": ((76, 36, 138, 255), (168, 92, 246, 255), (244, 218, 255, 255)),
    }
    for name, (c0, c1, c2) in crys.items():
        im = Image.new("RGBA", (44, 40), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        polys = [
            [(10, 36), (5, 20), (11, 12), (17, 22), (16, 36)],
            [(16, 36), (17, 8), (22, 3), (28, 12), (25, 36)],
            [(25, 36), (30, 15), (37, 13), (38, 24), (31, 36)],
            [(6, 36), (2, 26), (7, 23), (12, 34)],
        ]
        for p in polys:
            d.polygon(p, fill=c0)
            d.polygon([p[0], p[1], p[2], ((p[0][0] + p[2][0]) // 2 + 2, p[0][1])], fill=c1)
            d.line([p[1], p[2]], fill=c2, width=2)
        outline(im).save(os.path.join(OUT, f"{name}.png"))

    # Enemy Orbital Fortress (160x120, upper-right target station in concept art!)
    im = Image.new("RGBA", (160, 120), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    wings = [
        [(6, 12), (62, 46), (50, 64), (2, 28)],
        [(98, 56), (154, 90), (144, 108), (88, 74)],
        [(98, 10), (150, 42), (140, 56), (88, 26)],
        [(14, 72), (66, 98), (58, 112), (6, 86)],
    ]
    for w in wings:
        d.polygon(w, fill=(40, 52, 78, 255), outline=DK)
        for i in range(1, 5):
            t = i / 5.0
            p0 = (int(w[0][0] + (w[1][0] - w[0][0]) * t), int(w[0][1] + (w[1][1] - w[0][1]) * t))
            p1 = (int(w[3][0] + (w[2][0] - w[3][0]) * t), int(w[3][1] + (w[2][1] - w[3][1]) * t))
            d.line([p0, p1], fill=(96, 128, 178, 255))
    # Armored central citadel
    d.polygon([(60, 26), (100, 26), (114, 60), (100, 94), (60, 94), (46, 60)], fill=S2, outline=DK)
    d.polygon([(65, 34), (95, 34), (106, 60), (95, 86), (65, 86), (54, 60)], fill=S1)
    # Glowing crimson reactor eye
    d.ellipse([64, 44, 96, 76], fill=(154, 22, 34, 255), outline=DK)
    d.ellipse([70, 50, 90, 70], fill=(255, 62, 68, 255))
    d.ellipse([75, 55, 85, 65], fill=(255, 226, 198, 255))
    outline(im).save(os.path.join(OUT, "enemy_station.png"))

    # Hostile Self-Replicating Red Probe (36x36, facing +X right)
    im = Image.new("RGBA", (36, 36), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    # Rear crimson thruster nozzles
    d.rectangle([3, 10, 9, 15], fill=(180, 32, 42, 255), outline=DK)
    d.rectangle([3, 21, 9, 26], fill=(180, 32, 42, 255), outline=DK)
    # Swept dark-crimson delta wings
    d.polygon([(7, 4), (24, 13), (18, 16), (5, 11)], fill=(128, 22, 34, 255), outline=DK)
    d.polygon([(7, 32), (24, 23), (18, 20), (5, 25)], fill=(128, 22, 34, 255), outline=DK)
    d.line([8, 6, 21, 13], fill=(242, 68, 76, 255))
    d.line([8, 30, 21, 23], fill=(242, 68, 76, 255))
    # Forward self-replicating harvester pincer mandibles (+X nose)
    d.polygon([(22, 11), (34, 14), (26, 16)], fill=(214, 48, 56, 255), outline=DK)
    d.polygon([(22, 25), (34, 22), (26, 20)], fill=(214, 48, 56, 255), outline=DK)
    # Armored octagonal probe hull
    d.polygon([(8, 12), (20, 10), (27, 15), (27, 21), (20, 26), (8, 24)], fill=(48, 24, 34, 255), outline=DK)
    d.polygon([(10, 14), (19, 12), (24, 16), (24, 20), (19, 24), (10, 22)], fill=(86, 30, 42, 255))
    # Glowing red optic core
    d.ellipse([14, 14, 22, 22], fill=(255, 46, 58, 255), outline=DK)
    d.ellipse([16, 16, 20, 20], fill=(255, 214, 186, 255))
    outline(im).save(os.path.join(OUT, "enemy_probe.png"))

    # 3 Shaded Moons + 4 Asteroids
    def sphere(fname, sz, base, hi, dark, crat, seed):
        sim = Image.new("RGBA", (sz, sz), (0, 0, 0, 0))
        px = sim.load()
        r = sz * 0.46
        c = sz * 0.5
        rng = random.Random(seed)
        cs = [(rng.uniform(-0.6, 0.6), rng.uniform(-0.6, 0.6), rng.uniform(0.08, 0.22)) for _ in range(9)]
        for y in range(sz):
            for x in range(sz):
                dx, dy = (x - c) / r, (y - c) / r
                d2 = dx * dx + dy * dy
                if d2 > 1.0:
                    continue
                dz = math.sqrt(max(0.0, 1.0 - d2))
                lit = dx * 0.55 - dy * 0.62 + dz * 0.56
                n = vnoise(x, y, sz * 0.14, seed)
                col = lerp_c(base, hi, n)
                for crx, cry, crr in cs:
                    if math.hypot(dx - crx, dy - cry) < crr:
                        col = lerp_c(col, crat, 0.55)
                col = lerp_c(dark, col, max(0.08, min(1.15, lit * 0.95 + 0.18)))
                if d2 > 0.84 and lit > 0.1:
                    col = lerp_c(col, hi, 0.45)
                px[x, y] = (col[0], col[1], col[2], 255)
        sim.save(os.path.join(OUT, fname))

    sphere("moon_luna.png", 96, (104, 118, 146, 255), (186, 204, 236, 255), (12, 16, 28, 255), (58, 68, 88, 255), 501)
    sphere("moon_ignis.png", 96, (162, 62, 32, 255), (255, 166, 62, 255), (24, 10, 10, 255), (255, 218, 88, 255), 502)
    sphere("moon_cryo.png", 96, (72, 152, 192, 255), (196, 244, 255, 255), (12, 26, 46, 255), (42, 92, 134, 255), 503)
    sphere("planet_astra.png", 96, (88, 64, 168, 255), (174, 242, 224, 255), (14, 12, 36, 255), (56, 134, 142, 255), 504)

    for fname, ore_col, seed in [
        ("ast_fe.png", (236, 70, 64, 255), 601),
        ("ast_cu.png", (246, 168, 52, 255), 602),
        ("ast_si.png", (68, 224, 255, 255), 603),
        ("ast_ti.png", (188, 112, 255, 255), 604),
    ]:
        aim = Image.new("RGBA", (36, 36), (0, 0, 0, 0))
        px = aim.load()
        rng = random.Random(seed)
        lumps = [(rng.uniform(0, math.tau), rng.uniform(0.10, 0.22)) for _ in range(4)]
        for y in range(36):
            for x in range(36):
                dx, dy = (x - 18) / 14.0, (y - 18) / 14.0
                ang = math.atan2(dy, dx)
                rad = 0.88 + sum(amp * math.cos(ang * (i + 2) + ph) for i, (ph, amp) in enumerate(lumps)) * 0.45
                if math.hypot(dx, dy) > rad:
                    continue
                lit = max(0.22, min(1.2, 0.72 + dx * 0.4 - dy * 0.5))
                n = vnoise(x, y, 4.5, seed)
                col = lerp_c((24, 26, 34, 255), (76, 78, 88, 255), lit * (0.7 + n * 0.5))
                if n > 0.74:
                    col = lerp_c(col, ore_col, 0.88)
                px[x, y] = (col[0], col[1], col[2], 255)
        outline(aim).save(os.path.join(OUT, fname))


def make_icons_and_glow():
    # 19 crisp 16x16 icons:
    # 0..11: fe, cu, si, ti, plate_fe, wire_cu, wafer_si, circuit, alloy, sci_pack, probe_stock, ice
    # 12..14: quantum_core, antimatter, dyson_panel
    # 15..18: ignis_ore, plasma_cell, cryo_rod, astra_shard
    im = Image.new("RGBA", (304, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    cols = [
        (228, 64, 58, 255), (242, 158, 46, 255), (62, 214, 255, 255), (174, 98, 246, 255),
        (154, 174, 198, 255), (236, 134, 48, 255), (52, 164, 224, 255), (46, 206, 118, 255),
        (194, 162, 242, 255), (72, 240, 186, 255), (255, 214, 82, 255), (156, 232, 255, 255),
        (124, 236, 255, 255), (255, 76, 168, 255), (255, 206, 68, 255),
        (255, 106, 34, 255), (255, 182, 46, 255), (86, 236, 255, 255), (218, 72, 255, 255),
    ]
    for i, c in enumerate(cols):
        x = i * 16
        hi = lerp_c(c, (255, 255, 255, 255), 0.55)
        if i in (0, 2, 3, 11, 15, 18):
            d.polygon([(x + 4, 13), (x + 3, 7), (x + 8, 2), (x + 13, 7), (x + 12, 13)], fill=c, outline=DK)
            d.line([x + 7, 4, x + 6, 11], fill=hi)
        elif i in (1, 5, 6):
            d.ellipse([x + 2, 2, x + 13, 13], fill=c, outline=DK)
            d.ellipse([x + 4, 4, x + 9, 8], fill=hi)
        elif i == 10:
            d.polygon([(x + 8, 2), (x + 3, 13), (x + 8, 10), (x + 13, 13)], fill=c, outline=DK)
            d.point((x + 8, 6), fill=CY3)
        elif i == 12:
            # Quantum Core: cyan-violet ringed energy sphere
            d.ellipse([x + 2, 2, x + 13, 13], fill=(92, 54, 198, 255), outline=DK)
            d.ellipse([x + 4, 4, x + 11, 11], fill=c)
            d.ellipse([x + 6, 6, x + 9, 9], fill=(255, 255, 255, 255))
        elif i in (13, 16):
            # Antimatter / Plasma Cell: glowing containment vial
            d.rectangle([x + 4, 1, x + 11, 14], fill=S2, outline=DK)
            d.rectangle([x + 5, 4, x + 10, 11], fill=c)
            d.line([x + 6, 5, x + 6, 10], fill=hi)
        elif i == 14:
            # Dyson Panel: hexagonal golden mirror array
            d.polygon([(x + 8, 1), (x + 14, 5), (x + 14, 11), (x + 8, 14), (x + 2, 11), (x + 2, 5)], fill=c, outline=DK)
            d.line([x + 8, 2, x + 8, 13], fill=hi)
            d.line([x + 3, 8, x + 13, 8], fill=(184, 112, 18, 255))
        elif i == 17:
            # Cryo Rod: diagonal superconducting cylinder
            d.polygon([(x + 3, 11), (x + 11, 3), (x + 13, 5), (x + 5, 13)], fill=c, outline=DK)
            d.line([x + 5, 10, x + 11, 4], fill=hi)
        else:
            d.rectangle([x + 2, 3, x + 13, 12], fill=c, outline=DK)
            d.line([x + 3, 4, x + 12, 4], fill=hi)
            if i == 7:
                d.rectangle([x + 5, 5, x + 10, 10], fill=(24, 30, 40, 255))
    im.save(os.path.join(OUT, "icon_strip.png"))

    # Radial soft glow
    g = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    px = g.load()
    for y in range(128):
        for x in range(128):
            dist = math.hypot(x - 63.5, y - 63.5) / 63.5
            if dist < 1.0:
                px[x, y] = (255, 255, 255, clamp(((1.0 - dist) ** 2.4) * 255.0))
    g.save(os.path.join(OUT, "glow.png"))


if __name__ == "__main__":
    make_hero_sprites()
    make_buildings()
    make_crystals_and_celestials()
    make_icons_and_glow()
    print("Generated true concept-art HD-2D sprite atlas in:", OUT)
