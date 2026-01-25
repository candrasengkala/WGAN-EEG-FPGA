/******************************************************************************
 * Module: Weight_BRAM_Top
 * 
 * Description:
 *   Top-level wrapper for weight BRAM array.
 *   Contains 16 dual-port BRAMs for weight storage with flattened interfaces.
 * 
 * Features:
 *   - 16 independent BRAMs (512 x 16-bit each)
 *   - Dual-port: separate write and read interfaces
 *   - Configurable read enable per BRAM (power optimization)
 *   - All ports flattened for Verilog-2001 compatibility
 * 
 * Parameters:
 *   DW         - Data width (default: 16)
 *   NUM_BRAMS  - Number of BRAMs (default: 16)
 *   ADDR_WIDTH - Address width (default: 9)
 * 
 * Author: Dharma Anargya Jowandy
 * Date: January 2026
 ******************************************************************************/


module Weight_BRAM_Top #(
    parameter DW         = 16,  // Data width (16-bit fixed-point)
    parameter NUM_BRAMS  = 16,  // Number of weight BRAMs
    parameter ADDR_WIDTH = 11,   // Address width (512 entries)
    parameter DEPTH = 2048
)(
    input  wire                              clk,
    input  wire                              rst_n,

    // -------------------------
    // WRITE INTERFACE (FLAT)
    // -------------------------
    input  wire        [NUM_BRAMS-1:0]       w_we,            // Write enable per BRAM
    input  wire        [NUM_BRAMS*ADDR_WIDTH-1:0] w_addr_wr_flat,  // Write addresses
    input  wire signed [NUM_BRAMS*DW-1:0]    w_din_flat,      // Write data

    // -------------------------
    // READ INTERFACE (FLAT)
    // -------------------------
    input  wire        [NUM_BRAMS-1:0]       w_re,            // Read enable per BRAM
    input  wire        [NUM_BRAMS*ADDR_WIDTH-1:0] w_addr_rd_flat,  // Read addresses

    // -------------------------
    // OUTPUT WEIGHTS (FLAT)
    // -------------------------
    output wire signed [NUM_BRAMS*DW-1:0]    weight_out_flat  // Weight outputs
);

    // ========================================================
    // 16 BRAM INSTANCES
    // ========================================================
    genvar i;
    generate
        for (i = 0; i < NUM_BRAMS; i = i + 1) begin : WEIGHT_BRAM_ARRAY

            simple_dual_two_clocks_512x16 #(
                .DEPTH      (DEPTH),  // Memory depth
                .DATA_WIDTH (DW),   // Data width (16-bit fixed-point)
                .ADDR_WIDTH (ADDR_WIDTH)     // Address width (2^9 = 512)
            ) u_weight_bram (
                // WRITE PORT
                .clka  (clk),
                .ena   (1'b1),
                .wea   (w_we[i]),
                .addra (w_addr_wr_flat[i*ADDR_WIDTH +: ADDR_WIDTH]),
                .dia   (w_din_flat[i*DW +: DW]),

                // READ PORT
                .clkb  (clk),
                .enb   (w_re[i]),
                .addrb (w_addr_rd_flat[i*ADDR_WIDTH +: ADDR_WIDTH]),
                .dob   (weight_out_flat[i*DW +: DW])
            );

        end
    endgenerate

endmodule