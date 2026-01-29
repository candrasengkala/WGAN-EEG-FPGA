`timescale 1ns / 1ps
// Top Module untuk Integrasi axis_custom, axis_counter, demux1to32, mux16to1
// Hanya instantiation, semua control dari FSM eksternal

`include "xpm_fifo_axis.v"
`include "axis_custom.v"
`include "axis_counter.v"
`include "parser64bit.v"
`include "packed64bit.v"
`include "demux1to32.v"
`include "mux16to1.v"


module axis_top #(
    parameter DATA_WIDTH = 16
)(
    input wire         aclk,
    input wire         aresetn,
    
    // *** AXI Stream Slave Port ***
    output wire        s_axis_tready,
    input wire [63:0]  s_axis_tdata,
    input wire         s_axis_tvalid,
    input wire         s_axis_tlast,
    
    // *** AXI Stream Master Port ***
    input wire         m_axis_tready,
    output wire [63:0] m_axis_tdata,
    output wire        m_axis_tvalid,
    output wire        m_axis_tlast,
    
    // *** MM2S FIFO Interface ***
    output wire [7:0]  mm2s_count,
    
    // *** BRAM Write Control (dari parser, untuk FSM) ***
    output wire        bram_wr_enable,    // Assert saat parser output valid data
    
    // *** BRAM Read Control (untuk trigger packer) ***
    input wire         bram_rd_enable,    // FSM assert untuk read BRAM ke packer
    
    // *** Write Counter Control (dari FSM eksternal) ***
    input wire         wr_counter_enable,
    input wire         wr_counter_start,
    input wire [15:0]  wr_start_addr,
    input wire [15:0]  wr_count_limit,
    output wire [15:0] wr_counter,
    output wire        wr_counter_done,
    
    // *** Read Counter Control (dari FSM eksternal) ***
    input wire         rd_counter_enable,
    input wire         rd_counter_start,
    input wire [15:0]  rd_start_addr,
    input wire [15:0]  rd_count_limit,
    output wire [15:0] rd_counter,
    output wire        rd_counter_done,
    
    // *** DEMUX Control (dari FSM eksternal) ***
    input wire [4:0]   demux_sel,
    output wire [DATA_WIDTH-1:0] demux_out_0,
    output wire [DATA_WIDTH-1:0] demux_out_1,
    output wire [DATA_WIDTH-1:0] demux_out_2,
    output wire [DATA_WIDTH-1:0] demux_out_3,
    output wire [DATA_WIDTH-1:0] demux_out_4,
    output wire [DATA_WIDTH-1:0] demux_out_5,
    output wire [DATA_WIDTH-1:0] demux_out_6,
    output wire [DATA_WIDTH-1:0] demux_out_7,
    output wire [DATA_WIDTH-1:0] demux_out_8,
    output wire [DATA_WIDTH-1:0] demux_out_9,
    output wire [DATA_WIDTH-1:0] demux_out_10,
    output wire [DATA_WIDTH-1:0] demux_out_11,
    output wire [DATA_WIDTH-1:0] demux_out_12,
    output wire [DATA_WIDTH-1:0] demux_out_13,
    output wire [DATA_WIDTH-1:0] demux_out_14,
    output wire [DATA_WIDTH-1:0] demux_out_15,
    output wire [DATA_WIDTH-1:0] demux_out_16,
    output wire [DATA_WIDTH-1:0] demux_out_17,
    output wire [DATA_WIDTH-1:0] demux_out_18,
    output wire [DATA_WIDTH-1:0] demux_out_19,
    output wire [DATA_WIDTH-1:0] demux_out_20,
    output wire [DATA_WIDTH-1:0] demux_out_21,
    output wire [DATA_WIDTH-1:0] demux_out_22,
    output wire [DATA_WIDTH-1:0] demux_out_23,
    output wire [DATA_WIDTH-1:0] demux_out_24,
    output wire [DATA_WIDTH-1:0] demux_out_25,
    output wire [DATA_WIDTH-1:0] demux_out_26,
    output wire [DATA_WIDTH-1:0] demux_out_27,
    output wire [DATA_WIDTH-1:0] demux_out_28,
    output wire [DATA_WIDTH-1:0] demux_out_29,
    output wire [DATA_WIDTH-1:0] demux_out_30,
    output wire [DATA_WIDTH-1:0] demux_out_31,
    
    // *** MUX Control (dari FSM eksternal) ***
    input wire [3:0]   mux_sel,
    input wire [DATA_WIDTH-1:0] mux_in_0,
    input wire [DATA_WIDTH-1:0] mux_in_1,
    input wire [DATA_WIDTH-1:0] mux_in_2,
    input wire [DATA_WIDTH-1:0] mux_in_3,
    input wire [DATA_WIDTH-1:0] mux_in_4,
    input wire [DATA_WIDTH-1:0] mux_in_5,
    input wire [DATA_WIDTH-1:0] mux_in_6,
    input wire [DATA_WIDTH-1:0] mux_in_7,
    input wire [DATA_WIDTH-1:0] mux_in_8,
    input wire [DATA_WIDTH-1:0] mux_in_9,
    input wire [DATA_WIDTH-1:0] mux_in_10,
    input wire [DATA_WIDTH-1:0] mux_in_11,
    input wire [DATA_WIDTH-1:0] mux_in_12,
    input wire [DATA_WIDTH-1:0] mux_in_13,
    input wire [DATA_WIDTH-1:0] mux_in_14,
    input wire [DATA_WIDTH-1:0] mux_in_15,
    output wire [DATA_WIDTH-1:0] mux_out
);

    // ============================================================================
    // Internal Wires
    // ============================================================================
    
    // MM2S FIFO to Parser
    wire [63:0] mm2s_data;
    wire        mm2s_valid;
    wire        mm2s_ready;
    
    // Parser to DEMUX
    wire [15:0] parser_data_out;
    wire        parser_data_valid;
    
    // Packer to S2MM FIFO
    wire [63:0] s2mm_data;
    wire        s2mm_valid;
    wire        s2mm_ready;
    wire        s2mm_last;
    
    // Internal Control
    assign bram_wr_enable = parser_data_valid;    // Expose parser valid ke FSM
    
    // ============================================================================
    // Module Instantiations
    // ============================================================================
    
    // AXI Stream Custom Module
    axis_custom axis_stream_inst (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tready(s_axis_tready),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tlast(s_axis_tlast),
        .m_axis_tready(m_axis_tready),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tlast(m_axis_tlast),
        .mm2s_data(mm2s_data),
        .mm2s_valid(mm2s_valid),
        .mm2s_ready(mm2s_ready),
        .mm2s_count(mm2s_count),
        .s2mm_data(s2mm_data),
        .s2mm_valid(s2mm_valid),
        .s2mm_ready(s2mm_ready),
        .s2mm_last(s2mm_last)
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
    
    // Parser 64-bit to 4x16-bit (automatic consumption dari MM2S FIFO)
    parser64bit parser_inst (
        .aclk(aclk),
        .aresetn(aresetn),
        .data_in(mm2s_data),
        .data_in_valid(mm2s_valid),
        .data_in_ready(mm2s_ready),
        .data_out(parser_data_out),
        .data_out_valid(parser_data_valid),
        .data_out_ready(1'b1),  // Selalu ready
        .word_index()
    );
    
    // DEMUX 1-to-32
    demux1to32 #(
        .DATA_WIDTH(DATA_WIDTH)
    ) demux_inst (
        .data_in(parser_data_out),
        .sel(demux_sel),
        .out_0(demux_out_0),
        .out_1(demux_out_1),
        .out_2(demux_out_2),
        .out_3(demux_out_3),
        .out_4(demux_out_4),
        .out_5(demux_out_5),
        .out_6(demux_out_6),
        .out_7(demux_out_7),
        .out_8(demux_out_8),
        .out_9(demux_out_9),
        .out_10(demux_out_10),
        .out_11(demux_out_11),
        .out_12(demux_out_12),
        .out_13(demux_out_13),
        .out_14(demux_out_14),
        .out_15(demux_out_15),
        .out_16(demux_out_16),
        .out_17(demux_out_17),
        .out_18(demux_out_18),
        .out_19(demux_out_19),
        .out_20(demux_out_20),
        .out_21(demux_out_21),
        .out_22(demux_out_22),
        .out_23(demux_out_23),
        .out_24(demux_out_24),
        .out_25(demux_out_25),
        .out_26(demux_out_26),
        .out_27(demux_out_27),
        .out_28(demux_out_28),
        .out_29(demux_out_29),
        .out_30(demux_out_30),
        .out_31(demux_out_31)
    );
    
    // MUX 16-to-1
    mux16to1 #(
        .DATA_WIDTH(DATA_WIDTH)
    ) mux_inst (
        .in_0(mux_in_0),
        .in_1(mux_in_1),
        .in_2(mux_in_2),
        .in_3(mux_in_3),
        .in_4(mux_in_4),
        .in_5(mux_in_5),
        .in_6(mux_in_6),
        .in_7(mux_in_7),
        .in_8(mux_in_8),
        .in_9(mux_in_9),
        .in_10(mux_in_10),
        .in_11(mux_in_11),
        .in_12(mux_in_12),
        .in_13(mux_in_13),
        .in_14(mux_in_14),
        .in_15(mux_in_15),
        .sel(mux_sel),
        .data_out(mux_out)
    );
    
    // Packer 4x16-bit to 64-bit (automatic output ke S2MM FIFO)
    packed64bit packer_inst (
        .aclk(aclk),
        .aresetn(aresetn),
        .data_in(mux_out),
        .data_in_valid(bram_rd_enable),
        .data_in_ready(),  
        .data_out(s2mm_data),
        .data_out_valid(s2mm_valid),
        .data_out_ready(s2mm_ready),
        .word_index()
    );
    
    // S2MM TLAST generation: assert every 4th write (automatic)
    reg [1:0] s2mm_word_count;
    always @(posedge aclk) begin
        if (!aresetn)
            s2mm_word_count <= 2'b00;
        else if (s2mm_valid && s2mm_ready)
            s2mm_word_count <= s2mm_word_count + 1;
    end
    assign s2mm_last = s2mm_valid && (s2mm_word_count == 2'b11);

endmodule

