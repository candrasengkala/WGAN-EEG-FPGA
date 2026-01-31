/******************************************************************************
 * Module: PE_D
 * 
 * Description:
 *   Diagonal Processing Element with ifmap source selection.
 *   Wrapper around PE_H that adds MUX for ifmap input selection
 *   (from BRAM or from neighbor PE).
 * 
 * Features:
 *   - Ifmap source selection: BRAM or neighbor PE
 *   - Output stationary architecture
 *   - Parameterized data width
 * 
 * Parameters:
 *   DW - Data width (default: 16)
 * 
 * Author: Rizmi Ahmad Raihan
 * Date: January 13, 2026
 ******************************************************************************/

`timescale 1ns / 1ps

module PE_D #(
    parameter DW = 16  // Data width (16-bit fixed-point)
)(
    input wire                   clk,
    input wire                   rst,
    
    // Control signals
    input wire                   en_in,
    input wire                   en_out,
    input wire                   en_psum,
    input wire                   clear_psum,
    
    // Data inputs
    input wire signed [DW-1:0]   weight_in,
    input wire signed [DW-1:0]   ifmap_in_nbr,    // From neighbor PE
    input wire signed [DW-1:0]   ifmap_in_bram,   // From BRAM
    input wire signed [DW-1:0]   output_in,
    
    // Control signals
    input wire                   ifmap_sel_ctrl,      // 1 = BRAM, 0 = Neighbor PE
    input wire                   output_eject_ctrl,   // Controlling passing outputs
    
    // Outputs (connection to neighboring PEs)
    output wire signed [DW-1:0]  weight_out, 
    output wire signed [DW-1:0]  ifmap_out,
    output wire signed [DW-1:0]  output_out
);

    // Selected ifmap input
    wire signed [DW-1:0] ifmap_in;
    assign ifmap_in = ifmap_sel_ctrl ? ifmap_in_bram : ifmap_in_nbr;
    
    // Instantiate base PE design
    PE_H #(
        .DW(DW)
    ) base_design (
        .clk(clk),
        .rst(rst),
        .en_in(en_in),
        .en_out(en_out),
        .en_psum(en_psum),
        .clear_psum(clear_psum),
        .weight_in(weight_in),
        .ifmap_in(ifmap_in),           // Selected ifmap input
        .output_in(output_in),
        .output_eject_ctrl(output_eject_ctrl),
        .weight_out(weight_out),
        .ifmap_out(ifmap_out),
        .output_out(output_out)
    );

endmodule