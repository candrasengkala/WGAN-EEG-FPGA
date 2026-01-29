`timescale 1ns / 1ps
// Custom AXI Stream Module - Simplified Version
// Contains only MM2S FIFO and S2MM FIFO

module axis_custom
    (
        input wire         aclk,
        input wire         aresetn,
        
        // *** AXI Stream Slave Port (Input dari DMA MM2S) ***
        output wire        s_axis_tready,
        input wire [63:0]  s_axis_tdata,
        input wire         s_axis_tvalid,
        input wire         s_axis_tlast,
        
        // *** AXI Stream Master Port (Output ke DMA S2MM) ***
        input wire         m_axis_tready,
        output wire [63:0] m_axis_tdata,
        output wire        m_axis_tvalid,
        output wire        m_axis_tlast,
        
        // *** MM2S FIFO Interface (untuk user logic) ***
        output wire [63:0] mm2s_data,      // Data yang dibaca dari MM2S FIFO
        output wire        mm2s_valid,     // Data valid
        input wire         mm2s_ready,     // Ready signal dari user (untuk read data)
        output wire [7:0]  mm2s_count,     // Jumlah data di FIFO (untuk monitoring)
        
        // *** S2MM FIFO Interface (untuk user logic) ***
        input wire [63:0]  s2mm_data,      // Data yang akan ditulis ke S2MM FIFO
        input wire         s2mm_valid,     // Valid signal dari user
        output wire        s2mm_ready,     // Ready signal (FIFO siap terima data)
        input wire         s2mm_last       // Last packet indicator
    );

    // Internal signals untuk S2MM pipeline register
    reg s2mm_valid_reg;
    reg s2mm_last_reg;
    reg [63:0] s2mm_data_reg;
    
    // ============================================================================
    // MM2S FIFO (Memory-Mapped to Stream)
    // ============================================================================
    // FIFO ini menerima data dari AXI Stream Slave dan menyimpannya dalam buffer
    // User logic bisa membaca data dengan mengontrol mm2s_ready signal
    
    xpm_fifo_axis
    #(
        .CDC_SYNC_STAGES(2),                 // Clock domain crossing stages
        .CLOCKING_MODE("common_clock"),      // Single clock domain
        .ECC_MODE("no_ecc"),                 // No error correction
        .FIFO_DEPTH(128),                    // Depth 128 words (64-bit each)
        .FIFO_MEMORY_TYPE("auto"),           // Auto memory type selection
        .PACKET_FIFO("false"),               // Not packet FIFO
        .PROG_EMPTY_THRESH(10),              // Programmable empty threshold
        .PROG_FULL_THRESH(10),               // Programmable full threshold
        .RD_DATA_COUNT_WIDTH(1),             // Read data count width
        .RELATED_CLOCKS(0),                  // Clocks not related
        .SIM_ASSERT_CHK(0),                  // Disable simulation assertions
        .TDATA_WIDTH(64),                    // Data width 64-bit
        .TDEST_WIDTH(1),                     // Destination width
        .TID_WIDTH(1),                       // ID width
        .TUSER_WIDTH(1),                     // User signal width
        .USE_ADV_FEATURES("0004"),           // Enable write data count
        .WR_DATA_COUNT_WIDTH(8)              // Width = log2(128)+1 = 8
    )
    mm2s_fifo
    (
        .almost_empty_axis(), 
        .almost_full_axis(), 
        .dbiterr_axis(), 
        .prog_empty_axis(), 
        .prog_full_axis(), 
        .rd_data_count_axis(), 
        .sbiterr_axis(), 
        .injectdbiterr_axis(1'b0), 
        .injectsbiterr_axis(1'b0), 
    
        // Clock and reset
        .s_aclk(aclk),
        .m_aclk(aclk),
        .s_aresetn(aresetn),
        
        // Slave side (input dari AXI Stream)
        .s_axis_tready(s_axis_tready),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tdest(1'b0), 
        .s_axis_tid(1'b0), 
        .s_axis_tkeep(8'hff), 
        .s_axis_tlast(s_axis_tlast),
        .s_axis_tstrb(8'hff), 
        .s_axis_tuser(1'b0), 
        
        // Master side (output ke user logic)
        .m_axis_tready(mm2s_ready),
        .m_axis_tdata(mm2s_data),
        .m_axis_tvalid(mm2s_valid),
        .m_axis_tdest(), 
        .m_axis_tid(), 
        .m_axis_tkeep(), 
        .m_axis_tlast(), 
        .m_axis_tstrb(), 
        .m_axis_tuser(),  
        
        // Write data count (jumlah data di FIFO)
        .wr_data_count_axis(mm2s_count)
    );
    
    // ============================================================================
    // S2MM FIFO (Stream to Memory-Mapped)
    // ============================================================================
    // FIFO ini menerima data dari user logic dan mengirimnya ke AXI Stream Master
    // User logic menulis data dengan mengontrol s2mm_valid signal
    
    // Pipeline register untuk timing improvement
    always @(posedge aclk)
    begin
        if (!aresetn)
        begin
            s2mm_valid_reg <= 0;
            s2mm_last_reg <= 0;
            s2mm_data_reg <= 0;
        end
        else
        begin
            s2mm_valid_reg <= s2mm_valid;
            s2mm_last_reg <= s2mm_last;
            s2mm_data_reg <= s2mm_data;
        end
    end
    
    xpm_fifo_axis
    #(
        .CDC_SYNC_STAGES(2),
        .CLOCKING_MODE("common_clock"),
        .ECC_MODE("no_ecc"),
        .FIFO_DEPTH(128),                    // Depth 128 words (64-bit each)
        .FIFO_MEMORY_TYPE("auto"),
        .PACKET_FIFO("false"),
        .PROG_EMPTY_THRESH(10),
        .PROG_FULL_THRESH(10),
        .RD_DATA_COUNT_WIDTH(1),
        .RELATED_CLOCKS(0),
        .SIM_ASSERT_CHK(0),
        .TDATA_WIDTH(64),                    // Data width 64-bit
        .TDEST_WIDTH(1),
        .TID_WIDTH(1),
        .TUSER_WIDTH(1),
        .USE_ADV_FEATURES("0000"),           // No advanced features needed
        .WR_DATA_COUNT_WIDTH(8)
    )
    s2mm_fifo
    (
        .almost_empty_axis(), 
        .almost_full_axis(), 
        .dbiterr_axis(), 
        .prog_empty_axis(), 
        .prog_full_axis(), 
        .rd_data_count_axis(), 
        .sbiterr_axis(), 
        .injectdbiterr_axis(1'b0), 
        .injectsbiterr_axis(1'b0), 
    
        // Clock and reset
        .s_aclk(aclk),
        .m_aclk(aclk),
        .s_aresetn(aresetn),
        
        // Slave side (input dari user logic)
        .s_axis_tready(s2mm_ready),
        .s_axis_tdata(s2mm_data_reg),
        .s_axis_tvalid(s2mm_valid_reg),
        .s_axis_tdest(1'b0), 
        .s_axis_tid(1'b0), 
        .s_axis_tkeep(8'hff), 
        .s_axis_tlast(s2mm_last_reg),
        .s_axis_tstrb(8'hff), 
        .s_axis_tuser(1'b0), 
        
        // Master side (output ke AXI Stream)
        .m_axis_tready(m_axis_tready),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tdest(), 
        .m_axis_tid(), 
        .m_axis_tkeep(), 
        .m_axis_tlast(m_axis_tlast), 
        .m_axis_tstrb(), 
        .m_axis_tuser(),  
        
        .wr_data_count_axis()
    );

endmodule

