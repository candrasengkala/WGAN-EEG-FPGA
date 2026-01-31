//==============================================================================
// Leaky ReLU for Q9.14 Fixed-Point Format
// Q9.14 = 9 integer bits + 14 fractional bits + 1 sign bit = 24 bits total
// Range: -256 to +255.999939
// Precision: 2^-14 ≈ 0.000061
//==============================================================================
module leaky_relu_q9_14 #(
    parameter DW = 24,
    parameter ALPHA_FIXED = 164  // 0.01 in Q9.14: 0.01 * 2^14 = 163.84 ≈ 164
)(
    input  wire signed [DW-1:0] x_in,
    output wire signed [DW-1:0] y_out
);

    wire is_negative = x_in[DW-1];
    
    // Multiply by alpha (164/16384 ≈ 0.01)
    wire signed [2*DW-1:0] mult_result = x_in * ALPHA_FIXED;
    
    // Scale back by dividing by 2^14 (shift right by 14)
    wire signed [DW-1:0] alpha_x = mult_result >>> 14;
    
    assign y_out = is_negative ? alpha_x : x_in;

endmodule

//------------------------------------------------------------------------------
// Vector Version for Parallel Channels (After Full Layer)
//------------------------------------------------------------------------------
module leaky_relu_q9_14_vector #(
    parameter DW = 24,
    parameter NUM_CHANNELS = 16,
    parameter ALPHA_SHIFT = 7
)(
    input  wire signed [NUM_CHANNELS*DW-1:0] x_in,
    output wire signed [NUM_CHANNELS*DW-1:0] y_out
);

    genvar i;
    generate
        for (i = 0; i < NUM_CHANNELS; i = i + 1) begin : GEN_LEAKY_RELU
            wire signed [DW-1:0] x_ch = x_in[i*DW +: DW];
            wire is_negative = x_ch[DW-1];
            wire signed [DW-1:0] alpha_x = x_ch >>> ALPHA_SHIFT;
            
            assign y_out[i*DW +: DW] = is_negative ? alpha_x : x_ch;
        end
    endgenerate

endmodule
//==============================================================================
// REMINDER: PUT THIS AFTER OUTPUT CONV. REMEMBER THAT THERE ARE TWO MODES. 
// IT DOESN'T IMPLEMENT RELU DIRECTLY ON OUTPUT.
//==============================================================================

//==============================================================================
// Q9.14 FORMAT VERIFICATION
//==============================================================================
/*
  Q9.14 Format Details:
  - Total bits: 24
  - Sign bit: 1
  - Integer bits: 9
  - Fractional bits: 14
  
  Value = sign × (integer_part + fractional_part / 2^14)
  
  Range: -256.0 to +255.999939
  Resolution: 1/16384 ≈ 0.000061
  
  Example values in Q9.14:
    1.0     = 24'h004000  (2^14 = 16384)
    0.5     = 24'h002000  (2^13 = 8192)
    0.01    = 24'h0000A4  (0.01 * 16384 ≈ 164)
    -1.0    = 24'hFFC000  (two's complement)
  
  Leaky ReLU with α = 1/128:
    Input:  -128.0 (Q9.14: 24'hE00000)
    Output: -1.0   (Q9.14: 24'hFFC000)
    
    Calculation: -128 >> 7 = -1 ✓
*/