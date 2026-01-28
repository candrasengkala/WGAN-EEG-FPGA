`timescale 1ns/1ps

module onedconv_tb;

    // ========================================================
    // Parameters
    // ========================================================
    parameter DW = 16;
    parameter Dimension = 16;
    parameter ADDRESS_LENGTH = 10;
    parameter BRAM_Depth = 1024;
    parameter MAX_COUNT = 512;
    parameter MUX_SEL_WIDTH = 4;
    
    parameter CLK_PERIOD = 10;  // 100MHz clock

    // ========================================================
    // Signals
    // ========================================================
    reg clk;
    reg rst;
    reg start_whole;
    reg weight_ack_top;
    
    reg dynamic_weight_loading_en;
    integer weight_batch_count;
    
    // Convolution parameters
    reg [1:0] stride;
    reg [2:0] padding;
    reg [4:0] kernel_size;
    reg [9:0] input_channels;
    reg [9:0] temporal_length;
    reg [9:0] filter_number;
    
    // External BRAM control (for writing test data)
    reg [Dimension-1:0] ena_weight_input_bram;
    reg [Dimension-1:0] wea_weight_input_bram;
    reg [Dimension-1:0] ena_inputdata_input_bram;
    reg [Dimension-1:0] wea_inputdata_input_bram;
    
    reg [ADDRESS_LENGTH-1:0] weight_bram_addr;
    reg [ADDRESS_LENGTH-1:0] inputdata_bram_addr;
    
    reg [DW*Dimension-1:0] weight_input_bram;
    reg [DW*Dimension-1:0] inputdata_input_bram;
    
    // Output reading
    reg read_mode_output_result;
    reg [Dimension-1:0] enb_output_result;
    reg [ADDRESS_LENGTH-1:0] output_result_bram_addr;
    
    // Bias BRAM control (tie to safe values)
    reg [Dimension-1:0] ena_bias_output_bram;
    reg [Dimension-1:0] wea_bias_output_bram;
    reg [ADDRESS_LENGTH-1:0] bias_output_bram_addr;
    reg [DW*Dimension-1:0] bias_output_bram;
    reg input_bias;

    // Outputs
    wire done_all;
    wire done_filter;
    wire weight_req_top;
    wire signed [DW*Dimension-1:0] output_result;

    // ========================================================
    // DUT Instantiation
    // ========================================================
    onedconv #(
        .DW(DW),
        .Dimension(Dimension),
        .ADDRESS_LENGTH(ADDRESS_LENGTH),
        .BRAM_Depth(BRAM_Depth),
        .MAX_COUNT(MAX_COUNT),
        .MUX_SEL_WIDTH(MUX_SEL_WIDTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .start_whole(start_whole),
        .weight_req_top(weight_req_top),
        .weight_ack_top(weight_ack_top),
        
        // Convolution parameters
        .stride(stride),
        .padding(padding),
        .kernel_size(kernel_size),
        .input_channels(input_channels),
        .temporal_length(temporal_length),
        .filter_number(filter_number),
        
        // BRAM write interface
        .ena_weight_input_bram(ena_weight_input_bram),
        .wea_weight_input_bram(wea_weight_input_bram),
        .ena_inputdata_input_bram(ena_inputdata_input_bram),
        .wea_inputdata_input_bram(wea_inputdata_input_bram),
        
        .weight_bram_addr(weight_bram_addr),
        .inputdata_bram_addr(inputdata_bram_addr),
        
        .weight_input_bram(weight_input_bram),
        .inputdata_input_bram(inputdata_input_bram),

        // Bias BRAM interface
        .ena_bias_output_bram(ena_bias_output_bram),
        .wea_bias_output_bram(wea_bias_output_bram),
        .bias_output_bram_addr(bias_output_bram_addr),
        .bias_output_bram(bias_output_bram),
        .input_bias(input_bias),

        // Output read interface
        .read_mode_output_result(read_mode_output_result),
        .enb_output_result(enb_output_result),
        .output_result_bram_addr(output_result_bram_addr),
        
        // Outputs
        .done_all(done_all),
        .done_filter(done_filter),
        .output_result(output_result)
    );

    // ========================================================
    // Clock Generation
    // ========================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // ========================================================
    // Weight Loading Handshake Simulation
    // ========================================================
    // FIXED: Ensure weight_ack_top is only asserted AFTER weight loading is complete
    // The handshake protocol:
    // 1. FSM asserts weight_req_top and waits in S_WAIT_WEIGHT_UPDATE
    // 2. TB detects request, loads weights (if dynamic loading enabled)
    // 3. TB asserts weight_ack_top ONLY after all writes are done
    // 4. FSM sees ack, proceeds to next state
    // 5. TB clears weight_ack_top when weight_req_top is deasserted

    reg weight_loading_done;  // Flag set when weight loading task completes

    // This initial block waits for weight requests and handles loading
    initial begin
        weight_loading_done = 1'b0;
        forever begin
            // Wait for a weight request
            @(posedge clk);
            if (weight_req_top && !weight_ack_top) begin
                $display("[TB] Weight Request detected at time %t", $time);

                // If dynamic loading is enabled, load the weights
                if (dynamic_weight_loading_en) begin
                    // Clear any previous write signals first
                    ena_weight_input_bram = {Dimension{1'b0}};
                    wea_weight_input_bram = {Dimension{1'b0}};
                    repeat(2) @(posedge clk);

                    // Load the weights
                    load_dynamic_weights(weight_batch_count);
                    weight_batch_count = weight_batch_count + 1;

                    // Ensure all write signals are cleared after loading
                    ena_weight_input_bram = {Dimension{1'b0}};
                    wea_weight_input_bram = {Dimension{1'b0}};
                    repeat(3) @(posedge clk);  // Allow signals to settle
                end else begin
                    // No dynamic loading - just wait a few cycles (weights already preloaded)
                    repeat(5) @(posedge clk);
                end

                // Signal that loading is complete
                weight_loading_done = 1'b1;
                $display("[TB] Weight loading complete, asserting ack at time %t", $time);
            end
        end
    end

    // Separate always block to handle the ack signal
    always @(posedge clk) begin
        if (!rst) begin
            weight_ack_top <= 1'b0;
        end else begin
            if (weight_loading_done && weight_req_top) begin
                // Assert ack only after loading is done
                weight_ack_top <= 1'b1;
                weight_loading_done <= 1'b0;  // Clear the flag
            end
            else if (weight_ack_top && !weight_req_top) begin
                // Clear ack when request is deasserted
                weight_ack_top <= 1'b0;
            end
        end
    end

    // ========================================================
    // Helper Tasks
    // ========================================================

    // Task: Write to input data BRAM (single BRAM, single address)
    // NOTE: Use write_inputdata_bram_parallel for bulk writes
    task write_inputdata_bram;
        input [ADDRESS_LENGTH-1:0] addr;
        input [DW*Dimension-1:0] data;
        input [Dimension-1:0] bram_select;
        begin
            @(posedge clk);
            ena_inputdata_input_bram = bram_select;
            wea_inputdata_input_bram = bram_select;
            inputdata_bram_addr = addr;
            inputdata_input_bram = data;
            @(posedge clk);
            // Hold write for one more cycle to ensure BRAM latches data
            @(posedge clk);
            ena_inputdata_input_bram = {Dimension{1'b0}};
            wea_inputdata_input_bram = {Dimension{1'b0}};
        end
    endtask

    // Task: Write to ALL input data BRAMs in parallel (same address, different data per BRAM)
    task write_inputdata_bram_parallel;
        input [ADDRESS_LENGTH-1:0] addr;
        input [DW*Dimension-1:0] data;  // Each 16-bit slice goes to corresponding BRAM
        begin
            @(posedge clk);
            ena_inputdata_input_bram = {Dimension{1'b1}};  // Enable ALL BRAMs
            wea_inputdata_input_bram = {Dimension{1'b1}};  // Write to ALL BRAMs
            inputdata_bram_addr = addr;
            inputdata_input_bram = data;
            @(posedge clk);
            // Hold write for one more cycle to ensure BRAM latches data
            @(posedge clk);
            ena_inputdata_input_bram = {Dimension{1'b0}};
            wea_inputdata_input_bram = {Dimension{1'b0}};
        end
    endtask

    // Task: Write to weight BRAM (single BRAM, single address)
    // NOTE: Use write_weight_bram_parallel for bulk writes
    task write_weight_bram;
        input [ADDRESS_LENGTH-1:0] addr;
        input [DW*Dimension-1:0] data;
        input [Dimension-1:0] bram_select;
        begin
            @(posedge clk);
            ena_weight_input_bram = bram_select;
            wea_weight_input_bram = bram_select;
            weight_bram_addr = addr;
            weight_input_bram = data;
            @(posedge clk);
            // Hold write for one more cycle to ensure BRAM latches data
            @(posedge clk);
            ena_weight_input_bram = {Dimension{1'b0}};
            wea_weight_input_bram = {Dimension{1'b0}};
        end
    endtask

    // Task: Write to ALL weight BRAMs in parallel (same address, different data per BRAM)
    task write_weight_bram_parallel;
        input [ADDRESS_LENGTH-1:0] addr;
        input [DW*Dimension-1:0] data;  // Each 16-bit slice goes to corresponding BRAM
        begin
            @(posedge clk);
            ena_weight_input_bram = {Dimension{1'b1}};  // Enable ALL BRAMs
            wea_weight_input_bram = {Dimension{1'b1}};  // Write to ALL BRAMs
            weight_bram_addr = addr;
            weight_input_bram = data;
            @(posedge clk);
            // Hold write for one more cycle to ensure BRAM latches data
            @(posedge clk);
            ena_weight_input_bram = {Dimension{1'b0}};
            wea_weight_input_bram = {Dimension{1'b0}};
        end
    endtask
    
    // Task: Read output BRAM (single address, all filters)
    task read_output_bram;
        input [ADDRESS_LENGTH-1:0] addr;
        begin
            @(posedge clk);
            read_mode_output_result = 1'b1;
            enb_output_result = {Dimension{1'b1}};
            output_result_bram_addr = addr;
            @(posedge clk);
            @(posedge clk);  // Wait for data
            @(posedge clk);
            // Don't display here - will be handled by read_results_table
        end
    endtask

    // Task: Display single filter value as signed decimal
    function signed [DW-1:0] extract_filter_value;
        input [DW*Dimension-1:0] full_output;
        input integer filter_idx;
        begin
            extract_filter_value = full_output[filter_idx*DW +: DW];
        end
    endfunction

    // Task: Read and compare with golden model (for Test 6 specifically)
    task read_and_compare_test6;
        input [9:0] expected_output_length;
        integer i, f;
        reg signed [DW-1:0] verilog_val;
        integer golden_val;
        integer error_count;
        reg [DW*Dimension-1:0] output_data [0:511];
        // Golden model values for Test 6, Time 0 (first 16 filters)
        integer golden_time0 [0:15];
        begin
            // Expected golden values at Time 0 for Test 6
            golden_time0[0]  = 8655;
            golden_time0[1]  = 8655;
            golden_time0[2]  = 8640;
            golden_time0[3]  = 8610;
            golden_time0[4]  = 8640;
            golden_time0[5]  = 8655;
            golden_time0[6]  = 8655;
            golden_time0[7]  = 8640;
            golden_time0[8]  = 8610;
            golden_time0[9]  = 8640;
            golden_time0[10] = 8655;
            golden_time0[11] = 8655;
            golden_time0[12] = 8640;
            golden_time0[13] = 8610;
            golden_time0[14] = 8640;
            golden_time0[15] = 8655;

            $display("\n========================================");
            $display("  TEST 6 GOLDEN MODEL COMPARISON");
            $display("========================================");

            // Read all output values from BRAM
            for (i = 0; i < expected_output_length; i = i + 1) begin
                read_output_bram(i);
                output_data[i] = output_result;
            end

            // Disable read mode
            read_mode_output_result = 1'b0;
            enb_output_result = {Dimension{1'b0}};

            // Compare Time 0 values
            $display("\nTime 0 Comparison (Verilog vs Golden):");
            $display("Filter | Verilog | Golden | Difference | Status");
            $display("-------|---------|--------|------------|-------");
            error_count = 0;
            for (f = 0; f < 16; f = f + 1) begin
                verilog_val = extract_filter_value(output_data[0], f);
                golden_val = golden_time0[f];
                if (verilog_val == golden_val) begin
                    $display("  %2d   |  %5d  | %5d  |    %5d     |  OK",
                             f, verilog_val, golden_val, verilog_val - golden_val);
                end else begin
                    $display("  %2d   |  %5d  | %5d  |    %5d     | MISMATCH",
                             f, verilog_val, golden_val, verilog_val - golden_val);
                    error_count = error_count + 1;
                end
            end

            $display("\n");
            if (error_count == 0) begin
                $display("PASS: All Time 0 outputs match golden model!");
            end else begin
                $display("FAIL: %0d mismatches found at Time 0", error_count);
            end
            $display("========================================\n");
        end
    endtask
    
    // Task: Initialize input data for testing
    task init_input_data;
        input [9:0] channels;
        input [9:0] temp_len;
        integer ch, t, bram_idx, slot;
        reg [ADDRESS_LENGTH-1:0] base_addr;
        reg [DW-1:0] value;
        begin
            $display("Initializing input data: %0d channels, %0d temporal length", channels, temp_len);
            for (ch = 0; ch < channels; ch = ch + 1) begin
                bram_idx = ch % 16;
                slot = ch / 16;
                base_addr = slot * temp_len;

                for (t = 0; t < temp_len; t = t + 1) begin
                    value = ((ch + t) % 5) + 1;  // Small pattern: ((ch + t) % 5) + 1
                    write_inputdata_bram(
                        base_addr + t,
                        {Dimension{value}},  // Replicate to all lanes
                        (1 << bram_idx)      // Select specific BRAM
                    );
                end

                // DEBUG: Print first few channels' data pattern
                if (ch < 4) begin
                    $display("  Ch %0d -> BRAM %0d, slot %0d, addr %0d-%0d, pattern: t=0:%0d, t=1:%0d, t=2:%0d",
                             ch, bram_idx, slot, base_addr, base_addr + temp_len - 1,
                             ((ch + 0) % 5) + 1,
                             ((ch + 1) % 5) + 1,
                             ((ch + 2) % 5) + 1);
                end
            end

            // CRITICAL: Ensure all input data write signals are cleared after initialization
            ena_inputdata_input_bram = {Dimension{1'b0}};
            wea_inputdata_input_bram = {Dimension{1'b0}};
            repeat(3) @(posedge clk);  // Allow signals to settle

            $display("Input data initialization complete");
        end
    endtask

    // Task: Clear all weight BRAMs to zero
    task clear_weight_brams;
        input [4:0] k_size;
        input [9:0] max_channels;
        integer addr;
        begin
            $display("Clearing weight BRAMs...");
            // Clear enough addresses to cover all channels * kernel_size
            for (addr = 0; addr < (max_channels * k_size); addr = addr + 1) begin
                write_weight_bram(
                    addr,
                    {DW*Dimension{1'b0}},  // All zeros
                    {Dimension{1'b1}}       // Enable all BRAMs
                );
            end

            // CRITICAL: Ensure all weight write signals are cleared after clearing
            ena_weight_input_bram = {Dimension{1'b0}};
            wea_weight_input_bram = {Dimension{1'b0}};
            repeat(3) @(posedge clk);  // Allow signals to settle

            $display("Weight BRAM clear complete");
        end
    endtask

    // Task: Initialize bias (clear output BRAM by writing zeros)
    task init_bias;
        input [9:0] max_output_length;
        integer addr;
        begin
            $display("Initializing bias (clearing output BRAM)...");
            input_bias = 1'b1;  // Enable bias mode

            // Write zeros to all output addresses
            for (addr = 0; addr < max_output_length; addr = addr + 1) begin
                @(posedge clk);
                bias_output_bram_addr = addr;
                bias_output_bram = {DW*Dimension{1'b0}};  // All zeros
                ena_bias_output_bram = {Dimension{1'b1}}; // Enable all BRAMs
                wea_bias_output_bram = {Dimension{1'b1}}; // Write enable all
            end

            @(posedge clk);
            // Disable bias mode
            input_bias = 1'b0;
            ena_bias_output_bram = {Dimension{1'b0}};
            wea_bias_output_bram = {Dimension{1'b0}};
            $display("Bias initialization complete (wrote %0d zeros)", max_output_length);
        end
    endtask

    // Task: Initialize weights for testing (for first 64 channels only)
    // This loads weights for the first batch of up to 16 filters, for the first 64 input channels
    task init_weights;
        input [4:0] k_size;
        input [9:0] num_filters;
        integer f, k, ch;
        integer bram_idx;
        integer num_channels_to_load;
        reg [DW-1:0] value;
        reg [ADDRESS_LENGTH-1:0] addr;
        begin
            $display("Initializing weights: kernel_size=%0d, filters=%0d, input_channels=%0d",
                     k_size, num_filters, input_channels);

            // Determine how many channels to load (up to 64)
            num_channels_to_load = (input_channels > 64) ? 64 : input_channels;

            // Load weights for first block of channels (0-63) for first batch of filters (0-15)
            for (f = 0; f < num_filters && f < Dimension; f = f + 1) begin
                bram_idx = f % Dimension;  // Select BRAM based on filter index

                // For each input channel in the first block
                for (ch = 0; ch < num_channels_to_load; ch = ch + 1) begin
                    // For each kernel position
                    for (k = 0; k < k_size; k = k + 1) begin
                        // Address = local_channel_index * kernel_size + k
                        addr = (ch * k_size) + k;
                        value = ((f + k) % 5) + 1;  // Small pattern

                        write_weight_bram(
                            addr,
                            {Dimension{value}},
                            (1 << bram_idx)
                        );
                    end
                end
            end

            // CRITICAL: Ensure all weight write signals are cleared after initialization
            ena_weight_input_bram = {Dimension{1'b0}};
            wea_weight_input_bram = {Dimension{1'b0}};
            repeat(3) @(posedge clk);  // Allow signals to settle

            $display("Weight initialization complete: loaded %0d channels for %0d filters",
                     num_channels_to_load, (num_filters < Dimension) ? num_filters : Dimension);
        end
    endtask

    // Task: Dynamic Weight Loading (Block-based)
    task load_dynamic_weights;
        input integer batch_idx;
        integer f, k, local_ch;
        integer num_ch_blocks;
        integer current_filter_batch;
        integer current_ch_block;
        integer start_filter, end_filter;
        integer start_ch;
        integer bram_idx;
        reg [DW-1:0] value;
        reg [ADDRESS_LENGTH-1:0] addr;
        begin
            $display("[TB] Loading Dynamic Weights for Request #%0d", batch_idx);

            // Calculate which batch of filters and which block of channels this request corresponds to
            num_ch_blocks = (input_channels + 63) / 64;
            if (num_ch_blocks == 0) num_ch_blocks = 1;

            current_filter_batch = batch_idx / num_ch_blocks;
            current_ch_block = batch_idx % num_ch_blocks;

            start_filter = current_filter_batch * Dimension;
            end_filter = start_filter + Dimension;
            if (end_filter > filter_number) end_filter = filter_number;

            start_ch = current_ch_block * 64;

            $display("[TB]   -> Filter Batch %0d (Filters %0d-%0d)", current_filter_batch, start_filter, end_filter-1);
            $display("[TB]   -> Channel Block %0d (Channels %0d-%0d)", current_ch_block, start_ch, start_ch+63);

            for (f = start_filter; f < end_filter; f = f + 1) begin
                bram_idx = f % Dimension;

                for (local_ch = 0; local_ch < 64; local_ch = local_ch + 1) begin
                    // Only write if channel is within valid range
                    if ((start_ch + local_ch) < input_channels) begin
                        for (k = 0; k < kernel_size; k = k + 1) begin
                            addr = (local_ch * kernel_size) + k;
                            // Value pattern: ((FilterID + KernelIndex) % 5) + 1
                            value = ((f + k) % 5) + 1;

                            // DEBUG: Print first few weights for first filter in batch
                            if ((f == start_filter) && (local_ch < 2) && (k < 3)) begin
                                $display("[TB]     DEBUG: Filter %0d, Ch %0d, k=%0d: addr=%0d, value=%0d (to BRAM %0d)",
                                         f, start_ch + local_ch, k, addr, value, bram_idx);
                            end

                            write_weight_bram(
                                addr,
                                {Dimension{value}},
                                (1 << bram_idx)
                            );
                        end
                    end
                end

                // DEBUG: Print weight pattern summary for each filter
                $display("[TB]   Loaded Filter %0d -> BRAM %0d, weight pattern: k=0:%0d, k=1:%0d, k=2:%0d, k=3:%0d, k=4:%0d",
                         f, bram_idx,
                         ((f + 0) % 5) + 1,
                         ((f + 1) % 5) + 1,
                         ((f + 2) % 5) + 1,
                         ((f + 3) % 5) + 1,
                         ((f + 4) % 5) + 1);
            end

            // CRITICAL: Ensure all weight write signals are cleared after loading
            ena_weight_input_bram = {Dimension{1'b0}};
            wea_weight_input_bram = {Dimension{1'b0}};

            $display("[TB] Dynamic Weight Load Complete");
        end
    endtask
    
    // Task: Clear all external BRAM write signals
    task clear_all_external_writes;
        begin
            ena_weight_input_bram = {Dimension{1'b0}};
            wea_weight_input_bram = {Dimension{1'b0}};
            ena_inputdata_input_bram = {Dimension{1'b0}};
            wea_inputdata_input_bram = {Dimension{1'b0}};
            ena_bias_output_bram = {Dimension{1'b0}};
            wea_bias_output_bram = {Dimension{1'b0}};
            repeat(3) @(posedge clk);  // Allow signals to settle
        end
    endtask

    // Task: Run convolution
    task run_convolution;
        integer actual_stride;
        begin
            // Calculate actual stride value (matching hardware logic)
            actual_stride = (stride == 2'd0) ? 1 : stride;

            $display("\n=== Starting Convolution ===");
            $display("Parameters:");
            $display("  stride_input=%0d (actual_stride=%0d), padding=%0d, kernel_size=%0d",
                     stride, actual_stride, padding, kernel_size);
            $display("  input_channels=%0d, temporal_length=%0d, filters=%0d",
                     input_channels, temporal_length, filter_number);

            // CRITICAL: Ensure all external BRAM write signals are cleared
            // before starting convolution to prevent read/write conflicts
            clear_all_external_writes();

            @(posedge clk);
            start_whole = 1'b1;
            @(posedge clk);
            start_whole = 1'b0;

            // Wait for completion
            wait(done_all);
            @(posedge clk);
            $display("=== Convolution Complete ===\n");
        end
    endtask
    
    // Task: Read and display results in table format
    task read_results;
        input [9:0] expected_output_length;
        integer i, f, max_filters;
        reg signed [DW-1:0] filter_val;
        reg [DW*Dimension-1:0] output_data [0:511];  // Store output data
        begin
            $display("\n========================================");
            $display("  OUTPUT RESULTS (Signed Decimal)");
            $display("========================================");
            $display("Reading %0d output values for %0d filter(s)...\n",
                     expected_output_length, filter_number);

            // Read all output values from BRAM
            for (i = 0; i < expected_output_length; i = i + 1) begin
                read_output_bram(i);
                output_data[i] = output_result;
            end

            // Disable read mode
            read_mode_output_result = 1'b0;
            enb_output_result = {Dimension{1'b0}};

            // Determine how many filters to display
            max_filters = (filter_number > Dimension) ? Dimension : filter_number;

            // Print table header
            $write("Time |");
            for (f = 0; f < max_filters; f = f + 1) begin
                $write(" Filter %2d |", f);
            end
            $write("\n");

            // Print separator
            $write("-----|");
            for (f = 0; f < max_filters; f = f + 1) begin
                $write("-----------|");
            end
            $write("\n");

            // Print data rows
            for (i = 0; i < expected_output_length; i = i + 1) begin
                $write(" %3d |", i);
                for (f = 0; f < max_filters; f = f + 1) begin
                    filter_val = extract_filter_value(output_data[i], f);
                    $write(" %9d |", filter_val);
                end
                $write("\n");
            end

            $display("========================================");

            // DEBUG: Show first output value details for debugging
            if (expected_output_length > 0 && max_filters >= 5) begin
                $display("\nDEBUG: First 5 filter outputs at Time 0:");
                for (f = 0; f < 5; f = f + 1) begin
                    filter_val = extract_filter_value(output_data[0], f);
                    $display("  Filter %0d: %0d (0x%0h)", f, filter_val, filter_val);
                end
            end

            $display("\n");
        end
    endtask

    // ========================================================
    // Test Scenarios
    // ========================================================
    
    initial begin
        // Initialize waveform dump
        $dumpfile("onedconv_tb.vcd");
        $dumpvars(0, onedconv_tb);
        
        // Initialize signals
        rst = 1'b0;
        start_whole = 1'b0;
        weight_ack_top = 1'b0;
        dynamic_weight_loading_en = 0;
        weight_batch_count = 0;
        stride = 2'd0;
        padding = 3'd0;
        kernel_size = 5'd3;
        input_channels = 10'd1;
        temporal_length = 10'd16;
        filter_number = 10'd1;
        
        ena_weight_input_bram = {Dimension{1'b0}};
        wea_weight_input_bram = {Dimension{1'b0}};
        ena_inputdata_input_bram = {Dimension{1'b0}};
        wea_inputdata_input_bram = {Dimension{1'b0}};
        weight_bram_addr = {ADDRESS_LENGTH{1'b0}};
        inputdata_bram_addr = {ADDRESS_LENGTH{1'b0}};
        weight_input_bram = {DW*Dimension{1'b0}};
        inputdata_input_bram = {DW*Dimension{1'b0}};
        
        read_mode_output_result = 1'b0;
        enb_output_result = {Dimension{1'b0}};
        output_result_bram_addr = {ADDRESS_LENGTH{1'b0}};

        // Bias BRAM signals (keep disabled during convolution)
        ena_bias_output_bram = {Dimension{1'b0}};
        wea_bias_output_bram = {Dimension{1'b0}};
        bias_output_bram_addr = {ADDRESS_LENGTH{1'b0}};
        bias_output_bram = {DW*Dimension{1'b0}};
        input_bias = 1'b0;  // Keep 0 during processing

        // Reset sequence
        repeat(10) @(posedge clk);
        rst = 1'b1;
        repeat(10) @(posedge clk);
        
        $display("\n");
        $display("========================================");
        $display("  1D Convolution Testbench");
        $display("========================================");
        
        // // ====================================================
        // // Test 1: Basic convolution (kernel=3, stride=1, no padding)
        // // ====================================================
        // $display("\n>>> Test 1: Basic Convolution");
        // stride = 2'd0;          // stride=1
        // padding = 3'd0;         // no padding
        // kernel_size = 5'd3;
        // input_channels = 10'd1;
        // temporal_length = 10'd16;
        // filter_number = 10'd1;
        
        // init_input_data(input_channels, temporal_length);
        // clear_weight_brams(kernel_size, input_channels);
        // init_weights(kernel_size, filter_number);
        // init_bias(64);  // Clear output BRAM (max 64 outputs per test typically)
        // run_convolution();
        // read_results(10'd14);   // Expected output length: 16-3+1=14
        
        // repeat(20) @(posedge clk);

        // // ====================================================
        // // Test 2: Convolution with stride=2
        // // ====================================================
        // $display("\n>>> Test 2: Convolution with Stride=2");
        // rst = 1'b0; repeat(5) @(posedge clk); rst = 1'b1; repeat(5) @(posedge clk);

        // stride = 2'd2;          // stride=2 (encoding: 2'd2 → actual stride 2)
        // padding = 3'd0;
        // kernel_size = 5'd4;     // Changed from 3 to 4 (kernel_size/stride must be whole number)
        // input_channels = 10'd1;
        // temporal_length = 10'd16;
        // filter_number = 10'd1;

        // init_input_data(input_channels, temporal_length);
        // clear_weight_brams(kernel_size, input_channels);
        // init_weights(kernel_size, filter_number);
        // init_bias(64);  // Clear output BRAM (max 64 outputs per test typically)
        // run_convolution();
        // read_results(10'd7);    // Expected: floor((16-4)/2)+1=7
        
        // repeat(20) @(posedge clk);

        // // ====================================================
        // // Test 3: Convolution with padding
        // // ====================================================
        // $display("\n>>> Test 3: Convolution with Padding=2");
        // rst = 1'b0; repeat(5) @(posedge clk); rst = 1'b1; repeat(5) @(posedge clk);

        // stride = 2'd0;          // stride=1
        // padding = 3'd2;         // padding=2
        // kernel_size = 5'd3;
        // input_channels = 10'd1;
        // temporal_length = 10'd16;
        // filter_number = 10'd1;
        
        // init_input_data(input_channels, temporal_length);
        // clear_weight_brams(kernel_size, input_channels);
        // init_weights(kernel_size, filter_number);
        // init_bias(64);  // Clear output BRAM (max 64 outputs per test typically)
        // run_convolution();
        // read_results(10'd18);   // Expected: 16+2*2-3+1=18
        
        // repeat(20) @(posedge clk);

        // // ====================================================
        // // Test 4: Different kernel size (7)
        // // ====================================================
        // $display("\n>>> Test 4: Kernel Size = 7");
        // rst = 1'b0; repeat(5) @(posedge clk); rst = 1'b1; repeat(5) @(posedge clk);

        // stride = 2'd0;
        // padding = 3'd0;
        // kernel_size = 5'd7;
        // input_channels = 10'd1;
        // temporal_length = 10'd32;
        // filter_number = 10'd1;
        
        // init_input_data(input_channels, temporal_length);
        // clear_weight_brams(kernel_size, input_channels);
        // init_weights(kernel_size, filter_number);
        // init_bias(64);  // Clear output BRAM (max 64 outputs per test typically)
        // run_convolution();
        // read_results(10'd26);   // Expected: 32-7+1=26
        
        // repeat(20) @(posedge clk);

        // // ====================================================
        // // Test 5: Multiple input channels
        // // ====================================================
        // $display("\n>>> Test 5: Multiple Input Channels (4 channels)");
        // rst = 1'b0; repeat(5) @(posedge clk); rst = 1'b1; repeat(5) @(posedge clk);

        // stride = 2'd0;
        // padding = 3'd0;
        // kernel_size = 5'd3;
        // input_channels = 10'd4;
        // temporal_length = 10'd16;
        // filter_number = 10'd1;
        
        // init_input_data(input_channels, temporal_length);
        // clear_weight_brams(kernel_size, input_channels);
        // init_weights(kernel_size, filter_number);
        // init_bias(64);  // Clear output BRAM (max 64 outputs per test typically)
        // run_convolution();
        // read_results(10'd14);
        
        // repeat(20) @(posedge clk);

        // ====================================================
        // Test 6: Complex scenario with dynamic weight loading
        // Matches golden_outputs.py Test 6:
        //   ch=64, len=64, k=16, f=64, stride=2, pad=1
        // Expected: Multiple weight requests due to 64 filters
        //   (4 filter batches: 0-15, 16-31, 32-47, 48-63)
        // ====================================================
        $display("\n>>> Test 6: Complex Scenario (64 channels, 64 filters)");
        $display("    Expect 4 Weight Requests for 64 filters in batches of 16");
        rst = 1'b0; repeat(5) @(posedge clk); rst = 1'b1; repeat(5) @(posedge clk);

        stride = 2'd2;          // stride=2
        padding = 3'd7;         // padding=1
        kernel_size = 5'd16;    // kernel_size=16
        input_channels = 10'd1; // 64 channels (exactly 1 block)
        temporal_length = 10'd512;
        filter_number = 10'd32; // 64 filters (requires 4 filter batches)

        dynamic_weight_loading_en = 1; // Enable dynamic loading
        weight_batch_count = 0;

        init_input_data(input_channels, temporal_length);
        init_bias(64);
        // Note: Weights loaded dynamically via handshake
        run_convolution();

        // Use special comparison task for Test 6
        read_and_compare_test6(10'd32);   // Expected: floor((64+2*1-16)/2)+1=26
        // Also show full table
        read_results(10'd32);

        dynamic_weight_loading_en = 0; // Disable for safety

        repeat(20) @(posedge clk);

        // ====================================================
        // Test 7: Block-based Weight Loading (> 64 Channels)
        // Matches golden_outputs.py Test 7:
        //   ch=70, len=16, k=3, f=1, stride=1, pad=0
        // Expected: 2 weight requests due to channel reloading
        //   (Ch 0-63 for first batch, then Ch 64-69 for second batch)
        // ====================================================
        $display("\n>>> Test 7: Block-based Weight Loading (70 Channels)");
        $display("    Expect 2 Weight Requests (Batch 0 for Ch 0-63, Batch 1 for Ch 64-69)");
        rst = 1'b0; repeat(5) @(posedge clk); rst = 1'b1; repeat(5) @(posedge clk);

        stride = 2'd0;          // stride=1
        padding = 3'd0;         // no padding
        kernel_size = 5'd3;     // kernel_size=3
        input_channels = 10'd70; // 70 channels (> 64, triggers channel reload)
        temporal_length = 10'd16;
        filter_number = 10'd1;  // 1 filter

        dynamic_weight_loading_en = 1; // Enable dynamic loading
        weight_batch_count = 0;

        init_input_data(input_channels, temporal_length);
        init_bias(64);
        // Note: Weights loaded dynamically - first Ch 0-63, then Ch 64-69
        run_convolution();
        read_results(10'd14);   // Expected: 16-3+1=14

        dynamic_weight_loading_en = 0; // Disable for safety

        repeat(20) @(posedge clk);

        // ====================================================
        // Test 8: Large Filter Number (32 Filters)
        // Matches golden_outputs.py Test 8:
        //   ch=16, len=16, k=4, f=32, stride=2, pad=1
        // ====================================================
        $display("\n>>> Test 8: Large Filter Number (32 Filters)");
        $display("    Expect 2 Weight Requests (Batch 0 for Filters 0-15, Batch 1 for Filters 16-31)");

        rst = 1'b0; repeat(5) @(posedge clk); rst = 1'b1; repeat(5) @(posedge clk);

        stride = 2'd2;          // stride=2 (encoding: 2'd2 → actual stride 2)
        padding = 3'd1;
        kernel_size = 5'd4;     // kernel_size=4 (matches golden model)
        input_channels = 10'd16; // 16 channels (fits in one block)
        temporal_length = 10'd16;
        filter_number = 10'd32; // 32 filters (requires 2 filter batches)

        dynamic_weight_loading_en = 1;
        weight_batch_count = 0;

        init_input_data(input_channels, temporal_length);
        init_bias(64);
        // Note: Weights are loaded dynamically via load_dynamic_weights
        // which is triggered by the weight handshake mechanism
        run_convolution();
        read_results(10'd8);    // Expected: floor((16+2*1-4)/2)+1=8

        dynamic_weight_loading_en = 0;

        repeat(20) @(posedge clk);

        // ====================================================
        // End of simulation
        // ====================================================
        repeat(100) @(posedge clk);
        $display("\n========================================");
        $display("  All Tests Complete!");
        $display("========================================\n");
        $finish;
    end
    
    // Timeout watchdog
    // initial begin
    //     #(CLK_PERIOD * 1000000);  // 1M cycles timeout
    //     $display("\nERROR: Simulation timeout!");
    //     $finish;
    // end

endmodule