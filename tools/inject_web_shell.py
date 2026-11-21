"""Injects mobile touch guards & WakeLock into exported docs/index.html."""
import os

HTML = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "docs", "index.html")
SNIP = """<style>
html, body, #canvas { touch-action: none; overscroll-behavior: none; user-select: none; -webkit-user-select: none; }
</style>
<script>
document.addEventListener('contextmenu', function(e) { e.preventDefault(); });
if ('wakeLock' in navigator) {
  window.addEventListener('pointerdown', function _w() {
    navigator.wakeLock.request('screen').catch(function(){});
    window.removeEventListener('pointerdown', _w);
  }, { passive: true });
}
</script>
"""
if __name__ == "__main__":
    with open(HTML, "r", encoding="utf-8") as f:
        s = f.read()
    if "wakeLock" not in s:
        s = s.replace("</head>", SNIP + "</head>")
        with open(HTML, "w", encoding="utf-8") as f:
            f.write(s)
    print("docs/index.html mobile guards injected.")
