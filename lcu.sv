import cgra_pkg::*;

module lcu(
    input logic clk,
    input logic rst,
    output logic done,
    input logic start,

    input logic signed [3:0][3:0][15:0] pe_values,
    input logic [3:0][3:0] pe_valids,
    input logic [3:0] pe_select,
    input logic [1:0] compare,
    input logic signed [15:0] compare_const,
    input logic [5:0] min_cycles,
    input logic [9:0] timeout
);

logic signed [15:0] pe_flat [0:15];
logic pe_valid_flat [0:15];
generate
    for (genvar row = 0; row < 4; row++) begin
        for (genvar col = 0; col < 4; col++) begin
            assign pe_flat[row*4 + col] = pe_values[row][col];
            assign pe_valid_flat[row*4 + col] = pe_valids[row][col];
        end
    end
endgenerate


logic signed [15:0] selected_value;
logic selected_valid;
always_comb begin
    selected_value = pe_flat[pe_select];
    selected_valid = pe_valid_flat[pe_select];
end


// Never converge on a value that has not yet been produced this run
logic compare_match;
logic compare_valid;

// 17 bits so -32768 negates without overflowing
logic signed [16:0] abs_value;
assign abs_value = selected_value[15] ? -{selected_value[15], selected_value}
                                      :  {selected_value[15], selected_value};

always_comb begin

    case(compare)
        GT: compare_match = selected_value > compare_const;
        LT: compare_match = selected_value < compare_const;
        EQ: compare_match = selected_value == compare_const;
        ABS_LT: compare_match = abs_value < $signed({1'b0, compare_const});
    endcase

    compare_valid = compare_match & selected_valid;
end


// Wider than timeout needs (10 bits) on purpose: narrowing this to [9:0] and
// comparing against timeout directly saves 11 flip-flops but costs 677 cells,
// because the zero-extended compares below collapse almost entirely.
logic [15:0] counter;
always_ff @(posedge clk or posedge rst) begin

    if (rst) begin
        counter <= 0;
        done <= 1;
    end

    else if (start && done) begin
        counter <= 0;
        done <= 0;
    end

    else if (!done) begin
        
        if (compare_valid && counter >= {10'b0, min_cycles})
            done <= 1;
        else if (counter >= {6'b0, timeout})
            done <= 1;
        else
            counter <= counter + 1;
            
    end
end

endmodule
