`timescale 1ns/1ps

module onedconv_tb;

    // ========================================================
    // Parameters
    // ========================================================
    parameter DW = 16;
    parameter Dimension = 16;
    parameter ADDRESS_LENGTH = 13;
    parameter BRAM_Depth = 512;
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
    
    // External BRAM control
    reg [Dimension-1:0] ena_weight_input_bram;
    reg [Dimension-1:0] wea_weight_input_bram;
    reg [Dimension-1:0] ena_inputdata_input_bram;
    reg [Dimension-1:0] wea_inputdata_input_bram;
    
    // Bias BRAM control
    reg [Dimension-1:0] ena_bias_output_bram;
    reg [Dimension-1:0] wea_bias_output_bram;
    reg [ADDRESS_LENGTH-1:0] bias_output_bram_addr;
    reg [DW*Dimension-1:0] bias_output_bram;
    reg input_bias;
    
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
        .MUX_SEL_WIDTH(MUX_SEL_WIDTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .start_whole(start_whole),
        .stride(stride),
        .padding(padding),
        .kernel_size(kernel_size),
        .input_channels(input_channels),
        .temporal_length(temporal_length),
        .filter_number(filter_number),
        .ena_weight_input_bram(ena_weight_input_bram),
        .wea_weight_input_bram(wea_weight_input_bram),
        .ena_inputdata_input_bram(ena_inputdata_input_bram),
        .wea_inputdata_input_bram(wea_inputdata_input_bram),
        .ena_bias_output_bram(ena_bias_output_bram),
        .wea_bias_output_bram(wea_bias_output_bram),
        .bias_output_bram_addr(bias_output_bram_addr),
        .bias_output_bram(bias_output_bram),
        .input_bias(input_bias),
        .weight_bram_addr(weight_bram_addr),
        .inputdata_bram_addr(inputdata_bram_addr),
        .weight_input_bram(weight_input_bram),
        .inputdata_input_bram(inputdata_input_bram),
        .read_mode_output_result(read_mode_output_result),
        .enb_output_result(enb_output_result),
        .output_result_bram_addr(output_result_bram_addr),
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
    // Helper Functions
    // ========================================================
    function integer calc_output_length;
        input integer temp_len;
        input integer pad;
        input integer k_size;
        input [1:0] str;
        integer stride_val;
        begin
            stride_val = (str == 2'd0) ? 1 : str;
            calc_output_length = (temp_len + 2*pad - k_size) / stride_val + 1;
        end
    endfunction
    
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
    
    // Task: Write bias
    task write_bias_bram;
        input [ADDRESS_LENGTH-1:0] addr;
        input [DW*Dimension-1:0] data;
        input [Dimension-1:0] bram_select;
        begin
            @(posedge clk);
            input_bias = 1'b1;
            ena_bias_output_bram = bram_select;
            wea_bias_output_bram = bram_select;
            bias_output_bram_addr = addr;
            bias_output_bram = data;
            @(posedge clk);
            ena_bias_output_bram = {Dimension{1'b0}};
            wea_bias_output_bram = {Dimension{1'b0}};
            input_bias = 1'b0;
        end
    endtask
    
    // Task: Read output (Includes 3-cycle latency fix)
    task read_output_bram_addr;
        input [ADDRESS_LENGTH-1:0] addr;
        output [DW*Dimension-1:0] data;
        begin
            @(posedge clk); 
            read_mode_output_result = 1'b1;
            enb_output_result = {Dimension{1'b1}};
            output_result_bram_addr = addr;
            
            @(posedge clk); // BRAM Addr Latch
            @(posedge clk); // BRAM Data Valid
            @(posedge clk); // Reg Capture
            
            data = output_result;
        end
    endtask
    
    // Task: Initialize input data
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
                    value = ch * 10 + t + 1;
                    write_inputdata_bram(
                        base_addr + t,
                        {Dimension{value}}, 
                        (1 << bram_idx)
                    );
                end
            end
            $display("Input data initialization complete");
        end
    endtask
    
    // Task: Initialize weights - UPDATED FOR MULTI-CHANNEL SUPPORT
    task init_weights;
        input [4:0] k_size;
        input [9:0] in_ch;
        input [9:0] num_filters;
        integer f, k, ch, bram_idx, row;
        reg [ADDRESS_LENGTH-1:0] addr;
        reg signed [DW-1:0] value;
        begin
            $display("Initializing weights: kernel_size=%0d, input_channels=%0d, filters=%0d", k_size, in_ch, num_filters);
            $display("  Systolic Architecture: 16 BRAMs");
            $display("  Multi-Channel Logic: Weights stored continuously for all channels.");
            
            for (f = 0; f < num_filters; f = f + 1) begin
                bram_idx = f % 16;
                row = f / 16;
                
                $display("  Filter %0d -> BRAM[%0d], Row %0d:", f, bram_idx, row);
                
                for (ch = 0; ch < in_ch; ch = ch + 1) begin
                    for (k = 0; k < k_size; k = k + 1) begin
                        // Unique weight value for verification
                        value = $signed((f + 1) * 100 + (ch + 1) * 10 + (k + 1));
                        
                        // [FIX] CORRECTED ADDRESSING:
                        // Row_Offset + Channel_Offset + Kernel_Pos
                        addr = row * (in_ch * k_size) + ch * k_size + k;
                        
                        write_weight_bram(
                            addr,
                            {Dimension{value}},
                            (1 << bram_idx)
                        );
                        
                        if (ch == 0 && k == 0)
                            $display("    Ch0 start addr: %0d", addr);
                        if (ch == 1 && k == 0 && in_ch > 1)
                            $display("    Ch1 start addr: %0d", addr);
                    end
                end
            end
            $display("Weight initialization complete");
            $display("  Total BRAM depth usage: %0d addresses", (num_filters / 16 + (num_filters % 16 != 0)) * in_ch * k_size);
        end
    endtask
    
    // Task: Initialize bias
    task init_bias;
        input [9:0] num_filters;
        input [9:0] output_len;
        input signed [DW-1:0] bias_value;
        integer f, t, bram_idx, row;
        reg [ADDRESS_LENGTH-1:0] base_addr, addr;
        begin
            $display("Initializing bias: filters=%0d, output_length=%0d, bias_value=%0d", num_filters, output_len, bias_value);
            for (f = 0; f < num_filters; f = f + 1) begin
                bram_idx = f % 16;
                row = f / 16;
                base_addr = row * output_len;
                for (t = 0; t < output_len; t = t + 1) begin
                    addr = base_addr + t;
                    write_bias_bram(addr, {Dimension{bias_value}}, (1 << bram_idx));
                end
                $display("  Filter %0d: BRAM[%0d], Row %0d, Addresses %0d-%0d", f, bram_idx, row, base_addr, base_addr + output_len - 1);
            end
            $display("Bias initialization complete");
        end
    endtask
    
    // Task: Run convolution
    task run_convolution;
        integer expected_output_len;
        begin
            expected_output_len = calc_output_length(temporal_length, padding, kernel_size, stride);
            $display("\n=== Starting Convolution ===");
            $display("Parameters: stride=%0d, padding=%0d, kernel_size=%0d", stride, padding, kernel_size);
            $display("  input_channels=%0d, temporal_length=%0d, filters=%0d", input_channels, temporal_length, filter_number);
            $display("  Expected output_length=%0d", expected_output_len);
            
            @(posedge clk);
            start_whole = 1'b1;
            @(posedge clk);
            start_whole = 1'b0;
            
            wait(done_all);
            @(posedge clk);
            $display("=== Convolution Complete ===\n");
        end
    endtask
    
    // Task: Read and parse results
    task read_and_parse_results;
        input [9:0] num_filters;
        input [9:0] output_len;
        integer f, t, bram_idx, row;
        reg [ADDRESS_LENGTH-1:0] base_addr, addr;
        reg [DW*Dimension-1:0] bram_data;
        reg signed [DW-1:0] value;
        begin
            $display("\n========================================");
            $display("OUTPUT RESULTS");
            $display("Filters: %0d | Output Length: %0d", num_filters, output_len);
            $display("========================================");
            
            for (f = 0; f < num_filters; f = f + 1) begin
                bram_idx = f % 16;
                row = f / 16;
                base_addr = row * output_len;
                $display("\nFilter %0d (BRAM[%0d], Row %0d):", f, bram_idx, row);
                $write("  [");
                for (t = 0; t < output_len; t = t + 1) begin
                    addr = base_addr + t;
                    read_output_bram_addr(addr, bram_data);
                    value = bram_data[DW*(bram_idx+1)-1 -: DW];
                    if (t < output_len - 1) $write("%0d, ", $signed(value));
                    else $write("%0d", $signed(value));
                end
                $display("]");
            end
            
            read_mode_output_result = 1'b0;
            enb_output_result = {Dimension{1'b0}};
            $display("\n========================================\n");
        end
    endtask

    // ========================================================
    // Test Scenarios
    // ========================================================
    
    initial begin
        $dumpfile("onedconv_tb.vcd");
        $dumpvars(0, onedconv_tb);
        
        rst = 1'b0;
        start_whole = 1'b0;
        
        // Zero out controls
        ena_weight_input_bram = 0; wea_weight_input_bram = 0;
        ena_inputdata_input_bram = 0; wea_inputdata_input_bram = 0;
        ena_bias_output_bram = 0; wea_bias_output_bram = 0;
        bias_output_bram_addr = 0; bias_output_bram = 0;
        input_bias = 0; weight_bram_addr = 0; inputdata_bram_addr = 0;
        read_mode_output_result = 0; enb_output_result = 0; output_result_bram_addr = 0;
        
        // Reset
        repeat(10) @(posedge clk);
        rst = 1'b1;
        repeat(10) @(posedge clk);
        
        $display("\n========================================\n  1D Convolution Testbench - ADAPTED DESIGN\n========================================");
        
        // --- Test 1 ---
        $display("\n>>> Test 1: Basic Convolution (No Bias)");
        stride = 2'd2;          // [FIX] Corrected to 2'd2
        padding = 3'd7;         
        kernel_size = 5'd4;
        input_channels = 10'd2;
        temporal_length = 10'd7;
        filter_number = 10'd1;
        
        init_input_data(input_channels, temporal_length);
        init_weights(kernel_size, input_channels, filter_number);
        run_convolution();
        read_and_parse_results(filter_number, calc_output_length(temporal_length, padding, kernel_size, stride));
        
        repeat(20) @(posedge clk);
        
        // --- Test 2 ---
        $display("\n>>> Test 2: Convolution with Bias = 0");
        stride = 2'd2;          // [FIX] Corrected to 2'd2
        padding = 3'd7;
        kernel_size = 5'd4;
        input_channels = 10'd2;
        temporal_length = 10'd7;
        filter_number = 10'd1;
        
        init_input_data(input_channels, temporal_length);
        init_weights(kernel_size, input_channels, filter_number);
        init_bias(filter_number, calc_output_length(temporal_length, padding, kernel_size, stride), 16'sd0);
        run_convolution();
        read_and_parse_results(filter_number, calc_output_length(temporal_length, padding, kernel_size, stride));
        
        repeat(20) @(posedge clk);
        
        // --- Test 3 ---
        $display("\n>>> Test 3: Convolution with Bias = 100");
        stride = 2'd2;          // [FIX] Corrected to 2'd2
        padding = 3'd7;
        kernel_size = 5'd4;
        input_channels = 10'd2;
        temporal_length = 10'd7;
        filter_number = 10'd1;
        
        init_input_data(input_channels, temporal_length);
        init_weights(kernel_size, input_channels, filter_number);
        init_bias(filter_number, calc_output_length(temporal_length, padding, kernel_size, stride), 16'sd100);
        run_convolution();
        read_and_parse_results(filter_number, calc_output_length(temporal_length, padding, kernel_size, stride));
        
        repeat(20) @(posedge clk);
        
        // --- Test 4 ---
        $display("\n>>> Test 4: Convolution with Negative Bias = -50");
        stride = 2'd2;          // [FIX] Corrected to 2'd2
        padding = 3'd7;
        kernel_size = 5'd4;
        input_channels = 10'd2;
        temporal_length = 10'd7;
        filter_number = 10'd1;
        
        init_input_data(input_channels, temporal_length);
        init_weights(kernel_size, input_channels, filter_number);
        init_bias(filter_number, calc_output_length(temporal_length, padding, kernel_size, stride), -16'sd50);
        run_convolution();
        read_and_parse_results(filter_number, calc_output_length(temporal_length, padding, kernel_size, stride));
        
        repeat(20) @(posedge clk);
        
        // --- Test 5 ---
        $display("\n>>> Test 5: Multiple Filters with Bias = 25");
        stride = 2'd1;          // [FIX] Corrected to 2'd1 (maps to 1 if using standard logic)
        padding = 3'd0;
        kernel_size = 5'd3;
        input_channels = 10'd2;
        temporal_length = 10'd8;
        filter_number = 10'd2;
        
        init_input_data(input_channels, temporal_length);
        init_weights(kernel_size, input_channels, filter_number);
        init_bias(filter_number, calc_output_length(temporal_length, padding, kernel_size, stride), 16'sd25);
        run_convolution();
        read_and_parse_results(filter_number, calc_output_length(temporal_length, padding, kernel_size, stride));
        
        repeat(100) @(posedge clk);
        $display("\n========================================\n  All Tests Complete!\n========================================\n");
        $finish;
    end
    
    // Watchdog
    initial begin
        #(CLK_PERIOD * 1000000);
        $display("\nERROR: Simulation timeout!");
        $finish;
    end

endmodule