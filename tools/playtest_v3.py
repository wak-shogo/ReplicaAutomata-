"""
STAR REPLICA: AUTOMA (V3 Concept Rebuild) - Live WebGL Playthrough & Visual Audit
Plays the exported Web build via real mouse/keyboard inputs on Desktop (1280x720)
and Touch/Portrait Mobile (412x915), capturing screenshots for visual inspection.
"""
import functools
import http.server
import os
import socketserver
import threading
import time
from playwright.sync_api import sync_playwright

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOCS = os.path.join(ROOT, "docs")
SHOT_DIR = os.path.join(
    os.path.expanduser("~"),
    ".gemini", "antigravity", "brain", "a952e86c-2824-4a0b-8f37-837ef56179e4", "scratch", "v3_shots"
)
os.makedirs(SHOT_DIR, exist_ok=True)


class Quiet(http.server.SimpleHTTPRequestHandler):
    def log_message(self, format, *args):
        pass


def start_srv():
    httpd = socketserver.TCPServer(("127.0.0.1", 0), functools.partial(Quiet, directory=DOCS))
    t = threading.Thread(target=httpd.serve_forever, daemon=True)
    t.start()
    return httpd, httpd.server_address[1]


def tel(page):
    return page.evaluate("window.__star_tel || null")


def wait_tel(page, timeout=25.0):
    t0 = time.time()
    while time.time() - t0 < timeout:
        v = tel(page)
        if v:
            return v
        time.sleep(0.2)
    raise RuntimeError("Timed out waiting for __star_tel")


def click_xy(page, x, y, hold=0.08):
    page.mouse.move(x, y)
    page.mouse.down()
    time.sleep(hold)
    page.mouse.up()
    time.sleep(0.14)


def hold_key(page, key, dur):
    page.keyboard.down(key)
    time.sleep(dur)
    page.keyboard.up(key)
    time.sleep(0.1)


