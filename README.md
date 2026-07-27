# Configuration File Format

The assembler reads a single CSV file describing the complete configuration of the CGRA. The format is designed to be human-readable while mapping directly to the hardware configuration bitstream.

## Array Size

The CGRA must be a **square array with dimensions (2^n \times 2^n)** for some integer (n \ge 0). Examples include:

* 1 × 1
* 2 × 2
* 4 × 4
* 8 × 8
* 16 × 16

The configuration file automatically scales with the array size.

## File Layout

The configuration file is divided into four sections in the following order:

1. **Processing Element (PE) Grid**
2. **Loop Control Unit (LCU) Configuration**
3. **Row Bus Configuration**
4. **Column Bus Configuration**
5. **Global Constant**

For an array of size **N × N**, the file contains:

* **N rows** describing the PE array
* **1 row** describing the LCU
* **1 row** describing the row bus routing
* **1 row** describing the column bus routing
* **1 row** containing the global constant

for a total of **N + 4 rows**.

## Processing Element Grid

The first **N rows** each contain **N comma-separated PE descriptions**.

Each PE is written as:

```
OPCODE SOURCE_A SOURCE_B
```

or, for unary operations,

```
OPCODE SOURCE
```

Whitespace inside each PE entry is ignored.

Example:

```
ADD N S
MUL W X
ABS F
SUB R C
```

## Available Operations

| Opcode | Description                |
| ------ | -------------------------- |
| `ADD`  | Addition                   |
| `SUB`  | Subtraction                |
| `MUL`  | Fixed-point multiplication |
| `ABS`  | Absolute value             |

Unary instructions such as `ABS` may omit the second operand.

## Data Sources

Each operand selects one of the following inputs.

| Source | Description                               |
| ------ | ----------------------------------------- |
| `N`    | North neighbor                            |
| `S`    | South neighbor                            |
| `E`    | East neighbor                             |
| `W`    | West neighbor                             |
| `R`    | Row bus                                   |
| `C`    | Column bus                                |
| `X`    | Global constant                           |
| `F`    | Feedback (previous output of the same PE) |

## LCU Configuration

The row immediately following the PE grid contains four values:

```
PE_INDEX, COMPARE, CONSTANT, TIMEOUT
```

where

* **PE_INDEX** is the flattened row-major index of the PE to monitor.
* **COMPARE** is one of:

  * `GT`
  * `LT`
  * `EQ`
  * `FALSE`
* **CONSTANT** is an 8-bit hexadecimal value.
* **TIMEOUT** is a 16-bit hexadecimal value.

Flattened indices are computed using

```
index = row × N + column
```

For example, in a 4 × 4 array:

```
0  1  2  3
4  5  6  7
8  9  A  B
C  D  E  F
```

## Row Bus Configuration

The next row contains **N comma-separated values**.

Each value selects which PE in that row drives the row bus.

Example for a 4 × 4 array:

```
0,3,1,2
```

## Column Bus Configuration

The following row contains **N comma-separated values**.

Each value selects which PE in that column drives the column bus.

Example:

```
2,2,0,1
```

## Global Constant

The final row contains a single signed 8-bit hexadecimal constant.

Example:

```
FF
```

This value is available to every processing element through the `X` source.
