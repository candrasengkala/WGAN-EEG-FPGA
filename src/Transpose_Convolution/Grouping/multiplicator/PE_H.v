/******************************************************************************
 * Module: PE_H
 * 
 * Description:
 *   Horizontal Processing Element - Base PE design.
 *   Implements output-stationary systolic array architecture with
 *   MAC operation and partial sum accumulation.
 *   Modified for Q9.10 fixed-point format (20-bit).
 * 
 * Features:
 *   - Output stationary architecture
 *   - Pipelined weight and ifmap propagation
 *   - Partial sum accumulation with clear
 *   - Configurable output ejection
 *   - Q9.10 fixed-point arithmetic with saturation
 *   - Wire slicing for format conversion (no shifter needed)
 * 
 * Parameters:
 *   DW - Data width (default: 20 for Q9.10)
 * 
 * Author: Rizmi Ahmad Raihan (Modified for Q9.10)
 * Date: January 13, 2026
 ******************************************************************************/

`timescale 1ns / 1ps

module PE_H #(
    parameter DW = 20  // Data width (20-bit Q9.10 fixed-point)
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
    
    // ============================================================
    // MAC Operation for Q9.10 Fixed-Point Format
    // ============================================================
    // Q9.10 × Q9.10 = Q18.20 (40-bit result)
    // Extract bits [29:10] to return to Q9.10 format (20-bit)
    // This is wire slicing, NOT a shift operation (zero hardware cost)
    // ============================================================
    
    // Step 1: Multiply (20-bit × 20-bit = 40-bit)
    wire signed [39:0] mult_result_full;
    assign mult_result_full = ifmap_out * weight_out;
    
    // Step 2: Extract Q9.10 from Q18.20 result
    // Bit layout of Q18.20 (40-bit):
    //   [39]     = sign
    //   [38:20]  = 19 integer bits
    //   [19:0]   = 20 fractional bits
    //
    // We want Q9.10 (20-bit):
    //   [19]     = sign
    //   [18:10]  = 9 integer bits
    //   [9:0]    = 10 fractional bits
    //
    // Take bits [29:10] from the 40-bit result
    wire signed [DW-1:0] mult_q9_10;
    assign mult_q9_10 = mult_result_full[29:10];
    
    // Step 3: Accumulation with overflow detection
    // Use 21-bit temporary to detect overflow
    wire signed [DW:0] psum_temp;
    assign psum_temp = mult_q9_10 + psum_reg_out;
    
    // Step 4: Saturation logic
    // Check MSB 2 bits for overflow:
    //   [20:19] = 00 → positive, no overflow
    //   [20:19] = 01 → positive overflow (saturate to max)
    //   [20:19] = 10 → negative overflow (saturate to min)
    //   [20:19] = 11 → negative, no overflow
    wire signed [DW-1:0] psum_saturated;
    assign psum_saturated = (psum_temp[DW:DW-1] == 2'b01) ? {1'b0, {(DW-1){1'b1}}} :  // Max: +524287
                            (psum_temp[DW:DW-1] == 2'b10) ? {1'b1, {(DW-1){1'b0}}} :  // Min: -524288
                            psum_temp[DW-1:0];  // Normal (no overflow)
    
    // Final psum output
    assign psum_now = psum_saturated;
    
endmodule