/******************************************************************************
 * Module: ifmap_BRAM_Top
 * 
 * Description:
 *   Top-level wrapper for input feature map (ifmap) BRAM array.
 *   Contains 16 dual-port BRAMs with 16-to-1 MUX for output selection.
 * 
 * Features:
 *   - 16 independent BRAMs (512 x 16-bit each)
 *   - Dual-port: separate write and read interfaces
 *   - Configurable read enable per BRAM (power optimization)
 *   - 16-to-1 MUX for selecting active BRAM output
 * 
 * Parameters:
 *   DW         - Data width (default: 16)
 *   NUM_BRAMS  - Number of BRAMs (default: 16)
 *   ADDR_WIDTH - Address width (default: 9)
 * 
 * Author: Dharma Anargya Jowandy
 * Date: January 2026
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