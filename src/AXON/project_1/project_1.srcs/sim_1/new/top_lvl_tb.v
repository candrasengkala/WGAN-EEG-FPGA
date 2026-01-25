`timescale 1ns / 1ps

module top_lvl_tb;

    // ============================================================
    // PARAMETERS
    // ============================================================
    parameter DW        = 16;
    parameter Dimension = 16;

    // ============================================================
    // SIGNALS
    // ============================================================
    reg clk;
    reg rst;
    reg en_cntr;

    reg [Dimension*Dimension-1:0] en_in;
    reg [Dimension*Dimension-1:0] en_out;
    reg [Dimension*Dimension-1:0] en_psum;

    reg [Dimension-1:0] ifmaps_sel;
    reg [Dimension-1:0] output_eject_ctrl;

    reg signed [DW*Dimension-1:0] weight_in;
    reg signed [DW*Dimension-1:0] ifmap_in;

    wire signed [DW*Dimension-1:0] output_out;
    wire done_count;

    // ============================================================
    // DUT
    // ============================================================
    top_lvl #(
        .DW(DW),
        .Dimension(Dimension)
    ) dut (
        .clk(clk),
        .rst(rst),
        .en_cntr(en_cntr),
        .en_in(en_in),
        .en_out(en_out),
        .en_psum(en_psum),
        .ifmaps_sel(ifmaps_sel),
        .output_eject_ctrl(output_eject_ctrl),
        .weight_in(weight_in),
        .ifmap_in(ifmap_in),
        .done_count(done_count),
        .output_out(output_out)
    );

    // ============================================================
    // CLOCK
    // ============================================================
    initial begin
        clk = 1'b1;
        forever #5 clk = ~clk;
    end

    // ============================================================
    // MATRICES
    // ============================================================
    integer r, c;

    reg signed [DW-1:0] A [0:Dimension-1][0:Dimension-1];
    reg signed [DW-1:0] B [0:Dimension-1][0:Dimension-1];

    // ============================================================
    // INIT
    // ============================================================
    initial begin
        rst = 1'b1;
        en_cntr = 1'b1;

        en_in   = {Dimension*Dimension{1'b1}};
        en_out  = {Dimension*Dimension{1'b1}};
        en_psum = {Dimension*Dimension{1'b1}};

        ifmaps_sel = {Dimension{1'b1}};
        output_eject_ctrl = {Dimension{1'b0}};

        weight_in = {DW*Dimension{1'b0}};
        ifmap_in  = {DW*Dimension{1'b0}};
    end

    // ============================================================
    // MATRIX VALUES
    // ============================================================
    initial begin
        // A = incremental values
        // B = all ones
        for (r = 0; r < Dimension; r = r + 1) begin
            for (c = 0; c < Dimension; c = c + 1) begin
                B[r][c] = r*Dimension + c + 1;
                A[r][c] = 16'sd1;
            end
        end
    end

    // ============================================================
    // INPUT STREAMING (NEGATIVE EDGE)
    // ============================================================
    initial begin
        for (c = Dimension-1; c >= 0; c = c - 1) begin
            @(negedge clk);

            // COLUMN of B - Fixed indexing
            for (r = 0; r < Dimension; r = r + 1) begin
                ifmap_in[DW*(r+1)-1 -: DW] = B[r][c];
            end

            // ROW of A - Fixed indexing
            for (r = 0; r < Dimension; r = r + 1) begin
                weight_in[DW*(r+1)-1 -: DW] = A[c][r];
            end
        end

        @(negedge clk);
        ifmap_in  = {DW*Dimension{1'b0}};
        weight_in = {DW*Dimension{1'b0}};
    end

    // ============================================================
    // OUTPUT EJECTION
    // ============================================================
    integer i;
    integer row_num;

    initial begin
        row_num = 0;
        
        @(posedge done_count);
        $display("\n=== OUTPUT EJECTION STARTED ===\n");

        // For Dimension=16 -> 16'b1111_1111_1111_1110
        output_eject_ctrl = {{(Dimension-1){1'b1}}, 1'b0};

        for (i = 0; i < Dimension; i = i + 1) begin
            repeat (Dimension) @(posedge clk);
            
            // Print the row that was just ejected
            $display("Row %2d:", row_num);
            for (r = 0; r < Dimension; r = r + 1) begin
                $display("  out[%2d] = %0d", r, $signed(output_out[DW*(r+1)-1 -: DW]));
            end
            $display("");
            
            row_num = row_num + 1;
            output_eject_ctrl = output_eject_ctrl << 1;
        end
        
        // Add finish
        repeat(10) @(posedge clk);
        $display("=== SIMULATION COMPLETE ===");
        $finish;
    end

    // ============================================================
    // WAVEFORM DUMP
    // ============================================================
    initial begin
        $dumpfile("top_lvl_tb.vcd");
        $dumpvars(0, top_lvl_tb);
        $display("=== TESTBENCH START ===");
        $display("DW=%0d, Dimension=%0d", DW, Dimension);
    end

endmodule