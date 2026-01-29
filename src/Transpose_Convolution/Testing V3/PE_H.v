/******************************************************************************
 * Module: PE_H
 * * Description:
 * Horizontal Processing Element - Base PE design.
 * Implements output-stationary systolic array architecture with
 * MAC operation and partial sum accumulation.
 * * Updated for Q9.14 fixed-point format (24-bit) to align with AXI width
 * requirements (compatible with 32-bit alignment).
 * * Features:
 * - Output stationary architecture
 * - Pipelined weight and ifmap propagation
 * - Partial sum accumulation with clear
 * - Configurable output ejection
 * - Q9.14 fixed-point arithmetic (24-bit) with saturation
 * - Wire slicing for format conversion [37:14]
 * * Parameters:
 * DW - Data width (default: 24 for Q9.14)
 * * Data Format (Q9.14):
 * [23]    : Sign bit
 * [22:14] : Integer (9 bits)
 * [13:0]  : Fractional (14 bits)
 * * Author: Dharma Anargya Jowandy (Modified for Q9.14 / 24-bit AXI)
 * Date: January 29, 2026
 ******************************************************************************/

`timescale 1ns / 1ps

module PE_H #(
    parameter DW = 24  // Data width (24-bit Q9.14 fixed-point)
)(
    // Clock and reset
    input wire                  clk,
    input wire                  rst,
    
    // Enable signals
    input wire                  en_in,        // Enable signal for input registers
    input wire                  en_out,       // Enable signal for output registers
    input wire                  en_psum,      // Enable signal for psum register
    input wire                  clear_psum,   // Clear psum accumulator
    
    // Data inputs
    input wire signed [DW-1:0]  weight_in,
    input wire signed [DW-1:0]  ifmap_in,
    input wire signed [DW-1:0]  output_in,
    
    // Control signals
    input wire                  output_eject_ctrl,  // Controlling passing outputs
    
    // Outputs (connection to neighboring PEs)
    output wire signed [DW-1:0] weight_out, 
    output wire signed [DW-1:0] ifmap_out,
    output wire signed [DW-1:0] output_out
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
    // MAC Operation for Q9.14 Fixed-Point Format (24-bit)
    // ============================================================
    // Q9.14 × Q9.14 = Q19.28 (48-bit result)
    // Extract bits [37:14] to return to Q9.14 format (24-bit)
    // ============================================================
    
    // Step 1: Multiply (24-bit × 24-bit = 48-bit)
    // We need 2*DW width to hold the full precision result
    wire signed [47:0] mult_result_full;
    assign mult_result_full = ifmap_out * weight_out;
    
    // Step 2: Extract Q9.14 from Q19.28 result
    //
    // Logic Calculation:
    // Input Fractional Bits = 14
    // Product Fractional Bits = 14 + 14 = 28 bits (Index [27:0])
    // Target Fractional Bits = 14
    //
    // We discard the lower 14 bits (excess precision): Bits [13:0]
    // We keep the next 24 bits (target width): Bits [37:14]
    //
    // [37]    = New Sign Bit
    // [36:28] = New Integer (9 bits)
    // [27:14] = New Fractional (14 bits)
    
    wire signed [DW-1:0] mult_q9_14;
    assign mult_q9_14 = mult_result_full[37:14];
    
    // Step 3: Accumulation with overflow detection
    // Use 25-bit temporary (DW+1) to detect overflow before saturation
    wire signed [DW:0] psum_temp;
    assign psum_temp = mult_q9_14 + psum_reg_out;
    
    // Step 4: Saturation logic
    // Check MSB 2 bits of psum_temp [24:23] for overflow:
    //   00 -> positive, no overflow
    //   01 -> positive overflow (saturate to max positive)
    //   10 -> negative overflow (saturate to max negative)
    //   11 -> negative, no overflow
    
    wire signed [DW-1:0] psum_saturated;
    assign psum_saturated = (psum_temp[DW:DW-1] == 2'b01) ? {1'b0, {(DW-1){1'b1}}} :  // Max: +8,388,607
                            (psum_temp[DW:DW-1] == 2'b10) ? {1'b1, {(DW-1){1'b0}}} :  // Min: -8,388,608
                            psum_temp[DW-1:0];  // Normal (no overflow)
    
    // Final psum output
    assign psum_now = psum_saturated;
    
endmodule