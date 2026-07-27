import cgra_pkg::*;

module lcu(
    input logic clk,
    input logic rst,
    output logic done,
    input logic start,

    input logic signed [3:0][3:0][7:0] pe_values,
    input logic [3:0] pe_select,
    input logic [1:0] compare,
    input logic signed [7:0] compare_const,
    input logic [15:0] timeout
);

logic signed [7:0] pe_flat [0:15];
generate
    for (genvar r = 0; r < 4; r++) begin
        for (genvar c = 0; c < 4; c++) begin
            assign pe_flat[r*4 + c] = pe_values[r][c];
        end
    end
endgenerate


logic signed [7:0] selected_value;
always_comb begin
    selected_value = pe_flat[pe_select];
end


logic compare_done;
always_comb begin

    case(compare)
        GT: compare_done = selected_value > compare_const;
        LT: compare_done = selected_value < compare_const;
        EQ: compare_done = selected_value == compare_const;
        FALSE: compare_done = 1'b0;
    endcase
end


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

        if (compare_done)
            done <= 1;
        else if (counter >= timeout)
            done <= 1;
        else
            counter <= counter + 1;
            
    end
end

endmodule
