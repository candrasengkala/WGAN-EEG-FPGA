/******************************************************************************
 * Module      : Weight_BRAM_Top
 * Author      : Dharma Anargya Jowandy
 * Date        : January 2026
 *
 * Description :
 * Top-level wrapper for the weight BRAM subsystem.
 * Instantiates multiple dual-port BRAM banks and exposes fully flattened
 * read and write interfaces for integration with control and compute logic.
 *
 * Key Features :
 * - Multi-BRAM architecture with independent dual-port memories
 * - Separate write and read interfaces
 * - Per-BRAM read enable for power optimization
 * - Flattened ports for Verilog-2001 compatibility
 *
 * Parameters :
 * - DW         : Data width in bits (default: 16)
 * - NUM_BRAMS  : Number of weight BRAM banks (default: 16)
 * - ADDR_WIDTH : Address width per BRAM
 * - DEPTH      : BRAM depth
 *
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