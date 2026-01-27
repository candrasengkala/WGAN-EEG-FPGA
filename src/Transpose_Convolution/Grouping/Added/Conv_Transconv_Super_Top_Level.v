`timescale 1ns / 1ps

/******************************************************************************
 * Module: Conv_Transconv_Super_Top_Level
 *
 * Description:
 * Unified top-level integration for BOTH Normal Convolution (1DCONV) and
 * Transposed Convolution (TRANSCONV) operations.
 *
 * Architecture:
 *   1. Weight_BRAM_Top      - Shared weight storage (16 BRAMs)
 *   2. Ifmap_BRAM_Top       - Shared input feature map storage (16 BRAMs)
 *   3. Conv_Transconv_Top   - Unified compute engine (systolic array + buffers)
 *   4. BRAM_Output_Top      - Unified output BRAM (supports both modes)
 *
 * Mode Selection:
 *   - conv_mode = 0: Normal 1D Convolution
 *   - conv_mode = 1: Transposed Convolution
 *
 * Control Signal Sources:
 *   - 1DCONV:    From onedconv_ctrl (external) - uses 2D array control
 *   - TRANSCONV: From Transpose_Control_Top (external) - uses 1D diagonal control
 *
 * Author: Integrated Design
 ******************************************************************************/

module Conv_Transconv_Super_Top_Level #(
    parameter DW          = 16,
    parameter NUM_BRAMS   = 16,   // Dimension
    parameter W_ADDR_W    = 11,   // Weight BRAM Address Width
    parameter W_DEPTH     = 2048, // Weight BRAM Depth
    parameter I_ADDR_W    = 10,   // Ifmap BRAM Address Width
    parameter I_DEPTH     = 1024, // Ifmap BRAM Depth
    parameter O_ADDR_W    = 10,   // Output BRAM Address Width
    parameter O_DEPTH     = 1024, // Output BRAM Depth
    parameter Depth_added = 16    // Buffer depth for 1DCONV
)(
    input  wire                              clk,
    input  wire                              rst_n,

    // ========================================================================
    // MODE SELECTION
    // ========================================================================
    input  wire                              conv_mode,  // 0=1DCONV, 1=TRANSCONV

    // ========================================================================
    // 1. WEIGHT BRAM INTERFACE (External Write Control)
    // ========================================================================
    input  wire [NUM_BRAMS-1:0]              w_we,
    input  wire [NUM_BRAMS*W_ADDR_W-1:0]     w_addr_wr_flat,
    input  wire signed [NUM_BRAMS*DW-1:0]    w_din_flat,

    // Read Port (from Control Units)
    input  wire [NUM_BRAMS-1:0]              w_re,
    input  wire [NUM_BRAMS*W_ADDR_W-1:0]     w_addr_rd_flat,

    // ========================================================================
    // 2. IFMAP BRAM INTERFACE (External Write Control)
    // ========================================================================
    input  wire [NUM_BRAMS-1:0]              if_we,
    input  wire [NUM_BRAMS*I_ADDR_W-1:0]     if_addr_wr_flat,
    input  wire signed [NUM_BRAMS*DW-1:0]    if_din_flat,

    // Read Port (from Control Units)
    input  wire [NUM_BRAMS-1:0]              if_re,
    input  wire [NUM_BRAMS*I_ADDR_W-1:0]     if_addr_rd_flat,
    input  wire [3:0]                        ifmap_sel,  // MUX selector for TRANSCONV

    // ========================================================================
    // 3. CONTROL INPUTS - 1DCONV (FROM onedconv_ctrl)
    // ========================================================================
    // Buffer control
    input  wire                              conv_buffer_mode,
    input  wire                              conv_en_shift_reg_ifmap_input,
    input  wire                              conv_en_shift_reg_weight_input,
    input  wire                              conv_en_shift_reg_ifmap_control,
    input  wire                              conv_en_shift_reg_weight_control,

    // Systolic array control (2D - Dimension x Dimension)
    input  wire                              conv_en_cntr,
    input  wire [NUM_BRAMS*NUM_BRAMS-1:0]    conv_en_in,
    input  wire [NUM_BRAMS*NUM_BRAMS-1:0]    conv_en_out,
    input  wire [NUM_BRAMS*NUM_BRAMS-1:0]    conv_en_psum,
    input  wire [NUM_BRAMS*NUM_BRAMS-1:0]    conv_clear_psum,
    input  wire [NUM_BRAMS-1:0]              conv_ifmaps_sel_ctrl,
    input  wire [NUM_BRAMS-1:0]              conv_output_eject_ctrl,

    // 1DCONV Output BRAM control
    input  wire                              conv_out_new_val_sign,
    input  wire [O_ADDR_W-1:0]               conv_output_addr_wr,
    input  wire [O_ADDR_W-1:0]               conv_output_addr_rd,
    input  wire [NUM_BRAMS-1:0]              conv_ena_output,
    input  wire [NUM_BRAMS-1:0]              conv_wea_output,
    input  wire [NUM_BRAMS-1:0]              conv_enb_output,
    input  wire                              conv_en_reg_adder,
    input  wire                              conv_output_reg_rst,
    input  wire                              conv_output_bram_dest,

    // 1DCONV Bias control
    input  wire                              input_bias,
    input  wire [NUM_BRAMS-1:0]              bias_ena,
    input  wire [NUM_BRAMS-1:0]              bias_wea,
    input  wire [O_ADDR_W-1:0]               bias_addr,
    input  wire signed [NUM_BRAMS*DW-1:0]    bias_data,

    // ========================================================================
    // 4. CONTROL INPUTS - TRANSCONV (FROM Transpose_Control_Top)
    // ========================================================================
    // Systolic array control (1D diagonal - Dimension)
    input  wire [NUM_BRAMS-1:0]              transconv_en_weight_load,
    input  wire [NUM_BRAMS-1:0]              transconv_en_ifmap_load,
    input  wire [NUM_BRAMS-1:0]              transconv_en_psum,
    input  wire [NUM_BRAMS-1:0]              transconv_clear_psum,
    input  wire [NUM_BRAMS-1:0]              transconv_en_output,
    input  wire [NUM_BRAMS-1:0]              transconv_ifmap_sel_ctrl,
    input  wire [4:0]                        transconv_done_select,

    // ========================================================================
    // 5. MAPPING CONFIGURATION - TRANSCONV (FROM MM2IM_Top)
    // ========================================================================
    input  wire [NUM_BRAMS-1:0]              cmap,
    input  wire [NUM_BRAMS*14-1:0]           omap_flat,

    // ========================================================================
    // 6. EXTERNAL READ INTERFACE (Shared for both modes)
    // ========================================================================
    input  wire                              ext_read_mode,
    input  wire [NUM_BRAMS*O_ADDR_W-1:0]     ext_read_addr_flat,

    // ========================================================================
    // 7. OUTPUTS
    // ========================================================================
    output wire signed [NUM_BRAMS*DW-1:0]    bram_read_data_flat,
    output wire        [NUM_BRAMS*O_ADDR_W-1:0] bram_read_addr_flat
);

    // ========================================================================
    // INTERNAL INTERCONNECTS
    // ========================================================================

    // Weight BRAM -> Compute Engine
    wire signed [NUM_BRAMS*DW-1:0] weight_data_flat;

    // Ifmap BRAM outputs
    wire signed [DW-1:0]           ifmap_data_single;      // For TRANSCONV (broadcast)
    wire signed [NUM_BRAMS*DW-1:0] ifmap_data_broadcast;   // Broadcasted version

    // Compute Engine outputs
    wire signed [DW-1:0]           transconv_result_out;
    wire [3:0]                     transconv_col_id;
    wire                           transconv_partial_valid;
    wire signed [NUM_BRAMS*DW-1:0] conv_output_from_array;

    // ========================================================================
    // BROADCAST LOGIC (TRANSCONV: Single Ifmap -> 16 Inputs)
    // ========================================================================
    genvar k;
    generate
        for (k = 0; k < NUM_BRAMS; k = k + 1) begin : IFMAP_BROADCAST
            assign ifmap_data_broadcast[k*DW +: DW] = ifmap_data_single;
        end
    endgenerate

    // ========================================================================
    // INSTANTIATION 1: WEIGHT BRAM TOP (Shared)
    // ========================================================================
    Weight_BRAM_Top #(
        .DW         (DW),
        .NUM_BRAMS  (NUM_BRAMS),
        .ADDR_WIDTH (W_ADDR_W),
        .DEPTH      (W_DEPTH)
    ) u_weight_bram (
        .clk             (clk),
        .rst_n           (rst_n),
        // Write Port
        .w_we            (w_we),
        .w_addr_wr_flat  (w_addr_wr_flat),
        .w_din_flat      (w_din_flat),
        // Read Port
        .w_re            (w_re),
        .w_addr_rd_flat  (w_addr_rd_flat),
        // Output
        .weight_out_flat (weight_data_flat)
    );

    // ========================================================================
    // INSTANTIATION 2: IFMAP BRAM TOP (Shared)
    // ========================================================================
    ifmap_BRAM_Top #(
        .DW         (DW),
        .NUM_BRAMS  (NUM_BRAMS),
        .ADDR_WIDTH (I_ADDR_W),
        .DEPTH      (I_DEPTH)
    ) u_ifmap_bram (
        .clk             (clk),
        .rst_n           (rst_n),
        // Write Port
        .if_we           (if_we),
        .if_addr_wr_flat (if_addr_wr_flat),
        .if_din_flat     (if_din_flat),
        // Read Port
        .if_re           (if_re),
        .if_addr_rd_flat (if_addr_rd_flat),
        .ifmap_sel       (ifmap_sel),
        // Outputs
        .ifmap_out       (ifmap_data_single)
    );

    // ========================================================================
    // INSTANTIATION 3: UNIFIED COMPUTE ENGINE
    // Conv_Transconv_Top handles both modes with internal MUXing
    // ========================================================================
    Conv_Transconv_Top #(
        .DW          (DW),
        .Dimension   (NUM_BRAMS),
        .Depth_added (Depth_added)
    ) u_compute_engine (
        .clk                         (clk),
        .rst_n                       (rst_n),
        .conv_mode                   (conv_mode),

        // Data Inputs (TRANSCONV - direct from BRAM)
        .weight_in                   (weight_data_flat),
        .ifmap_in                    (ifmap_data_broadcast),

        // Data Inputs (1DCONV - through buffers)
        .buffer_mode                 (conv_buffer_mode),
        .weight_brams_in             (weight_data_flat),
        .ifmap_serial_in             (ifmap_data_single),

        // Buffer Control (1DCONV)
        .en_shift_reg_ifmap_input    (conv_en_shift_reg_ifmap_input),
        .en_shift_reg_weight_input   (conv_en_shift_reg_weight_input),
        .en_shift_reg_ifmap_control  (conv_en_shift_reg_ifmap_control),
        .en_shift_reg_weight_control (conv_en_shift_reg_weight_control),

        // Control Inputs (1DCONV - 2D array)
        .conv_en_cntr                (conv_en_cntr),
        .conv_en_in                  (conv_en_in),
        .conv_en_out                 (conv_en_out),
        .conv_en_psum                (conv_en_psum),
        .conv_clear_psum             (conv_clear_psum),
        .conv_ifmaps_sel_ctrl        (conv_ifmaps_sel_ctrl),
        .conv_output_eject_ctrl      (conv_output_eject_ctrl),

        // Control Inputs (TRANSCONV - 1D diagonal)
        .transconv_en_weight_load    (transconv_en_weight_load),
        .transconv_en_ifmap_load     (transconv_en_ifmap_load),
        .transconv_en_psum           (transconv_en_psum),
        .transconv_clear_psum        (transconv_clear_psum),
        .transconv_en_output         (transconv_en_output),
        .transconv_ifmap_sel_ctrl    (transconv_ifmap_sel_ctrl),
        .transconv_done_select       (transconv_done_select),

        // Outputs (TRANSCONV)
        .transconv_result_out        (transconv_result_out),
        .transconv_col_id            (transconv_col_id),
        .transconv_partial_valid     (transconv_partial_valid),

        // Outputs (1DCONV)
        .conv_output_from_array      (conv_output_from_array)
    );

    // ========================================================================
    // INSTANTIATION 4: UNIFIED OUTPUT BRAM
    // BRAM_Output_Top handles both TRANSCONV accumulation and 1DCONV addition
    // ========================================================================
    BRAM_Output_Top #(
        .DW         (DW),
        .NUM_BRAMS  (NUM_BRAMS),
        .ADDR_WIDTH (O_ADDR_W),
        .DEPTH      (O_DEPTH)
    ) u_output_bram (
        .clk                      (clk),
        .rst_n                    (rst_n),
        
        // Mode selection
        .conv_mode                (conv_mode),

        // TRANSCONV inputs
        .transconv_partial_in     (transconv_result_out),
        .transconv_col_id         (transconv_col_id),
        .transconv_partial_valid  (transconv_partial_valid),
        .transconv_cmap           (cmap),
        .transconv_omap_flat      (omap_flat),

        // 1DCONV inputs
        .conv_systolic_output     (conv_output_from_array),
        .conv_out_new_val_sign    (conv_out_new_val_sign),
        .conv_output_addr_wr      (conv_output_addr_wr),
        .conv_output_addr_rd      (conv_output_addr_rd),
        .conv_ena_output          (conv_ena_output),
        .conv_wea_output          (conv_wea_output),
        .conv_enb_output          (conv_enb_output),
        .conv_en_reg_adder        (conv_en_reg_adder),
        .conv_output_reg_rst      (conv_output_reg_rst),
        .conv_output_bram_dest    (conv_output_bram_dest),

        // Bias inputs (1DCONV)
        .input_bias               (input_bias),
        .bias_ena                 (bias_ena),
        .bias_wea                 (bias_wea),
        .bias_addr                (bias_addr),
        .bias_data                (bias_data),

        // External read interface (shared)
        .ext_read_mode            (ext_read_mode),
        .ext_read_addr_flat       (ext_read_addr_flat),

        // Outputs
        .bram_read_data_flat      (bram_read_data_flat),
        .bram_read_addr_flat      (bram_read_addr_flat)
    );

endmodule