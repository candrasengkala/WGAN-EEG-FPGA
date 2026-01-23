`timescale 1ns/1ps

module tb_counter_axon_addr;

    // ----------------------------------------
    // Parameters
    // ----------------------------------------
    localparam ADDRESS_LENGTH = 13;
    localparam MAX_COUNT      = 512;

    // ----------------------------------------
    // DUT signals
    // ----------------------------------------
    reg clk;
    reg rst;
    reg en;

    wire flag_1per16;
    wire done;
    wire [ADDRESS_LENGTH-1:0] addr_out;

    // ----------------------------------------
    // DUT
    // ----------------------------------------
    counter_axon_addr_inputdata #(
        .ADDRESS_LENGTH(ADDRESS_LENGTH),
        .MAX_COUNT(MAX_COUNT)
    ) dut (
        .clk(clk),
        .rst(rst),
        .en(en),
        .flag_1per16(flag_1per16),
        .addr_out(addr_out),
        .done(done)
    );

    // ----------------------------------------
    // Clock (100 MHz)
    // ----------------------------------------
    always #5 clk = ~clk;

    // ----------------------------------------
    // Stimulus
    // ----------------------------------------
    initial begin
        $dumpfile("counter_axon_addr.vcd");
        $dumpvars(0, tb_counter_axon_addr);

        // init
        clk = 0;
        rst = 0;
        en  = 0;

        // -------------------------
        // Apply reset
        // -------------------------
        #20;
        rst = 1;

        // -------------------------
        // Start counting
        // -------------------------
        #10;
        en = 1;

        // Run past terminal (hold)
        #(MAX_COUNT * 2 * 10);

        // -------------------------
        // Apply reset again
        // -------------------------
        $display("Applying reset after done...");
        en  = 0;
        rst = 0;
        #20;
        rst = 1;
        #10;
        en  = 1;

        // Run again to ensure restart
        #(MAX_COUNT * 2 * 10);

        $display("TEST PASSED");
        $finish;
    end

    // ----------------------------------------
    // Self-check logic
    // ----------------------------------------
    reg done_seen;
    reg [ADDRESS_LENGTH-1:0] terminal_addr;

    always @(posedge clk) begin
        if (!rst) begin
            done_seen     <= 1'b0;
            terminal_addr <= {ADDRESS_LENGTH{1'b0}};
        end
        else if (en) begin

            // --------------------------------
            // Every-16 pulse check (before done)
            // --------------------------------
            if (!done_seen) begin
                if ((addr_out & 4'b1111) == 4'b1111) begin
                    if (!flag_1per16) begin
                        $display(
                            "ERROR @ %0t: missing flag_1per16 at addr_out=%0d",
                            $time, addr_out
                        );
                        $stop;
                    end
                end
                else if (flag_1per16) begin
                    $display(
                        "ERROR @ %0t: early flag_1per16 at addr_out=%0d",
                        $time, addr_out
                    );
                    $stop;
                end
            end

            // --------------------------------
            // Terminal detection
            // --------------------------------
            if (addr_out == MAX_COUNT - 1 && !done_seen) begin
                if (!done) begin
                    $display(
                        "ERROR @ %0t: done missing at terminal",
                        $time
                    );
                    $stop;
                end
                done_seen     <= 1'b1;
                terminal_addr <= addr_out;
            end

            // --------------------------------
            // Hold-after-terminal check
            // --------------------------------
            if (done_seen) begin
                if (addr_out != terminal_addr) begin
                    $display(
                        "ERROR @ %0t: addr_out changed after terminal",
                        $time
                    );
                    $stop;
                end
                if (flag_1per16) begin
                    $display(
                        "ERROR @ %0t: flag_1per16 asserted after done",
                        $time
                    );
                    $stop;
                end
            end
        end
    end

endmodule
