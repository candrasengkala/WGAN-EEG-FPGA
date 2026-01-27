/******************************************************************************
 * Module: systolic_wrapper
 * 
 * Description:
 *   Top-level wrapper for systolic array with mode selection.
 *   Multiplexes control signals between convolution and transposed convolution
 *   modes to support both operations on the same hardware.
 * 
 * Features:
 *   - Mode 0: Standard convolution configuration
 *   - Mode 1: Transposed convolution configuration
 *   - Automatic control signal routing based on mode
 *   - Unified interface for both operations
 * 
 * Parameters:
 *   DW        - Data width (default: 16)
 *   Dimension - Array dimension (default: 16)
 * 
 * Author: Rizmi Ahmad Raihan
 * Date: January 25, 2026
 ******************************************************************************/

module systolic_wrapper #(
    parameter DW = 16,
    parameter Dimension = 16
)(
    input  wire clk,
    input  wire rst,
    
    // Mode selection: 0 = Conv, 1 = TransConv
    input  wire mode,

    // Control signals for Convolution mode
    input  wire en_cntr_conv,
    input  wire [Dimension*Dimension - 1 : 0] en_in_conv,
    input  wire [Dimension*Dimension - 1 : 0] en_out_conv,
    input  wire [Dimension*Dimension - 1 : 0] en_psum_conv,
    input  wire [Dimension*Dimension - 1 : 0] clear_psum_conv,
    input  wire [Dimension-1:0] ifmaps_sel_conv,
    input  wire [Dimension-1:0] output_eject_ctrl_conv,

    // Control signals for Transposed Convolution mode
    input  wire en_cntr_transconv,
    input  wire [Dimension*Dimension - 1 : 0] en_in_transconv,
    input  wire [Dimension*Dimension - 1 : 0] en_out_transconv,
    input  wire [Dimension*Dimension - 1 : 0] en_psum_transconv,
    input  wire [Dimension*Dimension - 1 : 0] clear_psum_transconv,
    input  wire [Dimension-1:0] ifmaps_sel_transconv,
    input  wire [Dimension-1:0] output_eject_ctrl_transconv,

    // Data inputs (shared between modes)
    input  wire signed [DW*Dimension-1:0] weight_in,
    input  wire signed [DW*Dimension-1:0] ifmap_in,

    // Outputs (shared between modes)
    output wire done_count,
    output wire signed [DW*Dimension-1:0] output_out,
    output wire signed [DW*Dimension-1:0] diagonal_out
);

    // ============================================================
    // Internal signals after multiplexing
    // ============================================================
    wire en_cntr_muxed;
    wire [Dimension*Dimension - 1 : 0] en_in_muxed;
    wire [Dimension*Dimension - 1 : 0] en_out_muxed;
    wire [Dimension*Dimension - 1 : 0] en_psum_muxed;
    wire [Dimension*Dimension - 1 : 0] clear_psum_muxed;
    wire [Dimension-1:0] ifmaps_sel_muxed;
    wire [Dimension-1:0] output_eject_ctrl_muxed;

    // ============================================================
    // Control Signal Multiplexing
    // Mode 0: Convolution
    // Mode 1: Transposed Convolution
    // ============================================================
    assign en_cntr_muxed = (mode == 1'b0) ? en_cntr_conv : en_cntr_transconv;
    assign en_in_muxed = (mode == 1'b0) ? en_in_conv : en_in_transconv;
    assign en_out_muxed = (mode == 1'b0) ? en_out_conv : en_out_transconv;
    assign en_psum_muxed = (mode == 1'b0) ? en_psum_conv : en_psum_transconv;
    assign clear_psum_muxed = (mode == 1'b0) ? clear_psum_conv : clear_psum_transconv;
    assign ifmaps_sel_muxed = (mode == 1'b0) ? ifmaps_sel_conv : ifmaps_sel_transconv;
    assign output_eject_ctrl_muxed = (mode == 1'b0) ? output_eject_ctrl_conv : output_eject_ctrl_transconv;

    // ============================================================
    // Instantiate the systolic array core
    // ============================================================
    top_lvl #(
        .DW(DW),
        .Dimension(Dimension)
    ) systolic_core (
        .clk(clk),
        .rst(rst),
        
        // Multiplexed control signals
        .en_cntr(en_cntr_muxed),
        .en_in(en_in_muxed),
        .en_out(en_out_muxed),
        .en_psum(en_psum_muxed),
        .clear_psum(clear_psum_muxed),
        .ifmaps_sel(ifmaps_sel_muxed),
        .output_eject_ctrl(output_eject_ctrl_muxed),
        
        // Data signals (shared)
        .weight_in(weight_in),
        .ifmap_in(ifmap_in),
        
        // Outputs
        .done_count(done_count),
        .output_out(output_out),
        .diagonal_out(diagonal_out)
    );

endmodule