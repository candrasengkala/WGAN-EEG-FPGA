`timescale 1ns / 1ps
// 16-to-1 Multiplexer
// Menggunakan case statement untuk sintesis yang optimal (tidak cascade, hemat area)

module mux16to1 #(
    parameter DATA_WIDTH = 16    // Lebar data yang di-mux
)(
    input wire [DATA_WIDTH-1:0] in_0,
    input wire [DATA_WIDTH-1:0] in_1,
    input wire [DATA_WIDTH-1:0] in_2,
    input wire [DATA_WIDTH-1:0] in_3,
    input wire [DATA_WIDTH-1:0] in_4,
    input wire [DATA_WIDTH-1:0] in_5,
    input wire [DATA_WIDTH-1:0] in_6,
    input wire [DATA_WIDTH-1:0] in_7,
    input wire [DATA_WIDTH-1:0] in_8,
    input wire [DATA_WIDTH-1:0] in_9,
    input wire [DATA_WIDTH-1:0] in_10,
    input wire [DATA_WIDTH-1:0] in_11,
    input wire [DATA_WIDTH-1:0] in_12,
    input wire [DATA_WIDTH-1:0] in_13,
    input wire [DATA_WIDTH-1:0] in_14,
    input wire [DATA_WIDTH-1:0] in_15,
    input wire [3:0] sel,                     // Select line (4-bit untuk 16 input)
    output reg [DATA_WIDTH-1:0] data_out      // Output data
);

    // Menggunakan case statement untuk mux yang optimal
    // Synthesis tool akan menghasilkan struktur parallel, bukan cascade
    // Menghemat area dan meningkatkan timing
    
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
