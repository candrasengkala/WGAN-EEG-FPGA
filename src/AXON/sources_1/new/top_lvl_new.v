`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Rizmi Ahmad Raihan
// Create Date: 01/13/2026 14:56 AM
// Design Name: Top Level, without control logic.
// Module Name: PE_H
// Project Name: AXON
// Target Devices: PYNQ-Z1
// Tool Versions: 2025.1
// Description: Placed horizontally on the AXON architecture. This architecture is Output Stationary.
// Revision 0.01 - File Created
// Revision 0.02 - Fixed clear_psum port connection warning (hardcoded alternative)
// Additional Comments: clear_psum is permanently disabled via localparam
//////////////////////////////////////////////////////////////////////////////////

module top_lvl #(
    parameter DW = 16,
    parameter Dimension = 16
)(
    input  wire clk,
    input  wire rst,

    // Control
    input wire en_cntr,
    input wire [Dimension*Dimension - 1 : 0] en_in, //Enable inputs on diagonals
    input wire [Dimension*Dimension - 1 : 0] en_out,
    input wire [Dimension*Dimension - 1 : 0] en_psum, // Enable psum registers on diagonals

    input  wire [Dimension-1:0] ifmaps_sel,
    input  wire [Dimension-1:0] output_eject_ctrl,

    // Inputs
    input  wire signed [DW*Dimension-1:0] weight_in,
    input  wire signed [DW*Dimension-1:0] ifmap_in,

    output wire done_count,
    // Outputs
    output wire signed [DW*Dimension-1:0] output_out
);
    // Local parameter for clear_psum (permanently disabled)
    localparam CLEAR_PSUM = 1'b0;

    // Internal PE interconnects
    wire signed [DW-1:0] weight_wires [0:Dimension-1][0:Dimension-1];
    wire signed [DW-1:0] ifmap_wires  [0:Dimension-1][0:Dimension-1];
    wire signed [DW-1:0] output_wires [0:Dimension-1][0:Dimension-1];

    wire signed en_in_wires [0:Dimension-1][0:Dimension-1];
    wire signed en_psum_wires [0:Dimension-1][0:Dimension-1];
    wire signed en_out_wires [0:Dimension-1][0:Dimension-1];

    genvar i, j;
    counter_top_lvl #(.Dimension(Dimension)) counter_inst (
        .clk(clk),
        .rst(rst),
        .en(en_cntr),
        .done(done_count)
    );
    // ============================================================
    // Diagonal PEs (PE_D)
    // ============================================================
    generate
        for (i = 0; i < Dimension; i = i + 1) begin : GEN_DIAG
            PE_D #(.DW(DW)) pe_d (
                .clk(clk),
                .rst(rst),

                .en_in(en_in_wires[i][i]),
                .en_psum(en_psum_wires[i][i]),
                .en_out(en_out_wires[i][i]),
                .clear_psum(CLEAR_PSUM),
                .weight_in(weight_in[DW*(i+1)-1 : DW*i]),
                .ifmap_in_bram(ifmap_in[DW*(i+1)-1 : DW*i]),

                .ifmap_in_nbr(
                    (i == 0) ? {DW{1'b0}} : ifmap_wires[i-1][i-1]
                ),

                .output_in(
                    (i == 0) ? {DW{1'b0}} : output_wires[i-1][i]
                ),

                .ifmap_sel_ctrl(ifmaps_sel[i]),
                .output_eject_ctrl(output_eject_ctrl[i]),

                .weight_out(weight_wires[i][i]),
                .ifmap_out(ifmap_wires[i][i]),
                .output_out(output_wires[i][i])
            );
        end
    endgenerate

    // ============================================================
    // Upper triangle (i < j)
    // ============================================================
    generate
        for (i = 0; i < Dimension-1; i = i + 1) begin : GEN_UPPER_ROW
            for (j = i+1; j < Dimension; j = j + 1) begin : GEN_UPPER_COL
                PE_H #(.DW(DW)) pe_h (
                    .clk(clk),
                    .rst(rst),
                    .clear_psum(CLEAR_PSUM),
                    .en_in(en_in_wires[i][j]),
                    .en_out(en_out_wires[i][j]),
                    .en_psum(en_psum_wires[i][j]),
                    // From south
                    .weight_in(
                        weight_wires[i+1][j]
                    ),

                    // From west
                    .ifmap_in(
                         ifmap_wires[i][j-1]
                    ),

                    // From north
                    .output_in(
                        (i == 0) ? {DW{1'b0}} : output_wires[i-1][j]
                    ),

                    .output_eject_ctrl(output_eject_ctrl[i]),

                    .weight_out(weight_wires[i][j]),
                    .ifmap_out(ifmap_wires[i][j]),
                    .output_out(output_wires[i][j])
                );
            end
        end
    endgenerate

    // ============================================================
    // Lower triangle (i > j)
    // ============================================================
    generate
        for (i = 1; i < Dimension; i = i + 1) begin : GEN_LOWER_ROW
            for (j = 0; j < i; j = j + 1) begin : GEN_LOWER_COL
                PE_H #(.DW(DW)) pe_h (
                    .clk(clk),
                    .rst(rst),
                    .clear_psum(CLEAR_PSUM),
                    .en_in(en_in_wires[i][j]),
                    .en_out(en_out_wires[i][j]),
                    .en_psum(en_psum_wires[i][j]),
                    // From north
                    .weight_in(weight_wires[i-1][j]),

                    // From east
                    .ifmap_in(ifmap_wires[i][j+1]),

                    // From north
                    .output_in(output_wires[i-1][j]),

                    .output_eject_ctrl(output_eject_ctrl[i]),

                    .weight_out(weight_wires[i][j]),
                    .ifmap_out(ifmap_wires[i][j]),
                    .output_out(output_wires[i][j])
                );
            end
        end
    endgenerate

    // ============================================================
    // Flatten final outputs (bottom row)
    // ============================================================
    generate
        for (i = 0; i < Dimension; i = i + 1) begin : GEN_OUTPUT
            assign output_out[DW*(i+1)-1 : DW*i] =
                output_wires[Dimension-1][i];
        end
    endgenerate

    generate
        for (i = 0; i < Dimension; i = i + 1) begin : EN_IO_ROWS
            for (j = 0; j < Dimension; j = j + 1) begin : EN_IO_COLUMNS
                assign en_in_wires[i][j] = en_in[i*Dimension + j];
                assign en_psum_wires[i][j] = en_psum[i*Dimension + j];
                assign en_out_wires[i][j] = en_out[i*Dimension + j];
            end
        end
    endgenerate

endmodule