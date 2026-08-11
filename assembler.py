#!/usr/bin/env python3

"""
assembler.py

Reads:
    config.csv

Writes:
    config.bin

Output layout (24 bytes)

Bytes  0-15 : PE configuration
Byte      16: Row routing
Byte      17: Column routing
Byte      18: Global constant
Bytes 19-23: LCU configuration (34 bits packed little-endian)
"""

import csv


# ------------------------------------------------------------
# Encoding tables
# ------------------------------------------------------------

SRC = {
    "N": 0,
    "S": 1,
    "E": 2,
    "W": 3,
    "R": 4,
    "C": 5,
    "X": 6,
    "F": 7,
}

OP = {
    "ADD": 0,
    "SUB": 1,
    "MUL": 2,
    "ABS": 3,
}

CMP = {
    "GT": 0,
    "LT": 1,
    "EQ": 2,
    "FALSE": 3,
}


# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------

def clean(tokens):
    return [x.strip() for x in tokens]


def parse_pe(cell):
    """
    ADD N S
    MUL W X
    ABS F
    """

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

    if opcode not in OP:
        raise ValueError(f"Unknown opcode '{opcode}'")

    if a not in SRC:
        raise ValueError(f"Unknown source '{a}'")

    if b not in SRC:
        raise ValueError(f"Unknown source '{b}'")

    value = (
        SRC[a]
        | (SRC[b] << 3)
        | (OP[opcode] << 6)
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


# ------------------------------------------------------------
# Read CSV
# ------------------------------------------------------------

with open("config.csv", newline="") as f:
    rows = [clean(r) for r in csv.reader(f)]

if len(rows) < 5:
    raise ValueError("Configuration file is too small.")


# ------------------------------------------------------------
# Determine array size
# ------------------------------------------------------------

N = len(rows) - 4

if len(rows) != N + 4:
    raise ValueError("Incorrect number of rows.")

if N & (N - 1):
    raise ValueError("CGRA size must be 2^n.")

for r in range(N):
    if len(rows[r]) != N:
        raise ValueError(
            f"Row {r} does not contain {N} PEs."
        )


# ------------------------------------------------------------
# PE bytes
# ------------------------------------------------------------

pe_bytes = bytearray()

for r in range(N):
    for c in range(N):
        pe_bytes.append(parse_pe(rows[r][c]))


# ------------------------------------------------------------
# LCU
# ------------------------------------------------------------

lcu = rows[N]

if len(lcu) != 5:
    raise ValueError("LCU row must contain five fields.")

pe_select = parse_hex(lcu[0], 4)

compare = lcu[1].upper()

if compare not in CMP:
    raise ValueError("Invalid compare mode.")

compare = CMP[compare]

compare_const = parse_hex(lcu[2], 8)

min_cycles = parse_hex(lcu[3], 4)

timeout = parse_hex(lcu[4], 16)

lcu_word = (
    pe_select
    | (compare << 4)
    | (compare_const << 6)
    | (min_cycles << 14)
    | (timeout << 18)
)


# ------------------------------------------------------------
# Row routing
# ------------------------------------------------------------

row = rows[N + 1]

if len(row) != N:
    raise ValueError("Incorrect row routing length.")

row_byte = 0

for i, value in enumerate(row):

    sel = parse_hex(value, 2)

    row_byte |= sel << (2 * i)


# ------------------------------------------------------------
# Column routing
# ------------------------------------------------------------

col = rows[N + 2]

if len(col) != N:
    raise ValueError("Incorrect column routing length.")

col_byte = 0

for i, value in enumerate(col):

    sel = parse_hex(value, 2)

    col_byte |= sel << (2 * i)


# ------------------------------------------------------------
# Global constant
# ------------------------------------------------------------

const_row = rows[N + 3]

if len(const_row) != 1:
    raise ValueError("Global constant row must contain one value.")

global_const = parse_hex(const_row[0], 8)


# ------------------------------------------------------------
# Emit binary
# ------------------------------------------------------------

out = bytearray()

out.extend(pe_bytes)
out.append(row_byte)
out.append(col_byte)
out.append(global_const)

for i in range(5):
    out.append((lcu_word >> (8 * i)) & 0xFF)

with open("config.bin", "wb") as f:
    f.write(out)

print(f"Wrote config.bin ({len(out)} bytes)")
