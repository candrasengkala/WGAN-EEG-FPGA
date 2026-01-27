`timescale 1ns/1ps

module onedconv_tb;

    // ========================================================
    // Parameters
    // ========================================================
    parameter DW = 16;
    parameter Dimension = 16;
    parameter ADDRESS_LENGTH = 13;
    parameter BRAM_Depth = 512;
    parameter MAX_COUNT = 512;
    parameter MUX_SEL_WIDTH = 4;
    
    parameter CLK_PERIOD = 10;  // 100MHz clock

    // ========================================================
    // Signals
    // ========================================================
    reg clk;
    reg rst;
    reg start_whole;
    
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
    
    // Outputs
    wire done_all;
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
        
        // Output read interface
        .read_mode_output_result(read_mode_output_result),
        .enb_output_result(enb_output_result),
        .output_result_bram_addr(output_result_bram_addr),
        
        // Outputs
        .done_all(done_all),
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
    // Helper Tasks
    // ========================================================
    
    // Task: Write to input data BRAM
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
            ena_inputdata_input_bram = {Dimension{1'b0}};
            wea_inputdata_input_bram = {Dimension{1'b0}};
        end
    endtask
    
    // Task: Write to weight BRAM
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
            ena_weight_input_bram = {Dimension{1'b0}};
            wea_weight_input_bram = {Dimension{1'b0}};
        end
    endtask
    
    // Task: Read output BRAM
    task read_output_bram;
        input [ADDRESS_LENGTH-1:0] addr;
        begin
            @(posedge clk);
            read_mode_output_result = 1'b1;
            enb_output_result = {Dimension{1'b1}};
            output_result_bram_addr = addr;
            @(posedge clk);
            @(posedge clk);  // Wait for data
            $display("Output[%0d] = %h", addr, output_result);
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
                    value = ch * 100 + t;  // Simple pattern: channel*100 + time
                    write_inputdata_bram(
                        base_addr + t,
                        {Dimension{value}},  // Replicate to all lanes
                        (1 << bram_idx)      // Select specific BRAM
                    );
                end
            end
            $display("Input data initialization complete");
        end
    endtask
    
    // Task: Initialize weights for testing
    task init_weights;
        input [4:0] k_size;
        input [9:0] num_filters;
        integer f, k;
        reg [DW-1:0] value;
        begin
            $display("Initializing weights: kernel_size=%0d, filters=%0d", k_size, num_filters);
            for (f = 0; f < num_filters; f = f + 1) begin
                for (k = 0; k < k_size; k = k + 1) begin
                    value = (f + 1) * (k + 1);  // Simple pattern
                    write_weight_bram(
                        k,
                        {Dimension{value}},  // Replicate to all lanes
                        (k < 16) ? (1 << k) : 16'h0000
                    );
                end
            end
            $display("Weight initialization complete");
        end
    endtask
    
    // Task: Run convolution
    task run_convolution;
        begin
            $display("\n=== Starting Convolution ===");
            $display("Parameters:");
            $display("  stride=%0d, padding=%0d, kernel_size=%0d", stride, padding, kernel_size);
            $display("  input_channels=%0d, temporal_length=%0d, filters=%0d", 
                     input_channels, temporal_length, filter_number);
            
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
    
    // Task: Read and display results
    task read_results;
        input [9:0] expected_output_length;
        integer i;
        begin
            $display("Reading output results (length=%0d):", expected_output_length);
            for (i = 0; i < expected_output_length; i = i + 1) begin
                read_output_bram(i);
            end
            read_mode_output_result = 1'b0;
            enb_output_result = {Dimension{1'b0}};
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
        
        // Reset sequence
        repeat(10) @(posedge clk);
        rst = 1'b1;
        repeat(10) @(posedge clk);
        
        $display("\n");
        $display("========================================");
        $display("  1D Convolution Testbench");
        $display("========================================");
        
        // ====================================================
        // Test 1: Basic convolution (kernel=3, stride=1, no padding)
        // ====================================================
        $display("\n>>> Test 1: Basic Convolution");
        stride = 2'd0;          // stride=1
        padding = 3'd0;         // no padding
        kernel_size = 5'd3;
        input_channels = 10'd1;
        temporal_length = 10'd16;
        filter_number = 10'd1;
        
        init_input_data(input_channels, temporal_length);
        init_weights(kernel_size, filter_number);
        run_convolution();
        read_results(10'd14);   // Expected output length: 16-3+1=14
        
        repeat(20) @(posedge clk);
        
        // ====================================================
        // Test 2: Convolution with stride=2
        // ====================================================
        $display("\n>>> Test 2: Convolution with Stride=2");
        stride = 2'd1;          // stride=2
        padding = 3'd0;
        kernel_size = 5'd3;
        input_channels = 10'd1;
        temporal_length = 10'd16;
        filter_number = 10'd1;
        
        init_input_data(input_channels, temporal_length);
        init_weights(kernel_size, filter_number);
        run_convolution();
        read_results(10'd7);    // Expected: floor((16-3)/2)+1=7
        
        repeat(20) @(posedge clk);
        
        // ====================================================
        // Test 3: Convolution with padding
        // ====================================================
        $display("\n>>> Test 3: Convolution with Padding=2");
        stride = 2'd0;          // stride=1
        padding = 3'd2;         // padding=2
        kernel_size = 5'd3;
        input_channels = 10'd1;
        temporal_length = 10'd16;
        filter_number = 10'd1;
        
        init_input_data(input_channels, temporal_length);
        init_weights(kernel_size, filter_number);
        run_convolution();
        read_results(10'd18);   // Expected: 16+2*2-3+1=18
        
        repeat(20) @(posedge clk);
        
        // ====================================================
        // Test 4: Different kernel size (7)
        // ====================================================
        $display("\n>>> Test 4: Kernel Size = 7");
        stride = 2'd0;
        padding = 3'd0;
        kernel_size = 5'd7;
        input_channels = 10'd1;
        temporal_length = 10'd32;
        filter_number = 10'd1;
        
        init_input_data(input_channels, temporal_length);
        init_weights(kernel_size, filter_number);
        run_convolution();
        read_results(10'd26);   // Expected: 32-7+1=26
        
        repeat(20) @(posedge clk);
        
        // ====================================================
        // Test 5: Multiple input channels
        // ====================================================
        $display("\n>>> Test 5: Multiple Input Channels (4 channels)");
        stride = 2'd0;
        padding = 3'd0;
        kernel_size = 5'd3;
        input_channels = 10'd4;
        temporal_length = 10'd16;
        filter_number = 10'd1;
        
        init_input_data(input_channels, temporal_length);
        init_weights(kernel_size, filter_number);
        run_convolution();
        read_results(10'd14);
        
        repeat(20) @(posedge clk);
        
        // ====================================================
        // Test 6: Complex scenario
        // ====================================================
        $display("\n>>> Test 6: Complex Scenario");
        $display("    32 channels, kernel=5, stride=2, padding=1");
        stride = 2'd1;          // stride=2
        padding = 3'd1;         // padding=1
        kernel_size = 5'd5;
        input_channels = 10'd32;
        temporal_length = 10'd64;
        filter_number = 10'd2;
        
        init_input_data(input_channels, temporal_length);
        init_weights(kernel_size, filter_number);
        run_convolution();
        read_results(10'd31);   // Expected: floor((64+2-5)/2)+1=31
        
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
    initial begin
        #(CLK_PERIOD * 1000000);  // 1M cycles timeout
        $display("\nERROR: Simulation timeout!");
        $finish;
    end

endmodule