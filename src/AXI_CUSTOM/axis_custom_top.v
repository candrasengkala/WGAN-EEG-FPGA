`timescale 1ns / 1ps

// Top-Level Module: AXI Custom IP with FIFO, Demux, BRAM, Mux, Counter, FSM
// Architecture: DMA → FIFO → Demux → 16 BRAM → Mux → FIFO → DMA
// FSM Control: Instruction decoder untuk write/read/duplex operation

module axis_custom_top #(
    parameter BRAM_DEPTH = 512,
    parameter DATA_WIDTH = 16,
    parameter BRAM_COUNT = 16
)(
    // Clock and Reset
    input wire aclk,
    input wire aresetn,
    
    // AXI Stream Slave (from DMA MM2S)
    input wire [DATA_WIDTH-1:0] s_axis_tdata,
    input wire s_axis_tvalid,
    output wire s_axis_tready,
    input wire s_axis_tlast,
    
    // AXI Stream Master (to DMA S2MM)
    output wire [DATA_WIDTH-1:0] m_axis_tdata,
    output wire m_axis_tvalid,
    input wire m_axis_tready,
    output wire m_axis_tlast,
    
    // ============================================================================
    // FSM Control Interface (simplified - hanya ini yang perlu dari luar)
    // ============================================================================
    input wire [7:0] Instruction_code,    // 0x01=WRITE, 0x02=READ, 0x03=DUPLEX
    
    // Write parameters
    input wire [4:0] wr_bram_start,       // BRAM awal untuk write (0-31)
    input wire [4:0] wr_bram_end,         // BRAM akhir untuk write (0-31)
    input wire [15:0] wr_addr_start,      // Address awal untuk write
    input wire [15:0] wr_addr_count,      // Jumlah word per BRAM
    
    // Read parameters
    input wire [2:0] rd_bram_start,       // BRAM awal untuk read (0-7)
    input wire [2:0] rd_bram_end,         // BRAM akhir untuk read (0-7)
    input wire [15:0] rd_addr_start,      // Address awal untuk read
    input wire [15:0] rd_addr_count,      // Jumlah word per BRAM
    
    // Status outputs
    output wire write_done,
    output wire read_done,
    output wire [9:0] mm2s_data_count,
    
    // BRAM Write Interface (to 16 BRAM) - dari demux 1-to-16
    output wire [15:0] bram_wr_data_0,
    output wire [15:0] bram_wr_data_1,
    output wire [15:0] bram_wr_data_2,
    output wire [15:0] bram_wr_data_3,
    output wire [15:0] bram_wr_data_4,
    output wire [15:0] bram_wr_data_5,
    output wire [15:0] bram_wr_data_6,
    output wire [15:0] bram_wr_data_7,
    output wire [15:0] bram_wr_data_8,
    output wire [15:0] bram_wr_data_9,
    output wire [15:0] bram_wr_data_10,
    output wire [15:0] bram_wr_data_11,
    output wire [15:0] bram_wr_data_12,
    output wire [15:0] bram_wr_data_13,
    output wire [15:0] bram_wr_data_14,
    output wire [15:0] bram_wr_data_15,
    output wire [8:0] bram_wr_addr,
    output wire [15:0] bram_wr_en,
    
    // BRAM Read Interface (from 8 BRAM) - ke mux 8-to-1
    input wire [15:0] bram_rd_data_0,
    input wire [15:0] bram_rd_data_1,
    input wire [15:0] bram_rd_data_2,
    input wire [15:0] bram_rd_data_3,
    input wire [15:0] bram_rd_data_4,
    input wire [15:0] bram_rd_data_5,
    input wire [15:0] bram_rd_data_6,
    input wire [15:0] bram_rd_data_7,
    output wire [8:0] bram_rd_addr
);

    // ============================================================================
    // Internal Wires
    // ============================================================================
    
    // MM2S FIFO outputs (from DMA to processing)
    wire [DATA_WIDTH-1:0] mm2s_tdata;
    wire mm2s_tvalid;
    wire mm2s_tready;
    wire mm2s_tlast;
    
    // S2MM FIFO inputs (from processing to DMA)
    wire [DATA_WIDTH-1:0] s2mm_tdata;
    wire s2mm_tvalid;
    wire s2mm_tready;
    wire s2mm_tlast;
    
    // FSM to Counter control signals
    wire wr_counter_enable;
    wire wr_counter_start;
    wire [15:0] wr_start_addr;
    wire [15:0] wr_count_limit;
    wire rd_counter_enable;
    wire rd_counter_start;
    wire [15:0] rd_start_addr;
    wire [15:0] rd_count_limit;
    
    // Counter outputs
    wire [15:0] wr_counter;
    wire wr_counter_done;
    wire [15:0] rd_counter;        // FIXED: Added missing wire declaration
    wire rd_counter_done;
    
    // FSM to Demux/Mux control
    wire [4:0] demux_sel;
    wire [2:0] mux_sel;
    wire bram_rd_enable;
    
    // Demux outputs
    wire [DATA_WIDTH-1:0] demux_out [0:BRAM_COUNT-1];
    
    // BRAM signals (simplified - add BRAM instantiation later)
    wire [DATA_WIDTH-1:0] bram_dout [0:BRAM_COUNT-1];
    
    // Mux output (1x mux 8-to-1 untuk BRAM 0-7)
    wire [DATA_WIDTH-1:0] mux_out;
    
    // Parser flag (for FSM bram_wr_enable)
    wire bram_wr_enable;
    assign bram_wr_enable = mm2s_tvalid && mm2s_tready;
    
    // ============================================================================
    // Module Instantiations
    // ============================================================================
    
    // -------------------------------------------------------------------------
    // 1. External_AXI_FSM: Main Control FSM
    // -------------------------------------------------------------------------
    External_AXI_FSM fsm_inst (
        .aclk(aclk),
        .aresetn(aresetn),
        
        // Instruction decoder input
        .Instruction_code(Instruction_code),
        
        // Write parameters
        .wr_bram_start(wr_bram_start),
        .wr_bram_end(wr_bram_end),
        .wr_addr_start(wr_addr_start),
        .wr_addr_count(wr_addr_count),
        
        // Read parameters
        .rd_bram_start(rd_bram_start),
        .rd_bram_end(rd_bram_end),
        .rd_addr_start(rd_addr_start),
        .rd_addr_count(rd_addr_count),
        
        // Control flags
        .bram_wr_enable(bram_wr_enable),
        .wr_counter_done(wr_counter_done),
        .rd_counter_done(rd_counter_done),
        
        // Write counter control outputs
        .wr_counter_enable(wr_counter_enable),
        .wr_counter_start(wr_counter_start),
        .wr_start_addr(wr_start_addr),
        .wr_count_limit(wr_count_limit),
        
        // Read counter control outputs
        .rd_counter_enable(rd_counter_enable),
        .rd_counter_start(rd_counter_start),
        .rd_start_addr(rd_start_addr),
        .rd_count_limit(rd_count_limit),
        
        // BRAM routing control
        .demux_sel(demux_sel),
        .mux_sel(mux_sel),
        .bram_rd_enable(bram_rd_enable)
    );
    
    // -------------------------------------------------------------------------
    // 2. MM2S_S2MM: FIFO Wrapper (Input and Output Buffering)
    // -------------------------------------------------------------------------
    MM2S_S2MM #(
        .FIFO_DEPTH(512),
        .DATA_WIDTH(DATA_WIDTH)
    ) fifo_wrapper (
        .aclk(aclk),
        .aresetn(aresetn),
        
        // AXI Stream Slave (from DMA)
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tlast(s_axis_tlast),
        
        // MM2S Output (to processing)
        .mm2s_tdata(mm2s_tdata),
        .mm2s_tvalid(mm2s_tvalid),
        .mm2s_tready(mm2s_tready),
        .mm2s_tlast(mm2s_tlast),
        .mm2s_data_count(mm2s_data_count),
        
        // S2MM Input (from processing)
        .s2mm_tdata(s2mm_tdata),
        .s2mm_tvalid(s2mm_tvalid),
        .s2mm_tready(s2mm_tready),
        .s2mm_tlast(s2mm_tlast),
        
        // AXI Stream Master (to DMA)
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast(m_axis_tlast)
    );
    
    // -------------------------------------------------------------------------
    // 3. Write Counter: Address generation for writing to BRAM
    // -------------------------------------------------------------------------
    axis_counter wr_counter_inst (
        .aclk(aclk),
        .aresetn(aresetn),
        .counter_enable(wr_counter_enable),
        .counter_start(wr_counter_start),
        .start_addr(wr_start_addr),
        .count_limit(wr_count_limit),
        .counter(wr_counter),
        .counter_done(wr_counter_done)
    );
    
    // Write done output
    assign write_done = wr_counter_done;
    
    // -------------------------------------------------------------------------
    // 4. Read Counter: Address generation for reading from BRAM
    // -------------------------------------------------------------------------
    axis_counter rd_counter_inst (
        .aclk(aclk),
        .aresetn(aresetn),
        .counter_enable(rd_counter_enable),
        .counter_start(rd_counter_start),
        .start_addr(rd_start_addr),
        .count_limit(rd_count_limit),
        .counter(rd_counter),
        .counter_done(rd_counter_done)
    );
    
    // Read done output
    assign read_done = rd_counter_done;
    
    // -------------------------------------------------------------------------
    // 5. Demux 1-to-16: Route MM2S data to selected BRAM
    // -------------------------------------------------------------------------
    demux1to16 #(
        .DATA_WIDTH(DATA_WIDTH)
    ) demux_inst (
        .data_in(mm2s_tdata),
        .sel(demux_sel[3:0]),
        .out_0(demux_out[0]),
        .out_1(demux_out[1]),
        .out_2(demux_out[2]),
        .out_3(demux_out[3]),
        .out_4(demux_out[4]),
        .out_5(demux_out[5]),
        .out_6(demux_out[6]),
        .out_7(demux_out[7]),
        .out_8(demux_out[8]),
        .out_9(demux_out[9]),
        .out_10(demux_out[10]),
        .out_11(demux_out[11]),
        .out_12(demux_out[12]),
        .out_13(demux_out[13]),
        .out_14(demux_out[14]),
        .out_15(demux_out[15])
    );
    
    // -------------------------------------------------------------------------
    // 6. Mux 8-to-1: Select from BRAM 0-7
    // -------------------------------------------------------------------------
    mux8to1 #(
        .DATA_WIDTH(DATA_WIDTH)
    ) mux_inst (
        .in_0(bram_dout[0]),
        .in_1(bram_dout[1]),
        .in_2(bram_dout[2]),
        .in_3(bram_dout[3]),
        .in_4(bram_dout[4]),
        .in_5(bram_dout[5]),
        .in_6(bram_dout[6]),
        .in_7(bram_dout[7]),
        .sel(mux_sel[2:0]),
        .data_out(mux_out)
    );
    
    // -------------------------------------------------------------------------
    // 7. Direct connection to S2MM
    // -------------------------------------------------------------------------
    assign s2mm_tdata = mux_out;
    
    // ============================================================================
    // Control Logic (simplified - controlled by FSM)
    // ============================================================================
    
    // MM2S ready: accept data saat FSM siap terima (state WRITE_WAIT atau DUPLEX_WAIT)
    // Tidak boleh tergantung wr_counter_enable karena akan circular dependency
    wire fsm_write_active;
    assign fsm_write_active = (fsm_inst.current_state == 4'd2) || // WRITE_WAIT
                              (fsm_inst.current_state == 4'd6);   // DUPLEX_WAIT
    assign mm2s_tready = fsm_write_active;
    
    // S2MM valid: send data when FSM enables read
    assign s2mm_tvalid = bram_rd_enable && rd_counter_enable;
    
    // TLAST generation (simplified - assert on last count)
    assign s2mm_tlast = rd_counter_done;
    
    // ============================================================================
    // BRAM Write Interface - Connect 16 demux outputs
    // ============================================================================
    assign bram_wr_data_0 = demux_out[0];
    assign bram_wr_data_1 = demux_out[1];
    assign bram_wr_data_2 = demux_out[2];
    assign bram_wr_data_3 = demux_out[3];
    assign bram_wr_data_4 = demux_out[4];
    assign bram_wr_data_5 = demux_out[5];
    assign bram_wr_data_6 = demux_out[6];
    assign bram_wr_data_7 = demux_out[7];
    assign bram_wr_data_8 = demux_out[8];
    assign bram_wr_data_9 = demux_out[9];
    assign bram_wr_data_10 = demux_out[10];
    assign bram_wr_data_11 = demux_out[11];
    assign bram_wr_data_12 = demux_out[12];
    assign bram_wr_data_13 = demux_out[13];
    assign bram_wr_data_14 = demux_out[14];
    assign bram_wr_data_15 = demux_out[15];
    assign bram_wr_addr = wr_counter[8:0];  // 9-bit address for 512 depth
    assign bram_wr_en = (16'b1 << demux_sel) & {16{wr_counter_enable}};  // One-hot write enable
    
    // ============================================================================
    // BRAM Read Interface
    // ============================================================================
    assign bram_rd_addr = rd_counter[8:0];  // 9-bit address for 512 depth
    
    // Connect BRAM read data to mux inputs (only 8 BRAM)
    assign bram_dout[0] = bram_rd_data_0;
    assign bram_dout[1] = bram_rd_data_1;
    assign bram_dout[2] = bram_rd_data_2;
    assign bram_dout[3] = bram_rd_data_3;
    assign bram_dout[4] = bram_rd_data_4;
    assign bram_dout[5] = bram_rd_data_5;
    assign bram_dout[6] = bram_rd_data_6;
    assign bram_dout[7] = bram_rd_data_7;

endmodule