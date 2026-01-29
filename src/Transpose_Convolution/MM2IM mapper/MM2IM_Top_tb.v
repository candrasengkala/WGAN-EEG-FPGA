`timescale 1ns/1ps
`include "MM2IM_Top.v"

module MM2IM_Top_tb;

    parameter CLK_PERIOD = 10;

    // Clock & reset
    reg clk;
    reg rst_n;

    // Control
    reg        start;
    reg [8:0]  row_id;
    reg [5:0]  tile_id;
    reg [1:0]  layer_id;
    reg [4:0]  done_PE;

    // Outputs from DUT
    wire [15:0]  cmap_snapshot;
    wire [223:0] omap_snapshot;
    wire         done;

    // ---------------------------------------------
    // DUT
    // ---------------------------------------------
    MM2IM_Top dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .start         (start),
        .row_id        (row_id),
        .tile_id       (tile_id),
        .layer_id      (layer_id),
        .done_PE       (done_PE),
        .cmap_snapshot (cmap_snapshot),
        .omap_snapshot (omap_snapshot),
        .done          (done)
    );

    // ---------------------------------------------
    // Clock generation
    // ---------------------------------------------
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // ---------------------------------------------
    // Helper signals for observation
    // ---------------------------------------------
    reg        cmap_bit;
    reg [3:0]  bram_sel;
    reg [9:0]  bram_addr;
    reg [13:0] omap_entry;

    // ---------------------------------------------
    // Test sequence
    // ---------------------------------------------
    initial begin
        // Init
        rst_n   = 0;
        start  = 0;
        row_id = 0;
        tile_id = 0;
        layer_id = 0;
        done_PE = 0;

        #(2*CLK_PERIOD);
        rst_n = 1;

        // -----------------------------------------
        // Configure test (d1)
        // -----------------------------------------
        row_id   = 9'd0;
        tile_id  = 6'd0;
        layer_id = 2'd0;

        // -----------------------------------------
        // Trigger mapper
        // -----------------------------------------
        #(CLK_PERIOD);
        start = 1;
        #(CLK_PERIOD);
        start = 0;

        // -----------------------------------------
        // Wait snapshot ready
        // -----------------------------------------
        wait (done == 1);
        $display("MM2IM snapshot ready");

        // -----------------------------------------
        // Sweep done_PE = 1..16
        // -----------------------------------------
        done_PE = 0;
        repeat (16) begin
            #(CLK_PERIOD);
            done_PE = done_PE + 1;

            // Extract snapshot entry
            cmap_bit  = cmap_snapshot[done_PE-1];
            omap_entry = omap_snapshot[(done_PE-1)*14 +: 14];
            bram_sel  = omap_entry[13:10];
            bram_addr = omap_entry[9:0];

            $display(
                "done_PE=%0d | cmap=%b | bram_sel=%0d | bram_addr=%0d",
                done_PE, cmap_bit, bram_sel, bram_addr
            );
        end

        #(5*CLK_PERIOD);
        $finish;
    end

    // ---------------------------------------------
    // Dump waves
    // ---------------------------------------------
    initial begin
        $dumpfile("MM2IM_Top.vcd");
        $dumpvars(0, MM2IM_Top_tb);
    end

endmodule
