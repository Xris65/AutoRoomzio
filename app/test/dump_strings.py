import struct

with open(r'c:\Users\krisd\AppData\Local\Temp\assets\index.android.bundle', 'rb') as f:
    buf = f.read()

# In Hermes v96:
# struct Header {
#   uint64_t magic;
#   uint32_t version; (96)
#   uint8_t sha1[20];
#   uint32_t fileLength;
#   uint32_t globalCodeIndex;
#   uint32_t functionCount;
#   uint32_t selectorHashCount;
#   uint32_t stringKindCount;
#   uint32_t identifierCount;
#   uint32_t stringCount;
#   uint32_t overflowStringCount;
#   uint32_t stringStorageSize;
#   ...
# }

# Let's inspect the layout around offset 0x20..0x60
# 0x20: fileLength = 5796392
# 0x24: globalCodeIndex = 0
# 0x28: functionCount = 31956
# 0x2c: selectorHashCount = 3
# 0x30: stringKindCount = 27948
# 0x34: identifierCount = 52190
# 0x38: stringCount = 52190 (or stringCount = ...?)
# 0x3c: stringStorageSize = 1009434
# Let's check where the string storage begins:
# String table entries are 4 bytes each: (isUTF16:1, offset:31) or (offset:23, length:9)
# In v96: SmallStringTableEntry: uint32_t is (offset: 23, length: 9) or uint32_t offset, uint32_t length.

# Let's search directly in buf for known strings like "workspaceId" or "bookedTimeSlot"
ws_pos = buf.find(b'workspaceId')
print(f'workspaceId found at: {ws_pos}')
if ws_pos != -1:
    # Look at surrounding bytes in the string storage pool!
    print('Surrounding bytes (string storage pool):')
    start = max(0, ws_pos - 1000)
    end = min(len(buf), ws_pos + 4000)
    # The string storage pool contains raw concatenated strings!
    raw_strings = buf[start:end]
    print(raw_strings.decode('latin1'))
