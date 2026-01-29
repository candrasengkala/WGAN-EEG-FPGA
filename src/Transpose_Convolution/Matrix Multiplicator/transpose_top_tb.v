`timescale 1ns / 1ps
`include "Transpose_top.v"

//////////////////////////////////////////////////////////////////////////////////
// Testbench: transpose_top_tb
// Description: Testbench dengan memory-based wavefront scheduling
// 
// WAVEFRONT PATTERN:
// - Phase 0: PE[0] loads data[0]
// - Phase 1: PE[0] loads data[1], PE[1] loads data[0]
// - Phase 2: PE[0] loads data[2], PE[1] loads data[1], PE[2] loads data[0]
// - Phase P: PE[i] loads data[P-i] (for i <= P)
//
// DATA ORGANIZATION:
// - Ifmap: sama untuk semua PE (sequence 1, 2, 3, ...)
// - Weight: setiap PE punya nilai berbeda
//   * PE[0]: semua 1
//   * PE[1]: semua 2
//   * PE[2]: semua 3
//   * PE[i]: semua (i+1)
//////////////////////////////////////////////////////////////////////////////////

module transpose_top_tb;
    // Parameters
    parameter DW = 16;
    parameter Dimension = 16;
    parameter CLK_PERIOD = 10;
    parameter NUM_ITER = 3;  // Small value untuk debug
    
    // Clock & Reset
    reg clk;
    reg rst_n;
    
    // Control signals
    reg start;
    reg [7:0] Instruction_code;
    reg [8:0] num_iterations;  // 9-bit untuk support 256
    
    // Input data (packed)
    reg signed [DW*Dimension-1:0] weight_in;
    reg signed [DW*Dimension-1:0] ifmap_in;
    
    // Output
    wire signed [DW-1:0] result_out;
    wire [4:0] done;
    wire [7:0] iter_count;
    wire [3:0] col_id;
    wire partial_valid;
    
    // Memory untuk test data
    reg signed [DW-1:0] weight_mem [0:15][0:NUM_ITER-1];  // [PE][iteration]
    reg signed [DW-1:0] ifmap_mem [0:NUM_ITER-1];         // [iteration]
    
    // Loop variables
    integer i, j, k;
    integer cycle_count;
    
    // ============================================================
    // DUT Instantiation
    // ============================================================
    Transpose_top #(
        .DW(DW),
        .Dimension(Dimension)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .Instruction_code(Instruction_code),
        .num_iterations(num_iterations),
        .weight_in(weight_in),
        .ifmap_in(ifmap_in),
        .result_out(result_out),
        .done(done),
        .iter_count(iter_count),
        .col_id(col_id),
        .partial_valid(partial_valid)
    );
    
    // ============================================================
    // Clock Generation
    // ============================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // ============================================================
    // Initialize Memory - BERAGAM PER PE
    // ============================================================
    initial begin
        // Ifmap: sama untuk semua PE (1, 2, 3, ...)
        for (i = 0; i < NUM_ITER; i = i + 1) begin
            ifmap_mem[i] = i + 1;
        end
        
        // Weight: BERAGAM per PE
        // PE[0]: semua 1
        // PE[1]: semua 2
        // PE[i]: semua (i+1)
        for (i = 0; i < 16; i = i + 1) begin
            for (j = 0; j < NUM_ITER; j = j + 1) begin
                weight_mem[i][j] = i + 1;  // PE[i] selalu bernilai (i+1)
            end
        end
        
        $display("========================================");
        $display("MEMORY INITIALIZATION:");
        $display("========================================");
        $display("Ifmap (shared): %0d, %0d, %0d", ifmap_mem[0], ifmap_mem[1], ifmap_mem[2]);
        for (i = 0; i < 16; i = i + 1) begin
            $display("PE[%2d] Weight: %0d, %0d, %0d (all=%0d)", 
                     i, weight_mem[i][0], weight_mem[i][1], weight_mem[i][2], i+1);
        end
        $display("========================================");
    end
    
    // ============================================================
    // Data Generation - WAVEFRONT PATTERN (registered di negedge untuk stable di posedge)
    // ============================================================
    wire [8:0] current_phase;
    assign current_phase = dut.fsm_inst.phase_counter;
    
    always @(negedge clk) begin
        // Initialize
        ifmap_in = {(DW*Dimension){1'b0}};
        weight_in = {(DW*Dimension){1'b0}};
        
        // Ifmap: PE[0] gets data based on current phase
        // Phase P → ifmap[P]
        if (current_phase < NUM_ITER) begin
            ifmap_in[DW-1 : 0] = ifmap_mem[current_phase];
        end
        
        // Weight: WAVEFRONT PATTERN
        // At phase P:
        //   PE[0] needs weight[0][P] 
        //   PE[1] needs weight[1][P-1]
        //   PE[2] needs weight[2][P-2]
        //   PE[i] needs weight[i][P-i] (if P >= i)
        for (k = 0; k < 16; k = k + 1) begin
            if (current_phase >= k && (current_phase - k) < NUM_ITER) begin
                weight_in[(k*DW) +: DW] = weight_mem[k][current_phase - k];
            end else begin
                weight_in[(k*DW) +: DW] = 16'd0;
            end
        end
    end
    
    // ============================================================
    // Main Test Stimulus
    // ============================================================
    initial begin
        // Waveform dump
        $dumpfile("transpose_top_tb.vcd");
        $dumpvars(0, transpose_top_tb);
        
        // Initialize signals
        rst_n = 0;
        start = 0;
        Instruction_code = 8'h00;
        num_iterations = 9'd0;
        
        // Reset
        #(CLK_PERIOD*5);
        rst_n = 1;
        
        // Configuration
        #(CLK_PERIOD*2);
        num_iterations = NUM_ITER;
        Instruction_code = 8'h03;
        #1;
        
        // Wait 2 cycles untuk config stable
        #(CLK_PERIOD*2);
        
        // Start FSM
        @(posedge clk);
        start = 1;
        
        @(posedge clk);
        start = 0;
        
        $display("[%0t] Starting simulation (num_iter=%0d)...", $time, num_iterations);
        
        // Wait for all PEs to complete
        wait(done == 16);
        
        $display("[%0t] All PE completed!", $time);
        
        // Print all PE results
        $display("========================================");
        $display("FINAL RESULTS:");
        $display("Expected: PE[i] = (i+1) * (1+2+3) = (i+1) * 6");
        $display("========================================");
        for (i = 0; i < 16; i = i + 1) begin
            case (i)
                0:  $display("  PE[%2d] = %5d | Expected = %5d | %s", i, $signed(dut.diagonal_out_packed[15:0]), (i+1)*6, ($signed(dut.diagonal_out_packed[15:0]) == (i+1)*6) ? "PASS" : "FAIL");
                1:  $display("  PE[%2d] = %5d | Expected = %5d | %s", i, $signed(dut.diagonal_out_packed[31:16]), (i+1)*6, ($signed(dut.diagonal_out_packed[31:16]) == (i+1)*6) ? "PASS" : "FAIL");
                2:  $display("  PE[%2d] = %5d | Expected = %5d | %s", i, $signed(dut.diagonal_out_packed[47:32]), (i+1)*6, ($signed(dut.diagonal_out_packed[47:32]) == (i+1)*6) ? "PASS" : "FAIL");
                3:  $display("  PE[%2d] = %5d | Expected = %5d | %s", i, $signed(dut.diagonal_out_packed[63:48]), (i+1)*6, ($signed(dut.diagonal_out_packed[63:48]) == (i+1)*6) ? "PASS" : "FAIL");
                4:  $display("  PE[%2d] = %5d | Expected = %5d | %s", i, $signed(dut.diagonal_out_packed[79:64]), (i+1)*6, ($signed(dut.diagonal_out_packed[79:64]) == (i+1)*6) ? "PASS" : "FAIL");
                5:  $display("  PE[%2d] = %5d | Expected = %5d | %s", i, $signed(dut.diagonal_out_packed[95:80]), (i+1)*6, ($signed(dut.diagonal_out_packed[95:80]) == (i+1)*6) ? "PASS" : "FAIL");
                6:  $display("  PE[%2d] = %5d | Expected = %5d | %s", i, $signed(dut.diagonal_out_packed[111:96]), (i+1)*6, ($signed(dut.diagonal_out_packed[111:96]) == (i+1)*6) ? "PASS" : "FAIL");
                7:  $display("  PE[%2d] = %5d | Expected = %5d | %s", i, $signed(dut.diagonal_out_packed[127:112]), (i+1)*6, ($signed(dut.diagonal_out_packed[127:112]) == (i+1)*6) ? "PASS" : "FAIL");
                8:  $display("  PE[%2d] = %5d | Expected = %5d | %s", i, $signed(dut.diagonal_out_packed[143:128]), (i+1)*6, ($signed(dut.diagonal_out_packed[143:128]) == (i+1)*6) ? "PASS" : "FAIL");
                9:  $display("  PE[%2d] = %5d | Expected = %5d | %s", i, $signed(dut.diagonal_out_packed[159:144]), (i+1)*6, ($signed(dut.diagonal_out_packed[159:144]) == (i+1)*6) ? "PASS" : "FAIL");
                10: $display("  PE[%2d] = %5d | Expected = %5d | %s", i, $signed(dut.diagonal_out_packed[175:160]), (i+1)*6, ($signed(dut.diagonal_out_packed[175:160]) == (i+1)*6) ? "PASS" : "FAIL");
                11: $display("  PE[%2d] = %5d | Expected = %5d | %s", i, $signed(dut.diagonal_out_packed[191:176]), (i+1)*6, ($signed(dut.diagonal_out_packed[191:176]) == (i+1)*6) ? "PASS" : "FAIL");
                12: $display("  PE[%2d] = %5d | Expected = %5d | %s", i, $signed(dut.diagonal_out_packed[207:192]), (i+1)*6, ($signed(dut.diagonal_out_packed[207:192]) == (i+1)*6) ? "PASS" : "FAIL");
                13: $display("  PE[%2d] = %5d | Expected = %5d | %s", i, $signed(dut.diagonal_out_packed[223:208]), (i+1)*6, ($signed(dut.diagonal_out_packed[223:208]) == (i+1)*6) ? "PASS" : "FAIL");
                14: $display("  PE[%2d] = %5d | Expected = %5d | %s", i, $signed(dut.diagonal_out_packed[239:224]), (i+1)*6, ($signed(dut.diagonal_out_packed[239:224]) == (i+1)*6) ? "PASS" : "FAIL");
                15: $display("  PE[%2d] = %5d | Expected = %5d | %s", i, $signed(dut.diagonal_out_packed[255:240]), (i+1)*6, ($signed(dut.diagonal_out_packed[255:240]) == (i+1)*6) ? "PASS" : "FAIL");
            endcase
        end
        $display("========================================");
        
        // End
        #(CLK_PERIOD*10);
        $finish;
    end
    
    // ============================================================
    // DISPLAY result_out SETIAP KALI ADA PERUBAHAN
    // ============================================================
    always @(posedge clk) begin
        if (rst_n) begin
            $display("[T=%0t] result_out=%0d | done=%0d | col_id=%0d | partial_valid=%b | phase=%0d", 
                     $time, $signed(result_out), done, col_id, partial_valid, current_phase);
        end
    end
    
    // ============================================================
    // Progress Monitor - Detail PE State
    // ============================================================
    initial begin
        wait(rst_n == 1);
        
        // Monitor phase 0
        @(posedge clk);
        wait(dut.fsm_inst.phase_counter == 0 && dut.fsm_inst.current_state == 3);
        @(posedge clk);
        $display("========================================");
        $display("PHASE 0:");
        $display("  PE[0]: ifmap=%0d, weight=%0d, psum=%0d", 
                 $signed(dut.systolic_array.pe_d_0.base_design.ifmap_reg),
                 $signed(dut.systolic_array.pe_d_0.base_design.weight_reg),
                 $signed(dut.systolic_array.pe_d_0.base_design.psum_reg));
        
        // Monitor phase 1
        wait(dut.fsm_inst.phase_counter == 1 && dut.fsm_inst.current_state == 3);
        @(posedge clk);
        $display("========================================");
        $display("PHASE 1:");
        $display("  PE[0]: ifmap=%0d, weight=%0d, psum=%0d", 
                 $signed(dut.systolic_array.pe_d_0.base_design.ifmap_reg),
                 $signed(dut.systolic_array.pe_d_0.base_design.weight_reg),
                 $signed(dut.systolic_array.pe_d_0.base_design.psum_reg));
        $display("  PE[1]: ifmap=%0d, weight=%0d, psum=%0d",
                 $signed(dut.systolic_array.GEN_DIAG[1].pe_d.base_design.ifmap_reg),
                 $signed(dut.systolic_array.GEN_DIAG[1].pe_d.base_design.weight_reg),
                 $signed(dut.systolic_array.GEN_DIAG[1].pe_d.base_design.psum_reg));
        
        // Monitor phase 2
        wait(dut.fsm_inst.phase_counter == 2 && dut.fsm_inst.current_state == 3);
        @(posedge clk);
        $display("========================================");
        $display("PHASE 2:");
        $display("  PE[0]: ifmap=%0d, weight=%0d, psum=%0d", 
                 $signed(dut.systolic_array.pe_d_0.base_design.ifmap_reg),
                 $signed(dut.systolic_array.pe_d_0.base_design.weight_reg),
                 $signed(dut.systolic_array.pe_d_0.base_design.psum_reg));
        $display("  PE[1]: ifmap=%0d, weight=%0d, psum=%0d",
                 $signed(dut.systolic_array.GEN_DIAG[1].pe_d.base_design.ifmap_reg),
                 $signed(dut.systolic_array.GEN_DIAG[1].pe_d.base_design.weight_reg),
                 $signed(dut.systolic_array.GEN_DIAG[1].pe_d.base_design.psum_reg));
        $display("  PE[2]: ifmap=%0d, weight=%0d, psum=%0d",
                 $signed(dut.systolic_array.GEN_DIAG[2].pe_d.base_design.ifmap_reg),
                 $signed(dut.systolic_array.GEN_DIAG[2].pe_d.base_design.weight_reg),
                 $signed(dut.systolic_array.GEN_DIAG[2].pe_d.base_design.psum_reg));
        $display("========================================");
    end
    
    // ============================================================
    // Timeout Watchdog
    // ============================================================
    initial begin
        #(CLK_PERIOD * 1000);
        if (done != 16) begin
            $display("ERROR: Timeout!");
            $finish;
        end
    end

endmodule