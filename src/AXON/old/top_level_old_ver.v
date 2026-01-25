//////////////////////////////////////////////////////////////////////////////////
// Engineer: Rizmi Ahmad Raihan
// Create Date: 01/13/2026 1:45:00 PM
// Design Name: Top level *without* control logic.
// Module Name: top_lvl_old_ver
// Project Name: AXON
// Target Devices: PYNQ-Z1
// Tool Versions: 2025.1
// Description: OLD VERSION. DO NOT USE. Generating a square array of PEs in AXON architecture. This architecture is Output Stationary.
// Revision 0.01 - File Created
// Additional Comments:
//////////////////////////////////////////////////////////////////////////////////

module top_lvl_old_ver #(
    parameter DW = 16,
    parameter Dimension = 16
)(
    input wire clk,
    input wire rst,
    //Control signals. Controlled by controller or external source.
    input wire [Dimension-1:0] ifmaps_sel,
    input wire [Dimension-1:0] output_eject_ctrl, 
    //Input values
    input wire signed [DW*Dimension - 1:0] weight_in,
    input wire signed [DW*Dimension - 1:0] ifmap_in,
    output wire signed [DW*Dimension -  1:0] output_out
);
    //Connecting wires between PEs.
    wire signed [DW-1:0] weight_wires [0:Dimension-1][0:Dimension-1]; // Ini dibuat sebagai matriks.
    wire signed [DW-1:0] ifmap_wires [0:Dimension-1][0:Dimension-1];
    wire signed [DW-1:0] output_wires [0:Dimension-1][0:Dimension-1];
    // Add precomputed mean and variance?
    genvar i; // Row variable
    genvar j; // Column variable
    genvar k; // Diagonal variable
    //Warning! There should be NO logical statement inside generate block.
    generate
        for (i = 0; i < Dimension; i = i + 1) begin // Row amount
            for (j = 0; j < Dimension; j = j + 1) // Column amount
            begin
                if (i == j) begin : PE_D_instance
                    PE_D #(
                        .DW(DW)
                    )(
                        .clk(clk),
                        .rst(rst),
                        .weight_in(weight_in[Dimension*(j+1)-1:Dimension*j]), // DW is parametrized using variable j.
                        .ifmap_in_nbr((i == 0) ? {DW{1'b0}} : ifmap_wires[i-1][j-1]), // If first row, connect to zero.
                        .ifmap_in_bram(ifmap_in[Dimension*(j+1)-1:Dimension*j]),
                        .output_in((i == 0) ? {DW{1'b0}} : output_wires[i-1][j]), // If first row, connect to zero.
                        .ifmaps_sel_ctrl(ifmaps_sel[i]),
                        .output_eject_ctrl(output_eject_ctrl[i]),
                        .weight_out(weight_wires[i][j]),
                        .ifmap_out(ifmap_wires[i][j]), 
                        .output_out(output_wires[i][j])
                        );
                end
                else if (i < j) begin : PE_H_instance_1
                    PE_H #(
                    .DW(DW))(
                        .clk(clk),
                        .rst(rst),
                        .weight_in(weight_wires[i+1][j]), // Recieve weight from south-side PE.
                        .ifmap_in(ifmap_wires[i][j-1]), // Recieve ifmap from west-side PE. 
                        .output_in(output_wires[i-1][j]) , // Recieve output from north-side PE.
                        .output_eject_ctrl(output_eject_ctrl[i]), // Control signal from controller.
                        .weight_out(weight_wires[i][j]), 
                        .ifmap_out(ifmap_wires[i][j]),
                        .output_out(output_wires[i][j])
                    );
                end
                else if (i > j) begin : PE_H_instance_2
                    PE_H #(
                    .DW(DW))(
                        .clk(clk),
                        .rst(rst),
                        .weight_in(weight_wires[i-1][j]), // Recieve weight from north-side PE.
                        .ifmap_in(ifmap_wires[i][j+1]), // Recieve ifmap from east-side PE. 
                        .output_in(output_wires[i-1][j]) , // Recieve output from north-side PE.
                        .output_eject_ctrl(output_eject_ctrl[i]), // Control signal from controller.
                        .weight_out(weight_wires[i][j]), 
                        .ifmap_out(ifmap_wires[i][j]),
                        .output_out(output_wires[i][j])
                    );
                end
            end
        end
    endgenerate
    // Instantiate your design here
endmodule