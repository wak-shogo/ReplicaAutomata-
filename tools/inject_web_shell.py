"""Injects mobile touch guards, WakeLock & SHA-256 PCK cache-busting into exported docs/index.html."""
import hashlib
import os
import re

DOCS = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "docs")
HTML = os.path.join(DOCS, "index.html")
PCK = os.path.join(DOCS, "index.pck")


def get_pck_hash() -> str:
    if not os.path.exists(PCK):
        return "v8"
    h = hashlib.sha256()
    with open(PCK, "rb") as f:
        while True:
            chunk = f.read(65536)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest()[:10]


if __name__ == "__main__":
    ver = get_pck_hash()
    snip = f"""<meta http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate" />
<meta http-equiv="Pragma" content="no-cache" />
<meta http-equiv="Expires" content="0" />
<style>
html, body, #canvas {{ touch-action: none; overscroll-behavior: none; user-select: none; -webkit-user-select: none; }}
</style>
<script>
(function() {{
  const VER = "{ver}";
  const origFetch = window.fetch.bind(window);
  window.fetch = function(input, init) {{
    try {{
      let url = (typeof input === "string") ? input : (input && input.url ? input.url : "");
      if (url && (url.indexOf("index.pck") !== -1 || url.indexOf("index.wasm") !== -1)) {{
        const sep = url.indexOf("?") === -1 ? "?" : "&";
        const bustUrl = url + sep + "v=" + VER;
        const nextInit = Object.assign({{}}, init || {{}}, {{ cache: "no-store" }});
        return origFetch(bustUrl, nextInit);
      }}
    }} catch (e) {{}}
    return origFetch(input, init);
  }};
}})();
document.addEventListener('contextmenu', function(e) {{ e.preventDefault(); }});
document.addEventListener('gesturestart', function(e) {{ e.preventDefault(); }}, {{ passive: false }});
document.addEventListener('gesturechange', function(e) {{ e.preventDefault(); }}, {{ passive: false }});
if ('wakeLock' in navigator) {{
  window.addEventListener('pointerdown', function _w() {{
    navigator.wakeLock.request('screen').catch(function(){{}});
    window.removeEventListener('pointerdown', _w);
  }}, {{ passive: true }});
}}
</script>
"""
    with open(HTML, "r", encoding="utf-8") as f:
        s = f.read()
    if "wakeLock" not in s:
        s = s.replace("</head>", snip + "</head>")
    s = re.sub(r'src="index\.js(?:\?[^"]*)?"', f'src="index.js?v={ver}"', s)
    s = re.sub(r'src="coi-serviceworker\.js(?:\?[^"]*)?"', f'src="coi-serviceworker.js?v={ver}"', s)
    with open(HTML, "w", encoding="utf-8") as f:
        f.write(s)
    print(f"docs/index.html mobile guards & PCK cache-buster (v={ver}) injected.")
