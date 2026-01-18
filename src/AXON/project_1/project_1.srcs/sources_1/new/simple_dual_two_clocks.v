// Simple Dual-Port Block RAM with Two Clocks
// File: simple_dual_two_clocks.v
module simple_dual_two_clocks 
#(
    parameter DW = 16,
    parameter ADDRESS_LENGTH = 13,
    parameter DEPTH = 8192   
)
(clka,clkb,ena,enb,wea,addra,addrb,dia,dob);
    input clka,clkb,ena,enb,wea;
    input [ADDRESS_LENGTH-1:0] addra,addrb;
    input [DW-1 : 0] dia;
    output [DW-1 : 0] dob;
    reg [DW-1 : 0] ram [DEPTH-1:0];
    reg [DW-1 : 0] dob;
    always @(posedge clka)
    begin
        if (ena) begin
            if (wea)
            ram[addra] <= dia;
        end
    end
    always @(posedge clkb)
    begin
        if (enb)begin
            dob <= ram[addrb];
        end
    end
endmodule