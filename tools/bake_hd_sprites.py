"""
STAR REPLICA: AUTOMA - High-Craft HD-2D Pixel Art Extractor & Multi-Frame Animation Baker
1. Extracts crisp pixel-art sprites from generated magenta-chroma sheets using
   exterior flood-fill + anti-fringe despill (preserving internal purples/magentas!).
2. Builds 32x32 high-detail icon_strip.png (19 items -> 608x32).
3. Bakes pixel-locked 6-frame horizontal sprite-sheet animations (*_anim.png) for
   all industrial factories, mass driver, drill, tesla, geothermal, battery, solar,
   turret, orbital modules, and hero seed_core!
4. Upgrades fab_drone, orbital_booster, enemy_probe, enemy_station to matching HD-2D pixel art.
"""
import math
import os
from collections import deque
from PIL import Image, ImageDraw, ImageEnhance

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "sprites")
RAW_DIR = r"C:\Users\wakazaki shogo\.gemini\antigravity\brain\a952e86c-2824-4a0b-8f37-837ef56179e4"
PREVIEW_DIR = os.path.join(RAW_DIR, "scratch", "sprite_check")
os.makedirs(OUT, exist_ok=True)
os.makedirs(PREVIEW_DIR, exist_ok=True)


def clamp(v, lo=0, hi=255):
    return max(lo, min(hi, int(v)))


def is_magenta_bg(r, g, b, strict=False):
    if strict:
        # Catch both pure magenta and JPEG-compressed purple/magenta inside narrow steel truss holes
        return r > 125 and b > 125 and g < 92 and (r - g) > 55 and (b - g) > 55
    return r > 145 and b > 145 and g < 125 and (r - g) > 55 and (b - g) > 55


def remove_magenta_bg(im_rgba, remove_interior_magenta=True):
    """Exterior flood-fill chroma key + interior pure-magenta cutout + 1px fringe despill."""
    im = im_rgba.convert("RGBA")
    w, h = im.size
    px = im.load()

    visited = [[False] * w for _ in range(h)]
    bg = [[False] * w for _ in range(h)]
    q = deque()

    # Seed from all 4 borders
    for x in range(w):
        for y in (0, h - 1):
            r, g, b, a = px[x, y]
            if is_magenta_bg(r, g, b):
                visited[y][x] = True
                bg[y][x] = True
                q.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            if not visited[y][x]:
                r, g, b, a = px[x, y]
                if is_magenta_bg(r, g, b):
                    visited[y][x] = True
                    bg[y][x] = True
                    q.append((x, y))

    while q:
        cx, cy = q.popleft()
        for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            nx, ny = cx + dx, cy + dy
            if 0 <= nx < w and 0 <= ny < h and not visited[ny][nx]:
                r, g, b, a = px[nx, ny]
                if is_magenta_bg(r, g, b):
                    visited[ny][nx] = True
                    bg[ny][nx] = True
                    q.append((nx, ny))

    # Optional interior pure-magenta hole cutout (truss gaps, ring station hollow, legs)
    if remove_interior_magenta:
        for y in range(h):
            for x in range(w):
                if not bg[y][x]:
                    r, g, b, a = px[x, y]
                    if is_magenta_bg(r, g, b, strict=True):
                        bg[y][x] = True

    # Apply transparency
    for y in range(h):
        for x in range(w):
            if bg[y][x]:
                px[x, y] = (0, 0, 0, 0)

    # Anti-fringe pass (2 rings around transparent pixels): remove JPEG pink bleed
    for _pass in range(2):
        to_clear = []
        to_darken = []
        for y in range(h):
            for x in range(w):
                r, g, b, a = px[x, y]
                if a == 0:
                    continue
                adj_bg = False
                for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h and px[nx, ny][3] == 0:
                        adj_bg = True
                        break
                if not adj_bg:
                    continue
                mag_excess = min(r, b) - g
                if mag_excess > 45 and g < 115:
                    if (r + b) > 260:
                        to_clear.append((x, y))
                    else:
                        # Despill edge pixel toward dark pixel outline
                        nr = clamp(min(r, g + 14))
                        nb = clamp(min(b, g + 18))
                        to_darken.append((x, y, (nr, g, nb, 255)))
        for x, y in to_clear:
            px[x, y] = (0, 0, 0, 0)
        for x, y, col in to_darken:
            px[x, y] = col

    return im


def trim_and_fit(im, target_w, target_h, pad=1, align_bottom=True):
    """Trim transparent borders, scale crisply preserving aspect ratio into (target_w, target_h)."""
    bbox = im.getbbox()
    if not bbox:
        return Image.new("RGBA", (target_w, target_h), (0, 0, 0, 0))
    crop = im.crop(bbox)
    cw, ch = crop.size
    avail_w = max(1, target_w - pad * 2)
    avail_h = max(1, target_h - pad * 2)
    scale = min(avail_w / cw, avail_h / ch)
    nw = max(1, int(round(cw * scale)))
    nh = max(1, int(round(ch * scale)))

    # Crisp high-detail resize then alpha-threshold for razor-sharp pixel-art edges
    resized = crop.resize((nw, nh), Image.Resampling.LANCZOS)
    rpx = resized.load()
    for y in range(nh):
        for x in range(nw):
            r, g, b, a = rpx[x, y]
            if a < 115:
                rpx[x, y] = (0, 0, 0, 0)
            else:
                # Subtle saturation/crispness & eliminate any stray magenta fringe
                if min(r, b) - g > 60 and a < 215:
                    rpx[x, y] = (0, 0, 0, 0)
                else:
                    rpx[x, y] = (r, g, b, 255)

    out = Image.new("RGBA", (target_w, target_h), (0, 0, 0, 0))
    ox = (target_w - nw) // 2
    oy = (target_h - pad - nh) if align_bottom else (target_h - nh) // 2
    out.paste(resized, (ox, oy), resized)
    return out


