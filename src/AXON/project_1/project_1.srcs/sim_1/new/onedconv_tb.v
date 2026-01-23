`timescale 1ns/1ps

module onedconv_tb;

    // ============================================================
    // 1. Parameters & Configuration
    // ============================================================
    parameter DW = 16;
    parameter Dimension = 16;
    parameter ADDRESS_LENGTH = 9;
    parameter BRAM_Depth = 512;
    parameter MUX_SEL_WIDTH = 4;
    parameter CLK_PERIOD = 10;

    // ============================================================
    // 2. Signals
    // ============================================================
    reg clk;
    reg rst; 
    reg start_whole;

    reg [1:0] stride;
    reg [2:0] padding;
    reg [4:0] kernel_size;
    reg [9:0] input_channels;
    reg [9:0] temporal_length;
    reg [9:0] filter_number;

    reg [Dimension-1:0] ena_weight_input_bram, wea_weight_input_bram;
    reg [Dimension-1:0] ena_inputdata_input_bram, wea_inputdata_input_bram;
    reg [ADDRESS_LENGTH-1:0] weight_bram_addr, inputdata_bram_addr;
    reg signed [DW*Dimension-1:0] weight_input_bram, inputdata_input_bram;

    reg read_mode_output_result;
    reg [Dimension-1:0] enb_output_result;
    reg [ADDRESS_LENGTH-1:0] output_result_bram_addr;

    wire done_all;
    wire signed [DW*Dimension-1:0] output_result;

    // ============================================================
    // 3. DUT Instantiation
    // ============================================================
    onedconv #(
        .DW(DW), .Dimension(Dimension), .ADDRESS_LENGTH(ADDRESS_LENGTH)
    ) dut (
        .clk(clk), .rst(rst), .start_whole(start_whole),
        .stride(stride), .padding(padding), .kernel_size(kernel_size),
        .input_channels(input_channels), .temporal_length(temporal_length), .filter_number(filter_number),
        .ena_weight_input_bram(ena_weight_input_bram), .wea_weight_input_bram(wea_weight_input_bram),
        .ena_inputdata_input_bram(ena_inputdata_input_bram), .wea_inputdata_input_bram(wea_inputdata_input_bram),
        .weight_bram_addr(weight_bram_addr), .inputdata_bram_addr(inputdata_bram_addr),
        .weight_input_bram(weight_input_bram), .inputdata_input_bram(inputdata_input_bram),
        .read_mode_output_result(read_mode_output_result), .enb_output_result(enb_output_result),
        .output_result_bram_addr(output_result_bram_addr), .done_all(done_all), .output_result(output_result)
    );

    // Clock Gen
    initial begin clk = 0; forever #(CLK_PERIOD/2) clk = ~clk; end

    // ============================================================
    // 4. Improved Data Loading Tasks
    // ============================================================
    task write_input_val(input integer channel, input integer addr_offset, input signed [DW-1:0] val);
        integer bram_idx, slot, final_addr;
        begin
            bram_idx = channel % Dimension;
            slot = channel / Dimension;
            final_addr = (slot * temporal_length) + addr_offset;
            inputdata_input_bram = 0;
            inputdata_input_bram[bram_idx*DW +: DW] = val;
            inputdata_bram_addr = final_addr;
            ena_inputdata_input_bram = (1 << bram_idx);
            wea_inputdata_input_bram = (1 << bram_idx);
            @(posedge clk);
            ena_inputdata_input_bram = 0; wea_inputdata_input_bram = 0;
        end
    endtask

    task write_weight_val(input integer filter_id, input integer channel_id, input integer k_idx, input signed [DW-1:0] val);
        integer bram_idx, filter_slot, final_addr;
        begin
            bram_idx = filter_id % Dimension;
            filter_slot = filter_id / Dimension;
            final_addr = (filter_slot * (input_channels * kernel_size)) + (channel_id * kernel_size) + k_idx;
            weight_input_bram = 0;
            weight_input_bram[bram_idx*DW +: DW] = val;
            weight_bram_addr = final_addr;
            ena_weight_input_bram = (1 << bram_idx);
            wea_weight_input_bram = (1 << bram_idx);
            @(posedge clk);
            ena_weight_input_bram = 0; wea_weight_input_bram = 0;
        end
    endtask

    // ============================================================
    // FIXED: Read output for specific filter
    // ============================================================
    task read_output_for_filter(input integer filter_id, input integer time_idx, input integer out_len);
        integer bram_idx, filter_slot, final_addr;
        reg signed [DW-1:0] result_val;
        begin
            bram_idx = filter_id % Dimension;
            filter_slot = filter_id / Dimension;
            
            // Calculate address: slot * output_length + time_idx
            // output_length for this config = 10
            final_addr = (filter_slot * out_len) + time_idx;
            
            output_result_bram_addr = final_addr;
            enb_output_result = (1 << bram_idx);  // Enable only this filter's BRAM
            
            @(posedge clk); // Cycle 1: Address setup
            @(posedge clk); // Cycle 2: BRAM latency
            @(posedge clk); // Cycle 3: Register latency
            
            // Extract result from the correct bit position
            result_val = output_result[bram_idx*DW +: DW];
            
            $display("  Filter %0d[%0d] = %0d", filter_id, time_idx, $signed(result_val));
        end
    endtask

    // ============================================================
    // 5. Main Test Sequence
    // ============================================================
    integer i, c, k, f, out_len;
    integer f0_val, f1_val;  // Declare at module level
    integer fp;  // File pointer
    
    initial begin
        // Init
        rst = 0; start_whole = 0; read_mode_output_result = 0;
        stride = 2; padding = 7; kernel_size = 4;
        input_channels = 2; temporal_length = 7; filter_number = 1;
        fp = $fopen("output_results.txt", "w");

        // Reset
        repeat(10) @(posedge clk);
        rst = 1; 
        repeat(5) @(posedge clk);

        $display("=======================================================");
        $display("         1D CONVOLUTION TESTBENCH");
        $display("=======================================================");
        $display("Configuration:");
        $display("  Input Channels:  %0d", input_channels);
        $display("  Temporal Length: %0d", temporal_length);
        $display("  Kernel Size:     %0d", kernel_size);
        $display("  Filters:         %0d", filter_number);
        $display("  Stride:          %0d", stride);
        $display("  Padding:         %0d", padding);
        $display("=======================================================");

        // Load Input Data
        $display("\nLoading Input Data...");
        for (c = 0; c < input_channels; c = c + 1) begin
            $write("  Channel %0d: ", c);
            for (i = 0; i < temporal_length; i = i + 1) begin
                write_input_val(c, i, (c*10 + i + 1));
                if (i < 10) $write("%0d ", (c*10 + i + 1));
            end
            $display("");
        end

        // Load Weights
        $display("\nLoading Weights (all = 1)...");
        for (f = 0; f < filter_number; f = f + 1)
            for (c = 0; c < input_channels; c = c + 1)
                for (k = 0; k < kernel_size; k = k + 1)
                    write_weight_val(f, c, k, 1);
        $display("  Done.");
        
        // Start Convolution
        $display("\n--- Starting Convolution ---");
        @(posedge clk); start_whole = 1;
        @(posedge clk); start_whole = 0;

        // Wait for Completion
        wait(done_all == 1);
        $display("--- Convolution Finished ---");
        
        // Wait for FSM to return to IDLE
        repeat(10) @(posedge clk);

        // Read Results - FIXED: Read per filter
        $display("\n=======================================================");
        $display("                   RESULTS");
        $display("=======================================================");
        read_mode_output_result = 1;
        out_len = (temporal_length + 2*padding - kernel_size) / stride + 1;
        
        // Read each filter separately
        for (f = 0; f < filter_number; f = f + 1) begin
            $display("\nFilter %0d outputs:", f);
            for (i = 0; i < out_len; i = i + 1) begin
                read_output_for_filter(f, i, out_len);
            end
        end
        
        // Alternative: Side-by-side comparison
        $display("\n=======================================================");
        $display("        SIDE-BY-SIDE COMPARISON");
        $display("=======================================================");
        $display("Time | Filter 0 | Filter 1");
        $display("-----|----------|----------");
        
        for (i = 0; i < out_len; i = i + 1) begin
            $write("%0d  | ", i);
            $fwrite(fp, "%0d  | ", i);
            for (f = 0; f < filter_number; f = f + 1) begin
                read_output_for_filter(f, i, out_len);
            end
            $fwrite(fp, "\n");
        end
        
        $fclose(fp);
        read_mode_output_result = 0;
        enb_output_result = 0;
        
        $display("\n=======================================================");
        $display("Test Finished.");
        $display("=======================================================");
        $finish;
    end

    // Monitor for debugging
    always @(posedge clk) begin
        if (dut.wea_output_result != 0) begin
            $display("[@%0t] Write to Output BRAM: addr=%0d, wea=%b", 
                     $time, dut.output_addr_out_a, dut.wea_output_result);
        end
    end
    

endmodule