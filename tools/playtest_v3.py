"""Live WebGL Chromium playtest for STAR REPLICA: AUTOMA (V4 Japanese Craft Queue, Minimal HUD, Screen-Space Move & Interactive Tutorial)."""

from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from playwright.sync_api import sync_playwright
import functools
import os
import threading
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOCS_DIR = os.path.join(ROOT, "docs")
SHOT_DIR = r"C:\Users\wakazaki shogo\.gemini\antigravity\brain\a952e86c-2824-4a0b-8f37-837ef56179e4\scratch\v4_shots"
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
        page.screenshot(path=os.path.join(SHOT_DIR, "v4_01_jp_start.png"))

        # 1. Surface Mining using SPACE + Cursor Aim (tap-to-mine is abolished!)
        # First verify tapping empty ground does NOT fire mining beam!
        click_xy(page, 760, 368, hold=0.15)
        t_tap = tel(page)
        assert t_tap["beam_x"] == 0 and t_tap["beam_y"] == 0, f"Tap-to-mine should be abolished! {t_tap}"

        for step in range(20):
            t = tel(page)
            if t["fe"] >= 46 and t["cu"] >= 30:
                break
            dir_k = "KeyD" if step < 8 else "KeyA"
            page.keyboard.down(dir_k)
            page.keyboard.down("KeyW")
            time.sleep(0.45)
            page.keyboard.up("KeyW")
            page.keyboard.up(dir_k)
            page.mouse.move(745 if dir_k == "KeyD" else 535, 402)
            page.keyboard.down("Space")
            time.sleep(0.95)
            page.keyboard.up("Space")
        t_m = tel(page)
        print("AFTER MINING:", "fe=", t_m["fe"], "cu=", t_m["cu"], "tut_step=", t_m["tut_step"], flush=True)
        assert t_m["fe"] >= 32 and t_m["cu"] >= 20 and t_m["tut_step"] >= 1, f"Mining failed: {t_m}"

        # 2. Open Craft Modal [C] & Enqueue Fabricator Drone (verify TIMED queue, NOT instant!)
        page.keyboard.press("KeyC")
        time.sleep(0.35)
        # Drone craft button in 1280x720 Craft modal (mw=820 -> x=230..1050, mh=610 -> y=55..665, card1 y=129..217, btn right edge x=916..1028, y=151..195)
        click_xy(page, 972, 173)
        time.sleep(0.3)
        t_q = tel(page)
        print("DRONE QUEUED:", "queue=", t_q["queue"], "drones=", t_q["drones"], flush=True)
        page.screenshot(path=os.path.join(SHOT_DIR, "v4_02_craft_queue.png"))
        assert t_q["queue"] >= 1 and t_q["drones"] == 0, f"Craft queue must be timed, not instant: {t_q}"

        # Wait ~4.4s for Drone fabrication to finish & auto-dock!
        t_wait0 = time.time()
        while time.time() - t_wait0 < 8.0:
            if tel(page)["drones"] >= 1:
                break
            time.sleep(0.25)
        t_d = tel(page)
        print("AFTER DRONE CRAFT COMPLETE:", "drones=", t_d["drones"], "tut_step=", t_d["tut_step"], flush=True)
        assert t_d["drones"] >= 1 and t_d["tut_step"] >= 2, f"Drone auto-dock failed: {t_d}"
        page.keyboard.press("Escape")
        time.sleep(0.2)

        # 3. Open Japanese Tech Tree [T] & Research Power Grid!
        page.keyboard.press("KeyT")
        time.sleep(0.35)
        page.screenshot(path=os.path.join(SHOT_DIR, "v4_03_jp_tech.png"))
        # Research button on bottom-right of Tech modal (mw=880 -> x=200..1080, mh=540 -> y=90..630, dr y=496..620, rb x=902..1058, y=518..598)
        click_xy(page, 980, 558)
        time.sleep(0.35)
        page.keyboard.press("Escape")
        time.sleep(0.2)
        t_tech = tel(page)
        print("TECHS:", t_tech["techs"], "tut_step=", t_tech["tut_step"], flush=True)
        assert "power_grid" in t_tech["techs"], f"power_grid research failed: {t_tech}"

        # 4. Open Craft Modal [C] -> Click 電力・防衛 tab -> Enqueue Solar & Tesla -> Wait for Stock!
        page.keyboard.press("KeyC")
        time.sleep(0.3)
        # Tab 1 (電力・防衛): Craft modal x=230..1050, tw=(820-24)/4=199, tab1 x=242+199=441..636, y=93..121
        click_xy(page, 538, 107)
        time.sleep(0.25)
        # Row 0 (Solar): list_y=129, list_h=610-74-94-14=428, 5 items -> row_h=78, row0 y=129..207, mk_r x=946..1030
        click_xy(page, 988, 168)
        time.sleep(0.2)
        # Row 1 (Tesla): y=213..291, mk_r x=946..1030
        click_xy(page, 988, 252)
        time.sleep(0.25)
        page.screenshot(path=os.path.join(SHOT_DIR, "v4_04_craft_power_queue.png"))
        # Wait for Solar & Tesla to finish crafting!
        t_wait1 = time.time()
        while time.time() - t_wait1 < 10.0:
            tw = tel(page)
            if tw["stock_solar"] >= 1 and tw["stock_tesla"] >= 1:
                break
            time.sleep(0.25)
        t_st = tel(page)
        print("CRAFTED STOCK:", "solar=", t_st["stock_solar"], "tesla=", t_st["stock_tesla"], "tut_step=", t_st["tut_step"], flush=True)
        assert t_st["stock_solar"] >= 1 and t_st["stock_tesla"] >= 1, f"Building craft failed: {t_st}"

        # Close modal & fly up to surface if underground
        page.keyboard.press("Escape")
        time.sleep(0.2)
        for _ in range(10):
            if tel(page)["alt"] >= -70:
                break
            page.keyboard.down("KeyW")
            time.sleep(0.45)
            page.keyboard.up("KeyW")
            time.sleep(0.15)

        # 5. Place Solar & Tesla via Craft modal '配置する' or Bottom Dock, then Wire them!
        # Open Craft modal -> Tab 1 -> Click Solar '配置する' (x=856..940, y=168)
        page.keyboard.press("KeyC")
        time.sleep(0.25)
        click_xy(page, 898, 168)
        time.sleep(0.25)
        # Tap surface left of player (click skyward at y=160 so it always snaps to top surface!)
        click_xy(page, 500, 160)
        time.sleep(0.3)

        # Open Craft modal -> Click Tesla '配置する' (x=856..940, y=252)
        page.keyboard.press("KeyC")
        time.sleep(0.25)
        click_xy(page, 898, 252)
        time.sleep(0.25)
        # Tap surface right of player (skyward at y=160 so it snaps to top surface!)
        click_xy(page, 760, 160)
        time.sleep(0.35)

        # Bottom dock now has [通常, 配線, 削除, +製造] (4 slots -> bar_w=256, bx=512, slot1 配線 x=580..634, y=651..705)
        sol_y = max(130, min(520, 360 + int((tel(page)["alt"] + 30) * 0.88)))
        click_xy(page, 607, 678)
        time.sleep(0.25)
        click_xy(page, 500, sol_y)
        time.sleep(0.25)
        click_xy(page, 500, sol_y) # Double-click Solar in wire mode auto-links to nearest Tesla!
        time.sleep(0.4)
        page.keyboard.press("Escape")
        t_w = tel(page)
        print("WIRED GRID:", "bldg=", t_w["bldg"], "wires=", t_w["wires"], "pwr=", t_w["pwr_prod"], "tut_step=", t_w["tut_step"], flush=True)
        page.screenshot(path=os.path.join(SHOT_DIR, "v4_05_wired_surface.png"))
        assert t_w["bldg"] >= 2 and t_w["wires"] >= 1 and t_w["pwr_prod"] >= 25, f"Wired grid failed: {t_w}"

        # 6. Tap Solar facility in normal mode -> Opens Universal Facility Inspector Modal (modal==6)!
        click_xy(page, 500, sol_y)
        time.sleep(0.35)
        t_insp = tel(page)
        print("INSPECT SOLAR:", "modal=", t_insp["modal"], "insp_uid=", t_insp["insp_uid"], flush=True)
        page.screenshot(path=os.path.join(SHOT_DIR, "v4_06_building_inspector.png"))
        assert t_insp["modal"] == 6 and t_insp["insp_uid"] > 0, f"Tapping Solar must open Facility Inspector! {t_insp}"
        page.keyboard.press("Escape")
        time.sleep(0.25)

        # 7. Delete mode double-tap verification:
        # Bottom dock now has [通常, 配線, 削除, +製造] (4 slots -> bar_w=256, bx=512, slot2 削除 x=640..694, y=651..705)
        click_xy(page, 667, 678)
        time.sleep(0.25)
        # 1st tap on Solar -> MUST ARM only, NOT delete!
        click_xy(page, 500, sol_y)
        time.sleep(0.25)
        t_arm = tel(page)
        print("DELETE 1ST TAP (ARM):", "bldg=", t_arm["bldg"], "armed=", t_arm["armed_del"], flush=True)
        assert t_arm["bldg"] == 2 and t_arm["armed_del"] > 0, f"1st tap in delete mode should arm only! {t_arm}"
        # 2nd tap on Solar -> DELETES & refunds stock_solar == 1!
        click_xy(page, 500, sol_y)
        time.sleep(0.3)
        t_del = tel(page)
        print("DELETE 2ND TAP (DONE):", "bldg=", t_del["bldg"], "stock_solar=", t_del["stock_solar"], flush=True)
        assert t_del["bldg"] == 1 and t_del["stock_solar"] == 1, f"2nd tap in delete mode failed to delete & refund! {t_del}"
        page.keyboard.press("Escape")
        time.sleep(0.2)

        # 8. Open Guide Modal [H]
        page.keyboard.press("KeyH")
        time.sleep(0.35)
        page.screenshot(path=os.path.join(SHOT_DIR, "v4_07_guide_modal.png"))
        ctx.close()

        # === PORTRAIT MOBILE (412x915, DPR 2.625) REAL TOUCHSCREEN TAP & TWIN-STICK TEST! ===
        mctx = browser.new_context(viewport={"width": 412, "height": 915}, device_scale_factor=2.625, has_touch=True, is_mobile=True)
        mpage = mctx.new_page()
        mpage.on("pageerror", lambda e: errors.append(f"MOBERR: {e}"))
        mpage.goto(url, wait_until="domcontentloaded")
        mpage.wait_for_selector("#canvas", timeout=25000)
        wait_tel(mpage, 25.0)
        time.sleep(1.2)
        mpage.screenshot(path=os.path.join(SHOT_DIR, "v4_08_mobile_hud.png"))

        # 1) REAL Touchscreen tap on top-right クラフト button!
        # In logical 520x1155 HUD coords: x=520-88-8=424..512 (center 468), y=8..42 (center 25)
        # CSS coords on 412x915 viewport: cx = 468 * (412/520) = 371, cy = 25 * (412/520) = 20
        mpage.touchscreen.tap(371, 20)
        time.sleep(0.45)
        tm_craft = tel(mpage)
        print("MOBILE TAP CRAFT:", "modal=", tm_craft["modal"], flush=True)
        mpage.screenshot(path=os.path.join(SHOT_DIR, "v4_09_mobile_craft.png"))
        assert tm_craft["modal"] == 1, f"Mobile touchscreen tap on クラフト FAILED to open Craft modal! {tm_craft}"

        # 2) Tap 閉じる button inside Craft modal via REAL touchscreen tap!
        # Craft modal mw=500 -> x=10..510, mh=610 -> y=(1155-610)/2=272.5, close btn x=442..500 (cx=471), y=279.5..303.5 (cy=291.5)
        # CSS coords: cx = 471 * (412/520) = 373, cy = 291.5 * (412/520) = 231
        mpage.touchscreen.tap(373, 231)
        time.sleep(0.4)
        tm_closed = tel(mpage)
        print("MOBILE TAP CLOSE:", "modal=", tm_closed["modal"], flush=True)
        assert tm_closed["modal"] == 0, f"Mobile tap on 閉じる failed! {tm_closed}"

        # 3) REAL Touchscreen Drag on Bottom-Right Twin-Stick Mining Pad (aim DOWN-RIGHT!)
        # Logical act_center = (520 - 48 - 20, 1155 - 48 - 118) = (452, 989)
        # CSS coords: (452 * 412/520, 989 * 412/520) = (358, 784)
        cdp = mctx.new_cdp_session(mpage)
        cdp.send("Input.dispatchTouchEvent", {"type": "touchStart", "touchPoints": [{"x": 358, "y": 784, "id": 1}]})
        time.sleep(0.08)
        cdp.send("Input.dispatchTouchEvent", {"type": "touchMove", "touchPoints": [{"x": 388, "y": 814, "id": 1}]})
        time.sleep(0.45)
        tm_beam = tel(mpage)
        mpage.screenshot(path=os.path.join(SHOT_DIR, "v4_10_mobile_twinstick_beam.png"))
        time.sleep(1.2)
        cdp.send("Input.dispatchTouchEvent", {"type": "touchEnd", "touchPoints": []})
        time.sleep(0.2)
        tm_mined = tel(mpage)
        print("MOBILE TWIN-STICK BEAM:", "bx=", tm_beam["beam_x"], "by=", tm_beam["beam_y"], "fe=", tm_mined["fe"], "cu=", tm_mined["cu"], flush=True)
        assert tm_beam["beam_x"] > 10.0 and tm_beam["beam_y"] > 10.0, f"Right mining stick did not aim DOWN-RIGHT! {tm_beam}"
        assert (tm_mined["fe"] + tm_mined["cu"]) > 0, f"Mobile twin-stick mining failed to harvest ore! {tm_mined}"

        # 4) REAL Two-Finger Pinch-Out (Zoom IN -> huge close-up of Seed Unit!)
        z0 = tel(mpage)["zoom"]
        cdp.send("Input.dispatchTouchEvent", {"type": "touchStart", "touchPoints": [{"x": 180, "y": 400, "id": 10}, {"x": 230, "y": 400, "id": 11}]})
        for step in range(1, 7):
            dx = step * 24
            cdp.send("Input.dispatchTouchEvent", {"type": "touchMove", "touchPoints": [{"x": 180 - dx, "y": 400, "id": 10}, {"x": 230 + dx, "y": 400, "id": 11}]})
            time.sleep(0.05)
        cdp.send("Input.dispatchTouchEvent", {"type": "touchEnd", "touchPoints": []})
        time.sleep(0.45)
        z_in = tel(mpage)["zoom"]
        print("MOBILE PINCH ZOOM IN:", "before=", z0, "after=", z_in, flush=True)
        mpage.screenshot(path=os.path.join(SHOT_DIR, "v4_11_mobile_zoom_in.png"))
        assert z_in > 1.8, f"Pinch zoom-in did not zoom close enough! z={z_in}"

        # 5) REAL Two-Finger Pinch-In (Zoom OUT -> full spherical planet!)
        for _repeat in range(3):
            cdp.send("Input.dispatchTouchEvent", {"type": "touchStart", "touchPoints": [{"x": 40, "y": 400, "id": 20}, {"x": 370, "y": 400, "id": 21}]})
            for step in range(1, 7):
                dx = step * 24
                cdp.send("Input.dispatchTouchEvent", {"type": "touchMove", "touchPoints": [{"x": 40 + dx, "y": 400, "id": 20}, {"x": 370 - dx, "y": 400, "id": 21}]})
                time.sleep(0.05)
            cdp.send("Input.dispatchTouchEvent", {"type": "touchEnd", "touchPoints": []})
            time.sleep(0.15)
        time.sleep(0.6)
        z_out = tel(mpage)["zoom"]
        print("MOBILE PINCH ZOOM OUT (FULL PLANET):", "zoom=", z_out, flush=True)
        mpage.screenshot(path=os.path.join(SHOT_DIR, "v4_12_mobile_zoom_planet.png"))
        assert z_out < 0.14, f"Pinch zoom-out did not reach full-planet scale! z={z_out}"

        mctx.close()
        browser.close()

    httpd.shutdown()
    print("V4_PLAYTEST_ERRORS:", errors, flush=True)
    assert len(errors) == 0, f"Browser runtime errors: {errors}"
    print("ALL V4 JP LIVE WEBGL PLAYTEST CHECKS PASSED!", flush=True)


if __name__ == "__main__":
    main()
