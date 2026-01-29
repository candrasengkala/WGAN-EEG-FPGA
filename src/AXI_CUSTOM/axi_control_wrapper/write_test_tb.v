`timescale 1ns / 1ps

/******************************************************************************
 * Simple Testbench: WRITE + READ Test (TANPA header injection dulu)
 * 
 * Test dengan wrapper ORIGINAL (belum ada header injection)
 ******************************************************************************/

module simple_write_read_tb();

    localparam T = 10;
    
    // Signals
    reg aclk, aresetn;
    
    // AXI Stream Slave (WRITE)
    reg [15:0] s_axis_tdata;
    reg s_axis_tvalid;
    wire s_axis_tready;
    reg s_axis_tlast;
    
    // AXI Stream Master (READ)
    wire [15:0] m_axis_tdata;
    wire m_axis_tvalid;
    reg m_axis_tready;
    wire m_axis_tlast;
    
    // Status
    wire write_done, read_done;
    wire [9:0] mm2s_data_count;
    wire [2:0] parser_state;
    wire error_invalid_magic;
    
    // BRAM interface
    wire [255:0] bram_wr_data_flat;  // 16 BRAMs x 16-bit
    wire [8:0] bram_wr_addr;
    wire [15:0] bram_wr_en;
    
    reg [127:0] bram_rd_data_flat;   // 8 BRAMs x 16-bit
    wire [8:0] bram_rd_addr;
    
    // Simple BRAM model (2 BRAMs only)
    reg [15:0] bram0_mem [0:31];
    reg [15:0] bram1_mem [0:31];
    
    integer i;
    
    // ========================================================================
    // DUT Instantiation (WRAPPER ORIGINAL - tanpa header ports)
    // ========================================================================
    axis_control_wrapper #(
        .BRAM_DEPTH(512),
        .DATA_WIDTH(16),
        .BRAM_COUNT(16),
        .ADDR_WIDTH(9)
    ) dut (
        .aclk(aclk),
        .aresetn(aresetn),
        
        // AXI Slave
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tlast(s_axis_tlast),
        
        // AXI Master
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast(m_axis_tlast),
        
        // Status
        .write_done(write_done),
        .read_done(read_done),
        .mm2s_data_count(mm2s_data_count),
        .parser_state(parser_state),
        .error_invalid_magic(error_invalid_magic),
        
        // BRAM
        .bram_wr_data_flat(bram_wr_data_flat),
        .bram_wr_addr(bram_wr_addr),
        .bram_wr_en(bram_wr_en),
        .bram_rd_data_flat(bram_rd_data_flat),
        .bram_rd_addr(bram_rd_addr)
    );
    
    // ========================================================================
    // BRAM Write Model
    // ========================================================================
    always @(posedge aclk) begin
        if (bram_wr_en[0])
            bram0_mem[bram_wr_addr[4:0]] <= bram_wr_data_flat[15:0];
        if (bram_wr_en[1])
            bram1_mem[bram_wr_addr[4:0]] <= bram_wr_data_flat[31:16];
    end
    
    // ========================================================================
    // BRAM Read Model
    // ========================================================================
    always @(*) begin
        bram_rd_data_flat[15:0]   = bram0_mem[bram_rd_addr[4:0]];
        bram_rd_data_flat[31:16]  = bram1_mem[bram_rd_addr[4:0]];
        bram_rd_data_flat[47:32]  = 16'h0000;
        bram_rd_data_flat[63:48]  = 16'h0000;
        bram_rd_data_flat[79:64]  = 16'h0000;
        bram_rd_data_flat[95:80]  = 16'h0000;
        bram_rd_data_flat[111:96] = 16'h0000;
        bram_rd_data_flat[127:112]= 16'h0000;
    end
    
    // ========================================================================
    // Clock
    // ========================================================================
    always begin aclk = 0; #(T/2); aclk = 1; #(T/2); end
    
    // ========================================================================
    // AXI Send Task
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
    // Main Test
    // ========================================================================
    initial begin
        // Initialize
        aresetn = 0;
        s_axis_tdata = 0;
        s_axis_tvalid = 0;
        s_axis_tlast = 0;
        m_axis_tready = 1;
        
        for (i = 0; i < 32; i = i + 1) begin
            bram0_mem[i] = 16'h0000;
            bram1_mem[i] = 16'h0000;
        end
        
        #(T*10);
        aresetn = 1;
        $display("\n[%0t] ========== RESET RELEASED ==========\n", $time);
        #(T*5);
        
        // ====================================================================
        // TEST 1: WRITE DATA
        // ====================================================================
        $display("[%0t] ===== TEST 1: WRITE =====", $time);
        $display("  Target: BRAM 0-1");
        $display("  Data: 0x0001-0x0010 (BRAM 0), 0x0101-0x0110 (BRAM 1)");
        
        // Header (6 words)
        send_word(16'hC0DE, 0);  // Magic
        send_word(16'h0001, 0);  // Instruction: WRITE
        send_word(16'h0000, 0);  // BRAM start = 0
        send_word(16'h0001, 0);  // BRAM end = 1
        send_word(16'h0000, 0);  // Addr start = 0
        send_word(16'h0010, 0);  // Count = 16 words
        
        // Data BRAM 0 (16 words)
        for (i = 1; i <= 16; i = i + 1) begin
            send_word(i[15:0], 0);
        end
        
        // Data BRAM 1 (16 words)
        for (i = 1; i <= 16; i = i + 1) begin
            send_word((16'h0100 + i[15:0]), (i == 16) ? 1 : 0);
        end
        
        $display("[%0t] Waiting for write_done...", $time);
        wait(write_done);
        $display("[%0t] WRITE COMPLETE!", $time);
        
        // Verify
        $display("\n[%0t] BRAM 0:", $time);
        for (i = 0; i < 16; i = i + 1)
            $display("  [%2d] = 0x%04h", i, bram0_mem[i]);
        
        $display("\n[%0t] BRAM 1:", $time);
        for (i = 0; i < 16; i = i + 1)
            $display("  [%2d] = 0x%04h", i, bram1_mem[i]);
        
        #(T*50);
        
        // ====================================================================
        // TEST 2: READ DATA
        // ====================================================================
        $display("\n[%0t] ===== TEST 2: READ =====", $time);
        $display("  Reading BRAM 0-1 back");
        
        // Header
        send_word(16'hC0DE, 0);  // Magic
        send_word(16'h0002, 0);  // Instruction: READ
        send_word(16'h0000, 0);  // BRAM start = 0
        send_word(16'h0001, 0);  // BRAM end = 1
        send_word(16'h0000, 0);  // Addr start = 0
        send_word(16'h0010, 1);  // Count = 16, TLAST
        
        $display("[%0t] Receiving data...", $time);
        
        // Monitor output
        fork
            begin
                integer word_count;
                word_count = 0;
                
                while (!read_done) begin
                    @(posedge aclk);
                    if (m_axis_tvalid && m_axis_tready) begin
                        $display("  [%2d] = 0x%04h%s", 
                                 word_count, m_axis_tdata, 
                                 m_axis_tlast ? " (TLAST)" : "");
                        word_count = word_count + 1;
                    end
                end
            end
        join_none
        
        wait(read_done);
        $display("[%0t] READ COMPLETE!", $time);
        
        #(T*100);
        
        $display("\n[%0t] ========== ALL TESTS PASSED ==========", $time);
        $finish;
    end
    
    // Timeout
    initial begin
        #(T*100000);
        $display("\n!!! TIMEOUT !!!");
        $finish;
    end

endmodule