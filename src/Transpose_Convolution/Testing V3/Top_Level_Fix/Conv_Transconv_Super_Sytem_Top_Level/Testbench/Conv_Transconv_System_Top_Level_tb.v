`timescale 1ns / 1ps

/******************************************************************************
 * Conv_Transconv_System_Top_Level Testbench with Bias Pre-loading
 * 
 * Features:
 * - Load Weight, Ifmap, and Bias in parallel for each layer
 * - Layer-specific bias distribution based on output buffer configuration
 * - Automated bias mapping to BRAM striped architecture
 ******************************************************************************/

module Conv_Transconv_System_Top_Level_tb();
    localparam T = 10;
    
    // ========================================================================
    // Parameters for Memory Files
    // ========================================================================
    parameter WEIGHT_MEM_FILE = "G_d5_Q10_10_decoder_weight.mem";
    parameter BIAS_MEM_FILE = "G_d5_Q10_10_decoder_bias.mem";
    parameter IFMAP_MEM_FILE = "input_ifmap.mem";
    
    // Memory depth
    parameter WEIGHT_MEM_DEPTH = 217088;
    parameter BIAS_MEM_DEPTH = 32768;  // 4 layers × 8192
    parameter IFMAP_MEM_DEPTH = 16384;
    parameter OUTPUT_MEM_DEPTH = 16384;  // Extended for Layer 3: 16 × 512 = 8192, doubled for safety
    
    // ========================================================================
    // Layer Configuration (Output Buffer)
    // ========================================================================
    // Layer 0: 128 channels × 64 positions = 8192
    // Layer 1: 64 channels × 128 positions = 8192
    // Layer 2: 32 channels × 256 positions = 8192
    // Layer 3: 16 channels × 512 positions = 8192
    
    // ========================================================================
    // DDR Memory Structures
    // ========================================================================
    reg [19:0] weight_ddr_mem [0:WEIGHT_MEM_DEPTH-1];
    reg [19:0] bias_ddr_mem [0:BIAS_MEM_DEPTH-1];
    reg [15:0] ifmap_ddr_mem [0:IFMAP_MEM_DEPTH-1];
    reg [15:0] output_captured_mem [0:OUTPUT_MEM_DEPTH-1];
    
    integer output_write_ptr;
    
    // ========================================================================
    // DUT Signals
    // ========================================================================
    reg             aclk;
    reg             aresetn;

    // AXI Stream 0 - Weight
    reg  [15:0]     s0_axis_tdata;
    reg             s0_axis_tvalid;
    wire            s0_axis_tready;
    reg             s0_axis_tlast;
    wire [15:0]     m0_axis_tdata;
    wire            m0_axis_tvalid;
    reg             m0_axis_tready;
    wire            m0_axis_tlast;

    // AXI Stream 1 - Ifmap
    reg  [15:0]     s1_axis_tdata;
    reg             s1_axis_tvalid;
    wire            s1_axis_tready;
    reg             s1_axis_tlast;
    wire [15:0]     m1_axis_tdata;
    wire            m1_axis_tvalid;
    reg             m1_axis_tready;
    wire            m1_axis_tlast;

    // AXI Stream 2 - Bias
    reg  [15:0]     s2_axis_tdata;
    reg             s2_axis_tvalid;
    wire            s2_axis_tready;
    reg             s2_axis_tlast;

    // Status signals
    wire       weight_write_done;
    wire       ifmap_write_done;
    wire       bias_write_done;
    wire       scheduler_done;
    wire [1:0] current_layer_id;
    wire [2:0] current_batch_id;
    wire       all_batches_done;
    
    reg        layer_readout_done;

    // ========================================================================
    // Latency Measurement
    // ========================================================================
    reg [63:0] cycle_count;
    reg [63:0] start_time_l0, start_time_l1, start_time_l2, start_time_l3;
    reg [63:0] end_time_l0, end_time_l1, end_time_l2, end_time_l3;
    reg [63:0] total_start_time;

    // ========================================================================
    // Bias JSON Configuration
    // ========================================================================
    localparam BIAS_LAYER_0_OFFSET = 0;      // 128 ch × 64 pos
    localparam BIAS_LAYER_1_OFFSET = 8192;   // 64 ch × 128 pos
    localparam BIAS_LAYER_2_OFFSET = 16384;  // 32 ch × 256 pos
    localparam BIAS_LAYER_3_OFFSET = 24576;  // 16 ch × 512 pos
    
    // ========================================================================
    // Dummy Wires for Unused DUT Outputs
    // ========================================================================
    wire weight_read_done_dummy, ifmap_read_done_dummy, weight_error_invalid_magic_dummy, ifmap_error_invalid_magic_dummy, bias_error_invalid_magic_dummy, auto_start_active_dummy;
    wire [15:0] weight_mm2s_data_count_dummy, ifmap_mm2s_data_count_dummy;
    wire [2:0] weight_parser_state_dummy, ifmap_parser_state_dummy, bias_parser_state_dummy;
    
    // ========================================================================
    // DUT Instantiation
    // ========================================================================
    System_Level_Top #(
        .DW(16), .NUM_BRAMS(16), .W_ADDR_W(11), .I_ADDR_W(10), .O_ADDR_W(9),
        .W_DEPTH(2048), .I_DEPTH(1024), .O_DEPTH(512), .Dimension(16)
    ) dut (
        .aclk(aclk), 
        .aresetn(aresetn),
        
        .s0_axis_tdata(s0_axis_tdata), 
        .s0_axis_tvalid(s0_axis_tvalid), 
        .s0_axis_tready(s0_axis_tready), 
        .s0_axis_tlast(s0_axis_tlast),
        
        .m0_axis_tdata(m0_axis_tdata), 
        .m0_axis_tvalid(m0_axis_tvalid), 
        .m0_axis_tready(m0_axis_tready), 
        .m0_axis_tlast(m0_axis_tlast),
        
        .s1_axis_tdata(s1_axis_tdata), 
        .s1_axis_tvalid(s1_axis_tvalid), 
        .s1_axis_tready(s1_axis_tready), 
        .s1_axis_tlast(s1_axis_tlast),
        
        .m1_axis_tdata(m1_axis_tdata), 
        .m1_axis_tvalid(m1_axis_tvalid), 
        .m1_axis_tready(m1_axis_tready), 
        .m1_axis_tlast(m1_axis_tlast),
        
        .s2_axis_tdata(s2_axis_tdata), 
        .s2_axis_tvalid(s2_axis_tvalid), 
        .s2_axis_tready(s2_axis_tready), 
        .s2_axis_tlast(s2_axis_tlast),
        
        .ext_start(1'b0), 
        .ext_layer_id(2'd0),
        
        .weight_write_done(weight_write_done), 
        .ifmap_write_done(ifmap_write_done),
        .bias_write_done(bias_write_done),
        .scheduler_done(scheduler_done), 
        .current_layer_id(current_layer_id), 
        .current_batch_id(current_batch_id), 
        .all_batches_done(all_batches_done),
        
        .weight_read_done(weight_read_done_dummy), 
        .ifmap_read_done(ifmap_read_done_dummy), 
        .weight_mm2s_data_count(weight_mm2s_data_count_dummy), 
        .ifmap_mm2s_data_count(ifmap_mm2s_data_count_dummy),
        .weight_parser_state(weight_parser_state_dummy), 
        .weight_error_invalid_magic(weight_error_invalid_magic_dummy), 
        .ifmap_parser_state(ifmap_parser_state_dummy), 
        .ifmap_error_invalid_magic(ifmap_error_invalid_magic_dummy),
        .bias_parser_state(bias_parser_state_dummy),
        .bias_error_invalid_magic(bias_error_invalid_magic_dummy),
        .auto_start_active(auto_start_active_dummy)
    );

    // ========================================================================
    // Clock Generation (100MHz)
    // ========================================================================
    initial aclk = 0;
    always #(T/2) aclk = ~aclk;

    // ========================================================================
    // Cycle Counter
    // ========================================================================
    always @(posedge aclk) begin
        if (!aresetn) 
            cycle_count <= 0;
        else 
            cycle_count <= cycle_count + 1;
    end

    // ========================================================================
    // Output Capture Logic (Dual Stream)
    // ========================================================================
    integer m1_output_ptr;
    
    always @(posedge aclk) begin
        if (!aresetn) begin
            output_write_ptr <= 0;
            m1_output_ptr <= 0;
        end else begin
            // Capture from m0_axis (BRAMs 0-7)
            if (m0_axis_tvalid && m0_axis_tready) begin
                output_captured_mem[output_write_ptr] <= m0_axis_tdata;
                $display("[DDR WRITE M0] Time: %0t | Addr: %0d | Data: %h", 
                         $time, output_write_ptr, m0_axis_tdata);
                output_write_ptr <= output_write_ptr + 1;
            end
            
            // Capture from m1_axis (BRAMs 8-15)
            if (m1_axis_tvalid && m1_axis_tready) begin
                output_captured_mem[OUTPUT_MEM_DEPTH/2 + m1_output_ptr] <= m1_axis_tdata;
                $display("[DDR WRITE M1] Time: %0t | Addr: %0d | Data: %h", 
                         $time, OUTPUT_MEM_DEPTH/2 + m1_output_ptr, m1_axis_tdata);
                m1_output_ptr <= m1_output_ptr + 1;
            end
        end
    end

    // ========================================================================
    // Monitor Logic for Batch Completion
    // ========================================================================
    integer rx0_count, rx0_data_count;
    reg [15:0] notif_header [0:5];
    reg notif_detected, in_data_phase;

    always @(posedge aclk) begin
        if (!aresetn) begin
            rx0_count <= 0; 
            rx0_data_count <= 0; 
            notif_detected <= 0; 
            in_data_phase <= 0; 
            layer_readout_done <= 0;
        end else begin
            notif_detected <= 0; 
            layer_readout_done <= 0;
            
            if (m0_axis_tvalid && m0_axis_tready) begin
                if (!in_data_phase) begin 
                    if (rx0_count < 6) 
                        notif_header[rx0_count] <= m0_axis_tdata;
                    
                    if (m0_axis_tlast) begin
                        if (notif_header[0] == 16'hC0DE) begin
                             $display("[%0t] [M0] NOTIF: Batch %0d Complete (Layer %0d, Cycle: %0d)", 
                                     $time, notif_header[2][2:0], current_layer_id, cycle_count);
                             notif_detected <= 1;
                        end
                        rx0_count <= 0;
                    end else if (rx0_count == 5) begin 
                        in_data_phase <= 1; 
                        rx0_count <= rx0_count + 1; 
                        rx0_data_count <= 0;
                        if (notif_header[0] == 16'hDA7A) 
                            $display("[%0t] [M0] === FULL DATA DUMP STARTED (Layer %0d) ===", 
                                    $time, current_layer_id);
                    end else 
                        rx0_count <= rx0_count + 1;
                end else begin
                    rx0_data_count <= rx0_data_count + 1; 
                    rx0_count <= rx0_count + 1;
                    
                    if (m0_axis_tlast) begin
                        $display("[%0t] [M0] === FULL DATA DUMP COMPLETE (Layer %0d, %0d words) ===", 
                                $time, current_layer_id, rx0_data_count);
                        layer_readout_done <= 1; 
                        rx0_count <= 0; 
                        rx0_data_count <= 0; 
                        in_data_phase <= 0;
                    end
                end
            end
        end
    end

    // ========================================================================
    // Task: Send One Word via AXI Stream
    // ========================================================================
    task send_one_word_weight;
        input [15:0] data; 
        input p_is_last;
        begin
            s0_axis_tdata = data; 
            s0_axis_tvalid = 1; 
            s0_axis_tlast = p_is_last;
            @(posedge aclk); 
            while (!s0_axis_tready) @(posedge aclk);
            #1; 
            s0_axis_tvalid = 0; 
            s0_axis_tlast = 0;
        end
    endtask

    task send_one_word_ifmap;
        input [15:0] data; 
        input p_is_last;
        begin
            s1_axis_tdata = data; 
            s1_axis_tvalid = 1; 
            s1_axis_tlast = p_is_last;
            @(posedge aclk); 
            while (!s1_axis_tready) @(posedge aclk);
            #1; 
            s1_axis_tvalid = 0; 
            s1_axis_tlast = 0;
        end
    endtask

    task send_one_word_bias;
        input [15:0] data; 
        input p_is_last;
        begin
            s2_axis_tdata = data; 
            s2_axis_tvalid = 1; 
            s2_axis_tlast = p_is_last;
            @(posedge aclk); 
            while (!s2_axis_tready) @(posedge aclk);
            #1; 
            s2_axis_tvalid = 0; 
            s2_axis_tlast = 0;
        end
    endtask

    // ========================================================================
    // Task: Send Weight Packet from DDR
    // ========================================================================
    task send_weight_packet_from_ddr;
        input [4:0] bram_start;
        input [4:0] bram_end;
        input [15:0] num_words;
        input integer offset;
        begin
            integer i, j, ddr_idx;
            
            send_one_word_weight(16'hC0DE, 0);
            send_one_word_weight(16'h0001, 0);
            send_one_word_weight({11'h0, bram_start}, 0);
            send_one_word_weight({11'h0, bram_end}, 0);
            send_one_word_weight(16'd0, 0);
            send_one_word_weight(num_words, 0);
            
            ddr_idx = offset;
            for (j = bram_start; j <= bram_end; j = j + 1) begin
                for (i = 0; i < num_words; i = i + 1) begin
                    send_one_word_weight(weight_ddr_mem[ddr_idx][15:0], 
                                       (j==bram_end && i==num_words-1));
                    ddr_idx = ddr_idx + 1;
                end
            end
            
            wait(weight_write_done); 
            @(posedge aclk);
        end
    endtask

    // ========================================================================
    // Task: Send Ifmap Packet from DDR (Generic)
    // ========================================================================
    task send_ifmap_packet_from_ddr;
        input [4:0] bram_start;
        input [4:0] bram_end;
        input [15:0] num_words;
        input integer offset;
        begin
            integer i, j, ddr_idx;
            
            send_one_word_ifmap(16'hC0DE, 0);
            send_one_word_ifmap(16'h0001, 0);
            send_one_word_ifmap({11'h0, bram_start}, 0);
            send_one_word_ifmap({11'h0, bram_end}, 0);
            send_one_word_ifmap(16'd0, 0);
            send_one_word_ifmap(num_words, 0);
            
            ddr_idx = offset;
            for (j = bram_start; j <= bram_end; j = j + 1) begin
                for (i = 0; i < num_words; i = i + 1) begin
                    send_one_word_ifmap(ifmap_ddr_mem[ddr_idx], 
                                      (j==bram_end && i==num_words-1));
                    ddr_idx = ddr_idx + 1;
                end
            end
            
            wait(ifmap_write_done); 
            @(posedge aclk);
        end
    endtask

    // ========================================================================
    // Task: Send Ifmap Layer 3 with Striping (Shape [64, 256])
    // ========================================================================
    // Input file: increment Y first, then X
    // File: Row0[0:255], Row1[0:255], ..., Row63[0:255]
    // BRAM mapping: BRAM_k receives rows: k, k+16, k+32, k+48
    task send_ifmap_layer3_striped;
        begin
            integer bram_id, row_group, col, row_idx, file_idx;
            integer word_count, total_words;
            
            total_words = 16 * 1024;  // 16 BRAMs × 1024 words
            word_count = 0;
            
            // Send header
            send_one_word_ifmap(16'hC0DE, 0);
            send_one_word_ifmap(16'h0001, 0);
            send_one_word_ifmap({11'h0, 5'd0}, 0);    // BRAM start = 0
            send_one_word_ifmap({11'h0, 5'd15}, 0);   // BRAM end = 15
            send_one_word_ifmap(16'd0, 0);            // Addr start = 0
            send_one_word_ifmap(16'd1024, 0);         // Num words per BRAM = 1024
            
            $display("[%0t] Starting Layer 3 Ifmap loading (striped)...", $time);
            
            // Stream data in BRAM order (BRAM 0 to 15)
            for (bram_id = 0; bram_id < 16; bram_id = bram_id + 1) begin
                // Each BRAM receives 4 rows: k, k+16, k+32, k+48
                for (row_group = 0; row_group < 4; row_group = row_group + 1) begin
                    row_idx = bram_id + (row_group * 16);
                    
                    // Send all 256 columns for this row
                    for (col = 0; col < 256; col = col + 1) begin
                        file_idx = (row_idx * 256) + col;
                        word_count = word_count + 1;
                        
                        send_one_word_ifmap(ifmap_ddr_mem[file_idx], 
                                          (word_count == total_words));
                    end
                end
                
                if ((bram_id % 4) == 3) begin
                    $display("[%0t]   BRAMs %0d-%0d loaded", $time, bram_id-3, bram_id);
                end
            end
            
            wait(ifmap_write_done);
            @(posedge aclk);
            
            $display("[%0t] Layer 3 Ifmap loading complete", $time);
        end
    endtask

    // ========================================================================
    // Task: Send Bias Packet with BRAM Striping
    // ========================================================================
    // Maps sequential channel bias to striped BRAM architecture
    // BRAM k receives: Ch_k, Ch_(k+16), Ch_(k+32), Ch_(k+48)
    task send_bias_packet_striped;
        input [1:0] layer_id;
        input integer bias_offset;  // Offset in bias_ddr_mem
        input integer num_channels;  // Total channels for this layer
        input integer positions_per_ch;  // Positions per channel
        begin
            integer bram_id, ch_group, pos, ch_idx, mem_idx;
            integer total_words;
            integer word_count;
            
            total_words = num_channels * positions_per_ch;
            
            // Send header
            send_one_word_bias(16'hC0DE, 0);
            send_one_word_bias(16'h0001, 0);
            send_one_word_bias({11'h0, 5'd0}, 0);   // BRAM start = 0
            send_one_word_bias({11'h0, 5'd15}, 0);  // BRAM end = 15
            send_one_word_bias(16'd0, 0);           // Addr start = 0
            send_one_word_bias(16'd512, 0);         // Num words per BRAM = 512
            
            word_count = 0;
            
            // Stream bias data with striped mapping
            for (bram_id = 0; bram_id < 16; bram_id = bram_id + 1) begin
                // Each BRAM receives 4 channel groups (if num_channels >= 64)
                // For 16 BRAMs × 512 depth = 8192 total
                for (ch_group = 0; ch_group < 4; ch_group = ch_group + 1) begin
                    ch_idx = bram_id + (ch_group * 16);
                    
                    if (ch_idx < num_channels) begin
                        // Send all positions for this channel
                        for (pos = 0; pos < positions_per_ch; pos = pos + 1) begin
                            mem_idx = bias_offset + (ch_idx * positions_per_ch) + pos;
                            word_count = word_count + 1;
                            
                            send_one_word_bias(bias_ddr_mem[mem_idx][15:0],
                                             (word_count == total_words));
                        end
                    end else begin
                        // Pad with zeros if channel doesn't exist
                        for (pos = 0; pos < positions_per_ch; pos = pos + 1) begin
                            word_count = word_count + 1;
                            send_one_word_bias(16'h0, (word_count == total_words));
                        end
                    end
                end
            end
            
            wait(bias_write_done);
            @(posedge aclk);
            
            $display("[%0t] Bias loaded for Layer %0d: %0d channels × %0d pos", 
                     $time, layer_id, num_channels, positions_per_ch);
        end
    endtask

    // ========================================================================
    // Task: Wait for Batch Notification
    // ========================================================================
    task wait_for_notification;
        input [2:0] expected_batch;
        begin
            @(posedge notif_detected);
        end
    endtask

    // ========================================================================
    // MAIN TEST SEQUENCE
    // ========================================================================
    initial begin
        $display("[%0t] Loading memory files...", $time);
        $readmemh(WEIGHT_MEM_FILE, weight_ddr_mem);
        $readmemh(BIAS_MEM_FILE, bias_ddr_mem);
        //$readmemh(IFMAP_MEM_FILE, ifmap_ddr_mem);
        $display("[%0t] Memory files loaded", $time);
        
        aresetn = 0;
        s0_axis_tdata = 0; s0_axis_tvalid = 0; s0_axis_tlast = 0; m0_axis_tready = 1;
        s1_axis_tdata = 0; s1_axis_tvalid = 0; s1_axis_tlast = 0; m1_axis_tready = 1;
        s2_axis_tdata = 0; s2_axis_tvalid = 0; s2_axis_tlast = 0;
        
        output_write_ptr = 0;
        
        #(T*10); 
        aresetn = 1; 
        #(T*20);

        total_start_time = cycle_count;

        // =====================================================================
        // LAYER 0: 128 channels × 64 positions
        // =====================================================================
        $display("\n[%0t] ========== LAYER 0 START ==========", $time);
        start_time_l0 = cycle_count;

        // Parallel load: Weight + Ifmap + Bias
        fork
            begin
                send_ifmap_packet_from_ddr(5'd0, 5'd15, 16'd1024, 0);
                $display("[%0t] [L0] IFMAP DONE", $time);
            end
            begin
                send_weight_packet_from_ddr(5'd0, 5'd15, 16'd1024, 0);
                $display("[%0t] [L0] WEIGHT B0 DONE", $time);
            end
            begin
                send_bias_packet_striped(2'd0, BIAS_LAYER_0_OFFSET, 128, 64);
                $display("[%0t] [L0] BIAS DONE", $time);
            end
        join
        
        wait_for_notification(3'd0);
        
        // Additional batches for layer 0...
        // (simplified - add more batches as needed)
        
        wait(layer_readout_done);
        end_time_l0 = cycle_count;
        $display("[%0t] >>> LAYER 0 DONE. Latency: %0d cycles <<<\n", 
                 $time, (end_time_l0 - start_time_l0));

        // =====================================================================
        // LAYER 1: 64 channels × 128 positions
        // =====================================================================
        $display("\n[%0t] ========== LAYER 1 START ==========", $time);
        start_time_l1 = cycle_count;

        fork
            begin send_ifmap_packet_from_ddr(5'd0, 5'd15, 16'd1024, 16384); end
            begin send_weight_packet_from_ddr(5'd0, 5'd15, 16'd1024, 131072); end
            begin send_bias_packet_striped(2'd1, BIAS_LAYER_1_OFFSET, 64, 128); end
        join
        
        wait_for_notification(3'd0);
        wait(layer_readout_done);
        end_time_l1 = cycle_count;
        $display("[%0t] >>> LAYER 1 DONE. Latency: %0d cycles <<<\n", 
                 $time, (end_time_l1 - start_time_l1));

        // =====================================================================
        // LAYER 2: 32 channels × 256 positions
        // =====================================================================
        $display("\n[%0t] ========== LAYER 2 START ==========", $time);
        start_time_l2 = cycle_count;

        fork
            begin send_ifmap_packet_from_ddr(5'd0, 5'd15, 16'd1024, 32768); end
            begin send_weight_packet_from_ddr(5'd0, 5'd15, 16'd1024, 196608); end
            begin send_bias_packet_striped(2'd2, BIAS_LAYER_2_OFFSET, 32, 256); end
        join
        
        wait_for_notification(3'd0);
        wait(layer_readout_done);
        end_time_l2 = cycle_count;
        $display("[%0t] >>> LAYER 2 DONE. Latency: %0d cycles <<<\n", 
                 $time, (end_time_l2 - start_time_l2));

        // =====================================================================
        // LAYER 3: 16 channels × 512 positions
        // =====================================================================
        $display("\n[%0t] ========== LAYER 3 START ==========", $time);
        start_time_l3 = cycle_count;

        fork
            begin send_ifmap_layer3_striped(); end  // NEW: Striped loading for Layer 3
            begin send_weight_packet_from_ddr(5'd0, 5'd15, 16'd256, 212992); end
            begin send_bias_packet_striped(2'd3, BIAS_LAYER_3_OFFSET, 16, 512); end
        join
        
        wait_for_notification(3'd0);
        wait(layer_readout_done);
        end_time_l3 = cycle_count;
        $display("[%0t] >>> LAYER 3 DONE. Latency: %0d cycles <<<\n", 
                 $time, (end_time_l3 - start_time_l3));

        // =====================================================================
        // DISPLAY LAYER 3 OUTPUT (16 BRAMs × 512 depth)
        // =====================================================================
        #(T*100);
        $display("\n");
        $display("=================================================================");
        $display("LAYER 3 OUTPUT DISPLAY (16 BRAMs × 512 Depth)");
        $display("=================================================================");
        
        display_layer3_output();
        
        // =====================================================================
        // PERFORMANCE REPORT
        // =====================================================================
        #(T*100);
        $display("\n=================================================================");
        $display("PERFORMANCE REPORT");
        $display("=================================================================");
        $display("Layer 0 Latency : %0d cycles (128ch × 64pos)", (end_time_l0 - start_time_l0));
        $display("Layer 1 Latency : %0d cycles (64ch × 128pos)", (end_time_l1 - start_time_l1));
        $display("Layer 2 Latency : %0d cycles (32ch × 256pos)", (end_time_l2 - start_time_l2));
        $display("Layer 3 Latency : %0d cycles (16ch × 512pos)", (end_time_l3 - start_time_l3));
        $display("-----------------------------------------------------------------");
        $display("TOTAL TIME      : %0d cycles", (cycle_count - total_start_time));
        $display("=================================================================\n");

        #(T*100);
        $finish;
    end

    // ========================================================================
    // Task: Display Layer 3 Output (16 BRAMs × 512 depth)
    // ========================================================================
    task display_layer3_output;
        begin
            integer bram_id, addr, file_handle;
            integer linear_idx;
            reg [15:0] data_value;
            
            // Open file untuk save output
            file_handle = $fopen("layer3_output_display.txt", "w");
            
            $display("Displaying Layer 3 Output to console and file...");
            $fwrite(file_handle, "=================================================================\n");
            $fwrite(file_handle, "LAYER 3 OUTPUT (16 Channels × 512 Positions)\n");
            $fwrite(file_handle, "=================================================================\n\n");
            
            // Display per BRAM
            for (bram_id = 0; bram_id < 16; bram_id = bram_id + 1) begin
                $display("\n--- BRAM %0d (Channel %0d) ---", bram_id, bram_id);
                $fwrite(file_handle, "\n--- BRAM %0d (Channel %0d) ---\n", bram_id, bram_id);
                
                // Display all 512 addresses
                for (addr = 0; addr < 512; addr = addr + 1) begin
                    // Calculate linear index in captured memory
                    // BRAMs 0-7 from m0_axis (first half)
                    // BRAMs 8-15 from m1_axis (second half)
                    if (bram_id < 8) begin
                        // From m0_axis stream
                        linear_idx = (bram_id * 512) + addr;
                    end else begin
                        // From m1_axis stream
                        linear_idx = ((bram_id - 8) * 512) + addr + (OUTPUT_MEM_DEPTH/2);
                    end
                    
                    data_value = output_captured_mem[linear_idx];
                    
                    // Display every 32nd value to console (to avoid clutter)
                    if ((addr % 32) == 0) begin
                        $display("  [%03d]: %h (linear_idx=%0d)", addr, data_value, linear_idx);
                    end
                    
                    // Write all values to file
                    $fwrite(file_handle, "[BRAM%02d][%03d]: %h\n", bram_id, addr, data_value);
                end
            end
            
            $display("\n");
            $fwrite(file_handle, "\n=================================================================\n");
            $fwrite(file_handle, "Total values displayed: 8192 (16 BRAMs × 512 depth)\n");
            $fwrite(file_handle, "=================================================================\n");
            
            $fclose(file_handle);
            $display("Layer 3 output saved to: layer3_output_display.txt");
            $display("=================================================================\n");
        end
    endtask

    // ========================================================================
    // Watchdog Timer
    // ========================================================================
    initial begin
        #(T*200000000); 
        $display("\n[%0t] !!! TIMEOUT WATCHDOG !!!", $time);
        $finish;
    end

endmodule