/******************************************************************************
 * Module      : ifmap_BRAM_Top
 * Author      : Dharma Anargya Jowandy
 * Date        : January 2026
 *
 * Description :
 * Top-level wrapper for the Input Feature Map (Ifmap) BRAM subsystem.
 * This module instantiates multiple BRAM banks and provides controlled
 * read/write access along with a multiplexed output path.
 *
 * Key Features :
 * - Multi-BRAM Architecture
 *   Implements NUM_BRAMS independent dual-port BRAM banks, each storing
 *   Ifmap data with programmable depth and data width.
 *
 * - Dual-Port Memory Access
 *   Provides independent write and read interfaces to support concurrent
 *   data loading and computation.
 *
 * - Per-BRAM Read Enable Gating
 *   Enables selective activation of BRAM read ports to reduce unnecessary
 *   memory access and improve power efficiency.
 *
 * - Output Multiplexing
 *   Uses a 16-to-1 multiplexer to select the active BRAM read data based
 *   on the Ifmap selector input.
 *
 * Parameters :
 * - DW         : Data width in bits (default: 16)
 * - NUM_BRAMS  : Number of Ifmap BRAM banks (default: 16)
 * - ADDR_WIDTH : Address width per BRAM
 *               (default: 10, depth = 1024)
 * - DEPTH      : BRAM depth (default: 1024)
 *
 ******************************************************************************/



module ifmap_BRAM_Top #(
    parameter DW         = 16,  // Data width (16-bit fixed-point)
    parameter NUM_BRAMS  = 16,  // Number of ifmap BRAMs
    parameter ADDR_WIDTH = 10,   // Address width (512 entries)
    parameter DEPTH = 1024 
)(
    input  wire                              clk,
    input  wire                              rst_n,

    // -------------------------
    // WRITE INTERFACE (FLAT)
    // -------------------------
    input  wire        [NUM_BRAMS-1:0]       if_we,            // Write enable per BRAM
    input  wire        [NUM_BRAMS*ADDR_WIDTH-1:0] if_addr_wr_flat,  // Write addresses
    input  wire signed [NUM_BRAMS*DW-1:0]    if_din_flat,      // Write data

    // -------------------------
    // READ INTERFACE (FLAT)
    // -------------------------
    input  wire        [NUM_BRAMS-1:0]       if_re,            // Read enable per BRAM
    input  wire        [NUM_BRAMS*ADDR_WIDTH-1:0] if_addr_rd_flat,  // Read addresses
    input  wire        [3:0]                 ifmap_sel,        // Select BRAM output

    // -------------------------
    // OUTPUT
    // -------------------------
    output wire signed [DW-1:0]              ifmap_out
);

    // ----------------------------------------
    // Internal flat bus for BRAM outputs
    // ----------------------------------------
    wire signed [NUM_BRAMS*DW-1:0] ifmap_out_flat;

    // ----------------------------------------
    // 16 BRAM INSTANCES
    // ----------------------------------------
    genvar i;
    generate
        for (i = 0; i < NUM_BRAMS; i = i + 1) begin : IFMAP_BRAM_ARRAY

            simple_dual_two_clocks_512x16 #(
                .DEPTH      (DEPTH),  // Memory depth
                .DATA_WIDTH (DW),   // Data width (16-bit fixed-point)
                .ADDR_WIDTH (ADDR_WIDTH)     // Address width (2^9 = 512)
            ) u_ifmap_bram (
                // WRITE PORT
                .clka  (clk),
                .ena   (1'b1),
                .wea   (if_we[i]),
                .addra (if_addr_wr_flat[i*ADDR_WIDTH +: ADDR_WIDTH]),
                .dia   (if_din_flat[i*DW +: DW]),

                // READ PORT
                .clkb  (clk),
                .enb   (if_re[i]),
                .addrb (if_addr_rd_flat[i*ADDR_WIDTH +: ADDR_WIDTH]),
                .dob   (ifmap_out_flat[i*DW +: DW])
            );

        end
    endgenerate

    // ----------------------------------------
    // 16-to-1 MUX (EXPLICIT CONNECTION)
    // ----------------------------------------
    mux16to1 #(
        .DATA_WIDTH(DW)
    ) u_ifmap_mux (
        .in_0  (ifmap_out_flat[  0 +: DW]),
        .in_1  (ifmap_out_flat[ DW +: DW]),
        .in_2  (ifmap_out_flat[ 2*DW +: DW]),
        .in_3  (ifmap_out_flat[ 3*DW +: DW]),
        .in_4  (ifmap_out_flat[ 4*DW +: DW]),
        .in_5  (ifmap_out_flat[ 5*DW +: DW]),
        .in_6  (ifmap_out_flat[ 6*DW +: DW]),
        .in_7  (ifmap_out_flat[ 7*DW +: DW]),
        .in_8  (ifmap_out_flat[ 8*DW +: DW]),
        .in_9  (ifmap_out_flat[ 9*DW +: DW]),
        .in_10 (ifmap_out_flat[10*DW +: DW]),
        .in_11 (ifmap_out_flat[11*DW +: DW]),
        .in_12 (ifmap_out_flat[12*DW +: DW]),
        .in_13 (ifmap_out_flat[13*DW +: DW]),
        .in_14 (ifmap_out_flat[14*DW +: DW]),
        .in_15 (ifmap_out_flat[15*DW +: DW]),
        .sel   (ifmap_sel),
        .data_out (ifmap_out)
    );

endmodule