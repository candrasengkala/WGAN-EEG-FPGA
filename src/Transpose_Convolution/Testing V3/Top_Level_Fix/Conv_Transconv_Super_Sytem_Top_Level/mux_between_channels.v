module mux_between_channels
#(
    parameter DW = 16,
    parameter Inputs = 32,
    parameter Sel_Width = 5
)
(
    input  wire [DW*Inputs-1:0] data_in,   // FIXED width
    input  wire [Sel_Width-1:0] sel,
    output reg  [DW-1:0] data_out           // FIXED width
);

integer i;

always @(*) begin
    data_out = {DW{1'b0}};  // default to avoid latches
    for (i = 0; i < Inputs; i = i + 1) begin
        if (sel == i[Sel_Width-1:0]) begin
            data_out = data_in[i*DW +: DW];
        end
    end
end

endmodule
