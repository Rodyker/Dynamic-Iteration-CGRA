import cgra_pkg::*;

module top(
    input logic clk,
    input logic rst,

    input logic start,
    input logic load_config,

    input logic [143:0] pe_config_in, // 4x4 PEs * 9 bits per PE = 144 bits
    input logic [7:0] row_config_in,  // 4 rows * choose from 4 PEs = 8 bits
    input logic [7:0] col_config_in,  // 4 cols * choose from 4 PEs = 8 bits
    input logic signed [3:0][15:0] global_config_in, // one constant per row, Q3.13
    input logic [37:0] lcu_config_in,
    input logic [1:0] mode_config_in, // array-wide: [0] cmp_min, [1] branch_mode

    input logic signed [3:0][15:0] input_data,
    output logic signed [3:0][15:0] output_data,

    output logic done
);

logic [143:0] pe_config;
logic [7:0] row_config;
logic [7:0] col_config;
logic signed [3:0][15:0] global_config;
logic [37:0] lcu_config;
logic [1:0] mode_config;

always_ff @(posedge clk or posedge rst) begin

    if(rst) begin
        pe_config <= '0;
        row_config <= '0;
        col_config <= '0;
        global_config <= '0;
        lcu_config <= '0;
        mode_config <= '0;
    end

    else if(load_config) begin
        pe_config <= pe_config_in;
        row_config <= row_config_in;
        col_config <= col_config_in;
        global_config <= global_config_in;
        lcu_config <= lcu_config_in;
        mode_config <= mode_config_in;
    end
end

logic signed [3:0][15:0] input_buffer;
logic input_valid;

always_ff @(posedge clk or posedge rst) begin
    if(rst) begin
        input_buffer <= 0;
        input_valid <= 1'b0;
    end

    else if(start && done) begin
        input_buffer <= input_data;
        input_valid <= 1'b1;
    end
end

logic [3:0][3:0][2:0] pe_select_a;
logic [3:0][3:0][2:0] pe_select_b;
logic [3:0][3:0][2:0] pe_opcode;

genvar pe_i;
genvar pe_j;

generate
    for (pe_i = 0; pe_i < 4; pe_i = pe_i + 1) begin : pe_config_row
        for (pe_j = 0; pe_j < 4; pe_j = pe_j + 1) begin : pe_config_col
            assign pe_select_a[pe_i][pe_j] = pe_config[(pe_i*36) + (pe_j*9) +: 3];
            assign pe_select_b[pe_i][pe_j] = pe_config[(pe_i*36) + (pe_j*9) + 3 +: 3];
            assign pe_opcode[pe_i][pe_j] = pe_config[(pe_i*36) + (pe_j*9) + 6 +: 3];
        end
    end
endgenerate

logic [1:0] row_select [4];
logic [1:0] col_select [4];

genvar bus_i;

generate
    for (bus_i = 0; bus_i < 4; bus_i = bus_i + 1) begin : bus_select_decode
        assign row_select[bus_i] = row_config[bus_i*2 +: 2];
        assign col_select[bus_i] = col_config[bus_i*2 +: 2];
    end
endgenerate

logic signed [3:0][3:0][15:0] North, South, East, West, Row, Col, Const, pe_out;
logic signed [3:0][15:0] row_bus, col_bus;

// Validity plane, mirroring the data interconnect
logic [3:0][3:0] v_North, v_South, v_East, v_West, v_Row, v_Col, pe_valid;
logic [3:0] row_bus_valid, col_bus_valid;

always_comb begin
    for(int i=0;i<4;i++) begin
        row_bus[i]       = pe_out[i][row_select[i]];
        col_bus[i]       = pe_out[col_select[i]][i];
        row_bus_valid[i] = pe_valid[i][row_select[i]];
        col_bus_valid[i] = pe_valid[col_select[i]][i];
    end
end

