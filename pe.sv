import cgra_pkg::*;

// N_PERM marks the North input as a permanently-valid source. It is set for
// row 0, whose North is the input buffer: inputs are loop-invariant and
// input_valid is sticky for the whole run, so typing them as pulses was a
// mismatch that made every row-0 PE latch a token it did not need.
module pe #(parameter bit N_PERM = 1'b0) (
    input logic clk,
    input logic rst,
    input logic done,
    input logic start,

    input logic signed [15:0] North,
    input logic signed [15:0] South,
    input logic signed [15:0] East,
    input logic signed [15:0] West,
    input logic signed [15:0] Row,
    input logic signed [15:0] Col,
    input logic signed [15:0] Const,

    input logic v_North,
    input logic v_South,
    input logic v_East,
    input logic v_West,
    input logic v_Row,
    input logic v_Col,

    input logic [2:0] a_source_sel,
    input logic [2:0] b_source_sel,

    input logic [2:0] opcode,

    input logic cmp_min,     // 0 = CMP is max, 1 = CMP is min
    input logic branch_mode, // STEER_TOKEN (gates) or STEER_VALUE (select/copysign)

    output logic signed [15:0] out,
    output logic valid
);

logic signed [15:0] a;
logic signed [15:0] b;

always_comb begin
    case (a_source_sel)
        NORTH: a = North;
        SOUTH: a = South;
        EAST : a = East;
        WEST : a = West;
        ROW  : a = Row;
        COL  : a = Col;
        CONST: a = Const;
        SELF : a = out;
        default: a = '0;
    endcase

    case (b_source_sel)
        NORTH: b = North;
        SOUTH: b = South;
        EAST : b = East;
        WEST : b = West;
        ROW  : b = Row;
        COL  : b = Col;
        CONST: b = Const;
        SELF : b = out;
        default: b = '0;
    endcase
end

// Permanence is a property of the SOURCE, so it needs no configuration:
// Const is a static config value, Self is this PE's own register, and in row 0
// North is the latched input, so all three always hold a usable value.
// Everything else arrives as a one-cycle pulse that must be latched until this
// PE fires.
logic a_permanent, b_permanent;
logic a_pulse, b_pulse;

always_comb begin
    a_permanent = 1'b0; a_pulse = 1'b0;
    case (a_source_sel)
        NORTH: begin a_permanent = N_PERM; a_pulse = N_PERM ? 1'b0 : v_North; end
        SOUTH: a_pulse = v_South;
        EAST : a_pulse = v_East;
        WEST : a_pulse = v_West;
        ROW  : a_pulse = v_Row;
        COL  : a_pulse = v_Col;
        CONST: a_permanent  = 1'b1;
        SELF : a_permanent  = 1'b1;
        default: a_permanent = 1'b1;
    endcase

    b_permanent = 1'b0; b_pulse = 1'b0;
    case (b_source_sel)
        NORTH: begin b_permanent = N_PERM; b_pulse = N_PERM ? 1'b0 : v_North; end
        SOUTH: b_pulse = v_South;
        EAST : b_pulse = v_East;
        WEST : b_pulse = v_West;
        ROW  : b_pulse = v_Row;
        COL  : b_pulse = v_Col;
        CONST: b_permanent  = 1'b1;
        SELF : b_permanent  = 1'b1;
        default: b_permanent = 1'b1;
    endcase
end

// Holding one token per operand makes generation matching automatic: the Nth
// token to arrive on an edge is by construction from iteration N, so a PE
// consuming one from each input per firing can never mix two iterations.
logic a_token, b_token;
logic a_valid, b_valid;

// Usable on the cycle it arrives as well as from the latch, or every hop
// would cost two cycles instead of one.
assign a_valid = a_permanent | a_token | a_pulse;
assign b_valid = b_permanent | b_token | b_pulse;

// SEL reads its condition from North -- a third input, so it needs a third
// token. Binding the condition to one direction is what keeps this to a sign
// tap instead of the 16-bit third operand mux that measured +4235 LUT4.
logic cond_token;
logic cond_valid;
assign cond_valid = N_PERM | v_North | cond_token;

logic carry_seeded;

