// Written by Claude.
// Basys 3 wrapper for hand-testing a kernel. The config is baked in at build
// time and the array reruns back to back, so results follow the switches live.
//
//   sw[15:0]   input[SW_SLOT], Q3.13 (other inputs fixed by INPUTS)
//   led[15:0]  output[LED_OUT] of the last finished run, Q3.13
//   display    cycle count of the last run in hex; all four dots lit = timed out
//   btnD       reset and reload the config
//
// Defaults are for configs/reciprocal_linear: sw = D, led = 1/D.
//
// The board's 100 MHz clock is divided to 50 MHz: the MUL -> MAC path misses 100.
module basys3_top #(
    // config.bin as a little-endian vector (byte 0 in bits 7:0). build.tcl
    // overrides this from config.bin; the default is configs/reciprocal_linear.
    parameter logic [263:0] CONFIG = 264'h0802_80023c40_00000000_000000ff_4070a4e1_4f3bfdfe_ff7fbfdf_eff7fa05_fcb098,
    parameter logic [63:0]  INPUTS = {16'h0000, 16'h0000, 16'h3E61, 16'h18E6}, // input[3] .. input[0]
    parameter int           SW_SLOT = 3,
    parameter int           LED_OUT = 1
) (
    input  logic        clk100,
    input  logic [15:0] sw,
    input  logic        btnD,
    output logic [15:0] led,
    output logic [6:0]  seg,
    output logic        dp,
    output logic [3:0]  an
);

// 100 MHz -> VCO 1000 MHz -> 50 MHz
logic clk, clk_mmcm, clk_fb;
MMCME2_BASE #(
    .CLKIN1_PERIOD(10.0),
    .CLKFBOUT_MULT_F(10.0),
    .CLKOUT0_DIVIDE_F(20.0)
) mmcm (
    .CLKIN1(clk100), .CLKFBIN(clk_fb), .CLKFBOUT(clk_fb),
    .CLKOUT0(clk_mmcm),
    .RST(1'b0), .PWRDWN(1'b0),
    .LOCKED(),
    .CLKOUT0B(), .CLKOUT1(), .CLKOUT1B(), .CLKOUT2(), .CLKOUT2B(),
    .CLKOUT3(), .CLKOUT3B(), .CLKOUT4(), .CLKOUT5(), .CLKOUT6(), .CLKFBOUTB()
);
BUFG clk_buf (.I(clk_mmcm), .O(clk));

logic reset_p;
debounce db_d (.clk, .in(btnD), .pulse(reset_p));

// Reset on power-up and on btnD, then load the config one cycle later.
logic [3:0] por = '1;
logic rst, load_config;
always_ff @(posedge clk) begin
    if (reset_p) por <= '1;
    else if (por != 0) por <= por - 1;
end
assign rst = (por > 1);
assign load_config = (por == 1);

logic [1:0][15:0] sw_sync = '0;
always_ff @(posedge clk) sw_sync <= {sw_sync[0], sw};

logic signed [3:0][15:0] input_data;
always_comb begin
    input_data = INPUTS;
    input_data[SW_SLOT] = sw_sync[1];
end

logic signed [3:0][15:0] output_data;
logic done, done_q, start;

// Start the next run as soon as one finishes.
assign start = done && (por == 0);

// Cycles from start until done; more than the LCU timeout means it timed out.
logic [15:0] cycles;
always_ff @(posedge clk) begin
    if (rst || start) cycles <= 0;
    else if (!done)   cycles <= cycles + 1;
end

// output_data holds the final values on the cycle done rises.
logic [15:0] result = '0, result_cycles = '0;
always_ff @(posedge clk) begin
    done_q <= done;
    if (done && !done_q) begin
        result        <= output_data[LED_OUT];
        result_cycles <= cycles;
    end
end

top dut (
    .clk, .rst,
    .start,
    .load_config,
    .pe_config_in    (CONFIG[143:0]),
    .row_config_in   (CONFIG[151:144]),
    .col_config_in   (CONFIG[159:152]),
    .global_config_in(CONFIG[223:160]),
    .lcu_config_in   (CONFIG[261:224]),
    .mode_config_in  (CONFIG[263:262]),
    .input_data,
    .output_data,
    .done
);

assign led = result;

logic timed_out;
assign timed_out = result_cycles > CONFIG[261:252]; // LCU timeout field

sevenseg display (.clk, .value(result_cycles), .dots(timed_out), .seg, .dp, .an);

endmodule


// Synchronize, debounce (~20 ms at 50 MHz) and emit a one-cycle press pulse.
module debounce (
    input  logic clk,
    input  logic in,
    output logic pulse
);
    logic [1:0]  sync = 0;
    logic        state = 0;
    logic [19:0] count = 0;

    always_ff @(posedge clk) begin
        sync  <= {sync[0], in};
        pulse <= 1'b0;
        if (sync[1] == state) count <= 0;
        else if (&count) begin
            state <= sync[1];
            pulse <= sync[1];
            count <= 0;
        end
        else count <= count + 1;
    end
endmodule


// Four hex digits, multiplexed, with all decimal points on when dots is set.
// Segments and anodes are active low.
module sevenseg (
    input  logic        clk,
    input  logic [15:0] value,
    input  logic        dots,
    output logic [6:0]  seg,
    output logic        dp,
    output logic [3:0]  an
);
    logic [18:0] refresh = 0;
    always_ff @(posedge clk) refresh <= refresh + 1;

    logic [1:0] digit;
    logic [3:0] nibble;
    assign digit  = refresh[18:17];
    assign nibble = value[digit*4 +: 4];
    assign an     = ~(4'b0001 << digit);
    assign dp     = ~dots;

    always_comb case (nibble) //  gfedcba
        4'h0: seg = 7'b1000000;
        4'h1: seg = 7'b1111001;
        4'h2: seg = 7'b0100100;
        4'h3: seg = 7'b0110000;
        4'h4: seg = 7'b0011001;
        4'h5: seg = 7'b0010010;
        4'h6: seg = 7'b0000010;
        4'h7: seg = 7'b1111000;
        4'h8: seg = 7'b0000000;
        4'h9: seg = 7'b0010000;
        4'hA: seg = 7'b0001000;
        4'hB: seg = 7'b0000011;
        4'hC: seg = 7'b1000110;
        4'hD: seg = 7'b0100001;
        4'hE: seg = 7'b0000110;
        default: seg = 7'b0001110;
    endcase
endmodule
