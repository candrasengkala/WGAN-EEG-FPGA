`timescale 1ns/1ps

module tb_counter_bram;

    // ----------------------------------------
    // Parameters
    // ----------------------------------------
    localparam DW             = 16;
    localparam ADDRESS_LENGTH = 13;
    localparam DEPTH          = 8192;
    localparam MAX_COUNT      = 512;

    // ----------------------------------------
    // Clock / control
    // ----------------------------------------
    reg clk;
    reg rst;
    reg en;
    wire negclk;
    // ----------------------------------------
    // Counter outputs
    // ----------------------------------------
    wire [ADDRESS_LENGTH-1:0] addr_out;
    wire flag_1per16;
    wire done;
    assign negclk = ~clk;
    // ----------------------------------------
    // BRAM output
    // ----------------------------------------
    wire [DW-1:0] dob;

    // ----------------------------------------
    // Counter
    // ----------------------------------------
    counter_axon_addr #(
        .ADDRESS_LENGTH(ADDRESS_LENGTH),
        .MAX_COUNT(MAX_COUNT)
    ) counter_u (
        .clk(negclk),
        .rst(rst),
        .en(en),
        .flag_1per16(flag_1per16),
        .addr_out(addr_out),
        .done(done)
    );

    // ----------------------------------------
    // BRAM (read-only)
    // ----------------------------------------
    simple_dual_two_clocks #(
        .DW(DW),
        .ADDRESS_LENGTH(ADDRESS_LENGTH),
        .DEPTH(DEPTH)
    ) bram_u (
        .clka(clk),
        .clkb(clk),
        .ena(1'b0),
        .enb(1'b1),
        .wea(1'b0),
        .addra({(ADDRESS_LENGTH){1'b0}}),
        .addrb({addr_out}),   // zero-extend address
        .dia({DW{1'b0}}),
        .dob(dob)
    );

    // ----------------------------------------
    // Clock (100 MHz)
    // ----------------------------------------
    always #5 clk = ~clk;

    // ----------------------------------------
    // BRAM initialization
    // ----------------------------------------
    integer i;
    initial begin
        for (i = 0; i < DEPTH; i = i + 1)
            bram_u.ram[i] = i[DW-1:0];
    end

    // ----------------------------------------
    // Stimulus
    // ----------------------------------------
    initial begin
        $dumpfile("counter_bram_tb.vcd");
        $dumpvars(0, tb_counter_bram);

        clk = 0;
        rst = 0;
        en  = 0;

        // reset
        #20 rst = 1;

        // start counter
        #10 en = 1;

        // run
        #(MAX_COUNT * 2 * 10);

        $finish;
    end

endmodule
