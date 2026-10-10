package cgra_pkg;

// Encodings are the assembler's wire format; the letter is the CSV mnemonic.
typedef enum logic [2:0] {
    NORTH = 3'd0, // N  (row 0: input buffer)
    SOUTH = 3'd1, // S
    EAST  = 3'd2, // E
    WEST  = 3'd3, // W
    ROW   = 3'd4, // R  row bus
    COL   = 3'd5, // C  column bus
    CONST = 3'd6, // X  this row's constant
    SELF  = 3'd7  // F  this PE's own output
} source_t;

// Opcode order affects synthesized area: swapping CMP and CARRY measured
// ~400 cells smaller.
//
// Slots 6 and 7 are paged by branch_mode. In both pages, slot 6 acts on a
// non-negative condition and slot 7 on a negative one.
typedef enum logic [2:0] {
    ADD       = 3'd0,
    SUB       = 3'd1,
    MUL       = 3'd2,
    MAC       = 3'd3, // Const - a*b
    CARRY     = 3'd4, // loop carry: seeds once from b, then follows a
    CMP       = 3'd5, // MAX, or MIN when cmp_min. CMP a a = PASS a.
    COND_POS  = 3'd6, // GATE: emit b iff a >= 0   | SEL:   North >= 0 ? a : b
    COND_NEG  = 3'd7  // NGATE: emit b iff a < 0   | CSIGN: a < 0 ? -b : b
} opcode_t;

typedef enum logic {
    STEER_TOKEN = 1'b0, // GATE / NGATE: the sign decides whether a token is emitted
    STEER_VALUE = 1'b1  // SEL / CSIGN:  the sign decides which value is emitted
} branch_mode_t;

// Values must match the assembler's COMPARE_CODES.
typedef enum logic [1:0] {
    EQ     = 2'd2,
    GT     = 2'd0,
    LT     = 2'd1,
    ABS_LT = 2'd3  // |value| < compare_const
} compare_t;

endpackage
