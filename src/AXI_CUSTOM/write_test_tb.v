`timescale 1ns / 1ps

/******************************************************************************
 * DEBUG Testbench: Write Sequence with Deep Monitoring
 ******************************************************************************/

module axis_control_wrapper_debug_tb();

    localparam T = 10;
    
    reg aclk, aresetn;
    reg [15:0] s_axis_tdata;
    reg s_axis_tvalid;
    wire s_axis_tready;
    reg s_axis_tlast;
    
    wire [15:0] m_axis_tdata;
    wire m_axis_tvalid;
    reg m_axis_tready;
    wire m_axis_tlast;
    
    wire write_done, read_done;
    wire [9:0] mm2s_data_count;
    wire [2:0] parser_state;
    wire error_invalid_magic;

    // Flattened signals
    wire [255:0] bram_wr_data_flat;
    wire [8:0] bram_wr_addr;
    wire [15:0] bram_wr_en;
    reg [127:0] bram_rd_data_flat;
    wire [8:0] bram_rd_addr;
    
    integer i;
    
    // DUT instantiation
    axis_control_wrapper #(
        .BRAM_DEPTH(512), .DATA_WIDTH(16), .BRAM_COUNT(16), .ADDR_WIDTH(9)
    ) dut (
        .aclk(aclk), .aresetn(aresetn),
        .s_axis_tdata(s_axis_tdata), .s_axis_tvalid(s_axis_tvalid), .s_axis_tready(s_axis_tready), .s_axis_tlast(s_axis_tlast),
        .m_axis_tdata(m_axis_tdata), .m_axis_tvalid(m_axis_tvalid), .m_axis_tready(m_axis_tready), .m_axis_tlast(m_axis_tlast),
        .write_done(write_done), .read_done(read_done), .mm2s_data_count(mm2s_data_count),
        .parser_state(parser_state), .error_invalid_magic(error_invalid_magic),
        .bram_wr_data_flat(bram_wr_data_flat), .bram_wr_addr(bram_wr_addr), .bram_wr_en(bram_wr_en),
        .bram_rd_data_flat(bram_rd_data_flat), .bram_rd_addr(bram_rd_addr)
    );
    
    // Clock Generation
    always begin aclk = 0; #(T/2); aclk = 1; #(T/2); end
    
    // ========================================================================
    // DEBUG MONITORING BLOCK (INTIP JEROAN FSM & COUNTER)
    // ========================================================================
    // Kita gunakan path hierarki untuk membaca sinyal internal
    // Pastikan nama instance sesuai: dut -> axis_top_inst -> fsm_inst / wr_counter_inst
    
    wire [3:0] debug_fsm_state      = dut.axis_top_inst.fsm_inst.current_state;
    wire [4:0] debug_bram_idx       = dut.axis_top_inst.fsm_inst.bram_write_index;
    wire [15:0] debug_counter       = dut.axis_top_inst.wr_counter;
    wire [15:0] debug_limit         = dut.axis_top_inst.wr_count_limit;
    wire debug_cnt_done             = dut.axis_top_inst.wr_counter_done;
    wire [4:0] debug_target_end     = dut.axis_top_inst.fsm_inst.wr_bram_end_reg;
    
    // Menampilkan status FSM setiap kali State Berubah
    always @(debug_fsm_state) begin
        $display("[%0t] [FSM STATE CHANGE] New State: %0d | BRAM Target: %0d (Limit: %0d)", 
                 $time, debug_fsm_state, debug_bram_idx, debug_target_end);
                 
        // Definisi State untuk referensi baca log:
        // 0: IDLE, 1: WRITE_SETUP, 2: WRITE_WAIT, 7: DONE
        if (debug_fsm_state == 7) 
            $display("[%0t] !!! FSM REACHED DONE STATE !!!", $time);
    end

    // Menampilkan progress Counter setiap 50ns (agar tidak spamming tiap clock)
    always begin
        #(T*5);
        if (debug_fsm_state == 2) begin // Hanya print saat state WRITE_WAIT
            $display("[%0t] [WRITE BUSY] BRAM#%0d | Addr: %0d / %0d | DoneSignal: %b", 
                     $time, debug_bram_idx, debug_counter, debug_limit, debug_cnt_done);
        end
    end
    
    // Monitor Sinyal WRITE DONE (Output Utama)
    always @(posedge write_done) begin
        $display("\n###############################################################");
        $display("[%0t] >>> SUKSES! write_done Asserted (HIGH) <<<", $time);
        $display("###############################################################\n");
    end

    // ========================================================================
    // TASK: SEND WORD
    // ========================================================================
    task send_word;
        input [15:0] data;
        input is_last;
        begin
            s_axis_tdata = data;
            s_axis_tvalid = 1;
            s_axis_tlast = is_last;
            
            @(posedge aclk);
            while (!s_axis_tready) @(posedge aclk);
            
            #1;
            s_axis_tvalid = 0;
            s_axis_tlast = 0;
        end
    endtask
    
    // ========================================================================
    // MAIN TEST SEQUENCE
    // ========================================================================
    initial begin
        aresetn = 0;
        s_axis_tdata = 0; s_axis_tvalid = 0; s_axis_tlast = 0;
        m_axis_tready = 1; bram_rd_data_flat = 0;
        
        #(T*10);
        aresetn = 1;
        #(T*20);
        
        $display("========================================================================");
        $display("START DEBUG SIMULATION");
        $display("========================================================================\n");
        
        // 1. Send Header Configuration
        $display("[%0t] Sending Header...", $time);
        send_word(16'hC0DE, 0); // Magic
        send_word(16'h0001, 0); // Instruction: WRITE
        send_word(16'h0002, 0); // BRAM Start (2)
        send_word(16'h0006, 0); // BRAM End   (6) -> Kita mau isi BRAM 2,3,4,5
        send_word(16'h0000, 0); // Addr Start (0)
        send_word(16'h002A, 0); // Count (42 words per BRAM)
        
        #(T*20);
        
        // 2. Send Data Payload
        // Total data needed: 4 BRAMs * 42 words = 168 words
        // Kita kirim 170 agar sisa 2 masuk ke BRAM selanjutnya atau FIFO
        $display("\n[%0t] Sending Data Payload (Target: Fill BRAM 2,3,4,5)...", $time);
        
        for (i = 1; i <= 170; i = i + 1) begin
            send_word(i, (i==170));
        end
        
        // Tunggu agak lama untuk melihat apakah DONE muncul
        #(T*100);
        
        $display("\n[%0t] Simulation Finished. Checking Results...", $time);
        if (write_done == 0) begin
             $display("!!! FAILURE: write_done is still LOW (0) !!!");
             $display("Check logs above to see where FSM got stuck.");
        end
        $finish;
    end
    
endmodule