`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Rizmi Ahmad Raihan
// Create Date: 01/13/2026 15:10 
// Design Name: Top Level
// Module Name: PE_H
// Project Name: AXON
// Target Devices: PYNQ-Z1
// Tool Versions: 2025.1
// Description: Complete top level with control logic included (there's FSM on-board!). This code also includes top-level module.
// Revision 0.01 - File Created
// Additional Comments: Naive version of top_lvl_control, not utilising stride = 1 specialities. 
//////////////////////////////////////////////////////////////////////////////////
module top_lvl_control #(
    parameter DW = 16,
    parameter Dimension = 16
)
(
    input wire clk,
    input wire rst,
    input wire en, // Start signal to begin operation. Start rised when loading input is finished
    output wire signed [Dimension-1:0] ifmaps_sel,
    output wire signed [Dimension-1:0] output_eject_ctrl,
    output wire finish // Finish signal to indicate operation completion
    );
    reg finish_reg;
    reg [4:0] counter;
    reg [Dimension-1:0] output_eject_ctrl_reg;
    // Default/placeholder assignments; replace with FSM/control logic.
    assign ifmaps_sel = {Dimension{1'b0}}; // all zeros, Dimension-wide

    assign output_eject_ctrl = {Dimension{1'b0}}; // all zeros, Dimension-wide
    assign finish = 1'b0;
    // Count till K+N - 1 AND then eject for all PEs continued by rising finish (31).
    always @(posedge clk) begin
        if (!rst) begin
            // Reset logic here
            counter <= 5'd0;
        end else if (en) begin // Start is kept active high during operation.
            // Control logic to manage ifmaps_sel, output_eject_ctrl, and finish signals
            counter <= counter + 5'd1;
        end
        if (counter == 5'd31) begin
            // Operation complete
            finish_reg <= 1'b1;
            counter <= 5'd0; // Reset counter or hold as needed
        end
    end
    assign finish = finish_reg;
    //FSM 
    reg [2:0] state_reg, state_next;
    always @(posedge clk) begin
        if (!rst)
        begin
            state_reg <= 0;
        end
        else begin
            state_reg <= state_next;
        end
    end
    always @(*) begin
        case (state_reg)
            0: begin
                if (counter == 5'd31) begin
                    state_next = 1;
                end
                else begin
                    state_next = 0;
                end
            end
        endcase
    end
endmodule

module top_lvl_complete #(
    parameter DW = 16,
    parameter Dimension = 16
)(
    input  wire clk,
    input  wire rst,
    // Control
    input wire start,
    // Inputs
    input  wire signed [DW*Dimension-1:0] weight_in,
    input  wire signed [DW*Dimension-1:0] ifmap_in,
    // Outputs
    // Output signal
    output wire finish,
    // Output proper
    output wire signed [DW*Dimension-1:0] output_out
);
    // Control s
endmodule