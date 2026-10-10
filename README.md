<!-- Written by Claude. -->
# Dynamic-Iteration CGRA

A coarse-grained reconfigurable array (CGRA) for iterative fixed-point kernels, such as Newton–Raphson reciprocal and square root. Processing elements (PEs) fire dataflow-style when their operands arrive. A loop control unit (LCU) ends the run when a watched value converges or a timeout expires.

The hardware is currently fixed at **4 × 4**. The config format is intended to grow to 2ⁿ × 2ⁿ later (see [Array size](#array-size)).

## Files

| File | Purpose |
| --- | --- |
| `cgra_pkg.sv` | Shared enums: operand sources, opcodes, branch mode, LCU compare modes |
| `pe.sv` | One processing element: operand muxes, token logic, ALU |
| `lcu.sv` | Loop control unit: convergence test and cycle counter |
| `top.sv` | Config registers, input buffer, interconnect, PE array, LCU |
| `tb.sv` | Testbench: loads `config.bin`, runs one kernel, prints the PE grid every cycle |
| `assembler.py` | Converts a config CSV into `config.bin` |
| `cgra.cmd`, `scripts/cgra.py` | Simulate a config, or build and program it on the Basys 3 |
| `scripts/place.py` | Place-and-route search: finds a grid layout for a kernel's cell list, or shows none exists |
| `fpga/` | Basys 3 wrapper, constraints and Vivado build scripts |
| `configs/*.csv` | Example kernels: `reciprocal_linear`, `reciprocal_const_x4`, `rsqrt`, `median3` |
| `configs/TEST_VECTORS.md` | Test inputs and expected outputs for each kernel |

## Flow

`cgra.cmd` wraps the whole flow (it runs `scripts/cgra.py` and needs Vivado for xsim and the board build):

```
cgra sim  configs\rsqrt.csv                      # assemble + simulate in xsim
cgra sim  configs\rsqrt.csv --inputs 2CF3 2000 0 110A --trace     # inputs as hex
cgra sim  configs\rsqrt.csv --dec 1.405 1.0 0 0.532               # or as decimals
cgra fpga configs\rsqrt.csv                      # assemble + build + program the Basys 3
cgra fpga configs\rsqrt.csv --no-program         # build only
cgra program configs\rsqrt.csv                   # reprogram a bitstream built earlier
```

Each config sets its own defaults in `#@` lines, which the flags override:

```
#@ inputs 2CF3 1000 0000 110A     input[0] .. input[3], hex
#@ board  sw=1 led=0              switches drive input[sw], LEDs show output[led]
```

Inputs are optional and are given as all four values, either as raw Q3.13 hex (`--inputs`) or as decimals in [-4, 4) (`--dec`, rounded to the nearest LSB). `fpga` takes the same two flags.

`sim` prints the four outputs in decimal and hex, and whether the LCU converged or timed out; `--trace` adds the PE grid for every cycle. Work files and `wave.vcd` go to `sim/build/`.

Vivado is found from `CGRA_VIVADO` (e.g. `C:\Xilinx\2025.1\Vivado`), the default install folders, or `PATH`. Python comes from `PATH`, or else from the copy bundled with Vivado.

By hand: `python assembler.py in.csv [out.bin]` writes the binary, and `tb.sv` reads `config.bin` from the current directory and takes inputs as `+input0=<hex>` … `+input3=<hex>` (it also runs under Verilator).

### Basys 3

`cgra fpga` builds with Vivado's non-project batch flow (`fpga/build.tcl`, `fpga/program.tcl`) into `fpga/build/<config>.bit`. The config is baked into the bitstream; the array runs at 50 MHz. The build stops before programming if timing fails.

The array reruns back to back, so results follow the switches live. The switches drive one input and the LEDs show one output, both raw Q3.13; by default these are D and 1/D for `reciprocal_linear`. The 7-segment display shows the cycle count of the last run in hex, with all four dots lit when the run timed out. The mapping comes from the config's `#@ board` and `#@ inputs` lines (`--sw`, `--led`, `--inputs`).

Because the config is a build-time constant, Vivado specializes the array for that one kernel. The resulting bitstream is not reconfigurable, and its utilization and timing are not representative of the full array.

## Architecture

**Numbers** are 16-bit signed Q3.13: `0x2000` is 1.0 and the range is [-4, 4). ADD, SUB and MAC saturate. MUL keeps the low 16 bits of `(a*b) >>> 13` and wraps on overflow.

**Interconnect.** Each PE reads its four neighbours. The array wraps around (torus), except that row 0's North is the input buffer (`input_data[col]`). Each row and each column also has a broadcast bus, driven by one configured PE in that row or column. Each row has its own constant.

**Outputs.** `output_data[j]` is column bus `j`, registered. To bring a result out on output `j`, point column bus `j` at that PE.

**Run control.** A `start` while `done` is high latches `input_data`, clears all tokens and starts the LCU counter. PEs stop updating once `done` rises, so the outputs hold.

### Firing rules

- Each operand has a one-bit token. A PE fires when both operands are valid, then consumes both tokens and pulses `valid` for one cycle. Its neighbours see that pulse as a token.
- `X` (constant), `F` (own output) and row-0 `N` (input) are **permanent**: always valid, never consumed. A PE whose operands are both permanent fires every cycle. `PASS F` is idle filler, and row-0 `PASS N` rebroadcasts an input every cycle.
- **Only the token is held, not the data.** Operands are read live from the producer when the PE fires. If a producer fires twice before its consumer fires, the consumer sees the newer value and the two tokens merge into one. There is no backpressure, so keep paths balanced or keep producers steady.
- Every feedback loop must contain a `CARRY`. It fires once on its seed (`b`) and afterwards on the feedback edge (`a`).

### Operations

| Slot | Mnemonic | Result | Fires when |
| --- | --- | --- | --- |
| 0 | `ADD a b` | a + b | a and b valid |
| 1 | `SUB a b` | a − b | a and b valid |
| 2 | `MUL a b` | a · b | a and b valid |
| 3 | `MAC a b` | X − a · b (X = row constant) | a and b valid |
| 4 | `CARRY a b` | b on first firing, then a | a valid, or b valid before first firing |
| 5 | `MAX a b` / `MIN a b` | max / min | a and b valid |
| 5 | `PASS a` | a (assembles to `MAX a a`) | a valid |
| 6 | `GATE a b` | b, emitted only if a ≥ 0 | a and b valid |
| 7 | `NGATE a b` | b, emitted only if a < 0 | a and b valid |
| 6 | `SEL a b` | North ≥ 0 ? a : b | a, b and North valid |
| 7 | `CSIGN a b` | a < 0 ? −b : b | a and b valid |

A gate that does not fire still consumes its inputs.

Slots 5–7 are paged by two **array-wide mode bits**. The assembler infers them from the opcodes used and rejects a kernel that needs both settings:

- `cmp_min`: slot 5 is MAX (0) or MIN (1). `PASS`, and any `MAX`/`MIN` with identical operands, works under either setting.
- `branch_mode`: slots 6/7 are GATE/NGATE (0) or SEL/CSIGN (1).

### Operand sources

| Code | Source |
| --- | --- |
| `N` `S` `E` `W` | Neighbour output (row-0 `N` = input) |
| `R` | This row's bus |
| `C` | This column's bus |
| `X` | This row's constant |
| `F` | This PE's own output |

### Loop control unit

The LCU watches one PE's output. It raises `done` when either:

- the PE fired on the previous cycle, the compare matches and at least `MIN_CYCLES` cycles have elapsed, or
- the cycle counter reaches `TIMEOUT`.

Compare modes are `GT`, `LT`, `EQ` and `ABSLT` (|value| < const). `GT 7FFF` never matches, so the run always lasts the full timeout.

For a convergence test, prefer a cell whose value goes to zero, tested with `ABSLT`. A one-sided test on the iterate itself cannot tell convergence from overshoot. See `configs/reciprocal_linear.csv`. A kernel with several independent results (`configs/reciprocal_const_x4.csv`) cannot be tested by one LCU, so it runs for a fixed number of cycles instead.

The hardware does not report whether a run converged or timed out.

## Config file format

A CSV file. Blank lines and lines starting with `#` are ignored, so each kernel documents its inputs, constants and outputs at the top. All numbers are hex. For an N × N array (N = 4) there are N + 4 rows:

```
PE grid        N rows of N cells:   OPCODE A [B]
LCU            PE_INDEX, COMPARE, CONSTANT, MIN_CYCLES, TIMEOUT
Row buses      N values:  bus r is driven by column value[r] of row r
Column buses   N values:  bus c is driven by row value[c] of column c
Constants      1 value (all rows) or N values (one per row), Q3.13
```

- **PE cells:** a unary cell (`PASS N`) uses its operand for both A and B.
- **LCU row:** `PE_INDEX` is row-major (`row * N + col`, 0–F). Field widths are 4 / 2 / 16 / 6 / 10 bits.

Example (`configs/rsqrt.csv`):

```
SUB N W, PASS N, PASS F, MUL N R
CARRY W N, MUL N W, MAC W R, MUL W R
PASS F, ADD N N, PASS F, PASS F
PASS F, PASS F, PASS F, PASS F
6, LT, 2003, A, 0080
1, 0, 0, 0
1, 2, 1, 1
0000, 3000, 0000, 0000
```

## config.bin layout (33 bytes, little-endian)

| Bytes | Contents |
| --- | --- |
| 0–17 | 16 PE words × 9 bits, row-major. Word = `a_src[2:0] \| b_src[5:3] \| opcode[8:6]` |
| 18 | Row bus selects, 2 bits each, row 0 in bits 1:0 |
| 19 | Column bus selects, 2 bits each, column 0 in bits 1:0 |
| 20–27 | Row constants 0–3, 16 bits each |
| 28–32 | LCU word, 38 bits: `pe[3:0] cmp[5:4] const[21:6] min[27:22] timeout[37:28]`. Byte 32 bits 7:6 hold `cmp_min` and `branch_mode` |

## Array size

Only 4 × 4 is supported today. Several places assume that size and will have to be generalized together to support 2ⁿ × 2ⁿ:

- `top.sv`, `lcu.sv` and `tb.sv`: hard-coded loop bounds, port widths and the 144-bit PE config.
- The LCU's 4-bit PE index and the 2-bit bus selects.
- The assembler's four-constant row and fixed 33-byte layout.
