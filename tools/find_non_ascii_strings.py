import os
import re

string_pattern = re.compile(r'("(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\')')

found = []
for root, dirs, files in os.walk('.'):
    if any(x in root for x in ['.git', '.godot', 'docs', 'brain']):
        continue
    for f in files:
        if f.endswith('.gd') or f.endswith('.tscn'):
            path = os.path.join(root, f)
            with open(path, 'r', encoding='utf-8', errors='ignore') as fp:
                for line_idx, line in enumerate(fp, 1):
                    for match in string_pattern.finditer(line):
                        s = match.group(0)
                        non_ascii = [c for c in s if ord(c) > 127]
                        if non_ascii:
                            codepoints = [f"U+{ord(c):04X}" for c in set(non_ascii)]
                            found.append((path, line_idx, codepoints, line.strip()))

print(f"Total non-ASCII occurrences in strings across project: {len(found)}")
for path, line_idx, codepoints, line in found:
    safe_line = line.encode('ascii', errors='backslashreplace').decode('ascii')
    print(f"{path}:{line_idx} [{' '.join(codepoints)}] -> {safe_line}")
