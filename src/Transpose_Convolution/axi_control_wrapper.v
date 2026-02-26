`timescale 1ns / 1ps
`include "axi_header_parser.v"
`include "axis_custom_top.v"

// axi_control_wrapper.v
// Verilog-2001 (IEEE 1364-2001) -- NO SystemVerilog constructs
//
// FIX: Added ENABLE_S2MM parameter (default 1).
// Set ENABLE_S2MM=0 when instantiating as write-only (e.g. bias_wrapper)
// to suppress S2MM FIFO and eliminate Vivado RTSTAT #1 warning.

module axis_control_wrapper #(
    parameter BRAM_DEPTH  = 512,
    parameter DATA_WIDTH  = 16,
    parameter BRAM_COUNT  = 16,
    parameter ADDR_WIDTH  = 9,
    parameter ENABLE_S2MM = 1
)(
    // System
    input  wire                              aclk,
    input  wire                              aresetn,

    // AXI Stream Slave (From DMA)
    input  wire [DATA_WIDTH-1:0]             s_axis_tdata,
    input  wire                              s_axis_tvalid,
    output wire                              s_axis_tready,
    input  wire                              s_axis_tlast,

    // AXI Stream Master (To DMA)
    output wire [DATA_WIDTH-1:0]             m_axis_tdata,
    output wire [(DATA_WIDTH+7)/8-1:0]       m_axis_tkeep,
    output wire                              m_axis_tvalid,
    input  wire                              m_axis_tready,
    output wire                              m_axis_tlast,

    // Status
    output wire                              write_done,
    output wire                              read_done,
    output wire [9:0]                        mm2s_data_count,

    // Debug
    output wire [2:0]                        parser_state,
    output wire                              error_invalid_magic,

    // BRAM Write Port
    output wire [BRAM_COUNT*DATA_WIDTH-1:0]  bram_wr_data_flat,
    output wire [ADDR_WIDTH-1:0]             bram_wr_addr,
    output wire [BRAM_COUNT-1:0]             bram_wr_en,

    // BRAM Read Port
    input  wire [8*DATA_WIDTH-1:0]           bram_rd_data_flat,
    output wire [ADDR_WIDTH-1:0]             bram_rd_addr,

    // Output Manager Control
    input  wire [15:0]                       header_word_0,
    input  wire [15:0]                       header_word_1,
    input  wire [15:0]                       header_word_2,
    input  wire [15:0]                       header_word_3,
    input  wire [15:0]                       header_word_4,
    input  wire [15:0]                       header_word_5,
    input  wire                              send_header,
    input  wire [2:0]                        out_mgr_rd_bram_start,
    input  wire [2:0]                        out_mgr_rd_bram_end,
    input  wire [15:0]                       out_mgr_rd_addr_count,
    input  wire                              notification_mode
);

    // Internal wires
    wire [7:0]   instruction_code;
    wire [4:0]   wr_bram_start, wr_bram_end;
    wire [15:0]  wr_addr_start, wr_addr_count;
    wire [2:0]   rd_bram_start, rd_bram_end;
    wire [15:0]  rd_addr_start, rd_addr_count;
    wire         header_valid;

    wire [DATA_WIDTH-1:0] parser_tdata;
    wire                  parser_tvalid;
    wire                  parser_tready;
    wire                  parser_tlast;

    reg  [7:0]  instruction_code_reg;
    reg  [4:0]  wr_bram_start_reg, wr_bram_end_reg;
    reg  [15:0] wr_addr_start_reg, wr_addr_count_reg;
    reg  [2:0]  rd_bram_start_reg, rd_bram_end_reg;
    reg  [15:0] rd_addr_start_reg, rd_addr_count_reg;

    // ========================================================================
    // AXI Header Parser
    // ========================================================================
    axi_header_parser #(
        .DATA_WIDTH(DATA_WIDTH)
    ) parser_inst (
        .aclk                (aclk),
        .aresetn             (aresetn),
        .s_axis_tdata        (s_axis_tdata),
        .s_axis_tvalid       (s_axis_tvalid),
        .s_axis_tready       (s_axis_tready),
        .s_axis_tlast        (s_axis_tlast),
        .m_axis_tdata        (parser_tdata),
        .m_axis_tvalid       (parser_tvalid),
        .m_axis_tready       (parser_tready),
        .m_axis_tlast        (parser_tlast),
        .instruction_code    (instruction_code),
        .bram_start          (wr_bram_start),
        .bram_end            (wr_bram_end),
        .addr_start          (wr_addr_start),
        .addr_count          (wr_addr_count),
        .header_valid        (header_valid),
        .error_invalid_magic (error_invalid_magic),
        .parser_state_debug  (parser_state)
    );

    // ========================================================================
    // Parameter Mux
    // ========================================================================
    assign rd_bram_start = send_header ? out_mgr_rd_bram_start : wr_bram_start[2:0];
    assign rd_bram_end   = send_header ? out_mgr_rd_bram_end   : wr_bram_end[2:0];
    assign rd_addr_start = send_header ? 16'd0                 : wr_addr_start;
    assign rd_addr_count = send_header ? out_mgr_rd_addr_count : wr_addr_count;

    // ========================================================================
    // Control Registers
    // ========================================================================
    always @(posedge aclk) begin
        if (!aresetn) begin
            instruction_code_reg <= 8'b0;
            wr_bram_start_reg    <= 5'b0;
            wr_bram_end_reg      <= 5'b0;
            wr_addr_start_reg    <= 16'b0;
            wr_addr_count_reg    <= 16'b0;
            rd_bram_start_reg    <= 3'b0;
            rd_bram_end_reg      <= 3'b0;
            rd_addr_start_reg    <= 16'b0;
            rd_addr_count_reg    <= 16'b0;
        end
        else if (write_done || read_done) begin
            instruction_code_reg <= 8'b0;
        end
        else if (header_valid) begin
            instruction_code_reg <= instruction_code;
            wr_bram_start_reg    <= wr_bram_start;
            wr_bram_end_reg      <= wr_bram_end;
            wr_addr_start_reg    <= wr_addr_start;
            wr_addr_count_reg    <= wr_addr_count;
            rd_bram_start_reg    <= rd_bram_start;
            rd_bram_end_reg      <= rd_bram_end;
            rd_addr_start_reg    <= rd_addr_start;
            rd_addr_count_reg    <= rd_addr_count;
        end
    end

    // ========================================================================
    // axis_custom_top -- ENABLE_S2MM propagated
    // ========================================================================
    axis_custom_top #(
        .BRAM_DEPTH  (BRAM_DEPTH),
        .DATA_WIDTH  (DATA_WIDTH),
        .BRAM_COUNT  (BRAM_COUNT),
        .ADDR_WIDTH  (ADDR_WIDTH),
        .ENABLE_S2MM (ENABLE_S2MM)
    ) axis_top_inst (
        .aclk             (aclk),
        .aresetn          (aresetn),
        .s_axis_tdata     (parser_tdata),
        .s_axis_tvalid    (parser_tvalid),
        .s_axis_tready    (parser_tready),
        .s_axis_tlast     (parser_tlast),
        .m_axis_tdata     (m_axis_tdata),
        .m_axis_tkeep     (m_axis_tkeep),
        .m_axis_tvalid    (m_axis_tvalid),
        .m_axis_tready    (m_axis_tready),
        .m_axis_tlast     (m_axis_tlast),
        .Instruction_code (instruction_code_reg),
        .wr_bram_start    (wr_bram_start_reg),
        .wr_bram_end      (wr_bram_end_reg),
        .wr_addr_start    (wr_addr_start_reg),
        .wr_addr_count    (wr_addr_count_reg),
        .rd_bram_start    (send_header ? out_mgr_rd_bram_start : rd_bram_start_reg),
        .rd_bram_end      (send_header ? out_mgr_rd_bram_end   : rd_bram_end_reg),
        .rd_addr_start    (rd_addr_start_reg),
        .rd_addr_count    (send_header ? out_mgr_rd_addr_count : rd_addr_count_reg),
        .header_word_0    (header_word_0),
        .header_word_1    (header_word_1),
        .header_word_2    (header_word_2),
        .header_word_3    (header_word_3),
        .header_word_4    (header_word_4),
        .header_word_5    (header_word_5),
        .send_header      (send_header),
        .notification_only(notification_mode),
        .write_done       (write_done),
        .read_done        (read_done),
        .mm2s_data_count  (mm2s_data_count),
        .bram_wr_data_flat(bram_wr_data_flat),
        .bram_wr_addr     (bram_wr_addr),
        .bram_wr_en       (bram_wr_en),
        .bram_rd_data_flat(bram_rd_data_flat),
        .bram_rd_addr     (bram_rd_addr)
    );

endmodule