`timescale 1ns/1ps
`include "Counter_Weight_BRAM.v"

module Weight_BRAM_Controller_tb;

    parameter CLK_PERIOD = 10;

    // ---------------------------------
    // DUT signals
    // ---------------------------------
    reg         clk;
    reg         rst_n;
    reg         start;
    reg  [8:0]  addr_start;
    reg  [8:0]  addr_end;

    wire [15:0]  w_en;
    wire [143:0] w_addr_rd_flat;
    wire         done;

    // ---------------------------------
    // DUT
    // ---------------------------------
    Weight_BRAM_Controller dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .start          (start),
        .addr_start     (addr_start),
        .addr_end       (addr_end),
        .w_en           (w_en),
        .w_addr_rd_flat (w_addr_rd_flat),
        .done           (done)
    );

    // ---------------------------------
    // CLOCK
    // ---------------------------------
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // ---------------------------------
    // SPLIT SIGNALS (TESTBENCH ONLY)
    // ---------------------------------
    wire w_en_0  = w_en[0];
    wire w_en_1  = w_en[1];
    wire w_en_2  = w_en[2];
    wire w_en_3  = w_en[3];
    wire w_en_4  = w_en[4];
    wire w_en_5  = w_en[5];
    wire w_en_6  = w_en[6];
    wire w_en_7  = w_en[7];
    wire w_en_8  = w_en[8];
    wire w_en_9  = w_en[9];
    wire w_en_10 = w_en[10];
    wire w_en_11 = w_en[11];
    wire w_en_12 = w_en[12];
    wire w_en_13 = w_en[13];
    wire w_en_14 = w_en[14];
    wire w_en_15 = w_en[15];

    wire [8:0] w_addr_0  = w_addr_rd_flat[  8:  0];
    wire [8:0] w_addr_1  = w_addr_rd_flat[ 17:  9];
    wire [8:0] w_addr_2  = w_addr_rd_flat[ 26: 18];
    wire [8:0] w_addr_3  = w_addr_rd_flat[ 35: 27];
    wire [8:0] w_addr_4  = w_addr_rd_flat[ 44: 36];
    wire [8:0] w_addr_5  = w_addr_rd_flat[ 53: 45];
    wire [8:0] w_addr_6  = w_addr_rd_flat[ 62: 54];
    wire [8:0] w_addr_7  = w_addr_rd_flat[ 71: 63];
    wire [8:0] w_addr_8  = w_addr_rd_flat[ 80: 72];
    wire [8:0] w_addr_9  = w_addr_rd_flat[ 89: 81];
    wire [8:0] w_addr_10 = w_addr_rd_flat[ 98: 90];
    wire [8:0] w_addr_11 = w_addr_rd_flat[107: 99];
    wire [8:0] w_addr_12 = w_addr_rd_flat[116:108];
    wire [8:0] w_addr_13 = w_addr_rd_flat[125:117];
    wire [8:0] w_addr_14 = w_addr_rd_flat[134:126];
    wire [8:0] w_addr_15 = w_addr_rd_flat[143:135];

    // ---------------------------------
    // TEST SEQUENCE
    // ---------------------------------
    integer cycle;

    initial begin
        rst_n = 0;
        start = 0;
        addr_start = 9'd128;
        addr_end   = 9'd255;
        cycle = 0;

        #(2*CLK_PERIOD);
        rst_n = 1;

        #(CLK_PERIOD);
        start = 1;
        #(CLK_PERIOD);
        start = 0;

        // RUN
        while (!done && cycle < 300) begin
            #(CLK_PERIOD);
            cycle = cycle + 1;

            $display(
              "T=%0d | EN=%b | A0=%0d A1=%0d A2=%0d A3=%0d",
              cycle,
              w_en,
              w_addr_0,
              w_addr_1,
              w_addr_2,
              w_addr_3
            );
        end

        if (!done)
            $display("❌ ERROR: DONE NOT ASSERTED");
        else
            $display("✅ DONE at cycle %0d", cycle);

        #(5*CLK_PERIOD);
        $finish;
    end

    // ---------------------------------
    // WAVES
    // ---------------------------------
    initial begin
        $dumpfile("weight_ctrl.vcd");
        $dumpvars(0, Weight_BRAM_Controller_tb);
    end

endmodule
