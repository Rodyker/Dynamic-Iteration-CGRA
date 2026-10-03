package cgra_pkg;

// The letter in each comment is the mnemonic the assembler accepts in
// config.csv, so these values are a wire format -- pinned, not positional.
typedef enum logic [2:0] {
    NORTH = 3'd0, // N
    SOUTH = 3'd1, // S
    EAST  = 3'd2, // E
    WEST  = 3'd3, // W
    ROW   = 3'd4, // R  row broadcast bus
    COL   = 3'd5, // C  column broadcast bus
    CONST = 3'd6, // X  this row's constant
    SELF  = 3'd7  // F  this PE's own output register
} source_t;

// Grouped arithmetic-first for readability, which costs 1092 cells: the opcode
// values decide how the output mux tree pairs up, and the old order
// (ADD SUB MUL CMP CARRY MAC ...) paired more cheaply. Swapping CMP and CARRY
// below recovers 395 of those if the cells are ever needed back.
//
// Slots 6 and 7 hold two branch idioms and branch_mode picks which the whole
// array uses, so the two idioms share two encodings instead of four. The
// pairing is not arbitrary: in both idioms slot 6 acts when the condition is
// non-negative and slot 7 acts when it is negative.
typedef enum logic [2:0] {
    ADD       = 3'd0,
    SUB       = 3'd1,
    MUL       = 3'd2,
    MAC       = 3'd3, // out <= Const - a*b. The third operand is bound to the
                      //   row constant, so it costs no config space.
    CARRY     = 3'd4, // loop carry: fires on EITHER operand, seeds once from
                      //   b, then locks to a. Every feedback loop is broken
                      //   by one of these.
    CMP       = 3'd5, // MAX, or MIN when cmp_min. CMP a a is an identity
                      //   relay on either setting, which is what PASS
                      //   assembles to.
    COND_POS  = 3'd6, // acts when the condition is >= 0
                      //   STEER_TOKEN  GATE:  fire iff a >= 0, out <= b
                      //   STEER_VALUE  SEL:   out <= a when North >= 0, else
                      //     b. The condition is bound to North, so it is a
                      //     sign tap rather than a third 16-bit operand mux.
    COND_NEG  = 3'd7  // acts when the condition is < 0
                      //   STEER_TOKEN  NGATE: fire iff a < 0, out <= b.
                      //     Exact complement of GATE, including at a == 0.
                      //   STEER_VALUE  CSIGN: out <= -b when a < 0, else b
} opcode_t;

// What the condition's sign actually steers. This is the array-wide bit that
// selects between the two idioms sharing slots 6 and 7.
typedef enum logic {
    STEER_TOKEN = 1'b0, // the sign decides WHETHER a token is emitted
    STEER_VALUE = 1'b1  // the sign decides WHICH value is emitted
} branch_mode_t;


// LCU convergence test. Values are pinned to match the assembler's table;
// 'never converge, run to timeout' is spelled GT 7FFF.
typedef enum logic [1:0] {
    EQ     = 2'd2,
    GT     = 2'd0,
    LT     = 2'd1,
    ABS_LT = 2'd3  // |value| < compare_const   (two-sided)
} compare_t;

endpackage
