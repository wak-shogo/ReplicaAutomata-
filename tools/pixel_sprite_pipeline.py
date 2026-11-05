#!/usr/bin/env python3
"""
AI Pixel Art Sprite Generator & Post-Processor Pipeline
Uses local Gemini Image Generation API (gemini-2.5-flash-image) +
Chroma/Flood-Fill Background Removal + Auto-Crop + Nearest-Neighbor Downscaling +
16-24 Color Palette Quantization + 1px Dark Outline.
"""

import os
import sys
import json
import base64
import math
import time
import urllib.request
from collections import deque
from PIL import Image, ImageEnhance, ImageFilter

def load_api_key() -> str:
    env_file = "C:/Users/wakazaki shogo/AppData/Local/hermes/.env"
    if os.path.exists(env_file):
        with open(env_file, "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                if "=" in line and not line.strip().startswith("#"):
                    k, v = line.strip().split("=", 1)
                    if k.strip() in ("GEMINI_API_KEY", "GOOGLE_API_KEY"):
                        val = v.strip().strip("'\"")
                        if val:
                            return val
    return os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY") or ""

def call_gemini_image_api(prompt: str, api_key: str, raw_save_path: str = None) -> Image.Image:
    model = "gemini-2.5-flash-image"
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={api_key}"
    
    full_prompt = (
        f"Generate a clean 16-bit dark sci-fi pixel art game sprite of: {prompt}. "
        "STYLE: High-detail retro pixel art (like Factorio / Into the Breach / Cogmind), "
        "isolated on a solid flat pure black #000000 background. "
        "Crisp pixel edges, distinct metallic shading, glowing cyan/amber sci-fi accents, "
        "centered single object, no background scenery, no text, no watermark, no frame."
    )
    
    payload = {
        "contents": [{"parts": [{"text": full_prompt}]}],
        "generationConfig": {"responseModalities": ["IMAGE"]}
    }
    
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"}
    )
    
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=90) as resp:
                result = json.loads(resp.read().decode("utf-8"))
                parts = result["candidates"][0]["content"]["parts"]
                for p in parts:
                    if "inlineData" in p:
                        img_bytes = base64.b64decode(p["inlineData"]["data"])
                        if raw_save_path:
                            os.makedirs(os.path.dirname(raw_save_path), exist_ok=True)
                            with open(raw_save_path, "wb") as f:
                                f.write(img_bytes)
                        from io import BytesIO
                        return Image.open(BytesIO(img_bytes)).convert("RGBA")
        except Exception as e:
            print(f"[Warn] Attempt {attempt+1} failed: {e}")
            time.sleep(2)
    raise RuntimeError(f"Failed to generate image for prompt: {prompt}")

def remove_background_floodfill(img: Image.Image, tolerance: float = 42.0) -> Image.Image:
    """
    Removes solid background using border-connected flood fill + inner dark key removal.
    Preserves internal dark armor details while cleanly making the background Alpha=0.
    """
    img = img.convert("RGBA")
    w, h = img.size
    pixels = img.load()
    
    # Sample corner colors to determine background color
    corners = [pixels[0, 0], pixels[w-1, 0], pixels[0, h-1], pixels[w-1, h-1]]
    bg_r = sum(c[0] for c in corners) // 4
    bg_g = sum(c[1] for c in corners) // 4
    bg_b = sum(c[2] for c in corners) // 4
    
    def color_dist(r, g, b):
        return math.sqrt((r - bg_r)**2 + (g - bg_g)**2 + (b - bg_b)**2)
    
    visited = [[False] * w for _ in range(h)]
    queue = deque()
    
    # Seed all border pixels that match background
    for x in range(w):
        for y in (0, h - 1):
            r, g, b, a = pixels[x, y]
            if color_dist(r, g, b) <= tolerance * 1.3:
                visited[y][x] = True
                queue.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            if not visited[y][x]:
                r, g, b, a = pixels[x, y]
                if color_dist(r, g, b) <= tolerance * 1.3:
                    visited[y][x] = True
                    queue.append((x, y))
                    
    # BFS flood fill from borders
    while queue:
        cx, cy = queue.popleft()
        pixels[cx, cy] = (0, 0, 0, 0)
        for nx, ny in ((cx+1, cy), (cx-1, cy), (cx, cy+1), (cx, cy-1)):
            if 0 <= nx < w and 0 <= ny < h and not visited[ny][nx]:
                r, g, b, a = pixels[nx, ny]
                if color_dist(r, g, b) <= tolerance:
                    visited[ny][nx] = True
                    queue.append((nx, ny))
                    
    # Also remove any enclosed pure-background holes (strict tolerance)
    strict_tol = tolerance * 0.45
    for y in range(h):
        for x in range(w):
            if not visited[y][x]:
                r, g, b, a = pixels[x, y]
                if color_dist(r, g, b) <= strict_tol:
                    pixels[x, y] = (0, 0, 0, 0)
                    
    return img

