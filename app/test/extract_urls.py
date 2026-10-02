with open(r'c:\Users\krisd\AppData\Local\Temp\assets\index.android.bundle', 'rb') as f:
    buf = f.read()

import re

# Search for all strings matching /...
urls = set()
for match in re.finditer(b'/([a-zA-Z0-9_-]+(?:/[a-zA-Z0-9_{}-]+)+)', buf):
    s = match.group(0).decode('latin1', errors='ignore')
    if any(k in s for k in ['booking', 'user', 'floor', 'building', 'workspace', 'favorite', 'tenant', 'org']):
        urls.add(s)

for u in sorted(urls):
    print(u)
