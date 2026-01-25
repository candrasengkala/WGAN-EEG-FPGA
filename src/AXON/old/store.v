module axon_pe #(
    parameter DW = 16,    // data width
    parameter WW = 16,    // weight width
    parameter AW = 16     // accumulator width
)(
    input  wire               clk,
    input  wire               rst,

    // IFMAP inputs
    input  wire [DW-1:0]      ifmap_sram,     // from IFMAP SRAM
    input  wire [DW-1:0]      ifmap_nbr,      // from neighbor PE
    input  wire               sel_sram,       // 1 = SRAM, 0 = neighbor
    input  wire               sel_zero,       // 1 = padding (inject zero)

    // Weight
    input  wire [WW-1:0]      weight_in,

    // Partial sum
    input  wire [AW-1:0]      psum_in,
    output reg  [AW-1:0]      psum_out,

    // Forward IFMAP to neighbors
    output reg  [DW-1:0]      ifmap_out
);

    // -------------------------
    // IFMAP selection (im2col logic)
    // -------------------------
    wire [DW-1:0] ifmap_sel;

    assign ifmap_sel =
        sel_zero ? {DW{1'b0}} :
        sel_sram ? ifmap_sram :
                   ifmap_nbr;

    // -------------------------
    // Registers
    // -------------------------
    reg [DW-1:0] ifmap_reg;
    reg [WW-1:0] weight_reg;

    always @(posedge clk) begin
        if (rst) begin
            ifmap_reg  <= {DW{1'b0}};
            weight_reg <= {WW{1'b0}};
        end else begin
            ifmap_reg  <= ifmap_sel;
            weight_reg <= weight_in;
        end
    end

    // -------------------------
    // MAC
    // -------------------------
    wire signed [DW-1:0] ifmap_s = ifmap_reg;
    wire signed [WW-1:0] weight_s = weight_reg;
    wire signed [DW+WW-1:0] mult = ifmap_s * weight_s;

    always @(posedge clk) begin
        if (rst) begin
            psum_out <= {AW{1'b0}};
        end else begin
            psum_out <= psum_in + mult;
        end
    end

    // -------------------------
    // Forward IFMAP (reuse path)
    // -------------------------
    always @(posedge clk) begin
        if (rst)
            ifmap_out <= {DW{1'b0}};
        else
            ifmap_out <= ifmap_reg;
    end

endmodule
