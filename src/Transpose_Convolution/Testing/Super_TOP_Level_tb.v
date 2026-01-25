/******************************************************************************
 * Module: Super_TOP_Level_tb
 * 
 * Description:
 *   Testbench for Super_TOP_Level transposed convolution accelerator.
 *   Tests complete system with simple pattern for verification.
 * 
 * Test Pattern:
 *   - Weight BRAM[i]: All addresses = i+1 (constant per BRAM)
 *   - Ifmap: [1,2,3,1,2,3,...] pattern
 *   - Expected PE[i] = i * (1+2+3) = 6*i
 * 
 * Features:
 *   - Weight and ifmap BRAM initialization
 *   - MM2IM mapper configuration (row_id=0, tile_id=0, layer=d3)
 *   - FSM control sequencing
 *   - Output BRAM result verification
 *   - Real-time monitoring of PE outputs and BRAM writes
 * 
 * Expected Results:
 *   BRAM[0]: [12, 18, 24]  (PE[1,2,3])
 *   BRAM[1]: [36, 42, 48]  (PE[5,6,7])
 *   BRAM[2]: [60, 66, 72]  (PE[9,10,11])
 *   BRAM[3]: [84, 90, 96]  (PE[13,14,15])
 * 
 * Parameters:
 *   CLK_PERIOD - Clock period in ns (default: 10)
 * 
 * Author: Dharma Anargya Jowandy
 * Date: January 2026
 ******************************************************************************/

`timescale 1ns/1ps
`include "Super_TOP_Level.v"

