// 32-bit Shift Register
// Rising edge clock
// Active high clock enable
// For-loop based template
// File: shift_registers_1.v

module shift_register
#(
    parameter DW = 16,
    parameter Depth_added = 16
)
(
    input wire clk, 
    input wire clken, 
    input wire rst, 
    input wire [DW - 1 : 0] SI, 
    output wire [DW - 1 : 0] SO
);
    // Between 16 ifmaps, a zero must be placed.
    reg [DW - 1 : 0] shreg [0:Depth_added-1];
    integer i;
    always @(posedge clk)begin
        if (!rst) begin
            for (i = 0; i < Depth_added-1; i = i + 1) shreg[i] <= 0;
        end
        else if (clken) begin
            for (i = 0; i < Depth_added-1; i = i+1)
                shreg[i+1] <= shreg[i];
                shreg[0] <= SI;
            end
    end
    assign SO = shreg[Depth_added-1];
endmodule
