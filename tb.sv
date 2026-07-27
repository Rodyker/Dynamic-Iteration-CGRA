module tb;

logic clk = 0;
logic rst;
logic start;
logic load_config;

logic [127:0] pe_config_in;
logic [7:0] row_config_in;
logic [7:0] col_config_in;
logic signed [7:0] global_config_in;
logic [29:0] lcu_config_in;

logic signed [3:0][7:0] input_data;
logic signed [3:0][7:0] output_data;

logic done;

byte conf[23];

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
    int fd;
    int count;

    //////////////////////////////////////////////////
    // Read binary configuration
    //////////////////////////////////////////////////

    fd = $fopen("config.bin", "rb");

    if (fd == 0)
        $fatal("Could not open config.bin");

    count = $fread(conf, fd);
    $fclose(fd);

    if (count != 23)
        $fatal("Expected 23-byte config.bin, read %0d bytes", count);

    //////////////////////////////////////////////////
    // Unpack configuration
    //////////////////////////////////////////////////

    pe_config_in = '0;

    for (int i = 0; i < 16; i++)
        pe_config_in[i*8 +: 8] = conf[i];

    row_config_in    = conf[16];
    col_config_in    = conf[17];
    global_config_in = conf[18];

    lcu_config_in =
    {
        conf[22][5:0],
        conf[21],
        conf[20],
        conf[19]
    };

    //////////////////////////////////////////////////
    // Default inputs
    //////////////////////////////////////////////////

    rst = 1;
    start = 0;
    load_config = 0;

    //fixed point representation with 5 fractional bits
    input_data[0] = 8'b00111000; //divisor (1.75)
    input_data[1] = 8'b00100000; //initial guess (1.0)
    input_data[2] = 8'h00;
    input_data[3] = 8'h00;

    //////////////////////////////////////////////////
    // Run
    //////////////////////////////////////////////////

    repeat (2) @(posedge clk);

    rst = 0;

    load_config = 1;
    @(posedge clk);
    load_config = 0;

    start = 1;
    @(posedge clk);
    start = 0;

    wait(done);

    $display("Output:");
    $display("%f, %f, %f, %f",
        output_data[0] / 32.0,
        output_data[1] / 32.0,
        output_data[2] / 32.0,
        output_data[3] / 32.0
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
                    $write("%f ", dut.pe_out[r][c] / 32.0);
                end
                $write("\n");
            end
        end
    end


end

endmodule