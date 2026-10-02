from hermes_dec.parsers.hbc_file_parser import HBCFileParser

bundle_path = r'c:\Users\krisd\AppData\Local\Temp\assets\index.android.bundle'
with open(bundle_path, 'rb') as f:
    data = f.read()

parser = HBCFileParser(data)
hbc = parser.parse()
print(f"Version: {hbc.header.version}")
print(f"Strings count: {len(hbc.string_table)}")

# Print some strings
for s in hbc.string_table[:20]:
    print(repr(s))
