`timescale 1ns/1ps

module tb_counter_axon_addr_weight;

    localparam ADDRESS_LENGTH = 8;
    localparam MAX_COUNT      = 64;

    reg clk;
    reg rst;
    reg rst_min_16;
    reg en;

    wire flag_1per16;
    wire [ADDRESS_LENGTH-1:0] addr_out;
    wire done;

    counter_axon_addr_weight #(
        .ADDRESS_LENGTH(ADDRESS_LENGTH),
        .MAX_COUNT(MAX_COUNT)
    ) dut (
        .clk(clk),
        .rst(rst),
        .rst_min_16(rst_min_16),
        .en(en),
        .flag_1per16(flag_1per16),
        .addr_out(addr_out),
        .done(done)
    );

    // 10 ns clock
    always #5 clk = ~clk;

    initial begin
        // -------- VCD (THIS WAS MISSING) --------
        $dumpfile("counter.vcd");
        $dumpvars(0, tb_counter_axon_addr_weight);

        // -------- INIT --------
        clk        = 0;
        rst        = 0;
        rst_min_16 = 0;
        en         = 0;

        // -------- RESET --------
        #12;
        rst = 1;
        en  = 1;

        // -------- SNAP --------
        wait (flag_1per16 == 1);
        @(negedge clk);
        rst_min_16 = 1;
        @(negedge clk);
        rst_min_16 = 0;

        // -------- RUN TO DONE --------
        while (!done)
            @(negedge clk);

        #20;
        $finish;
    end

endmodule
