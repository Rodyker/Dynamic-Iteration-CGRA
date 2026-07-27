import cgra_pkg::*;

module pe(
    input logic clk,
    input logic rst,
    input logic done,

    // Data inputs
    input logic signed [7:0] North,
    input logic signed [7:0] South,
    input logic signed [7:0] East,
    input logic signed [7:0] West,
    input logic signed [7:0] Row,
    input logic signed [7:0] Col,
    input logic signed [7:0] Const,

    input logic [2:0] a_sel,
    input logic [2:0] b_sel,

    input logic [1:0] opcode,

    output logic signed [7:0] out
);

// Internal Signals
logic signed [7:0] a;
logic signed [7:0] b;

// Operand Multiplexers

always_comb begin
    case (a_sel)
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

    case (b_sel)
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

// Output Register

logic signed [15:0] mul_result;
assign mul_result = ($signed({{8{a[7]}}, a}) * $signed({{8{b[7]}}, b})) >>> 5;

always_ff @(posedge clk or posedge rst) begin
    if (rst) out <= '0;

    else if (!done) begin
        case (opcode)
            ADD: out <= a + b;
            SUB: out <= a - b;
            MUL: out <= mul_result[7:0];
            ABS: out <= a[7] ? -a : a;
            default: out <= '0;
        endcase
    end
end

endmodule
