with open(r'c:\Users\krisd\AppData\Local\Temp\assets\index.android.bundle', 'rb') as f:
    buf = f.read()

idx = buf.find(b'favorite-users')
if idx != -1:
    print('Found favorite-users at', idx)
    print(buf[max(0, idx-500):min(len(buf), idx+500)].decode('latin1', errors='ignore'))
