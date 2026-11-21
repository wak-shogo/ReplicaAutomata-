"""Injects mobile touch-action guards, safe viewport lock, and WakeLock into docs/index.html."""
import os

HTML_PATH = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "docs", "index.html")

GUARD_SNIPPET = """<style>
html, body, #canvas {
  touch-action: none;
  overscroll-behavior: none;
  user-select: none;
  -webkit-user-select: none;
  -webkit-touch-callout: none;
}
</style>
<script>
document.addEventListener('contextmenu', function(e) { e.preventDefault(); });
if ('wakeLock' in navigator) {
  window.addEventListener('pointerdown', function _wl() {
    navigator.wakeLock.request('screen').catch(function(){});
    window.removeEventListener('pointerdown', _wl);
  }, { passive: true });
}
</script>
"""

if __name__ == "__main__":
    with open(HTML_PATH, "r", encoding="utf-8") as f:
        html = f.read()
    if "wakeLock" not in html:
        html = html.replace("</head>", GUARD_SNIPPET + "</head>")
        with open(HTML_PATH, "w", encoding="utf-8") as f:
            f.write(html)
    print("docs/index.html updated with mobile touch guards and wakeLock.")
