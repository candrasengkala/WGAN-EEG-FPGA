// ============================================================
// Parameterized register with enable and synchronous reset
// ============================================================
module reg_en_rst #(
    parameter WIDTH = 1
)(
    input  wire              clk,
    input  wire              rst,   // synchronous reset
    input  wire              en,    // write enable
    input  wire [WIDTH-1:0]  d,
    output reg  [WIDTH-1:0]  q = 0
);

    always @(posedge clk) begin
        if (!rst)
            q <= {WIDTH{1'b0}};
        else if (en)
            q <= d;
    end

endmodule
