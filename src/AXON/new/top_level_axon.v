module top_level_axon 
#(
parameter DATA_WIDTH = 16,
parameter DIMENSION = 16
)(
    input wire clk,
    input wire rst_n, // Active low reset

    // Data Inputs
    input wire [(DATA_WIDTH*(DIMENSION) - 1) : 0] ifmap_ram,
    input wire [(DATA_WIDTH*(DIMENSION) - 1) : 0] weight_ram,
    // Data Outputs
    output wire [(DATA_WIDTH*DIMENSION  - 1) : 0] output_ram
);
wire [DATA_WIDTH - 1 : 0] weight_link   [0 : DIMENSION-1];
wire [DATA_WIDTH - 1 : 0] ifmap_link    [0 : DIMENSION-1];
wire [DATA_WIDTH - 1 : 0] output_link   [0 : DIMENSION-1];

genvar i; // Untuk sejumlah baris
genvar j; // Untuk sejumlah kolom
generate
    for (i = 0; i < DIMENSION; i = i + 1) begin
        for (j = 0; j < DIMENSION; j = j + 1) begin
            if (i == j) begin : GEN_DIAG
                // Generate Diagonal PE 
            pe_d axon_pe_d(
                
            )
        end
    end 
end 
endgenerate
endmodule