def main():
    httpd, port = start_srv()
    url = f"http://127.0.0.1:{port}/index.html"
    errors = []

    with sync_playwright() as p:
        browser = p.chromium.launch(
            channel="msedge", headless=True,
            args=["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader"],
        )
        ctx = browser.new_context(viewport={"width": 1280, "height": 720})
        page = ctx.new_page()
        page.on("pageerror", lambda e: errors.append(f"PAGEERR: {e}"))
        page.on("console", lambda m: errors.append(f"CONERR: {m.text}") if m.type == "error" else None)

        print("Opening:", url, flush=True)
        page.goto(url, wait_until="domcontentloaded")
        page.wait_for_selector("#canvas", timeout=25000)
        t0 = wait_tel(page, 30.0)
        time.sleep(1.2)
        page.screenshot(path=os.path.join(SHOT_DIR, "v3_01_concept_start.png"))
        print("START:", t0, flush=True)
        assert t0["bldg"] == 0 and t0["drones"] == 0, f"Bad start: {t0}"

        # 1. Organic Tunnel Mining & Crystal Harvesting with Seed Unit (WASD + Space/Mouse!)
        for step in range(10):
            t = tel(page)
            if t["fe"] >= 36 and t["cu"] >= 20:
                break
            dir_k = "KeyD" if step < 6 else "KeyA"
            page.keyboard.down(dir_k)
            page.keyboard.down("KeyW")
            time.sleep(0.55)
            page.keyboard.up("KeyW")
            page.keyboard.up(dir_k)
            page.mouse.move(680 if dir_k == "KeyD" else 590, 440)
            page.mouse.down()
            time.sleep(1.5)
            page.mouse.up()
        t_m = tel(page)
        print("AFTER MINING:", "fe=", t_m["fe"], "cu=", t_m["cu"], "si=", t_m["si"], "px=", t_m["px"], flush=True)
        assert t_m["fe"] >= 20 and t_m["cu"] >= 12, f"Mining failed: {t_m}"

        # 2. Physically Dock Fabricator Drone #1 onto Seed Unit! (Left sidebar +DOCK DRONE button ~ x=106, y=168)
        click_xy(page, 106, 168)
        time.sleep(0.35)
        t_d = tel(page)
        print("AFTER DOCK DRONE:", "drones=", t_d["drones"], flush=True)
        assert t_d["drones"] >= 1, f"Drone docking failed: {t_d}"
        page.screenshot(path=os.path.join(SHOT_DIR, "v3_02_drone_docked_caves.png"))

        # 3. Open Factorio Tech Tree [T], inspect & research Power & Tesla!
        page.keyboard.press("KeyT")
        time.sleep(0.35)
        page.screenshot(path=os.path.join(SHOT_DIR, "v3_03_tech_tree.png"))
        # Click RESEARCH button on bottom-right of Tech modal (x=990, y=545)
        click_xy(page, 990, 545)
        time.sleep(0.35)
        page.keyboard.press("KeyT")
        time.sleep(0.25)
        print("TECHS:", tel(page)["techs"], flush=True)
        assert "power_grid" in tel(page)["techs"], f"power_grid research failed: {tel(page)}"

        # 4. Build Solar Array & Tesla Relay via bottom hotbar POWER & DEF tab + Wire them!
        # Gather a little more Fe/Cu if needed for Solar(10,6) + Tesla(10,8)
        for step in range(8):
            t = tel(page)
            if t["fe"] >= 24 and t["cu"] >= 16:
                break
            page.keyboard.down("KeyA"); page.keyboard.down("KeyW"); time.sleep(0.5)
            page.keyboard.up("KeyW"); page.keyboard.up("KeyA")
            page.mouse.move(580, 440); page.mouse.down(); time.sleep(1.4); page.mouse.up()

        # Fly back up onto the surface if we dug into a subterranean cavern!
        for _ in range(10):
            if tel(page)["alt"] >= -70:
                break
            page.keyboard.down("KeyW")
            time.sleep(0.45)
            page.keyboard.up("KeyW")
            time.sleep(0.15)

        # Click POWER & DEF tab on bottom hotbar (tab 2 -> right third of hotbar, y=642, x=758)
        click_xy(page, 758, 642)
        time.sleep(0.25)
        # Equip Solar [2], click surface left of player
        page.keyboard.press("Digit2")
        time.sleep(0.2)
        click_xy(page, 500, 385)
        time.sleep(0.3)
        # Equip Tesla [3], click surface right of player
        page.keyboard.press("Digit3")
        time.sleep(0.2)
        click_xy(page, 760, 385)
        time.sleep(0.3)
        # Equip Wire [7], click Solar -> click Tesla!
        page.keyboard.press("Digit7")
        time.sleep(0.2)
        click_xy(page, 500, 365)
        time.sleep(0.25)
        click_xy(page, 760, 365)
        time.sleep(0.4)
        page.keyboard.press("Escape")
        t_w = tel(page)
        print("WIRED GRID:", "bldg=", t_w["bldg"], "wires=", t_w["wires"], "pwr=", t_w["pwr_prod"], "teslas=", t_w["teslas_on"], flush=True)
        page.screenshot(path=os.path.join(SHOT_DIR, "v3_04_wired_surface.png"))
        assert t_w["bldg"] >= 2 and t_w["wires"] >= 1 and t_w["pwr_prod"] >= 25, f"Wired grid failed: {t_w}"

        # 5. Toggle Full-Planet Orbital Macro View [M]
        page.keyboard.press("KeyM")
        time.sleep(1.0)
        page.screenshot(path=os.path.join(SHOT_DIR, "v3_05_orbital_macro.png"))
        page.keyboard.press("KeyM")
        ctx.close()

        # 6. Portrait Mobile (412x915, DPR 2.625) Touch HUD & Tech Tree
        mctx = browser.new_context(viewport={"width": 412, "height": 915}, device_scale_factor=2.625, has_touch=True, is_mobile=True)
        mpage = mctx.new_page()
        mpage.on("pageerror", lambda e: errors.append(f"MOBERR: {e}"))
        mpage.goto(url, wait_until="domcontentloaded")
        mpage.wait_for_selector("#canvas", timeout=25000)
        wait_tel(mpage, 25.0)
        time.sleep(1.2)
        mpage.screenshot(path=os.path.join(SHOT_DIR, "v3_06_mobile_hud.png"))
        mpage.keyboard.press("KeyT")
        time.sleep(0.4)
        mpage.screenshot(path=os.path.join(SHOT_DIR, "v3_07_mobile_tech.png"))
        mctx.close()
        browser.close()

    httpd.shutdown()
    print("V3_PLAYTEST_ERRORS:", errors, flush=True)
    assert len(errors) == 0, f"Browser runtime errors: {errors}"
    print("ALL V3 LIVE WEBGL PLAYTEST CHECKS PASSED!", flush=True)


if __name__ == "__main__":
    main()
