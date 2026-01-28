module Core #(
    parameter DW = 16,
    parameter Dimension = 16,
    parameter Depth_added = 16
)(
    input  wire                              clk,
    input  wire                              rst_n,
    input  wire                              conv_mode,

    // ============================================================
    // DATA INPUTS (TRANSCONV)
    // ============================================================
    input  wire signed [DW*Dimension-1:0]    weight_in,
    input  wire signed [DW*Dimension-1:0]    ifmap_in,

    // ============================================================
    // DATA INPUTS (1DCONV)
    // ============================================================
    input  wire                              buffer_mode,
    input  wire signed [Dimension*DW-1:0]    weight_brams_in,
    input  wire signed [DW-1:0]              ifmap_serial_in,

    // ============================================================
    // CONTROL INPUTS (1DCONV BUFFERS)
    // ============================================================
    input  wire                              en_shift_reg_ifmap_input,
    input  wire                              en_shift_reg_weight_input,
    input  wire                              en_shift_reg_ifmap_control,
    input  wire                              en_shift_reg_weight_control,

    // ============================================================
    // CONTROL INPUTS (FROM CONTROL TOP 1DCONV)
    // ============================================================
    input  wire                                  conv_en_cntr,
    input  wire [Dimension*Dimension-1:0]        conv_en_in,
    input  wire [Dimension*Dimension-1:0]        conv_en_out,
    input  wire [Dimension*Dimension-1:0]        conv_en_psum,
    input  wire [Dimension-1:0]                  conv_ifmaps_sel_ctrl,
    input  wire [Dimension-1:0]                  conv_output_eject_ctrl,

    // ============================================================
    // CONTROL INPUTS (FROM CONTROL TOP TRANSCONV)
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
    wire signed [DW*Dimension-1:0] weight_in_goes_into;
    wire signed [DW*Dimension-1:0] ifmap_in_goes_into;
    wire signed [DW*Dimension-1:0] weight_flat;
    wire signed [DW*Dimension-1:0] ifmap_flat;

    // ============================================================
    // 1DCONV BUFFER INSTANTIATION
    // ============================================================
    Onedconv_Buffers #(
        .DW          (DW),
        .Dimension   (Dimension),
        .Depth_added (Depth_added)
    ) u_onedconv_buffers (
        // Global Signals
        .clk                         (clk),
        .rst                         (rst_n),

        // Control Signal
        .mode                        (buffer_mode),

        // Enable Signals
        .en_shift_reg_ifmap_input    (en_shift_reg_ifmap_input),
        .en_shift_reg_weight_input   (en_shift_reg_weight_input),
        .en_shift_reg_ifmap_control  (en_shift_reg_ifmap_control),
        .en_shift_reg_weight_control (en_shift_reg_weight_control),

        // Data Inputs
        .weight_brams_in             (weight_brams_in),
        .ifmap_serial_in             (ifmap_serial_in),

        // Data Outputs
        .weight_flat                 (weight_flat),
        .ifmap_flat                  (ifmap_flat)
    );

    // ============================================================
    // MODE-BASED DATA MULTIPLEXING
    // conv_mode = 0: Normal Convolution (use buffer outputs)
    // conv_mode = 1: Transposed Convolution (use direct inputs)
    // ============================================================
    assign weight_in_goes_into = conv_mode ? weight_in : weight_flat;
    assign ifmap_in_goes_into  = conv_mode ? ifmap_in  : ifmap_flat;

    // ============================================================
    // UNIFIED MULTIPLICATOR INSTANTIATION
    // ============================================================
    Unified_Multiplicator #(
        .DW        (DW),
        .Dimension (Dimension)
    ) u_Unified_Multiplicator (
        .clk                       (clk),
        .rst_n                     (rst_n),
        .conv_mode                 (conv_mode),

        // Data Inputs
        .weight_in                 (weight_in_goes_into),
        .ifmap_in                  (ifmap_in_goes_into),

        // Control Inputs (1DCONV)
        .conv_en_cntr              (conv_en_cntr),
        .conv_en_in                (conv_en_in),
        .conv_en_out               (conv_en_out),
        .conv_en_psum              (conv_en_psum),
        .conv_ifmaps_sel_ctrl      (conv_ifmaps_sel_ctrl),
        .conv_output_eject_ctrl    (conv_output_eject_ctrl),

        // Control Inputs (TRANSCONV)
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
