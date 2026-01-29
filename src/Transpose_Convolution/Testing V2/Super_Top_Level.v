`timescale 1ns / 1ps

/******************************************************************************
 * Module: Super_TOP_Level
 * * Description:
 * Top-level integration of the 5 specific modules requested:
 * 1. Weight_BRAM_Top
 * 2. Ifmap_BRAM_Top
 * 3. Transpose_top
 * 4. BRAM_Read_Modify_Top (contains Accumulation_Unit)
 * * * Logic:
 * - All Control Signals (Write/Read/Compute) are EXTERNAL INPUTS.
 * - Weight BRAM Output -> Transpose Top (Direct Connect)
 * - Ifmap BRAM Output  -> Transpose Top (Broadcast to all inputs)
 * - Transpose Top Output -> BRAM_Read_Modify_Top (Accumulation)
 * ******************************************************************************/

module Super_TOP_Level #(
    parameter DW         = 16,
    parameter NUM_BRAMS  = 16,  // Dimension
    parameter W_ADDR_W   = 10,  // Weight BRAM Address Width
    parameter I_ADDR_W   = 10,  // Ifmap BRAM Address Width
    parameter O_ADDR_W   = 9    // Output/Accumulation BRAM Address Width
)(
    input  wire          clk,
    input  wire          rst_n,

    // ========================================================================
    // 1. WEIGHT BRAM INTERFACE (External Control)
    // ========================================================================
    // Write Port (from Wrapper/External)
    input  wire [NUM_BRAMS-1:0]              w_we,
    input  wire [NUM_BRAMS*W_ADDR_W-1:0]     w_addr_wr_flat,
    input  wire signed [NUM_BRAMS*DW-1:0]    w_din_flat,
    
    // Read Port (from Counter/External)
    input  wire [NUM_BRAMS-1:0]              w_re,
    input  wire [NUM_BRAMS*W_ADDR_W-1:0]     w_addr_rd_flat,

    // ========================================================================
    // 2. IFMAP BRAM INTERFACE (External Control)
    // ========================================================================
    // Write Port (from Wrapper/External)
    input  wire [NUM_BRAMS-1:0]              if_we,
    input  wire [NUM_BRAMS*I_ADDR_W-1:0]     if_addr_wr_flat,
    input  wire signed [NUM_BRAMS*DW-1:0]    if_din_flat,
    
    // Read Port (from Counter/External)
    input  wire [NUM_BRAMS-1:0]              if_re,
    input  wire [NUM_BRAMS*I_ADDR_W-1:0]     if_addr_rd_flat,
    input  wire [3:0]                        ifmap_sel, // Selector for MUX

    // ========================================================================
    // 3. COMPUTE CONTROL INTERFACE (From FSM/External)
    // ========================================================================
    input  wire [NUM_BRAMS-1:0]              en_weight_load,
    input  wire [NUM_BRAMS-1:0]              en_ifmap_load,
    input  wire [NUM_BRAMS-1:0]              en_psum,
    input  wire [NUM_BRAMS-1:0]              clear_psum,
    input  wire [NUM_BRAMS-1:0]              en_output,
    input  wire [NUM_BRAMS-1:0]              ifmap_sel_ctrl,
    input  wire [4:0]                        done_select, // MUX selector for Transpose Output

    // ========================================================================
    // 4. MAPPING CONFIGURATION (From MM2IM/External)
    // ========================================================================
    input  wire [NUM_BRAMS-1:0]              cmap,
    input  wire [NUM_BRAMS*14-1:0]           omap_flat,

    // ========================================================================
    // 5. RESULT READ INTERFACE (External Access)
    // ========================================================================
    input  wire                              ext_read_mode,
    input  wire [NUM_BRAMS*O_ADDR_W-1:0]     ext_read_addr_flat,
    output wire signed [NUM_BRAMS*DW-1:0]    ext_read_data_flat
);

    // ========================================================================
    // INTERNAL INTERCONNECTS
    // ========================================================================
    
    // Weight BRAM -> Transpose Top
    wire signed [NUM_BRAMS*DW-1:0] weight_data_flat;
    
    // Ifmap BRAM -> Transpose Top (Broadcast Logic)
    wire signed [DW-1:0]           ifmap_data_single;
    wire signed [NUM_BRAMS*DW-1:0] ifmap_data_broadcast;
    
    // Transpose Top -> BRAM Read Modify Top (Accumulation)
    wire signed [DW-1:0]           result_partial_sum;
    wire [3:0]                     col_id;
    wire                           partial_valid;

    // ========================================================================
    // BROADCAST LOGIC (Ifmap Single Output -> 16 Inputs)
    // ========================================================================
    genvar k;
    generate
        for(k=0; k<NUM_BRAMS; k=k+1) begin : IFMAP_BROADCAST
            assign ifmap_data_broadcast[k*DW +: DW] = ifmap_data_single;
        end
    endgenerate

    // ========================================================================
    // INSTANTIATION 1: WEIGHT BRAM TOP
    // ========================================================================
    Weight_BRAM_Top #(
        .DW(DW), 
        .NUM_BRAMS(NUM_BRAMS), 
        .ADDR_WIDTH(W_ADDR_W)
    ) u_weight_bram (
        .clk(clk), 
        .rst_n(rst_n),
        // Write Port
        .w_we(w_we), 
        .w_addr_wr_flat(w_addr_wr_flat), 
        .w_din_flat(w_din_flat),
        // Read Port
        .w_re(w_re), 
        .w_addr_rd_flat(w_addr_rd_flat),
        // Output
        .weight_out_flat(weight_data_flat)
    );

    // ========================================================================
    // INSTANTIATION 2: IFMAP BRAM TOP
    // ========================================================================
    ifmap_BRAM_Top #(
        .DW(DW), 
        .NUM_BRAMS(NUM_BRAMS), 
        .ADDR_WIDTH(I_ADDR_W)
    ) u_ifmap_bram (
        .clk(clk), 
        .rst_n(rst_n),
        // Write Port
        .if_we(if_we), 
        .if_addr_wr_flat(if_addr_wr_flat), 
        .if_din_flat(if_din_flat),
        // Read Port
        .if_re(if_re), 
        .if_addr_rd_flat(if_addr_rd_flat), 
        .ifmap_sel(ifmap_sel),
        // Output (Single)
        .ifmap_out(ifmap_data_single)
    );

    // ========================================================================
    // INSTANTIATION 3: TRANSPOSE TOP (COMPUTE)
    // ========================================================================
    Transpose_top #(
        .DW(DW), 
        .Dimension(NUM_BRAMS)
    ) u_compute_engine (
        .clk(clk), 
        .rst_n(rst_n),
        // Data Inputs
        .weight_in(weight_data_flat), 
        .ifmap_in(ifmap_data_broadcast),
        // Control Inputs
        .en_weight_load(en_weight_load), 
        .en_ifmap_load(en_ifmap_load),
        .en_psum(en_psum), 
        .clear_psum(clear_psum),
        .en_output(en_output), 
        .ifmap_sel_ctrl(ifmap_sel_ctrl),
        .done_select(done_select),
        // Outputs
        .result_out(result_partial_sum), 
        .col_id(col_id), 
        .partial_valid(partial_valid)
    );

    // ========================================================================
    // INSTANTIATION 4: BRAM READ MODIFY TOP (ACCUMULATION & OUTPUT)
    // ========================================================================
    BRAM_Read_Modify_Top #(
        .DW(DW), 
        .NUM_BRAMS(NUM_BRAMS), 
        .ADDR_WIDTH(O_ADDR_W)
    ) u_output_storage (
        .clk(clk), 
        .rst_n(rst_n),
        // Inputs from Compute
        .partial_in(result_partial_sum), 
        .col_id(col_id), 
        .partial_valid(partial_valid),
        // Mapping Configuration
        .cmap(cmap), 
        .omap_flat(omap_flat),
        // External Read Interface
        .ext_read_mode(ext_read_mode), 
        .ext_read_addr_flat(ext_read_addr_flat),
        .bram_read_data_flat(ext_read_data_flat),
        // Read Address Monitoring (Optional/Unused in port list)
        .bram_read_addr_flat() 
    );

endmodule