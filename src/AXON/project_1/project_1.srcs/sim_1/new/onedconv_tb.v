`timescale 1ns/1ps

module onedconv_tb;

    // ============================================================
    // 1. Parameters & Configuration
    // ============================================================
    parameter DW = 16;
    parameter Dimension = 16;
    parameter ADDRESS_LENGTH = 13;
    parameter BRAM_Depth = 8192;
    parameter MUX_SEL_WIDTH = 4;
    parameter CLK_PERIOD = 10;

    // ============================================================
    // 2. Signals
    // ============================================================
    reg clk;
    reg rst; // ACTIVE LOW
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

    reg [Dimension-1:0] ena_bias_output_bram, wea_bias_output_bram;
    reg [ADDRESS_LENGTH-1:0] bias_output_bram_addr;
    reg signed [DW*Dimension-1:0] bias_output_bram;
    reg input_bias = 0; 

    reg read_mode_output_result;
    reg [Dimension-1:0] enb_output_result;
    reg [ADDRESS_LENGTH-1:0] output_result_bram_addr;

    wire done_all;
    wire signed [DW*Dimension-1:0] output_result;

    // ============================================================
    // 3. DUT Instantiation
    // ============================================================
    onedconv #(
        .DW(DW), .Dimension(Dimension), .ADDRESS_LENGTH(ADDRESS_LENGTH),
        .BRAM_Depth(BRAM_Depth), .MUX_SEL_WIDTH(MUX_SEL_WIDTH)
    ) dut (
        .clk(clk), .rst(rst), .start_whole(start_whole),
        .stride(stride), .padding(padding), .kernel_size(kernel_size),
        .input_channels(input_channels), .temporal_length(temporal_length), .filter_number(filter_number),
        .ena_weight_input_bram(ena_weight_input_bram), .wea_weight_input_bram(wea_weight_input_bram),
        .ena_inputdata_input_bram(ena_inputdata_input_bram), .wea_inputdata_input_bram(wea_inputdata_input_bram),
        .ena_bias_output_bram(ena_bias_output_bram), .wea_bias_output_bram(wea_bias_output_bram),
        .bias_output_bram_addr(bias_output_bram_addr), .bias_output_bram(bias_output_bram), .input_bias(input_bias),
        .weight_bram_addr(weight_bram_addr), .inputdata_bram_addr(inputdata_bram_addr),
        .weight_input_bram(weight_input_bram), .inputdata_input_bram(inputdata_input_bram),
        .read_mode_output_result(read_mode_output_result), .enb_output_result(enb_output_result),
        .output_result_bram_addr(output_result_bram_addr), .done_all(done_all), .output_result(output_result)
    );

    // Clock Gen
    initial begin clk = 0; forever #(CLK_PERIOD/2) clk = ~clk; end

    // ============================================================
    // 4. Per-Channel Debug Inspection
    // ============================================================
    wire signed [DW-1:0] debug_output_lane [0:Dimension-1];
    
    genvar g;
    generate
        for (g = 0; g < Dimension; g = g + 1) begin : dbg_lanes
            assign debug_output_lane[g] = output_result[(g+1)*DW-1 : g*DW];
            
            // Monitor Memory Writes
            always @(posedge clk) begin
                if (dut.gen_output_result_bram[g].bram_output.wea && dut.gen_output_result_bram[g].bram_output.ena) begin
                     $display("[MemWrite] Filter %0d[%0d] = %d", 
                        g, 
                        dut.gen_output_result_bram[g].bram_output.addra, 
                        $signed(dut.gen_output_result_bram[g].bram_output.dia)
                     );
                end
            end
        end
    endgenerate

    // ============================================================
    // 5. INTERNAL STATE MONITOR (NEW!)
    // ============================================================
    // This block spies on the Controller FSM to print the current state
    // and which channel/filter is being processed.
    
    reg [25*8-1:0] state_name; // String buffer for state name

    // Decode State Number to String
    always @(*) begin
        case (dut.onedconv_ctrl_inst.state)
            5'd0:  state_name = "S_IDLE";
            5'd1:  state_name = "S_SET_ADDR";
            5'd2:  state_name = "S_PRE_LOAD";
            5'd3:  state_name = "S_LOAD_INITIAL";
            5'd4:  state_name = "S_RUN";
            5'd5:  state_name = "S_OUTPUT_VAL";
            5'd6:  state_name = "S_INC_WORK";
            5'd7:  state_name = "S_CHECK_PASSES";
            5'd8:  state_name = "S_INC_CHANNEL";
            5'd9:  state_name = "S_CHECK_CHANNELS";
            5'd10: state_name = "S_INC_FILTER";
            5'd11: state_name = "S_CHECK_FILTERS";
            5'd12: state_name = "S_DONE";
            default: state_name = "UNKNOWN";
        endcase
    end

    // Print Logic
    always @(dut.onedconv_ctrl_inst.state) begin
        if (rst == 1'b1 && start_whole == 1'b0) begin // Only print if not in reset and after start
            if (dut.onedconv_ctrl_inst.state == 5'd4) begin // S_RUN
                $display("[Time %0t] State: %s | >>> PROCESSING: Filter Block %0d vs Input Channel %0d", 
                         $time, state_name, 
                         dut.onedconv_ctrl_inst.filter_number_count, 
                         dut.onedconv_ctrl_inst.input_channel_count);
            end else begin
                // Just print the state transition
                $display("[Time %0t] State: %s", $time, state_name);
            end
        end
    end

    // ============================================================
    // 6. Tasks
    // ============================================================
    
    task perform_system_reset;
        begin
            rst = 1'b1; 
            repeat(20) @(posedge clk);
            rst = 1'b0; // Active Low Reset
            repeat(5) @(posedge clk);
            rst = 1'b1;
        end
    endtask

    task zero_all_outputs(input integer total_filters, input integer current_out_len);
        integer f_idx, t_idx;
        begin
            $display("--- Initializing Output BRAMs to Zero ---");
            for (f_idx = 0; f_idx < total_filters; f_idx = f_idx + 1) begin
                for (t_idx = 0; t_idx < current_out_len; t_idx = t_idx + 1) begin
                    write_bias_val(f_idx, t_idx, current_out_len, 16'sh0000);
                end
            end
        end
    endtask

    task write_bias_val(input integer filter_id, input integer time_idx, input integer out_len, input signed [DW-1:0] val);
        integer bram_idx, filter_slot, final_addr;
        begin
            bram_idx = filter_id % Dimension;
            filter_slot = filter_id / Dimension;
            final_addr = (filter_slot * out_len) + time_idx;
            
            input_bias = 1'b1;
            bias_output_bram = 0;
            bias_output_bram[bram_idx*DW +: DW] = val;
            bias_output_bram_addr = final_addr;
            ena_bias_output_bram = (1 << bram_idx);
            wea_bias_output_bram = (1 << bram_idx);
            @(posedge clk);
            ena_bias_output_bram = 0;
            wea_bias_output_bram = 0;
            @(posedge clk);
            input_bias = 1'b0;
            @(posedge clk);
        end
    endtask

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

    task read_output_single_lane(input integer filter_id, input integer time_idx, input integer out_len);
        integer bram_idx, filter_slot, final_addr;
        reg signed [DW-1:0] result_val;
        begin
            bram_idx = filter_id % Dimension;
            filter_slot = filter_id / Dimension;
            final_addr = (filter_slot * out_len) + time_idx;
            output_result_bram_addr = final_addr;
            enb_output_result = (1 << bram_idx);
            repeat(3) @(posedge clk);
            result_val = output_result[bram_idx*DW +: DW];
            $display("  Filter %0d[%0d] = %d", filter_id, time_idx, result_val);
            enb_output_result = 0;
            @(posedge clk);
        end
    endtask

    // ============================================================
    // 7. Main Sequence
    // ============================================================
    integer i, c, k, f, out_len;
    
    initial begin
        // Init signals
        rst = 1'b0; start_whole = 0; input_bias = 0;
        ena_weight_input_bram = 0; wea_weight_input_bram = 0;
        ena_inputdata_input_bram = 0; wea_inputdata_input_bram = 0;
        ena_bias_output_bram = 0; wea_bias_output_bram = 0;
        read_mode_output_result = 0; enb_output_result = 0;

        perform_system_reset();

        // --------------------------------------------------------------------
        // TEST 1: Basic (S=1, P=1) - No Bias
        // --------------------------------------------------------------------
        $display("\n>>> TEST 1: Basic (S=1, P=1) - No Bias (Unique Weights/Inputs)");
        stride = 2'd1; padding = 3'd1; kernel_size = 5'd3;
        input_channels = 10'd2; temporal_length = 10'd8; filter_number = 10'd1;
        out_len = (temporal_length + 2*padding - kernel_size) / stride + 1;

        zero_all_outputs(filter_number, out_len); 

        // Input Pattern: (Channel+1)*10 + Index
        for (c = 0; c < input_channels; c = c + 1)
            for (i = 0; i < temporal_length; i = i + 1) 
                write_input_val(c, i, (c + 1) * 10 + i);

        // Weight Pattern: Unique per column
        for (f = 0; f < filter_number; f = f + 1)
            for (c = 0; c < input_channels; c = c + 1)
                for (k = 0; k < kernel_size; k = k + 1) 
                    write_weight_val(f, c, k, (f + 1) * 10 + (c + 1) * 5 + k + 1);

        start_whole = 1; @(posedge clk); start_whole = 0;
        wait(done_all);
        
        $display("--- Final Readout ---");
        read_mode_output_result = 1;
        for (i = 0; i < out_len; i = i + 1) read_output_single_lane(0, i, out_len);
        read_mode_output_result = 0;
        perform_system_reset();

        // --------------------------------------------------------------------
        // TEST 2: High Padding (S=2, P=7)
        // --------------------------------------------------------------------
        $display("\n>>> TEST 2: High Padding (S=2, P=7) - No Bias (Unique Weights/Inputs)");
        stride = 2'd2; padding = 3'd7; kernel_size = 5'd4;
        input_channels = 10'd2; temporal_length = 10'd7; filter_number = 10'd1;
        out_len = (temporal_length + 2*padding - kernel_size) / stride + 1;

        zero_all_outputs(filter_number, out_len);

        for (c = 0; c < input_channels; c = c + 1)
            for (i = 0; i < temporal_length; i = i + 1) 
                write_input_val(c, i, (c + 1) * 10 + i);

        for (f = 0; f < filter_number; f = f + 1)
            for (c = 0; c < input_channels; c = c + 1)
                for (k = 0; k < kernel_size; k = k + 1) 
                     write_weight_val(f, c, k, (f + 1) * 10 + (c + 1) * 5 + k + 1);

        start_whole = 1; @(posedge clk); start_whole = 0;
        wait(done_all);
        
        $display("--- Final Readout ---");
        read_mode_output_result = 1;
        for (i = 0; i < out_len; i = i + 1) read_output_single_lane(0, i, out_len);
        read_mode_output_result = 0;
        perform_system_reset();

        // --------------------------------------------------------------------
        // TEST 3: Multi-Filter + Bias
        // --------------------------------------------------------------------
        $display("\n>>> TEST 3: Multi-Filter + Bias (Unique Bias/Weights/Inputs)");
        stride = 2'd1; padding = 3'd0; kernel_size = 5'd3;
        input_channels = 10'd2; temporal_length = 10'd8; filter_number = 10'd3;
        out_len = (temporal_length + 2*padding - kernel_size) / stride + 1;

        zero_all_outputs(filter_number, out_len);

        // Bias Pattern
        for (f = 0; f < filter_number; f = f + 1)
             for (i = 0; i < out_len; i = i + 1) 
                 write_bias_val(f, i, out_len, (f + 1) * 100);

        for (c = 0; c < input_channels; c = c + 1)
            for (i = 0; i < temporal_length; i = i + 1) 
                write_input_val(c, i, (c + 1) * 10 + i);

        for (f = 0; f < filter_number; f = f + 1)
            for (c = 0; c < input_channels; c = c + 1)
                for (k = 0; k < kernel_size; k = k + 1) 
                     write_weight_val(f, c, k, (f + 1) * 10 + (c + 1) * 5 + k + 1);

        start_whole = 1; @(posedge clk); start_whole = 0;
        wait(done_all);
        
        $display("--- Final Readout ---");
        read_mode_output_result = 1;
        for (f = 0; f < filter_number; f = f + 1) begin
            $display("Filter %0d:", f);
            for (i = 0; i < out_len; i = i + 1) read_output_single_lane(f, i, out_len);
        end
        read_mode_output_result = 0;

        $display("\n--- All Tests Finished ---");
        $finish;
    end

endmodule