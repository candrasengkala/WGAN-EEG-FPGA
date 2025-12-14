`include "register.v"

module delay_module #(
    parameter DATA_WIDTH = 32,
    parameter NUM_STAGES = 3  // Number of registers in delay chain
)
(
    input wire clk,
    input wire reset,
    input wire enable,
    input wire [DATA_WIDTH-1:0] data_in,
    output wire [DATA_WIDTH-1:0] data_out
);

    // Internal wires connecting registers in series
    wire [DATA_WIDTH-1:0] stage_out [0:NUM_STAGES];
    
    // First stage input comes from module input
    assign stage_out[0] = data_in;
    
    // Generate NUM_STAGES registers in series
    genvar i;
    generate
        for (i = 0; i < NUM_STAGES; i = i + 1) begin : delay_stages
            register #(
                .Xwidth(DATA_WIDTH)
            ) reg_stage (
                .clk(clk),
                .reset(reset),
                .enable(enable),
                .data_in(stage_out[i]),
                .data_out(stage_out[i+1])
            );
        end
    endgenerate
    
    // Output comes from last register
    assign data_out = stage_out[NUM_STAGES];
    
endmodule