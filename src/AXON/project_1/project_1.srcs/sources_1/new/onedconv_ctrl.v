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
module onedconv_ctrl #(
    parameter DW = 16,
    parameter Dimension = 16
)(
    input  wire clk,
    input  wire rst,
    input  wire start,

    input 
    output wire done_all,

    output wire [Dimension-1 : 0] en_shift_reg_ifmap_input,
    output wire [Dimension-1 : 0] en_shift_reg_weight_input,

    output wire [1:0]
    output wire mode
);
    // Control signals
    wire output_val;
    wire out_new_val;

    // Counters to control shift registers
    wire en_ifmap_counter;
    wire en_weight_counter;

    top_lvl_io_control #(
        .DW(DW),
        .Dimension(Dimension)
    ) top_lvl_io_control_inst (
        .clk                    (clk),
        .rst                    (rst),
        .start                  (start),
        .output_val             (output_val),

        .weight_brams_in       (), // Not used here
        .ifmap_serial_in        (), // Not used here

        .en_shift_reg_ifmap_input (en_shift_reg_ifmap_input),
        .en_shift_reg_weight_input(en_shift_reg_weight_input),
        .mode                   (mode),

        .out_new_val            (out_new_val),
        .done_count             (),
        .done_all               (done_all),

        .en_ifmap_counter      (en_ifmap_counter),
        .en_weight_counter     (en_weight_counter)
    );
endmodule