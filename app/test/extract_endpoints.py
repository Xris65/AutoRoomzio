with open(r'c:\Users\krisd\AppData\Local\Temp\assets\index.android.bundle', 'r', encoding='utf-8', errors='ignore') as f:
    text = f.read()

import re

# Find occurrences of api.my.roomz or roomz.io
for m in re.finditer(r'roomz\.io', text):
    start = max(0, m.start() - 200)
    end = min(len(text), m.end() + 200)
    print('--- MATCH ---')
    print(text[start:end])
