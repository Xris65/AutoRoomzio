with open(r'c:\Users\krisd\AppData\Local\Temp\assets\index.android.bundle', 'rb') as f:
    buf = f.read()

terms = [
    b'search_colleagues',
    b'favorite-users',
    b'favoriteUsers',
    b'deleteItemAsync',
    b'reserved_hot_desk',
    b'Search colleagues',
]

for t in terms:
    pos = 0
    print(f"\n==================== TERM: {t.decode()} ====================")
    while True:
        idx = buf.find(t, pos)
        if idx == -1:
            break
        start = max(0, idx - 400)
        end = min(len(buf), idx + 600)
        snippet = buf[start:end].decode('latin1', errors='ignore')
        print(f"[{idx}] {snippet}\n")
        pos = idx + len(t)
        if pos >= len(buf): break