module Super_TOP_Level_tb;

    parameter CLK_PERIOD = 10;

    reg clk, rst_n;
    
    reg start_ifmap, start_weight, start_transpose, start_Mapper;
    
    reg         ext_read_mode;
    reg  [143:0] ext_read_addr_flat;
    wire [255:0] bram_read_data_flat;
    wire [143:0] bram_read_addr_flat;
    
    reg [8:0] if_addr_start, if_addr_end;
    reg [3:0] ifmap_sel_in;
    reg [8:0] addr_start, addr_end;
    reg [7:0] Instruction_code_transpose;
    reg [8:0] num_iterations;
    reg [8:0] row_id;
    reg [5:0] tile_id;
    reg [1:0] layer_id;
    
    reg [15:0] w_we, if_we;
    reg [143:0] w_addr_wr_flat, if_addr_wr_flat;
    reg [255:0] w_din_flat, if_din_flat;
    
    wire if_done, done_weight, done_mapper;
    wire [7:0] iter_count;
    wire [4:0] done_transpose;
    
    integer i, j;
    
    Super_TOP_Level dut (
        .clk(clk), .rst_n(rst_n),
        .if_addr_start(if_addr_start), .if_addr_end(if_addr_end),
        .ifmap_sel_in(ifmap_sel_in), .start_ifmap(start_ifmap), .if_done(if_done),
        .addr_start(addr_start), .addr_end(addr_end),
        .start_weight(start_weight), .done_weight(done_weight),
        .w_we(w_we), .w_addr_wr_flat(w_addr_wr_flat), .w_din_flat(w_din_flat),
        .if_we(if_we), .if_addr_wr_flat(if_addr_wr_flat), .if_din_flat(if_din_flat),
        .start_transpose(start_transpose),
        .Instruction_code_transpose(Instruction_code_transpose),
        .num_iterations(num_iterations),
        .iter_count(iter_count), .done_transpose(done_transpose),
        .start_Mapper(start_Mapper), .row_id(row_id),
        .tile_id(tile_id), .layer_id(layer_id), .done_mapper(done_mapper),
        .ext_read_mode(ext_read_mode),
        .ext_read_addr_flat(ext_read_addr_flat),
        .bram_read_data_flat(bram_read_data_flat),
        .bram_read_addr_flat(bram_read_addr_flat)
    );
    
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    wire [15:0] bram_data [0:15];
    genvar gv;
    generate
        for (gv = 0; gv < 16; gv = gv + 1) begin : UNPACK
            assign bram_data[gv] = bram_read_data_flat[gv*16 +: 16];
        end
    endgenerate
    
    initial begin
        $display("========================================");
        $display("SIMPLE PATTERN TEST");
        $display("========================================");
        
        rst_n = 0;
        start_ifmap = 0; start_weight = 0;
        start_transpose = 0; start_Mapper = 0;
        ext_read_mode = 0;
        ext_read_addr_flat = 144'd0;
        
        if_addr_start = 9'd0; if_addr_end = 9'd15;
        ifmap_sel_in = 4'd0;
        addr_start = 9'd0; addr_end = 9'd15;
        Instruction_code_transpose = 8'h03;
        num_iterations = 9'd3;
        
        row_id = 9'd0; tile_id = 6'd0; layer_id = 2'd2;
        
        w_we = 0; if_we = 0;
        w_addr_wr_flat = 0; if_addr_wr_flat = 0;
        w_din_flat = 0; if_din_flat = 0;
        
        #(CLK_PERIOD*5);
        rst_n = 1;
        #(CLK_PERIOD*2);
        
        $display("\n========================================");
        $display("WEIGHT FILL - SIMPLE PER-BRAM PATTERN");
        $display("========================================");
        $display("BRAM[0]:  ALL addresses = 1");
        $display("BRAM[1]:  ALL addresses = 2");
        $display("BRAM[2]:  ALL addresses = 3");
        $display("...");
        $display("BRAM[15]: ALL addresses = 16");
        
        // Fill weight - Each BRAM has constant value
        for (i = 0; i < 16; i = i + 1) begin
            @(posedge clk);
            w_we = 16'hFFFF;
            for (j = 0; j < 16; j = j + 1) begin
                w_addr_wr_flat[j*9 +: 9] = i;
                // BRAM[j] = j+1 (constant for all addresses)
                w_din_flat[j*16 +: 16] = (j + 1);
            end
        end
        @(posedge clk);
        w_we = 16'd0;
        
        $display("\n========================================");
        $display("IFMAP FILL - PATTERN [1,2,3,1,2,3,...]");
        $display("========================================");
        
        // Fill ifmap - Pattern 1,2,3,1,2,3,...
        for (i = 0; i < 16; i = i + 1) begin
            @(posedge clk);
            if_we = 16'h0001;
            if_addr_wr_flat[8:0] = i;
            // Pattern: 1,2,3,1,2,3,...
            if_din_flat[15:0] = (i % 3) + 1;
        end
        @(posedge clk);
        if_we = 16'd0;
        
        $display("\nData filled:");
        $display("  Weight BRAM[0] = 1, BRAM[1] = 2, ..., BRAM[15] = 16");
        $display("  ifmap = [1,2,3,1,2,3,1,2,3,1,2,3,1,2,3,1]");
        
        repeat(5) @(posedge clk);
        
        $display("\n========================================");
        $display("EXPECTED COMPUTATION:");
        $display("========================================");
        $display("PE[i] uses BRAM[i] with ifmap sequence");
        $display("");
        $display("PE[0]: weight=1, ifmap=[1,2,3] → 1*1 + 1*2 + 1*3 = 6");
        $display("PE[1]: weight=2, ifmap=[2,3,1] → 2*2 + 2*3 + 2*1 = 12");
        $display("PE[2]: weight=3, ifmap=[3,1,2] → 3*3 + 3*1 + 3*2 = 18");
        $display("PE[3]: weight=4, ifmap=[1,2,3] → 4*1 + 4*2 + 4*3 = 24");
        $display("...");
        
        $display("\nStarting Mapper...");
        @(posedge clk);
        start_Mapper = 1;
        @(posedge clk);
        start_Mapper = 0;
        
        repeat(4) @(posedge clk);
        
        $display("\nStarting FSM...\n");
        @(posedge clk);
        start_weight = 1;
        start_ifmap = 1;
        
        @(posedge clk);
        start_weight = 0;
        start_ifmap = 0;
        
        repeat(2) @(posedge clk);
        
        @(posedge clk);
        start_transpose = 1;
        @(posedge clk);
        start_transpose = 0;
        
        repeat(100) @(posedge clk);
        
        $display("\n========================================");
        $display("EXPECTED MAPPING (row_id=0, tile_id=0):");
        $display("========================================");
        $display("cmap[0]=0 → PE[0] result=6   DISCARDED");
        $display("cmap[1]=1 → PE[1] result=12  → BRAM[0][0]");
        $display("cmap[2]=1 → PE[2] result=18  → BRAM[0][1]");
        $display("cmap[3]=1 → PE[3] result=24  → BRAM[0][2]");
        $display("");
        $display("cmap[4]=0 → PE[4] result=30  DISCARDED");
        $display("cmap[5]=1 → PE[5] result=36  → BRAM[1][0]");
        $display("cmap[6]=1 → PE[6] result=42  → BRAM[1][1]");
        $display("cmap[7]=1 → PE[7] result=48  → BRAM[1][2]");
        
        $display("\n========================================");
        $display("Reading Output BRAM");
        $display("========================================");
        
        ext_read_mode = 1;
        
        for (i = 0; i < 4; i = i + 1) begin
            $display("\nBRAM %0d:", i);
            for (j = 0; j < 3; j = j + 1) begin
                ext_read_addr_flat = 144'd0;
                ext_read_addr_flat[i*9 +: 9] = j;
                @(posedge clk);
                @(posedge clk);
                $display("  [%0d] = %0d", j, $signed(bram_data[i]));
            end
        end
        
        $display("\n========================================");
        $display("VERIFICATION:");
        $display("========================================");
        $display("Expected BRAM[0]: [12, 18, 24]");
        $display("Expected BRAM[1]: [36, 42, 48]");
        $display("Expected BRAM[2]: [60, 66, 72]");
        $display("Expected BRAM[3]: [84, 90, 96]");
        
        $display("\n========================================");
        $display("TEST COMPLETE");
        $display("========================================");
        
        #(CLK_PERIOD*10);
        $finish;
    end
    
    // Monitor PE outputs
    always @(posedge clk) begin
        if (dut.Transpose_top_inst.partial_valid) begin
            $display("[%0t] PE[%0d]: result=%0d (done=%0d)",
                     $time,
                     dut.col_id,
                     $signed(dut.Transpose_top_inst.result_out),
                     dut.done_transpose);
        end
    end
    
    // Monitor BRAM writes
    always @(posedge clk) begin
        if (dut.u_bram_read_modify.bram_we != 16'd0) begin
            for (i = 0; i < 4; i = i + 1) begin
                if (dut.u_bram_read_modify.bram_we[i]) begin
                    $display("[%0t]   → WRITE BRAM[%0d][%0d] = %0d",
                             $time, i,
                             dut.u_bram_read_modify.bram_addr_wr_flat[i*9 +: 9],
                             $signed(dut.u_bram_read_modify.bram_din_flat[i*16 +: 16]));
                end
            end
        end
    end
    
    initial begin
        $dumpfile("super_top_debug.vcd");
        $dumpvars(0, Super_TOP_Level_tb);
    end

endmodule