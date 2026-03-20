import sys
import re

OPCODES = {
    'NOP':   '0000',
    'BR':    '0001', # BRnzp
    'CMP':   '0010',
    'ADD':   '0011',
    'SUB':   '0100',
    'MUL':   '0101',
    'DIV':   '0110',
    'LDR':   '0111',
    'STR':   '1000',
    'CONST': '1001',
    'RET':   '1111',
}

REGISTERS = {
    'R0': '0000', 'R1': '0001', 'R2': '0010', 'R3': '0011',
    'R4': '0100', 'R5': '0101', 'R6': '0110', 'R7': '0111',
    'R8': '1000', 'R9': '1001', 'R10':'1010', 'R11':'1011',
    '%gridDim': '1100',
    '%blockIdx': '1101',
    '%blockDim': '1110',
    '%threadIdx':'1111',
}

def parse_register(r_str):
    r_str = r_str.strip().upper()
    if r_str in REGISTERS:
        return REGISTERS[r_str]
    # Handle lowercase special registers
    r_str_orig = r_str.replace('%', '%').lower()
    for k in REGISTERS.keys():
        if k.lower() == r_str_orig:
            return REGISTERS[k]
    raise ValueError(f"Unknown register: {r_str}")

def parse_imm(imm_str):
    imm_str = imm_str.strip().replace('#', '')
    if imm_str.startswith('0x'):
        val = int(imm_str, 16)
    else:
        val = int(imm_str)
    if val < -128 or val > 255:
        raise ValueError(f"Immediate {val} out of 8-bit bounds")
    if val < 0:
        val = (1 << 8) + val
    return f"{val:08b}"

def parse_branch_cond(cond_str):
    cond_str = cond_str.lower()
    n = '1' if 'n' in cond_str else '0'
    z = '1' if 'z' in cond_str else '0'
    p = '1' if 'p' in cond_str else '0'
    return f"{n}{z}{p}0" # 4 bits: NZP + 1 padding bit

def assemble_instruction(line):
    # Strip comments
    line = line.split(';')[0].strip()
    if not line:
        return None
    
    parts = line.replace(',', ' ').split()
    mnemonic = parts[0].upper()

    if mnemonic == 'NOP':
        return '0000000000000000'
    
    if mnemonic == 'RET':
        return '1111000000000000'
        
    if mnemonic.startswith('BR'):
        cond = mnemonic[2:]
        if not cond: cond = 'nzp' # default to unconditional
        nzp = parse_branch_cond(cond)
        imm = parse_imm(parts[1])
        return f"{OPCODES['BR']}{nzp}{imm}"
        
    if mnemonic == 'CMP':
        rs = parse_register(parts[1])
        rt = parse_register(parts[2])
        return f"{OPCODES['CMP']}0000{rs}{rt}"
        
    if mnemonic in ['ADD', 'SUB', 'MUL', 'DIV']:
        rd = parse_register(parts[1])
        rs = parse_register(parts[2])
        rt = parse_register(parts[3])
        return f"{OPCODES[mnemonic]}{rd}{rs}{rt}"
        
    if mnemonic == 'LDR':
        rd = parse_register(parts[1])
        rs = parse_register(parts[2])
        return f"{OPCODES['LDR']}{rd}{rs}0000"
        
    if mnemonic == 'STR':
        rs = parse_register(parts[1])
        rt = parse_register(parts[2])
        return f"{OPCODES['STR']}0000{rs}{rt}"
        
    if mnemonic == 'CONST':
        rd = parse_register(parts[1])
        imm = parse_imm(parts[2])
        return f"{OPCODES['CONST']}{rd}{imm}"

    raise ValueError(f"Unknown instruction: {mnemonic}")

def main():
    if len(sys.argv) < 3:
        print("Usage: python assembler.py <input.asm> <out_prefix>")
        sys.exit(1)
        
    in_file = sys.argv[1]
    out_prefix = sys.argv[2]
    
    program_hex = []
    data_hex = []
    
    with open(in_file, 'r') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith(';'):
                continue
                
            # Directives
            if line.startswith('.threads'):
                pass # Handled by Makefile/Runner for now
            elif line.startswith('.data'):
                # .data 0 1 2 3
                parts = line.split(';')[0].split()
                for p in parts[1:]:
                    val = int(p)
                    data_hex.append(f"{val:02x}")
            else:
                bin_str = assemble_instruction(line)
                if bin_str:
                    hex_str = f"{int(bin_str, 2):04x}"
                    program_hex.append(hex_str)
                    
    with open(f"{out_prefix}_program.hex", 'w') as f:
        for h in program_hex:
            f.write(h + '\n')
            
    with open(f"{out_prefix}_data.hex", 'w') as f:
        for h in data_hex:
            f.write(h + '\n')
            
    print(f"Assembled {len(program_hex)} instructions and {len(data_hex)} data elements.")

if __name__ == "__main__":
    main()
