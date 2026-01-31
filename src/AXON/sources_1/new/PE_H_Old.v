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


module PE_H_Old #(
    parameter DW = 16
)(
    //Inputs are exclusively wire.
    input wire clk,
    input wire rst,
    input wire en_in,   //Enable signal for input registers
    input wire en_out,  //Enable signal for output registers
    input wire en_psum, //Enable signal for psum register
    input wire signed [DW-1:0] weight_in,
    input wire signed [DW-1:0] ifmap_in,
    input wire signed [DW-1:0] output_in,
    //Control Signals
    input wire output_eject_ctrl, //Controlling passing outputs.
    //Outputs, connection to neighboring PEs.
    output wire signed [DW-1:0] weight_out, 
    output wire signed [DW-1:0] ifmap_out,
    output wire signed [DW-1:0] output_out
);
// Register initial values. 
reg signed [DW-1:0] ifmap_reg = {DW{1'b0}}, weight_reg = {DW{1'b0}}, psum_reg = {DW{1'b0}}, output_reg = {DW{1'b0}};

wire signed [DW-1:0] psum_now, psum_reg_out;
wire signed [DW-1:0] output_selected;
//Multiplexer for output selection
assign output_selected = output_eject_ctrl ? output_in : psum_reg_out;
//Pipelining registers for ifmaps, psum, and weights. Here describing reset.
// From ChatGPT:
// 4. Why simulators don’t warn you
// Verilog makes this worse because:
// @(posedge clk);
// en = 1;
// looks like it happens at the edge, but it actually happens after the edge in simulation time.
// In hardware, there is no “after the edge” — the decision is already made.
always @(posedge clk) begin
    if (!rst) begin
        ifmap_reg <= {DW{1'b0}};
        weight_reg <= {DW{1'b0}};
        psum_reg <= {DW{1'b0}};
        output_reg <= {DW{1'b0}};
    end else begin
        if (en_in) begin
            ifmap_reg <= ifmap_in;
            weight_reg <= weight_in;
        end 
        if (en_out) begin
            output_reg <= output_selected;
        end
        if (en_psum) begin
            psum_reg <= psum_now;
        end
    end
end
//Intermediate signal for psum register output.
assign psum_reg_out = psum_reg;
//Output assignments
assign weight_out = weight_reg;
assign ifmap_out = ifmap_reg;
assign output_out = output_reg;
//Current psum calculation.
assign psum_now = ifmap_out*weight_out + psum_reg_out;
endmodule
