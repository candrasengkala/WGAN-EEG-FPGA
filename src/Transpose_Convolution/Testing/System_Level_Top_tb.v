`timescale 1ns / 1ps

/******************************************************************************
 * System_Level_Top Testbench - MULTI-BATCH VERSION
 * 
 * Test Flow:
 *   1. Load ifmap (once, all 16 BRAMs)
 *   2. Load weight batch 0 (tiles 0-3)
 *      → Auto-start batch 0 processing
 *      → Wait for batch_complete notification
 *   3. Load weight batch 1 (tiles 4-7)
 *      → Auto-start batch 1 processing
 *      → Wait for batch_complete notification
 *   4. Load weight batch 2 (tiles 8-11)
 *      → Auto-start batch 2 processing
 *      → Wait for batch_complete notification
 *   5. Verify output stream packets
 ******************************************************************************/

module System_Level_Top_tb();
    localparam T = 10;
    
    // ========================================================================
    // Testbench Signals
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

    // NEW: AXI Stream Output (from FPGA to PS)
    wire [15:0]     m_output_axis_tdata;
    wire            m_output_axis_tvalid;
    reg             m_output_axis_tready;
    wire            m_output_axis_tlast;

    // Status
    wire       weight_write_done;
    wire       weight_read_done;
    wire       ifmap_write_done;
    wire       ifmap_read_done;
    wire [9:0] weight_mm2s_data_count;
    wire [9:0] ifmap_mm2s_data_count;
    
    reg        scheduler_start;     
    wire       scheduler_done;
    
    reg                   ext_read_mode;
    reg [16*10-1:0]       ext_read_addr_flat;
    
    wire [2:0] weight_parser_state;
    wire       weight_error_invalid_magic;
    wire [2:0] ifmap_parser_state;
    wire       ifmap_error_invalid_magic;
    
    wire auto_start_active;
    wire data_load_ready;

    // ========================================================================
    // DUT Instantiation
    // ========================================================================
    System_Level_Top #(
        .DW(16), 
        .NUM_BRAMS(16), 
        .ADDR_WIDTH(10), 
        .Dimension(16), 
        .DEPTH(1024)  
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

        // NEW: Output AXI Stream
        .m_output_axis_tdata(m_output_axis_tdata),
        .m_output_axis_tvalid(m_output_axis_tvalid),
        .m_output_axis_tready(m_output_axis_tready),
        .m_output_axis_tlast(m_output_axis_tlast),

        // Status
        .weight_write_done(weight_write_done),
        .weight_read_done(weight_read_done),
        .ifmap_write_done(ifmap_write_done),
        .ifmap_read_done(ifmap_read_done),
        .weight_mm2s_data_count(weight_mm2s_data_count),
        .ifmap_mm2s_data_count(ifmap_mm2s_data_count),

        .scheduler_start(scheduler_start),     
        .scheduler_done(scheduler_done),      

        .ext_read_mode(ext_read_mode),
        .ext_read_addr_flat(ext_read_addr_flat),

        .weight_parser_state(weight_parser_state),
        .weight_error_invalid_magic(weight_error_invalid_magic),
        .ifmap_parser_state(ifmap_parser_state),
        .ifmap_error_invalid_magic(ifmap_error_invalid_magic),
        
        .auto_start_active(auto_start_active),
        .data_load_ready(data_load_ready)
    );

    // ========================================================================
    // Output Stream Receiver (Simulate PS DMA)
    // ========================================================================
    reg [15:0] output_packet [0:8191];  // Storage for output data
    integer output_word_cnt;
    reg [15:0] output_header [0:3];     // Header storage
    integer output_header_cnt;
    
    always @(posedge aclk) begin
        if (!aresetn) begin
            output_word_cnt <= 0;
            output_header_cnt <= 0;
        end else begin
            if (m_output_axis_tvalid && m_output_axis_tready) begin
                // Store header first (assume first 4 words)
                if (output_header_cnt < 4) begin
                    output_header[output_header_cnt] <= m_output_axis_tdata;
                    output_header_cnt <= output_header_cnt + 1;
                    
                    // Decode header after 4th word
                    if (output_header_cnt == 3) begin
                        if (output_header[0] == 16'hC0DE) begin
                            $display("[%0t] [OUTPUT RX] NOTIFICATION Received:", $time);
                            $display("              Magic: 0x%04h", output_header[0]);
                            $display("              Batch ID: %0d", output_header[1]);
                            $display("              Tile Start: %0d", output_header[2]);
                            $display("              Tile End: %0d", output_header[3]);
                        end else if (output_header[0] == 16'hDA7A) begin
                            $display("[%0t] [OUTPUT RX] FULL DATA Header Received:", $time);
                            $display("              Magic: 0x%04h", output_header[0]);
                            $display("              Num BRAMs: %0d", output_header[1]);
                            $display("              Words per BRAM: %0d", output_header[2]);
                            $display("              Total Words: %0d", output_header[3]);
                        end
                    end
                end else begin
                    // Store payload
                    output_packet[output_word_cnt] <= m_output_axis_tdata;
                    output_word_cnt <= output_word_cnt + 1;
                end
                
                // Reset on TLAST
                if (m_output_axis_tlast) begin
                    if (output_header[0] == 16'hDA7A) begin
                        $display("[%0t] [OUTPUT RX] Full output data received (%0d words)", 
                                 $time, output_word_cnt);
                    end
                    output_header_cnt <= 0;
                    output_word_cnt <= 0;
                end
            end
        end
    end

    // ========================================================================
    // Debug Monitors
    // ========================================================================
    wire [2:0] dbg_sched_state = dut.scheduler_inst.state;
    wire dbg_start_weight = dut.scheduler_inst.start_weight;
    wire dbg_start_ifmap = dut.scheduler_inst.start_ifmap;
    wire dbg_start_mapper = dut.scheduler_inst.start_Mapper;
    wire dbg_start_trans = dut.scheduler_inst.start_transpose;
    wire dbg_done_weight = dut.done_weight;
    wire dbg_done_ifmap = dut.if_done;
    wire dbg_done_mapper = dut.done_mapper;
    wire [8:0] dbg_row_id = dut.scheduler_inst.row_id;
    wire [5:0] dbg_tile_id = dut.scheduler_inst.tile_id;
    wire [2:0] dbg_batch_id = dut.scheduler_inst.current_batch_id;
    wire dbg_batch_complete = dut.scheduler_inst.batch_complete;

    // Batch state monitoring (if batch FSM is implemented)
    // wire [2:0] dbg_batch_state = dut.batch_state;
    // wire [2:0] dbg_batch_counter = dut.batch_counter;

    always @(dbg_sched_state) begin
        case (dbg_sched_state)
            3'd0: $display("[%0t] [SCHEDULER] State -> IDLE", $time);
            3'd1: $display("[%0t] [SCHEDULER] State -> START_ALL (Batch %0d)", $time, dbg_batch_id);
            3'd2: $display("[%0t] [SCHEDULER] State -> WAIT_BRAM", $time);
            3'd3: $display("[%0t] [SCHEDULER] State -> START_TRANS", $time);
            3'd4: $display("[%0t] [SCHEDULER] State -> WAIT_TRANS", $time);
            3'd5: $display("[%0t] [SCHEDULER] State -> DONE_STATE (Batch %0d Complete)", $time, dbg_batch_id);
        endcase
    end

    always @(posedge dbg_batch_complete) begin
        $display("[%0t] >>> BATCH %0d COMPLETE (Tiles %0d-%0d) <<<", 
                 $time, dbg_batch_id, dbg_batch_id*4, dbg_batch_id*4+3);
    end

    always @(posedge auto_start_active) 
        $display("[%0t] [SYSTEM] AUTO-START TRIGGERED for Batch %0d", $time, dbg_batch_id);

    // ========================================================================
    // Clock
    // ========================================================================
    always begin aclk = 0; #(T/2); aclk = 1; #(T/2); end

    // ========================================================================
    // AXI Stream Send Tasks
    // ========================================================================
    task send_one_word_weight;
        input [15:0] data; 
        input is_last;
        begin
            s0_axis_tdata = data; 
            s0_axis_tvalid = 1; 
            s0_axis_tlast = is_last;
            @(posedge aclk); 
            while (!s0_axis_tready) @(posedge aclk);
            #1; 
            s0_axis_tvalid = 0; 
            s0_axis_tlast = 0;
        end
    endtask

    task send_one_word_ifmap;
        input [15:0] data; 
        input is_last;
        begin
            s1_axis_tdata = data; 
            s1_axis_tvalid = 1; 
            s1_axis_tlast = is_last;
            @(posedge aclk); 
            while (!s1_axis_tready) @(posedge aclk);
            #1; 
            s1_axis_tvalid = 0; 
            s1_axis_tlast = 0;
        end
    endtask

    task send_packet_weight;
        input [4:0] bram_start; 
        input [4:0] bram_end; 
        input [15:0] num_words; 
        input [15:0] data_pattern;
        begin
            $display("\n[%0t] [WEIGHT] Loading Batch via AXI (BRAMs %0d-%0d, %0d words each)...", 
                     $time, bram_start, bram_end, num_words);
            
            // Header
            send_one_word_weight(16'hC0DE, 0);          // Magic
            send_one_word_weight(16'h0001, 0);          // WRITE instruction
            send_one_word_weight({11'h0, bram_start}, 0);
            send_one_word_weight({11'h0, bram_end}, 0);
            send_one_word_weight(16'd0, 0);             // Addr Start = 0
            send_one_word_weight(num_words, 0);         // Addr Count
            
            // Payload: Pattern = BRAM_ID
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
        input [4:0] bram_start; 
        input [4:0] bram_end; 
        input [15:0] num_words; 
        input [15:0] data_pattern;
        begin
            $display("\n[%0t] [IFMAP] Loading via AXI (BRAMs %0d-%0d, %0d words each)...", 
                     $time, bram_start, bram_end, num_words);
            
            // Header
            send_one_word_ifmap(16'hC0DE, 0);
            send_one_word_ifmap(16'h0001, 0);
            send_one_word_ifmap({11'h0, bram_start}, 0);
            send_one_word_ifmap({11'h0, bram_end}, 0);
            send_one_word_ifmap(16'd0, 0);
            send_one_word_ifmap(num_words, 0);
            
            // Payload
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

    // ========================================================================
    // Main Test Sequence - MULTI-BATCH (3 batches = 12 tiles)
    // ========================================================================
    initial begin
        // Initialize
        aresetn = 0;
        s0_axis_tdata = 0; s0_axis_tvalid = 0; s0_axis_tlast = 0; m0_axis_tready = 1;
        s1_axis_tdata = 0; s1_axis_tvalid = 0; s1_axis_tlast = 0; m1_axis_tready = 1;
        m_output_axis_tready = 1;  // Always ready to receive output
        scheduler_start = 0; 
        ext_read_mode = 0; 
        ext_read_addr_flat = 0;
        
        #(T*10); 
        aresetn = 1;
        $display("\n[%0t] ============ RESET RELEASED ============\n", $time);
        #(T*20);

        // ====================================================================
        // STEP 1: Load IFMAP (ONCE - all 16 BRAMs, 512 words each)
        // ====================================================================
        $display("\n[%0t] ===== STEP 1: Loading IFMAP (ONE-TIME) =====", $time);
        send_packet_ifmap(5'd0, 5'd15, 16'd512, 16'h1000);
        
        #(T*100);

        // ====================================================================
        // STEP 2: Load WEIGHT BATCH 0 (Tiles 0-3)
        // ====================================================================
        $display("\n[%0t] ===== STEP 2: Loading WEIGHT BATCH 0 (Tiles 0-3) =====", $time);
        send_packet_weight(5'd0, 5'd15, 16'd1024, 16'h0000);
        
        $display("[%0t] Waiting for Batch 0 processing...", $time);
        wait(dbg_batch_complete && dbg_batch_id == 0);
        #(T*100);
        
        // ====================================================================
        // STEP 3: Load WEIGHT BATCH 1 (Tiles 4-7)
        // ====================================================================
        $display("\n[%0t] ===== STEP 3: Loading WEIGHT BATCH 1 (Tiles 4-7) =====", $time);
        send_packet_weight(5'd0, 5'd15, 16'd1024, 16'h0100);
        
        $display("[%0t] Waiting for Batch 1 processing...", $time);
        wait(dbg_batch_complete && dbg_batch_id == 1);
        #(T*100);
        
        // ====================================================================
        // STEP 4: Load WEIGHT BATCH 2 (Tiles 8-11)
        // ====================================================================
        $display("\n[%0t] ===== STEP 4: Loading WEIGHT BATCH 2 (Tiles 8-11) =====", $time);
        send_packet_weight(5'd0, 5'd15, 16'd1024, 16'h0200);
        
        $display("[%0t] Waiting for Batch 2 processing...", $time);
        wait(dbg_batch_complete && dbg_batch_id == 2);
        #(T*100);

        // ====================================================================
        // VERIFICATION
        // ====================================================================
        $display("\n[%0t] ===== ALL 3 BATCHES (12 TILES) COMPLETED =====", $time);
        $display("[%0t] Processed Tiles: 0-11", $time);
        $display("[%0t] Waiting for final output stream transmission...", $time);
        
        #(T*10000);  // Wait for output transmission

        $display("\n[%0t] ===== TEST COMPLETE =====", $time);
        $finish;
    end

    // Timeout watchdog
    initial begin
        #(T*50000000);  // 500ms timeout
        $display("\n[%0t] !!! TIMEOUT - TEST FAILED !!!", $time);
        $finish;
    end

        // ------------------------------------------------------------------------
    // 1. WEIGHT WRITE PROBES
    // ------------------------------------------------------------------------
    wire [9:0]  probe_wr_weight_addr    = dut.weight_wr_addr; // Alamat tulis (Shared)
    
    // Pecah Flat Data Weight (256-bit -> 16x16-bit)
    wire [15:0] probe_wr_weight_data_00 = dut.weight_wr_data_flat[15:0];
    wire [15:0] probe_wr_weight_data_01 = dut.weight_wr_data_flat[31:16];
    wire [15:0] probe_wr_weight_data_02 = dut.weight_wr_data_flat[47:32];
    wire [15:0] probe_wr_weight_data_03 = dut.weight_wr_data_flat[63:48];
    wire [15:0] probe_wr_weight_data_04 = dut.weight_wr_data_flat[79:64];
    wire [15:0] probe_wr_weight_data_05 = dut.weight_wr_data_flat[95:80];
    wire [15:0] probe_wr_weight_data_06 = dut.weight_wr_data_flat[111:96];
    wire [15:0] probe_wr_weight_data_07 = dut.weight_wr_data_flat[127:112];
    wire [15:0] probe_wr_weight_data_08 = dut.weight_wr_data_flat[143:128];
    wire [15:0] probe_wr_weight_data_09 = dut.weight_wr_data_flat[159:144];
    wire [15:0] probe_wr_weight_data_10 = dut.weight_wr_data_flat[175:160];
    wire [15:0] probe_wr_weight_data_11 = dut.weight_wr_data_flat[191:176];
    wire [15:0] probe_wr_weight_data_12 = dut.weight_wr_data_flat[207:192];
    wire [15:0] probe_wr_weight_data_13 = dut.weight_wr_data_flat[223:208];
    wire [15:0] probe_wr_weight_data_14 = dut.weight_wr_data_flat[239:224];
    wire [15:0] probe_wr_weight_data_15 = dut.weight_wr_data_flat[255:240];

    // Pecah Enable Weight (Lihat mana yang aktif)
    wire probe_wr_weight_en_00 = dut.weight_wr_en[0];
    wire probe_wr_weight_en_01 = dut.weight_wr_en[1];
    wire probe_wr_weight_en_02 = dut.weight_wr_en[2];
    wire probe_wr_weight_en_03 = dut.weight_wr_en[3];
    wire probe_wr_weight_en_04 = dut.weight_wr_en[4];
    wire probe_wr_weight_en_05 = dut.weight_wr_en[5];
    wire probe_wr_weight_en_06 = dut.weight_wr_en[6];
    wire probe_wr_weight_en_07 = dut.weight_wr_en[7];
    wire probe_wr_weight_en_08 = dut.weight_wr_en[8];
    wire probe_wr_weight_en_09 = dut.weight_wr_en[9];
    wire probe_wr_weight_en_10 = dut.weight_wr_en[10];
    wire probe_wr_weight_en_11 = dut.weight_wr_en[11];
    wire probe_wr_weight_en_12 = dut.weight_wr_en[12];
    wire probe_wr_weight_en_13 = dut.weight_wr_en[13];
    wire probe_wr_weight_en_14 = dut.weight_wr_en[14];
    wire probe_wr_weight_en_15 = dut.weight_wr_en[15];

    // ------------------------------------------------------------------------
    // 2. IFMAP WRITE PROBES
    // ------------------------------------------------------------------------
    wire [9:0]  probe_wr_ifmap_addr    = dut.ifmap_wr_addr; // Alamat tulis (Shared)

    // Pecah Flat Data Ifmap (256-bit -> 16x16-bit)
    wire [15:0] probe_wr_ifmap_data_00 = dut.ifmap_wr_data_flat[15:0];
    wire [15:0] probe_wr_ifmap_data_01 = dut.ifmap_wr_data_flat[31:16];
    wire [15:0] probe_wr_ifmap_data_02 = dut.ifmap_wr_data_flat[47:32];
    wire [15:0] probe_wr_ifmap_data_03 = dut.ifmap_wr_data_flat[63:48];
    wire [15:0] probe_wr_ifmap_data_04 = dut.ifmap_wr_data_flat[79:64];
    wire [15:0] probe_wr_ifmap_data_05 = dut.ifmap_wr_data_flat[95:80];
    wire [15:0] probe_wr_ifmap_data_06 = dut.ifmap_wr_data_flat[111:96];
    wire [15:0] probe_wr_ifmap_data_07 = dut.ifmap_wr_data_flat[127:112];
    wire [15:0] probe_wr_ifmap_data_08 = dut.ifmap_wr_data_flat[143:128];
    wire [15:0] probe_wr_ifmap_data_09 = dut.ifmap_wr_data_flat[159:144];
    wire [15:0] probe_wr_ifmap_data_10 = dut.ifmap_wr_data_flat[175:160];
    wire [15:0] probe_wr_ifmap_data_11 = dut.ifmap_wr_data_flat[191:176];
    wire [15:0] probe_wr_ifmap_data_12 = dut.ifmap_wr_data_flat[207:192];
    wire [15:0] probe_wr_ifmap_data_13 = dut.ifmap_wr_data_flat[223:208];
    wire [15:0] probe_wr_ifmap_data_14 = dut.ifmap_wr_data_flat[239:224];
    wire [15:0] probe_wr_ifmap_data_15 = dut.ifmap_wr_data_flat[255:240];

    // Pecah Enable Ifmap
    wire probe_wr_ifmap_en_00 = dut.ifmap_wr_en[0];
    wire probe_wr_ifmap_en_01 = dut.ifmap_wr_en[1];
    wire probe_wr_ifmap_en_02 = dut.ifmap_wr_en[2];
    wire probe_wr_ifmap_en_03 = dut.ifmap_wr_en[3];
    wire probe_wr_ifmap_en_04 = dut.ifmap_wr_en[4];
    wire probe_wr_ifmap_en_05 = dut.ifmap_wr_en[5];
    wire probe_wr_ifmap_en_06 = dut.ifmap_wr_en[6];
    wire probe_wr_ifmap_en_07 = dut.ifmap_wr_en[7];
    wire probe_wr_ifmap_en_08 = dut.ifmap_wr_en[8];
    wire probe_wr_ifmap_en_09 = dut.ifmap_wr_en[9];
    wire probe_wr_ifmap_en_10 = dut.ifmap_wr_en[10];
    wire probe_wr_ifmap_en_11 = dut.ifmap_wr_en[11];
    wire probe_wr_ifmap_en_12 = dut.ifmap_wr_en[12];
    wire probe_wr_ifmap_en_13 = dut.ifmap_wr_en[13];
    wire probe_wr_ifmap_en_14 = dut.ifmap_wr_en[14];
    wire probe_wr_ifmap_en_15 = dut.ifmap_wr_en[15];


endmodule