/******************************************************************************
 * Module      : BRAM_Read_Modify_Top
 * Author      : Dharma Anargya Jowandy
 * Date        : January 2026
 *
 * Description :
 * Top-level wrapper managing the output BRAM array and accumulation logic.
 * This module integrates a multi-bank BRAM subsystem with an accumulation
 * unit and provides controlled read access for both internal processing
 * and external data extraction.
 *
 * Key Features :
 * - Multi-BRAM Architecture
 *   Implements 16 independent dual-port BRAM banks, each with a depth of
 *   512 entries and 16-bit data width.
 *
 * - Read / Write Arbitration
 *   • Write port exclusively driven by the accumulation unit
 *   • Read port multiplexed between accumulation access and external access
 *
 * - External Read Mode
 *   Supports external BRAM readout (e.g., via AXI Stream or testbench)
 *   for result extraction without interfering with accumulation writes.
 *
 * Parameters :
 * - DW         : Data width in bits (default: 16)
 * - NUM_BRAMS  : Number of BRAM banks (default: 16)
 * - ADDR_WIDTH : Address width per BRAM (default: 9, depth = 512)
 * - DEPTH      : BRAM depth (default: 512)
 *
 ******************************************************************************/



module BRAM_Read_Modify_Top #(
    parameter DW         = 16,  // Data width (16-bit fixed-point)
    parameter NUM_BRAMS  = 16,  // Number of output BRAMs
    parameter ADDR_WIDTH = 9,   // Address width (512 entries)
    parameter DEPTH = 512
)(
    input  wire                              clk,
    input  wire                              rst_n,

    // Input from Systolic Array
    input  wire signed [DW-1:0]              partial_in,
    input  wire        [3:0]                 col_id,
    input  wire                              partial_valid,

    // Input from MM2IM buffers
    input  wire        [NUM_BRAMS-1:0]       cmap,
    input  wire        [NUM_BRAMS*14-1:0]    omap_flat,   // 16 × 14-bit
    
    // ======================================================
    // EXTERNAL READ CONTROL (for AXI Stream or testbench)
    // ======================================================
    input  wire                              ext_read_mode,       // 1 = external read, 0 = accumulation read
    input  wire        [NUM_BRAMS*ADDR_WIDTH-1:0] ext_read_addr_flat, // External read addresses
    
    // ======================================================
    // OUTPUT for AXI Stream (READ PORT)
    // ======================================================
    output wire signed [NUM_BRAMS*DW-1:0]    bram_read_data_flat,  // Read data (flattened)
    output wire        [NUM_BRAMS*ADDR_WIDTH-1:0] bram_read_addr_flat   // Read addresses (monitoring)
);

    // ======================================================
    // Accumulation ↔ BRAM interface (FLATTENED)
    // ======================================================
    wire [NUM_BRAMS*ADDR_WIDTH-1:0] acc_addr_rd_flat;   // Read address from Accumulation Unit
    wire signed [NUM_BRAMS*DW-1:0]  bram_dout_flat;     // Data from BRAM

    wire        [NUM_BRAMS-1:0]     bram_we;
    wire        [NUM_BRAMS*ADDR_WIDTH-1:0] bram_addr_wr_flat;
    wire signed [NUM_BRAMS*DW-1:0]  bram_din_flat;

    // ======================================================
    // MUX for READ ADDRESS
    // ======================================================
    wire [NUM_BRAMS*ADDR_WIDTH-1:0] bram_addr_rd_muxed;
    
    assign bram_addr_rd_muxed = ext_read_mode ? ext_read_addr_flat : acc_addr_rd_flat;
    
    // ======================================================
    // Expose read address currently in use
    // ======================================================
    assign bram_read_addr_flat = bram_addr_rd_muxed;
    
    // ======================================================
    // Assign READ DATA to output
    // ======================================================
    assign bram_read_data_flat = bram_dout_flat;

    // ======================================================
    // Accumulation Unit
    // ======================================================
    accumulation_unit #(
        .DW(DW),
        .NUM_BRAMS(NUM_BRAMS)
    ) u_accumulation (
        .clk               (clk),
        .rst_n             (rst_n),
        .partial_in        (partial_in),
        .col_id            (col_id),
        .partial_valid     (partial_valid),
        .cmap              (cmap),
        .omap_flat         (omap_flat),
        .bram_addr_rd_flat (acc_addr_rd_flat),  // Output from Accumulation
        .bram_dout_flat    (bram_dout_flat),    // Input to Accumulation
        .bram_we           (bram_we),
        .bram_addr_wr_flat (bram_addr_wr_flat),
        .bram_din_flat     (bram_din_flat)
    );

    // ======================================================
    // 16 × BRAM instantiation
    // ======================================================
    genvar i;
    generate
        for (i = 0; i < NUM_BRAMS; i = i + 1) begin : BRAM_ARRAY

            simple_dual_two_clocks_512x16 #(
                .DEPTH      (DEPTH),  // Memory depth
                .DATA_WIDTH (DW),   // Data width (16-bit fixed-point)
                .ADDR_WIDTH (ADDR_WIDTH)     // Address width (2^9 = 512)
            ) bram_i (
                // WRITE PORT (controlled by Accumulation Unit)
                .clka  (clk),
                .ena   (1'b1),
                .wea   (bram_we[i]),
                .addra (bram_addr_wr_flat[i*ADDR_WIDTH +: ADDR_WIDTH]),
                .dia   (bram_din_flat[i*DW +: DW]),

                // READ PORT (MUXed: Accumulation Unit OR External)
                .clkb  (clk),
                .enb   (1'b1),
                .addrb (bram_addr_rd_muxed[i*ADDR_WIDTH +: ADDR_WIDTH]),
                .dob   (bram_dout_flat[i*DW +: DW])
            );

        end
    endgenerate

endmodule