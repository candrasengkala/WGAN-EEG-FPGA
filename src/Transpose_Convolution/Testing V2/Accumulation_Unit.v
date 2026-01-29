`timescale 1ns / 1ps

module Accumulation_Unit #(
    parameter DW = 14,
    parameter Num_PE = 16
)(
    input clk,
    input rst_n,
    input en_psum,
    input clear_psum,
    input [Num_PE*DW-1:0] psum_in,
    output reg [Num_PE*DW-1:0] psum_out
);

    reg [Num_PE*DW-1:0] psum_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            psum_reg <= 0;
        end else if (clear_psum) begin
            psum_reg <= 0;
        end else if (en_psum) begin
            psum_reg <= psum_reg + psum_in;
        end
    end

    assign psum_out = psum_reg;

endmodule
