`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 01/16/2026 01:57:00 PM
// Design Name: 
// Module Name: top_level_complete_tb
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


`timescale 1ns/1ps

module tb_top_lvl_io_control;

    /* ============================================================
     * Parameters
     * ============================================================ */
    localparam DW        = 16;
    localparam Dimension = 4;   // keep small for simulation
    localparam Input_length = 10;
    localparam Stride = 2;

    /* ============================================================
     * DUT signals
     * ============================================================ */
    reg clk;
    reg rst;
    reg start;
    reg output_val;
    reg mode;

    reg  signed [Dimension*DW-1:0] weight_brams_in;
    reg  signed [DW-1:0] ifmap_serial_in;

    reg [Dimension-1 : 0] en_shift_reg_ifmap_input;
    reg [Dimension-1 : 0] en_shift_reg_weight_input;
    reg [Dimension : 0] en_shift_reg_ifmap_input_bayangan; 
    wire out_new_val;
    wire done_count;
    wire done_all;

    wire signed [DW*Dimension-1:0] output_out;
    always @(*) begin
        en_shift_reg_ifmap_input = en_shift_reg_ifmap_input_bayangan[Dimension : 1]; // Must be kept like this. 
    end
    /* ============================================================
     * Clock generation
     * ============================================================ */
    always #5 clk = ~clk; // 100 MHz

    /* ============================================================
     * DUT
     * ============================================================ */
    top_lvl_io_control #(
        .DW(DW),
        .Dimension(Dimension)
    ) dut (
        .clk                    (clk),
        .rst                    (rst),
        .start                  (start),
        .output_val             (output_val),

        .weight_brams_in       (weight_brams_in),
        .ifmap_serial_in        (ifmap_serial_in),

        .en_shift_reg_ifmap_input (en_shift_reg_ifmap_input),
        .en_shift_reg_weight_input(en_shift_reg_weight_input),
        .mode                   (mode), // NOL UNTUK MENULIS DARI LUAR.

        .out_new_val            (out_new_val),
        .done_count             (done_count),
        .done_all               (done_all),

        .output_out             (output_out)
    );

    /* ============================================================
     * Test vectors
     * ============================================================ */

    reg signed [DW-1:0] weight_vec_1 [0:Dimension-1];
    reg signed [DW-1:0] weight_vec_2 [0:Dimension-1];
    reg signed [DW-1:0] weight_vec_3 [0:Dimension-1];
    reg signed [DW-1:0] weight_vec_4 [0:Dimension-1];

    reg signed [DW-1:0] ifmap_vec  [0:Input_length-1];

    /* ============================================================
     * Test sequence
     * ============================================================ */
    initial begin
        
        /* ---------------- init ---------------- */
        clk  = 0;
        rst  = 0;
        start = 0;
        output_val = 0;
        mode = 0;

        en_shift_reg_ifmap_input_bayangan  = 0;
        en_shift_reg_weight_input = 0;

        weight_brams_in = {Dimension*DW{1'b0}};
        ifmap_serial_in  = 16'b0;

        /* ---------------- reset ---------------- */
        #20;
        rst = 1;
        #20;

        /* ========================================================
         * Initialize input vectors
         * ======================================================== */
        weight_vec_1[0] = 16'sd1;
        weight_vec_1[1] = 16'sd2;
        weight_vec_1[2] = 16'sd3;
        weight_vec_1[3] = 16'sd4;
    
        weight_vec_2[0] = 16'sd2;
        weight_vec_2[1] = 16'sd3;
        weight_vec_2[2] = 16'sd4;
        weight_vec_2[3] = 16'sd5;

        weight_vec_3[0] = 16'sd3;
        weight_vec_3[1] = 16'sd4;
        weight_vec_3[2] = 16'sd3;
        weight_vec_3[3] = 16'sd2;

        weight_vec_4[0] = 16'sd4;
        weight_vec_4[1] = 16'sd3;
        weight_vec_4[2] = 16'sd2;
        weight_vec_4[3] = 16'sd4;

        ifmap_vec[0]  = 16'sd5;
        ifmap_vec[1]  = 16'sd5;
        ifmap_vec[2]  = 16'sd4;
        ifmap_vec[3]  = 16'sd8;
        ifmap_vec[4]  = 16'sd7;
        ifmap_vec[5]  = 16'sd6;
        ifmap_vec[6]  = 16'sd5;
        ifmap_vec[7]  = 16'sd4;
        ifmap_vec[8]  = 16'sd3;
        ifmap_vec[9]  = 16'sd2;

        /* ========================================================
         * INPUT PHASE (manual shift)
         * ======================================================== */
//        @(posedge clk); //Wait for one posedge biar pas lmao.
        $display("=== INPUT PHASE ===");
        mode = 0;
        // COUNTER-DATA-INPUT MODEL.
        // Remember that clock for shift register is negative edge.
        fork 
            begin : WEIGHT_IN_BRAM // PADDING TERJADI DI SINI.
                integer i;
                for (i = 0; i < Dimension; i = i + 1) begin
                    @(posedge clk);
                        if (i == 0) begin
                            en_shift_reg_weight_input = {Dimension{1'b1}};
                        end
                        weight_brams_in = {weight_vec_4[i], weight_vec_3[i], weight_vec_2[i], weight_vec_1[i]};
                end
                // Nol-kan input terakhir. Dilakukannya di shift register saja.
                @(posedge clk);
                weight_brams_in = {Dimension*DW{1'b0}}; 
                @(posedge clk); // Disable shifting
                en_shift_reg_weight_input = 0;
            end
            begin : IMPLICIT_IM2COL
                integer i;
                integer stride_cnt;
                reg first_phase;   // <-- explicit phase offset

                stride_cnt  = 0;
                first_phase = 1'b1;

                for (i = 0; i < Input_length; i = i + 1) begin
                    @(posedge clk);

                    // Initialize enable pattern once
                    if (i == 0) begin
                        en_shift_reg_ifmap_input_bayangan
                            = {{(Dimension-1){1'b0}}, 1'b1, 1'b1};
                    end

                    // Feed input
                    ifmap_serial_in = ifmap_vec[i];

                    // ----- stride + phase logic -----
                    if (first_phase) begin
                        // consume first tighter window WITHOUT shifting
                        first_phase = 1'b0;
                    end
                    else if (stride_cnt == Stride-1) begin
                        en_shift_reg_ifmap_input_bayangan
                            = en_shift_reg_ifmap_input_bayangan << 1;
                        stride_cnt = 0;
                    end
                    else begin
                        stride_cnt = stride_cnt + 1;
                    end
                end

                // Flush pipeline
                @(posedge clk);
                en_shift_reg_ifmap_input_bayangan = {Dimension+1{1'b1}};
                ifmap_serial_in = 0;

                @(posedge clk);
                en_shift_reg_ifmap_input_bayangan = 0;
            end
        join
        @(posedge clk); // Negative edge
        /* ========================================================
         * COMPUTE PHASE
         * ======================================================== */
        $display("=== COMPUTE PHASE ===");
        mode = 1;

        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;
//lihat nilai ke6.
        /* ========================================================
         * WAIT FOR COMPLETION. Then, eject output.
         * ======================================================== */
        wait(done_count == 1'b1);
        output_val = 1'b1; // Output Value.
        wait(done_all == 1'b1);
        $finish;
    end
    integer r;
    always @(posedge clk) begin
        if (output_val && out_new_val) begin
            $display("---- OUTPUT ROWS @ t=%0t ----", $time);
            for (r = 0; r < Dimension; r = r + 1) begin
                $display(
                    "Row %0d : %0d",
                    r,
                    $signed(output_out[DW*(r+1)-1 -: DW])
                );
            end
            $display("-----------------------------");
        end
    end
endmodule
