with open(r'c:\Users\krisd\AppData\Local\Temp\assets\index.android.bundle', 'rb') as f:
    buf = f.read()

keywords = [
    b'/bookings',
    b'/users',
    b'/floors',
    b'/buildings',
    b'booking',
    b'organizer',
    b'bookedFor',
    b'forUserId',
    b'colleague',
    b'favorite',
    b'favourite',
    b'beneficiary',
    b'delegate',
    b'delegation',
    b'onBehalf',
    b'behalf',
    b'impersonat',
    b'directory',
    b'colleagues',
]

for kw in keywords:
    pos = 0
    count = 0
    print(f"\n==================== KEYWORD: {kw.decode()} ====================")
    while True:
        idx = buf.find(kw, pos)
        if idx == -1:
            break
        count += 1
        start = max(0, idx - 100)
        end = min(len(buf), idx + 200)
        snippet = buf[start:end].decode('latin1', errors='ignore')
        print(f"[{idx}] {snippet}")
        pos = idx + len(kw)
        if count >= 8:
            print(f"... and more")
            break
