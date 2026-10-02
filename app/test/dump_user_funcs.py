import sys, io
sys.stdout.reconfigure(encoding='utf-8', errors='replace')
from hermes_dec.parsers.hbc_file_parser import HBCReader, parse_hbc_bytecode
from hermes_dec.parsers.hbc_opcodes.def_classes import OperandMeaning

bundle_path = r'c:\Users\krisd\AppData\Local\Temp\assets\index.android.bundle'
bio = io.BytesIO(open(bundle_path, 'rb').read())
hbc = HBCReader()
hbc.read_whole_file(bio)

def get_str(sid):
    if 0 <= sid < len(hbc.strings):
        s = hbc.strings[sid]
        return s.decode('utf-8', errors='replace') if isinstance(s, bytes) else str(s)
    return f'<sid:{sid}>'

target_funcs = [15116, 17152, 31315, 29261]

for f_idx in target_funcs:
    f_hdr = hbc.function_headers[f_idx]
    fname = get_str(f_hdr.functionName)
    instrs = list(parse_hbc_bytecode(f_hdr, hbc))
    print(f"\n==================== FUNCTION #{f_idx} '{fname}' ({len(instrs)} instrs) ====================")
    for ins_idx, ins in enumerate(instrs):
        ops_repr = []
        for op_idx, op_def in enumerate(ins.inst.operands):
            val = getattr(ins, f'arg{op_idx+1}')
            if op_def.operand_meaning == OperandMeaning.string_id:
                ops_repr.append(f"{repr(get_str(val))}")
            elif op_def.operand_meaning == OperandMeaning.function_id:
                fsub_name = get_str(hbc.function_headers[val].functionName) if val < len(hbc.function_headers) else ''
                ops_repr.append(f"func#{val}({fsub_name})")
            else:
                ops_repr.append(str(val))
        print(f"[{ins_idx:3d}] {ins.inst.name:22s} {', '.join(ops_repr)}")
