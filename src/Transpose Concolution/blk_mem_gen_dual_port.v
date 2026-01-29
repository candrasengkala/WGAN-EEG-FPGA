`timescale 1ns / 1ps
// Behavioral model of Xilinx Block Memory Generator (True Dual Port)
// Simplified version for simulation purposes only

module blk_mem_gen_dual_port #(
    parameter ADDR_WIDTH = 9,      // Default 512 depth (2^9)
    parameter DATA_WIDTH = 16      // Default 16-bit data
)(
    // Port A (Write Port)
    input wire clka,
    input wire ena,
    input wire wea,
    input wire [ADDR_WIDTH-1:0] addra,
    input wire [DATA_WIDTH-1:0] dina,
    
    // Port B (Read Port)
    input wire clkb,
    input wire enb,
    input wire [ADDR_WIDTH-1:0] addrb,
    output reg [DATA_WIDTH-1:0] doutb
);

    // Calculate memory depth from address width
    localparam MEM_DEPTH = 2**ADDR_WIDTH;
    
    // Memory array
    reg [DATA_WIDTH-1:0] mem [0:MEM_DEPTH-1];
    
    // Initialize memory to zero
    integer i;
    initial begin
        for (i = 0; i < MEM_DEPTH; i = i + 1) begin
            mem[i] = {DATA_WIDTH{1'b0}};
        end
        doutb = {DATA_WIDTH{1'b0}};
    end
    
    // Port A: Write operation
    always @(posedge clka) begin
        if (ena && wea) begin
            mem[addra] <= dina;
        end
    end
    
    // Port B: Read operation
    always @(posedge clkb) begin
        if (enb) begin
            doutb <= mem[addrb];
        end
    end

endmodule