def crisp_outline(im, col=(10, 13, 20, 255)):
    """Ensure crisp 1px dark silhouette around exterior transparent edge if missing."""
    w, h = im.size
    src = im.load()
    res = im.copy()
    dst = res.load()
    for y in range(h):
        for x in range(w):
            if src[x, y][3] > 0:
                continue
            for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and src[nx, ny][3] > 200:
                    nr, ng, nb, _ = src[nx, ny]
                    # Only add outline if neighbor isn't already very dark
                    if nr + ng + nb > 95:
                        dst[x, y] = col
                    break
    return res


def extract_grid_cells(path, cols, rows, remove_interior_list=None):
    im = Image.open(path).convert("RGBA")
    w, h = im.size
    cw = w / cols
    ch = h / rows
    cells = []
    for r in range(rows):
        for c in range(cols):
            idx = r * cols + c
            x0 = int(round(c * cw))
            y0 = int(round(r * ch))
            x1 = int(round((c + 1) * cw))
            y1 = int(round((r + 1) * ch))
            cell = im.crop((x0, y0, x1, y1))
            rem_int = True if remove_interior_list is None else bool(remove_interior_list[idx])
            clean = remove_magenta_bg(cell, remove_interior_magenta=rem_int)
            cells.append(clean)
    return cells


def add_glow_px(im, cx, cy, rad, col_rgb, strength=0.85):
    """Additive soft pixel-art glow overlay clipped cleanly."""
    w, h = im.size
    px = im.load()
    x0 = max(0, int(cx - rad))
    x1 = min(w - 1, int(cx + rad))
    y0 = max(0, int(cy - rad))
    y1 = min(h - 1, int(cy + rad))
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            d = math.hypot(x - cx, y - cy) / max(1.0, rad)
            if d >= 1.0:
                continue
            f = ((1.0 - d) ** 2.0) * strength
            r, g, b, a = px[x, y]
            if a == 0:
                na = clamp(f * 185)
                if na > 16:
                    px[x, y] = (col_rgb[0], col_rgb[1], col_rgb[2], na)
            else:
                px[x, y] = (
                    clamp(r + col_rgb[0] * f),
                    clamp(g + col_rgb[1] * f),
                    clamp(b + col_rgb[2] * f),
                    a,
                )


def tint_region_pulse(im, rect, mul_rgb, min_luma=90):
    """Pulse bright emissive pixels inside a bounding rect (for roaring flames, glowing screens, cores)."""
    w, h = im.size
    px = im.load()
    x0, y0, x1, y1 = max(0, rect[0]), max(0, rect[1]), min(w, rect[2]), min(h, rect[3])
    for y in range(y0, y1):
        for x in range(x0, x1):
            r, g, b, a = px[x, y]
            if a < 128:
                continue
            luma = 0.299 * r + 0.587 * g + 0.114 * b
            if luma >= min_luma:
                px[x, y] = (clamp(r * mul_rgb[0]), clamp(g * mul_rgb[1]), clamp(b * mul_rgb[2]), a)


def save_strip(frames, path):
    w, h = frames[0].size
    strip = Image.new("RGBA", (w * len(frames), h), (0, 0, 0, 0))
    for i, fr in enumerate(frames):
        strip.paste(fr, (i * w, 0))
    strip.save(path)


def bake_icons():
    s1 = extract_grid_cells(
        os.path.join(RAW_DIR, "icons_sheet_1_1795404795210.jpg"),
        5, 2,
        # Index 6 is astra_shard (purple/magenta crystal) -> preserve interior magenta!
        remove_interior_list=[True, True, True, True, True, True, False, True, True, True],
    )
    s2 = extract_grid_cells(
        os.path.join(RAW_DIR, "icons_sheet_2_1795404798322.jpg"),
        3, 3,
        # Index 7 is antimatter (bright magenta core!) -> preserve interior magenta!
        remove_interior_list=[True, True, True, True, True, True, True, False, True],
    )

    # Exact ICON_IDS order in scripts/core/art_reg.gd (19 items)
    ordered = [
        s1[0],  # 0: fe
        s1[1],  # 1: cu
        s1[2],  # 2: si
        s1[3],  # 3: ti
        s1[7],  # 4: plate_fe
        s1[8],  # 5: wire_cu
        s1[9],  # 6: wafer_si
        s2[0],  # 7: circuit
        s2[1],  # 8: alloy
        s2[2],  # 9: sci_pack
        s2[3],  # 10: probe_stock
        s1[5],  # 11: ice
        s2[6],  # 12: quantum_core
        s2[7],  # 13: antimatter
        s2[8],  # 14: dyson_panel
        s1[4],  # 15: ignis_ore
        s2[4],  # 16: plasma_cell
        s2[5],  # 17: cryo_rod
        s1[6],  # 18: astra_shard
    ]

    strip = Image.new("RGBA", (32 * len(ordered), 32), (0, 0, 0, 0))
    for i, cell in enumerate(ordered):
        ic = trim_and_fit(cell, 32, 32, pad=1, align_bottom=False)
        strip.paste(ic, (i * 32, 0), ic)
    strip.save(os.path.join(OUT, "icon_strip.png"))
    # Also save 4x zoomed preview sheet for visual inspection
    strip.resize((strip.width * 3, strip.height * 3), Image.Resampling.NEAREST).save(
        os.path.join(PREVIEW_DIR, "preview_icons.png")
    )
    print("Baked 32x32 icon_strip.png (19 icons).")


