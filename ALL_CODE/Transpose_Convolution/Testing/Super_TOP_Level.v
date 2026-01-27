/******************************************************************************
 * Module: Super_TOP_Level
 * 
 * Description:
 *   Top-level integration module for complete transposed convolution system.
 *   Integrates all major subsystems: weight/ifmap BRAMs, systolic array,
 *   transpose controller, MM2IM mapper, and output accumulation unit.
 * 
 * Features:
 *   - 16 weight BRAMs (512 x 16-bit each)
 *   - 16 ifmap BRAMs (512 x 16-bit each)
 *   - 16x16 systolic array for transposed convolution
 *   - MM2IM mapper for output channel mapping
 *   - Accumulation unit with 16 output BRAMs
 *   - External read interface for result extraction
 * 
 * Subsystems:
 *   - Weight_BRAM_Top: Weight storage
 *   - Ifmap_BRAM_Top: Input feature map storage
 *   - Transpose_top: Systolic array + FSM
 *   - MM2IM_Top: Mapping calculator
 *   - BRAM_Read_Modify_Top: Output accumulation
 * 
 * Parameters:
 *   DW         - Data width (default: 16)
 *   NUM_BRAMS  - Number of BRAMs (default: 16)
 *   ADDR_WIDTH - BRAM address width (default: 9)
 *   Dimension  - Systolic array dimension (default: 16)
 * 
 * Author: Dharma Anargya Jowandy
 * Date: January 2026
 ******************************************************************************/