generate
    for (pe_i = 0; pe_i < 4; pe_i = pe_i + 1) begin : pe_wire_row
        for (pe_j = 0; pe_j < 4; pe_j = pe_j + 1) begin : pe_wire_col

            if (pe_i == 0) begin
                assign North[pe_i][pe_j]   = input_buffer[pe_j];
                assign v_North[pe_i][pe_j] = input_valid;
            end else begin
                assign North[pe_i][pe_j]   = pe_out[pe_i-1][pe_j];
                assign v_North[pe_i][pe_j] = pe_valid[pe_i-1][pe_j];
            end

            if (pe_i == 3) begin
                assign South[pe_i][pe_j]   = pe_out[0][pe_j];
                assign v_South[pe_i][pe_j] = pe_valid[0][pe_j];
            end else begin
                assign South[pe_i][pe_j]   = pe_out[pe_i+1][pe_j];
                assign v_South[pe_i][pe_j] = pe_valid[pe_i+1][pe_j];
            end

            if (pe_j == 3) begin
                assign East[pe_i][pe_j]   = pe_out[pe_i][0];
                assign v_East[pe_i][pe_j] = pe_valid[pe_i][0];
            end else begin
                assign East[pe_i][pe_j]   = pe_out[pe_i][pe_j+1];
                assign v_East[pe_i][pe_j] = pe_valid[pe_i][pe_j+1];
            end

            if (pe_j == 0) begin
                assign West[pe_i][pe_j]   = pe_out[pe_i][3];
                assign v_West[pe_i][pe_j] = pe_valid[pe_i][3];
            end else begin
                assign West[pe_i][pe_j]   = pe_out[pe_i][pe_j-1];
                assign v_West[pe_i][pe_j] = pe_valid[pe_i][pe_j-1];
            end

            assign Row[pe_i][pe_j]   = row_bus[pe_i];
            assign Col[pe_i][pe_j]   = col_bus[pe_j];
            assign Const[pe_i][pe_j] = global_config[pe_i];

            assign v_Row[pe_i][pe_j] = row_bus_valid[pe_i];
            assign v_Col[pe_i][pe_j] = col_bus_valid[pe_j];
        end
    end
endgenerate

always_ff @(posedge clk or posedge rst) begin
    if (rst)
        output_data <= 0;
    else
        for (int i = 0; i < 4; i++) begin
            output_data[i] <= col_bus[i];
        end
end

generate
    for (pe_i = 0; pe_i < 4; pe_i = pe_i + 1) begin : pe_array_row
        for (pe_j = 0; pe_j < 4; pe_j = pe_j + 1) begin : pe_array_col
            pe #(.N_PERM(pe_i == 0)) pe_inst(
            .clk(clk),
            .rst(rst),
            .done(done),
            .start(start),

            .North(North[pe_i][pe_j]),
            .South(South[pe_i][pe_j]),
            .East(East[pe_i][pe_j]),
            .West(West[pe_i][pe_j]),

            .Row(Row[pe_i][pe_j]),
            .Col(Col[pe_i][pe_j]),
            .Const(Const[pe_i][pe_j]),

            .v_North(v_North[pe_i][pe_j]),
            .v_South(v_South[pe_i][pe_j]),
            .v_East(v_East[pe_i][pe_j]),
            .v_West(v_West[pe_i][pe_j]),
            .v_Row(v_Row[pe_i][pe_j]),
            .v_Col(v_Col[pe_i][pe_j]),

            .a_source_sel(pe_select_a[pe_i][pe_j]),
            .b_source_sel(pe_select_b[pe_i][pe_j]),

            .opcode(pe_opcode[pe_i][pe_j]),

            .cmp_min(mode_config[0]),
            .branch_mode(mode_config[1]),

            .out(pe_out[pe_i][pe_j]),
            .valid(pe_valid[pe_i][pe_j])
            );
        end
    end
endgenerate

lcu lcu_inst(

    .clk(clk),
    .rst(rst),
    .start(start),

    .pe_values(pe_out),
    .pe_valids(pe_valid),

    .pe_select(lcu_config[3:0]),

    .compare(lcu_config[5:4]),

    .compare_const(lcu_config[21:6]),

    .min_cycles(lcu_config[27:22]),

    .timeout(lcu_config[37:28]),

    .done(done)
);

endmodule
