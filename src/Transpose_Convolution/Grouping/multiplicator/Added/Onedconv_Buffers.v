module Onedconv_Buffers #(
    parameter DW = 16,
    parameter Dimension = 16,
    parameter Depth_added = 16
)(
    input  wire clk,
    input  wire rst,
    
    input  wire mode, // 0: input phase, 1: compute phase

    input  wire [Dimension-1:0]  en_shift_reg_ifmap_input,
    input  wire [Dimension-1:0]  en_shift_reg_weight_input,

    input  wire [Dimension-1:0]  en_shift_reg_ifmap_control,
    input  wire [Dimension-1:0]  en_shift_reg_weight_control,

    input  wire signed [Dimension*DW-1:0] weight_brams_in,       //Serial Inputs 
    input  wire signed [DW-1:0] ifmap_serial_in,        //Serial Inputs

    output wire signed [DW*Dimension-1:0] weight_flat,
    output wire signed [DW*Dimension-1:0] ifmap_flat
);
    wire [Dimension-1:0]  en_shift_reg_ifmap;
    wire [Dimension-1:0]  en_shift_reg_weight;

    /* ============================================================
     * Mode MUX
     * ============================================================ */
    assign en_shift_reg_ifmap  = mode ? en_shift_reg_ifmap_control
                                      : en_shift_reg_ifmap_input;

    assign en_shift_reg_weight = mode ? en_shift_reg_weight_control
                                      : en_shift_reg_weight_input;

    wire signed [DW-1:0] weight_sr [0:Dimension-1];
    wire signed [DW-1:0] ifmap_sr  [0:Dimension-1];
    genvar j;
    generate
        for (j = 0; j < Dimension; j = j + 1) begin : FLATTEN_INPUTS
            assign weight_flat[(j+1)*DW-1 -: DW] = weight_sr[j];
            assign ifmap_flat [(j+1)*DW-1 -: DW] = ifmap_sr[j];
        end
    endgenerate 

    genvar i;
    generate
        for (i = 0; i < Dimension; i = i + 1) begin : INPUT_SHIFT_REGS
            /* ---- Weight shift register ---- */
            shift_reg_input #(
                .DW(DW),
                .Depth_added(Dimension + 1) // Added depth for zero padding. For first shifting, fill it with zero (Logic developed later)
            ) weight_shift (
                .clk   (clk),
                .rst   (rst),
                .clken (en_shift_reg_weight[i]),
                .SI    (weight_brams_in[DW*(i+1)-1 -: DW]),
                .SO    (weight_sr[i])
            );
            /* ---- IFMAP shift register ---- */
            shift_reg_input #(
                .DW(DW),
                .Depth_added(Dimension + 1)
            ) ifmap_shift (
                .clk   (clk), // Sesuai dengan yang mengeluarkannya
                .rst   (rst),
                .clken (en_shift_reg_ifmap[i]),
                .SI    (ifmap_serial_in),
                .SO    (ifmap_sr[i])
            );
        end
    endgenerate
endmodule
module shift_reg_input
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
    always @(negedge clk)begin
        if (!rst) begin
            for (i = 0; i < Depth_added; i = i + 1) shreg[i] <= 0;
        end
        else if (clken) begin
            for (i = 0; i < Depth_added; i = i+1)
                shreg[i+1] <= shreg[i];
                shreg[0] <= SI;
            end
    end
    assign SO = shreg[Depth_added-1];
endmodule
