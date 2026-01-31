`timescale 1ns / 1ps

/******************************************************************************
 * Module: Unified_Multiplicator
 * 
 * Description:
 * Top-level integration module for both 1D convolution and transposed convolution.
 * Multiplexes control signals based on conv_mode.
 * Integrates Systolic Array, Output MUX, and Synchronization Logic.
 * 
 * Author: Rizmi Ahmad Raihan
 ******************************************************************************/

module Unified_Multiplicator #(
    parameter DW        = 16,  // Data width
    parameter Dimension = 16   // Array dimension
)(
    input  wire                              clk,
    input  wire                              rst_n,
    input  wire                              conv_mode,  // 0 = 1D Conv, 1 = Transposed Conv
    
    // ============================================================
    // DATA INPUTS
    // ============================================================
    input  wire signed [DW*Dimension-1:0]    weight_in,
    input  wire signed [DW*Dimension-1:0]    ifmap_in,
    
    // ============================================================
    // CONTROL INPUTS (FROM CONTROL TOP 1DCONV)
    // ============================================================
    input  wire [Dimension*Dimension-1:0]    conv_en_in,
    input  wire [Dimension*Dimension-1:0]    conv_en_out,
    input  wire [Dimension*Dimension-1:0]    conv_en_psum,
    input  wire [Dimension*Dimension-1:0]    conv_clear_psum,        // FIXED: Added missing port
    input  wire [Dimension-1:0]              conv_ifmaps_sel_ctrl,
    input  wire [Dimension-1:0]              conv_output_eject_ctrl,

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
    // OUTPUTS
    // ============================================================
    output wire signed [DW-1:0]              transconv_result_out,
    output wire        [3:0]                 transconv_col_id,
    output wire                              transconv_partial_valid,
    output wire signed [DW*Dimension-1:0]    conv_output_from_array
);

    // ============================================================
    // INTERNAL MAPPING LOGIC (1D Control -> 2D Array) - TRANSCONV
    // ============================================================
    wire [Dimension*Dimension-1:0] transconv_en_in_array;
    wire [Dimension*Dimension-1:0] transconv_en_psum_array;
    wire [Dimension*Dimension-1:0] transconv_en_out_array;
    wire [Dimension*Dimension-1:0] transconv_clear_psum_array;
    
    genvar i, j;
    generate
        for (i = 0; i < Dimension; i = i + 1) begin : GEN_CTRL_ROW
            for (j = 0; j < Dimension; j = j + 1) begin : GEN_CTRL_COL
                // Diagonal mapping: Active only when Row == Col
                if (i == j) begin
                    assign transconv_en_in_array[i*Dimension + j]      = transconv_en_weight_load[i] | transconv_en_ifmap_load[i];
                    assign transconv_en_psum_array[i*Dimension + j]    = transconv_en_psum[i];
                    assign transconv_en_out_array[i*Dimension + j]     = transconv_en_output[i];
                    assign transconv_clear_psum_array[i*Dimension + j] = transconv_clear_psum[i];
                end else begin
                    // Off-diagonal PEs are slaves or unused for direct control
                    assign transconv_en_in_array[i*Dimension + j]      = 1'b0;
                    assign transconv_en_psum_array[i*Dimension + j]    = 1'b0;
                    assign transconv_en_out_array[i*Dimension + j]     = 1'b0;
                    assign transconv_clear_psum_array[i*Dimension + j] = 1'b0;
                end
            end
        end
    endgenerate

    // ============================================================
    // DIAGONAL OUTPUT EXTRACTION WIRES
    // ============================================================
    wire signed [DW*Dimension-1:0] diagonal_out_packed;
    wire signed [DW-1:0] diagonal_outputs [0:Dimension-1];
    
    genvar k;
    generate
        for (k = 0; k < Dimension; k = k + 1) begin : GEN_DIAG_OUT
            assign diagonal_outputs[k] = diagonal_out_packed[DW*(k+1)-1 : DW*k];
        end
    endgenerate

    // ============================================================
    // CONTROL MUX: SELECT BETWEEN CONV AND TRANSCONV CONTROL SIGNALS
    // conv_mode = 0: Normal Convolution (1DCONV)
    // conv_mode = 1: Transposed Convolution
    // ============================================================
    wire [Dimension*Dimension-1:0] en_in_array_goes_into;
    wire [Dimension*Dimension-1:0] en_psum_array_goes_into;
    wire [Dimension*Dimension-1:0] en_out_array_goes_into;
    wire [Dimension*Dimension-1:0] clear_psum_array_goes_into;
    wire [Dimension-1:0]           ifmap_sel_ctrl_goes_into;
    wire [Dimension-1:0]           output_eject_ctrl_goes_into;

    // Output wire from systolic array
    wire signed [DW*Dimension-1:0] output_from_array;

    // MUX assignments
    assign en_in_array_goes_into       = conv_mode ? transconv_en_in_array      : conv_en_in;
    assign en_psum_array_goes_into     = conv_mode ? transconv_en_psum_array    : conv_en_psum;
    assign en_out_array_goes_into      = conv_mode ? transconv_en_out_array     : conv_en_out;
    assign clear_psum_array_goes_into  = conv_mode ? transconv_clear_psum_array : conv_clear_psum;  // FIXED: Now uses conv_clear_psum
    assign ifmap_sel_ctrl_goes_into    = conv_mode ? transconv_ifmap_sel_ctrl   : conv_ifmaps_sel_ctrl;
    assign output_eject_ctrl_goes_into = conv_mode ? {Dimension{1'b0}}          : conv_output_eject_ctrl;

    // ============================================================
    // INSTANTIATION 1: SYSTOLIC ARRAY
    // ============================================================
    top_lvl #(
        .DW(DW), 
        .Dimension(Dimension)
    ) systolic_array (
        .clk(clk),
        .rst(rst_n),  // top_lvl uses active-high reset
        
        // Mapped Control Signals
        .en_in(en_in_array_goes_into), 
        .en_out(en_out_array_goes_into),
        .en_psum(en_psum_array_goes_into), 
        .clear_psum(clear_psum_array_goes_into),
        .ifmaps_sel(ifmap_sel_ctrl_goes_into), 
        .output_eject_ctrl(output_eject_ctrl_goes_into),
        
        // Data Inputs
        .weight_in(weight_in), 
        .ifmap_in(ifmap_in),
        
        // Outputs
        .output_out(output_from_array), 
        .diagonal_out(diagonal_out_packed) 
    );

    // ============================================================
    // INSTANTIATION 2: OUTPUT SYNCHRONIZATION LOGIC (Transconv only)
    // ============================================================
    wire [3:0] sync_col_id;
    wire       sync_partial_valid;

    Transpose_Output_Sync #(
        .Dimension(Dimension)
    ) u_sync (
        .clk(clk),
        .rst_n(rst_n),
        .en_output(transconv_en_output),   // Input from Transconv Control
        .col_id(sync_col_id),              // Output to Accumulation
        .partial_valid(sync_partial_valid) // Output to Accumulation
    );

    // ============================================================
    // OUTPUT MUX (16-to-1) FOR TRANSCONV DIAGONAL OUTPUTS
    // ============================================================
    reg signed [DW-1:0] mux_output;
    always @(*) begin
        case (transconv_done_select)
            5'd0:  mux_output = diagonal_outputs[0];
            5'd1:  mux_output = diagonal_outputs[1];
            5'd2:  mux_output = diagonal_outputs[2];
            5'd3:  mux_output = diagonal_outputs[3];
            5'd4:  mux_output = diagonal_outputs[4];
            5'd5:  mux_output = diagonal_outputs[5];
            5'd6:  mux_output = diagonal_outputs[6];
            5'd7:  mux_output = diagonal_outputs[7];
            5'd8:  mux_output = diagonal_outputs[8];
            5'd9:  mux_output = diagonal_outputs[9];
            5'd10: mux_output = diagonal_outputs[10];
            5'd11: mux_output = diagonal_outputs[11];
            5'd12: mux_output = diagonal_outputs[12];
            5'd13: mux_output = diagonal_outputs[13];
            5'd14: mux_output = diagonal_outputs[14];
            5'd15: mux_output = diagonal_outputs[15];
            default: mux_output = {DW{1'b0}};
        endcase
    end

    // ============================================================
    // OUTPUT ASSIGNMENTS
    // ============================================================
    // Transconv outputs
    assign transconv_result_out    = mux_output;
    assign transconv_col_id        = sync_col_id;
    assign transconv_partial_valid = sync_partial_valid;

    // Conv output (flat array output from systolic array)
    assign conv_output_from_array  = output_from_array;

endmodule