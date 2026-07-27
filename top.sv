import cgra_pkg::*;

module top(
    input logic clk,
    input logic rst,

    input logic start,
    input logic load_config,

    // Configuration
    input logic [127:0] pe_config_in, // 2 inputs * 4x4 PEs * 8 bits per PE = 128 bits
    input logic [7:0] row_config_in,  // 4 rows * choose from 4 PEs = 8 bits
    input logic [7:0] col_config_in,  // 4 cols * choose from 4 PEs = 8 bits
    input logic signed [7:0] global_config_in, // 8 bits
    input logic [29:0] lcu_config_in, // 

    // Data interface
    input logic signed [3:0][7:0] input_data,
    output logic signed [3:0][7:0] output_data,

    output logic done
);


// Configuration registers

logic [127:0] pe_config;
logic [7:0] row_config;
logic [7:0] col_config;
logic signed [7:0] global_config;
logic [29:0] lcu_config;

always_ff @(posedge clk or posedge rst) begin

    if(rst) begin
        pe_config <= '0;
        row_config <= '0;
        col_config <= '0;
        global_config <= '0;
        lcu_config <= '0;
    end

    else if(load_config) begin
        pe_config <= pe_config_in;
        row_config <= row_config_in;
        col_config <= col_config_in;
        global_config <= global_config_in;
        lcu_config <= lcu_config_in;
    end
end


// Input buffer

logic signed [3:0][7:0] input_buffer;

always_ff @(posedge clk or posedge rst) begin
    if(rst) input_buffer <= 0;

    else if(start && done) input_buffer <= input_data;
end


// Output capture

always_ff @(posedge clk or posedge rst) begin
    if (rst) 
        output_data <= 0;
    else 
        for (int i = 0; i < 4; i++) begin
            output_data[i] <= pe_out[3][i];
        end
end


// PE configuration decode

logic [3:0][3:0][2:0] pe_pick_a;
logic [3:0][3:0][2:0] pe_pick_b;
logic [3:0][3:0][1:0] pe_opcode;

genvar pe_i;
genvar pe_j;

generate
    for (pe_i = 0; pe_i < 4; pe_i = pe_i + 1) begin : pe_config_row
        for (pe_j = 0; pe_j < 4; pe_j = pe_j + 1) begin : pe_config_col
            assign pe_pick_a[pe_i][pe_j] = pe_config[(pe_i*32) + (pe_j*8) +: 3];
            assign pe_pick_b[pe_i][pe_j] = pe_config[(pe_i*32) + (pe_j*8) + 3 +: 3];
            assign pe_opcode[pe_i][pe_j] = pe_config[(pe_i*32) + (pe_j*8) + 6 +: 2];
        end
    end
endgenerate


// Bus select decode

logic [1:0] row_select [4];
logic [1:0] col_select [4];

genvar bus_i;

generate
    for (bus_i = 0; bus_i < 4; bus_i = bus_i + 1) begin : bus_select_decode
        assign row_select[bus_i] = row_config[bus_i*2 +: 2];
        assign col_select[bus_i] = col_config[bus_i*2 +: 2];
    end
endgenerate


// PE wiring

logic signed [3:0][3:0][7:0] North, South, East, West, Row, Col, Const, pe_out;
logic signed [3:0][7:0] row_bus, col_bus;

always_comb begin
    for(int i=0;i<4;i++) begin
        row_bus[i] = pe_out[i][row_select[i]];
        col_bus[i] = pe_out[col_select[i]][i];
    end
end

generate
    for (pe_i = 0; pe_i < 4; pe_i = pe_i + 1) begin : pe_wire_row
        for (pe_j = 0; pe_j < 4; pe_j = pe_j + 1) begin : pe_wire_col

            if (pe_i == 0) begin
                assign North[pe_i][pe_j] = input_buffer[pe_j];
            end else begin
                assign North[pe_i][pe_j] = pe_out[pe_i-1][pe_j];
            end

            if (pe_i == 3) begin
                assign South[pe_i][pe_j] = pe_out[0][pe_j];
            end else begin
                assign South[pe_i][pe_j] = pe_out[pe_i+1][pe_j];
            end

            if (pe_j == 3) begin
                assign East[pe_i][pe_j] = pe_out[pe_i][0];
            end else begin
                assign East[pe_i][pe_j] = pe_out[pe_i][pe_j+1];
            end

            if (pe_j == 0) begin
                assign West[pe_i][pe_j] = pe_out[pe_i][3];
            end else begin
                assign West[pe_i][pe_j] = pe_out[pe_i][pe_j-1];
            end

            assign Row[pe_i][pe_j]   = row_bus[pe_i];
            assign Col[pe_i][pe_j]   = col_bus[pe_j];
            assign Const[pe_i][pe_j] = global_config;
        end
    end
endgenerate


// PE net

generate
    for (pe_i = 0; pe_i < 4; pe_i = pe_i + 1) begin : pe_array_row
        for (pe_j = 0; pe_j < 4; pe_j = pe_j + 1) begin : pe_array_col
            pe pe_inst(
            .clk(clk),
            .rst(rst),
            .done(done),

            .North(North[pe_i][pe_j]),
            .South(South[pe_i][pe_j]),
            .East(East[pe_i][pe_j]),
            .West(West[pe_i][pe_j]),

            .Row(Row[pe_i][pe_j]),
            .Col(Col[pe_i][pe_j]),
            .Const(Const[pe_i][pe_j]),

            .a_sel(pe_pick_a[pe_i][pe_j]),
            .b_sel(pe_pick_b[pe_i][pe_j]),

            .opcode(pe_opcode[pe_i][pe_j]),

            .out(pe_out[pe_i][pe_j])
            );
        end
    end
endgenerate


// LCU

lcu lcu_inst(

    .clk(clk),
    .rst(rst),
    .start(start),

    .pe_values(pe_out),

    .pe_select(lcu_config[3:0]),

    .compare(lcu_config[5:4]),

    .compare_const(lcu_config[13:6]),

    .timeout(lcu_config[29:14]),

    .done(done)
);

endmodule
