import io
import sys
from hermes_dec.parsers.hbc_file_parser import HBCReader

# Set stdout encoding
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')

bundle_path = r'c:\Users\krisd\AppData\Local\Temp\assets\index.android.bundle'
with open(bundle_path, 'rb') as f:
    hbc = HBCReader()
    hbc.read_whole_file(f)

keywords = [
    'bookworkspace', 'externalorganizer', 'getotheruserbookings', 'createfavoriteuser',
    'deletefavoriteuser', 'getfavorites', 'externalbooking', 'favorite-users',
    'search_colleagues', 'favoriteusers', 'colleagues'
]

with open('bundle_matches.txt', 'w', encoding='utf-8') as out:
    for idx, s in enumerate(hbc.strings):
        s_str = s.decode('utf-8', errors='replace') if isinstance(s, bytes) else str(s)
        for kw in keywords:
            if kw in s_str.lower():
                out.write(f"[{kw}] #{idx}: {repr(s_str)}\n")

print("Dumped matches to bundle_matches.txt")
