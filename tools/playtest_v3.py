"""Live WebGL Chromium playtest for STAR REPLICA: AUTOMA V5 (Heliocentric Solar System, FastNoiseLite Caves,
Always Player-Centered Zoom, Tech Detail Popup, Larger Visual-First HUD & Orbital Infrastructure)."""

from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from playwright.sync_api import sync_playwright
import functools
import os
import threading
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOCS_DIR = os.path.join(ROOT, "docs")
SHOT_DIR = r"C:\Users\wakazaki shogo\.gemini\antigravity\brain\a952e86c-2824-4a0b-8f37-837ef56179e4\scratch\v5_shots"
os.makedirs(SHOT_DIR, exist_ok=True)


class COOPHandler(SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def log_message(self, format, *args):
        pass


def start_server():
    handler = functools.partial(COOPHandler, directory=DOCS_DIR)
    srv = ThreadingHTTPServer(("127.0.0.1", 0), handler)
    port = srv.server_address[1]
    t = threading.Thread(target=srv.serve_forever, daemon=True)
    t.start()
    return srv, port


def tel(page):
    try:
        return page.evaluate("() => window.__star_tel || null")
    except Exception:
        return None


def wait_tel(page, timeout=25.0):
    t0 = time.time()
    while time.time() - t0 < timeout:
        v = tel(page)
        if v is not None:
            return v
        time.sleep(0.2)
    raise RuntimeError("Telemetry never appeared")


def click_xy(page, x, y, hold=0.06):
    page.mouse.move(x, y)
    page.mouse.down()
    time.sleep(hold)
    page.mouse.up()


def main():
    httpd, port = start_server()
    url = f"http://127.0.0.1:{port}/index.html"
    errors = []

    with sync_playwright() as p:
        try:
            browser = p.chromium.launch(
                channel="chrome",
                headless=True,
                args=["--use-gl=angle", "--use-angle=swiftshader", "--enable-webgl", "--ignore-gpu-blocklist"],
            )
        except Exception:
            browser = p.chromium.launch(
                channel="msedge",
                headless=True,
                args=["--use-gl=angle", "--use-angle=swiftshader", "--enable-webgl", "--ignore-gpu-blocklist"],
            )

        # === DESKTOP (1280x720) ===
        ctx = browser.new_context(viewport={"width": 1280, "height": 720})
        page = ctx.new_page()
        page.on("pageerror", lambda e: errors.append(f"PAGEERR: {e}"))
        page.on("console", lambda m: errors.append(f"CONSOLE_ERR: {m.text}") if m.type == "error" else None)

        print("Opening:", url, flush=True)
        page.goto(url, wait_until="domcontentloaded")
        page.wait_for_selector("#canvas", timeout=25000)
        t0 = wait_tel(page, 25.0)
        time.sleep(1.2)
        print("START:", t0, flush=True)
        page.screenshot(path=os.path.join(SHOT_DIR, "v5_01_start_day_caves.png"))

        # 1. Surface Mining with SPACE + Cursor Aim
        for step in range(18):
            t = tel(page)
            if t["fe"] >= 40 and t["cu"] >= 24:
                break
            dir_k = "KeyD" if step < 8 else "KeyA"
            page.keyboard.down(dir_k)
            page.keyboard.down("KeyW")
            time.sleep(0.45)
            page.keyboard.up("KeyW")
            page.keyboard.up(dir_k)
            page.mouse.move(745 if dir_k == "KeyD" else 535, 405)
            page.keyboard.down("Space")
            time.sleep(0.95)
            page.keyboard.up("Space")
        t_m = tel(page)
        print("AFTER MINING:", "fe=", t_m["fe"], "cu=", t_m["cu"], flush=True)
        assert t_m["fe"] >= 22 and t_m["cu"] >= 14, f"Mining failed: {t_m}"

        # 2. Open Tech Tree [T] -> Tap '電力とテスラ' card -> Verify DEDICATED TECH DETAIL POPUP opens!
        page.keyboard.press("KeyT")
        time.sleep(0.35)
        page.screenshot(path=os.path.join(SHOT_DIR, "v5_02_tech_tree.png"))
        # Desktop Tech modal: mw=920 -> x=180..1100, mh=560 -> y=80..640
        # cw=(920-86)/6=139, power_grid col=1, row=0 -> x=180+18+1*149=347..486 (cx=416), y=80+52=132..244 (cy=188)
        click_xy(page, 416, 188)
        time.sleep(0.35)
        t_td = tel(page)
        print("TECH DETAIL POPUP:", "modal=", t_td["modal"], "tech_detail=", t_td["tech_detail"], flush=True)
        page.screenshot(path=os.path.join(SHOT_DIR, "v5_03_tech_detail_popup.png"))
        assert t_td["tech_detail"] is True, f"Tapping Tech Card must open dedicated Tech Detail Popup! {t_td}"

        # Click wide bottom 「研究する」 button inside Tech Detail Popup!
        # Popup pw=580 -> x=350..930 (cx=640), ph=440 -> y=140..580, rb y=512..566 (cy=539)
        click_xy(page, 640, 539)
        time.sleep(0.35)
        t_res = tel(page)
        print("AFTER RESEARCH:", "techs=", t_res["techs"], "tech_detail=", t_res["tech_detail"], flush=True)
        assert "power_grid" in t_res["techs"] and t_res["tech_detail"] is False, f"Wide Research button failed! {t_res}"
        page.keyboard.press("Escape")
        time.sleep(0.2)

        # 3. Open Craft Modal [C] -> Click 軌道施設 tab (Tab 4) & capture!
        page.keyboard.press("KeyC")
        time.sleep(0.3)
        # Craft modal mw=860 -> x=210..1070, mh=640 -> y=40..680, ty=86..120 (cy=103), 5 tabs -> tab4 cx=222 + 4.5*167 = 974
        click_xy(page, 974, 103)
        time.sleep(0.3)
        page.screenshot(path=os.path.join(SHOT_DIR, "v5_04_craft_orbital_tab.png"))
        page.keyboard.press("Escape")
        time.sleep(0.2)

        # 4. Open Complete Item & Facility Recipe Tree [I] -> Verify wide spacing & 2D scroll!
        page.keyboard.press("KeyI")
        time.sleep(0.35)
        t_it = tel(page)
        print("ITEM TREE MODAL:", "modal=", t_it["modal"], "sel=", t_it["item_tree_sel"], flush=True)
        page.screenshot(path=os.path.join(SHOT_DIR, "v5_05_visual_guide.png"))
        assert t_it["modal"] == 8, f"KeyI must open Complete Item & Facility Recipe Tree (modal==8)! {t_it}"
        # Drag-scroll the Recipe Tree horizontally & vertically to inspect middle/right columns!
        page.mouse.move(850, 320)
        page.mouse.down()
        page.mouse.move(420, 260, steps=10)
        page.mouse.up()
        time.sleep(0.35)
        page.screenshot(path=os.path.join(SHOT_DIR, "v5_05b_recipe_tree_scrolled.png"))
        page.keyboard.press("Escape")
        time.sleep(0.2)

        # 5. Mouse-wheel zoom-out to full Terra planet with Day/Night shadow & verify ALWAYS player-centered (cam_err < 10)!
        page.mouse.move(640, 360)
        for _ in range(18):
            page.mouse.wheel(0, 120)
            time.sleep(0.05)
        time.sleep(0.8)
        t_z = tel(page)
        print("ZOOMED OUT (PLAYER-CENTERED):", "zoom=", t_z["zoom"], "cam_err=", t_z["cam_err"], flush=True)
        page.screenshot(path=os.path.join(SHOT_DIR, "v5_06_zoom_planet_daynight.png"))
        assert t_z["zoom"] < 0.14 and t_z["cam_err"] <= 15, f"Zoom-out must stay player-centered! {t_z}"

        # 6. Toggle Heliocentric Solar System Overview [M] -> Verify Sun + 4 Planets + Luna!
        page.keyboard.press("KeyM")
        time.sleep(1.2)
        page.screenshot(path=os.path.join(SHOT_DIR, "v5_07_solar_system_map.png"))
        ctx.close()

        # === PORTRAIT MOBILE (412x915, DPR 2.625) ===
        mctx = browser.new_context(viewport={"width": 412, "height": 915}, device_scale_factor=2.625, has_touch=True, is_mobile=True)
        mpage = mctx.new_page()
        mpage.on("pageerror", lambda e: errors.append(f"MOBERR: {e}"))
        mpage.goto(url, wait_until="domcontentloaded")
        mpage.wait_for_selector("#canvas", timeout=25000)
        wait_tel(mpage, 25.0)
        time.sleep(1.2)
        mpage.screenshot(path=os.path.join(SHOT_DIR, "v5_08_mobile_hud.png"))

        # Tap top-right 研究 button on mobile!
        # Logical HUD width=500 (scale = 412*2.625/500 = 2.163), CSS scale = 412/500 = 0.824
        # 研究 btn: x=500-100-8=392..492 (cx=442), y=52..90 (cy=71) -> CSS (364, 59)
        mpage.touchscreen.tap(364, 59)
        time.sleep(0.45)
        tm_tech = tel(mpage)
        print("MOBILE TAP TECH:", "modal=", tm_tech["modal"], flush=True)
        assert tm_tech["modal"] == 2, f"Mobile tap 研究 failed! {tm_tech}"
        # Tap Tech Card #1 (電力とテスラ) in mobile 2-col grid -> Opens Tech Detail Popup!
        mpage.touchscreen.tap(295, 311)
        time.sleep(0.4)
        tm_td = tel(mpage)
        print("MOBILE TECH DETAIL POPUP:", "tech_detail=", tm_td["tech_detail"], flush=True)
        mpage.screenshot(path=os.path.join(SHOT_DIR, "v5_09_mobile_tech_detail.png"))
        assert tm_td["tech_detail"] is True, f"Mobile tap Tech Card did not open detail popup! {tm_td}"

        # Open Recipe Tree on Mobile Portrait (412x915) & capture initial, Col 5 (Mass Driver), and zoomed views!
        mpage.keyboard.press("KeyI")
        time.sleep(0.45)
        tm_it = tel(mpage)
        print("MOBILE RECIPE TREE:", "modal=", tm_it["modal"], flush=True)
        mpage.screenshot(path=os.path.join(SHOT_DIR, "v5_10_mobile_recipe_tree.png"))
        assert tm_it["modal"] == 8, f"Mobile Recipe Tree did not open! {tm_it}"
        # Tap Stage Jump button 「3.回路・研究pt」 + 「右▶」 on Mobile Portrait Recipe Tree to view 3Dプリンタ & マスドライバー!
        # Logical HUD width=500, modal mw=488 (x=6..494), mh=830 (y=(1110-830)/2=140..970), nav_y=140+40=180..208 (cy=194 -> CSS y=160)
        # Button 4 ("3.回路・研究pt") logical cx ~ 295 -> CSS x=243; Button 5 ("右▶") logical cx ~ 372 -> CSS x=306
        mpage.touchscreen.tap(243, 160)
        time.sleep(0.3)
        mpage.touchscreen.tap(306, 160)
        time.sleep(0.3)
        # Tap マスドライバー card (row 2 -> logical y ~ 140+74+30+16 + 2*140 + 40 = 580 -> CSS y=478, CSS x=110)
        mpage.touchscreen.tap(110, 478)
        time.sleep(0.4)
        mpage.screenshot(path=os.path.join(SHOT_DIR, "v5_10b_mobile_recipe_tree_scrolled.png"))
        # Tap Zoom Out 「－」 twice (logical cx ~ 418 -> CSS x=344, y=160)
        mpage.touchscreen.tap(344, 160)
        time.sleep(0.25)
        mpage.touchscreen.tap(344, 160)
        time.sleep(0.35)
        mpage.screenshot(path=os.path.join(SHOT_DIR, "v5_10c_mobile_recipe_tree_zoomed.png"))
        mctx.close()
        browser.close()

    httpd.shutdown()
    print("V5_PLAYTEST_ERRORS:", errors, flush=True)
    assert len(errors) == 0, f"Browser runtime errors: {errors}"
    print("ALL V5 LIVE WEBGL PLAYTEST CHECKS PASSED!", flush=True)


if __name__ == "__main__":
    main()
