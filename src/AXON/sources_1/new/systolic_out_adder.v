module systolic_out_adder #(
    parameter Dimension = 16,
    parameter DW = 16
)(
    input  wire [Dimension*DW-1:0] in_a,
    input  wire [Dimension*DW-1:0] in_b,
    output wire [Dimension*DW-1:0] out_val
);

    integer i;
    reg [DW-1:0] hasil [0:Dimension-1];

    // ----------------------------------------
    // Lane-wise addition
    // ----------------------------------------
    always @(*) begin
        for (i = 0; i < Dimension; i = i + 1) begin
            hasil[i] = in_a[i*DW +: DW] + in_b[i*DW +: DW];
        end
    end

    // ----------------------------------------
    // Pack array back into vector
    // ----------------------------------------
    genvar j;
    generate
        for (j = 0; j < Dimension; j = j + 1) begin : pack_out
            assign out_val[j*DW +: DW] = hasil[j];
        end
    endgenerate

endmodule
