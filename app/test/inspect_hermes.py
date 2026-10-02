import struct

with open(r'c:\Users\krisd\AppData\Local\Temp\assets\index.android.bundle', 'rb') as f:
    buf = f.read()

# Header:
# 8 bytes: magic
# uint32: version
# uint32: pageCount (or flags)
# uint32: globalCodeIndex
# uint32: functionCount
# uint32: stringKindCount
# uint32: identifierCount
# uint32: stringCount
# uint32: overflowStringCount
# uint32: stringStorageSize

# Let's inspect integers in the first 128 bytes
ints = struct.unpack('<32I', buf[:128])
for i, val in enumerate(ints):
    print(f'{i*4:02x}: {val} (0x{val:08x})')
