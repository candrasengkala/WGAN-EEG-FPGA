/******************************************************************************
 * Module: mm2im_mapper_final
 * 
 * Description:
 *   Memory Mapped to Image Mapping (MM2IM) calculator for transposed convolution.
 *   Computes channel map (cmap) and output map (omap) for systolic array
 *   processing based on layer parameters and current tile position.
 * 
 * Features:
 *   - Supports 4 deconvolution layers (d1-d4) with different parameters
 *   - Computes valid output positions considering stride and padding
 *   - Generates BRAM addressing for output accumulation
 *   - 2-cycle latency from start to done
 *   - Parallel computation for all 16 PE columns
 * 
 * Layer Parameters:
 *   d1: 32x128   (out_time=64,  out_ch=128)
 *   d2: 64x64    (out_time=128, out_ch=64)
 *   d3: 128x32   (out_time=256, out_ch=32)
 *   d4: 256x16   (out_time=512, out_ch=16)
 * 
 * Fixed Parameters:
 *   STRIDE = 2
 *   PAD    = 1
 * 
 * Parameters:
 *   NUM_PE - Number of PE columns (default: 16)
 * 
 * Author: Dharma Anargya Jowandy
 * Date: January 2026
 ******************************************************************************/

module mm2im_mapper_final #(
    parameter NUM_PE = 16  // Number of PE columns
)(
    input  wire              clk,
    input  wire              rst_n,
    input  wire              start,

    // =========================================================
    // CONTROL INPUTS (ALL 0-BASED)
    // =========================================================

    input  wire [8:0]        row_id,
    // row_id:
    // - 0-based index of input feature map row
    // - valid range depends on layer:
    //   d1: 0 .. 31   (input length 32)
    //   d2: 0 .. 63
    //   d3: 0 .. 127
    //   d4: 0 .. 255
    // - row_id = 0 means first input row
    // - USED IN FORMULA:
    //     base_pos = row_id * STRIDE - PAD

    input  wire [5:0]        tile_id,
    // tile_id:
    // - 0-based index of output channel tile
    // - each tile contains 4 output channels
    // - valid range depends on layer:
    //   d1: 0 .. 31  (128 / 4)
    //   d2: 0 .. 15  (64  / 4)
    //   d3: 0 .. 7   (32  / 4)
    //   d4: 0 .. 3   (16  / 4)

    input  wire [1:0]        layer_id,
    // layer_id:
    //   0 = d1
    //   1 = d2
    //   2 = d3
    //   3 = d4

    // =========================================================
    // OUTPUTS
    // =========================================================

    output reg  [NUM_PE-1:0]      cmap,
    // cmap[i]:
    // - i = 0..15 (PE index)
    // - 1 = (oc,k) at column i is valid (MAC contribution executed)
    // - 0 = column invalid (padding / out of range)

    output reg  [NUM_PE*14-1:0]   omap_flat,
    // omap_flat:
    // - flattened array 16 x 14-bit
    // - entry i (i=0..15):
    //     omap_flat[i*14 +: 14] =
    //       { bram_id[3:0], bram_addr[9:0] }

    output reg                    done
    // done:
    // - asserted 1 cycle AFTER cmap & omap stable
    // - indicates snapshot ready for downstream use
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
    reg [9:0] out_time;   // Output length (Oh)
    reg [7:0] out_ch;     // Number of output channels
    reg [5:0] tile_max;   // Number of valid tiles

    always @(*) begin
        case (layer_id)
            2'd0: begin // d1
                out_time = 10'd64;
                out_ch   = 8'd128;
                tile_max = 6'd32;
            end
            2'd1: begin // d2
                out_time = 10'd128;
                out_ch   = 8'd64;
                tile_max = 6'd16;
            end
            2'd2: begin // d3
                out_time = 10'd256;
                out_ch   = 8'd32;
                tile_max = 6'd8;
            end
            2'd3: begin // d4
                out_time = 10'd512;
                out_ch   = 8'd16;
                tile_max = 6'd4;
            end
            default: begin
                out_time = 10'd64;
                out_ch   = 8'd128;
                tile_max = 6'd32;
            end
        endcase
    end

    // =========================================================
    // START PIPELINE (2 CYCLES)
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
    // BASE OUTPUT POSITION
    // =========================================================
    reg signed [11:0] base_pos;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            base_pos <= 12'sd0;
        else if (start)
            base_pos <= $signed({3'b0, row_id}) * STRIDE - PAD;
        // base_pos = row_id*2 - 1
    end

    // =========================================================
    // INTERNAL OMAP ARRAY
    // =========================================================
    reg [13:0] omap_int [0:NUM_PE-1];

    // =========================================================
    // PARALLEL COLUMN MAPPING
    // =========================================================
    genvar i;
    generate
        for (i = 0; i < PE; i = i + 1) begin : MAP

            wire [1:0] k_pos      = i[1:0];
            // k_pos:
            // - kernel index (0..3)

            wire [1:0] oc_in_tile = i[3:2];
            // oc_in_tile:
            // - output channel offset in tile (0..3)

            wire [7:0] channel    = tile_id * 4 + oc_in_tile;
            // channel:
            // - global output channel index (0-based)

            wire signed [11:0] time_pos = base_pos + k_pos;
            // time_pos:
            // - output time index for (row_id, k)

            wire valid =
                (tile_id < tile_max) &&
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
                end
                else if (start_d) begin
                    cmap[i]     <= valid;
                    omap_int[i] <= valid ? {bram_id, bram_addr} : 14'h3FFF;
                end
            end
        end
    endgenerate

    // =========================================================
    // FLATTEN OMAP ARRAY
    // =========================================================
    integer j;
    always @(*) begin
        for (j = 0; j < NUM_PE; j = j + 1)
            omap_flat[j*14 +: 14] = omap_int[j];
    end

    // =========================================================
    // DONE FLAG
    // =========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            done <= 1'b0;
        else
            done <= start_dd;
    end

endmodule