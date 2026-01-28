`timescale 1ns / 1ps

/******************************************************************************
 * System_Level_Top Testbench - FIXED VERSION
 * 
 * FIXES:
 * - Monitoring sekarang menampilkan SEMUA data BRAM yang keluar
 * - Print first 20 data words
 * - Print every 512th word (BRAM boundaries)
 * - Print total count saat TLAST
 * - Tambah counter terpisah untuk data words
 ******************************************************************************/

module System_Level_Top_tb();
    localparam T = 10;
    
    // ========================================================================
    // Signals
    // ========================================================================
    reg             aclk;
    reg             aresetn;

    // AXI Stream 0 - Weight (TX) & Notification/Data (RX)
    reg  [15:0]     s0_axis_tdata;
    reg             s0_axis_tvalid;
    wire            s0_axis_tready;
    reg             s0_axis_tlast;
    wire [15:0]     m0_axis_tdata;
    wire            m0_axis_tvalid;
    reg             m0_axis_tready;
    wire            m0_axis_tlast;

    // AXI Stream 1 - Ifmap (TX) & Data (RX)
    reg  [15:0]     s1_axis_tdata;
    reg             s1_axis_tvalid;
    wire            s1_axis_tready;
    reg             s1_axis_tlast;
    wire [15:0]     m1_axis_tdata;
    wire            m1_axis_tvalid;
    reg             m1_axis_tready;
    wire            m1_axis_tlast;

    // Status
    wire       weight_write_done;
    wire       ifmap_write_done;
    
    // DUT
    System_Level_Top #(
        .DW(16), 
        .NUM_BRAMS(16),
        .W_ADDR_W(10),
        .I_ADDR_W(10),
        .O_ADDR_W(9),
        .W_DEPTH(1024),
        .I_DEPTH(1024),
        .O_DEPTH(512),
        .Dimension(16)
    ) dut (
        .aclk(aclk),
        .aresetn(aresetn),
        // Weight AXI
        .s0_axis_tdata(s0_axis_tdata),
        .s0_axis_tvalid(s0_axis_tvalid),
        .s0_axis_tready(s0_axis_tready),
        .s0_axis_tlast(s0_axis_tlast),
        .m0_axis_tdata(m0_axis_tdata),
        .m0_axis_tvalid(m0_axis_tvalid),
        .m0_axis_tready(m0_axis_tready),
        .m0_axis_tlast(m0_axis_tlast),
        // Ifmap AXI
        .s1_axis_tdata(s1_axis_tdata),
        .s1_axis_tvalid(s1_axis_tvalid),
        .s1_axis_tready(s1_axis_tready),
        .s1_axis_tlast(s1_axis_tlast),
        .m1_axis_tdata(m1_axis_tdata),
        .m1_axis_tvalid(m1_axis_tvalid),
        .m1_axis_tready(m1_axis_tready),
        .m1_axis_tlast(m1_axis_tlast),
        // Control
        .ext_start(1'b0),
        .ext_layer_id(2'd0),
        // Status
        .weight_write_done(weight_write_done),
        .ifmap_write_done(ifmap_write_done),
        .scheduler_done(),
        .current_layer_id(),
        .current_batch_id(),
        .all_batches_done(),
        .weight_read_done(),
        .ifmap_read_done(),
        .weight_mm2s_data_count(),
        .ifmap_mm2s_data_count(),
        .weight_parser_state(),
        .weight_error_invalid_magic(),
        .ifmap_parser_state(),
        .ifmap_error_invalid_magic(),
        .auto_start_active()
    );

    // ========================================================================
    // DEBUG READ MONITORING - FIXED VERSION
    // ========================================================================
    
    // 1. MONITOR GROUP 0 (Notification dengan Header + Data)
    integer rx0_count;
    integer rx0_data_count;  // NEW: Counter khusus untuk data words
    reg [15:0] notif_header [0:5];  // 6 words header
    reg notif_detected;
    reg in_data_phase;
    
    always @(posedge aclk) begin
        if (!aresetn) begin
            rx0_count <= 0;
            rx0_data_count <= 0;
            notif_detected <= 0;
            in_data_phase <= 0;
        end else if (m0_axis_tvalid && m0_axis_tready) begin
            
            // State machine is based on in_data_phase
            if (!in_data_phase) begin 
                // ---- HEADER RECEPTION PHASE ----
                if (rx0_count < 6) begin
                    notif_header[rx0_count] <= m0_axis_tdata;
                    $display("[%0t] [M0] HEADER[%0d] = %0d (0x%04h)", $time, rx0_count, m0_axis_tdata, m0_axis_tdata);
                end

                if (m0_axis_tlast) begin
                    // ---- HEADER-ONLY PACKET DETECTED ----
                    $display("[%0t] [M0] === HEADER COMPLETE ===", $time);
                    
                    // Decode header 
                    if (notif_header[0] == 16'hC0DE) begin
                         $display("[%0t] [M0] Mode: NOTIFICATION (header-only)", $time);
                         $display("[%0t] [M0]   Batch ID: %0d", $time, notif_header[2][2:0]);
                         notif_detected <= 1;
                    end
                    // Reset for next packet
                    rx0_count <= 0;
                    rx0_data_count <= 0;
                end else if (rx0_count == 5) begin // 5 means 6th word just arrived
                    // ---- END OF HEADER, DATA EXPECTED ----
                    in_data_phase <= 1;
                    rx0_count <= rx0_count + 1;
                    rx0_data_count <= 0;  // Reset data counter
                    $display("[%0t] [M0] === HEADER COMPLETE ===", $time);
                    
                    // Decode header for data packet
                    if (notif_header[0] == 16'hDA7A) begin 
                        $display("[%0t] [M0] Mode: FULL DATA STREAM", $time);
                        $display("[%0t] [M0]   Layer ID: %0d", $time, notif_header[2][1:0]);
                        $display("[%0t] [M0]   Expected: %0d words", $time, notif_header[5]);
                        $display("[%0t] [M0] === DATA RECEPTION STARTED ===", $time);
                    end
                end else begin
                    rx0_count <= rx0_count + 1;
                end
            end else begin
                // ---- DATA RECEPTION PHASE ----
                // NEW: Print first 20, every 512th word (BRAM boundary), and summary
                if (rx0_data_count < 20) begin
                    $display("[%0t] [M0] DATA[%0d] = %0d (0x%04h)", $time, rx0_data_count, m0_axis_tdata, m0_axis_tdata);
                end else if ((rx0_data_count % 512) == 0) begin
                    $display("[%0t] [M0] DATA[%0d] = %0d (BRAM boundary)", $time, rx0_data_count, m0_axis_tdata);
                end else if ((rx0_data_count % 512) == 511) begin
                    $display("[%0t] [M0] DATA[%0d] = %0d (BRAM end)", $time, rx0_data_count, m0_axis_tdata);
                end
                
                rx0_data_count <= rx0_data_count + 1;
                rx0_count <= rx0_count + 1;

                if (m0_axis_tlast) begin
                    $display("[%0t] [M0] === DATA COMPLETE ===", $time);
                    $display("[%0t] [M0] Total DATA words received: %0d", $time, rx0_data_count + 1);
                    $display("[%0t] [M0] Total words (Header+Data): %0d", $time, rx0_count + 1);
                    $display("[%0t] [M0] Number of BRAMs: %0d", $time, (rx0_data_count + 1) / 512);
                    // Reset for next packet
                    rx0_count <= 0;
                    rx0_data_count <= 0;
                    in_data_phase <= 0;
                end
            end

        end else begin
            // De-assert single-cycle signals
            notif_detected <= 0;
        end
    end

    // 2. MONITOR GROUP 1 (Ifmap dengan Header + Data)
    integer rx1_count;
    integer rx1_data_count;  // NEW: Counter khusus untuk data words
    reg [15:0] data_header [0:5];  // 6 words header
    reg data_detected;
    reg in_data_phase_1;
    
    always @(posedge aclk) begin
        if (!aresetn) begin
            rx1_count <= 0;
            rx1_data_count <= 0;
            data_detected <= 0;
            in_data_phase_1 <= 0;
        end else if (m1_axis_tvalid && m1_axis_tready) begin
            
            if (!in_data_phase_1) begin
                // ---- HEADER RECEPTION PHASE ----
                if (rx1_count < 6) begin
                    data_header[rx1_count] <= m1_axis_tdata;
                    $display("[%0t] [M1] HEADER[%0d] = %0d (0x%04h)", $time, rx1_count, m1_axis_tdata, m1_axis_tdata);
                end

                if (m1_axis_tlast) begin
                    // ---- HEADER-ONLY PACKET ----
                    $display("[%0t] [M1] === HEADER COMPLETE ===", $time);
                    
                    if (data_header[0] == 16'hC0DE) begin
                        $display("[%0t] [M1] Mode: NOTIFICATION (header-only)", $time);
                        $display("[%0t] [M1]   Batch ID: %0d", $time, data_header[2][2:0]);
                        data_detected <= 1;
                    end
                    // Reset
                    rx1_count <= 0;
                    rx1_data_count <= 0;
                end else if (rx1_count == 5) begin
                    // ---- END OF HEADER, DATA EXPECTED ----
                    in_data_phase_1 <= 1;
                    rx1_count <= rx1_count + 1;
                    rx1_data_count <= 0;  // Reset data counter
                    $display("[%0t] [M1] === HEADER COMPLETE ===", $time);
                    
                    if (data_header[0] == 16'hDA7A) begin
                        $display("[%0t] [M1] Mode: FULL DATA STREAM", $time);
                        $display("[%0t] [M1]   Layer ID: %0d", $time, data_header[2][1:0]);
                        $display("[%0t] [M1]   Expected: %0d words", $time, data_header[5]);
                        $display("[%0t] [M1] === DATA RECEPTION STARTED ===", $time);
                    end
                end else begin
                    rx1_count <= rx1_count + 1;
                end
            end else begin
                // ---- DATA RECEPTION PHASE ----
                // NEW: Print first 20, every 512th word (BRAM boundary), and summary
                if (rx1_data_count < 20) begin
                    $display("[%0t] [M1] DATA[%0d] = %0d (0x%04h)", $time, rx1_data_count, m1_axis_tdata, m1_axis_tdata);
                end else if ((rx1_data_count % 512) == 0) begin
                    $display("[%0t] [M1] DATA[%0d] = %0d (BRAM boundary)", $time, rx1_data_count, m1_axis_tdata);
                end else if ((rx1_data_count % 512) == 511) begin
                    $display("[%0t] [M1] DATA[%0d] = %0d (BRAM end)", $time, rx1_data_count, m1_axis_tdata);
                end
                
                rx1_data_count <= rx1_data_count + 1;
                rx1_count <= rx1_count + 1;
                
                if (m1_axis_tlast) begin
                    $display("[%0t] [M1] === DATA COMPLETE ===", $time);
                    $display("[%0t] [M1] Total DATA words received: %0d", $time, rx1_data_count + 1);
                    $display("[%0t] [M1] Total words (Header+Data): %0d", $time, rx1_count + 1);
                    $display("[%0t] [M1] Number of BRAMs: %0d", $time, (rx1_data_count + 1) / 512);
                    // Reset
                    rx1_count <= 0;
                    rx1_data_count <= 0;
                    in_data_phase_1 <= 0;
                end
            end
        end else begin
            // De-assert single-cycle signals
            data_detected <= 0;
        end
    end

    // ========================================================================
    // Tasks
    // ========================================================================
    always begin aclk = 0; #(T/2); aclk = 1; #(T/2); end

    task send_one_word_weight;
        input [15:0] data; input is_last;
        begin
            s0_axis_tdata = data; s0_axis_tvalid = 1; s0_axis_tlast = is_last;
            @(posedge aclk); while (!s0_axis_tready) @(posedge aclk);
            #1; s0_axis_tvalid = 0; s0_axis_tlast = 0;
        end
    endtask

    task send_one_word_ifmap;
        input [15:0] data; input is_last;
        begin
            s1_axis_tdata = data; s1_axis_tvalid = 1; s1_axis_tlast = is_last;
            @(posedge aclk); while (!s1_axis_tready) @(posedge aclk);
            #1; s1_axis_tvalid = 0; s1_axis_tlast = 0;
        end
    endtask

    task send_packet_weight;
        input [4:0] bram_start; input [4:0] bram_end; 
        input [15:0] num_words; input [15:0] data_pattern;
        begin
            $display("\n[%0t] [WEIGHT] Sending Header...", $time);
            send_one_word_weight(16'hC0DE, 0);
            send_one_word_weight(16'h0001, 0);
            send_one_word_weight({11'h0, bram_start}, 0);
            send_one_word_weight({11'h0, bram_end}, 0);
            send_one_word_weight(16'd0, 0);
            send_one_word_weight(num_words, 0);
            
            $display("[%0t] [WEIGHT] Sending Payload (Parallel Write)...", $time);
            fork 
                begin : weight_payload
                    integer i, j;
                    for (j = bram_start; j <= bram_end; j = j + 1) begin
                        for (i = 0; i < num_words; i = i + 1) begin
                            send_one_word_weight(j + data_pattern, (j==bram_end && i==num_words-1));
                        end
                    end
                end
            join
            wait(weight_write_done);
            @(posedge aclk);
            $display("[%0t] [WEIGHT] Load COMPLETE.", $time);
        end
    endtask

    task send_packet_ifmap;
        input [4:0] bram_start; input [4:0] bram_end; 
        input [15:0] num_words; input [15:0] data_pattern;
        begin
            $display("\n[%0t] [IFMAP] Sending Header...", $time);
            send_one_word_ifmap(16'hC0DE, 0);
            send_one_word_ifmap(16'h0001, 0);
            send_one_word_ifmap({11'h0, bram_start}, 0);
            send_one_word_ifmap({11'h0, bram_end}, 0);
            send_one_word_ifmap(16'd0, 0);
            send_one_word_ifmap(num_words, 0);
            
            $display("[%0t] [IFMAP] Sending Payload (Parallel Write)...", $time);
            fork 
                begin : ifmap_payload
                    integer i, j;
                    for (j = bram_start; j <= bram_end; j = j + 1) begin
                        for (i = 0; i < num_words; i = i + 1) begin
                            send_one_word_ifmap(i[15:0] + data_pattern, (j==bram_end && i==num_words-1));
                        end
                    end
                end
            join
            wait(ifmap_write_done);
            @(posedge aclk);
            $display("[%0t] [IFMAP] Load COMPLETE.", $time);
        end
    endtask

    task wait_for_notification;
        input [2:0] expected_batch;
        begin
            $display("[%0t] Waiting for Batch %0d notification...", $time, expected_batch);
            @(posedge notif_detected);
            $display("[%0t] >>> NOTIFICATION RECEIVED for Batch %0d <<<", $time, expected_batch);
        end
    endtask

    // ========================================================================
    // Main Sequence
    // ========================================================================
    initial begin
        aresetn = 0;
        s0_axis_tdata = 0; s0_axis_tvalid = 0; s0_axis_tlast = 0; 
        m0_axis_tready = 1; // ALWAYS READY TO READ
        s1_axis_tdata = 0; s1_axis_tvalid = 0; s1_axis_tlast = 0; 
        m1_axis_tready = 1; // ALWAYS READY TO READ
        
        #(T*10); aresetn = 1;
        $display("\n[%0t] ============ RESET RELEASED ============\n", $time);
        #(T*20);

        // STEP 1: IFMAP
        $display("\n[%0t] ===== STEP 1: Loading IFMAP =====", $time);
        send_packet_ifmap(5'd0, 5'd15, 16'd1024, 16'h0000);
        #(T*100);

        // STEP 2: BATCH 0
        $display("\n[%0t] ===== STEP 2: Loading WEIGHT BATCH 0 =====", $time);
        send_packet_weight(5'd0, 5'd15, 16'd1024, 16'h0000);
        wait_for_notification(3'd0);
        #(T*100);

        // STEP 3: BATCH 1
        $display("\n[%0t] ===== STEP 3: Loading WEIGHT BATCH 1 =====", $time);
        send_packet_weight(5'd0, 5'd15, 16'd1024, 16'h0000);
        wait_for_notification(3'd1);
        #(T*100);

        // STEP 4: BATCH 2
        $display("\n[%0t] ===== STEP 4: Loading WEIGHT BATCH 2 =====", $time);
        send_packet_weight(5'd0, 5'd15, 16'd1024, 16'h0000);
        wait_for_notification(3'd2);
        #(T*100);
        
        // STEP 5: BATCH 3
        $display("\n[%0t] ===== STEP 5: Loading WEIGHT BATCH 3 =====", $time);
        send_packet_weight(5'd0, 5'd15, 16'd1024, 16'h0000);
        wait_for_notification(3'd3);
        #(T*100);
        
        // STEP 6: BATCH 4
        $display("\n[%0t] ===== STEP 6: Loading WEIGHT BATCH 4 =====", $time);
        send_packet_weight(5'd0, 5'd15, 16'd1024, 16'h0000);
        wait_for_notification(3'd4);
        #(T*100);
        
        // STEP 7: BATCH 5
        $display("\n[%0t] ===== STEP 7: Loading WEIGHT BATCH 5 =====", $time);
        send_packet_weight(5'd0, 5'd15, 16'd1024, 16'h0000);
        wait_for_notification(3'd5);
        #(T*100);
        
        // STEP 8: BATCH 6
        $display("\n[%0t] ===== STEP 8: Loading WEIGHT BATCH 6 =====", $time);
        send_packet_weight(5'd0, 5'd15, 16'd1024, 16'h0000);
        wait_for_notification(3'd6);
        #(T*100);
        
        // STEP 9: BATCH 7 (LAST)
        $display("\n[%0t] ===== STEP 9: Loading WEIGHT BATCH 7 (LAST) =====", $time);
        send_packet_weight(5'd0, 5'd15, 16'd1024, 16'h0000);
        wait_for_notification(3'd7);
        #(T*100);

        // VERIFICATION
        $display("\n[%0t] ===== ALL 8 BATCHES PROCESSED =====", $time);
        $display("  Expected: 8 notifications received (Batch 0-7)");
        $display("  Each notification: Header(6) words, NO DATA");
        $display("\n  Waiting for FULL DATA transmission...");
        $display("  Expected: Header(6) + All BRAM(4096) = 4102 words via m0_axis");
        
        // Tunggu data output keluar di M0/M1
        #(T*50000);
        
        $display("\n[%0t] ========== TEST COMPLETE ==========", $time);
        $finish;
    end

    // Watchdog
    initial begin
        #(T*50000000);
        $display("\n[%0t] !!! TIMEOUT !!!", $time);
        $finish;
    end

    // ------------------------------------------------------------------------
    // 1. WEIGHT WRITE PROBES
    // ------------------------------------------------------------------------
    wire [10:0] probe_wr_weight_addr = dut.datapath.w_addr_wr_flat[10:0]; // Alamat tulis (Shared)
    
    // Pecah Flat Data Weight (256-bit -> 16x16-bit)
    wire [15:0] probe_wr_weight_data_00 = dut.datapath.w_din_flat[15:0];
    wire [15:0] probe_wr_weight_data_01 = dut.datapath.w_din_flat[31:16];
    wire [15:0] probe_wr_weight_data_02 = dut.datapath.w_din_flat[47:32];
    wire [15:0] probe_wr_weight_data_03 = dut.datapath.w_din_flat[63:48];
    wire [15:0] probe_wr_weight_data_04 = dut.datapath.w_din_flat[79:64];
    wire [15:0] probe_wr_weight_data_05 = dut.datapath.w_din_flat[95:80];
    wire [15:0] probe_wr_weight_data_06 = dut.datapath.w_din_flat[111:96];
    wire [15:0] probe_wr_weight_data_07 = dut.datapath.w_din_flat[127:112];
    wire [15:0] probe_wr_weight_data_08 = dut.datapath.w_din_flat[143:128];
    wire [15:0] probe_wr_weight_data_09 = dut.datapath.w_din_flat[159:144];
    wire [15:0] probe_wr_weight_data_10 = dut.datapath.w_din_flat[175:160];
    wire [15:0] probe_wr_weight_data_11 = dut.datapath.w_din_flat[191:176];
    wire [15:0] probe_wr_weight_data_12 = dut.datapath.w_din_flat[207:192];
    wire [15:0] probe_wr_weight_data_13 = dut.datapath.w_din_flat[223:208];
    wire [15:0] probe_wr_weight_data_14 = dut.datapath.w_din_flat[239:224];
    wire [15:0] probe_wr_weight_data_15 = dut.datapath.w_din_flat[255:240];

    // Pecah Enable Weight (Lihat mana yang aktif)
    wire probe_wr_weight_en_00 = dut.datapath.w_we[0];
    wire probe_wr_weight_en_01 = dut.datapath.w_we[1];
    wire probe_wr_weight_en_02 = dut.datapath.w_we[2];
    wire probe_wr_weight_en_03 = dut.datapath.w_we[3];
    wire probe_wr_weight_en_04 = dut.datapath.w_we[4];
    wire probe_wr_weight_en_05 = dut.datapath.w_we[5];
    wire probe_wr_weight_en_06 = dut.datapath.w_we[6];
    wire probe_wr_weight_en_07 = dut.datapath.w_we[7];
    wire probe_wr_weight_en_08 = dut.datapath.w_we[8];
    wire probe_wr_weight_en_09 = dut.datapath.w_we[9];
    wire probe_wr_weight_en_10 = dut.datapath.w_we[10];
    wire probe_wr_weight_en_11 = dut.datapath.w_we[11];
    wire probe_wr_weight_en_12 = dut.datapath.w_we[12];
    wire probe_wr_weight_en_13 = dut.datapath.w_we[13];
    wire probe_wr_weight_en_14 = dut.datapath.w_we[14];
    wire probe_wr_weight_en_15 = dut.datapath.w_we[15];

    // ------------------------------------------------------------------------
    // 2. IFMAP WRITE PROBES
    // ------------------------------------------------------------------------
    wire [9:0]  probe_wr_ifmap_addr = dut.datapath.if_addr_wr_flat[9:0]; // Alamat tulis (Shared)

    // Pecah Flat Data Ifmap (256-bit -> 16x16-bit)
    wire [15:0] probe_wr_ifmap_data_00 = dut.datapath.if_din_flat[15:0];
    wire [15:0] probe_wr_ifmap_data_01 = dut.datapath.if_din_flat[31:16];
    wire [15:0] probe_wr_ifmap_data_02 = dut.datapath.if_din_flat[47:32];
    wire [15:0] probe_wr_ifmap_data_03 = dut.datapath.if_din_flat[63:48];
    wire [15:0] probe_wr_ifmap_data_04 = dut.datapath.if_din_flat[79:64];
    wire [15:0] probe_wr_ifmap_data_05 = dut.datapath.if_din_flat[95:80];
    wire [15:0] probe_wr_ifmap_data_06 = dut.datapath.if_din_flat[111:96];
    wire [15:0] probe_wr_ifmap_data_07 = dut.datapath.if_din_flat[127:112];
    wire [15:0] probe_wr_ifmap_data_08 = dut.datapath.if_din_flat[143:128];
    wire [15:0] probe_wr_ifmap_data_09 = dut.datapath.if_din_flat[159:144];
    wire [15:0] probe_wr_ifmap_data_10 = dut.datapath.if_din_flat[175:160];
    wire [15:0] probe_wr_ifmap_data_11 = dut.datapath.if_din_flat[191:176];
    wire [15:0] probe_wr_ifmap_data_12 = dut.datapath.if_din_flat[207:192];
    wire [15:0] probe_wr_ifmap_data_13 = dut.datapath.if_din_flat[223:208];
    wire [15:0] probe_wr_ifmap_data_14 = dut.datapath.if_din_flat[239:224];
    wire [15:0] probe_wr_ifmap_data_15 = dut.datapath.if_din_flat[255:240];

    // Pecah Enable Ifmap
    wire probe_wr_ifmap_en_00 = dut.datapath.if_we[0];
    wire probe_wr_ifmap_en_01 = dut.datapath.if_we[1];
    wire probe_wr_ifmap_en_02 = dut.datapath.if_we[2];
    wire probe_wr_ifmap_en_03 = dut.datapath.if_we[3];
    wire probe_wr_ifmap_en_04 = dut.datapath.if_we[4];
    wire probe_wr_ifmap_en_05 = dut.datapath.if_we[5];
    wire probe_wr_ifmap_en_06 = dut.datapath.if_we[6];
    wire probe_wr_ifmap_en_07 = dut.datapath.if_we[7];
    wire probe_wr_ifmap_en_08 = dut.datapath.if_we[8];
    wire probe_wr_ifmap_en_09 = dut.datapath.if_we[9];
    wire probe_wr_ifmap_en_10 = dut.datapath.if_we[10];
    wire probe_wr_ifmap_en_11 = dut.datapath.if_we[11];
    wire probe_wr_ifmap_en_12 = dut.datapath.if_we[12];
    wire probe_wr_ifmap_en_13 = dut.datapath.if_we[13];
    wire probe_wr_ifmap_en_14 = dut.datapath.if_we[14];
    wire probe_wr_ifmap_en_15 = dut.datapath.if_we[15];

    // ------------------------------------------------------------------------
    // 3. OUTPUT BRAM READ PROBES (dari BRAM_Read_Modify_Top)
    // ------------------------------------------------------------------------

    // A. READ CONTROL SIGNALS
    wire probe_ext_read_mode = dut.datapath.u_output_storage.ext_read_mode;

    // B. READ ADDRESS (per BRAM) - 16 BRAMs × 9-bit address
    wire [8:0] probe_rd_output_addr_00 = dut.datapath.u_output_storage.bram_read_addr_flat[8:0];
    wire [8:0] probe_rd_output_addr_01 = dut.datapath.u_output_storage.bram_read_addr_flat[17:9];
    wire [8:0] probe_rd_output_addr_02 = dut.datapath.u_output_storage.bram_read_addr_flat[26:18];
    wire [8:0] probe_rd_output_addr_03 = dut.datapath.u_output_storage.bram_read_addr_flat[35:27];
    wire [8:0] probe_rd_output_addr_04 = dut.datapath.u_output_storage.bram_read_addr_flat[44:36];
    wire [8:0] probe_rd_output_addr_05 = dut.datapath.u_output_storage.bram_read_addr_flat[53:45];
    wire [8:0] probe_rd_output_addr_06 = dut.datapath.u_output_storage.bram_read_addr_flat[62:54];
    wire [8:0] probe_rd_output_addr_07 = dut.datapath.u_output_storage.bram_read_addr_flat[71:63];
    wire [8:0] probe_rd_output_addr_08 = dut.datapath.u_output_storage.bram_read_addr_flat[80:72];
    wire [8:0] probe_rd_output_addr_09 = dut.datapath.u_output_storage.bram_read_addr_flat[89:81];
    wire [8:0] probe_rd_output_addr_10 = dut.datapath.u_output_storage.bram_read_addr_flat[98:90];
    wire [8:0] probe_rd_output_addr_11 = dut.datapath.u_output_storage.bram_read_addr_flat[107:99];
    wire [8:0] probe_rd_output_addr_12 = dut.datapath.u_output_storage.bram_read_addr_flat[116:108];
    wire [8:0] probe_rd_output_addr_13 = dut.datapath.u_output_storage.bram_read_addr_flat[125:117];
    wire [8:0] probe_rd_output_addr_14 = dut.datapath.u_output_storage.bram_read_addr_flat[134:126];
    wire [8:0] probe_rd_output_addr_15 = dut.datapath.u_output_storage.bram_read_addr_flat[143:135];

    // C. READ DATA (per BRAM) - 16 BRAMs × 16-bit data
    wire [15:0] probe_rd_output_data_00 = dut.datapath.u_output_storage.bram_read_data_flat[15:0];
    wire [15:0] probe_rd_output_data_01 = dut.datapath.u_output_storage.bram_read_data_flat[31:16];
    wire [15:0] probe_rd_output_data_02 = dut.datapath.u_output_storage.bram_read_data_flat[47:32];
    wire [15:0] probe_rd_output_data_03 = dut.datapath.u_output_storage.bram_read_data_flat[63:48];
    wire [15:0] probe_rd_output_data_04 = dut.datapath.u_output_storage.bram_read_data_flat[79:64];
    wire [15:0] probe_rd_output_data_05 = dut.datapath.u_output_storage.bram_read_data_flat[95:80];
    wire [15:0] probe_rd_output_data_06 = dut.datapath.u_output_storage.bram_read_data_flat[111:96];
    wire [15:0] probe_rd_output_data_07 = dut.datapath.u_output_storage.bram_read_data_flat[127:112];
    wire [15:0] probe_rd_output_data_08 = dut.datapath.u_output_storage.bram_read_data_flat[143:128];
    wire [15:0] probe_rd_output_data_09 = dut.datapath.u_output_storage.bram_read_data_flat[159:144];
    wire [15:0] probe_rd_output_data_10 = dut.datapath.u_output_storage.bram_read_data_flat[175:160];
    wire [15:0] probe_rd_output_data_11 = dut.datapath.u_output_storage.bram_read_data_flat[191:176];
    wire [15:0] probe_rd_output_data_12 = dut.datapath.u_output_storage.bram_read_data_flat[207:192];
    wire [15:0] probe_rd_output_data_13 = dut.datapath.u_output_storage.bram_read_data_flat[223:208];
    wire [15:0] probe_rd_output_data_14 = dut.datapath.u_output_storage.bram_read_data_flat[239:224];
    wire [15:0] probe_rd_output_data_15 = dut.datapath.u_output_storage.bram_read_data_flat[255:240];

    // ========================================================================
// PROBE DEBUGGING READ ADDRESS - TRACE LENGKAP DARI AXIS_CUSTOM_TOP
// ========================================================================

// -----------------------------------------------------------------------
// 1. AXIS_CUSTOM_TOP - Counter dan Control untuk READ
// -----------------------------------------------------------------------

// A. READ COUNTER (ini yang jadi address untuk baca BRAM output)
wire [15:0] probe_rd_counter = dut.weight_wrapper.axis_top_inst.rd_counter;
wire [15:0] probe_rd_counter_limit = dut.weight_wrapper.axis_top_inst.rd_count_limit;
wire [15:0] probe_rd_start_addr = dut.weight_wrapper.axis_top_inst.rd_start_addr;
wire        probe_rd_counter_enable = dut.weight_wrapper.axis_top_inst.rd_counter_enable;
wire        probe_rd_counter_start = dut.weight_wrapper.axis_top_inst.rd_counter_start;
wire        probe_rd_counter_done = dut.weight_wrapper.axis_top_inst.rd_counter_done;

// B. FSM State untuk READ
wire [3:0]  probe_fsm_state = dut.weight_wrapper.axis_top_inst.fsm_inst.current_state;
wire        probe_fsm_batch_read_done = dut.weight_wrapper.axis_top_inst.fsm_batch_read_done;

// C. MUX Select (pilih BRAM mana yang dibaca)
wire [2:0]  probe_mux_sel = dut.weight_wrapper.axis_top_inst.mux_sel;



endmodule