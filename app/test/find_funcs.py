import sys
from hermes_dec.parsers.hbc_file_parser import HBCReader, parse_hbc_bytecode

bundle_path = r'c:\Users\krisd\AppData\Local\Temp\assets\index.android.bundle'
with open(bundle_path, 'rb') as f:
    hbc = HBCReader()
    hbc.read_whole_file(f)

target_strings = {
    'bookings/bookWorkspace': None,
    'bookAsExternalOrganizer': None,
    'getBookWorkspaceData': None,
    'bookWorkspace': None,
    'users/getFavorites': None,
    'users/createFavoriteUser': None,
    'users/deleteFavoriteUser': None,
    'search_colleagues': None,
    'ColleaguesScreen': None,
    'bookings/getOtherUserBookings': None,
}

for idx, s in enumerate(hbc.strings):
    s_str = s.decode('utf-8', errors='replace') if isinstance(s, bytes) else str(s)
    if s_str in target_strings:
        target_strings[s_str] = idx

print("Target string IDs:", target_strings)

# Search functions that reference these string IDs
# In HBC, instructions like LoadConstString, GetById, TryGetById, PutById reference string_id
found_funcs = {k: [] for k in target_strings}

for func_idx, func_hdr in enumerate(hbc.function_headers):
    # parse bytecode for function
    try:
        instrs = list(parse_hbc_bytecode(func_hdr, hbc))
    except Exception:
        continue
    for instr in instrs:
        # Check operands
        for op in instr.operands:
            for k, sid in target_strings.items():
                if sid is not None and op == sid:
                    func_name = hbc.strings[func_hdr.functionName] if func_hdr.functionName < len(hbc.strings) else '<anon>'
                    if isinstance(func_name, bytes):
                        func_name = func_name.decode('utf-8', errors='replace')
                    found_funcs[k].append((func_idx, func_name, len(instrs)))

for k, funcs in found_funcs.items():
    print(f"\nTarget: {k} (String ID: {target_strings[k]})")
    for f_idx, f_name, f_len in funcs[:10]:
        print(f"  Function #{f_idx} '{f_name}' ({f_len} instrs)")
