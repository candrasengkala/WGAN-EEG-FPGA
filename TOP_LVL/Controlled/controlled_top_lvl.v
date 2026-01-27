/******************************************************************************
 * Module: controlled_top_lvl
 * 
 * Description:
 *   Top-level wrapper that instantiates ifmap, weight, and output BRAM arrays.
 *   Multiplexes control signals between 1D convolution and transposed convolution
 *   modes based on conv_mode signal.
 * 
 * Features:
 *   - Mode selection: conv_mode = 0 (1D Conv), conv_mode = 1 (Transposed Conv)
 *   - Multiplexed control signals for all three BRAM arrays
 *   - Supports independent read/write operations per mode
 * 
 * Author: Dharma Anargya Jowandy
 * Date: January 2026
 ******************************************************************************/

module controlled_top_lvl #(
    parameter DW         = 16,  // Data width (16-bit fixed-point)
    parameter NUM_BRAMS  = 16,  // Number of BRAMs
    parameter ADDR_WIDTH = 10,  // Address width for ifmap
    parameter W_ADDR_WIDTH = 11, // Address width for weight
    parameter O_ADDR_WIDTH = 9,  // Address width for output
    parameter DEPTH = 1024,
    parameter W_DEPTH = 2048,
    parameter O_DEPTH = 512
)(
    input  wire                              clk,
    input  wire                              rst_n,
    
    // ======================================================
    // MODE CONTROL
    // ======================================================
    input  wire                              conv_mode,  // 0 = 1D Conv, 1 = Transposed Conv
    
    // ======================================================
    // 1D CONVOLUTION INTERFACE - IFMAP BRAM
    // ======================================================
    input  wire        [NUM_BRAMS-1:0]       onedconv_if_we,
    input  wire        [NUM_BRAMS*ADDR_WIDTH-1:0] onedconv_if_addr_wr_flat,
    input  wire signed [NUM_BRAMS*DW-1:0]    onedconv_if_din_flat,
    input  wire        [NUM_BRAMS-1:0]       onedconv_if_re,
    input  wire        [NUM_BRAMS*ADDR_WIDTH-1:0] onedconv_if_addr_rd_flat,
    input  wire        [3:0]                 onedconv_ifmap_sel,
    
    // ======================================================
    // TRANSPOSED CONVOLUTION INTERFACE - IFMAP BRAM
    // ======================================================
    input  wire        [NUM_BRAMS-1:0]       transconv_if_we,
    input  wire        [NUM_BRAMS*ADDR_WIDTH-1:0] transconv_if_addr_wr_flat,
    input  wire signed [NUM_BRAMS*DW-1:0]    transconv_if_din_flat,
    input  wire        [NUM_BRAMS-1:0]       transconv_if_re,
    input  wire        [NUM_BRAMS*ADDR_WIDTH-1:0] transconv_if_addr_rd_flat,
    input  wire        [3:0]                 transconv_ifmap_sel,
    
    // ======================================================
    // 1D CONVOLUTION INTERFACE - WEIGHT BRAM
    // ======================================================
    input  wire        [NUM_BRAMS-1:0]       onedconv_w_we,
    input  wire        [NUM_BRAMS*W_ADDR_WIDTH-1:0] onedconv_w_addr_wr_flat,
    input  wire signed [NUM_BRAMS*DW-1:0]    onedconv_w_din_flat,
    input  wire        [NUM_BRAMS-1:0]       onedconv_w_re,
    input  wire        [NUM_BRAMS*W_ADDR_WIDTH-1:0] onedconv_w_addr_rd_flat,
    
    // ======================================================
    // TRANSPOSED CONVOLUTION INTERFACE - WEIGHT BRAM
    // ======================================================
    input  wire        [NUM_BRAMS-1:0]       transconv_w_we,
    input  wire        [NUM_BRAMS*W_ADDR_WIDTH-1:0] transconv_w_addr_wr_flat,
    input  wire signed [NUM_BRAMS*DW-1:0]    transconv_w_din_flat,
    input  wire        [NUM_BRAMS-1:0]       transconv_w_re,
    input  wire        [NUM_BRAMS*W_ADDR_WIDTH-1:0] transconv_w_addr_rd_flat,
    
    // ======================================================
    // 1D CONVOLUTION INTERFACE - OUTPUT BRAM (External Read Only)
    // ======================================================
    input  wire                              onedconv_ext_read_mode,
    input  wire        [NUM_BRAMS*O_ADDR_WIDTH-1:0] onedconv_ext_read_addr_flat,
    
    // ======================================================
    // TRANSPOSED CONVOLUTION INTERFACE - OUTPUT BRAM (Full Interface)
    // ======================================================
    input  wire signed [DW-1:0]              transconv_partial_in,
    input  wire        [3:0]                 transconv_col_id,
    input  wire                              transconv_partial_valid,
    input  wire        [NUM_BRAMS-1:0]       transconv_cmap,
    input  wire        [NUM_BRAMS*14-1:0]    transconv_omap_flat,
    input  wire                              transconv_ext_read_mode,
    input  wire        [NUM_BRAMS*O_ADDR_WIDTH-1:0] transconv_ext_read_addr_flat,
    
    // ======================================================
    // OUTPUTS
    // ======================================================
    output wire signed [DW-1:0]              ifmap_out,
    output wire signed [NUM_BRAMS*DW-1:0]    weight_out_flat,
    output wire signed [NUM_BRAMS*DW-1:0]    bram_read_data_flat,
    output wire        [NUM_BRAMS*O_ADDR_WIDTH-1:0] bram_read_addr_flat
);

    // ======================================================
    // MULTIPLEXED CONTROL SIGNALS - IFMAP BRAM
    // ======================================================
    wire        [NUM_BRAMS-1:0]              if_we;
    wire        [NUM_BRAMS*ADDR_WIDTH-1:0]   if_addr_wr_flat;
    wire signed [NUM_BRAMS*DW-1:0]           if_din_flat;
    wire        [NUM_BRAMS-1:0]              if_re;
    wire        [NUM_BRAMS*ADDR_WIDTH-1:0]   if_addr_rd_flat;
    wire        [3:0]                        ifmap_sel;
    
    assign if_we           = conv_mode ? transconv_if_we           : onedconv_if_we;
    assign if_addr_wr_flat = conv_mode ? transconv_if_addr_wr_flat : onedconv_if_addr_wr_flat;
    assign if_din_flat     = conv_mode ? transconv_if_din_flat     : onedconv_if_din_flat;
    assign if_re           = conv_mode ? transconv_if_re           : onedconv_if_re;
    assign if_addr_rd_flat = conv_mode ? transconv_if_addr_rd_flat : onedconv_if_addr_rd_flat;
    assign ifmap_sel       = conv_mode ? transconv_ifmap_sel       : onedconv_ifmap_sel;
    
    // ======================================================
    // MULTIPLEXED CONTROL SIGNALS - WEIGHT BRAM
    // ======================================================
    wire        [NUM_BRAMS-1:0]              w_we;
    wire        [NUM_BRAMS*W_ADDR_WIDTH-1:0] w_addr_wr_flat;
    wire signed [NUM_BRAMS*DW-1:0]           w_din_flat;
    wire        [NUM_BRAMS-1:0]              w_re;
    wire        [NUM_BRAMS*W_ADDR_WIDTH-1:0] w_addr_rd_flat;
    
    assign w_we           = conv_mode ? transconv_w_we           : onedconv_w_we;
    assign w_addr_wr_flat = conv_mode ? transconv_w_addr_wr_flat : onedconv_w_addr_wr_flat;
    assign w_din_flat     = conv_mode ? transconv_w_din_flat     : onedconv_w_din_flat;
    assign w_re           = conv_mode ? transconv_w_re           : onedconv_w_re;
    assign w_addr_rd_flat = conv_mode ? transconv_w_addr_rd_flat : onedconv_w_addr_rd_flat;
    
    // ======================================================
    // MULTIPLEXED CONTROL SIGNALS - OUTPUT BRAM
    // ======================================================
    // Accumulation signals are TRANSCONV ONLY
    wire signed [DW-1:0]                     partial_in;
    wire        [3:0]                        col_id;
    wire                                     partial_valid;
    wire        [NUM_BRAMS-1:0]              cmap;
    wire        [NUM_BRAMS*14-1:0]           omap_flat;
    
    assign partial_in    = transconv_partial_in;
    assign col_id        = transconv_col_id;
    assign partial_valid = transconv_partial_valid;
    assign cmap          = transconv_cmap;
    assign omap_flat     = transconv_omap_flat;
    
    // External read mode is multiplexed between modes
    wire                                     ext_read_mode;
    wire        [NUM_BRAMS*O_ADDR_WIDTH-1:0] ext_read_addr_flat;
    
    assign ext_read_mode     = conv_mode ? transconv_ext_read_mode     : onedconv_ext_read_mode;
    assign ext_read_addr_flat = conv_mode ? transconv_ext_read_addr_flat : onedconv_ext_read_addr_flat;
    
    // ======================================================
    // IFMAP BRAM INSTANTIATION
    // ======================================================
    ifmap_BRAM_Top #(
        .DW         (DW),
        .NUM_BRAMS  (NUM_BRAMS),
        .ADDR_WIDTH (ADDR_WIDTH),
        .DEPTH      (DEPTH)
    ) u_ifmap_BRAM_Top (
        .clk             (clk),
        .rst_n           (rst_n),
        
        // Write Interface
        .if_we           (if_we),
        .if_addr_wr_flat (if_addr_wr_flat),
        .if_din_flat     (if_din_flat),
        
        // Read Interface
        .if_re           (if_re),
        .if_addr_rd_flat (if_addr_rd_flat),
        .ifmap_sel       (ifmap_sel),
        
        // Output
        .ifmap_out       (ifmap_out)
    );
    
    // ======================================================
    // WEIGHT BRAM INSTANTIATION
    // ======================================================
    Weight_BRAM_Top #(
        .DW         (DW),
        .NUM_BRAMS  (NUM_BRAMS),
        .ADDR_WIDTH (W_ADDR_WIDTH),
        .DEPTH      (W_DEPTH)
    ) u_Weight_BRAM_Top (
        .clk             (clk),
        .rst_n           (rst_n),
        
        // Write Interface
        .w_we            (w_we),
        .w_addr_wr_flat  (w_addr_wr_flat),
        .w_din_flat      (w_din_flat),
        
        // Read Interface
        .w_re            (w_re),
        .w_addr_rd_flat  (w_addr_rd_flat),
        
        // Output
        .weight_out_flat (weight_out_flat)
    );
    
    // ======================================================
    // OUTPUT BRAM INSTANTIATION
    // ======================================================
    BRAM_Read_Modify_Top #(
        .DW         (DW),
        .NUM_BRAMS  (NUM_BRAMS),
        .ADDR_WIDTH (O_ADDR_WIDTH),
        .DEPTH      (O_DEPTH)
    ) u_BRAM_Read_Modify_Top (
        .clk                  (clk),
        .rst_n                (rst_n),
        
        // Systolic Array Interface
        .partial_in           (partial_in),
        .col_id               (col_id),
        .partial_valid        (partial_valid),
        
        // MM2IM Buffer Interface
        .cmap                 (cmap),
        .omap_flat            (omap_flat),
        
        // External Read Control
        .ext_read_mode        (ext_read_mode),
        .ext_read_addr_flat   (ext_read_addr_flat),
        
        // Outputs
        .bram_read_data_flat  (bram_read_data_flat),
        .bram_read_addr_flat  (bram_read_addr_flat)
    );

endmodule