def post_process_pixel_sprite(
    img: Image.Image,
    target_size: tuple[int, int],
    num_colors: int = 20,
    add_outline: bool = True,
    outline_color: tuple[int, int, int, int] = (10, 14, 24, 255)
) -> Image.Image:
    # 1. Background removal
    img = remove_background_floodfill(img, tolerance=42.0)
    
    # 2. Auto-crop to non-transparent bounding box
    bbox = img.getbbox()
    if bbox:
        img = img.crop(bbox)
        
    tw, th = target_size
    margin = 2 if add_outline else 0
    avail_w = max(4, tw - margin * 2)
    avail_h = max(4, th - margin * 2)
    
    # Preserve aspect ratio within available target box
    src_w, src_h = img.size
    scale = min(avail_w / float(src_w), avail_h / float(src_h))
    new_w = max(1, int(round(src_w * scale)))
    new_h = max(1, int(round(src_h * scale)))
    
    # Intermediate downsample with BOX to prevent single-pixel aliasing artifacts from 1024x1024,
    # then final snap with NEAREST
    if src_w > new_w * 3:
        mid_w = new_w * 2
        mid_h = new_h * 2
        img = img.resize((mid_w, mid_h), Image.Resampling.BOX)
    img_small = img.resize((new_w, new_h), Image.Resampling.NEAREST)
    
    # Place centered on target canvas
    canvas = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
    off_x = (tw - new_w) // 2
    off_y = (th - new_h) // 2
    canvas.paste(img_small, (off_x, off_y))
    
    # 3. Clean alpha threshold & Desaturate slightly for gritty dark sci-fi feel + Quantize palette
    c_pixels = canvas.load()
    rgb_img = Image.new("RGB", (tw, th), (0, 0, 0))
    rgb_pixels = rgb_img.load()
    alpha_mask = [[0] * tw for _ in range(th)]
    
    for y in range(th):
        for x in range(tw):
            r, g, b, a = c_pixels[x, y]
            if a > 96:
                alpha_mask[y][x] = 255
                rgb_pixels[x, y] = (r, g, b)
            else:
                alpha_mask[y][x] = 0
                rgb_pixels[x, y] = (0, 0, 0)
                
    # Slightly tone saturation for cohesive dark sci-fi palette & increase contrast
    rgb_img = ImageEnhance.Color(rgb_img).enhance(0.92)
    rgb_img = ImageEnhance.Contrast(rgb_img).enhance(1.15)
    
    # Quantize to 16-24 colors
    quantized_rgb = rgb_img.quantize(colors=num_colors, method=Image.Quantize.MEDIANCUT).convert("RGB")
    q_pixels = quantized_rgb.load()
    
    final_img = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
    f_pixels = final_img.load()
    
    for y in range(th):
        for x in range(tw):
            if alpha_mask[y][x] > 0:
                r, g, b = q_pixels[x, y]
                f_pixels[x, y] = (r, g, b, 255)
                
    # 4. Add 1px dark outline around opaque pixels
    if add_outline:
        outline_coords = []
        for y in range(th):
            for x in range(tw):
                if alpha_mask[y][x] == 0:
                    # Check 4-neighbors
                    has_opaque_neighbor = False
                    for nx, ny in ((x+1, y), (x-1, y), (x, y+1), (x, y-1)):
                        if 0 <= nx < tw and 0 <= ny < th and alpha_mask[ny][nx] > 0:
                            has_opaque_neighbor = True
                            break
                    if has_opaque_neighbor:
                        outline_coords.append((x, y))
        for ox, oy in outline_coords:
            f_pixels[ox, oy] = outline_color
            
    return final_img

def generate_pixel_sprite(
    prompt: str,
    target_size: tuple[int, int],
    output_path: str,
    num_colors: int = 20,
    add_outline: bool = True
) -> str:
    api_key = load_api_key()
    if not api_key:
        raise RuntimeError("GEMINI_API_KEY / GOOGLE_API_KEY not found in environment!")
        
    raw_dir = os.path.join(os.path.dirname(output_path), "_raw_ai")
    os.makedirs(raw_dir, exist_ok=True)
    raw_path = os.path.join(raw_dir, os.path.basename(output_path))
    
    print(f"[1/2] Generating AI base image for '{os.path.basename(output_path)}' ({target_size[0]}x{target_size[1]})...")
    raw_img = call_gemini_image_api(prompt, api_key, raw_save_path=raw_path)
    
    print(f"[2/2] Post-processing (bg removal -> crop -> nearest {target_size} -> {num_colors} colors -> 1px outline)...")
    sprite_img = post_process_pixel_sprite(
        raw_img,
        target_size=target_size,
        num_colors=num_colors,
        add_outline=add_outline
    )
    
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    sprite_img.save(output_path)
    print(f"[DONE] Saved pixel sprite to: {output_path} ({os.path.getsize(output_path)} bytes)")
    return output_path

if __name__ == "__main__":
    # Test generation for Player Seed Unit (48x48) & Mass Driver (140x110)
    base_sprites = "C:/Users/wakazaki shogo/git/StarReplica-Automa/assets/sprites"
    
    generate_pixel_sprite(
        prompt="futuristic modular self-replicating space mining probe core unit (Seed Unit), top-down view, dark gunmetal steel armor plates, glowing cyan energy reactor core in center, 4 mechanical docking ports on corners, industrial sci-fi",
        target_size=(48, 48),
        output_path=f"{base_sprites}/player_core.png",
        num_colors=20,
        add_outline=True
    )
    
    generate_pixel_sprite(
        prompt="colossal orbital electromagnetic mass driver launch rail cannon facility on planet surface, side-angled view pointing diagonally up-right at 45 degrees toward space, heavy industrial steel trusses, glowing cyan accelerator rings along the barrel, reinforced concrete and metal base",
        target_size=(140, 110),
        output_path=f"{base_sprites}/mass_driver_ramp.png",
        num_colors=24,
        add_outline=True
    )
