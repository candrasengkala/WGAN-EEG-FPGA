`timescale 1ns / 1ps

/******************************************************************************
 * Module: System_Level_Top (REFACTORED VERSION)
 * 
 * Description:
 *   Top-level system integration with CLEAN separation:
 *   1. AXI Wrappers (Weight & Ifmap loading)
 *   2. Transpose_Control_Top (ALL control logic centralized)
 *   3. Super_TOP_Level (Datapath: BRAMs + Compute + Accumulation)
 *   4. Output_Stream_Manager (Result transmission to PS)
 * 
 * Features:
 *   - Multi-layer support (Layer 0: 8 batches, Layer 1: 4 batches)
 *   - Automatic batch management via Auto_Scheduler
 *   - Output BRAM clearing on layer transition
 *   - AXI Stream output for result transmission
 * 
 * Author: Dharma Anargya Jowandy
 * Date: January 2026
 ******************************************************************************/

module System_Level_Top #(
    parameter DW         = 16,
    parameter NUM_BRAMS  = 16,
    parameter W_ADDR_W   = 11,   // Weight BRAM address width
    parameter I_ADDR_W   = 10,   // Ifmap BRAM address width
    parameter O_ADDR_W   = 9,    // Output BRAM address width
    parameter W_DEPTH    = 2048, // Weight BRAM depth (2^11)
    parameter I_DEPTH    = 1024, // Ifmap BRAM depth (2^10)
    parameter O_DEPTH    = 512,  // Output BRAM depth (2^9)
    parameter Dimension  = 16
)(
    input  wire aclk,
    input  wire aresetn,
    
    // ========================================================================
    // AXI Stream 0 - Weight Loading (from PS via DMA MM2S)
    // ========================================================================
    input  wire [DW-1:0]  s0_axis_tdata,
    input  wire           s0_axis_tvalid,
    output wire           s0_axis_tready,
    input  wire           s0_axis_tlast,
    output wire [DW-1:0]  m0_axis_tdata,
    output wire           m0_axis_tvalid,
    input  wire           m0_axis_tready,
    output wire           m0_axis_tlast,
    
    // ========================================================================
    // AXI Stream 1 - Ifmap Loading (from PS via DMA MM2S)
    // ========================================================================
    input  wire [DW-1:0]  s1_axis_tdata,
    input  wire           s1_axis_tvalid,
    output wire           s1_axis_tready,
    input  wire           s1_axis_tlast,
    output wire [DW-1:0]  m1_axis_tdata,
    output wire           m1_axis_tvalid,
    input  wire           m1_axis_tready,
    output wire           m1_axis_tlast,
    
    // ========================================================================
    // AXI Stream 2 - Output Stream (to PS via DMA S2MM)
    // ========================================================================
    output wire [DW-1:0]  m_output_axis_tdata,
    output wire           m_output_axis_tvalid,
    input  wire           m_output_axis_tready,
    output wire           m_output_axis_tlast,
    
    // ========================================================================
    // External Control & Status
    // ========================================================================
    input  wire           ext_start,           // Manual start trigger
    input  wire [1:0]     ext_layer_id,        // Optional: Manual layer ID
    
    output wire           scheduler_done,      // Processing complete
    output wire [1:0]     current_layer_id,    // Current layer being processed
    output wire [2:0]     current_batch_id,    // Current batch (0-7 or 0-3)
    output wire           all_batches_done,    // All batches for current layer done
    
    // ========================================================================
    // Debug & Status Outputs
    // ========================================================================
    output wire           weight_write_done,
    output wire           weight_read_done,
    output wire           ifmap_write_done,
    output wire           ifmap_read_done,
    output wire [9:0]     weight_mm2s_data_count,
    output wire [9:0]     ifmap_mm2s_data_count,
    output wire [2:0]     weight_parser_state,
    output wire           weight_error_invalid_magic,
    output wire [2:0]     ifmap_parser_state,
    output wire           ifmap_error_invalid_magic,
    output wire           auto_start_active
);

    // ========================================================================
    // INTERNAL WIRES - AXI Wrappers to BRAMs
    // ========================================================================
    
    // Weight BRAM Write Interface
    wire [NUM_BRAMS*DW-1:0]      weight_wr_data_flat;
    wire [W_ADDR_W-1:0]          weight_wr_addr;
    wire [NUM_BRAMS-1:0]         weight_wr_en;
    wire [8*DW-1:0]              weight_rd_data_flat;  // Unused for now
    wire [W_ADDR_W-1:0]          weight_rd_addr;        // Unused for now
    
    // Ifmap BRAM Write Interface
    wire [NUM_BRAMS*DW-1:0]      ifmap_wr_data_flat;
    wire [I_ADDR_W-1:0]          ifmap_wr_addr;
    wire [NUM_BRAMS-1:0]         ifmap_wr_en;
    wire [8*DW-1:0]              ifmap_rd_data_flat;   // Unused for now
    wire [I_ADDR_W-1:0]          ifmap_rd_addr;         // Unused for now
    
    // ========================================================================
    // INTERNAL WIRES - Control to Datapath
    // ========================================================================
    
    // From Transpose_Control_Top to Super_TOP_Level
    wire [NUM_BRAMS-1:0]         w_re;
    wire [NUM_BRAMS*W_ADDR_W-1:0] w_addr_rd_flat;
    wire [NUM_BRAMS-1:0]         if_re;
    wire [NUM_BRAMS*I_ADDR_W-1:0] if_addr_rd_flat;
    wire [3:0]                   ifmap_sel;
    
    wire [NUM_BRAMS-1:0]         en_weight_load;
    wire [NUM_BRAMS-1:0]         en_ifmap_load;
    wire [NUM_BRAMS-1:0]         en_psum;
    wire [NUM_BRAMS-1:0]         clear_psum;
    wire [NUM_BRAMS-1:0]         en_output;
    wire [NUM_BRAMS-1:0]         ifmap_sel_ctrl;
    
    wire [NUM_BRAMS-1:0]         cmap_snapshot;
    wire [NUM_BRAMS*14-1:0]      omap_snapshot;
    
    wire                         clear_output_bram;
    
    // ========================================================================
    // INTERNAL WIRES - Output Manager
    // ========================================================================
    wire                         out_mgr_ext_read_mode;
    wire [NUM_BRAMS*O_ADDR_W-1:0] out_mgr_ext_read_addr_flat;
    wire [NUM_BRAMS*DW-1:0]      ext_read_data_flat;
    
    // ========================================================================
    // INSTANTIATION 1: AXI WEIGHT WRAPPER
    // ========================================================================
    axis_control_wrapper #(
        .BRAM_DEPTH(W_DEPTH),    // Weight BRAM depth = 2048
        .DATA_WIDTH(DW),
        .BRAM_COUNT(NUM_BRAMS),
        .ADDR_WIDTH(W_ADDR_W)
    ) weight_wrapper (
        .aclk(aclk),
        .aresetn(aresetn),
        
        // AXI Stream Slave (from PS)
        .s_axis_tdata(s0_axis_tdata),
        .s_axis_tvalid(s0_axis_tvalid),
        .s_axis_tready(s0_axis_tready),
        .s_axis_tlast(s0_axis_tlast),
        
        // AXI Stream Master (to PS) - unused
        .m_axis_tdata(m0_axis_tdata),
        .m_axis_tvalid(m0_axis_tvalid),
        .m_axis_tready(m0_axis_tready),
        .m_axis_tlast(m0_axis_tlast),
        
        // Status
        .write_done(weight_write_done),
        .read_done(weight_read_done),
        .mm2s_data_count(weight_mm2s_data_count),
        .parser_state(weight_parser_state),
        .error_invalid_magic(weight_error_invalid_magic),
        
        // BRAM Write Interface
        .bram_wr_data_flat(weight_wr_data_flat),
        .bram_wr_addr(weight_wr_addr),
        .bram_wr_en(weight_wr_en),
        
        // BRAM Read Interface (unused)
        .bram_rd_data_flat(weight_rd_data_flat),
        .bram_rd_addr(weight_rd_addr)
    );
    
    // ========================================================================
    // INSTANTIATION 2: AXI IFMAP WRAPPER
    // ========================================================================
    axis_control_wrapper #(
        .BRAM_DEPTH(I_DEPTH),    // Ifmap BRAM depth = 1024
        .DATA_WIDTH(DW),
        .BRAM_COUNT(NUM_BRAMS),
        .ADDR_WIDTH(I_ADDR_W)
    ) ifmap_wrapper (
        .aclk(aclk),
        .aresetn(aresetn),
        
        // AXI Stream Slave (from PS)
        .s_axis_tdata(s1_axis_tdata),
        .s_axis_tvalid(s1_axis_tvalid),
        .s_axis_tready(s1_axis_tready),
        .s_axis_tlast(s1_axis_tlast),
        
        // AXI Stream Master (to PS) - unused
        .m_axis_tdata(m1_axis_tdata),
        .m_axis_tvalid(m1_axis_tvalid),
        .m_axis_tready(m1_axis_tready),
        .m_axis_tlast(m1_axis_tlast),
        
        // Status
        .write_done(ifmap_write_done),
        .read_done(ifmap_read_done),
        .mm2s_data_count(ifmap_mm2s_data_count),
        .parser_state(ifmap_parser_state),
        .error_invalid_magic(ifmap_error_invalid_magic),
        
        // BRAM Write Interface
        .bram_wr_data_flat(ifmap_wr_data_flat),
        .bram_wr_addr(ifmap_wr_addr),
        .bram_wr_en(ifmap_wr_en),
        
        // BRAM Read Interface (unused)
        .bram_rd_data_flat(ifmap_rd_data_flat),
        .bram_rd_addr(ifmap_rd_addr)
    );
    
    // ========================================================================
    // INSTANTIATION 3: TRANSPOSE CONTROL TOP (ALL CONTROL LOGIC)
    // ========================================================================
    Transpose_Control_Top #(
        .DW(DW),
        .NUM_BRAMS(NUM_BRAMS),
        .NUM_PE(Dimension),
        .ADDR_WIDTH(I_ADDR_W)     // Use ifmap address width for scheduler
    ) control_top (
        .clk(aclk),
        .rst_n(aresetn),
        
        // Automation inputs (from AXI wrappers)
        .weight_write_done(weight_write_done),
        .ifmap_write_done(ifmap_write_done),
        
        // External control
        .ext_start(ext_start),
        .ext_layer_id(ext_layer_id),
        
        // Status outputs
        .current_layer_id(current_layer_id),
        .current_batch_id(current_batch_id),
        .scheduler_done(scheduler_done),
        .all_batches_done(all_batches_done),
        .clear_output_bram(clear_output_bram),
        .auto_active(auto_start_active),
        
        // Weight BRAM control
        .w_re(w_re),
        .w_addr_rd_flat(w_addr_rd_flat),
        
        // Ifmap BRAM control
        .if_re(if_re),
        .if_addr_rd_flat(if_addr_rd_flat),
        .ifmap_sel_out(ifmap_sel),
        
        // Systolic array control signals
        .en_weight_load(en_weight_load),
        .en_ifmap_load(en_ifmap_load),
        .en_psum(en_psum),
        .clear_psum(clear_psum),
        .en_output(en_output),
        .ifmap_sel_ctrl(ifmap_sel_ctrl),
        
        // Mapping configuration (to accumulation)
        .cmap_snapshot(cmap_snapshot),
        .omap_snapshot(omap_snapshot),
        .mapper_done_pulse()  // Unused for now
    );
    
    // ========================================================================
    // INSTANTIATION 4: SUPER_TOP_LEVEL (DATAPATH)
    // ========================================================================
    Super_TOP_Level #(
        .DW(DW),
        .NUM_BRAMS(NUM_BRAMS),
        .W_ADDR_W(W_ADDR_W),
        .I_ADDR_W(I_ADDR_W),
        .O_ADDR_W(O_ADDR_W)
    ) datapath (
        .clk(aclk),
        .rst_n(aresetn),
        
        // Weight BRAM interface
        .w_we(weight_wr_en),
        .w_addr_wr_flat({NUM_BRAMS{weight_wr_addr}}),  // Broadcast address
        .w_din_flat(weight_wr_data_flat),
        .w_re(w_re),
        .w_addr_rd_flat(w_addr_rd_flat),
        
        // Ifmap BRAM interface
        .if_we(ifmap_wr_en),
        .if_addr_wr_flat({NUM_BRAMS{ifmap_wr_addr}}),  // Broadcast address
        .if_din_flat(ifmap_wr_data_flat),
        .if_re(if_re),
        .if_addr_rd_flat(if_addr_rd_flat),
        .ifmap_sel(ifmap_sel),
        
        // Compute control signals
        .en_weight_load(en_weight_load),
        .en_ifmap_load(en_ifmap_load),
        .en_psum(en_psum),
        .clear_psum(clear_psum),
        .en_output(en_output),
        .ifmap_sel_ctrl(ifmap_sel_ctrl),
        .done_select(5'd0),  // Mux selector (can be controlled if needed)
        
        // Mapping configuration
        .cmap(cmap_snapshot),
        .omap_flat(omap_snapshot),
        
        // External read interface (from output manager)
        .ext_read_mode(out_mgr_ext_read_mode),
        .ext_read_addr_flat(out_mgr_ext_read_addr_flat),
        .ext_read_data_flat(ext_read_data_flat)
    );
    
    // ========================================================================
    // INSTANTIATION 5: OUTPUT STREAM MANAGER
    // ========================================================================
    output_stream_manager #(
        .DW(DW),
        .NUM_BRAMS(NUM_BRAMS),
        .ADDR_WIDTH(O_ADDR_W),
        .OUTPUT_DEPTH(O_DEPTH)   // Output BRAM depth = 512
    ) output_mgr (
        .clk(aclk),
        .rst_n(aresetn),
        
        // Triggers from control
        .batch_complete(1'b0),              // Not used in this version
        .completed_batch_id(current_batch_id),
        .all_batches_complete(all_batches_done),
        
        // Output BRAM read interface
        .ext_read_mode(out_mgr_ext_read_mode),
        .ext_read_addr_flat(out_mgr_ext_read_addr_flat),
        .bram_read_data_flat(ext_read_data_flat),
        
        // AXI Stream Master (to PS)
        .m_axis_tdata(m_output_axis_tdata),
        .m_axis_tvalid(m_output_axis_tvalid),
        .m_axis_tready(m_output_axis_tready),
        .m_axis_tlast(m_output_axis_tlast),
        
        // Status
        .state_debug(),
        .transmission_active()
    );

endmodule