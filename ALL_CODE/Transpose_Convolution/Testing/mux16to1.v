/******************************************************************************
 * Module: mux16to1
 * 
 * Description:
 *   16-to-1 multiplexer with parameterized data width.
 *   Uses case statement for optimal synthesis (parallel structure).
 * 
 * Features:
 *   - Parameterized data width
 *   - Combinational logic (no latency)
 *   - Synthesizes to parallel MUX structure (not cascaded)
 * 
 * Parameters:
 *   DATA_WIDTH - Width of data being multiplexed (default: 16)
 * 
 * Author: Dharma Anargya Jowandy
 * Date: January 2026
 ******************************************************************************/

`ifndef MUX16TO1_V
`define MUX16TO1_V

`timescale 1ns / 1ps

module mux16to1 #(
    parameter DATA_WIDTH = 16    // Data width
)(
    input wire signed [DATA_WIDTH-1:0] in_0,
    input wire signed [DATA_WIDTH-1:0] in_1,
    input wire signed [DATA_WIDTH-1:0] in_2,
    input wire signed [DATA_WIDTH-1:0] in_3,
    input wire signed [DATA_WIDTH-1:0] in_4,
    input wire signed [DATA_WIDTH-1:0] in_5,
    input wire signed [DATA_WIDTH-1:0] in_6,
    input wire signed [DATA_WIDTH-1:0] in_7,
    input wire signed [DATA_WIDTH-1:0] in_8,
    input wire signed [DATA_WIDTH-1:0] in_9,
    input wire signed [DATA_WIDTH-1:0] in_10,
    input wire signed [DATA_WIDTH-1:0] in_11,
    input wire signed [DATA_WIDTH-1:0] in_12,
    input wire signed [DATA_WIDTH-1:0] in_13,
    input wire signed [DATA_WIDTH-1:0] in_14,
    input wire signed [DATA_WIDTH-1:0] in_15,
    input wire        [3:0]            sel,       // Select line (4-bit for 16 inputs)
    output reg signed [DATA_WIDTH-1:0] data_out   // Output data
);

    // Case statement for optimal MUX synthesis
    // Synthesis tool generates parallel structure (not cascaded)
    // Saves area and improves timing
    
    always @(*) begin
        case (sel)
            4'd0:  data_out = in_0;
            4'd1:  data_out = in_1;
            4'd2:  data_out = in_2;
            4'd3:  data_out = in_3;
            4'd4:  data_out = in_4;
            4'd5:  data_out = in_5;
            4'd6:  data_out = in_6;
            4'd7:  data_out = in_7;
            4'd8:  data_out = in_8;
            4'd9:  data_out = in_9;
            4'd10: data_out = in_10;
            4'd11: data_out = in_11;
            4'd12: data_out = in_12;
            4'd13: data_out = in_13;
            4'd14: data_out = in_14;
            4'd15: data_out = in_15;
            default: data_out = {DATA_WIDTH{1'b0}};  // Default output = 0
        endcase
    end

endmodule

`endif // MUX16TO1_V