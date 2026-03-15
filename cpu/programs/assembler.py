import sys
import re

# =========================
# ISA CONSTANTS
# =========================

ALU_OPS = {
    "ADD":  0b0000,
    "SUB":  0b0001,
    "SLT":  0b0010,
    "SLTU": 0b0011,
    "AND":  0b0100,
    "OR":   0b0101,
    "XNOR": 0b0110,
    "SLL":  0b0111,
    "SRL":  0b1000,
    "EQ":   0b1001
}

COND = {
    "BEQ": 0b00,
    "BNE": 0b01,
    "J":   0b10
}

def regnum(r):
    if not r.lower().startswith("r"):
        raise Exception(f"Invalid register {r}")
    n = int(r[1:])
    if n < 0 or n > 7:
        raise Exception("Register must be r0–r7")
    return n

def imm(x):
    if x.startswith("0x"):
        return int(x, 16)
    return int(x)

def sign_extend(val, bits):
    mask = (1 << bits) - 1
    return val & mask

# =========================
# ENCODERS
# =========================

def encode_nop():
    return (1<<29)

def encode_rtype(op, rd, rs1, rs2):
    word = 0
    word |= (0b00 << 30)
    word |= (rs1 << 25)
    word |= (rs2 << 21)
    word |= (rd  << 17)
    word |= (ALU_OPS[op] << 13)
    return word

def encode_addi(rd, rs1, immediate):
    word = 0
    word |= (0b00 << 30)
    word |= (rs1 << 25)
    word |= (0 << 21)
    word |= (rd << 17)
    word |= (ALU_OPS["ADD"] << 13)
    word |= (1 << 12)
    word |= sign_extend(immediate, 12)
    return word

def encode_lw(rd, rs1, offset):
    word = 0
    word |= (0b01 << 30)
    word |= (rs1 << 25)
    word |= (rd << 21)
    word |= sign_extend(offset, 21)
    return word

def encode_sw(rs2, rs1, offset):
    word = 0
    word |= (0b10 << 30)
    word |= (rs1 << 25)
    word |= (rs2 << 21)
    word |= sign_extend(offset, 21)
    return word

def encode_branch(cond, rs1, rs2, offset):
    word = 0
    word |= (0b11 << 30)
    word |= (rs1 << 25)
    word |= (rs2 << 21)
    word |= (COND[cond] << 19)
    word |= sign_extend(offset, 19)
    return word

def encode_jump(offset):
    word = 0
    word |= (0b11 << 30)
    word |= (COND["J"] << 19)
    word |= sign_extend(offset, 19)
    return word

# =========================
# ASSEMBLER
# =========================

def assemble(lines):
    labels = {}
    pc = 0

    # First pass
    for line in lines:
        line = line.split("#")[0].strip()
        if not line:
            continue
        if line.endswith(":"):
            labels[line[:-1]] = pc
        else:
            pc += 4

    # Second pass
    pc = 0
    machine = []

    for line in lines:
        raw = line
        line = line.split("#")[0].strip()
        if not line or line.endswith(":"):
            continue

        parts = re.split(r'[,\s()]+', line)
        parts = [p for p in parts if p]

        op = parts[0].upper()

        if op == "NOP":
            word = encode_nop()
        elif op in ALU_OPS:
            rd = regnum(parts[1])
            rs1 = regnum(parts[2])
            rs2 = regnum(parts[3])
            word = encode_rtype(op, rd, rs1, rs2)

        elif op == "ADDI":
            rd = regnum(parts[1])
            rs1 = regnum(parts[2])
            immediate = imm(parts[3])
            word = encode_addi(rd, rs1, immediate)

        elif op == "LW":
            rd = regnum(parts[1])
            offset = imm(parts[2])
            rs1 = regnum(parts[3])
            word = encode_lw(rd, rs1, offset)

        elif op == "SW":
            rs2 = regnum(parts[1])
            offset = imm(parts[2])
            rs1 = regnum(parts[3])
            word = encode_sw(rs2, rs1, offset)

        elif op in ["BEQ", "BNE"]:
            rs1 = regnum(parts[1])
            rs2 = regnum(parts[2])
            target = parts[3]
            offset = (labels[target] - pc) // 4
            word = encode_branch(op, rs1, rs2, offset)

        elif op == "J":
            target = parts[1]
            offset = (labels[target] - pc - 4) // 4
            word = encode_jump(offset)

        else:
            raise Exception(f"Unknown instruction: {raw}")

        machine.append(word)
        pc += 4

    return machine

if __name__ == "__main__":
    with open(sys.argv[1]) as f:
        lines = f.readlines()

    machine = assemble(lines)

    for word in machine:
        print(f"{word:08X},")