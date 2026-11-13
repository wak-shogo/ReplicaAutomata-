with open('docs/index.html', 'r', encoding='utf-8') as f:
    html = f.read()

# 1. Viewport & mobile web app meta
old_vp = '<meta name="viewport" content="width=device-width, user-scalable=no, initial-scale=1.0">'
new_vp = '''<meta name="viewport" content="width=device-width, user-scalable=no, initial-scale=1.0, maximum-scale=1.0, minimum-scale=1.0, viewport-fit=cover">
\t\t<meta name="apple-mobile-web-app-capable" content="yes">
\t\t<meta name="mobile-web-app-capable" content="yes">'''

assert old_vp in html, "old_vp not found"
html = html.replace(old_vp, new_vp)

# 2. Touch gesture & Android Chrome pull-to-refresh CSS guard + screen wake lock
css_guard = '''<style>
			html, body, #canvas {
				touch-action: none !important;
				overscroll-behavior: none !important;
				user-select: none !important;
				-webkit-user-select: none !important;
			}
		</style>
	</head>'''
if '</head>' in html and 'overscroll-behavior: none' not in html:
    html = html.replace('</head>', css_guard)

guard_script = '''
		<script>
			// Prevent accidental double-tap zoom & pinch-to-zoom on iOS/Android
			document.addEventListener('gesturestart', function(e) { e.preventDefault(); }, { passive: false });
			document.addEventListener('gesturechange', function(e) { e.preventDefault(); }, { passive: false });
			document.addEventListener('gestureend', function(e) { e.preventDefault(); }, { passive: false });
			// Screen Wake Lock API to prevent mobile sleep while playing
			if ('wakeLock' in navigator) {
				let wakeLock = null;
				const requestWakeLock = async () => {
					try {
						wakeLock = await navigator.wakeLock.request('screen');
					} catch (err) {}
				};
				requestWakeLock();
				document.addEventListener('visibilitychange', () => {
					if (wakeLock !== null && document.visibilityState === 'visible') {
						requestWakeLock();
					}
				});
			}
		</script>
	</body>'''

assert '</body>' in html, "</body> not found"
html = html.replace('</body>', guard_script)

with open('docs/index.html', 'w', encoding='utf-8') as f:
    f.write(html)

print("docs/index.html updated with mobile guards and wake lock.")
