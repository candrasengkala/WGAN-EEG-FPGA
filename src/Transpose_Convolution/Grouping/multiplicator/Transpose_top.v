`timescale 1ns / 1ps

/******************************************************************************
 * Module: Transpose_top (COMPUTE ENGINE ONLY)
 * * Description:
 * Top-level integration module for transposed convolution COMPUTE PATH.
 * Integrates Systolic Array, Output MUX, and Synchronization Logic.
 * * CHANGES:
 * - Logic synchronization moved to 'Transpose_Output_Sync'.
 * - Instantiates 'Transpose_Output_Sync'.
 * * Author: Dharma Anargya Jowandy
 ******************************************************************************/

module Transpose_top #(
    parameter DW        = 16,  // Data width
    parameter Dimension = 16   // Array dimension
)(
    input  wire                              clk,
    input  wire                              rst_n,
    
    // ============================================================
    // DATA INPUTS
    // ============================================================
    input  wire signed [DW*Dimension-1:0]    weight_in,
    input  wire signed [DW*Dimension-1:0]    ifmap_in,
    
    // ============================================================
    // CONTROL INPUTS (FROM CONTROL TOP)
    // ============================================================
    input  wire [Dimension-1:0]              en_weight_load,
    input  wire [Dimension-1:0]              en_ifmap_load,
    input  wire [Dimension-1:0]              en_psum,
    input  wire [Dimension-1:0]              clear_psum,
    input  wire [Dimension-1:0]              en_output,
    input  wire [Dimension-1:0]              ifmap_sel_ctrl,
    
    // MUX Selector (from Control Top / FSM Done Counter)
    input  wire [4:0]                        done_select, 
    
    // ============================================================
    // OUTPUTS
    // ============================================================
    output wire signed [DW-1:0]              result_out,     // Selected Partial Sum
    output wire        [3:0]                 col_id,         // Synchronized ID
    output wire                              partial_valid   // Synchronized Valid
);

    // ============================================================
    // INTERNAL MAPPING LOGIC (1D Control -> 2D Array)
    // ============================================================
    wire [Dimension*Dimension-1:0] en_in_array, en_psum_array, en_out_array, clear_psum_array;
    
    genvar i, j;
    generate
        for (i = 0; i < Dimension; i = i + 1) begin : GEN_CTRL_ROW
            for (j = 0; j < Dimension; j = j + 1) begin : GEN_CTRL_COL
                // Diagonal mapping: Active only when Row == Col
                if (i == j) begin
                    assign en_in_array[i*Dimension + j]      = en_weight_load[i] | en_ifmap_load[i];
                    assign en_psum_array[i*Dimension + j]    = en_psum[i];
                    assign en_out_array[i*Dimension + j]     = en_output[i];
                    assign clear_psum_array[i*Dimension + j] = clear_psum[i];
                end else begin
                    // Off-diagonal PEs are slaves or unused for direct control
                    assign en_in_array[i*Dimension + j]      = 1'b0;
                    assign en_psum_array[i*Dimension + j]    = 1'b0;
                    assign en_out_array[i*Dimension + j]     = 1'b0;
                    assign clear_psum_array[i*Dimension + j] = 1'b0;
                end
            end
        end
    endgenerate

    // ============================================================
    // DIAGONAL OUTPUT EXTRACTION WIRES
    // ============================================================
    wire signed [DW*Dimension-1:0] output_from_array; // Unused flat output
    wire signed [DW*Dimension-1:0] diagonal_out_packed;
    wire signed [DW-1:0] diagonal_outputs [0:Dimension-1];
    
    genvar k;
    generate
        for (k = 0; k < Dimension; k = k + 1) begin : GEN_DIAG_OUT
            assign diagonal_outputs[k] = diagonal_out_packed[DW*(k+1)-1 : DW*k];
        end
    endgenerate

    // ============================================================
    // INSTANTIATION 1: SYSTOLIC ARRAY
    // ============================================================
    top_lvl #(
        .DW(DW), 
        .Dimension(Dimension)
    ) systolic_array (
        .clk(clk),
        .rst(rst_n),
        .en_cntr(1'b0), // Not used
        
        // Mapped Control Signals
        .en_in(en_in_array), 
        .en_out(en_out_array),
        .en_psum(en_psum_array), 
        .clear_psum(clear_psum_array),
        .ifmaps_sel(ifmap_sel_ctrl), 
        .output_eject_ctrl({Dimension{1'b0}}),
        
        // Data Inputs
        .weight_in(weight_in), 
        .ifmap_in(ifmap_in),
        
        // Outputs
        .done_count(), 
        .output_out(output_from_array), 
        .diagonal_out(diagonal_out_packed) 
    );

    // ============================================================
    // INSTANTIATION 2: OUTPUT SYNCHRONIZATION LOGIC
    // ============================================================
    Transpose_Output_Sync #(
        .Dimension(Dimension)
    ) u_sync (
        .clk(clk),
        .rst_n(rst_n),
        .en_output(en_output),   // Input from Control
        .col_id(col_id),         // Output to Accumulation
        .partial_valid(partial_valid) // Output to Accumulation
    );

    // ============================================================
    // OUTPUT MUX (16-to-1)
    // ============================================================
    reg signed [DW-1:0] mux_output;
    always @(*) begin
        case (done_select)
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
    
    assign result_out = mux_output;

endmodule