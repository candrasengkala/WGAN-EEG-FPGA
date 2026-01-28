/******************************************************************************
 * Module: Transpose_top
 * 
 * Description:
 *   Top-level integration module for transposed convolution.
 *   Integrates systolic array, FSM controller, and output MUX.
 *   Handles diagonal output extraction and timing synchronization.
 * 
 * Features:
 *   - 16x16 systolic array for transposed convolution
 *   - FSM-controlled dataflow
 *   - Diagonal PE output extraction
 *   - 16-to-1 MUX for sequential partial sum output
 *   - Column ID and valid signal generation
 *   - 1-cycle latency compensation for PE output
 * 
 * Parameters:
 *   DW        - Data width (default: 16)
 *   Dimension - Array dimension (default: 16)
 * 
 * Author: Dharma Anargya Jowandy
 * Date: January 2026
 ******************************************************************************/

`timescale 1ns / 1ps

module Transpose_top #(
    parameter DW        = 16,  // Data width (16-bit fixed-point)
    parameter Dimension = 16   // Array dimension
)(
    input wire                              clk,
    input wire                              rst_n,
    input wire                              start,
    input wire [7:0]                        Instruction_code, 
    input wire [8:0]                        num_iterations,
    input wire signed [DW*Dimension-1:0]    weight_in,
    input wire signed [DW*Dimension-1:0]    ifmap_in,
    
    output wire signed [DW-1:0]             result_out,
    output wire [4:0]                       done,
    output wire [7:0]                       iter_count,
    output wire [3:0]                       col_id,
    output wire                             partial_valid
);
    // Internal wires
    wire [Dimension-1:0] en_weight_load, en_ifmap_load, en_psum, clear_psum, en_output, ifmap_sel_ctrl;
    wire [Dimension*Dimension-1:0] en_in_array, en_psum_array, en_out_array, clear_psum_array;
    wire signed [DW*Dimension-1:0] output_from_array, diagonal_out_packed;
    wire signed [DW-1:0] diagonal_outputs [0:Dimension-1];
    
    // Extract Outputs
    genvar k;
    generate
        for (k = 0; k < Dimension; k = k + 1) begin : GEN_DIAG_OUT
            assign diagonal_outputs[k] = diagonal_out_packed[DW*(k+1)-1 : DW*k];
        end
    endgenerate
    
    // Map Controls
    genvar i, j;
    generate
        for (i = 0; i < Dimension; i = i + 1) begin : GEN_CTRL_ROW
            for (j = 0; j < Dimension; j = j + 1) begin : GEN_CTRL_COL
                if (i == j) begin
                    assign en_in_array[i*Dimension + j] = en_weight_load[i] | en_ifmap_load[i];
                    assign en_psum_array[i*Dimension + j] = en_psum[i];
                    assign en_out_array[i*Dimension + j] = en_output[i];
                    assign clear_psum_array[i*Dimension + j] = clear_psum[i];
                end else begin
                    assign en_in_array[i*Dimension + j] = 1'b0;
                    assign en_psum_array[i*Dimension + j] = 1'b0;
                    assign en_out_array[i*Dimension + j] = 1'b0;
                    assign clear_psum_array[i*Dimension + j] = 1'b0;
                end
            end
        end
    endgenerate
    
    // ============================================================
    // DATA SYNCHRONIZATION LOGIC
    // ============================================================
    reg [3:0] col_id_delayed;
    reg partial_valid_delayed;
    
    reg [3:0] col_id_comb;
    integer m;
    always @(*) begin
        col_id_comb = 4'd0;
        for (m = 0; m < Dimension; m = m + 1) begin
            if (en_output[m]) col_id_comb = m[3:0];
        end
    end

    // Delay 1 cycle to match PE Output Latency
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            col_id_delayed <= 4'd0;
            partial_valid_delayed <= 1'b0;
        end else begin
            col_id_delayed <= col_id_comb;
            // Valid only if en_output was active
            // This masks the "Gap" cycles during LOAD state
            partial_valid_delayed <= |en_output; 
        end
    end
    
    assign col_id = col_id_delayed;
    assign partial_valid = partial_valid_delayed;
    
    // ============================================================
    // Instantiations
    // ============================================================
    Transpose_Matrix_FSM #(
        .DW(DW),
        .NUM_PE(Dimension)
    ) fsm_inst (
        .clk(clk), 
        .rst_n(rst_n), 
        .start(start),
        .Instruction_code(Instruction_code), 
        .num_iterations(num_iterations),
        .en_weight_load(en_weight_load), 
        .en_ifmap_load(en_ifmap_load),
        .en_psum(en_psum), 
        .clear_psum(clear_psum),
        .en_output(en_output), 
        .ifmap_sel_ctrl(ifmap_sel_ctrl),
        .done(done), 
        .iter_count(iter_count)
    );

    top_lvl #(
        .DW(DW), 
        .Dimension(Dimension)
    ) systolic_array (
        .clk(clk),
        .rst(rst_n),
        .en_cntr(1'b0), 
        .en_in(en_in_array), 
        .en_out(en_out_array),
        .en_psum(en_psum_array), 
        .clear_psum(clear_psum_array),
        .ifmaps_sel(ifmap_sel_ctrl), 
        .output_eject_ctrl({Dimension{1'b0}}),
        .weight_in(weight_in), 
        .ifmap_in(ifmap_in),
        .done_count(), 
        .output_out(output_from_array),
        .diagonal_out(diagonal_out_packed)
    );

    // MUX 16-to-1
    reg signed [DW-1:0] mux_output;
    always @(*) begin
        case (done)
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