with open(r'c:\Users\krisd\AppData\Local\Temp\assets\index.android.bundle', 'rb') as f:
    buf = f.read()

terms = [
    b'bookAsExternalOrganizer',
    b'ExternalOrganizer',
    b'organizer.id',
    b'organizer',
    b'favorite-users',
    b'favoriteUsers',
    b'colleague',
    b'delegat',
]

for t in terms:
    pos = 0
    print(f"\n==================== TERM: {t.decode()} ====================")
    while True:
        idx = buf.find(t, pos)
        if idx == -1:
            break
        start = max(0, idx - 200)
        end = min(len(buf), idx + 300)
        snippet = buf[start:end].decode('latin1', errors='ignore')
        print(f"[{idx}] {snippet}\n")
        pos = idx + len(t)
        if pos >= len(buf): break
