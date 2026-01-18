`timescale 1ns / 1ps

// Testbench: Write 512 words ke setiap BRAM (0-15) secara bergantian
// Data pattern: 1, 2, 3, 4, ..., 8192 (simple increment)
module axis_custom_top_write_tb();
    localparam T = 10;
    
    reg aclk, aresetn;
    reg [15:0] s_axis_tdata;
    reg s_axis_tvalid, s_axis_tlast;
    wire s_axis_tready;
    wire [15:0] m_axis_tdata;
    wire m_axis_tvalid, m_axis_tlast;
    reg m_axis_tready;
    
    reg [7:0] Instruction_code;
    reg [4:0] wr_bram_start, wr_bram_end;
    reg [15:0] wr_addr_start, wr_addr_count;
    reg [2:0] rd_bram_start, rd_bram_end;
    reg [15:0] rd_addr_start, rd_addr_count;
    
    wire write_done, read_done;
    wire [9:0] mm2s_data_count;
    
    wire [15:0] bram_wr_data_0, bram_wr_data_1, bram_wr_data_2, bram_wr_data_3;
    wire [15:0] bram_wr_data_4, bram_wr_data_5, bram_wr_data_6, bram_wr_data_7;
    wire [15:0] bram_wr_data_8, bram_wr_data_9, bram_wr_data_10, bram_wr_data_11;
    wire [15:0] bram_wr_data_12, bram_wr_data_13, bram_wr_data_14, bram_wr_data_15;
    wire [8:0] bram_wr_addr;
    wire [15:0] bram_wr_en;
    
    reg [15:0] bram_rd_data_0, bram_rd_data_1, bram_rd_data_2, bram_rd_data_3;
    reg [15:0] bram_rd_data_4, bram_rd_data_5, bram_rd_data_6, bram_rd_data_7;
    wire [8:0] bram_rd_addr;
    
    integer i, bram_idx;
    reg [15:0] data_counter;
    
    // Tie read data to 0 (not testing read)
    always @(*) begin
        bram_rd_data_0 = 0; bram_rd_data_1 = 0;
        bram_rd_data_2 = 0; bram_rd_data_3 = 0;
        bram_rd_data_4 = 0; bram_rd_data_5 = 0;
        bram_rd_data_6 = 0; bram_rd_data_7 = 0;
    end
    
    // =========================================================================
    // DUT Instantiation
    // =========================================================================
    axis_custom_top dut (
        .aclk(aclk), .aresetn(aresetn),
        .s_axis_tdata(s_axis_tdata), .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready), .s_axis_tlast(s_axis_tlast),
        .m_axis_tdata(m_axis_tdata), .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready), .m_axis_tlast(m_axis_tlast),
        .Instruction_code(Instruction_code),
        .wr_bram_start(wr_bram_start), .wr_bram_end(wr_bram_end),
        .wr_addr_start(wr_addr_start), .wr_addr_count(wr_addr_count),
        .rd_bram_start(rd_bram_start), .rd_bram_end(rd_bram_end),
        .rd_addr_start(rd_addr_start), .rd_addr_count(rd_addr_count),
        .write_done(write_done), .read_done(read_done),
        .mm2s_data_count(mm2s_data_count),
        .bram_wr_data_0(bram_wr_data_0), .bram_wr_data_1(bram_wr_data_1),
        .bram_wr_data_2(bram_wr_data_2), .bram_wr_data_3(bram_wr_data_3),
        .bram_wr_data_4(bram_wr_data_4), .bram_wr_data_5(bram_wr_data_5),
        .bram_wr_data_6(bram_wr_data_6), .bram_wr_data_7(bram_wr_data_7),
        .bram_wr_data_8(bram_wr_data_8), .bram_wr_data_9(bram_wr_data_9),
        .bram_wr_data_10(bram_wr_data_10), .bram_wr_data_11(bram_wr_data_11),
        .bram_wr_data_12(bram_wr_data_12), .bram_wr_data_13(bram_wr_data_13),
        .bram_wr_data_14(bram_wr_data_14), .bram_wr_data_15(bram_wr_data_15),
        .bram_wr_addr(bram_wr_addr), .bram_wr_en(bram_wr_en),
        .bram_rd_data_0(bram_rd_data_0), .bram_rd_data_1(bram_rd_data_1),
        .bram_rd_data_2(bram_rd_data_2), .bram_rd_data_3(bram_rd_data_3),
        .bram_rd_data_4(bram_rd_data_4), .bram_rd_data_5(bram_rd_data_5),
        .bram_rd_data_6(bram_rd_data_6), .bram_rd_data_7(bram_rd_data_7),
        .bram_rd_addr(bram_rd_addr)
    );
    
    // Clock
    always begin aclk = 0; #(T/2); aclk = 1; #(T/2); end
    
    // =========================================================================
    // DEBUG MONITORING - Reduced verbosity
    // =========================================================================
    integer debug_counter = 0;
    reg [3:0] prev_fsm_state = 0;
    reg [4:0] prev_demux_sel = 0;
    reg prev_wr_done = 0;
    
    // Monitor critical changes only
    always @(posedge aclk) begin
        if (aresetn) begin
            debug_counter = debug_counter + 1;
            
            // Print every 1000 clocks or when FSM state changes
            if (debug_counter % 1000 == 0 || dut.fsm_inst.current_state != prev_fsm_state) begin
                $display("[%0t] FSM=%0d demux_sel=%0d idx=%0d | MM2S: val=%b rdy=%b | wr_en=%b cnt=%0d count_reg=%0d wr_done=%b limit=%0d fifo=%0d",
                         $time, dut.fsm_inst.current_state, dut.demux_sel, dut.fsm_inst.bram_write_index,
                         dut.mm2s_tvalid, dut.mm2s_tready, dut.bram_wr_enable, dut.wr_counter, 
                         dut.wr_counter_inst.count_reg, dut.wr_counter_done, dut.wr_count_limit, mm2s_data_count);
                prev_fsm_state = dut.fsm_inst.current_state;
            end
            
            // Print when wr_counter_done changes
            if (dut.wr_counter_done != prev_wr_done) begin
                $display("[%0t] *** WR_COUNTER_DONE: %b -> %b, count_reg=%0d limit=%0d", 
                         $time, prev_wr_done, dut.wr_counter_done, 
                         dut.wr_counter_inst.count_reg, dut.fsm_inst.wr_count_limit);
                prev_wr_done = dut.wr_counter_done;
            end
            
            // Print when demux_sel changes (BRAM switch)
            if (dut.demux_sel != prev_demux_sel) begin
                $display("[%0t] >>> BRAM SWITCH: demux_sel %0d -> %0d, wr_cnt=%0d", 
                         $time, prev_demux_sel, dut.demux_sel, dut.wr_counter);
                prev_demux_sel = dut.demux_sel;
            end
        end
    end
    
    // Monitor BRAM writes (first 10 per BRAM only)
    integer write_count [0:15];
    initial begin
        for (debug_counter = 0; debug_counter < 16; debug_counter = debug_counter + 1)
            write_count[debug_counter] = 0;
    end
    
    always @(posedge aclk) begin
        if (|bram_wr_en && aresetn) begin
            if (bram_wr_en[0] && write_count[0] < 5) begin
                $display("[%0t] BRAM[0] Addr=%03h Data=%04h", $time, bram_wr_addr, bram_wr_data_0);
                write_count[0] = write_count[0] + 1;
            end
            if (bram_wr_en[1] && write_count[1] < 5) begin
                $display("[%0t] BRAM[1] Addr=%03h Data=%04h", $time, bram_wr_addr, bram_wr_data_1);
                write_count[1] = write_count[1] + 1;
            end
            // Add similar for other BRAMs if needed
        end
    end
    
    // =========================================================================
    // Main Test
    // =========================================================================
    initial begin
        // Initialize
        aresetn = 0;
        s_axis_tdata = 0;
        s_axis_tvalid = 0;
        s_axis_tlast = 0;
        m_axis_tready = 1;
        Instruction_code = 8'h00;
        wr_bram_start = 0; wr_bram_end = 0;
        wr_addr_start = 0; wr_addr_count = 0;
        rd_bram_start = 0; rd_bram_end = 0;
        rd_addr_start = 0; rd_addr_count = 0;
        
        #(T*10); aresetn = 1; #(T*10);
        
        $display("========================================================================");
        $display("FULL WRITE TEST: 512 words to each BRAM (0-15)");
        $display("Data pattern: 1, 2, 3, ..., 8192");
        $display("Total: 16 BRAM x 512 words = 8192 words");
        $display("FSM will auto-route: BRAM0→BRAM1→...→BRAM15");
        $display("========================================================================");
        
        // Configure FSM ONCE for all 16 BRAM
        $display("\n[%0t ns] Configuring FSM: wr_bram_start=0, wr_bram_end=15", $time);
        Instruction_code = 8'h01;              // WRITE command
        wr_bram_start = 5'd0;                  // Start from BRAM 0
        wr_bram_end = 5'd15;                   // End at BRAM 15 (total 16 BRAM)
        wr_addr_start = 16'd0;                 // Start from address 0
        wr_addr_count = 16'd512;               // 512 words per BRAM
        
        #(T*5);
        
        // Send 8192 words continuously - FSM will auto-route
        $display("[%0t ns] Sending 8192 words continuously...", $time);
        data_counter = 16'd1;
        
        for (i = 0; i < 8192; i = i + 1) begin
            s_axis_tdata = data_counter;
            s_axis_tvalid = 1;
            
            // Assert TLAST on last word
            if (i == 8191)
                s_axis_tlast = 1;
            else
                s_axis_tlast = 0;
            
            // Wait for handshake
            @(posedge aclk);
            while (!s_axis_tready) @(posedge aclk);
            
            // Progress indicator every 512 words
            if ((i+1) % 512 == 0)
                $display("[%0t ns] Sent %0d words (BRAM %0d should be filling)...", 
                         $time, i+1, (i+1)/512 - 1);
            
            data_counter = data_counter + 1;
        end
        
        // Deassert valid and last
        s_axis_tvalid = 0;
        s_axis_tlast = 0;
        
        $display("[%0t ns] All 8192 words sent!", $time);
        
        // Wait for write completion
        wait(write_done);
        $display("[%0t ns] write_done asserted!", $time);
        
        $display("\n========================================================================");
        $display("ALL WRITES COMPLETED at time: %0t ns", $time);
        $display("Check waveform for bram_wr_data[0:15] values");
        $display("========================================================================");
        
        #(T*50);
        $finish;
    end
    
endmodule