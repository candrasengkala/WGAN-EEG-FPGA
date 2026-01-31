`timescale 1ns / 1ps
/******************************************************************************
 * Module      : mm2im_mapper_final (FIXED)
 * Author      : Dharma Anargya Jowandy
 * Date        : January 2026
 *
 * Description :
 * Memory-Mapped-to-Image (MM2IM) mapping unit for transposed convolution.
 * FIXED VERSION:
 * - row_id dan tile_id di-latch saat start
 * - Menghilangkan pipeline hazard (shift berantai)
 ******************************************************************************/

module mm2im_mapper_final #(
    parameter NUM_PE = 16
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  start,
    input  wire [8:0]            row_id,
    input  wire [5:0]            tile_id,
    input  wire [1:0]            layer_id,

    output reg  [NUM_PE-1:0]      cmap,
    output reg  [NUM_PE*14-1:0]   omap_flat,
    output reg                   done
);

    // =========================================================
    // FIXED TRANSPOSED CONV PARAMETERS
    // =========================================================
    localparam integer STRIDE = 2;
    localparam integer PAD    = 1;
    localparam integer PE     = NUM_PE;

    // =========================================================
    // PER-LAYER PARAMETERS
    // =========================================================
    reg [9:0] out_time;
    reg [7:0] out_ch;
    reg [5:0] tile_max;

    always @(*) begin
        case (layer_id)
            2'd0: begin // d1
                out_time = 10'd64;  out_ch = 8'd128; tile_max = 6'd32;
            end
            2'd1: begin // d2
                out_time = 10'd128; out_ch = 8'd64;  tile_max = 6'd16;
            end
            2'd2: begin // d3
                out_time = 10'd256; out_ch = 8'd32;  tile_max = 6'd8;
            end
            2'd3: begin // d4 (Layer 3)
                out_time = 10'd512; out_ch = 8'd16;  tile_max = 6'd4;
            end
            default: begin
                out_time = 10'd64;  out_ch = 8'd128; tile_max = 6'd32;
            end
        endcase
    end

    // =========================================================
    // PIPELINE CONTROL
    // =========================================================
    reg start_d, start_dd;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            start_d  <= 1'b0;
            start_dd <= 1'b0;
        end else begin
            start_d  <= start;
            start_dd <= start_d;
        end
    end

    // =========================================================
    // LATCH INPUTS (FIX UTAMA)
    // =========================================================
    reg [8:0] row_id_latched;
    reg [5:0] tile_id_latched;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            row_id_latched  <= 9'd0;
            tile_id_latched <= 6'd0;
        end else if (start) begin
            row_id_latched  <= row_id;
            tile_id_latched <= tile_id;
        end
    end

    // =========================================================
    // BASE OUTPUT POSITION (STABLE)
    // =========================================================
    wire signed [11:0] base_pos;
    assign base_pos = $signed({3'b0, row_id_latched}) * STRIDE - PAD;

    // =========================================================
    // INTERNAL OMAP ARRAY
    // =========================================================
    reg [13:0] omap_int [0:NUM_PE-1];

    // =========================================================
    // PARALLEL PE MAPPING
    // =========================================================
    genvar i;
    generate
        for (i = 0; i < PE; i = i + 1) begin : MAP
            wire [1:0] k_pos      = i[1:0];
            wire [1:0] oc_in_tile = i[3:2];

            wire [7:0] channel    = tile_id_latched * 4 + oc_in_tile;
            wire signed [11:0] time_pos = base_pos + k_pos;

            wire valid = (tile_id_latched < tile_max) &&
                         (channel < out_ch) &&
                         (time_pos >= 0) &&
                         (time_pos < out_time);

            wire [3:0] bram_id   = channel[3:0];
            wire [4:0] bram_page = channel[7:4];
            wire [9:0] bram_addr = bram_page * out_time + time_pos[9:0];

            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    cmap[i]     <= 1'b0;
                    omap_int[i] <= 14'h3FFF;
                end else if (start_d) begin
                    cmap[i]     <= valid;
                    omap_int[i] <= valid ? {bram_id, bram_addr} : 14'h3FFF;
                end
            end
        end
    endgenerate

    // =========================================================
    // FLATTEN OMAP
    // =========================================================
    integer j;
    always @(*) begin
        for (j = 0; j < NUM_PE; j = j + 1) begin
            omap_flat[j*14 +: 14] = omap_int[j];
        end
    end

    // =========================================================
    // DONE FLAG
    // =========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            done <= 1'b0;
        else
            done <= start_dd;
    end //

endmodule
