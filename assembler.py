#!/usr/bin/env python3

"""
Assemble a CGRA config CSV into a 33-byte binary (little-endian).

    python assembler.py [config.csv] [out.bin]     (defaults: config.csv, config.bin)

See README.md for the CSV format and binary layout.

Bytes  0-17: 16 PE words x 9 bits, row-major
Byte     18: row bus selects
Byte     19: column bus selects
Bytes 20-27: four row constants, Q3.13
Bytes 28-32: 38-bit LCU word; byte 32 bits 7:6 hold the mode bits

The mode bits (cmp_min, branch_mode) are array-wide and inferred from the
opcodes used. PASS and MAX/MIN with identical operands work in either mode.
"""

import csv
import sys


SOURCE_CODES = {
    "N": 0,
    "S": 1,
    "E": 2,
    "W": 3,
    "R": 4,
    "C": 5,
    "X": 6,
    "F": 7,
}

# mnemonic -> (opcode, mode bit it requires, required value)
CMP_OPCODE = 5
OPCODE_INFO = {
    "ADD":   (0, None,           None),
    "SUB":   (1, None,           None),
    "MUL":   (2, None,           None),
    "MAC":   (3, None,           None),   # Const - a*b
    "CARRY": (4, None,           None),   # loop carry: seeds once, then locks
    "MAX":   (5, "cmp_min",      0),
    "MIN":   (5, "cmp_min",      1),
    "PASS":  (5, None,           None),   # MAX a a: identity in either mode
    "GATE":  (6, "branch_mode",  0),      # emit b iff a >= 0
    "NGATE": (7, "branch_mode",  0),      # emit b iff a <  0
    "SEL":   (6, "branch_mode",  1),      # North >= 0 ? a : b
    "CSIGN": (7, "branch_mode",  1),      # a < 0 ? -b : b
}

# Array-wide mode bits, set by the first opcode that needs them.
mode_bit = {"cmp_min": None, "branch_mode": None}
mode_why = {"cmp_min": None, "branch_mode": None}


def require_mode(field, value, cell):
    if mode_bit[field] is None:
        mode_bit[field] = value
        mode_why[field] = cell
        return

    if mode_bit[field] != value:
        raise ValueError(
            f"'{cell}' needs {field}={value} but '{mode_why[field]}' "
            f"already needs {field}={mode_bit[field]}. "
            f"{field} is array-wide, so one kernel cannot use both."
        )

# Bits per PE configuration word: a_source_sel(3) + b_source_sel(3) + opcode(3)
PE_BITS = 9

COMPARE_CODES = {
    "GT": 0,
    "LT": 1,
    "EQ": 2,
    "ABSLT": 3,
}


def clean(tokens):
    return [x.strip() for x in tokens]


def parse_pe(cell):
    """'OP A [B]' -> 9-bit PE word. A unary cell uses A for both operands."""

    parts = cell.split()

    if len(parts) == 2:
        opcode, a = parts
        b = a

    elif len(parts) == 3:
        opcode, a, b = parts

    else:
        raise ValueError(f"Invalid PE description: '{cell}'")

    opcode = opcode.upper()
    a = a.upper()
    b = b.upper()

    if opcode not in OPCODE_INFO:
        raise ValueError(f"Unknown opcode '{opcode}'")

    if a not in SOURCE_CODES:
        raise ValueError(f"Unknown source '{a}'")

    if b not in SOURCE_CODES:
        raise ValueError(f"Unknown source '{b}'")

    code, field, want = OPCODE_INFO[opcode]

    # CMP a a is the same in either mode, so it doesn't fix cmp_min.
    if field is not None and not (code == CMP_OPCODE and a == b):
        require_mode(field, want, cell.strip())

    value = (
        SOURCE_CODES[a]
        | (SOURCE_CODES[b] << 3)
        | (code << 6)
    )

    return value


def parse_hex(value, bits):
    value = value.strip()

    maximum = (1 << bits) - 1

    number = int(value, 16)

    if number > maximum:
        raise ValueError(
            f"{value} does not fit in {bits} bits"
        )

    return number


config_path = sys.argv[1] if len(sys.argv) > 1 else "config.csv"
out_path = sys.argv[2] if len(sys.argv) > 2 else "config.bin"

with open(config_path, newline="") as f:
    rows = [clean(r) for r in csv.reader(f)]

# Drop blank lines and '#' comments.
rows = [r for r in rows if r and r[0] and not r[0].startswith("#")]

if len(rows) < 5:
    raise ValueError("Configuration file is too small.")


array_size = len(rows) - 4

if len(rows) != array_size + 4:
    raise ValueError("Incorrect number of rows.")

if array_size & (array_size - 1):
    raise ValueError("CGRA size must be 2^n.")

for row in range(array_size):
    if len(rows[row]) != array_size:
        raise ValueError(
            f"Row {row} does not contain {array_size} PEs."
        )


pe_word = 0
pe_index = 0

for row in range(array_size):
    for col in range(array_size):
        pe_word |= parse_pe(rows[row][col]) << (PE_BITS * pe_index)
        pe_index += 1

pe_bit_count = PE_BITS * pe_index
pe_byte_count = (pe_bit_count + 7) // 8

pe_bytes = bytearray(
    (pe_word >> (8 * i)) & 0xFF for i in range(pe_byte_count)
)


lcu = rows[array_size]

if len(lcu) != 5:
    raise ValueError("LCU row must contain five fields.")

pe_select = parse_hex(lcu[0], 4)

compare = lcu[1].upper()

if compare not in COMPARE_CODES:
    raise ValueError("Invalid compare mode.")

compare = COMPARE_CODES[compare]

compare_const = parse_hex(lcu[2], 16)

min_cycles = parse_hex(lcu[3], 6)

timeout = parse_hex(lcu[4], 10)

lcu_word = (
    pe_select
    | (compare << 4)
    | (compare_const << 6)
    | (min_cycles << 22)
    | (timeout << 28)
)


row = rows[array_size + 1]

if len(row) != array_size:
    raise ValueError("Incorrect row routing length.")

row_byte = 0

for i, value in enumerate(row):

    sel = parse_hex(value, 2)

    row_byte |= sel << (2 * i)


col = rows[array_size + 2]

if len(col) != array_size:
    raise ValueError("Incorrect column routing length.")

col_byte = 0

for i, value in enumerate(col):

    sel = parse_hex(value, 2)

    col_byte |= sel << (2 * i)


const_row = rows[array_size + 3]

if len(const_row) == 1:
    const_row = const_row * 4

if len(const_row) != 4:
    raise ValueError("Constant row must hold one value, or four (one per row).")

global_const = [parse_hex(v, 16) for v in const_row]


out = bytearray()

out.extend(pe_bytes)
out.append(row_byte)
out.append(col_byte)
for gc in global_const:
    out.append(gc & 0xFF)
    out.append((gc >> 8) & 0xFF)

mode_word = (
    (mode_bit["cmp_min"] or 0)
    | ((mode_bit["branch_mode"] or 0) << 1)
)

# Mode bits use the two spare top bits of the 38-bit LCU word's fifth byte.
lcu_word |= mode_word << 38

for i in range(5):
    out.append((lcu_word >> (8 * i)) & 0xFF)

with open(out_path, "wb") as f:
    f.write(out)

print(f"Wrote {out_path} ({len(out)} bytes)")
print(f"  cmp_min={mode_bit['cmp_min'] or 0}  branch_mode={mode_bit['branch_mode'] or 0}")
