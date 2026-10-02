# Let's inspect the Hermes v96 string table.
# In Hermes, there is:
# - string table (array of SmallStringTableEntry or StringTableEntry)
# - string storage (raw bytes)

with open(r'c:\Users\krisd\AppData\Local\Temp\assets\index.android.bundle', 'rb') as f:
    buf = f.read()

# Let's find occurrences of null-terminated strings around 800000..1800000
# Or let's inspect the layout of strings in the storage pool:
# Let's check byte values around 'bookAsExternalOrganizer'
idx = buf.find(b'bookAsExternalOrganizer')
print(f"bookAsExternalOrganizer at {idx}")
print("Bytes before and after:")
for b in buf[idx-50:idx+80]:
    if 32 <= b < 127:
        print(chr(b), end='')
    else:
        print(f'\\x{b:02x}', end='')
print()
