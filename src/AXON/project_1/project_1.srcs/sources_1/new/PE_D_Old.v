`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Rizmi Ahmad Raihan
// Create Date: 01/13/2026 10:18:45 AM
// Design Name: Horizontal Processing Element
// Module Name: PE_H
// Project Name: AXON
// Target Devices: PYNQ-Z1
// Tool Versions: 2025.1
// Description: Placed horizontally on the AXON architecture. This architecture is Output Stationary.
// Revision 0.01 - File Created
// Additional Comments:
//////////////////////////////////////////////////////////////////////////////////


module PE_D_Old #(
    parameter DW = 16
)(
    input wire clk,
    input wire rst,
    input wire en_in,
    input wire en_out,
    input wire en_psum, 
    input wire signed [DW-1:0] weight_in,
    input wire signed [DW-1:0] ifmap_in_nbr,
    input wire signed [DW-1:0] ifmap_in_bram,
    input wire signed [DW-1:0] output_in,
    //Control Signals
    input wire ifmap_sel_ctrl, //1 = BRAM, 0 = Neighbor PE
    input wire output_eject_ctrl, //Controlling passing outputs.
    //Outputs, connection to neighboring PEs.
    output wire signed [DW-1:0] weight_out, 
    output wire signed [DW-1:0] ifmap_out,
    output wire signed [DW-1:0] output_out
    );
    wire signed [DW-1:0] ifmap_in; // Selected ifmap input
    assign ifmap_in = ifmap_sel_ctrl ? ifmap_in_bram : ifmap_in_nbr;
    PE_H #(.DW(DW)) base_design (
        .clk(clk),
        .rst(rst),
        .en_in(en_in),
        .en_out(en_out),
        .en_psum(en_psum),
        .weight_in(weight_in),
        .ifmap_in((ifmap_in)), //Selected ifmap input.
        .output_in(output_in),
        .output_eject_ctrl(output_eject_ctrl),
        .weight_out(weight_out),
        .ifmap_out(ifmap_out),
        .output_out(output_out)
    );
    //Menghitung clock cycle untuk mengetahui selesai atau belum adalah IDE BURUK. 
endmodule