module Super_TOP_Level #(
    parameter DW         = 16,  // Data width (16-bit fixed-point)
    parameter NUM_BRAMS  = 16,  // Number of BRAMs
    parameter ADDR_WIDTH = 10,   // BRAM address width (1024 entries)
    parameter Dimension  = 16,  // Systolic array dimension
    parameter DEPTH = 1024       // BRAM depth
)(
    input  wire                              clk,
    input  wire                              rst_n,

    // =========================================================
    // Ifmap BRAM Controller
    // =========================================================
    input  wire [ADDR_WIDTH-1:0]             if_addr_start,
    input  wire [ADDR_WIDTH-1:0]             if_addr_end,
    input  wire [3:0]                        ifmap_sel_in,
    input  wire                              start_ifmap,
    output wire                              if_done,

    // =========================================================
    // Weight BRAM Controller
    // =========================================================
    input  wire [ADDR_WIDTH-1:0]             addr_start,
    input  wire [ADDR_WIDTH-1:0]             addr_end,
    input  wire                              start_weight,
    output wire                              done_weight,

    // =========================================================
    // BRAM Weight Write Interface
    // =========================================================
    input  wire        [NUM_BRAMS-1:0]       w_we,
    input  wire        [NUM_BRAMS*ADDR_WIDTH-1:0] w_addr_wr_flat,
    input  wire signed [NUM_BRAMS*DW-1:0]    w_din_flat,

    // =========================================================
    // BRAM Ifmap Write Interface
    // =========================================================
    input  wire        [NUM_BRAMS-1:0]       if_we,
    input  wire        [NUM_BRAMS*ADDR_WIDTH-1:0] if_addr_wr_flat,
    input  wire signed [NUM_BRAMS*DW-1:0]    if_din_flat,

    // =========================================================
    // Transpose Matrix Controller
    // =========================================================
    input wire                               start_transpose,
    input wire [7:0]                         Instruction_code_transpose,
    input wire [8:0]                         num_iterations,
    output wire [7:0]                        iter_count,
    output wire [4:0]                        done_transpose,

    // =========================================================
    // MM2IM Mapper
    // =========================================================
    input  wire                              start_Mapper,
    input  wire [8:0]                        row_id,
    input  wire [5:0]                        tile_id,
    input  wire [1:0]                        layer_id,
    output wire                              done_mapper,

    // =========================================================
    // External Read Control (for debugging or AXI Stream)
    // =========================================================
    input  wire                              ext_read_mode,
    input  wire        [NUM_BRAMS*ADDR_WIDTH-1:0] ext_read_addr_flat,

    // =========================================================
    // Output (Read Port)
    // =========================================================
    output wire signed [NUM_BRAMS*DW-1:0]    bram_read_data_flat,
    output wire        [NUM_BRAMS*ADDR_WIDTH-1:0] bram_read_addr_flat
);

    // =========================================================
    // Internal Wires
    // =========================================================
    wire signed [DW-1:0]                     transpose_out_mux;
    wire        [3:0]                        col_id;
    wire                                     partial_valid;
    wire        [NUM_BRAMS-1:0]              w_read_enable;
    wire        [NUM_BRAMS-1:0]              if_read_enable;
    wire        [NUM_BRAMS*ADDR_WIDTH-1:0]   w_addr_rd_flat;
    wire signed [NUM_BRAMS*DW-1:0]           weight_out_flat;
    wire        [3:0]                        ifmap_selector;
    wire        [NUM_BRAMS*ADDR_WIDTH-1:0]   if_addr_rd_flat;
    wire        [NUM_BRAMS-1:0]              cmap_snapshot;
    wire        [NUM_BRAMS*14-1:0]           omap_snapshot;
    wire        [4:0]                        done_FSM_Transpose;
    wire signed [DW-1:0]                     ifmap_out;
    
    assign done_transpose = done_FSM_Transpose;
    
    // Ifmap broadcast to systolic array (only PE[0] receives data)
    wire signed [Dimension*DW-1:0] ifmap_in_transpose;
    
    assign ifmap_in_transpose[DW-1:0] = ifmap_out;
    genvar g;
    generate
        for (g = 1; g < Dimension; g = g + 1) begin : GEN_IFMAP_ZERO
            assign ifmap_in_transpose[g*DW +: DW] = {DW{1'b0}};
        end
    endgenerate

    // =========================================================
    // BRAM Read Modify Top (Output Accumulation)
    // =========================================================
    BRAM_Read_Modify_Top #(
        .DW(DW),
        .NUM_BRAMS(NUM_BRAMS),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DEPTH(512)
    ) u_bram_read_modify (
        .clk(clk),
        .rst_n(rst_n),
        .partial_in(transpose_out_mux),
        .col_id(col_id),
        .partial_valid(partial_valid),
        .cmap(cmap_snapshot),
        .omap_flat(omap_snapshot),
        .ext_read_mode(ext_read_mode),
        .ext_read_addr_flat(ext_read_addr_flat),
        .bram_read_data_flat(bram_read_data_flat),
        .bram_read_addr_flat(bram_read_addr_flat)
    );

    // =========================================================
    // Weight BRAM Top
    // =========================================================
    Weight_BRAM_Top #(
        .DW(DW),
        .NUM_BRAMS(NUM_BRAMS),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DEPTH(DEPTH)
    ) Weight_BRAM_Top_inst (
        .clk(clk),
        .rst_n(rst_n),
        .w_we(w_we),
        .w_addr_wr_flat(w_addr_wr_flat),
        .w_din_flat(w_din_flat),
        .w_re(w_read_enable),
        .w_addr_rd_flat(w_addr_rd_flat),
        .weight_out_flat(weight_out_flat)
    );

    // =========================================================
    // Ifmap BRAM Top
    // =========================================================
    ifmap_BRAM_Top #(
        .DW(DW),
        .NUM_BRAMS(NUM_BRAMS),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DEPTH(DEPTH)
    ) ifmap_BRAM_Top_inst (
        .clk(clk),
        .rst_n(rst_n),
        .if_we(if_we),
        .if_addr_wr_flat(if_addr_wr_flat),
        .if_din_flat(if_din_flat),
        .if_re(if_read_enable),
        .if_addr_rd_flat(if_addr_rd_flat),
        .ifmap_sel(ifmap_selector),
        .ifmap_out(ifmap_out)
    );

    // =========================================================
    // Counter Ifmap BRAM
    // =========================================================
    Counter_Ifmap_BRAM #(
        .NUM_BRAMS(NUM_BRAMS),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) Counter_Ifmap_BRAM_inst (
        .clk(clk),
        .rst_n(rst_n),
        .start(start_ifmap),
        .if_addr_start(if_addr_start),
        .if_addr_end(if_addr_end),
        .ifmap_sel_in(ifmap_sel_in),
        .if_re(if_read_enable),
        .if_addr_rd_flat(if_addr_rd_flat),
        .ifmap_sel_out(ifmap_selector),
        .if_done(if_done)
    );

    // =========================================================
    // Counter Weight BRAM
    // =========================================================
    Counter_Weight_BRAM #(
        .NUM_BRAMS(NUM_BRAMS),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) Counter_Weight_BRAM_inst (
        .clk(clk),
        .rst_n(rst_n),
        .start(start_weight),
        .addr_start(addr_start),
        .addr_end(addr_end),
        .w_re(w_read_enable),
        .w_addr_rd_flat(w_addr_rd_flat),
        .done(done_weight)
    );

    // =========================================================
    // Transpose Top (Systolic Array + FSM)
    // =========================================================
    Transpose_top #(
        .DW(DW),
        .Dimension(Dimension)
    ) Transpose_top_inst (
        .clk(clk),
        .rst_n(rst_n),
        .start(start_transpose),
        .Instruction_code(Instruction_code_transpose),
        .num_iterations(num_iterations),
        .weight_in(weight_out_flat),
        .ifmap_in(ifmap_in_transpose),
        .result_out(transpose_out_mux),
        .done(done_FSM_Transpose),
        .iter_count(iter_count),
        .col_id(col_id),
        .partial_valid(partial_valid)
    );

    // =========================================================
    // MM2IM Top (Mapper)
    // =========================================================
    MM2IM_Top #(
        .NUM_PE(Dimension)
    ) MM2IM_Top_inst (
        .clk(clk),
        .rst_n(rst_n),
        .start(start_Mapper),
        .row_id(row_id),
        .tile_id(tile_id),
        .layer_id(layer_id),
        .done_PE(done_FSM_Transpose),
        .cmap_snapshot(cmap_snapshot),
        .omap_snapshot(omap_snapshot),
        .done(done_mapper)
    );

endmodule