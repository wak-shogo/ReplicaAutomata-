import os

for root, dirs, files in os.walk('scripts'):
    for f in files:
        if f.endswith('.gd'):
            path = os.path.join(root, f)
            with open(path, 'r', encoding='utf-8') as fp:
                for idx, line in enumerate(fp, 1):
                    # Check non-ascii in string literals or code
                    non_ascii = [c for c in line if ord(c) > 127]
                    if non_ascii:
                        stripped = line.strip()
                        # print if it looks like a UI string or label
                        print(f"{path}:{idx}: {''.join(set(non_ascii))} -> {stripped}")
