`timescale 1ns / 1ps
// 1-to-32 Demultiplexer
// Menggunakan case statement untuk sintesis yang optimal (tidak cascade, hemat area)

module demux1to32 #(
    parameter DATA_WIDTH = 16    // Lebar data yang di-demux
)(
    input wire [DATA_WIDTH-1:0] data_in,     // Input data
    input wire [4:0] sel,                     // Select line (5-bit untuk 32 output)
    output reg [DATA_WIDTH-1:0] out_0,
    output reg [DATA_WIDTH-1:0] out_1,
    output reg [DATA_WIDTH-1:0] out_2,
    output reg [DATA_WIDTH-1:0] out_3,
    output reg [DATA_WIDTH-1:0] out_4,
    output reg [DATA_WIDTH-1:0] out_5,
    output reg [DATA_WIDTH-1:0] out_6,
    output reg [DATA_WIDTH-1:0] out_7,
    output reg [DATA_WIDTH-1:0] out_8,
    output reg [DATA_WIDTH-1:0] out_9,
    output reg [DATA_WIDTH-1:0] out_10,
    output reg [DATA_WIDTH-1:0] out_11,
    output reg [DATA_WIDTH-1:0] out_12,
    output reg [DATA_WIDTH-1:0] out_13,
    output reg [DATA_WIDTH-1:0] out_14,
    output reg [DATA_WIDTH-1:0] out_15,
    output reg [DATA_WIDTH-1:0] out_16,
    output reg [DATA_WIDTH-1:0] out_17,
    output reg [DATA_WIDTH-1:0] out_18,
    output reg [DATA_WIDTH-1:0] out_19,
    output reg [DATA_WIDTH-1:0] out_20,
    output reg [DATA_WIDTH-1:0] out_21,
    output reg [DATA_WIDTH-1:0] out_22,
    output reg [DATA_WIDTH-1:0] out_23,
    output reg [DATA_WIDTH-1:0] out_24,
    output reg [DATA_WIDTH-1:0] out_25,
    output reg [DATA_WIDTH-1:0] out_26,
    output reg [DATA_WIDTH-1:0] out_27,
    output reg [DATA_WIDTH-1:0] out_28,
    output reg [DATA_WIDTH-1:0] out_29,
    output reg [DATA_WIDTH-1:0] out_30,
    output reg [DATA_WIDTH-1:0] out_31
);

    // Menggunakan case statement untuk demux yang optimal
    // Synthesis tool akan menghasilkan struktur parallel, bukan cascade
    // Menghemat area dan meningkatkan timing
    
    always @(*) begin
        // Default: semua output = 0
        out_0  = {DATA_WIDTH{1'b0}};
        out_1  = {DATA_WIDTH{1'b0}};
        out_2  = {DATA_WIDTH{1'b0}};
        out_3  = {DATA_WIDTH{1'b0}};
        out_4  = {DATA_WIDTH{1'b0}};
        out_5  = {DATA_WIDTH{1'b0}};
        out_6  = {DATA_WIDTH{1'b0}};
        out_7  = {DATA_WIDTH{1'b0}};
        out_8  = {DATA_WIDTH{1'b0}};
        out_9  = {DATA_WIDTH{1'b0}};
        out_10 = {DATA_WIDTH{1'b0}};
        out_11 = {DATA_WIDTH{1'b0}};
        out_12 = {DATA_WIDTH{1'b0}};
        out_13 = {DATA_WIDTH{1'b0}};
        out_14 = {DATA_WIDTH{1'b0}};
        out_15 = {DATA_WIDTH{1'b0}};
        out_16 = {DATA_WIDTH{1'b0}};
        out_17 = {DATA_WIDTH{1'b0}};
        out_18 = {DATA_WIDTH{1'b0}};
        out_19 = {DATA_WIDTH{1'b0}};
        out_20 = {DATA_WIDTH{1'b0}};
        out_21 = {DATA_WIDTH{1'b0}};
        out_22 = {DATA_WIDTH{1'b0}};
        out_23 = {DATA_WIDTH{1'b0}};
        out_24 = {DATA_WIDTH{1'b0}};
        out_25 = {DATA_WIDTH{1'b0}};
        out_26 = {DATA_WIDTH{1'b0}};
        out_27 = {DATA_WIDTH{1'b0}};
        out_28 = {DATA_WIDTH{1'b0}};
        out_29 = {DATA_WIDTH{1'b0}};
        out_30 = {DATA_WIDTH{1'b0}};
        out_31 = {DATA_WIDTH{1'b0}};
        
        // Case statement untuk routing data_in ke output yang dipilih
        case (sel)
            5'd0:  out_0  = data_in;
            5'd1:  out_1  = data_in;
            5'd2:  out_2  = data_in;
            5'd3:  out_3  = data_in;
            5'd4:  out_4  = data_in;
            5'd5:  out_5  = data_in;
            5'd6:  out_6  = data_in;
            5'd7:  out_7  = data_in;
            5'd8:  out_8  = data_in;
            5'd9:  out_9  = data_in;
            5'd10: out_10 = data_in;
            5'd11: out_11 = data_in;
            5'd12: out_12 = data_in;
            5'd13: out_13 = data_in;
            5'd14: out_14 = data_in;
            5'd15: out_15 = data_in;
            5'd16: out_16 = data_in;
            5'd17: out_17 = data_in;
            5'd18: out_18 = data_in;
            5'd19: out_19 = data_in;
            5'd20: out_20 = data_in;
            5'd21: out_21 = data_in;
            5'd22: out_22 = data_in;
            5'd23: out_23 = data_in;
            5'd24: out_24 = data_in;
            5'd25: out_25 = data_in;
            5'd26: out_26 = data_in;
            5'd27: out_27 = data_in;
            5'd28: out_28 = data_in;
            5'd29: out_29 = data_in;
            5'd30: out_30 = data_in;
            5'd31: out_31 = data_in;
            default: begin
                // Semua output tetap 0 (sudah di-set di atas)
            end
        endcase
    end

endmodule
