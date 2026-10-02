from hermes_dec.parsers.hbc_file_parser import HBCReader

bundle_path = r'c:\Users\krisd\AppData\Local\Temp\assets\index.android.bundle'
with open(bundle_path, 'rb') as f:
    hbc = HBCReader()
    hbc.read_whole_file(f)

print(f"Bytecode version: {hbc.header.version}")
print(f"Total strings: {len(hbc.strings)}")

# Search for strings containing endpoints or keywords
keywords = [
    'booking', 'forUser', 'bookFor', 'colleague', 'delegate', 'beneficiary',
    'organizer', 'external', 'directory', 'favorite', 'user', 'tenant', 'organization'
]

results = {}
for idx, s in enumerate(hbc.strings):
    # s is bytes or str
    if isinstance(s, bytes):
        s_str = s.decode('utf-8', errors='ignore')
    else:
        s_str = str(s)
    for kw in keywords:
        if kw.lower() in s_str.lower():
            if kw not in results:
                results[kw] = []
            results[kw].append((idx, s_str))

for kw, matches in results.items():
    print(f"\n=== KEYWORD: {kw} (total matches: {len(matches)}) ===")
    for idx, s_str in matches[:25]:
        print(f"  [{idx}] {repr(s_str)}")
