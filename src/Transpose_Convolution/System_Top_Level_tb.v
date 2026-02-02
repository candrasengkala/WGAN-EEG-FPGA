`timescale 1ns / 1ps
//tucadonka - FIXED VERSION
module System_Level_Top_tb();

    localparam T = 10;
    localparam DW = 24; 
    
    // ========================================================================
    // 1. PARAMETERS
    // ========================================================================
    parameter WEIGHT_MEM_FILE = "G_d5_Q9.14_decoder_weight.mem";
    parameter BIAS_MEM_FILE   = "G_d5_Q9.14_decoder_bias.mem";
    parameter IFMAP_MEM_FILE  = "decoder_last_input_hex.mem";
    
    parameter WEIGHT_MEM_DEPTH = 217088;
    parameter BIAS_MEM_DEPTH   = 32768;
    parameter IFMAP_MEM_DEPTH  = 16384;
    parameter OUTPUT_MEM_DEPTH = 16384;

    // ========================================================================
    // 2. GLOBAL VARIABLES (ISOLATED FOR PARALLEL SAFETY)
    // ========================================================================
    
    // Memory Arrays
    reg [31:0] weight_ddr_mem [0:WEIGHT_MEM_DEPTH-1];
    reg [31:0] bias_ddr_mem   [0:BIAS_MEM_DEPTH-1];
    reg [31:0] ifmap_ddr_mem  [0:IFMAP_MEM_DEPTH-1];
    reg [DW-1:0] output_captured_mem [0:OUTPUT_MEM_DEPTH-1];
    
    // Monitor
    reg [23:0] notif_header [0:5];
    reg notif_detected, in_data_phase;
    integer rx0_count, rx0_data_count;
    integer output_write_ptr, m1_output_ptr;
    integer file_handle;
    reg     is_layer3_output;
    
    // Layer 3 dual stream buffer
    reg [23:0] m0_buf [0:4095];
    reg [23:0] m1_buf [0:4095];
    reg        m0_done, m1_done;
    integer    m0_cnt, m1_cnt;
    integer    ppos, pch;

    // --- VARIABLES KHUSUS TASK (AGAR TIDAK BENTROK SAAT PARALEL) ---
    
    // Variables for Weight Task
    integer w_i, w_j, w_ddr_idx;
    
    // Variables for Ifmap Task
    integer i_i, i_j, i_ddr_idx;
    
    // Variables for Bias Task
    integer b_bram_id, b_ch_group, b_pos, b_ch_idx, b_mem_idx, b_total_words, b_word_count;
    
    // Variables for L3 Ifmap Task
    integer l3_bram_id, l3_pos_group, l3_channel, l3_position, l3_ddr_idx, l3_total_words, l3_word_count;
    
    // Variables for Display Task
    integer d_bram_id, d_addr, d_lin_idx;
    reg [23:0] d_val;

    // ========================================================================
    // 3. DUT SIGNALS
    // ========================================================================
    reg             aclk;
    reg             aresetn;

    reg  [DW-1:0]   s0_axis_tdata; reg s0_axis_tvalid; wire s0_axis_tready; reg s0_axis_tlast;
    wire [DW-1:0]   m0_axis_tdata; wire m0_axis_tvalid; reg m0_axis_tready; wire m0_axis_tlast;

    reg  [DW-1:0]   s1_axis_tdata; reg s1_axis_tvalid; wire s1_axis_tready; reg s1_axis_tlast;
    wire [DW-1:0]   m1_axis_tdata; wire m1_axis_tvalid; reg m1_axis_tready; wire m1_axis_tlast;

    reg  [DW-1:0]   s2_axis_tdata; reg s2_axis_tvalid; wire s2_axis_tready; reg s2_axis_tlast;

    wire       weight_write_done, ifmap_write_done, bias_write_done, scheduler_done;
    wire [1:0] current_layer_id;
    wire [2:0] current_batch_id;
    wire       all_batches_done;
    
    wire       weight_read_done, ifmap_read_done;
    wire [9:0] weight_mm2s_data_count, ifmap_mm2s_data_count;
    wire [2:0] weight_parser_state, ifmap_parser_state, bias_parser_state;
    wire       weight_error_invalid_magic, ifmap_error_invalid_magic, bias_error_invalid_magic;
    wire       auto_start_active;

    reg        layer_readout_done;
    reg [63:0] cycle_count;
    reg [63:0] start_time_l0, start_time_l1, start_time_l2, start_time_l3;
    reg [63:0] end_time_l0, end_time_l1, end_time_l2, end_time_l3;
    reg [63:0] total_start_time;

    localparam BIAS_LAYER_0_OFFSET = 0;
    localparam BIAS_LAYER_1_OFFSET = 8192;
    localparam BIAS_LAYER_2_OFFSET = 16384;
    localparam BIAS_LAYER_3_OFFSET = 24576;

    // ========================================================================
    // 4. DUT INSTANTIATION
    // ========================================================================
    System_Level_Top #(
        .DW(DW), .NUM_BRAMS(16), .W_ADDR_W(10), .I_ADDR_W(10), .O_ADDR_W(9),
        .W_DEPTH(1024), .I_DEPTH(1024), .O_DEPTH(512), .Dimension(16)
    ) dut (
        .aclk(aclk), .aresetn(aresetn),
        .s0_axis_tdata(s0_axis_tdata), .s0_axis_tvalid(s0_axis_tvalid), .s0_axis_tready(s0_axis_tready), .s0_axis_tlast(s0_axis_tlast),
        .m0_axis_tdata(m0_axis_tdata), .m0_axis_tvalid(m0_axis_tvalid), .m0_axis_tready(m0_axis_tready), .m0_axis_tlast(m0_axis_tlast),
        .s1_axis_tdata(s1_axis_tdata), .s1_axis_tvalid(s1_axis_tvalid), .s1_axis_tready(s1_axis_tready), .s1_axis_tlast(s1_axis_tlast),
        .m1_axis_tdata(m1_axis_tdata), .m1_axis_tvalid(m1_axis_tvalid), .m1_axis_tready(m1_axis_tready), .m1_axis_tlast(m1_axis_tlast),
        .s2_axis_tdata(s2_axis_tdata), .s2_axis_tvalid(s2_axis_tvalid), .s2_axis_tready(s2_axis_tready), .s2_axis_tlast(s2_axis_tlast),
        
        .ext_start(1'b0), // Use AUTO scheduler
        .ext_layer_id(2'd0),
        
        .weight_write_done(weight_write_done), .ifmap_write_done(ifmap_write_done), .bias_write_done(bias_write_done),
        .scheduler_done(scheduler_done), .current_layer_id(current_layer_id), .current_batch_id(current_batch_id), .all_batches_done(all_batches_done),
        
        .weight_read_done(weight_read_done), .ifmap_read_done(ifmap_read_done), 
        .weight_mm2s_data_count(weight_mm2s_data_count), .ifmap_mm2s_data_count(ifmap_mm2s_data_count),
        .weight_parser_state(weight_parser_state), .weight_error_invalid_magic(weight_error_invalid_magic), 
        .ifmap_parser_state(ifmap_parser_state), .ifmap_error_invalid_magic(ifmap_error_invalid_magic),
        .bias_parser_state(bias_parser_state), .bias_error_invalid_magic(bias_error_invalid_magic),
        .auto_start_active(auto_start_active)
    );

    // ========================================================================
    // 5. CLOCK & MONITORING
    // ========================================================================
    initial aclk = 0;
    always #(T/2) aclk = ~aclk;
    always @(posedge aclk) if (!aresetn) cycle_count <= 0; else cycle_count <= cycle_count + 1;

    always @(posedge aclk) begin
        if (!aresetn) begin output_write_ptr <= 0; m1_output_ptr <= 0; end 
        else begin
            if (m0_axis_tvalid && m0_axis_tready) begin
                output_captured_mem[output_write_ptr] <= m0_axis_tdata; output_write_ptr <= output_write_ptr + 1;
            end
            if (m1_axis_tvalid && m1_axis_tready) begin
                output_captured_mem[OUTPUT_MEM_DEPTH/2 + m1_output_ptr] <= m1_axis_tdata; m1_output_ptr <= m1_output_ptr + 1;
            end
        end
    end

    always @(posedge aclk) begin
        if (!aresetn) begin
            rx0_count <= 0; rx0_data_count <= 0; notif_detected <= 0; in_data_phase <= 0; layer_readout_done <= 0;
            is_layer3_output <= 0; m0_done <= 0; m0_cnt <= 0;
        end else begin
            notif_detected <= 0; layer_readout_done <= 0;
            if (m0_axis_tvalid && m0_axis_tready) begin
                if (!in_data_phase) begin 
                    if (rx0_count < 6) notif_header[rx0_count] <= m0_axis_tdata;
                    if (m0_axis_tlast) begin
                        if (notif_header[0][15:0] == 16'hC0DE) begin
                            notif_detected <= 1;
                        end
                        rx0_count <= 0;
                    end else if (rx0_count == 5) begin
                        in_data_phase <= 1; rx0_count <= rx0_count + 1; rx0_data_count <= 0;
                        m0_cnt <= 0; m0_done <= 0;
                        if (notif_header[0][15:0] == 16'hDA7A) begin
                            is_layer3_output <= (notif_header[2][1:0] == 2'd3);
                        end
                    end else rx0_count <= rx0_count + 1;
                end else begin
                    // DATA PHASE - ✅ FIX: TAMBAH CHECK in_data_phase!
                    if (is_layer3_output && in_data_phase) begin  // ← TAMBAH && in_data_phase
                        m0_buf[m0_cnt] <= m0_axis_tdata;
                        m0_cnt <= m0_cnt + 1;
                    end
                    
                    rx0_data_count <= rx0_data_count + 1; 
                    rx0_count <= rx0_count + 1;
                    
                    if (m0_axis_tlast) begin
                        if (is_layer3_output) begin
                            m0_done <= 1;
                        end else begin
                            layer_readout_done <= 1;
                        end
                        rx0_count <= 0;
                        rx0_data_count <= 0;
                        in_data_phase <= 0;
                        if (!is_layer3_output) is_layer3_output <= 0;
                    end
                end
            end
        end
    end

    always @(posedge aclk) begin
        if (!aresetn) begin
            m1_done <= 0; m1_cnt <= 0;
        end else begin
            if (m1_axis_tvalid && m1_axis_tready && is_layer3_output) begin
                m1_buf[m1_cnt] <= m1_axis_tdata;
                m1_cnt <= m1_cnt + 1;
                if (m1_axis_tlast) begin
                    m1_done <= 1;
                end
            end
        end
    end

    always @(posedge aclk) begin
        if (m0_done && m1_done) begin
            $display("=============================================================");
            $display("Position |  Ch0  |  Ch1  |  Ch2  |  Ch3  |  Ch4  |  Ch5  |  Ch6  |  Ch7  |  Ch8  |  Ch9  | Ch10  | Ch11  | Ch12  | Ch13  | Ch14  | Ch15  |");
            $display("---------|-------|-------|-------|-------|-------|-------|-------|-------|-------|-------|-------|-------|-------|-------|-------|-------|");
            
            // Data organization:
            // m0_buf: [BRAM0_all_512, BRAM1_all_512, ..., BRAM7_all_512]
            // m1_buf: [BRAM8_all_512, BRAM9_all_512, ..., BRAM15_all_512]
            // Each BRAM contains one channel: BRAM_n = Ch_n[Pos0-511]
            
            for (ppos = 0; ppos < 512; ppos = ppos + 1) begin
                $write("  %4d   |", ppos);
                
                // Ch0-7: BRAM 0-7 (from m0_buf)
                // BRAM_n data starts at offset n*512
                for (pch = 0; pch < 8; pch = pch + 1) 
                    $write(" %5d |", $signed(m0_buf[pch*512 + ppos]));
                
                // Ch8-15: BRAM 8-15 (from m1_buf)  
                // BRAM_n data starts at offset (n-8)*512
                for (pch = 0; pch < 8; pch = pch + 1) 
                    $write(" %5d |", $signed(m1_buf[pch*512 + ppos]));
                
                $write("\n");
            end
            
            $display("=============================================================");

            // ============================================================
            // FILE EXPORT: Per-Channel Format -> decoder_output_perchannel.txt
            // ============================================================
            file_handle = $fopen("decoder_output_perchannel.txt", "w");

            $fwrite(file_handle, "=============================================================\n");
            $fwrite(file_handle, "DECODER OUTPUT D5 - PER CHANNEL DUMP\n");
            $fwrite(file_handle, "Format: Channel -> 512 Posisi\n");
            $fwrite(file_handle, "=============================================================\n");

            // Channel 0-7 (from m0_buf)
            for (pch = 0; pch < 8; pch = pch + 1) begin
                $fwrite(file_handle, "\n=== CHANNEL %0d ===\n", pch);
                for (ppos = 0; ppos < 512; ppos = ppos + 1) begin
                    $fwrite(file_handle, "%0d\n", $signed(m0_buf[pch*512 + ppos]));
                end
            end

            // Channel 8-15 (from m1_buf)
            for (pch = 0; pch < 8; pch = pch + 1) begin
                $fwrite(file_handle, "\n=== CHANNEL %0d ===\n", pch + 8);
                for (ppos = 0; ppos < 512; ppos = ppos + 1) begin
                    $fwrite(file_handle, "%0d\n", $signed(m1_buf[pch*512 + ppos]));
                end
            end

            $fwrite(file_handle, "\n=============================================================\n");
            $fclose(file_handle);

            layer_readout_done <= 1;
            m0_done <= 0; m1_done <= 0; is_layer3_output <= 0;
        end
    end

    // ========================================================================
    // 6. PACKET SEND TASKS - Kirim sekali batch langsung
    // ========================================================================
    task send_one_word_weight;
        input [23:0] data; 
        input is_last;
        begin
            s0_axis_tdata = data; s0_axis_tvalid = 1; s0_axis_tlast = is_last;
            @(posedge aclk); while (!s0_axis_tready) @(posedge aclk);
            #1; s0_axis_tvalid = 0; s0_axis_tlast = 0;
        end
    endtask

    task send_one_word_ifmap;
        input [23:0] data; 
        input is_last;
        begin
            s1_axis_tdata = data; s1_axis_tvalid = 1; s1_axis_tlast = is_last;
            @(posedge aclk); while (!s1_axis_tready) @(posedge aclk);
            #1; s1_axis_tvalid = 0; s1_axis_tlast = 0;
        end
    endtask

    task send_one_word_bias;
        input [23:0] data; 
        input is_last;
        begin
            s2_axis_tdata = data; s2_axis_tvalid = 1; s2_axis_tlast = is_last;
            @(posedge aclk); while (!s2_axis_tready) @(posedge aclk);
            #1; s2_axis_tvalid = 0; s2_axis_tlast = 0;
        end
    endtask

    // ========================================================================
    // LAYER 3 WEIGHT LOADING - FIXED VERSION
    // ========================================================================
    // Layout file mem: Oc0[k0[Ich0-63], k1[Ich0-63], k2[Ich0-63], k3[Ich0-63]], 
    //                  Oc1[k0[Ich0-63], k1[Ich0-63], k2[Ich0-63], k3[Ich0-63]], ...
    //
    // Target BRAM layout:
    // BRAM 0 (k0): Oc0_k0[Ich0-63] + Oc4_k0[Ich0-63] + Oc8_k0[Ich0-63] + Oc12_k0[Ich0-63]
    // BRAM 1 (k1): Oc0_k1[Ich0-63] + Oc4_k1[Ich0-63] + Oc8_k1[Ich0-63] + Oc12_k1[Ich0-63]
    // BRAM 2 (k2): Oc0_k2[Ich0-63] + Oc4_k2[Ich0-63] + Oc8_k2[Ich0-63] + Oc12_k2[Ich0-63]
    // BRAM 3 (k3): Oc0_k3[Ich0-63] + Oc4_k3[Ich0-63] + Oc8_k3[Ich0-63] + Oc12_k3[Ich0-63]
    // ...
    
    task send_packet_weight_layer3;
        input [31:0] ddr_offset;
        integer bram_id, k_pos, oc_in_tile, tile, oc_absolute, cin, ddr_addr, word_count, bram_addr;
        begin
            send_one_word_weight(24'h00C0DE, 0);
            send_one_word_weight(24'h000001, 0);
            send_one_word_weight({19'h0, 5'd0}, 0);
            send_one_word_weight({19'h0, 5'd15}, 0);
            send_one_word_weight(24'd0, 0);
            send_one_word_weight(16'd256, 0);
            
            word_count = 0;
            
            // 16 BRAMs
            for (bram_id = 0; bram_id < 16; bram_id = bram_id + 1) begin
                k_pos = bram_id[1:0];
                oc_in_tile = bram_id[3:2];
                
                // 4 tiles sequentially in this BRAM
                for (tile = 0; tile < 4; tile = tile + 1) begin
                    oc_absolute = tile * 4 + oc_in_tile;
                    
                    // 64 input channels = 64 consecutive addresses
                    for (cin = 0; cin < 64; cin = cin + 1) begin
                        bram_addr = tile * 64 + cin;  // 0-63, 64-127, 128-191, 192-255
                        ddr_addr = ddr_offset + (oc_absolute * 256) + (k_pos * 64) + cin;
                        word_count = word_count + 1;
                        send_one_word_weight(weight_ddr_mem[ddr_addr][23:0], (word_count == 4096));
                    end
                end
            end
            
            wait(weight_write_done); 
            @(posedge aclk);
        end
    endtask

    task send_packet_bias_layer3;
        input [31:0] bias_offset;
        integer l3b_bram_id, l3b_pos, l3b_ddr_idx, l3b_total_words, l3b_word_count;
        begin
            l3b_total_words = 16 * 512;
            l3b_word_count = 0;
            
            send_one_word_bias(24'h00C0DE, 0);
            send_one_word_bias(24'h000001, 0);
            send_one_word_bias({19'h0, 5'd0}, 0);
            send_one_word_bias({19'h0, 5'd15}, 0);
            send_one_word_bias(24'd0, 0);
            send_one_word_bias(16'd512, 0);
            
            for (l3b_bram_id = 0; l3b_bram_id < 16; l3b_bram_id = l3b_bram_id + 1) begin
                for (l3b_pos = 0; l3b_pos < 512; l3b_pos = l3b_pos + 1) begin
                    l3b_ddr_idx = bias_offset + (l3b_bram_id * 512) + l3b_pos;
                    l3b_word_count = l3b_word_count + 1;
                    send_one_word_bias(
                        bias_ddr_mem[l3b_ddr_idx][23:0], 
                        (l3b_word_count == l3b_total_words)
                    );
                end
            end
            
            wait(bias_write_done); 
            @(posedge aclk);
        end
    endtask

    task send_ifmap_layer3_stride16;
        begin
            l3_total_words = 16 * 1024;
            l3_word_count = 0;
            
            send_one_word_ifmap(24'h00C0DE, 0);
            send_one_word_ifmap(24'h000001, 0);
            send_one_word_ifmap({19'h0, 5'd0}, 0);
            send_one_word_ifmap({19'h0, 5'd15}, 0);
            send_one_word_ifmap(24'd0, 0);
            send_one_word_ifmap(24'd1024, 0);
            
            for (l3_bram_id = 0; l3_bram_id < 16; l3_bram_id = l3_bram_id + 1) begin
                for (l3_pos_group = 0; l3_pos_group < 16; l3_pos_group = l3_pos_group + 1) begin
                    l3_position = l3_bram_id + (l3_pos_group * 16);
                    for (l3_channel = 0; l3_channel < 64; l3_channel = l3_channel + 1) begin
                        l3_ddr_idx = (l3_position * 64) + l3_channel;
                        l3_word_count = l3_word_count + 1;
                        send_one_word_ifmap(
                            ifmap_ddr_mem[l3_ddr_idx][23:0], 
                            (l3_word_count == l3_total_words)
                        );
                    end
                end
            end
            
            wait(ifmap_write_done); 
            @(posedge aclk);
        end
    endtask

    // ========================================================================
    // ZERO TEST TASKS
    // ========================================================================
    
    task send_packet_weight_zeros;
        input [4:0] start_bram; 
        input [4:0] end_bram; 
        input [15:0] num_words; 
        begin
            send_one_word_weight(24'h00C0DE, 0); 
            send_one_word_weight(24'h000001, 0);
            send_one_word_weight({19'h0, start_bram}, 0); 
            send_one_word_weight({19'h0, end_bram}, 0);
            send_one_word_weight(24'd0, 0); 
            send_one_word_weight({8'h0, num_words}, 0);
            
            for (w_j = start_bram; w_j <= end_bram; w_j = w_j + 1) begin
                for (w_i = 0; w_i < num_words; w_i = w_i + 1) begin
                    send_one_word_weight(24'h000000, (w_j==end_bram && w_i==num_words-1));
                end
            end
            wait(weight_write_done); @(posedge aclk);
        end
    endtask

    task send_packet_ifmap_zeros;
        input [4:0] start_bram; 
        input [4:0] end_bram; 
        input [15:0] num_words; 
        begin
            send_one_word_ifmap(24'h00C0DE, 0); 
            send_one_word_ifmap(24'h000001, 0);
            send_one_word_ifmap({19'h0, start_bram}, 0); 
            send_one_word_ifmap({19'h0, end_bram}, 0);
            send_one_word_ifmap(24'd0, 0); 
            send_one_word_ifmap({8'h0, num_words}, 0);
            
            for (i_j = start_bram; i_j <= end_bram; i_j = i_j + 1) begin
                for (i_i = 0; i_i < num_words; i_i = i_i + 1) begin
                    send_one_word_ifmap(24'h000000, (i_j==end_bram && i_i==num_words-1));
                end
            end
            wait(ifmap_write_done); @(posedge aclk);
        end
    endtask

    task send_packet_bias_zeros;
        input [1:0] layer_id; 
        input [31:0] num_channels; 
        input [31:0] positions_per_ch;
        integer total_data_per_bram;
        begin
            total_data_per_bram = (num_channels / 16) * positions_per_ch;
            
            send_one_word_bias(24'h00C0DE, 0); 
            send_one_word_bias(24'h000001, 0);
            send_one_word_bias({19'h0, 5'd0}, 0);
            send_one_word_bias({19'h0, 5'd15}, 0);
            send_one_word_bias(24'd0, 0);
            send_one_word_bias({8'h0, total_data_per_bram[15:0]}, 0);
            
            for (b_bram_id = 0; b_bram_id < 16; b_bram_id = b_bram_id + 1) begin
                for (b_word_count = 0; b_word_count < total_data_per_bram; b_word_count = b_word_count + 1) begin
                    send_one_word_bias(24'h000000, (b_bram_id == 15 && b_word_count == total_data_per_bram-1));
                end
            end
            
            wait(bias_write_done); 
            @(posedge aclk);
        end
    endtask

    task wait_for_notification;
        input [2:0] expected_batch;
        begin
            @(posedge notif_detected);
            if (notif_header[2][2:0] != expected_batch) begin
                $display("[ERROR] Expected batch %0d, got %0d", expected_batch, notif_header[2][2:0]);
            end
        end
    endtask

    // ========================================================================
    // DISPLAY TASKS - FULL PRINT ke file TXT
    // ========================================================================
    
    task display_all_layer3_inputs;
        begin
            display_layer3_weights_full();
            display_layer3_ifmap_full();
            display_layer3_bias_full();
        end
    endtask

    task display_layer3_weights_full;
        integer bram, tile, oc_base, k, cin, bram_addr, oc_abs, ddr_addr;
        reg [23:0] weight_val;
        begin
            file_handle = $fopen("layer3_weights_FULL.txt", "w");
            
            for (bram = 0; bram < 16; bram = bram + 1) begin
                k = bram[1:0];               // kernel position
                oc_base = bram[3:2];         // base OC in tile (0,1,2,3)
                
                $fwrite(file_handle, "\n=== BRAM %2d (k=%0d) ===\n", bram, k);
                $fwrite(file_handle, "Addr   | Tile0_Oc%2d | Tile1_Oc%2d | Tile2_Oc%2d | Tile3_Oc%2d |\n", 
                        oc_base, oc_base+4, oc_base+8, oc_base+12);
                $fwrite(file_handle, "-------|------------|------------|------------|------------|\n");
                
                // 64 addresses (input channels)
                for (cin = 0; cin < 64; cin = cin + 1) begin
                    $fwrite(file_handle, "%3d    |", cin);
                    
                    // 4 tiles
                    for (tile = 0; tile < 4; tile = tile + 1) begin
                        bram_addr = tile * 64 + cin;  // 0-63, 64-127, 128-191, 192-255
                        oc_abs = tile * 4 + oc_base;  // Oc0,4,8,12 or Oc1,5,9,13 etc
                        
                        // DDR: offset + (oc * 256) + (k * 64) + cin
                        ddr_addr = 212992 + (oc_abs * 256) + (k * 64) + cin;
                        weight_val = weight_ddr_mem[ddr_addr][23:0];
                        
                        $fwrite(file_handle, " %6d     |", $signed(weight_val));
                    end
                    
                    $fwrite(file_handle, "\n");
                end
                
                $fwrite(file_handle, "\n");
                $fwrite(file_handle, "Address Range  | Content\n");
                $fwrite(file_handle, "---------------|--------------------------------------------------\n");
                $fwrite(file_handle, "0-63           | Oc%2d,  k%0d, Ich[0-63]\n", oc_base, k);
                $fwrite(file_handle, "64-127         | Oc%2d,  k%0d, Ich[0-63]\n", oc_base+4, k);
                $fwrite(file_handle, "128-191        | Oc%2d,  k%0d, Ich[0-63]\n", oc_base+8, k);
                $fwrite(file_handle, "192-255        | Oc%2d,  k%0d, Ich[0-63]\n", oc_base+12, k);
                $fwrite(file_handle, "256-1023       | KOSONG\n");
            end
            
            $fclose(file_handle);
        end
    endtask

    task display_layer3_ifmap_full;
        integer disp_pos, disp_ch, disp_ddr_idx;
        reg [23:0] disp_ifm;
        begin
            file_handle = $fopen("layer3_input_ifmap_FULL.txt", "w");
            
            $fwrite(file_handle, "========================================================================\n");
            $fwrite(file_handle, "LAYER 3 IFMAP DATA - FULL DUMP FROM DDR MEMORY\n");
            $fwrite(file_handle, "========================================================================\n");
            $fwrite(file_handle, "Layout: 256 Positions × 64 Channels = 16384 values total\n");
            $fwrite(file_handle, "File organization: Pos0[Ch0-63], Pos1[Ch0-63], ..., Pos255[Ch0-63]\n");
            $fwrite(file_handle, "========================================================================\n\n");
            
            // Print semua ifmap dari DDR memory
            for (disp_pos = 0; disp_pos < 256; disp_pos = disp_pos + 1) begin
                $fwrite(file_handle, "\n=== POSITION %3d ===\n", disp_pos);
                
                for (disp_ch = 0; disp_ch < 64; disp_ch = disp_ch + 1) begin
                    disp_ddr_idx = (disp_pos * 64) + disp_ch;
                    disp_ifm = ifmap_ddr_mem[disp_ddr_idx][23:0];
                    
                    $fwrite(file_handle, "  Pos%03d_Ch%02d: DDR[%5d] = 0x%06h (%0d)\n", 
                            disp_pos, disp_ch, disp_ddr_idx, disp_ifm, $signed(disp_ifm));
                end
            end
            
            $fwrite(file_handle, "\n========================================================================\n");
            $fwrite(file_handle, "TARGET BRAM LAYOUT (with stride 16):\n");
            $fwrite(file_handle, "========================================================================\n");
            $fwrite(file_handle, "BRAM 0:  Pos[0,16,32,...,240] × Ch[0-63] = 1024 words\n");
            $fwrite(file_handle, "BRAM 1:  Pos[1,17,33,...,241] × Ch[0-63] = 1024 words\n");
            $fwrite(file_handle, "...\n");
            $fwrite(file_handle, "BRAM 15: Pos[15,31,47,...,255] × Ch[0-63] = 1024 words\n");
            $fwrite(file_handle, "========================================================================\n");
            
            $fclose(file_handle);
        end
    endtask

    task display_layer3_bias_full;
        integer disp_bram, disp_addr, disp_ddr_idx;
        reg [23:0] disp_bias;
        begin
            file_handle = $fopen("layer3_input_bias_FULL.txt", "w");
            
            $fwrite(file_handle, "========================================================================\n");
            $fwrite(file_handle, "LAYER 3 BIAS DATA - FULL DUMP FROM DDR MEMORY\n");
            $fwrite(file_handle, "========================================================================\n");
            $fwrite(file_handle, "Layout: 16 Channels × 512 Positions = 8192 values total\n");
            $fwrite(file_handle, "File organization: Ch0[Pos0-511], Ch1[Pos0-511], ..., Ch15[Pos0-511]\n");
            $fwrite(file_handle, "========================================================================\n\n");
            
            // Print semua bias dari DDR memory
            for (disp_bram = 0; disp_bram < 16; disp_bram = disp_bram + 1) begin
                $fwrite(file_handle, "\n=== CHANNEL %2d (BRAM %2d) ===\n", disp_bram, disp_bram);
                
                for (disp_addr = 0; disp_addr < 512; disp_addr = disp_addr + 1) begin
                    disp_ddr_idx = BIAS_LAYER_3_OFFSET + (disp_bram * 512) + disp_addr;
                    disp_bias = bias_ddr_mem[disp_ddr_idx][23:0];
                    
                    $fwrite(file_handle, "  Ch%02d_Pos%03d: DDR[%5d] = 0x%06h (%0d)\n", 
                            disp_bram, disp_addr, disp_ddr_idx, disp_bias, $signed(disp_bias));
                end
            end
            
            $fclose(file_handle);
        end
    endtask


    task display_layer3_output;
        integer out_bram, out_addr, out_lin_idx, out_pos, out_ch;
        reg [23:0] out_val;
        begin
            // ========== FILE 1: RAW FULL DUMP ==========
            file_handle = $fopen("layer3_output_RAW_FULL.txt", "w");
            
            $fwrite(file_handle, "================================================================================\n");
            $fwrite(file_handle, "LAYER 3 OUTPUT DATA - RAW FULL DUMP\n");
            $fwrite(file_handle, "================================================================================\n");
            $fwrite(file_handle, "16 BRAMs x 512 addresses = 8192 total output values\n");
            $fwrite(file_handle, "BRAM 0-7 from m0_axis, BRAM 8-15 from m1_axis\n");
            $fwrite(file_handle, "================================================================================\n\n");
            
            for (out_bram = 0; out_bram < 16; out_bram = out_bram + 1) begin
                $fwrite(file_handle, "\n=== BRAM %2d ===\n", out_bram);
                
                for (out_addr = 0; out_addr < 512; out_addr = out_addr + 1) begin
                    if (out_bram < 8) 
                        out_lin_idx = (out_bram * 512) + out_addr;
                    else 
                        out_lin_idx = ((out_bram - 8) * 512) + out_addr + (OUTPUT_MEM_DEPTH/2);
                    
                    out_val = output_captured_mem[out_lin_idx];
                    
                    $fwrite(file_handle, "  BRAM%02d[%03d]: 0x%06h (%6d)\n", 
                            out_bram, out_addr, out_val, $signed(out_val));
                end
            end
            
            $fwrite(file_handle, "\n================================================================================\n");
            $fclose(file_handle);

            // ========== FILE 2: TABLE FORMAT (Position x Channel) ==========
            file_handle = $fopen("layer3_output_TABLE.txt", "w");
            
            $fwrite(file_handle, "================================================================================\n");
            $fwrite(file_handle, "LAYER 3 OUTPUT - TABLE FORMAT (Position x Channel)\n");
            $fwrite(file_handle, "================================================================================\n");
            $fwrite(file_handle, "Layout: 256 Positions x 16 Channels\n");
            $fwrite(file_handle, "Each row = 1 position, Each column = 1 channel\n");
            $fwrite(file_handle, "================================================================================\n\n");
            
            // Print table header
            $fwrite(file_handle, "      |");
            for (out_ch = 0; out_ch < 16; out_ch = out_ch + 1) begin
                $fwrite(file_handle, "   Ch%02d   |", out_ch);
            end
            $fwrite(file_handle, "\n");
            
            $fwrite(file_handle, "------+");
            for (out_ch = 0; out_ch < 16; out_ch = out_ch + 1) begin
                $fwrite(file_handle, "----------+");
            end
            $fwrite(file_handle, "\n");
            
            // Print ALL 256 positions x 16 channels
            for (out_pos = 0; out_pos < 256; out_pos = out_pos + 1) begin
                $fwrite(file_handle, "Pos%03d|", out_pos);
                
                for (out_ch = 0; out_ch < 16; out_ch = out_ch + 1) begin
                    out_bram = out_ch;
                    out_addr = out_pos;
                    
                    if (out_bram < 8) 
                        out_lin_idx = (out_bram * 512) + out_addr;
                    else 
                        out_lin_idx = ((out_bram - 8) * 512) + out_addr + (OUTPUT_MEM_DEPTH/2);
                    
                    out_val = output_captured_mem[out_lin_idx];
                    
                    $fwrite(file_handle, " %8d |", $signed(out_val));
                end
                $fwrite(file_handle, "\n");
            end
            
            $fwrite(file_handle, "\n================================================================================\n");
            $fclose(file_handle);

            // ========== FILE 3: SUMMARY ==========
            file_handle = $fopen("layer3_output_SUMMARY.txt", "w");
            
            $fwrite(file_handle, "================================================================================\n");
            $fwrite(file_handle, "LAYER 3 OUTPUT - SUMMARY\n");
            $fwrite(file_handle, "================================================================================\n\n");
            
            $fwrite(file_handle, "First 16 positions, all 16 channels:\n");
            $fwrite(file_handle, "------------------------------------------------------------\n");
            
            for (out_pos = 0; out_pos < 16; out_pos = out_pos + 1) begin
                $fwrite(file_handle, "\nPosition %3d:\n", out_pos);
                for (out_ch = 0; out_ch < 16; out_ch = out_ch + 1) begin
                    out_bram = out_ch;
                    out_addr = out_pos;
                    
                    if (out_bram < 8) 
                        out_lin_idx = (out_bram * 512) + out_addr;
                    else 
                        out_lin_idx = ((out_bram - 8) * 512) + out_addr + (OUTPUT_MEM_DEPTH/2);
                    
                    out_val = output_captured_mem[out_lin_idx];
                    $fwrite(file_handle, "  Ch%02d = %6d (0x%06h)\n", out_ch, $signed(out_val), out_val);
                end
            end
            
            $fwrite(file_handle, "\n================================================================================\n");
            $fclose(file_handle);
        end
    endtask


    // ========================================================================
    // 8. MAIN SEQUENCE - ZERO TEST MODE WITH INPUT DISPLAY
    // ========================================================================
    initial begin
        aresetn = 0;
        s0_axis_tdata = 0; s0_axis_tvalid = 0; s0_axis_tlast = 0; m0_axis_tready = 1;
        s1_axis_tdata = 0; s1_axis_tvalid = 0; s1_axis_tlast = 0; m1_axis_tready = 1;
        s2_axis_tdata = 0; s2_axis_tvalid = 0; s2_axis_tlast = 0;
        output_write_ptr = 0; 

        $readmemh(WEIGHT_MEM_FILE, weight_ddr_mem);
        $readmemh(BIAS_MEM_FILE, bias_ddr_mem);
        $readmemh(IFMAP_MEM_FILE, ifmap_ddr_mem);

        #(T*10); aresetn = 1; #(T*20);
        total_start_time = cycle_count;

        // ====================== LAYER 0 (ZEROS) ======================
        start_time_l0 = cycle_count;

        fork
            begin
                send_packet_bias_zeros(2'd0, 128, 64);
            end
            begin
                send_packet_ifmap_zeros(5'd0, 5'd15, 16'd1024); 
            end
            begin
                send_packet_weight_zeros(5'd0, 5'd15, 16'd1024); 
            end
        join
        
        wait_for_notification(3'd0);
        send_packet_weight_zeros(5'd0, 5'd15, 16'd1024); wait_for_notification(3'd1);
        send_packet_weight_zeros(5'd0, 5'd15, 16'd1024); wait_for_notification(3'd2);
        send_packet_weight_zeros(5'd0, 5'd15, 16'd1024); wait_for_notification(3'd3);
        send_packet_weight_zeros(5'd0, 5'd15, 16'd1024); wait_for_notification(3'd4);
        send_packet_weight_zeros(5'd0, 5'd15, 16'd1024); wait_for_notification(3'd5);
        send_packet_weight_zeros(5'd0, 5'd15, 16'd1024); wait_for_notification(3'd6);
        send_packet_weight_zeros(5'd0, 5'd15, 16'd1024); wait_for_notification(3'd7);

        wait(layer_readout_done);
        end_time_l0 = cycle_count;
        #(T*100);

        // ====================== LAYER 1 (ZEROS) ======================
        start_time_l1 = cycle_count;

        fork
            begin
                send_packet_bias_zeros(2'd1, 64, 128);
            end
            begin
                send_packet_ifmap_zeros(5'd0, 5'd15, 16'd1024);
            end
            begin
                send_packet_weight_zeros(5'd0, 5'd15, 16'd1024);
            end
        join
        
        wait_for_notification(3'd0);
        send_packet_weight_zeros(5'd0, 5'd15, 16'd1024); wait_for_notification(3'd1);
        send_packet_weight_zeros(5'd0, 5'd15, 16'd1024); wait_for_notification(3'd2);
        send_packet_weight_zeros(5'd0, 5'd15, 16'd1024); wait_for_notification(3'd3);

        wait(layer_readout_done);
        end_time_l1 = cycle_count;
        #(T*100);

        // ====================== LAYER 2 (ZEROS) ======================
        start_time_l2 = cycle_count;

        fork
            begin
                send_packet_bias_zeros(2'd2, 32, 256);
            end
            begin
                send_packet_ifmap_zeros(5'd0, 5'd15, 16'd1024);
            end
            begin
                send_packet_weight_zeros(5'd0, 5'd15, 16'd1024);
            end
        join
        
        wait_for_notification(3'd0);
        wait(layer_readout_done);
        end_time_l2 = cycle_count;
        #(T*100);

        // ====================== LAYER 3 (REAL DATA) ======================
        
        // DISPLAY LAYER 3 INPUT DATA (from DDR memory before sending to BRAMs)
        display_all_layer3_inputs();
        
        start_time_l3 = cycle_count;

        fork
            begin
                send_packet_bias_layer3(BIAS_LAYER_3_OFFSET);
            end
            begin
                send_ifmap_layer3_stride16();
            end
            begin
                send_packet_weight_layer3(212992);
            end
        join
        
        wait_for_notification(3'd0);
        wait(layer_readout_done);
        end_time_l3 = cycle_count;

        $display("\n==========================================================");
        $display(" LATENCY SUMMARY TABLE");
        $display("==========================================================");
        $display(" Layer | Mode  | Latency (cycles)");
        $display("-------|-------|------------------");
        $display("  d1   | ZERO  | %0d", (end_time_l0 - start_time_l0));
        $display("  d2   | ZERO  | %0d", (end_time_l1 - start_time_l1));
        $display("  d3   | ZERO  | %0d", (end_time_l2 - start_time_l2));
        $display("  d4   | REAL  | %0d", (end_time_l3 - start_time_l3));
        $display("-------|-------|------------------");
        $display(" TOTAL |       | %0d", (cycle_count - total_start_time));
        $display("==========================================================");
        
        #(T*100);
        display_layer3_output();
        $finish;
    end

endmodule