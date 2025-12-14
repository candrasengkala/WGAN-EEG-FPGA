module pe_operator #(
    parameter INPUT_WIDTH = 16,
    parameter ACCUM_WIDTH = 32
)
(
    input wire [INPUT_WIDTH-1:0] weight,
    input wire [INPUT_WIDTH-1:0] activation,
    input wire [ACCUM_WIDTH-1:0] partial_sum_in,
    output wire [ACCUM_WIDTH-1:0] result_out
);

    // Internal signals
    wire [ACCUM_WIDTH-1:0] mult_result;
    
    // Multiply: 16-bit x 16-bit = 32-bit (extended to ACCUM_WIDTH)
    assign mult_result = weight * activation;
    
    // Add with partial sum: 32-bit + 32-bit = 32-bit (combinational)
    assign result_out = mult_result + partial_sum_in;
    
endmodule
