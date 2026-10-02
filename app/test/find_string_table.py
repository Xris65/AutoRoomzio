import struct

with open(r'c:\Users\krisd\AppData\Local\Temp\assets\index.android.bundle', 'rb') as f:
    buf = f.read()

# Let's search for the exact Hermes v96 header and section offsets.
# In Hermes:
# struct Header {
#   uint64_t magic; // 0x00
#   uint32_t version; // 0x08 (96)
#   uint8_t sha1[20]; // 0x0c .. 0x1f
#   uint32_t fileLength; // 0x20
#   ...
# }

# Let's check the size of the header and subsequent tables.
# Often Hermes tables appear in a fixed order right after Header:
# 1. Function headers
# 2. Small string table entries
# 3. Overflow string table entries
# 4. String storage
# 5. Array storage, etc.

# Let's inspect where string table is.
# In Hermes v96, SmallStringTableEntry is 4 bytes:
# struct SmallStringTableEntry {
#   uint32_t isUTF16 : 1;
#   uint32_t offset : 23;
#   uint32_t length : 8; // or offset:24, length:7?
# };
# Let's test combinations!

print("File size:", len(buf))
