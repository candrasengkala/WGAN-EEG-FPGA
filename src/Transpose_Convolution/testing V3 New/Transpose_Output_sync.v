`timescale 1ns / 1ps

/******************************************************************************
 * Module      : Transpose_Output_Sync
 * Author      : Dharma Anargya Jowandy
 *
 * Description :
 * Synchronization module for transpose engine outputs.
 * Aligns control signals with the processing element (PE) output latency
 * by decoding the active column and applying a one-cycle delay.
 *
 * Functionality :
 * - Decodes active column index from en_output vector
 * - Delays col_id and valid signal by one clock cycle
 *
 * Parameters :
 * - Dimension : Systolic array dimension (default: 16)
 *
 ******************************************************************************/

module Transpose_Output_Sync #(
    parameter Dimension = 16   // Array dimension
)(
    input  wire                  clk,
    input  wire                  rst_n,
    
    // Input Control Signal (from Control Top)
    input  wire [Dimension-1:0]  en_output, 
    
    // Synchronized Outputs (to Accumulation Unit)
    output reg  [3:0]            col_id,
    output reg                   partial_valid
);

    reg [3:0] col_id_comb;
    integer m;

    // Combinational Logic: Decode active column
    always @(*) begin
        col_id_comb = 4'd0;
        for (m = 0; m < Dimension; m = m + 1) begin
            if (en_output[m]) 
                col_id_comb = m[3:0];
        end
    end

    // Sequential Logic: 1-Cycle Delay to match PE Latency
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            col_id        <= 4'd0;
            partial_valid <= 1'b0;
        end else begin
            col_id <= col_id_comb;
            
            // Valid if ANY column output is enabled
            partial_valid <= |en_output;
        end
    end

endmodule