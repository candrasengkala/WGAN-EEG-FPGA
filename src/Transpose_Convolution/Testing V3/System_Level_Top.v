`timescale 1ns / 1ps
//halo
/******************************************************************************
 * System_Level_Top (DUAL PARALLEL OUTPUT STREAM)
 * 
 * CRITICAL CHANGE:
 * - Output Manager now triggers BOTH wrappers simultaneously
 * - m0_axis sends BRAM 0-7 (via Weight Wrapper)
 * - m1_axis sends BRAM 8-15 (via Ifmap Wrapper)
 * - PARALLEL transmission for 2x throughput
 ******************************************************************************/

module System_Level_Top #(
    parameter DW         = 16,
    parameter NUM_BRAMS  = 16,
    parameter W_ADDR_W   = 11,
    parameter I_ADDR_W   = 10,
    parameter O_ADDR_W   = 9,
    parameter W_DEPTH    = 2048,
    parameter I_DEPTH    = 1024,
    parameter O_DEPTH    = 512,
    parameter Dimension  = 16
)(
    input  wire aclk,
    input  wire aresetn,
    
    // AXI Stream 0 - Weight (WRITE + READ OUTPUT)
    input  wire [DW-1:0]  s0_axis_tdata,
    input  wire           s0_axis_tvalid,
    output wire           s0_axis_tready,
    input  wire           s0_axis_tlast,
    output wire [DW-1:0]  m0_axis_tdata,
    output wire           m0_axis_tvalid,
    input  wire           m0_axis_tready,
    output wire           m0_axis_tlast,
    
    // AXI Stream 1 - Ifmap (WRITE + READ OUTPUT)
    input  wire [DW-1:0]  s1_axis_tdata,
    input  wire           s1_axis_tvalid,
    output wire           s1_axis_tready,
    input  wire           s1_axis_tlast,
    output wire [DW-1:0]  m1_axis_tdata,
    output wire           m1_axis_tvalid,
    input  wire           m1_axis_tready,
    output wire           m1_axis_tlast,
    
    // Control & Status
    input  wire           ext_start,
    input  wire [1:0]     ext_layer_id,
    output wire           scheduler_done,
    output wire [1:0]     current_layer_id,
    output wire [2:0]     current_batch_id,
    output wire           all_batches_done,
    
    // Status
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
    // Internal Wires
    // ========================================================================
    wire [NUM_BRAMS*DW-1:0]      weight_wr_data_flat;
    wire [W_ADDR_W-1:0]          weight_wr_addr;
    wire [NUM_BRAMS-1:0]         weight_wr_en;
    wire [W_ADDR_W-1:0]          weight_rd_addr;
    
    wire [NUM_BRAMS*DW-1:0]      ifmap_wr_data_flat;
    wire [I_ADDR_W-1:0]          ifmap_wr_addr;
    wire [NUM_BRAMS-1:0]         ifmap_wr_en;
    wire [I_ADDR_W-1:0]          ifmap_rd_addr;
    
    // Scheduler Signals
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
    wire                         batch_complete_from_ctrl;
    
    wire [NUM_BRAMS*DW-1:0]      ext_read_data_flat;
    
    // ========================================================================
    // DUAL STREAM OUTPUT - Header injection wires (SHARED by both wrappers)
    // ========================================================================
    wire [15:0] header_word_0;
    wire [15:0] header_word_1;
    wire [15:0] header_word_2;
    wire [15:0] header_word_3;
    wire [15:0] header_word_4;
    wire [15:0] header_word_5;
    wire        send_header;  // SAME trigger for both!

    // Output Manager read control signals
    wire        out_mgr_trigger_read;
    wire [2:0]  out_mgr_rd_bram_start;
    wire [2:0]  out_mgr_rd_bram_end;
    wire [15:0] out_mgr_rd_addr_count;
    wire        out_mgr_notification_mode;
    
    wire [8*DW-1:0] out_group0_bram_data;  // BRAM 0-7
    wire [8*DW-1:0] out_group1_bram_data;  // BRAM 8-15
    wire [4:0]      done_transpose;
    
    // Datapath read interface
    wire out_mgr_ext_read_mode;
    wire [NUM_BRAMS*O_ADDR_W-1:0] out_mgr_ext_read_addr_flat;
    wire out_mgr_transmission_active;  // NEW: untuk kontrol ext_read_mode

    // FIX: ext_read_mode dikontrol oleh transmission_active
    // - Saat accumulation (transmission_active=0): pakai acc_addr_rd_flat
    // - Saat output (transmission_active=1): pakai ext_read_addr_flat dari wrapper
    assign out_mgr_ext_read_mode = out_mgr_transmission_active;

    // Map addresses for BOTH groups
    genvar k;
    generate
        for(k=0; k<8; k=k+1) begin : MAP_ADDR_GRP0
            assign out_mgr_ext_read_addr_flat[k*O_ADDR_W +: O_ADDR_W] = weight_rd_addr[O_ADDR_W-1:0];
        end
        for(k=8; k<16; k=k+1) begin : MAP_ADDR_GRP1
            assign out_mgr_ext_read_addr_flat[k*O_ADDR_W +: O_ADDR_W] = ifmap_rd_addr[O_ADDR_W-1:0];
        end
    endgenerate

    // Split datapath output to 2 groups
    assign out_group0_bram_data = ext_read_data_flat[8*DW-1 : 0];      // BRAM 0-7
    assign out_group1_bram_data = ext_read_data_flat[16*DW-1 : 8*DW];  // BRAM 8-15

    // ========================================================================
    // WEIGHT WRAPPER - Handles BRAM 0-7 OUTPUT
    // ========================================================================
    axis_control_wrapper #(
        .BRAM_DEPTH(W_DEPTH),
        .DATA_WIDTH(DW),
        .BRAM_COUNT(NUM_BRAMS),
        .ADDR_WIDTH(W_ADDR_W)
    ) weight_wrapper (
        .aclk(aclk),
        .aresetn(aresetn),
        
        .s_axis_tdata(s0_axis_tdata),
        .s_axis_tvalid(s0_axis_tvalid),
        .s_axis_tready(s0_axis_tready),
        .s_axis_tlast(s0_axis_tlast),
        
        .m_axis_tdata(m0_axis_tdata),
        .m_axis_tvalid(m0_axis_tvalid),
        .m_axis_tready(m0_axis_tready),
        .m_axis_tlast(m0_axis_tlast),
        
        // SHARED header from Output Manager
        .header_word_0(header_word_0),
        .header_word_1(header_word_1),
        .header_word_2(header_word_2),
        .header_word_3(header_word_3),
        .header_word_4(header_word_4),
        .header_word_5(header_word_5),
        .send_header(send_header),  // SAME trigger as ifmap!

        // Read control: BRAM 0-7
        .out_mgr_rd_bram_start(out_mgr_rd_bram_start),  // 0
        .out_mgr_rd_bram_end(out_mgr_rd_bram_end),      // 7
        .out_mgr_rd_addr_count(out_mgr_rd_addr_count),  // 512
        .notification_mode(out_mgr_notification_mode),

        .write_done(weight_write_done),
        .read_done(weight_read_done),
        .mm2s_data_count(weight_mm2s_data_count),
        .parser_state(weight_parser_state),
        .error_invalid_magic(weight_error_invalid_magic),

        .bram_wr_data_flat(weight_wr_data_flat),
        .bram_wr_addr(weight_wr_addr),
        .bram_wr_en(weight_wr_en),

        .bram_rd_data_flat(out_group0_bram_data),  // Read from BRAM 0-7
        .bram_rd_addr(weight_rd_addr)
    );

    // ========================================================================
    // IFMAP WRAPPER - Handles BRAM 8-15 OUTPUT
    // ========================================================================
    axis_control_wrapper #(
        .BRAM_DEPTH(I_DEPTH),
        .DATA_WIDTH(DW),
        .BRAM_COUNT(NUM_BRAMS),
        .ADDR_WIDTH(I_ADDR_W)
    ) ifmap_wrapper (
        .aclk(aclk),
        .aresetn(aresetn),
        
        .s_axis_tdata(s1_axis_tdata),
        .s_axis_tvalid(s1_axis_tvalid),
        .s_axis_tready(s1_axis_tready),
        .s_axis_tlast(s1_axis_tlast),
        
        .m_axis_tdata(m1_axis_tdata),
        .m_axis_tvalid(m1_axis_tvalid),
        .m_axis_tready(m1_axis_tready),
        .m_axis_tlast(m1_axis_tlast),
        
        // SHARED header from Output Manager (SAME as weight!)
        .header_word_0(header_word_0),
        .header_word_1(header_word_1),
        .header_word_2(header_word_2),
        .header_word_3(header_word_3),
        .header_word_4(header_word_4),
        .header_word_5(header_word_5),
        .send_header(send_header),  // SAME trigger!

        // Read control: BRAM 8-15 (mapped as 0-7 in wrapper's perspective)
        .out_mgr_rd_bram_start(out_mgr_rd_bram_start),  // 0 (maps to BRAM 8)
        .out_mgr_rd_bram_end(out_mgr_rd_bram_end),      // 7 (maps to BRAM 15)
        .out_mgr_rd_addr_count(out_mgr_rd_addr_count),  // 512
        .notification_mode(out_mgr_notification_mode),

        .write_done(ifmap_write_done),
        .read_done(ifmap_read_done),
        .mm2s_data_count(ifmap_mm2s_data_count),
        .parser_state(ifmap_parser_state),
        .error_invalid_magic(ifmap_error_invalid_magic),

        .bram_wr_data_flat(ifmap_wr_data_flat),
        .bram_wr_addr(ifmap_wr_addr),
        .bram_wr_en(ifmap_wr_en),

        .bram_rd_data_flat(out_group1_bram_data),  // Read from BRAM 8-15
        .bram_rd_addr(ifmap_rd_addr)
    );

    // ========================================================================
    // TRANSPOSE CONTROL TOP
    // ========================================================================
    Transpose_Control_Top #(
        .DW(DW),
        .NUM_BRAMS(NUM_BRAMS),
        .NUM_PE(Dimension),
        .ADDR_WIDTH(I_ADDR_W)
    ) control_top (
        .clk(aclk),
        .rst_n(aresetn),
        .weight_write_done(weight_write_done),
        .ifmap_write_done(ifmap_write_done),
        .batch_complete_signal(batch_complete_from_ctrl),
        .ext_start(ext_start),
        .ext_layer_id(ext_layer_id),
        .current_layer_id(current_layer_id),
        .current_batch_id(current_batch_id),
        .scheduler_done(scheduler_done),
        .all_batches_done(all_batches_done),
        .clear_output_bram(clear_output_bram),
        .auto_active(auto_start_active),
        .w_re(w_re),
        .w_addr_rd_flat(w_addr_rd_flat),
        .if_re(if_re),
        .if_addr_rd_flat(if_addr_rd_flat),
        .ifmap_sel_out(ifmap_sel),
        .en_weight_load(en_weight_load),
        .en_ifmap_load(en_ifmap_load),
        .en_psum(en_psum),
        .clear_psum(clear_psum),
        .en_output(en_output),
        .ifmap_sel_ctrl(ifmap_sel_ctrl),
        .cmap_snapshot(cmap_snapshot),
        .omap_snapshot(omap_snapshot),
        .mapper_done_pulse(),
        .selector_mux_transpose(done_transpose)
    );

    // ========================================================================
    // DATAPATH
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
        
        .w_we(weight_wr_en),
        .w_addr_wr_flat({NUM_BRAMS{weight_wr_addr}}),
        .w_din_flat(weight_wr_data_flat),
        .w_re(w_re),
        .w_addr_rd_flat(w_addr_rd_flat),
        
        .if_we(ifmap_wr_en),
        .if_addr_wr_flat({NUM_BRAMS{ifmap_wr_addr}}),
        .if_din_flat(ifmap_wr_data_flat),
        .if_re(if_re),
        .if_addr_rd_flat(if_addr_rd_flat),
        .ifmap_sel(ifmap_sel),
        
        .en_weight_load(en_weight_load),
        .en_ifmap_load(en_ifmap_load),
        .en_psum(en_psum),
        .clear_psum(clear_psum),
        .en_output(en_output),
        .ifmap_sel_ctrl(ifmap_sel_ctrl),
        .done_select(done_transpose),
        
        .cmap(cmap_snapshot),
        .omap_flat(omap_snapshot),
        
        .ext_read_mode(out_mgr_ext_read_mode),
        .ext_read_addr_flat(out_mgr_ext_read_addr_flat),
        .ext_read_data_flat(ext_read_data_flat)
    );

    // ========================================================================
    // OUTPUT STREAM MANAGER - DRIVES BOTH WRAPPERS SIMULTANEOUSLY
    // ========================================================================
    Output_Manager_Simple #(
        .DW(DW)
    ) output_mgr (
        .clk(aclk),
        .rst_n(aresetn),

        .batch_complete(batch_complete_from_ctrl),
        .current_batch_id(current_batch_id),
        .all_batches_done(all_batches_done),
        .completed_layer_id(current_layer_id),

        // SHARED header outputs (connected to BOTH wrappers)
        .header_word_0(header_word_0),
        .header_word_1(header_word_1),
        .header_word_2(header_word_2),
        .header_word_3(header_word_3),
        .header_word_4(header_word_4),
        .header_word_5(header_word_5),
        .send_header(send_header),  // SAME for both!

        .trigger_read(out_mgr_trigger_read),
        .rd_bram_start(out_mgr_rd_bram_start),
        .rd_bram_end(out_mgr_rd_bram_end),
        .rd_addr_count(out_mgr_rd_addr_count),
        .notification_mode(out_mgr_notification_mode),

        // Use weight_read_done as primary done signal
        // (both should complete simultaneously in parallel mode)
        .read_done(weight_read_done),
        .transmission_active(out_mgr_transmission_active)  // FIX: tersambung untuk kontrol ext_read_mode
    );

endmodule