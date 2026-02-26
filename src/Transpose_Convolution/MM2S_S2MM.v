`timescale 1ns / 1ps
// MM2S and S2MM FIFO Module
// Verilog-2001 (IEEE 1364-2001) — NO SystemVerilog constructs
//
// FIX: Added ENABLE_S2MM parameter.
// ENABLE_S2MM=0  → S2MM FIFO not instantiated; s2mm_tready tied HIGH,
//                  m_axis outputs tied LOW. Eliminates RTSTAT #1 warning
//                  (133 unroutable doutb nets) in write-only wrappers.
// ENABLE_S2MM=1  → Normal operation, identical to original.

module MM2S_S2MM #(
    parameter FIFO_DEPTH  = 512,
    parameter DATA_WIDTH  = 20,
    parameter ENABLE_S2MM = 1,
    parameter TKEEP_WIDTH = (DATA_WIDTH + 7) / 8   // ceiling(DATA_WIDTH/8) //ok
)
(
    input  wire                    aclk,
    input  wire                    aresetn,

    // MM2S - Slave AXI Stream Input
    output wire                    s_axis_tready,
    input  wire [DATA_WIDTH-1:0]   s_axis_tdata,
    input  wire                    s_axis_tvalid,
    input  wire                    s_axis_tlast,

    // MM2S - Master Output to Processing
    input  wire                    mm2s_tready,
    output wire [DATA_WIDTH-1:0]   mm2s_tdata,
    output wire                    mm2s_tvalid,
    output wire                    mm2s_tlast,
    output wire [9:0]              mm2s_data_count,

    // S2MM - Slave Input from Processing
    output wire                    s2mm_tready,
    input  wire [DATA_WIDTH-1:0]   s2mm_tdata,
    input  wire                    s2mm_tvalid,
    input  wire                    s2mm_tlast,

    // S2MM - Master AXI Stream Output
    input  wire                    m_axis_tready,
    output wire [DATA_WIDTH-1:0]   m_axis_tdata,
    output wire [TKEEP_WIDTH-1:0]  m_axis_tkeep,
    output wire                    m_axis_tvalid,
    output wire                    m_axis_tlast
);

    // =========================================================================
    // MM2S FIFO — Always present
    // =========================================================================
    xpm_fifo_axis #(
        .CDC_SYNC_STAGES    (2),
        .CLOCKING_MODE      ("common_clock"),
        .ECC_MODE           ("no_ecc"),
        .FIFO_DEPTH         (FIFO_DEPTH),
        .FIFO_MEMORY_TYPE   ("auto"),
        .PACKET_FIFO        ("false"),
        .PROG_EMPTY_THRESH  (10),
        .PROG_FULL_THRESH   (10),
        .RD_DATA_COUNT_WIDTH(1),
        .RELATED_CLOCKS     (0),
        .SIM_ASSERT_CHK     (0),
        .TDATA_WIDTH        (DATA_WIDTH),
        .TDEST_WIDTH        (1),
        .TID_WIDTH          (1),
        .TUSER_WIDTH        (1),
        .USE_ADV_FEATURES   ("0004"),
        .WR_DATA_COUNT_WIDTH(10)
    ) xpm_fifo_axis_mm2s (
        .almost_empty_axis  (),
        .almost_full_axis   (),
        .dbiterr_axis       (),
        .prog_empty_axis    (),
        .prog_full_axis     (),
        .rd_data_count_axis (),
        .sbiterr_axis       (),
        .injectdbiterr_axis (1'b0),
        .injectsbiterr_axis (1'b0),
        .s_aclk             (aclk),
        .m_aclk             (aclk),
        .s_aresetn          (aresetn),
        .s_axis_tready      (s_axis_tready),
        .s_axis_tdata       (s_axis_tdata),
        .s_axis_tvalid      (s_axis_tvalid),
        .s_axis_tdest       (1'b0),
        .s_axis_tid         (1'b0),
        .s_axis_tkeep       ({TKEEP_WIDTH{1'b1}}),
        .s_axis_tlast       (s_axis_tlast),
        .s_axis_tstrb       ({TKEEP_WIDTH{1'b1}}),
        .s_axis_tuser       (1'b0),
        .m_axis_tready      (mm2s_tready),
        .m_axis_tdata       (mm2s_tdata),
        .m_axis_tvalid      (mm2s_tvalid),
        .m_axis_tdest       (),
        .m_axis_tid         (),
        .m_axis_tkeep       (),
        .m_axis_tlast       (mm2s_tlast),
        .m_axis_tstrb       (),
        .m_axis_tuser       (),
        .wr_data_count_axis (mm2s_data_count)
    );

    // =========================================================================
    // S2MM FIFO — Conditionally instantiated (Verilog-2001 generate/if)
    //
    // assign inside a generate-else branch driving module output ports is
    // legal per IEEE 1364-2001 Section 12.1.3 and accepted by Vivado,
    // Quartus, and VCS when the file is compiled as Verilog (not SV).
    // =========================================================================
    generate
        if (ENABLE_S2MM == 1) begin : gen_s2mm_on

            xpm_fifo_axis #(
                .CDC_SYNC_STAGES    (2),
                .CLOCKING_MODE      ("common_clock"),
                .ECC_MODE           ("no_ecc"),
                .FIFO_DEPTH         (FIFO_DEPTH),
                .FIFO_MEMORY_TYPE   ("auto"),
                .PACKET_FIFO        ("false"),
                .PROG_EMPTY_THRESH  (10),
                .PROG_FULL_THRESH   (10),
                .RD_DATA_COUNT_WIDTH(1),
                .RELATED_CLOCKS     (0),
                .SIM_ASSERT_CHK     (0),
                .TDATA_WIDTH        (DATA_WIDTH),
                .TDEST_WIDTH        (1),
                .TID_WIDTH          (1),
                .TUSER_WIDTH        (1),
                .USE_ADV_FEATURES   ("0000"),
                .WR_DATA_COUNT_WIDTH(1)
            ) xpm_fifo_axis_s2mm (
                .almost_empty_axis  (),
                .almost_full_axis   (),
                .dbiterr_axis       (),
                .prog_empty_axis    (),
                .prog_full_axis     (),
                .rd_data_count_axis (),
                .sbiterr_axis       (),
                .injectdbiterr_axis (1'b0),
                .injectsbiterr_axis (1'b0),
                .s_aclk             (aclk),
                .m_aclk             (aclk),
                .s_aresetn          (aresetn),
                .s_axis_tready      (s2mm_tready),
                .s_axis_tdata       (s2mm_tdata),
                .s_axis_tvalid      (s2mm_tvalid),
                .s_axis_tdest       (1'b0),
                .s_axis_tid         (1'b0),
                .s_axis_tkeep       ({TKEEP_WIDTH{1'b1}}),
                .s_axis_tlast       (s2mm_tlast),
                .s_axis_tstrb       ({TKEEP_WIDTH{1'b1}}),
                .s_axis_tuser       (1'b0),
                .m_axis_tready      (m_axis_tready),
                .m_axis_tdata       (m_axis_tdata),
                .m_axis_tvalid      (m_axis_tvalid),
                .m_axis_tdest       (),
                .m_axis_tid         (),
                .m_axis_tkeep       (m_axis_tkeep),
                .m_axis_tlast       (m_axis_tlast),
                .m_axis_tstrb       (),
                .m_axis_tuser       (),
                .wr_data_count_axis ()
            );

        end else begin : gen_s2mm_off
            // Write-only mode: no FIFO, no BRAM, no doutb nets.
            assign s2mm_tready   = 1'b1;
            assign m_axis_tdata  = {DATA_WIDTH{1'b0}};
            assign m_axis_tkeep  = {TKEEP_WIDTH{1'b0}};
            assign m_axis_tvalid = 1'b0;
            assign m_axis_tlast  = 1'b0;
        end
    endgenerate

endmodule