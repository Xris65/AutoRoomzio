import io
import sys
from hermes_dec.parsers.hbc_file_parser import HBCReader, parse_hbc_bytecode

bundle_path = r'c:\Users\krisd\AppData\Local\Temp\assets\index.android.bundle'
with open(bundle_path, 'rb') as f:
    data = f.read()

bio = io.BytesIO(data)
hbc = HBCReader()
hbc.read_whole_file(bio)

print(f"Loaded HBC bytecode: {len(hbc.function_headers)} functions, {len(hbc.strings)} strings")

targets = [
    'bookings/bookWorkspace',
    'bookWorkspace',
    'bookAsExternalOrganizer',
    'ExternalBooking',
    'externalBookingTabName',
    'search_colleagues',
    'users/getFavorites',
    'getFavoriteUsers',
    'createFavoriteUser',
    'deleteFavoriteUser',
    'favorite-users',
    'getOtherUserBookings',
    '/bookings',
    '/users',
]

target_sids = {}
for idx, s in enumerate(hbc.strings):
    s_str = s.decode('utf-8', errors='replace') if isinstance(s, bytes) else str(s)
    for t in targets:
        if s_str == t:
            target_sids[t] = idx

print("Matched targets to string IDs:", target_sids)

# Map string ID to string for quick lookup
def get_str(sid):
    if 0 <= sid < len(hbc.strings):
        s = hbc.strings[sid]
        return s.decode('utf-8', errors='replace') if isinstance(s, bytes) else str(s)
    return f"<sid:{sid}>"

# Find functions that reference any of target_sids
matching_funcs = {t: [] for t in target_sids}

for func_idx, func_hdr in enumerate(hbc.function_headers):
    try:
        instrs = list(parse_hbc_bytecode(func_hdr, hbc))
    except Exception:
        continue

    func_sids = set()
    for ins in instrs:
        # Check all arg fields
        for k, v in vars(ins).items():
            if k.startswith('arg') and isinstance(v, int):
                func_sids.add(v)
    
    for t, sid in target_sids.items():
        if sid in func_sids:
            matching_funcs[t].append((func_idx, func_hdr, instrs))

for t, flist in matching_funcs.items():
    print(f"\n================ Target: {t} (Matches: {len(flist)}) ================")
    for f_idx, f_hdr, instrs in flist[:5]:
        fname = get_str(f_hdr.functionName)
        print(f"Function #{f_idx} '{fname}' ({len(instrs)} instructions):")
        # Print instructions that use strings
        for ins in instrs:
            str_args = []
            for k, v in vars(ins).items():
                if k.startswith('arg') and isinstance(v, int) and 0 <= v < len(hbc.strings):
                    # Check if operand definition says it's a string
                    s_val = get_str(v)
                    # if length is reasonable and printable
                    if len(s_val) > 0 and len(s_val) < 60:
                        str_args.append(f"{k}={repr(s_val)}")
            if str_args:
                print(f"    {ins.inst.name:20s} {' '.join(str_args)}")
