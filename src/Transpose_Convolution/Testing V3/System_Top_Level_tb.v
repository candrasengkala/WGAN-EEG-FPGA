`timescale 1ns / 1ps

module System_Level_Top_tb();

    localparam T = 10;
    localparam DW = 24; 
    
    // ========================================================================
    // 1. PARAMETERS
    // ========================================================================
    parameter WEIGHT_MEM_FILE = "G_d5_Q9.14_decoder_weight.mem";
    parameter BIAS_MEM_FILE   = "G_d5_Q9.14_decoder_bias.mem";
    parameter IFMAP_MEM_FILE  = "decoder_last_input.mem";
    
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
    integer file_handle; // Global file handle
    reg     is_layer3_output; // Flag for Layer 3 detection

    // --- VARIABLES KHUSUS TASK (AGAR TIDAK BENTROK SAAT PARALEL) ---
    
    // Variables for Weight Task
    integer w_i, w_j, w_ddr_idx;
    
    // Variables for Ifmap Task
    integer i_i, i_j, i_ddr_idx;
    
    // Variables for Bias Task
    integer b_bram_id, b_ch_group, b_pos, b_ch_idx, b_mem_idx, b_total_words, b_word_count;
    
    // Variables for L3 Ifmap Task
    integer l3_b_id, l3_r_grp, l3_c_ol, l3_f_ix, l3_w_c, l3_t_w;
    
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
            is_layer3_output <= 0;
        end else begin
            notif_detected <= 0; layer_readout_done <= 0;
            if (m0_axis_tvalid && m0_axis_tready) begin
                if (!in_data_phase) begin 
                    if (rx0_count < 6) notif_header[rx0_count] <= m0_axis_tdata;
                    if (m0_axis_tlast) begin
                        if (notif_header[0][15:0] == 16'hC0DE) begin
                             $display("[%0t] [M0] NOTIF: Batch %0d Complete (Cycle: %0d)", $time, notif_header[2][2:0], cycle_count);
                             notif_detected <= 1;
                        end
                        rx0_count <= 0;
                    end else if (rx0_count == 5) begin 
                        in_data_phase <= 1; rx0_count <= rx0_count + 1; rx0_data_count <= 0;
                        if (notif_header[0][15:0] == 16'hDA7A) begin
                            $display("[%0t] [M0] === FULL DATA DUMP STARTED ===", $time);
                            // Detect Layer 3 (layer_id = 3 = 2'b11)
                            is_layer3_output <= (notif_header[2][1:0] == 2'd3);
                            if (notif_header[2][1:0] == 2'd3) begin
                                $display("[%0t] [M0] *** LAYER 3 OUTPUT - FULL TABLE PRINT ***", $time);
                                $display("=============================================================");
                                $display("Position |  Ch0  |  Ch1  |  Ch2  |  Ch3  |  Ch4  |  Ch5  |  Ch6  |  Ch7  |  Ch8  |  Ch9  | Ch10  | Ch11  | Ch12  | Ch13  | Ch14  | Ch15  |");
                                $display("---------|-------|-------|-------|-------|-------|-------|-------|-------|-------|-------|-------|-------|-------|-------|-------|-------|");
                            end
                        end
                    end else rx0_count <= rx0_count + 1;
                end else begin
                    // DATA PHASE
                    if (is_layer3_output) begin
                        // Layer 3: Print full table (16 channels × 512 positions)
                        // Data comes as: Ch0[0], Ch1[0], ..., Ch15[0], Ch0[1], Ch1[1], ...
                        if (rx0_data_count % 16 == 0) begin
                            // Start new row (new position)
                            $write("  %4d   |", rx0_data_count / 16);
                        end
                        $write(" %5d |", $signed(m0_axis_tdata));
                        if (rx0_data_count % 16 == 15) begin
                            // End of row
                            $write("\n");
                        end
                    end else begin
                        // Other layers: Print first 20 samples only
                        if (rx0_data_count < 20) begin
                            $display("[%0t] [M0] DATA[%0d] = 0x%06h (%0d)", 
                                $time, rx0_data_count, m0_axis_tdata, $signed(m0_axis_tdata));
                        end
                    end
                    
                    rx0_data_count <= rx0_data_count + 1; 
                    rx0_count <= rx0_count + 1;
                    
                    if (m0_axis_tlast) begin
                        if (is_layer3_output) begin
                            $display("=============================================================");
                            $display("[%0t] [M0] === LAYER 3 TABLE COMPLETE ===", $time);
                        end else begin
                            $display("[%0t] [M0] === FULL DATA DUMP COMPLETE ===", $time);
                        end
                        $display("[%0t] [M0] Total data words: %0d", $time, rx0_data_count + 1);
                        layer_readout_done <= 1; 
                        rx0_count <= 0; 
                        rx0_data_count <= 0; 
                        in_data_phase <= 0;
                        is_layer3_output <= 0;
                    end
                end
            end
        end
    end

    // ========================================================================
    // 6. TASKS (MENGGUNAKAN VARIABEL KHUSUS)
    // ========================================================================
    
    task send_one_word_weight;
        input [23:0] data; input is_last;
        begin
            s0_axis_tdata = data; s0_axis_tvalid = 1; s0_axis_tlast = is_last;
            @(posedge aclk); while (!s0_axis_tready) @(posedge aclk);
            #1; s0_axis_tvalid = 0; s0_axis_tlast = 0;
        end
    endtask

    task send_one_word_ifmap;
        input [23:0] data; input is_last;
        begin
            s1_axis_tdata = data; s1_axis_tvalid = 1; s1_axis_tlast = is_last;
            @(posedge aclk); while (!s1_axis_tready) @(posedge aclk);
            #1; s1_axis_tvalid = 0; s1_axis_tlast = 0;
        end
    endtask

    task send_one_word_bias;
        input [23:0] data; input is_last;
        begin
            s2_axis_tdata = data; s2_axis_tvalid = 1; s2_axis_tlast = is_last;
            @(posedge aclk); while (!s2_axis_tready) @(posedge aclk);
            #1; s2_axis_tvalid = 0; s2_axis_tlast = 0;
        end
    endtask

    task send_packet_weight;
        input [4:0] start_bram; input [4:0] end_bram; input [15:0] num_words; input [31:0] offset;
        begin
            // Header
            send_one_word_weight(24'h00C0DE, 0); send_one_word_weight(24'h000001, 0);
            send_one_word_weight({19'h0, start_bram}, 0); send_one_word_weight({19'h0, end_bram}, 0);
            send_one_word_weight(24'd0, 0); send_one_word_weight({8'h0, num_words}, 0);
            
            w_ddr_idx = offset;
            // USE w_j, w_i
            for (w_j = start_bram; w_j <= end_bram; w_j = w_j + 1) begin
                for (w_i = 0; w_i < num_words; w_i = w_i + 1) begin
                    send_one_word_weight(weight_ddr_mem[w_ddr_idx][23:0], (w_j==end_bram && w_i==num_words-1));
                    w_ddr_idx = w_ddr_idx + 1;
                end
            end
            wait(weight_write_done); @(posedge aclk);
        end
    endtask

    task send_packet_ifmap;
        input [4:0] start_bram; input [4:0] end_bram; input [15:0] num_words; input [31:0] offset;
        begin
            // Header
            send_one_word_ifmap(24'h00C0DE, 0); send_one_word_ifmap(24'h000001, 0);
            send_one_word_ifmap({19'h0, start_bram}, 0); send_one_word_ifmap({19'h0, end_bram}, 0);
            send_one_word_ifmap(24'd0, 0); send_one_word_ifmap({8'h0, num_words}, 0);
            
            i_ddr_idx = offset;
            // USE i_j, i_i
            for (i_j = start_bram; i_j <= end_bram; i_j = i_j + 1) begin
                for (i_i = 0; i_i < num_words; i_i = i_i + 1) begin
                    send_one_word_ifmap(ifmap_ddr_mem[i_ddr_idx][23:0], (i_j==end_bram && i_i==num_words-1));
                    i_ddr_idx = i_ddr_idx + 1;
                end
            end
            wait(ifmap_write_done); @(posedge aclk);
        end
    endtask

    task send_packet_bias_striped;
        input [1:0] layer_id; 
        input [31:0] bias_offset; 
        input [31:0] num_channels; 
        input [31:0] positions_per_ch;
        integer total_data_per_bram;
        begin
            total_data_per_bram = (num_channels / 16) * positions_per_ch;
            
            // Header
            send_one_word_bias(24'h00C0DE, 0); 
            send_one_word_bias(24'h000001, 0);
            send_one_word_bias({19'h0, 5'd0}, 0);   // start_bram = 0
            send_one_word_bias({19'h0, 5'd15}, 0);  // end_bram = 15
            send_one_word_bias(24'd0, 0);
            send_one_word_bias({8'h0, total_data_per_bram[15:0]}, 0);
            
            $display("[%0t] [BIAS] Layer %0d: %0d channels, %0d pos/ch, %0d words/BRAM", 
                     $time, layer_id, num_channels, positions_per_ch, total_data_per_bram);
            
            // Data - STRIPED pattern
            // BRAM 0: Ch0, Ch16, Ch32, ...
            // BRAM 1: Ch1, Ch17, Ch33, ...
            for (b_bram_id = 0; b_bram_id < 16; b_bram_id = b_bram_id + 1) begin
                b_word_count = 0;
                
                // Iterate through channel groups (Ch0-15, Ch16-31, Ch32-47, ...)
                for (b_ch_group = 0; b_ch_group < (num_channels / 16); b_ch_group = b_ch_group + 1) begin
                    // Channel index for this BRAM in this group
                    b_ch_idx = b_bram_id + (b_ch_group * 16);
                    
                    // Send all positions for this channel
                    for (b_pos = 0; b_pos < positions_per_ch; b_pos = b_pos + 1) begin
                        // Memory index: channel_offset + position
                        b_mem_idx = bias_offset + (b_ch_idx * positions_per_ch) + b_pos;
                        b_word_count = b_word_count + 1;
                        
                        send_one_word_bias(
                            bias_ddr_mem[b_mem_idx][23:0], 
                            (b_bram_id == 15 && b_word_count == total_data_per_bram)
                        );
                    end
                end
            end
            
            wait(bias_write_done); 
            @(posedge aclk);
            $display("[%0t] [PARALLEL] BIAS L%0d DONE", $time, layer_id);
        end
    endtask

    task send_ifmap_layer3_striped;
        begin
            l3_t_w = 16 * 1024; l3_w_c = 0;
            
            send_one_word_ifmap(24'h00C0DE, 0); send_one_word_ifmap(24'h000001, 0);
            send_one_word_ifmap({19'h0, 5'd0}, 0); send_one_word_ifmap({19'h0, 5'd15}, 0);
            send_one_word_ifmap(24'd0, 0); send_one_word_ifmap(24'd1024, 0);
            
            $display("[%0t] Starting Layer 3 Ifmap loading...", $time);
            // USE l3_xxx vars
            for (l3_b_id = 0; l3_b_id < 16; l3_b_id = l3_b_id + 1) begin
                for (l3_r_grp = 0; l3_r_grp < 4; l3_r_grp = l3_r_grp + 1) begin
                    for (l3_c_ol = 0; l3_c_ol < 256; l3_c_ol = l3_c_ol + 1) begin
                        l3_f_ix = (l3_b_id + l3_r_grp * 16) * 256 + l3_c_ol;
                        l3_w_c = l3_w_c + 1;
                        send_one_word_ifmap(ifmap_ddr_mem[l3_f_ix][23:0], (l3_w_c == l3_t_w));
                    end
                end
            end
            wait(ifmap_write_done); @(posedge aclk);
        end
    endtask

    task wait_for_notification;
        input [2:0] expected_batch;
        begin
            @(posedge notif_detected);
        end
    endtask

    task display_layer3_output;
        begin : disp_out
            file_handle = $fopen("layer3_output_display.txt", "w");
            for (d_bram_id = 0; d_bram_id < 16; d_bram_id = d_bram_id + 1) begin
                $fwrite(file_handle, "\n--- BRAM %0d ---\n", d_bram_id);
                for (d_addr = 0; d_addr < 512; d_addr = d_addr + 1) begin
                    if (d_bram_id < 8) d_lin_idx = (d_bram_id * 512) + d_addr;
                    else d_lin_idx = ((d_bram_id - 8) * 512) + d_addr + (OUTPUT_MEM_DEPTH/2);
                    d_val = output_captured_mem[d_lin_idx];
                    $fwrite(file_handle, "[%03d]: %h\n", d_addr, d_val);
                end
            end
            $fclose(file_handle);
        end
    endtask

    // ========================================================================
    // 7. DEBUG: FILE CHECKER (NAMED BLOCK for Variable)
    // ========================================================================
    initial begin : check_files
        integer f_check; // Local variable OK inside named block
        #10;
        $display("\n=== Testing File Access (Absolute Path Check) ===");
        f_check = $fopen(WEIGHT_MEM_FILE, "r");
        if (f_check == 0) $display("[ERROR] Cannot open WEIGHT file!");
        else begin $display("[SUCCESS] Weight file found!"); $fclose(f_check); end
        
        f_check = $fopen(BIAS_MEM_FILE, "r");
        if (f_check == 0) $display("[ERROR] Cannot open BIAS file!");
        else begin $display("[SUCCESS] Bias file found!"); $fclose(f_check); end
    end

    // ========================================================================
    // 8. MAIN SEQUENCE
    // ========================================================================
    initial begin
        // INIT
        aresetn = 0;
        s0_axis_tdata = 0; s0_axis_tvalid = 0; s0_axis_tlast = 0; m0_axis_tready = 1;
        s1_axis_tdata = 0; s1_axis_tvalid = 0; s1_axis_tlast = 0; m1_axis_tready = 1;
        s2_axis_tdata = 0; s2_axis_tvalid = 0; s2_axis_tlast = 0;
        output_write_ptr = 0; 

        // LOAD MEMORY
        $display("---------------------------------------------------------------");
        $display("[%0t] Loading memory files...", $time);
        $readmemh(WEIGHT_MEM_FILE, weight_ddr_mem);
        $readmemh(BIAS_MEM_FILE, bias_ddr_mem);
        $readmemh(IFMAP_MEM_FILE, ifmap_ddr_mem);
        
        #1; 
        if (bias_ddr_mem[0] === 32'bx) 
            $display("[CRITICAL] BIAS MEMORY X (Check Path)");
        else 
            $display("[INFO] Bias Loaded. First Data: %h", bias_ddr_mem[0]);

        #(T*10); aresetn = 1; #(T*20);
        total_start_time = cycle_count;

        // ====================== LAYER 0 ======================
        $display("\n[%0t] STARTING LAYER 0 (Cycle: %0d)", $time, cycle_count);
        start_time_l0 = cycle_count;

        // 3-WAY PARALLEL LOAD (Using Safe Variables)
        fork
            begin
                send_packet_bias_striped(2'd0, BIAS_LAYER_0_OFFSET, 128, 64);
                $display("[%0t] [PARALLEL] BIAS L0 DONE", $time);
            end
            begin
                send_packet_ifmap(5'd0, 5'd15, 16'd1024, 0); 
                $display("[%0t] [PARALLEL] IFMAP L0 DONE", $time);
            end
            begin
                send_packet_weight(5'd0, 5'd15, 16'd1024, 0); 
                $display("[%0t] [PARALLEL] WEIGHT L0 B0 DONE", $time);
            end
        join
        
        wait_for_notification(3'd0);

        // Batches 1-7
        send_packet_weight(5'd0, 5'd15, 16'd1024, 16384); wait_for_notification(3'd1);
        send_packet_weight(5'd0, 5'd15, 16'd1024, 32768); wait_for_notification(3'd2);
        send_packet_weight(5'd0, 5'd15, 16'd1024, 49152); wait_for_notification(3'd3);
        send_packet_weight(5'd0, 5'd15, 16'd1024, 65536); wait_for_notification(3'd4);
        send_packet_weight(5'd0, 5'd15, 16'd1024, 81920); wait_for_notification(3'd5);
        send_packet_weight(5'd0, 5'd15, 16'd1024, 98304); wait_for_notification(3'd6);
        send_packet_weight(5'd0, 5'd15, 16'd1024, 114688); wait_for_notification(3'd7);

        wait(layer_readout_done); 
        end_time_l0 = cycle_count;
        $display("[%0t] >>> LAYER 0 DONE. Latency: %0d cycles <<<", $time, (end_time_l0 - start_time_l0));
        #(T*100); 

        // ====================== LAYER 1 ======================
        $display("\n[%0t] STARTING LAYER 1 (Cycle: %0d)", $time, cycle_count);
        start_time_l1 = cycle_count;

        fork
            begin
                send_packet_bias_striped(2'd1, BIAS_LAYER_1_OFFSET, 64, 128);
                $display("[%0t] [PARALLEL] BIAS L1 DONE", $time);
            end
            begin
                send_packet_ifmap(5'd0, 5'd15, 16'd1024, 0);
                $display("[%0t] [PARALLEL] IFMAP L1 DONE", $time);
            end
            begin
                send_packet_weight(5'd0, 5'd15, 16'd1024, 131072);
                $display("[%0t] [PARALLEL] WEIGHT L1 B0 DONE", $time);
            end
        join
        
        wait_for_notification(3'd0);

        send_packet_weight(5'd0, 5'd15, 16'd1024, 147456); wait_for_notification(3'd1);
        send_packet_weight(5'd0, 5'd15, 16'd1024, 163840); wait_for_notification(3'd2);
        send_packet_weight(5'd0, 5'd15, 16'd1024, 180224); wait_for_notification(3'd3);

        wait(layer_readout_done);
        end_time_l1 = cycle_count;
        $display("[%0t] >>> LAYER 1 DONE. Latency: %0d cycles <<<", $time, (end_time_l1 - start_time_l1));
        #(T*100);

        // ====================== LAYER 2 ======================
        $display("\n[%0t] STARTING LAYER 2 (Cycle: %0d)", $time, cycle_count);
        start_time_l2 = cycle_count;

        fork
            begin
                send_packet_bias_striped(2'd2, BIAS_LAYER_2_OFFSET, 32, 256);
                $display("[%0t] [PARALLEL] BIAS L2 DONE", $time);
            end
            begin
                send_packet_ifmap(5'd0, 5'd15, 16'd1024, 0);
                $display("[%0t] [PARALLEL] IFMAP L2 DONE", $time);
            end
            begin
                send_packet_weight(5'd0, 5'd15, 16'd1024, 196608);
                $display("[%0t] [PARALLEL] WEIGHT L2 DONE", $time);
            end
        join
        
        wait_for_notification(3'd0);
        wait(layer_readout_done);
        end_time_l2 = cycle_count;
        $display("[%0t] >>> LAYER 2 DONE. Latency: %0d cycles <<<", $time, (end_time_l2 - start_time_l2));
        #(T*100);

        // ====================== LAYER 3 ======================
        $display("\n[%0t] STARTING LAYER 3 (Cycle: %0d)", $time, cycle_count);
        start_time_l3 = cycle_count;

        fork
            begin
                send_packet_bias_striped(2'd3, BIAS_LAYER_3_OFFSET, 16, 512);
                $display("[%0t] [PARALLEL] BIAS L3 DONE", $time);
            end
            begin
                send_ifmap_layer3_striped();
                $display("[%0t] [PARALLEL] IFMAP L3 DONE (STRIPED)", $time);
            end
            begin
                send_packet_weight(5'd0, 5'd15, 16'd256, 212992);
                $display("[%0t] [PARALLEL] WEIGHT L3 DONE", $time);
            end
        join
        
        wait_for_notification(3'd0);
        wait(layer_readout_done);
        end_time_l3 = cycle_count;
        $display("[%0t] >>> LAYER 3 DONE. Latency: %0d cycles <<<", $time, (end_time_l3 - start_time_l3));

        // FINAL REPORT
        $display("\n=================================================");
        $display("ALL LAYERS COMPLETED SUCCESSFULLY");
        $display("Total Cycles: %0d", (cycle_count - total_start_time));
        $display("=================================================");
        
        #(T*100);
        display_layer3_output();
        $finish;
    end

    // Watchdog
    initial begin
        #(T*200000000); 
        $display("\n[%0t] !!! TIMEOUT WATCHDOG !!!", $time);
        $finish;
    end

    wire [10:0] probe_wr_weight_addr = dut.datapath.w_addr_wr_flat[10:0]; 
    wire [23:0] probe_wr_weight_data_00 = dut.datapath.w_din_flat[23:0];

endmodule