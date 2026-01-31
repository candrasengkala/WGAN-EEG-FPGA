/******************************************************************************
 * Module: top_lvl
 * 
 * Description:
 *   Top-level systolic array module without control logic.
 *   Implements 16x16 output-stationary systolic array with diagonal and
 *   horizontal PEs for transposed convolution acceleration.
 * 
 * Features:
 *   - 16x16 PE array (256 PEs total)
 *   - Diagonal PEs (PE_D) on main diagonal with ifmap source selection
 *   - Horizontal PEs (PE_H) for remaining positions
 *   - Weight and ifmap propagation through array
 *   - Diagonal output extraction for partial sum accumulation
 *   - Parameterized data width and array dimension
 * 
 * Parameters:
 *   DW        - Data width (default: 16)
 *   Dimension - Array dimension (default: 16)
 * 
 * Author: Rizmi Ahmad Raihan
 * Date: January 13, 2026
 ******************************************************************************/


module top_lvl #(
    parameter DW = 16,
    parameter Dimension = 16
)(
    input  wire clk,
    input  wire rst,

    // Control
    input wire en_cntr,
    input wire [Dimension*Dimension - 1 : 0] en_in,
    input wire [Dimension*Dimension - 1 : 0] en_out,
    input wire [Dimension*Dimension - 1 : 0] en_psum,
    input wire [Dimension*Dimension - 1 : 0] clear_psum, // DIPERBAIKI: Tambahkan port

    input  wire [Dimension-1:0] ifmaps_sel,
    input  wire [Dimension-1:0] output_eject_ctrl,

    // Inputs
    input  wire signed [DW*Dimension-1:0] weight_in,
    input  wire signed [DW*Dimension-1:0] ifmap_in,

    output wire done_count,
    // Outputs
    output wire signed [DW*Dimension-1:0] output_out,
    output wire signed [DW*Dimension-1:0] diagonal_out
);

    // Internal PE interconnects
    wire signed [DW-1:0] weight_wires [0:Dimension-1][0:Dimension-1];
    wire signed [DW-1:0] ifmap_wires  [0:Dimension-1][0:Dimension-1];
    wire signed [DW-1:0] output_wires [0:Dimension-1][0:Dimension-1];

    // DIPERBAIKI: Control signals harus 1-bit wire, bukan signed [DW-1:0]!
    wire en_in_wires [0:Dimension-1][0:Dimension-1];
    wire en_psum_wires [0:Dimension-1][0:Dimension-1];
    wire en_out_wires [0:Dimension-1][0:Dimension-1];
    wire clear_psum_wires [0:Dimension-1][0:Dimension-1];

    genvar i, j;
    
    // Dummy done_count karena counter tidak digunakan
    assign done_count = 1'b0;
    
    // ============================================================
    // Unpack 1D control inputs to 2D wire arrays
    // ============================================================
    generate
        for (i = 0; i < Dimension; i = i + 1) begin : GEN_UNPACK_ROW
            for (j = 0; j < Dimension; j = j + 1) begin : GEN_UNPACK_COL
                assign en_in_wires[i][j] = en_in[i*Dimension + j];
                assign en_psum_wires[i][j] = en_psum[i*Dimension + j];
                assign en_out_wires[i][j] = en_out[i*Dimension + j];
                assign clear_psum_wires[i][j] = clear_psum[i*Dimension + j];
            end
        end
    endgenerate
    
    // ============================================================
    // Diagonal PEs (PE_D)
    // ============================================================
    
    // PE_D[0] - Special case (first diagonal, no neighbor input)
    PE_D #(.DW(DW)) pe_d_0 (
        .clk(clk),
        .rst(rst),
        .en_in(en_in_wires[0][0]),
        .en_psum(en_psum_wires[0][0]),
        .en_out(en_out_wires[0][0]),
        .clear_psum(clear_psum_wires[0][0]),
        .weight_in(weight_in[DW-1 : 0]),
        .ifmap_in_bram(ifmap_in[DW-1 : 0]),
        .ifmap_in_nbr({DW{1'b0}}),      // No neighbor for PE[0]
        .output_in({DW{1'b0}}),          // No output from north
        .ifmap_sel_ctrl(ifmaps_sel[0]),
        .output_eject_ctrl(output_eject_ctrl[0]),
        .weight_out(weight_wires[0][0]),
        .ifmap_out(ifmap_wires[0][0]),
        .output_out(output_wires[0][0])
    );
    
    // PE_D[1..15] - General case (with neighbor connections)
    generate
        for (i = 1; i < Dimension; i = i + 1) begin : GEN_DIAG
            PE_D #(.DW(DW)) pe_d (
                .clk(clk),
                .rst(rst),
                .en_in(en_in_wires[i][i]),
                .en_psum(en_psum_wires[i][i]),
                .en_out(en_out_wires[i][i]),
                .clear_psum(clear_psum_wires[i][i]),
                .weight_in(weight_in[DW*(i+1)-1 : DW*i]),
                .ifmap_in_bram(ifmap_in[DW*(i+1)-1 : DW*i]),
                .ifmap_in_nbr(ifmap_wires[i-1][i-1]),  // From previous diagonal PE
                .output_in(output_wires[i-1][i]),       // From north (upper triangle)
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
    
    // Row 0 - Special case (no north input)
    generate
        for (j = 1; j < Dimension; j = j + 1) begin : GEN_UPPER_ROW0
            PE_H #(.DW(DW)) pe_h (
                .clk(clk),
                .rst(rst),
                .en_in(en_in_wires[0][j]),
                .en_out(en_out_wires[0][j]),
                .en_psum(en_psum_wires[0][j]),
                .clear_psum(clear_psum_wires[0][j]),
                .weight_in(weight_wires[1][j]),      // From south
                .ifmap_in(ifmap_wires[0][j-1]),      // From west
                .output_in({DW{1'b0}}),              // No north for row 0
                .output_eject_ctrl(output_eject_ctrl[0]),
                .weight_out(weight_wires[0][j]),
                .ifmap_out(ifmap_wires[0][j]),
                .output_out(output_wires[0][j])
            );
        end
    endgenerate
    
    // Rows 1..14 - General case
    generate
        for (i = 1; i < Dimension-1; i = i + 1) begin : GEN_UPPER_ROW
            for (j = i+1; j < Dimension; j = j + 1) begin : GEN_UPPER_COL
                PE_H #(.DW(DW)) pe_h (
                    .clk(clk),
                    .rst(rst),
                    .en_in(en_in_wires[i][j]),
                    .en_out(en_out_wires[i][j]),
                    .en_psum(en_psum_wires[i][j]),
                    .clear_psum(clear_psum_wires[i][j]),
                    .weight_in(weight_wires[i+1][j]),    // From south
                    .ifmap_in(ifmap_wires[i][j-1]),      // From west
                    .output_in(output_wires[i-1][j]),    // From north
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
                    .en_in(en_in_wires[i][j]),
                    .en_out(en_out_wires[i][j]),
                    .en_psum(en_psum_wires[i][j]),
                    .clear_psum(clear_psum_wires[i][j]),
                    
                    .weight_in(weight_wires[i-1][j]),
                    .ifmap_in(ifmap_wires[i][j+1]),
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

    // ============================================================
    // Wire mapping for control signals
    // ============================================================
    generate
        for (i = 0; i < Dimension; i = i + 1) begin : EN_IO_ROWS
            for (j = 0; j < Dimension; j = j + 1) begin : EN_IO_COLUMNS
                assign en_in_wires[i][j] = en_in[i*Dimension + j];
                assign en_psum_wires[i][j] = en_psum[i*Dimension + j];
                assign en_out_wires[i][j] = en_out[i*Dimension + j];
                assign clear_psum_wires[i][j] = clear_psum[i*Dimension + j];
            end
        end
    endgenerate

    // ============================================================
    // Expose diagonal PE outputs
    // ============================================================
    generate
        for (i = 0; i < Dimension; i = i + 1) begin : GEN_DIAG_OUTPUT
            assign diagonal_out[DW*(i+1)-1 : DW*i] = output_wires[i][i];
        end
    endgenerate

endmodule