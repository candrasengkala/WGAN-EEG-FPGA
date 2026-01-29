/******************************************************************************
 * Module: axis_custom_top
 * * Description:
 * AXI Stream custom IP dengan FLATTENED BRAM interface.
 * Architecture: DMA -> FIFO -> Demux -> 16 BRAM -> Mux -> FIFO -> DMA
 * * FIXED VERSION: 
 * 1. Data leak fix on mm2s_tready
 * 2. Correct done signal wiring from FSM
 ******************************************************************************/

`timescale 1ns / 1ps
`include "External_AXI_FSM.v"
`include "MM2S_S2MM.v"
`include "axis_counter.v"
`include "demux1to16.v"
`include "mux8to1.v"

module axis_custom_top #(
    parameter BRAM_DEPTH = 512,
    parameter DATA_WIDTH = 16,
    parameter BRAM_COUNT = 16,
    parameter ADDR_WIDTH = 9
)(
    // Clock and Reset
    input wire aclk,
    input wire aresetn,
    
    // ========================================================================
    // AXI Stream Slave (from DMA MM2S)
    // ========================================================================
    input wire [DATA_WIDTH-1:0] s_axis_tdata,
    input wire s_axis_tvalid,
    output wire s_axis_tready,
    input wire s_axis_tlast,
    
    // ========================================================================
    // AXI Stream Master (to DMA S2MM)
    // ========================================================================
    output wire [DATA_WIDTH-1:0] m_axis_tdata,
    output wire m_axis_tvalid,
    input wire m_axis_tready,
    output wire m_axis_tlast,
    
    // ========================================================================
    // FSM Control Interface
    // ========================================================================
    input wire [7:0] Instruction_code,
    
    // Write parameters
    input wire [4:0] wr_bram_start,
    input wire [4:0] wr_bram_end,
    input wire [15:0] wr_addr_start,
    input wire [15:0] wr_addr_count,
    
    // Read parameters
    input wire [2:0] rd_bram_start, 
    input wire [2:0] rd_bram_end,
    input wire [15:0] rd_addr_start,
    input wire [15:0] rd_addr_count,
    
    // NEW: Header injection for READ packets
    input wire [15:0] header_word_0,
    input wire [15:0] header_word_1,
    input wire [15:0] header_word_2,
    input wire [15:0] header_word_3,
    input wire [15:0] header_word_4,
    input wire [15:0] header_word_5,
    input wire        send_header,        // 1 = inject header before data
    
    // Status outputs
    output wire write_done,
    output wire read_done,
    output wire [9:0] mm2s_data_count,
    
    // ========================================================================
    // BRAM Write Interface - FLATTENED (to 16 BRAM)
    // ========================================================================
    output wire [BRAM_COUNT*DATA_WIDTH-1:0] bram_wr_data_flat,
    output wire [ADDR_WIDTH-1:0]            bram_wr_addr,
    output wire [BRAM_COUNT-1:0]            bram_wr_en,
    
    // ========================================================================
    // BRAM Read Interface - FLATTENED (from 8 BRAM)
    // ========================================================================
    input  wire [8*DATA_WIDTH-1:0]          bram_rd_data_flat,
    output wire [ADDR_WIDTH-1:0]            bram_rd_addr
);
    // ========================================================================
    // Internal Wires
    // ========================================================================
    
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
    wire [15:0] rd_counter;
    wire rd_counter_done;

    // FSM to Demux/Mux control
    wire [4:0] demux_sel;
    wire [2:0] mux_sel;
    wire bram_rd_enable;
    
    // Demux outputs (internal array)
    wire [DATA_WIDTH-1:0] demux_out [0:BRAM_COUNT-1];
    
    // BRAM read data (internal array)
    wire [DATA_WIDTH-1:0] bram_dout [0:7];
    
    // Mux output
    wire [DATA_WIDTH-1:0] mux_out;
    
    // FSM Batch Done Signals
    wire fsm_batch_write_done;
    wire fsm_batch_read_done;
    
    // Helper flag
    wire bram_wr_enable;
    assign bram_wr_enable = mm2s_tvalid && mm2s_tready;
    
    // ========================================================================
    // Module Instantiations
    // ========================================================================
    
    External_AXI_FSM fsm_inst (
        .aclk(aclk),
        .aresetn(aresetn),
        .Instruction_code(Instruction_code),
        .wr_bram_start(wr_bram_start),
        .wr_bram_end(wr_bram_end),
        .wr_addr_start(wr_addr_start),
        .wr_addr_count(wr_addr_count),
        
        .rd_bram_start(rd_bram_start),
        .rd_bram_end(rd_bram_end),
        .rd_addr_start(rd_addr_start),
        .rd_addr_count(rd_addr_count),
        .bram_wr_enable(bram_wr_enable),
        .wr_counter_done(wr_counter_done),
        .rd_counter_done(rd_counter_done),
        .wr_counter_enable(wr_counter_enable),
        .wr_counter_start(wr_counter_start),
        .wr_start_addr(wr_start_addr),
        .wr_count_limit(wr_count_limit),
        .rd_counter_enable(rd_counter_enable),
        .rd_counter_start(rd_counter_start),
    
        .rd_start_addr(rd_start_addr),
        .rd_count_limit(rd_count_limit),
        .demux_sel(demux_sel),
        .mux_sel(mux_sel),
        .bram_rd_enable(bram_rd_enable),
        
        // Connect New Done Signals
        .batch_write_done(fsm_batch_write_done),
        .batch_read_done(fsm_batch_read_done)
    );

    // MM2S_S2MM: FIFO Wrapper
    MM2S_S2MM #(
        .FIFO_DEPTH(512),
        .DATA_WIDTH(DATA_WIDTH)
    ) fifo_wrapper (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tlast(s_axis_tlast),
        .mm2s_tdata(mm2s_tdata),
        .mm2s_tvalid(mm2s_tvalid),
        .mm2s_tready(mm2s_tready),
        .mm2s_tlast(mm2s_tlast),
        .mm2s_data_count(mm2s_data_count),
        .s2mm_tdata(s2mm_tdata),
        .s2mm_tvalid(s2mm_tvalid),
        .s2mm_tready(s2mm_tready),
        .s2mm_tlast(s2mm_tlast),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast(m_axis_tlast)
    );

    // Write Counter
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
    
    // FIX: Gunakan sinyal DONE dari FSM, bukan dari counter per-BRAM
    assign write_done = fsm_batch_write_done;
    
    // Read Counter
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
    
    // FIX: Gunakan sinyal DONE dari FSM
    assign read_done = fsm_batch_read_done;
    
    // Demux 1-to-16
    demux1to16 #(
        .DATA_WIDTH(DATA_WIDTH)
    ) demux_inst (
        .data_in(mm2s_tdata),
        .sel(demux_sel[3:0]),
        .out_0(demux_out[0]), .out_1(demux_out[1]), .out_2(demux_out[2]), .out_3(demux_out[3]),
        .out_4(demux_out[4]), .out_5(demux_out[5]), .out_6(demux_out[6]), .out_7(demux_out[7]),
        .out_8(demux_out[8]), .out_9(demux_out[9]), .out_10(demux_out[10]), .out_11(demux_out[11]),
        .out_12(demux_out[12]), .out_13(demux_out[13]), .out_14(demux_out[14]), .out_15(demux_out[15])
    );

    // Mux 8-to-1
    mux8to1 #(
        .DATA_WIDTH(DATA_WIDTH)
    ) mux_inst (
        .in_0(bram_dout[0]), .in_1(bram_dout[1]), .in_2(bram_dout[2]), .in_3(bram_dout[3]),
        .in_4(bram_dout[4]), .in_5(bram_dout[5]), .in_6(bram_dout[6]), .in_7(bram_dout[7]),
        .sel(mux_sel[2:0]),
        .data_out(mux_out)
    );
    
    // ========================================================================
    // HEADER INJECTION LOGIC
    // ========================================================================
    reg [15:0] header_buffer [0:5];
    reg [2:0] header_word_count;
    reg sending_header;
    reg header_sent;
    
    always @(posedge aclk) begin
        if (!aresetn) begin
            header_buffer[0] <= 16'd0;
            header_buffer[1] <= 16'd0;
            header_buffer[2] <= 16'd0;
            header_buffer[3] <= 16'd0;
            header_buffer[4] <= 16'd0;
            header_buffer[5] <= 16'd0;
            header_word_count <= 3'd0;
            sending_header <= 1'b0;
            header_sent <= 1'b0;
        end else begin
            // Latch header saat send_header trigger
            if (send_header && !sending_header && !header_sent) begin
                header_buffer[0] <= header_word_0;
                header_buffer[1] <= header_word_1;
                header_buffer[2] <= header_word_2;
                header_buffer[3] <= header_word_3;
                header_buffer[4] <= header_word_4;
                header_buffer[5] <= header_word_5;
                sending_header <= 1'b1;
                header_word_count <= 3'd0;
            end
            
            // Send header words sequentially
            if (sending_header && s2mm_tready) begin
                if (header_word_count < 3'd5) begin
                    header_word_count <= header_word_count + 1;
                end else begin
                    // Header complete
                    sending_header <= 1'b0;
                    header_sent <= 1'b1;
                end
            end
            
            // Clear header_sent saat READ selesai
            if (rd_counter_done) begin
                header_sent <= 1'b0;
            end
        end
    end
    
    // MUX antara header dan BRAM data
    wire [15:0] s2mm_data_muxed;
    assign s2mm_data_muxed = sending_header ? header_buffer[header_word_count] : mux_out;
    
    // S2MM connection dengan header injection
    assign s2mm_tdata = s2mm_data_muxed;

    // ========================================================================
    // Control Logic
    // ========================================================================
    wire fsm_write_active;
    assign fsm_write_active = (fsm_inst.current_state == 4'd2) || 
                              (fsm_inst.current_state == 4'd6);
    
    // *** CRITICAL FIX: DATA LEAK PREVENTION ***
    // Stop tready immediately when counter is done, preventing the FIFO 
    // from sending the next word before FSM transitions.
    assign mm2s_tready = fsm_write_active && !wr_counter_done;
    
    // s2mm_tvalid active saat sending header ATAU reading BRAM
    assign s2mm_tvalid = sending_header || (bram_rd_enable && rd_counter_enable);
    assign s2mm_tlast = rd_counter_done;
    
    // ========================================================================
    // BRAM Write Interface - FLATTEN with GENVAR
    // ========================================================================
    genvar i;
    generate
        for (i = 0; i < BRAM_COUNT; i = i + 1) begin : WR_DATA_FLATTEN
            assign bram_wr_data_flat[i*DATA_WIDTH +: DATA_WIDTH] = demux_out[i];
        end
    endgenerate
    
    assign bram_wr_addr = wr_counter[ADDR_WIDTH-1:0];
    assign bram_wr_en = (16'b1 << demux_sel) & {16{wr_counter_enable}};
    
    // ========================================================================
    // BRAM Read Interface - UNFLATTEN with GENVAR
    // ========================================================================
    generate
        for (i = 0; i < 8; i = i + 1) begin : RD_DATA_UNFLATTEN
            assign bram_dout[i] = bram_rd_data_flat[i*DATA_WIDTH +: DATA_WIDTH];
        end
    endgenerate
    
    assign bram_rd_addr = rd_counter[ADDR_WIDTH-1:0];

endmodule