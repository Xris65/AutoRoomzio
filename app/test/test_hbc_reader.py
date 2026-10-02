from hermes_dec.parsers.hbc_file_parser import HBCReader

bundle_path = r'c:\Users\krisd\AppData\Local\Temp\assets\index.android.bundle'
with open(bundle_path, 'rb') as f:
    reader = HBCReader(f)
    print("Version:", reader.header.version)
    print("String count:", len(reader.string_table))
    print("Sample strings:")
    for s in reader.string_table[:15]:
        print(" ", repr(s))