// CSIGN needs a real negation of b; the adder's internal one is not
// exposed as a 16-bit value.
logic signed [15:0] neg_b;
assign neg_b = (b == 16'sh8000) ? 16'sh7fff : -b;

// The two paged slots, named once so the datapath below never spells out a
// bare `branch_mode ? ... : ...`. Resolving them into a wider opcode enum
// instead reads well but measures 1120-1900 cells worse: the 3-bit case is
// fully dense and any recode makes it sparse.
logic value_page;
assign value_page = branch_mode; // STEER_VALUE

//                     STEER_TOKEN        STEER_VALUE
// COND_POS            GATE               SEL
// COND_NEG            NGATE              CSIGN
logic fire_cond_pos, fire_cond_neg;
assign fire_cond_pos = value_page ? (a_valid & b_valid & cond_valid) // SEL
                                  : (a_valid & b_valid & ~a[15]);    // GATE
assign fire_cond_neg = value_page ? (a_valid & b_valid)              // CSIGN
                                  : (a_valid & b_valid &  a[15]);    // NGATE

// A gate is the only op whose condition withholds the token rather than
// choosing the value, so it is the only one that discards without firing.
logic is_gate;
assign is_gate = ((opcode == COND_POS) | (opcode == COND_NEG)) & ~value_page;

logic fire;

always_comb begin
    case (opcode)
        CARRY:    fire = a_valid | (b_valid & ~carry_seeded);
        COND_POS: fire = fire_cond_pos;
        COND_NEG: fire = fire_cond_neg;
        default:  fire = a_valid & b_valid;
    endcase
end

// A steer that does not fire still consumes its inputs: the untaken value is
// discarded, not queued. Leaving it latched would pair a stale token with the
// next iteration's fresh one, which is exactly the generation skew the token
// discipline exists to prevent.
logic consume;
assign consume = is_gate ? (a_valid & b_valid) : fire;

// The upper half is intentionally dead: only bits [15:0] of the shifted
// product reach the output register. Slicing product[28:13] instead expresses
// the same thing and silences lint, but measures ~1000 cells worse.
logic signed [31:0] mul_result;
assign mul_result = ($signed({{16{a[15]}}, a}) * $signed({{16{b[15]}}, b})) >>> 13;

logic signed [16:0] add_wide;
logic signed [15:0] sat_add;

logic sub_mode;
assign sub_mode = (opcode == SUB) || (opcode == CMP);
assign add_wide = $signed({a[15], a}) + (sub_mode ? -$signed({b[15], b}) : $signed({b[15], b}));

// a >= b comes straight off the subtract's sign bit, so CMP needs no
// comparator of its own -- only the output mux, whose polarity is the
// array-wide min/max bit.
logic a_ge_b;
assign a_ge_b = ~add_wide[16];

assign sat_add = (add_wide > 17'sd32767)  ? 16'sd32767  :
                  (add_wide < -17'sd32768) ? -16'sd32768 :
                  add_wide[15:0];

// MAC keeps its own adder rather than muxing the multiplier output into the
// one above. Sharing looks cheaper and measures 7x worse: a mux on the DSP
// output path fans out badly through technology mapping.
logic signed [16:0] mac_wide;
logic signed [15:0] mac_sat;

assign mac_wide = $signed({Const[15], Const}) - $signed({mul_result[15], mul_result[15:0]});

assign mac_sat = (mac_wide > 17'sd32767)  ? 16'sd32767  :
                 (mac_wide < -17'sd32768) ? -16'sd32768 :
                 mac_wide[15:0];

always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        out <= '0;
        valid <= 1'b0;
        a_token <= 1'b0; b_token <= 1'b0; cond_token <= 1'b0; carry_seeded <= 1'b0;
    end

    else if (start && done) begin
        valid <= 1'b0;
        a_token <= 1'b0; b_token <= 1'b0; cond_token <= 1'b0; carry_seeded <= 1'b0;
    end

    else if (!done) begin

        a_token <= consume ? 1'b0 : (a_pulse | a_token);
        b_token <= consume ? 1'b0 : (b_pulse | b_token);
        cond_token <= consume ? 1'b0 : (v_North | cond_token);

        // The CARRY seed is one-shot: lock on ANY firing, not on `a`
        // arriving, since `a` is the feedback edge and cannot arrive until
        // the cycle closes.
        if (fire) carry_seeded <= 1'b1;

        valid <= fire;

        if (fire) case (opcode)
            ADD:      out <= sat_add;
            SUB:      out <= sat_add;
            MUL:      out <= mul_result[15:0];
            CMP:      out <= (a_ge_b ^ cmp_min) ? a : b;
            CARRY:    out <= a_valid ? a : b;
            MAC:      out <= mac_sat;
            COND_POS: out <= value_page ? (North[15] ? b : a)  // SEL
                                        : b;                  // GATE
            COND_NEG: out <= value_page ? (a[15] ? neg_b : b)  // CSIGN
                                        : b;                  // NGATE
            default:  out <= '0;
        endcase
    end
end

endmodule
