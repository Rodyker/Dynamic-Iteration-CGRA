<!-- Written by Claude. -->
# Test vectors

All values are Q3.13 hex (`2000` = 1.0, negative values in two's complement: `E000` = −1.0). Expected values are the exact result rounded to the nearest LSB. The iterative kernels land within the tolerance listed for each one, so the lowest bits can differ. To simulate a row, run `cgra sim configs\<name>.csv --inputs <input[0]> <input[1]> <input[2]> <input[3]>`.

## reciprocal_linear — output[1] = 1/D

Fixed inputs: `[0] = 18E6`, `[1] = 3E61`. Tolerance: ±10 LSB.

| D | input[3] | Exact 1/D | Simulated output[1] |
| --- | --- | --- | --- |
| 0.5 | `1000` | 2.0 (`4000`) | `4000` |
| 1.0 | `2000` | 1.0 (`2000`) | `1FFF` |
| 1.5 | `3000` | 0.6667 (`1555`) | `1555` |
| 2.0 | `4000` | 0.5 (`1000`) | `0FFF` |
| 2.5 | `5000` | 0.4 (`0CCD`) | `0CCC` |
| 3.0 | `6000` | 0.3333 (`0AAB`) | `0AAA` |
| 0 | `0000` | — | timeout |

Board (`cgra fpga`): switches = D, LEDs = 1/D.

## reciprocal_const_x4 — output[j] = 1/D[j]

Inputs: `[j] = D` for lane j. Tolerance: ±3 LSB. Every run takes 25 cycles, so the display's timeout dots are always lit; the result is valid only for D in (0.25, 3.0].

| D[0..3] | input[0..3] | Exact 1/D | Simulated output[0..3] |
| --- | --- | --- | --- |
| 0.5, 1.0, 1.5, 3.0 | `1000 2000 3000 6000` | `4000 2000 1555 0AAB` | `4000 1FFF 1555 0AAA` |
| 2.0, 2.5, 0.375, 0.75 | `4000 5000 0C00 1800` | `1000 0CCD 5555 2AAB` | `0FFF 0CCC 5557 2AAB` |
| 0.3125, 1.25, 1.0, 1.0 | `0A00 2800 2000 2000` | `6666 199A 2000 2000` | `6669 1999 1FFF 1FFF` |

Board (`cgra fpga`): switches = D for lane 0, LEDs = 1/D for lane 0. Lanes 1-3 are fixed at 1.0, 1.5, 3.0.

## rsqrt — output[0] = 1/√D, output[1] = √D

Fixed inputs: `[0] = 2CF3`, `[3] = 110A`. input[1] is E = D/2, not D. Tolerance: ±7 LSB on 1/√D, ±5 LSB on √D.

| D | input[1] (E) | 1/√D | output[0] | √D | output[1] |
| --- | --- | --- | --- | --- | --- |
| 0.25 | `0400` | 2.0 | `4000` | 0.5 | `1000` |
| 1.0 | `1000` | 1.0 | `2000` | 1.0 | `2000` |
| 2.0 | `2000` | 0.7071 | `16A1` | 1.4142 | `2D41` |
| 3.0 | `3000` | 0.5774 | `127A` | 1.7321 | `376D` |
| 4.0 | `4000` | 0.5 | `1000` | 2.0 | `4000` |

Board (`cgra fpga`): switches = E, LEDs = 1/√D. Add `--led 1` to show √D instead.

## median3 — output[2] = median(a, b, c)

Inputs: `[0] = a`, `[1] = b`, `[2] = b`, `[3] = c`. Exact, since there is no iteration. Requires |a+b| < 4 and |max(a,b)+c| < 4.

| a | b | c | input[0..3] | Median | output[2] |
| --- | --- | --- | --- | --- | --- |
| 1.0 | 0.5 | 1.5 | `2000 1000 1000 3000` | 1.0 | `2000` |
| −1.0 | 0.25 | 0.5 | `E000 0800 0800 1000` | 0.25 | `0800` |
| 1.5 | 1.0 | −0.5 | `3000 2000 2000 F000` | 1.0 | `2000` |
| 0.5 | 0.5 | 0 | `1000 1000 1000 0000` | 0.5 | `1000` |

Board (`cgra fpga`): switches = c, LEDs = median, with a = 1.0 and b = 0.5 fixed. The LEDs then show c clamped to [0.5, 1.0].
