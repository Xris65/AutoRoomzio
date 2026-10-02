import struct

with open(r'c:\Users\krisd\AppData\Local\Temp\assets\index.android.bundle', 'rb') as f:
    buf = f.read()

# Header:
# 0x00: magic (8)
# 0x08: version (4)
# 0x0c: sha1 (20)
# 0x20: fileLength (4)
# 0x24: globalCodeIndex (4)
# 0x28: functionCount (4)
# 0x2c: selectorHashCount (4)
# 0x30: stringKindCount (4)
# 0x34: identifierCount (4)
# 0x38: stringCount (4)
# 0x3c: overflowStringCount (4)
# 0x40: stringStorageSize (4)
# 0x44: bigIntCount (4)
# 0x48: bigIntStorageSize (4)
# 0x4c: regExpCount (4)
# 0x50: regExpStorageSize (4)
# 0x54: cjsModuleCount (4)
# 0x58: cjsModuleOffset (4)

fields = [
    'fileLength', 'globalCodeIndex', 'functionCount', 'selectorHashCount',
    'stringKindCount', 'identifierCount', 'stringCount', 'overflowStringCount',
    'stringStorageSize', 'bigIntCount', 'bigIntStorageSize', 'regExpCount',
    'regExpStorageSize', 'cjsModuleCount', 'cjsModuleOffset'
]

for idx, name in enumerate(fields):
    val = struct.unpack('<I', buf[0x20 + idx*4 : 0x24 + idx*4])[0]
    print(f'{name}: {val} (0x{val:08x})')
