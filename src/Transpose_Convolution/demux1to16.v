`timescale 1ns / 1ps

module demux1to16 #(
    parameter DATA_WIDTH = 16
)(
    input wire [DATA_WIDTH-1:0] data_in,
    input wire [3:0] sel,
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
    output reg [DATA_WIDTH-1:0] out_15
);

    always @(*) begin
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

        case (sel)
            4'd0:  out_0  = data_in;
            4'd1:  out_1  = data_in;
            4'd2:  out_2  = data_in;
            4'd3:  out_3  = data_in;
            4'd4:  out_4  = data_in;
            4'd5:  out_5  = data_in;
            4'd6:  out_6  = data_in;
            4'd7:  out_7  = data_in;
            4'd8:  out_8  = data_in;
            4'd9:  out_9  = data_in;
            4'd10: out_10 = data_in;
            4'd11: out_11 = data_in;
            4'd12: out_12 = data_in;
            4'd13: out_13 = data_in;
            4'd14: out_14 = data_in;
            4'd15: out_15 = data_in;
            default: begin end
        endcase
    end

endmodule
