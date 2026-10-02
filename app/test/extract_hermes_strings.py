import struct

with open(r'c:\Users\krisd\AppData\Local\Temp\assets\index.android.bundle', 'rb') as f:
    data = f.read()

# Hermes header:
# magic: 8 bytes (c6 1f bc 03 ...)
# version: uint32
# string count: uint32
magic = data[:8]
version = struct.unpack('<I', data[4:8])[0]
print(f'Magic: {magic.hex()}, version: {version}')

# Find ASCII / UTF-8 strings of length >= 4
import re
strings = set()
for s in re.findall(b'[/a-zA-Z0-9_\\-\\?\\&\\=\\.:]{4,}', data):
    try:
        strings.add(s.decode('utf-8'))
    except:
        pass

print(f'Extracted {len(strings)} strings')

# Filter for API paths
api_strings = [s for s in strings if s.startswith('/') and len(s) > 3]
print('\n--- Potential API paths ---')
for s in sorted(api_strings):
    if any(k in s.lower() for k in ['booking', 'user', 'floor', 'workspace', 'building', 'favorite', 'directory', 'search', 'colleague', 'tenant', 'org']):
        print(s)
