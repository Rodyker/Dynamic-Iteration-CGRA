module tb;

logic clk = 0;
logic rst;
logic start;
logic load_config;

logic [143:0] pe_config_in;
logic [7:0] row_config_in;
logic [7:0] col_config_in;
logic signed [3:0][15:0] global_config_in;
logic [37:0] lcu_config_in;
logic [1:0] mode_config_in;

logic signed [3:0][15:0] input_data;
logic signed [3:0][15:0] output_data;

logic done;

byte conf[33];

top dut(
    .clk(clk),
    .rst(rst),

    .start(start),
    .load_config(load_config),

    .pe_config_in(pe_config_in),
    .row_config_in(row_config_in),
    .col_config_in(col_config_in),
    .global_config_in(global_config_in),
    .lcu_config_in(lcu_config_in),
    .mode_config_in(mode_config_in),

    .input_data(input_data),
    .output_data(output_data),

    .done(done)
);

initial begin
    $dumpfile("wave.vcd");
    $dumpvars(0, tb);
end

always #5 clk = ~clk;

initial begin
    int config_file_handle;
    int bytes_read;
    int unsigned input_arg;

    config_file_handle = $fopen("config.bin", "rb");

    if (config_file_handle == 0)
        $fatal("Could not open config.bin");

    bytes_read = $fread(conf, config_file_handle);
    $fclose(config_file_handle);

    if (bytes_read != 33)
        $fatal("Expected 33-byte config.bin, read %0d bytes", bytes_read);

    pe_config_in = '0;

    for (int i = 0; i < 18; i++)
        pe_config_in[i*8 +: 8] = conf[i];

    row_config_in    = conf[18];
    col_config_in    = conf[19];
    for (int i = 0; i < 4; i++)
        global_config_in[i] = {conf[21+i*2], conf[20+i*2]};

    lcu_config_in =
    {
        conf[32][5:0],
        conf[31],
        conf[30],
        conf[29],
        conf[28]
    };

    // Array-wide mode rides in the two bits the 38-bit LCU field leaves spare
    // in its five bytes, so config.bin stays 33 bytes.
    mode_config_in = conf[32][7:6];

    rst = 1;
    start = 0;
    load_config = 0;

    input_data[0] = 16'h18E6;
    input_data[1] = 16'h3E61;
    input_data[2] = 16'h0000;
    input_data[3] = 16'h4000;

    if ($value$plusargs("input0=%h", input_arg)) input_data[0] = input_arg[15:0];
    if ($value$plusargs("input1=%h", input_arg)) input_data[1] = input_arg[15:0];
    if ($value$plusargs("input2=%h", input_arg)) input_data[2] = input_arg[15:0];
    if ($value$plusargs("input3=%h", input_arg)) input_data[3] = input_arg[15:0];

    repeat (2) @(posedge clk);

    rst = 0;

    load_config = 1;
    @(posedge clk);
    load_config = 0;

    start = 1;
    @(posedge clk);
    start = 0;

    wait(done);

    // output_data is declared signed, but an element select of a packed array
    // is unsigned by the LRM -- without $signed this silently printed -0.5 as
    // 7.5, and whether it did depended on how Verilator inlined the build.
    $display("Output:");
    $display("%f, %f, %f, %f",
        $signed(output_data[0]) / 8192.0,
        $signed(output_data[1]) / 8192.0,
        $signed(output_data[2]) / 8192.0,
        $signed(output_data[3]) / 8192.0
    );

    $finish;
end

initial begin
    int cycle = -4;

    forever begin
        @(posedge clk);
        cycle++;

        if (cycle >= 0) begin

            $display("\nCycle %0d", cycle);

            for (int r = 0; r < 4; r++) begin
                for (int c = 0; c < 4; c++) begin
                    $write("%f ", $signed(dut.pe_out[r][c]) / 8192.0);
                    // $write("%b ", dut.pe_out[r][c]);
                end
                $write("\n");
            end
        end
    end

end

endmodule

//Allow for more extensive tiling to allow for more complex programs
//Potential block floating point per tile
//ADD MAC AND DELAY