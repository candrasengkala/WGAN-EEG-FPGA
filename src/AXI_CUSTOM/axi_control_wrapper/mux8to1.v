`timescale 1ns / 1ps
// 8-to-1 Multiplexer
// Menggunakan case statement untuk sintesis yang optimal (tidak cascade, hemat area)

module mux8to1 #(
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
    input wire [2:0] sel,                     // Select line (3-bit untuk 8 input)
    output reg [DATA_WIDTH-1:0] data_out      // Output data
);

    // Menggunakan case statement untuk mux yang optimal
    // Synthesis tool akan menghasilkan struktur parallel, bukan cascade
    // Menghemat area dan meningkatkan timing
    
    always @(*) begin
        case (sel)
            3'd0:  data_out = in_0;
            3'd1:  data_out = in_1;
            3'd2:  data_out = in_2;
            3'd3:  data_out = in_3;
            3'd4:  data_out = in_4;
            3'd5:  data_out = in_5;
            3'd6:  data_out = in_6;
            3'd7:  data_out = in_7;
            default: data_out = {DATA_WIDTH{1'b0}};  // Default output = 0
        endcase
    end

endmodule
