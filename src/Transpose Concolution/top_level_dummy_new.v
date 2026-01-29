`timescale 1ns / 1ps
`include "blk_mem_gen_dual_port.v"
`include "axis_top.v"
`include "External_FSM_AXI.v"

module top_level_dummy (
    input wire aclk,
    input wire aresetn,
    input wire [63:0] s_axis_tdata,
    input wire s_axis_tvalid,
    input wire s_axis_tlast,
    output wire s_axis_tready,
    output wire [63:0] m_axis_tdata,
    output wire m_axis_tvalid,
    output wire m_axis_tlast,
    input wire m_axis_tready,
    input wire [7:0] instruction_code,
    input wire [4:0] wr_bram_start,
    input wire [4:0] wr_bram_end,
    input wire [15:0] wr_addr_start,
    input wire [15:0] wr_addr_count,
    input wire [3:0] rd_bram_start,
    input wire [3:0] rd_bram_end,
    input wire [15:0] rd_addr_start,
    input wire [15:0] rd_addr_count
);

    wire [7:0] mm2s_count;
    wire bram_wr_enable;
    wire bram_rd_enable;
    wire wr_counter_enable;
    wire wr_counter_start;
    wire [15:0] wr_start_addr_out;
    wire [15:0] wr_count_limit;
    wire [15:0] wr_counter;
    wire wr_counter_done;
    wire rd_counter_enable;
    wire rd_counter_start;
    wire [15:0] rd_start_addr_out;
    wire [15:0] rd_count_limit;
    wire [15:0] rd_counter;
    wire rd_counter_done;
    wire [4:0] demux_sel;
    wire [3:0] mux_sel;
    wire [15:0] demux_out_0;
    wire [15:0] demux_out_1;
    wire [15:0] demux_out_2;
    wire [15:0] demux_out_3;
    wire [15:0] demux_out_4;
    wire [15:0] demux_out_5;
    wire [15:0] demux_out_6;
    wire [15:0] demux_out_7;
    wire [15:0] demux_out_8;
    wire [15:0] demux_out_9;
    wire [15:0] demux_out_10;
    wire [15:0] demux_out_11;
    wire [15:0] demux_out_12;
    wire [15:0] demux_out_13;
    wire [15:0] demux_out_14;
    wire [15:0] demux_out_15;
    wire [15:0] demux_out_16;
    wire [15:0] demux_out_17;
    wire [15:0] demux_out_18;
    wire [15:0] demux_out_19;
    wire [15:0] demux_out_20;
    wire [15:0] demux_out_21;
    wire [15:0] demux_out_22;
    wire [15:0] demux_out_23;
    wire [15:0] demux_out_24;
    wire [15:0] demux_out_25;
    wire [15:0] demux_out_26;
    wire [15:0] demux_out_27;
    wire [15:0] demux_out_28;
    wire [15:0] demux_out_29;
    wire [15:0] demux_out_30;
    wire [15:0] demux_out_31;
    wire [15:0] mux_in_0;
    wire [15:0] mux_in_1;
    wire [15:0] mux_in_2;
    wire [15:0] mux_in_3;
    wire [15:0] mux_in_4;
    wire [15:0] mux_in_5;
    wire [15:0] mux_in_6;
    wire [15:0] mux_in_7;
    wire [15:0] mux_in_8;
    wire [15:0] mux_in_9;
    wire [15:0] mux_in_10;
    wire [15:0] mux_in_11;
    wire [15:0] mux_in_12;
    wire [15:0] mux_in_13;
    wire [15:0] mux_in_14;
    wire [15:0] mux_in_15;
    wire [15:0] bram_dout_0;
    wire [15:0] bram_dout_1;
    wire [15:0] bram_dout_2;
    wire [15:0] bram_dout_3;
    wire [15:0] mux_out;

    axis_top axis_top_inst (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tlast(s_axis_tlast),
        .s_axis_tready(s_axis_tready),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tlast(m_axis_tlast),
        .m_axis_tready(m_axis_tready),
        .mm2s_count(mm2s_count),
        .bram_wr_enable(bram_wr_enable),
        .bram_rd_enable(bram_rd_enable),
        .wr_counter_enable(wr_counter_enable),
        .wr_counter_start(wr_counter_start),
        .wr_start_addr(wr_addr_start),
        .wr_count_limit(wr_addr_count),
        .wr_counter(wr_counter),
        .wr_counter_done(wr_counter_done),
        .rd_counter_enable(rd_counter_enable),
        .rd_counter_start(rd_counter_start),
        .rd_start_addr(rd_addr_start),
        .rd_count_limit(rd_addr_count),
        .rd_counter(rd_counter),
        .rd_counter_done(rd_counter_done),
        .demux_sel(demux_sel),
        .mux_sel(mux_sel),
        .demux_out_0(demux_out_0),
        .demux_out_1(demux_out_1),
        .demux_out_2(demux_out_2),
        .demux_out_3(demux_out_3),
        .demux_out_4(demux_out_4),
        .demux_out_5(demux_out_5),
        .demux_out_6(demux_out_6),
        .demux_out_7(demux_out_7),
        .demux_out_8(demux_out_8),
        .demux_out_9(demux_out_9),
        .demux_out_10(demux_out_10),
        .demux_out_11(demux_out_11),
        .demux_out_12(demux_out_12),
        .demux_out_13(demux_out_13),
        .demux_out_14(demux_out_14),
        .demux_out_15(demux_out_15),
        .demux_out_16(demux_out_16),
        .demux_out_17(demux_out_17),
        .demux_out_18(demux_out_18),
        .demux_out_19(demux_out_19),
        .demux_out_20(demux_out_20),
        .demux_out_21(demux_out_21),
        .demux_out_22(demux_out_22),
        .demux_out_23(demux_out_23),
        .demux_out_24(demux_out_24),
        .demux_out_25(demux_out_25),
        .demux_out_26(demux_out_26),
        .demux_out_27(demux_out_27),
        .demux_out_28(demux_out_28),
        .demux_out_29(demux_out_29),
        .demux_out_30(demux_out_30),
        .demux_out_31(demux_out_31),
        .mux_in_0(mux_in_0),
        .mux_in_1(mux_in_1),
        .mux_in_2(mux_in_2),
        .mux_in_3(mux_in_3),
        .mux_in_4(mux_in_4),
        .mux_in_5(mux_in_5),
        .mux_in_6(mux_in_6),
        .mux_in_7(mux_in_7),
        .mux_in_8(mux_in_8),
        .mux_in_9(mux_in_9),
        .mux_in_10(mux_in_10),
        .mux_in_11(mux_in_11),
        .mux_in_12(mux_in_12),
        .mux_in_13(mux_in_13),
        .mux_in_14(mux_in_14),
        .mux_in_15(mux_in_15),
        .mux_out(mux_out)
    );

    External_FSM_AXI fsm_inst (
        .aclk(aclk),
        .aresetn(aresetn),
        .Instruction_code(instruction_code),
        .wr_bram_start(wr_bram_start),
        .wr_bram_end(wr_bram_end),
        .wr_addr_start(wr_addr_start),
        .wr_addr_count(wr_addr_count),
        .rd_bram_start(rd_bram_start),
        .rd_bram_end(rd_bram_end),
        .rd_addr_start(rd_addr_start),
        .rd_addr_count(rd_addr_count),
        .bram_wr_enable(bram_wr_enable),
        .wr_counter_enable(wr_counter_enable),
        .wr_counter_start(wr_counter_start),
        .wr_start_addr(wr_start_addr_out),
        .wr_count_limit(wr_count_limit),
        .wr_counter_done(wr_counter_done),
        .rd_counter_enable(rd_counter_enable),
        .rd_counter_start(rd_counter_start),
        .rd_start_addr(rd_start_addr_out),
        .rd_count_limit(rd_count_limit),
        .rd_counter_done(rd_counter_done),
        .demux_sel(demux_sel),
        .mux_sel(mux_sel),
        .bram_rd_enable(bram_rd_enable)
    );

    blk_mem_gen_dual_port #(
        .ADDR_WIDTH(9),
        .DATA_WIDTH(16)
    ) bram_inst_0 (
        .clka(aclk),
        .ena(bram_wr_enable && (demux_sel == 5'd0)),
        .wea(bram_wr_enable && (demux_sel == 5'd0)),
        .addra(wr_counter[8:0]),
        .dina(demux_out_0),
        .clkb(aclk),
        .enb(bram_rd_enable && (mux_sel == 4'd0)),
        .addrb(rd_counter[8:0]),
        .doutb(bram_dout_0)
    );

    blk_mem_gen_dual_port #(
        .ADDR_WIDTH(9),
        .DATA_WIDTH(16)
    ) bram_inst_1 (
        .clka(aclk),
        .ena(bram_wr_enable && (demux_sel == 5'd1)),
        .wea(bram_wr_enable && (demux_sel == 5'd1)),
        .addra(wr_counter[8:0]),
        .dina(demux_out_1),
        .clkb(aclk),
        .enb(bram_rd_enable && (mux_sel == 4'd1)),
        .addrb(rd_counter[8:0]),
        .doutb(bram_dout_1)
    );

    blk_mem_gen_dual_port #(
        .ADDR_WIDTH(9),
        .DATA_WIDTH(16)
    ) bram_inst_2 (
        .clka(aclk),
        .ena(bram_wr_enable && (demux_sel == 5'd2)),
        .wea(bram_wr_enable && (demux_sel == 5'd2)),
        .addra(wr_counter[8:0]),
        .dina(demux_out_2),
        .clkb(aclk),
        .enb(bram_rd_enable && (mux_sel == 4'd2)),
        .addrb(rd_counter[8:0]),
        .doutb(bram_dout_2)
    );

    blk_mem_gen_dual_port #(
        .ADDR_WIDTH(9),
        .DATA_WIDTH(16)
    ) bram_inst_3 (
        .clka(aclk),
        .ena(bram_wr_enable && (demux_sel == 5'd3)),
        .wea(bram_wr_enable && (demux_sel == 5'd3)),
        .addra(wr_counter[8:0]),
        .dina(demux_out_3),
        .clkb(aclk),
        .enb(bram_rd_enable && (mux_sel == 4'd3)),
        .addrb(rd_counter[8:0]),
        .doutb(bram_dout_3)
    );

    assign mux_in_0 = bram_dout_0;
    assign mux_in_1 = bram_dout_1;
    assign mux_in_2 = bram_dout_2;
    assign mux_in_3 = bram_dout_3;
    assign mux_in_4 = 16'd0;
    assign mux_in_5 = 16'd0;
    assign mux_in_6 = 16'd0;
    assign mux_in_7 = 16'd0;
    assign mux_in_8 = 16'd0;
    assign mux_in_9 = 16'd0;
    assign mux_in_10 = 16'd0;
    assign mux_in_11 = 16'd0;
    assign mux_in_12 = 16'd0;
    assign mux_in_13 = 16'd0;
    assign mux_in_14 = 16'd0;
    assign mux_in_15 = 16'd0;

endmodule