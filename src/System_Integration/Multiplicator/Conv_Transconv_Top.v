`timescale 1ns / 1ps

/******************************************************************************
 * Module: Conv_Transconv_Top
 *
 * Description:
 * Top-level integration module for unified convolution compute path.
 * Supports both Normal Convolution (1DCONV) and Transposed Convolution modes.
 * Integrates:
 *   - Onedconv_Buffers: Data buffering for 1DCONV mode
 *   - Unified_Multiplicator: Systolic array with control MUX
 *
 * Mode Selection:
 *   - conv_mode = 0: Normal Convolution (1DCONV)
 *   - conv_mode = 1: Transposed Convolution (TRANSCONV)
 *
 * Author: Rizmi Ahmad Raihan
 ******************************************************************************/

module Conv_Transconv_Top #(
    parameter DW         = 16,  // Data width
    parameter Dimension  = 16,  // Array dimension
    parameter Depth_added = 17  // Buffer depth for 1DCONV
)(
    input  wire                              clk,
    input  wire                              rst_n,
    input  wire                              conv_mode,
    input  wire                              rst_top,
    // ============================================================
    // DATA INPUTS (TRANSCONV - Direct to Systolic Array)
    // ============================================================
    input  wire signed [DW*Dimension-1:0]    weight_in,
    input  wire signed [DW*Dimension-1:0]    ifmap_in,

    // ============================================================
    // DATA INPUTS (1DCONV - Through Buffers)
    // ============================================================
    input  wire signed [Dimension*DW-1:0]    weight_brams_in,
    input  wire signed [DW-1:0]              ifmap_serial_in,
    input  wire                              conv_zero_or_data,
    input  wire                              conv_zero_or_data_weight,

    // ============================================================
    // CONTROL INPUTS (1DCONV BUFFERS)
    // Per-register enables for staggered shifting (matches Onedconv_Buffers)
    // ============================================================
    input  wire [Dimension-1:0]              en_shift_reg_ifmap_muxed,
    input  wire [Dimension-1:0]              en_shift_reg_weight_muxed,

    // ============================================================
    // CONTROL INPUTS (FROM CONTROL TOP 1DCONV - 2D Array Controls)
    // ============================================================
    input  wire [Dimension*Dimension-1:0]        conv_en_in,
    input  wire [Dimension*Dimension-1:0]        conv_en_out,
    input  wire [Dimension*Dimension-1:0]        conv_en_psum,
    input  wire [Dimension*Dimension-1:0]        conv_clear_psum,  // FIXED: Added missing port
    input  wire [Dimension-1:0]                  conv_ifmaps_sel_ctrl,
    input  wire [Dimension-1:0]                  conv_output_eject_ctrl,

    // ============================================================
    // CONTROL INPUTS (FROM CONTROL TOP TRANSCONV - 1D Diagonal Controls)
    // ============================================================
    input  wire [Dimension-1:0]              transconv_en_weight_load,
    input  wire [Dimension-1:0]              transconv_en_ifmap_load,
    input  wire [Dimension-1:0]              transconv_en_psum,
    input  wire [Dimension-1:0]              transconv_clear_psum,
    input  wire [Dimension-1:0]              transconv_en_output,
    input  wire [Dimension-1:0]              transconv_ifmap_sel_ctrl,
    input  wire [4:0]                        transconv_done_select,

    // ============================================================
    // OUTPUTS (TRANSCONV)
    // ============================================================
    output wire signed [DW-1:0]              transconv_result_out,
    output wire        [3:0]                 transconv_col_id,
    output wire                              transconv_partial_valid,

    // ============================================================
    // OUTPUTS (1DCONV)
    // ============================================================
    output wire signed [DW*Dimension-1:0]    conv_output_from_array
);

    // ============================================================
    // INTERNAL SIGNALS
    // ============================================================
    wire signed [DW*Dimension-1:0] weight_to_array;
    wire signed [DW*Dimension-1:0] ifmap_to_array;
    wire signed [DW*Dimension-1:0] weight_from_buffer;
    wire signed [DW*Dimension-1:0] ifmap_from_buffer;

    // ============================================================
    // 1DCONV BUFFER INSTANTIATION
    // Preprocesses serial input data into parallel format for systolic array
    // ============================================================
    Onedconv_Buffers #(
        .DW          (DW),
        .Dimension   (Dimension),
        .Depth_added (Depth_added)
    ) u_onedconv_buffers (
        // Global Signals
        .clk                         (clk),
        .rst                         (~rst_n || ~rst_top),

        // Control Signal
        .zero_or_data           (conv_zero_or_data),
        .zero_or_data_weight    (conv_zero_or_data_weight),   
        // Enable Signals
        .en_shift_reg_ifmap_muxed    (en_shift_reg_ifmap_muxed),
        .en_shift_reg_weight_muxed   (en_shift_reg_weight_muxed),
        // Data Inputs
        .weight_brams_in             (weight_brams_in),
        .ifmap_serial_in             (ifmap_serial_in),

        // Data Outputs
        .weight_flat                 (weight_from_buffer),
        .ifmap_flat                  (ifmap_from_buffer)
    );

    // ============================================================
    // MODE-BASED DATA MULTIPLEXING
    // conv_mode = 0: Use buffered data (1DCONV)
    // conv_mode = 1: Use direct inputs (TRANSCONV)
    // ============================================================
    assign weight_to_array = conv_mode ? weight_in : weight_from_buffer;
    assign ifmap_to_array  = conv_mode ? ifmap_in  : ifmap_from_buffer;

    // ============================================================
    // UNIFIED MULTIPLICATOR INSTANTIATION
    // Contains systolic array with internal control MUX for both modes
    // ============================================================
    Unified_Multiplicator #(
        .DW        (DW),
        .Dimension (Dimension)
    ) u_unified_multiplicator (
        .clk                       (clk),
        .rst_n                     (~rst_n || ~rst_top),
        .conv_mode                 (conv_mode),

        // Data Inputs (MUXed based on mode)
        .weight_in                 (weight_to_array),
        .ifmap_in                  (ifmap_to_array),

        // Control Inputs (1DCONV - 2D array controls)
        .conv_en_in                (conv_en_in),
        .conv_en_out               (conv_en_out),
        .conv_en_psum              (conv_en_psum),
        .conv_clear_psum           (conv_clear_psum),  // FIXED: Added connection
        .conv_ifmaps_sel_ctrl      (conv_ifmaps_sel_ctrl),
        .conv_output_eject_ctrl    (conv_output_eject_ctrl),

        // Control Inputs (TRANSCONV - 1D diagonal controls)
        .transconv_en_weight_load  (transconv_en_weight_load),
        .transconv_en_ifmap_load   (transconv_en_ifmap_load),
        .transconv_en_psum         (transconv_en_psum),
        .transconv_clear_psum      (transconv_clear_psum),
        .transconv_en_output       (transconv_en_output),
        .transconv_ifmap_sel_ctrl  (transconv_ifmap_sel_ctrl),
        .transconv_done_select     (transconv_done_select),

        // Outputs (TRANSCONV)
        .transconv_result_out      (transconv_result_out),
        .transconv_col_id          (transconv_col_id),
        .transconv_partial_valid   (transconv_partial_valid),

        // Outputs (1DCONV)
        .conv_output_from_array    (conv_output_from_array)
    );

endmodule