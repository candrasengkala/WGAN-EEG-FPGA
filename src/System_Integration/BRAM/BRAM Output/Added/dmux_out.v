module dmux_out #(
    parameter DW = 16,
    parameter Dimension = 16
)
(
    input  wire sel,
    input  wire [Dimension*DW-1:0] in,
    output wire [Dimension*DW-1:0] out_a,
    output wire [Dimension*DW-1:0] out_b
);

    // ----------------------------------------
    // Demultiplex input vector
    // ----------------------------------------
    assign out_a = (sel == 1'b0) ? in : {Dimension*DW{1'b0}};
    assign out_b = (sel == 1'b1) ? in : {Dimension*DW{1'b0}};

endmodule
