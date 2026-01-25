module multichannel_add #(
    parameter DW = 16
)
(
    input  wire clk,
    input  wire rst,   // active-high reset
    input  wire en,
    input  wire [DW-1:0] din,
    output reg  [DW-1:0] dout
);

    always @(posedge clk) begin
        if (rst) begin
            dout <= {DW{1'b0}};
        end
        else if (en) begin
            dout <= dout + din;
        end
        else begin
            dout <= dout; // hold value
        end
    end

endmodule