def bake_buildings_and_animations():
    b1 = extract_grid_cells(os.path.join(RAW_DIR, "buildings_sheet_1_1795404800273.jpg"), 2, 2)
    b2 = extract_grid_cells(os.path.join(RAW_DIR, "buildings_sheet_2_1795404800905.jpg"), 2, 2)
    b3 = extract_grid_cells(os.path.join(RAW_DIR, "buildings_sheet_3_ortho_1795404818762.jpg"), 2, 2)
    orb = extract_grid_cells(os.path.join(RAW_DIR, "orbital_sheet_1795404822348.jpg"), 2, 2)

    # 1. Depot (static high-craft base)
    depot = crisp_outline(trim_and_fit(b1[0], 144, 84, pad=2, align_bottom=True))
    depot.save(os.path.join(OUT, "depot.png"))

    # 2. Gantry 3D Macro Printer (192x140 + 6-frame sweeping laser & hologram print animation!)
    gp = crisp_outline(trim_and_fit(b1[1], 192, 140, pad=2, align_bottom=True))
    # Restore clean translucent cyan holographic containment chamber inside the projector frame
    gp_holo = Image.new("RGBA", gp.size, (0, 0, 0, 0))
    hd = ImageDraw.Draw(gp_holo)
    hd.rectangle([82, 73, 133, 118], fill=(28, 175, 255, 44))
    gp = Image.alpha_composite(gp_holo, gp)
    gp.save(os.path.join(OUT, "gantry_printer.png"))
    gp_frames = []
    for f in range(6):
        fr = gp.copy()
        d = ImageDraw.Draw(fr)
        if f == 0:
            # Standby dim hologram
            tint_region_pulse(fr, (78, 70, 136, 120), (0.65, 0.72, 0.85), min_luma=75)
        else:
            # Sweeping cyan fabrication laser + print scanline + weld spark!
            sweep = [0.18, 0.36, 0.56, 0.74, 0.45][f - 1]
            lx = int(86 + sweep * 42)
            sy = int(84 + ((f * 6) % 22))
            # Laser beam from overhead gantry emitter down to hologram craft
            d.line([(108, 72), (lx, sy)], fill=(90, 240, 255, 225), width=2)
            d.line([(108, 72), (lx, sy)], fill=(235, 255, 255, 255), width=1)
            # Horizontal holographic scanline across print chamber
            d.line([(83, sy), (132, sy)], fill=(120, 248, 255, 210), width=1)
            add_glow_px(fr, lx, sy, 10, (80, 235, 255), 0.88)
            add_glow_px(fr, lx, sy, 4, (255, 240, 170), 0.95)
            # Sparks at print point
            for sx, syo in [(-5, -3), (6, -4), (-3, 5), (5, 4)]:
                if ((f + sx) % 2) == 0:
                    d.point((lx + sx, sy + syo), fill=(255, 238, 150, 255))
            # Booth status screen pulse
            tint_region_pulse(fr, (18, 92, 54, 120), (1.05, 1.18, 1.24) if (f % 2 == 1) else (0.95, 1.05, 1.12), min_luma=95)
        gp_frames.append(fr)
    save_strip(gp_frames, os.path.join(OUT, "gantry_printer_anim.png"))

    # 3. Blast Smelter (128x128 + 6-frame roaring molten furnace & chimney heat animation!)
    sm = crisp_outline(trim_and_fit(b1[2], 128, 128, pad=2, align_bottom=True))
    sm.save(os.path.join(OUT, "smelter.png"))
    sm_frames = []
    for f in range(6):
        fr = sm.copy()
        d = ImageDraw.Draw(fr)
        if f == 0:
            tint_region_pulse(fr, (52, 86, 102, 114), (0.55, 0.42, 0.35), min_luma=65)
        else:
            p_wave = 1.0 + 0.22 * math.sin((f - 1) * math.tau / 5.0)
            tint_region_pulse(fr, (52, 86, 102, 114), (p_wave * 1.15, p_wave * 0.96, 0.80), min_luma=85)
            # Animated rising sparks inside hearth & flickering chimney heat glow
            add_glow_px(fr, 76, 102, 22, (255, 120, 24), 0.38 * p_wave)
            for k in range(4):
                fx = 58 + ((k * 11 + f * 7) % 34)
                fy = 109 - ((f * 4 + k * 5) % 16)
                d.rectangle([fx, fy, fx + 1, fy + 1], fill=(255, 245, 165, 255))
            # Glowing embers rising above twin smokestacks
            for st_x in (45, 62):
                ey = 14 - ((f * 3 + st_x) % 12)
                ex = st_x + int(math.sin(f * 1.4 + st_x) * 3)
                add_glow_px(fr, ex, max(2, ey), 6, (255, 130, 40), 0.45)
                d.point((ex, max(2, ey)), fill=(255, 220, 120, 255))
        sm_frames.append(fr)
    save_strip(sm_frames, os.path.join(OUT, "smelter_anim.png"))

    # 4. Auto Assembler (128x104 + 6-frame robotic welding spark & oscilloscope telemetry animation!)
    asm = crisp_outline(trim_and_fit(b1[3], 128, 104, pad=2, align_bottom=True))
    asm.save(os.path.join(OUT, "assembler.png"))
    asm_frames = []
    for f in range(6):
        fr = asm.copy()
        d = ImageDraw.Draw(fr)
        if f == 0:
            tint_region_pulse(fr, (96, 56, 122, 82), (0.55, 0.70, 0.72), min_luma=60)
        else:
            # Welding arc flash at robotic arm tip & laser nozzle
            wx = 66 + (f % 3) * 3
            wy = 66 + ((f + 1) % 2) * 2
            flash_s = 0.95 if (f in (1, 3, 5)) else 0.45
            add_glow_px(fr, wx, wy, 12, (95, 245, 255), flash_s)
            add_glow_px(fr, wx, wy, 6, (255, 245, 175), flash_s)
            if f in (1, 3, 5):
                for dx, dy in [(-6, -5), (5, -6), (-4, 4), (7, -2), (3, 5)]:
                    d.point((wx + dx, wy + dy), fill=(255, 232, 130, 255))
            # Animated scrolling telemetry bars on right monitor
            bar_x = 100 + ((f * 3) % 12)
            d.line([(bar_x, 62), (bar_x, 70)], fill=(120, 255, 210, 255), width=1)
            d.point((102 + (f * 2) % 10, 65), fill=(255, 255, 255, 255))
            # Top piston subtle vertical glow pulse
            add_glow_px(fr, 78, 52 + (f % 2) * 2, 5, (255, 180, 50), 0.55)
        asm_frames.append(fr)
    save_strip(asm_frames, os.path.join(OUT, "assembler_anim.png"))

    # 5. Mass Driver Railgun (192x162 + 6-frame sequential superconducting coil wave & muzzle discharge!)
    md = crisp_outline(trim_and_fit(b2[0], 192, 162, pad=2, align_bottom=True))
    md.save(os.path.join(OUT, "mass_driver.png"))
    md_frames = []
    # Exact breech-to-muzzle center line between the twin rails inside 192x162 canvas
    b_start = (48, 96)
    b_end = (166, 13)
    for f in range(6):
        fr = md.copy()
        d = ImageDraw.Draw(fr)
        if f == 0:
            # Standby dim coils
            tint_region_pulse(fr, (84, 12, 178, 96), (0.65, 0.72, 0.80), min_luma=110)
        elif f < 5:
            # Racing cyan-white electromagnetic charge pulse from breech -> muzzle!
            t_prog = (f - 1) / 3.0
            px_c = int(b_start[0] + (b_end[0] - b_start[0]) * (0.20 + t_prog * 0.72))
            py_c = int(b_start[1] + (b_end[1] - b_start[1]) * (0.20 + t_prog * 0.72))
            add_glow_px(fr, px_c, py_c, 16, (60, 225, 255), 0.90)
            add_glow_px(fr, px_c, py_c, 7, (240, 255, 255), 1.0)
            # Energy trail behind pulse
            px_t = int(b_start[0] + (b_end[0] - b_start[0]) * max(0.08, 0.20 + t_prog * 0.72 - 0.26))
            py_t = int(b_start[1] + (b_end[1] - b_start[1]) * max(0.08, 0.20 + t_prog * 0.72 - 0.26))
            d.line([(px_t, py_t), (px_c, py_c)], fill=(120, 245, 255, 235), width=3)
            d.line([(px_t, py_t), (px_c, py_c)], fill=(255, 255, 255, 255), width=1)
            # Breech orange plasma capacitor surge
            add_glow_px(fr, 28, 126, 12, (255, 140, 30), 0.35 + 0.35 * (1.0 - t_prog))
        else:
            # Frame 5: FULL RAILGUN LAUNCH DISCHARGE FLASH!
            d.line([b_start, b_end], fill=(100, 245, 255, 255), width=4)
            d.line([b_start, b_end], fill=(255, 255, 255, 255), width=2)
            add_glow_px(fr, b_end[0], b_end[1], 14, (90, 240, 255), 0.95)
            add_glow_px(fr, b_end[0], b_end[1], 8, (255, 235, 140), 1.0)
            add_glow_px(fr, 28, 126, 14, (255, 180, 50), 0.78)
        md_frames.append(fr)
    save_strip(md_frames, os.path.join(OUT, "mass_driver_anim.png"))

    # 6. Subterranean Drill Rig (96x128 + 6-frame spinning auger helix + beacon strobe!)
    dr = crisp_outline(trim_and_fit(b2[1], 96, 128, pad=2, align_bottom=True))
    dr.save(os.path.join(OUT, "drill.png"))
    dr_frames = []
    for f in range(6):
        fr = dr.copy()
        d = ImageDraw.Draw(fr)
        if f > 0:
            # Subtle 1px vertical shift on central auger spiral region to create crisp rotating screw illusion!
            auger_box = (36, 62, 60, 118)
            auger_crop = fr.crop(auger_box)
            shift_y = (f % 3) - 1
            fr.paste((0, 0, 0, 0), auger_box)
            fr.paste(auger_crop, (auger_box[0], auger_box[1] + shift_y), auger_crop)
            # Flashing amber strobe right on the roof warning beacon!
            if f in (1, 2, 4):
                add_glow_px(fr, 62, 46, 9, (255, 194, 42), 0.95)
            # Rock drilling sparks at auger tip
            for spx, spy in [(-7, 0), (8, -2), (-4, 4), (5, 3)]:
                if ((f + spx) % 2) == 0:
                    d.rectangle([48 + spx, 116 + spy, 49 + spx, 117 + spy], fill=(255, 214, 110, 255))
        dr_frames.append(fr)
    save_strip(dr_frames, os.path.join(OUT, "drill_anim.png"))

    # 7. Solar Panel Array (116x84 + 6-frame diagonal photovoltaic glint)
    sol = crisp_outline(trim_and_fit(b2[2], 116, 84, pad=2, align_bottom=True))
    sol.save(os.path.join(OUT, "solar.png"))
    sol_frames = []
    for f in range(6):
        fr = sol.copy()
        if f > 0:
            # Diagonal specular solar reflection sweep across blue panel pixels
            px = fr.load()
            band = 24 + (f - 1) * 18
            for y in range(6, 56):
                for x in range(8, 108):
                    r, g, b, a = px[x, y]
                    if a > 200 and b > r + 25 and b > 90:
                        dist = abs((x + y * 0.55) - band)
                        if dist < 6.0:
                            k = (1.0 - dist / 6.0) * 0.55
                            px[x, y] = (clamp(r + 180 * k), clamp(g + 225 * k), clamp(b + 255 * k), a)
        sol_frames.append(fr)
    save_strip(sol_frames, os.path.join(OUT, "solar_anim.png"))

    # 8. Tesla Power Relay Tower (88x128 + 6-frame crackling plasma lightning arcs!)
    tes = crisp_outline(trim_and_fit(b2[3], 88, 128, pad=2, align_bottom=True))
    tes.save(os.path.join(OUT, "tesla.png"))
    tes_frames = []
    for f in range(6):
        fr = tes.copy()
        d = ImageDraw.Draw(fr)
        if f == 0:
            tint_region_pulse(fr, (24, 4, 64, 38), (0.48, 0.58, 0.72), min_luma=85)
        else:
            cx, cy = 44, 19
            add_glow_px(fr, cx, cy, 20, (55, 225, 255), 0.58 + 0.25 * math.sin(f * 1.3))
            # 3 branching pixel lightning arcs around the top plasma orb
            for ai in range(3):
                ang = (f * 1.15 + ai * 2.1)
                x1 = cx + int(math.cos(ang) * 9)
                y1 = cy + int(math.sin(ang) * 9)
                xm = cx + int(math.cos(ang + 0.35) * 17)
                ym = cy + int(math.sin(ang + 0.35) * 16)
                x2 = cx + int(math.cos(ang - 0.15) * 24)
                y2 = cy + int(math.sin(ang - 0.15) * 21)
                d.line([(x1, y1), (xm, ym), (x2, y2)], fill=(120, 245, 255, 240), width=2)
                d.line([(x1, y1), (xm, ym), (x2, y2)], fill=(255, 255, 255, 255), width=1)
            # Copper coil subtle induction glow
            add_glow_px(fr, 44, 58, 14, (255, 175, 65), 0.28)
        tes_frames.append(fr)
    save_strip(tes_frames, os.path.join(OUT, "tesla_anim.png"))

    # 9. Geothermal Magma Power Plant (120x114 + 6-frame surging magma chamber & steam vents!)
    geo = crisp_outline(trim_and_fit(b3[0], 120, 114, pad=2, align_bottom=True))
    geo.save(os.path.join(OUT, "geothermal.png"))
    geo_frames = []
    for f in range(6):
        fr = geo.copy()
        d = ImageDraw.Draw(fr)
        if f == 0:
            tint_region_pulse(fr, (36, 42, 84, 78), (0.50, 0.38, 0.34), min_luma=70)
        else:
            pw = 1.0 + 0.20 * math.sin((f - 1) * math.tau / 5.0)
            tint_region_pulse(fr, (36, 42, 84, 78), (pw * 1.16, pw * 0.96, 0.80), min_luma=85)
            add_glow_px(fr, 60, 60, 24, (255, 115, 22), 0.42 * pw)
            # Rising glowing magma bubbles inside central window
            for bi in range(3):
                bx = 46 + ((bi * 12 + f * 5) % 28)
                by = 70 - ((f * 4 + bi * 6) % 18)
                d.rectangle([bx, by, bx + 2, by + 1], fill=(255, 245, 165, 255))
            # Pressurized steam puffs above twin cooling exhaust stacks
            for sx in (37, 74):
                sy = 8 - ((f * 2 + sx) % 7)
                add_glow_px(fr, sx, max(2, sy), 7, (220, 235, 255), 0.45)
        geo_frames.append(fr)
    save_strip(geo_frames, os.path.join(OUT, "geothermal_anim.png"))

    # 10. Power Bank Battery (96x92 + 6-frame rising emerald charge pulse!)
    bat = crisp_outline(trim_and_fit(b3[1], 96, 92, pad=2, align_bottom=True))
    bat.save(os.path.join(OUT, "battery.png"))
    bat_frames = []
    for f in range(6):
        fr = bat.copy()
        d = ImageDraw.Draw(fr)
        if f == 0:
            tint_region_pulse(fr, (14, 34, 82, 78), (0.45, 0.55, 0.52), min_luma=65)
        else:
            wy = 72 - ((f - 1) * 7)
            for cx in (27, 48, 69):
                add_glow_px(fr, cx, wy, 9, (90, 255, 195), 0.72)
                d.line([(cx - 4, wy), (cx + 4, wy)], fill=(225, 255, 240, 255), width=1)
        bat_frames.append(fr)
    save_strip(bat_frames, os.path.join(OUT, "battery_anim.png"))

    # 11. Defense Laser Turret (96x96 + 6-frame optic scanner & barrel charge!)
    tur = crisp_outline(trim_and_fit(b3[2], 96, 96, pad=2, align_bottom=True))
    tur.save(os.path.join(OUT, "turret.png"))
    tur_frames = []
    for f in range(6):
        fr = tur.copy()
        if f > 0:
            p = 0.45 + 0.50 * (0.5 + 0.5 * math.sin(f * 1.4))
            add_glow_px(fr, 53, 44, 8, (255, 50, 65), p)
            if f in (3, 4, 5):
                add_glow_px(fr, 73, 8, 6, (80, 240, 255), 0.88)
                add_glow_px(fr, 86, 9, 6, (80, 240, 255), 0.88)
        tur_frames.append(fr)
    save_strip(tur_frames, os.path.join(OUT, "turret_anim.png"))

    # 12. Seed Unit Core (64x64 + 4-frame breathing cyan AI optic core!)
    seed = crisp_outline(trim_and_fit(b3[3], 64, 64, pad=2, align_bottom=False))
    seed.save(os.path.join(OUT, "seed_core.png"))
    seed_frames = []
    for f in range(4):
        fr = seed.copy()
        p = 0.25 + 0.40 * (0.5 + 0.5 * math.sin(f * math.tau / 4.0))
        add_glow_px(fr, 32, 32, 11, (75, 235, 255), p)
        seed_frames.append(fr)
    save_strip(seed_frames, os.path.join(OUT, "seed_core_anim.png"))

    # 13..16. Orbital Facilities (High-Craft Base + 6-frame animations!)
    op = crisp_outline(trim_and_fit(orb[0], 128, 96, pad=2, align_bottom=False))
    op.save(os.path.join(OUT, "orb_power.png"))
    op_frames = []
    for f in range(6):
        fr = op.copy()
        if f > 0:
            add_glow_px(fr, 64, 64, 14, (75, 235, 255), 0.45 + 0.45 * math.sin(f * 1.2))
            add_glow_px(fr, 64, 76, 8, (255, 230, 120), 0.55)
        op_frames.append(fr)
    save_strip(op_frames, os.path.join(OUT, "orb_power_anim.png"))

    ol = crisp_outline(trim_and_fit(orb[1], 108, 116, pad=2, align_bottom=False))
    ol.save(os.path.join(OUT, "orb_laser.png"))
    ol_frames = []
    for f in range(6):
        fr = ol.copy()
        if f > 0:
            add_glow_px(fr, 54, 98, 14, (80, 255, 210), 0.55 + 0.40 * math.sin(f * 1.5))
            add_glow_px(fr, 54, 58, 12, (70, 210, 255), 0.45)
        ol_frames.append(fr)
    save_strip(ol_frames, os.path.join(OUT, "orb_laser_anim.png"))

    oc = crisp_outline(trim_and_fit(orb[2], 112, 106, pad=2, align_bottom=False))
    oc.save(os.path.join(OUT, "orb_collector.png"))
    oc_frames = []
    for f in range(6):
        fr = oc.copy()
        d = ImageDraw.Draw(fr)
        if f > 0:
            add_glow_px(fr, 34, 92, 11, (75, 245, 255), 0.78)
            add_glow_px(fr, 78, 92, 11, (75, 245, 255), 0.78)
            # Crackling magnetic tractor arc between catcher prongs
            mid_y = 84 + int(math.sin(f * 1.8) * 6)
            d.line([(36, 92), (56, mid_y), (76, 92)], fill=(115, 250, 240, 225), width=2)
            d.line([(36, 92), (56, mid_y), (76, 92)], fill=(235, 255, 255, 255), width=1)
        oc_frames.append(fr)
    save_strip(oc_frames, os.path.join(OUT, "orb_collector_anim.png"))

    os_im = crisp_outline(trim_and_fit(orb[3], 144, 128, pad=2, align_bottom=False))
    os_im.save(os.path.join(OUT, "orb_station.png"))
    os_frames = []
    for f in range(6):
        fr = os_im.copy()
        if f > 0:
            # Pulsing central quantum nanofactory core + rotating ring beacons!
            add_glow_px(fr, 72, 74, 16, (150, 120, 255), 0.55 + 0.35 * math.sin(f * 1.3))
            ang = f * math.tau / 5.0
            for k in range(3):
                ba = ang + k * (math.tau / 3.0)
                bx = int(72 + math.cos(ba) * 44)
                by = int(74 + math.sin(ba) * 44)
                add_glow_px(fr, bx, by, 7, (85, 240, 255), 0.85)
        os_frames.append(fr)
    save_strip(os_frames, os.path.join(OUT, "orb_station_anim.png"))

    # Visual contact sheet preview for inspection
    sheet = Image.new("RGBA", (600, 420), (14, 18, 28, 255))
    sheet.paste(depot, (10, 10), depot)
    sheet.paste(gp_frames[2], (164, 8), gp_frames[2])
    sheet.paste(sm_frames[2], (366, 8), sm_frames[2])
    sheet.paste(asm_frames[3], (10, 154), asm_frames[3])
    sheet.paste(md_frames[5], (148, 152), md_frames[5])
    sheet.paste(dr_frames[2], (350, 156), dr_frames[2])
    sheet.paste(tes_frames[2], (456, 156), tes_frames[2])
    sheet.paste(geo_frames[2], (10, 290), geo_frames[2])
    sheet.paste(sol_frames[2], (140, 316), sol_frames[2])
    sheet.paste(bat_frames[2], (266, 308), bat_frames[2])
    sheet.paste(tur_frames[3], (372, 304), tur_frames[3])
    sheet.paste(seed_frames[1], (486, 326), seed_frames[1])
    sheet.save(os.path.join(PREVIEW_DIR, "preview_buildings.png"))
    print("Baked all buildings + 6-frame animations.")


