/******************************************************************************
 * Module: PE_H
 * 
 * Description:
 *   Horizontal Processing Element - Base PE design.
 *   Implements output-stationary systolic array architecture with
 *   MAC operation and partial sum accumulation.
 * 
 * Features:
 *   - Output stationary architecture
 *   - Pipelined weight and ifmap propagation
 *   - Partial sum accumulation with clear
 *   - Configurable output ejection
 *   - Parameterized data width
 * 
 * Parameters:
 *   DW - Data width (default: 16)
 * 
 * Author: Rizmi Ahmad Raihan
 * Date: January 13, 2026
 ******************************************************************************/

`timescale 1ns / 1ps

module PE_H #(
    parameter DW = 16  // Data width (16-bit fixed-point)
)(
    // Clock and reset
    input wire                   clk,
    input wire                   rst,
    
    // Enable signals
    input wire                   en_in,        // Enable signal for input registers
    input wire                   en_out,       // Enable signal for output registers
    input wire                   en_psum,      // Enable signal for psum register
    input wire                   clear_psum,   // Clear psum accumulator
    
    // Data inputs
    input wire signed [DW-1:0]   weight_in,
    input wire signed [DW-1:0]   ifmap_in,
    input wire signed [DW-1:0]   output_in,
    
    // Control signals
    input wire                   output_eject_ctrl,  // Controlling passing outputs
    
    // Outputs (connection to neighboring PEs)
    output wire signed [DW-1:0]  weight_out, 
    output wire signed [DW-1:0]  ifmap_out,
    output wire signed [DW-1:0]  output_out
);

    // Register initial values
    reg signed [DW-1:0] ifmap_reg = {DW{1'b0}};
    reg signed [DW-1:0] weight_reg = {DW{1'b0}};
    reg signed [DW-1:0] psum_reg = {DW{1'b0}};
    reg signed [DW-1:0] output_reg = {DW{1'b0}};

    wire signed [DW-1:0] psum_now;
    wire signed [DW-1:0] psum_reg_out;
    wire signed [DW-1:0] output_selected;
    
    // Multiplexer for output selection
    assign output_selected = output_eject_ctrl ? output_in : psum_reg_out;
    
    // Pipelining registers for ifmaps, psum, and weights
    always @(posedge clk) begin
        if (!rst) begin
            ifmap_reg <= {DW{1'b0}};
            weight_reg <= {DW{1'b0}};
            psum_reg <= {DW{1'b0}};
            output_reg <= {DW{1'b0}};
        end else begin
            if (en_in) begin
                ifmap_reg <= ifmap_in;
                weight_reg <= weight_in;
            end 
            if (en_out) begin
                output_reg <= output_selected;
            end
            if (clear_psum) begin
                psum_reg <= {DW{1'b0}};
            end else if (en_psum) begin
                psum_reg <= psum_now;
            end
        end
    end
    
    // Intermediate signal for psum register output
    assign psum_reg_out = psum_reg;
    
    // Output assignments
    assign weight_out = weight_reg;
    assign ifmap_out = ifmap_reg;
    assign output_out = output_reg;
    
    // Current psum calculation (MAC operation)
    assign psum_now = ifmap_out * weight_out + psum_reg_out;
    
endmodule