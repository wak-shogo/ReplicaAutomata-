"""
STAR REPLICA: AUTOMA - Live Chromium/WebGL Computer Use Playthrough & Visual Audit
Plays the exported Web build via real virtual joystick drags, ABXY clicks,
and keyboard shortcuts on Desktop (1280x720) and Mobile Portrait (412x915).
"""
import functools
import http.server
import math
import os
import socketserver
import threading
import time
from playwright.sync_api import sync_playwright

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOCS = os.path.join(ROOT, "docs")
SHOT_DIR = os.path.join(
    os.path.expanduser("~"),
    ".gemini", "antigravity", "brain", "a952e86c-2824-4a0b-8f37-837ef56179e4", "scratch", "v2_shots"
)
os.makedirs(SHOT_DIR, exist_ok=True)

# Desktop (1280x720) control coordinates computed identically to hud.gd
JOY = (88, 624)
BTN_A = (1159, 651)
BTN_B = (1223, 587)
BTN_X = (1095, 587)
BTN_Y = (1159, 523)


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, format, *args):
        pass


def start_server():
    handler = functools.partial(QuietHandler, directory=DOCS)
    httpd = socketserver.TCPServer(("127.0.0.1", 0), handler)
    port = httpd.server_address[1]
    t = threading.Thread(target=httpd.serve_forever, daemon=True)
    t.start()
    return httpd, port


def get_tel(page):
    return page.evaluate("window.__star_tel || null")


def wait_tel(page, timeout=25.0):
    t0 = time.time()
    while time.time() - t0 < timeout:
        tel = get_tel(page)
        if tel:
            return tel
        time.sleep(0.2)
    raise RuntimeError("Timed out waiting for __star_tel telemetry")


def click_pt(page, pt, hold_s=0.09):
    page.mouse.move(pt[0], pt[1])
    page.mouse.down()
    time.sleep(hold_s)
    page.mouse.up()
    time.sleep(0.14)


def drag_joy(page, dx, dy, dur_s=0.7):
    page.mouse.move(JOY[0], JOY[1])
    page.mouse.down()
    page.mouse.move(JOY[0] + dx, JOY[1] + dy)
    time.sleep(dur_s)
    page.mouse.up()
    time.sleep(0.12)


def move_surface_to(page, target_x, max_s=18.0, tol=70.0):
    t0 = time.time()
    while time.time() - t0 < max_s:
        tel = get_tel(page)
        if not tel:
            time.sleep(0.15)
            continue
        diff = target_x - tel["px"]
        if abs(diff) <= tol and tel["r"] >= 6280:
            click_pt(page, BTN_B, hold_s=0.16)
            return True
        cw = 1.0 if diff > 0 else -1.0
        if tel["r"] < 6395:
            # Hop cleanly up & over 120px crust ledges!
            dx = 34.0 * cw
            dy = -52.0
        else:
            dx = 54.0 * cw if abs(diff) > 150 else 32.0 * cw
            dy = -26.0
        drag_joy(page, dx, dy, 0.68)
    click_pt(page, BTN_B, hold_s=0.16)
    return False


def research_tech(page, tech_id, idx):
    tel = get_tel(page)
    if tech_id in tel["techs"]:
        return True
    page.keyboard.press("KeyT")
    time.sleep(0.35)
    # Reset selection to 0 via repeated Y (PREV), then step forward via X (NEXT)
    for _ in range(8):
        click_pt(page, BTN_Y, 0.05)
    # Use stick left to clamp at 0 cleanly
    for _ in range(8):
        drag_joy(page, -52, 0, 0.08)
    for _ in range(idx):
        drag_joy(page, 52, 0, 0.08)
    time.sleep(0.15)
    click_pt(page, BTN_A)
    time.sleep(0.28)
    ok = tech_id in get_tel(page)["techs"]
    if get_tel(page)["menu"] != 0:
        click_pt(page, BTN_B)
    return ok


def equip_build(page, tab_idx, row_idx):
    if get_tel(page)["menu"] != 0:
        click_pt(page, BTN_B)
    click_pt(page, BTN_X)
    time.sleep(0.22)
    # Click tab directly on Desktop (mw=540 -> x0=370, y0=108; tab_w=172, y=135)
    tx = 382 + tab_idx * 172 + 80
    click_pt(page, (tx, 135))
    time.sleep(0.16)
    # Click row directly (y = 160 + row_idx * 46 + 20)
    ry = 160 + row_idx * 46 + 20
    click_pt(page, (640, ry))
    time.sleep(0.22)


def place_building(page, tab_idx, row_idx, cw=1.0):
    before = get_tel(page)["bldg"]
    equip_build(page, tab_idx, row_idx)
    click_pt(page, BTN_A)
    time.sleep(0.28)
    for _ in range(4):
        if get_tel(page)["bldg"] > before:
            break
        drag_joy(page, 46 * cw, -16, 0.45)
        click_pt(page, BTN_A)
        time.sleep(0.25)
    if get_tel(page)["tool"] != "pick":
        click_pt(page, BTN_B)
    return get_tel(page)["bldg"] > before