def bake_crystals_and_asteroids():
    ca = extract_grid_cells(
        os.path.join(RAW_DIR, "crystals_asteroids_sheet_1795404825197.jpg"),
        4, 2,
        # Preserve purple titanium interior in col 3!
        remove_interior_list=[True, True, True, False, True, True, True, False],
    )
    outcrops = [("ore_fe.png", ca[0]), ("ore_cu.png", ca[1]), ("crystal_si.png", ca[2]), ("ore_ti.png", ca[3])]
    for fname, cell in outcrops:
        im = crisp_outline(trim_and_fit(cell, 64, 60, pad=1, align_bottom=True))
        im.save(os.path.join(OUT, fname))
    asts = [("ast_fe.png", ca[4]), ("ast_cu.png", ca[5]), ("ast_si.png", ca[6]), ("ast_ti.png", ca[7])]
    for fname, cell in asts:
        im = crisp_outline(trim_and_fit(cell, 56, 56, pad=1, align_bottom=False))
        im.save(os.path.join(OUT, fname))
    print("Baked all 4 crystal outcrops and 4 asteroids.")


def bake_upgraded_units():
    """High-craft 32-bit multi-shaded HD pixel art for fab_drone, orbital_booster, enemy_probe, enemy_station."""
    DK = (10, 13, 20, 255)
    S0 = (26, 32, 44, 255)
    S1 = (46, 55, 72, 255)
    S2 = (78, 92, 114, 255)
    S3 = (122, 140, 166, 255)
    S4 = (182, 202, 224, 255)
    AM0 = (128, 62, 16, 255)
    AM1 = (196, 108, 28, 255)
    AM2 = (244, 174, 52, 255)
    AM3 = (255, 232, 136, 255)
    CY1 = (18, 128, 186, 255)
    CY2 = (66, 222, 255, 255)
    CY3 = (218, 252, 255, 255)
    RD0 = (68, 14, 24, 255)
    RD1 = (142, 24, 38, 255)
    RD2 = (224, 46, 58, 255)
    RD3 = (255, 132, 118, 255)

    # 1. Fabricator Drone (36x36)
    im = Image.new("RGBA", (36, 36), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    # Armored amber shoulder pods
    d.polygon([(8, 5), (28, 5), (32, 13), (32, 22), (27, 27), (9, 27), (4, 22), (4, 13)], fill=AM1, outline=DK)
    d.polygon([(9, 6), (27, 6), (30, 12), (28, 15), (8, 15), (6, 12)], fill=AM2)
    d.line([(10, 7), (26, 7)], fill=AM3)
    # Central brushed gunmetal chassis
    d.rectangle([10, 8, 26, 24], fill=S2, outline=DK)
    d.rectangle([12, 10, 24, 22], fill=S1)
    d.line([(11, 9), (25, 9)], fill=S4)
    # Glowing cyan optic eye with specular highlight
    d.ellipse([12, 10, 24, 22], fill=CY1, outline=DK)
    d.ellipse([14, 12, 22, 20], fill=CY2)
    d.ellipse([15, 13, 19, 17], fill=CY3)
    # Articulated welding pincer arms
    d.polygon([(8, 25), (12, 25), (9, 33), (5, 31)], fill=S3, outline=DK)
    d.polygon([(24, 25), (28, 25), (31, 31), (27, 33)], fill=S3, outline=DK)
    d.point((7, 32), fill=CY3)
    d.point((29, 32), fill=CY3)
    crisp_outline(im).save(os.path.join(OUT, "fab_drone.png"))

    # 2. Orbital Booster Skirt (68x72)
    im = Image.new("RGBA", (68, 72), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    # Twin white-ceramic cryogenic side tanks with bevel shading & orange bands
    for tx in (4, 48):
        d.rounded_rectangle([tx, 16, tx + 16, 54], radius=5, fill=(192, 204, 220, 255), outline=DK)
        d.rectangle([tx + 2, 18, tx + 6, 52], fill=(242, 248, 255, 255))
        d.rectangle([tx + 12, 18, tx + 14, 52], fill=S2)
        d.rectangle([tx + 1, 28, tx + 15, 34], fill=AM2, outline=DK)
        d.line([(tx + 2, 29), (tx + 14, 29)], fill=AM3)
        d.rectangle([tx + 1, 44, tx + 15, 47], fill=S1)
    # Central gold-foil thermal truss skirt
    d.polygon([(18, 36), (50, 36), (56, 54), (12, 54)], fill=AM1, outline=DK)
    d.polygon([(20, 38), (48, 38), (52, 50), (16, 50)], fill=AM2)
    for gx in range(20, 49, 6):
        d.line([(gx, 38), (gx, 52)], fill=AM0)
    d.line([(20, 38), (48, 38)], fill=AM3)
    # Twin gimballed bell rocket nozzles
    for bx in (24, 44):
        d.polygon([(bx - 6, 54), (bx + 6, 54), (bx + 10, 69), (bx - 10, 69)], fill=S1, outline=DK)
        d.polygon([(bx - 5, 55), (bx - 1, 55), (bx - 3, 68), (bx - 8, 68)], fill=S3)
        d.line([(bx - 7, 62), (bx + 7, 62)], fill=S0, width=2)
        d.line([(bx - 9, 67), (bx + 9, 67)], fill=S4)
    crisp_outline(im).save(os.path.join(OUT, "orbital_booster.png"))

    # 3. Hostile Self-Replicating Red Probe (48x48, facing +X right)
    im = Image.new("RGBA", (48, 48), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    # Rear crimson ion thrusters
    d.rectangle([3, 13, 12, 20], fill=RD1, outline=DK)
    d.rectangle([3, 28, 12, 35], fill=RD1, outline=DK)
    d.rectangle([4, 15, 7, 18], fill=AM3)
    d.rectangle([4, 30, 7, 33], fill=AM3)
    # Swept razor crimson-obsidian delta wings
    d.polygon([(8, 4), (33, 16), (24, 21), (6, 13)], fill=RD0, outline=DK)
    d.polygon([(8, 44), (33, 32), (24, 27), (6, 35)], fill=RD0, outline=DK)
    d.polygon([(10, 7), (29, 16), (23, 19), (9, 12)], fill=RD1)
    d.polygon([(10, 41), (29, 32), (23, 29), (9, 36)], fill=RD1)
    d.line([(10, 6), (31, 16)], fill=RD2, width=2)
    d.line([(10, 42), (31, 32)], fill=RD2, width=2)
    # Forward armored harvester pincer mandibles (+X nose)
    d.polygon([(28, 13), (45, 19), (34, 22)], fill=RD2, outline=DK)
    d.polygon([(28, 35), (45, 29), (34, 26)], fill=RD2, outline=DK)
    d.line([(30, 15), (43, 19)], fill=RD3)
    d.line([(30, 33), (43, 29)], fill=RD3)
    # Armored dark-steel hexagonal core hull
    d.polygon([(10, 15), (26, 12), (36, 19), (36, 29), (26, 36), (10, 33)], fill=S0, outline=DK)
    d.polygon([(13, 17), (25, 15), (32, 20), (32, 28), (25, 33), (13, 31)], fill=(66, 24, 36, 255))
    d.line([(14, 17), (25, 15)], fill=RD2)
    # Glowing scarlet AI core eye
    d.ellipse([17, 18, 29, 30], fill=RD1, outline=DK)
    d.ellipse([19, 20, 27, 28], fill=RD2)
    d.ellipse([21, 21, 25, 25], fill=(255, 224, 204, 255))
    add_glow_px(im, 23, 24, 9, (255, 45, 58), 0.55)
    crisp_outline(im).save(os.path.join(OUT, "enemy_probe.png"))

    # 4. Enemy Orbital Citadel Fortress (180x136)
    im = Image.new("RGBA", (180, 136), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    wings = [
        [(8, 12), (72, 50), (58, 72), (4, 32)],
        [(108, 64), (172, 102), (160, 124), (96, 86)],
        [(108, 12), (170, 48), (158, 66), (96, 30)],
        [(14, 80), (74, 112), (64, 128), (6, 98)],
    ]
    for w in wings:
        d.polygon(w, fill=S0, outline=DK)
        for i in range(1, 6):
            t = i / 6.0
            p0 = (int(w[0][0] + (w[1][0] - w[0][0]) * t), int(w[0][1] + (w[1][1] - w[0][1]) * t))
            p1 = (int(w[3][0] + (w[2][0] - w[3][0]) * t), int(w[3][1] + (w[2][1] - w[3][1]) * t))
            d.line([p0, p1], fill=RD1, width=2)
        d.line([w[0], w[1]], fill=S3, width=2)
    # Heavy hexagonal armored core
    d.polygon([(64, 24), (116, 24), (134, 68), (116, 112), (64, 112), (46, 68)], fill=S1, outline=DK)
    d.polygon([(70, 32), (110, 32), (124, 68), (110, 104), (70, 104), (56, 68)], fill=S0, outline=DK)
    d.line([(66, 26), (114, 26)], fill=S4, width=2)
    # Blazing crimson AI reactor core
    d.ellipse([68, 46, 112, 90], fill=RD0, outline=DK)
    d.ellipse([73, 51, 107, 85], fill=RD1)
    d.ellipse([78, 56, 102, 80], fill=RD2)
    d.ellipse([84, 62, 96, 74], fill=(255, 224, 194, 255))
    add_glow_px(im, 90, 68, 28, (255, 42, 58), 0.58)
    crisp_outline(im).save(os.path.join(OUT, "enemy_station.png"))
    print("Baked upgraded HD unit & enemy sprites.")


if __name__ == "__main__":
    bake_icons()
    bake_buildings_and_animations()
    bake_crystals_and_asteroids()
    bake_upgraded_units()
    print("ALL HD-2D SPRITES AND MULTI-FRAME ANIMATIONS BAKED SUCCESSFULLY!")