def main():
    httpd, port = start_server()
    url = f"http://127.0.0.1:{port}/index.html"
    errors = []

    with sync_playwright() as p:
        browser = p.chromium.launch(
            channel="msedge",
            headless=True,
            args=["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader"],
        )
        ctx = browser.new_context(viewport={"width": 1280, "height": 720})
        page = ctx.new_page()
        page.on("pageerror", lambda e: errors.append(f"PAGEERROR: {e}"))
        page.on("console", lambda m: errors.append(f"CONSOLE_ERR: {m.text}") if m.type == "error" else None)

        print("Opening:", url, flush=True)
        page.goto(url, wait_until="domcontentloaded")
        page.wait_for_selector("#canvas", timeout=25000)
        tel0 = wait_tel(page, 30.0)
        time.sleep(1.0)
        page.screenshot(path=os.path.join(SHOT_DIR, "v2_01_capsule_start.png"))
        print("STAGE 0 Initial:", tel0, flush=True)
        assert tel0["eng"] == 0 and tel0["bldg"] == 0, f"Bad initial state: {tel0}"

        # STAGE 1: Electric Ion Hop & Surface Crust Mining (Fe & Cu)
        drag_joy(page, 18, -55, 0.8)
        tel_hop = get_tel(page)
        print("STAGE 1A Ion Hop:", tel_hop["alt"], "bat=", tel_hop["bat"], flush=True)
        assert tel_hop["bat"] < 100, f"Ion battery did not consume on hop: {tel_hop}"

        for step in range(22):
            t = get_tel(page)
            if t["fe"] >= 48 and t["cu"] >= 36:
                break
            cw = 1.0 if step < 11 else -1.0
            drag_joy(page, 48 * cw, -34, 0.72)
            click_pt(page, BTN_A, hold_s=1.8)
        t_mine = get_tel(page)
        print("STAGE 1B Mined:", "fe=", t_mine["fe"], "cu=", t_mine["cu"], "px=", t_mine["px"], "r=", t_mine["r"], flush=True)
        assert t_mine["fe"] >= 30 and t_mine["cu"] >= 18, f"Starter mining too low: {t_mine}"

        # Open Tech Tree & screenshot
        page.keyboard.press("KeyT")
        time.sleep(0.35)
        page.screenshot(path=os.path.join(SHOT_DIR, "v2_02_tech_tree.png"))
        click_pt(page, BTN_B)
        assert research_tech(page, "tesla_grid", 1), f"tesla_grid research failed: {get_tel(page)}"
        print("STAGE 1C Researched tesla_grid!", flush=True)

        # STAGE 2: Build Solar Array + Tesla Coil + Wire them!
        move_surface_to(page, 120.0)
        assert place_building(page, 2, 0, 1.0), "Solar placement failed"
        move_surface_to(page, 320.0)
        assert place_building(page, 2, 1, 1.0), "Tesla placement failed"
        # Select Wire tool (tab 2, row 5) and press A twice to auto-wire Solar <-> Tesla!
        equip_build(page, 2, 5)
        click_pt(page, BTN_A)
        time.sleep(0.25)
        click_pt(page, BTN_A)
        time.sleep(0.35)
        click_pt(page, BTN_B)
        t_pwr = get_tel(page)
        print("STAGE 2A Wired Power Grid:", "wires=", t_pwr["wires"], "pwr_prod=", t_pwr["pwr_prod"], "teslas_on=", t_pwr["teslas_on"], flush=True)
        assert t_pwr["wires"] >= 1 and t_pwr["teslas_on"] >= 1 and t_pwr["pwr_prod"] >= 25, f"Wired grid failed: {t_pwr}"

        # Gather enough Fe & Cu for Belt Logistics + Metallurgy + Drill/Belt/Depot/Smelter + Lander Mk-I (120 Fe, 65 Cu)
        for step in range(28):
            t = get_tel(page)
            if t["fe"] >= 120 and t["cu"] >= 65:
                break
            spot = -240.0 - float(step) * 195.0
            move_surface_to(page, spot, max_s=10.0, tol=85.0)
            click_pt(page, BTN_A, hold_s=2.2)
        t_res = get_tel(page)
        print("STAGE 2B Resources ready:", "fe=", t_res["fe"], "cu=", t_res["cu"], flush=True)
        assert research_tech(page, "belt_logistics", 2), f"belt_logistics failed: {get_tel(page)}"
        assert research_tech(page, "metallurgy", 3), f"metallurgy failed: {get_tel(page)}"

        # Build Drill, Belt, Cargo Depot, Blast Smelter inside Tesla dome!
        move_surface_to(page, 430.0)
        assert place_building(page, 0, 0, 1.0), "Drill failed"
        move_surface_to(page, 540.0)
        assert place_building(page, 0, 1, 1.0), "Belt failed"
        move_surface_to(page, 650.0)
        assert place_building(page, 0, 3, 1.0), "Depot failed"
        # Open Cargo Depot modal via [A] right beside it!
        click_pt(page, BTN_A)
        time.sleep(0.35)
        if get_tel(page)["menu"] == 4:
            # Click RIGHT filter button & screenshot Depot UI!
            click_pt(page, (560, 232))
            time.sleep(0.2)
            page.screenshot(path=os.path.join(SHOT_DIR, "v2_03_depot_ui.png"))
            click_pt(page, BTN_B)
            print("STAGE 2C Depot 4-Way Filter UI verified!", flush=True)

        move_surface_to(page, 210.0)
        assert place_building(page, 1, 0, -1.0), "Smelter failed"
        time.sleep(0.6)
        page.screenshot(path=os.path.join(SHOT_DIR, "v2_04_wired_factory.png"))

        # Smelt >= 4 Iron Plates on Blast Smelter -> Print Lander Mk-I & Fabricator Drone!
        for _s in range(14):
            ts = get_tel(page)
            if ts["plate_fe"] >= 4:
                break
            move_surface_to(page, 210.0, max_s=6.0, tol=55.0)
            click_pt(page, BTN_A)
            time.sleep(2.2)
        print("STAGE 3A Smelted:", "plate_fe=", get_tel(page)["plate_fe"], "fe=", get_tel(page)["fe"], "cu=", get_tel(page)["cu"], flush=True)

        # Open Onboard 3D Printer [Y] -> Print Lander Mk-I [Y] -> Craft Drone [X]
        click_pt(page, BTN_Y)
        time.sleep(0.3)
        page.screenshot(path=os.path.join(SHOT_DIR, "v2_05_printer_menu.png"))
        click_pt(page, BTN_Y) # Upgrade to Lander Mk-I!
        time.sleep(0.35)
        t_mk1 = get_tel(page)
        print("STAGE 3B Vessel Upgraded:", "eng=", t_mk1["eng"], "fuel=", t_mk1["fuel"], flush=True)
        assert t_mk1["eng"] >= 1, f"Lander Mk-I upgrade failed: {t_mk1}"

        # Launch Lander Mk-I into Vacuum Keplerian Space!
        print("STAGE 3C Launching Lander Mk-I to Space...", flush=True)
        t_asc = time.time()
        page.mouse.move(JOY[0], JOY[1])
        page.mouse.down()
        try:
            while time.time() - t_asc < 65.0:
                tel = get_tel(page)
                if tel:
                    if tel["r"] > 10100:
                        break
                    if tel["r"] <= 7250:
                        dx, dy = (0.35 if tel["alt"] > 350 else 0.0), -1.0
                    else:
                        rn = max(1.0, math.hypot(tel["px"], tel["py"]))
                        ux, uy = tel["px"] / rn, tel["py"] / rn
                        dx, dy = ux - uy * 0.45, uy + ux * 0.45
                    dl = max(0.01, math.hypot(dx, dy))
                    page.mouse.move(JOY[0] + (dx / dl) * 58.0, JOY[1] + (dy / dl) * 58.0)
                time.sleep(0.2)
        finally:
            page.mouse.up()

        t_sp0 = get_tel(page)
        print("STAGE 3D Reached Space:", "r=", t_sp0["r"], "vel=", t_sp0["vel"], "fuel=", t_sp0["fuel"], flush=True)
        assert t_sp0["r"] > 9650, f"Did not exit atmosphere into space: {t_sp0}"
        page.screenshot(path=os.path.join(SHOT_DIR, "v2_06_space_orbit.png"))

        # Verify Zero-Drag Vacuum Coast (hands off for 2.5s!)
        v0 = t_sp0["vel"]
        time.sleep(2.5)
        t_sp1 = get_tel(page)
        print("STAGE 3E Vacuum Keplerian Coast:", v0, "->", t_sp1["vel"], "r=", t_sp1["r"], flush=True)
        assert t_sp1["vel"] > 50, f"Spacecraft stopped artificially in vacuum: {t_sp1}"

        # Toggle Orbital Macro View [M]
        page.keyboard.press("KeyM")
        time.sleep(0.9)
        page.screenshot(path=os.path.join(SHOT_DIR, "v2_07_macro_planet.png"))
        ctx.close()

        # STAGE 4: Portrait Mobile (412x915, DPR 2.625)
        mctx = browser.new_context(viewport={"width": 412, "height": 915}, device_scale_factor=2.625, has_touch=True, is_mobile=True)
        mpage = mctx.new_page()
        mpage.on("pageerror", lambda e: errors.append(f"MOB_PAGEERROR: {e}"))
        mpage.goto(url, wait_until="domcontentloaded")
        mpage.wait_for_selector("#canvas", timeout=25000)
        wait_tel(mpage, 25.0)
        time.sleep(1.0)
        mpage.screenshot(path=os.path.join(SHOT_DIR, "v2_08_mobile_hud.png"))
        mpage.keyboard.press("KeyT")
        time.sleep(0.4)
        mpage.screenshot(path=os.path.join(SHOT_DIR, "v2_09_mobile_tech.png"))
        mctx.close()
        browser.close()

    httpd.shutdown()
    print("VERIFY_ERRORS:", errors, flush=True)
    assert len(errors) == 0, f"Browser runtime errors: {errors}"
    print("ALL LIVE WEBGL COMPUTER USE CHECKS PASSED!", flush=True)


if __name__ == "__main__":
    main()
