`timescale 1ns / 1ps

/******************************************************************************
 * Module: Conv_Transconv_System_Top_Level_Auto_Sequenced
 *
 * Description:
 *   Fully automatic sequencing system that performs:
 *   1. Normal 1D Convolution (9 layers: 0-8) - triggered by AXI data arrival
 *   2. Transposed Convolution (4 layers: 0-3) - triggered by CONV completion
 *   
 *   The conv_mode signal is AUTOMATICALLY controlled based on completion
 *   status from the control modules:
 *   - Initially: conv_mode = 0 (CONV mode)
 *   - After conv_global_done: conv_mode = 1 (TRANSCONV mode)
 *   - After transconv_scheduler_done: Entire sequence complete
 *
 * NO EXTERNAL START SIGNAL:
 *   - Onedconv_Control_Top waits for AXI write_done (data arrival)
 *   - When data arrives, CONV processing begins automatically
 *   - When CONV completes, system switches to TRANSCONV mode
 *   - Transpose_Control_Top waits for its data and processes
 *
 * Author: Auto-Sequenced Design  
 * Date: January 2026
 ******************************************************************************/

module Conv_Transconv_System_Top_Level_Auto_Sequenced #(
    parameter DW           = 16,
    parameter NUM_BRAMS    = 16,
    parameter W_ADDR_W     = 11,
    parameter I_ADDR_W     = 10,
    parameter O_ADDR_W     = 10,
    parameter W_DEPTH      = 2048,
    parameter I_DEPTH      = 1024,
    parameter O_DEPTH      = 1024,
    parameter Dimension    = 16,
    parameter MUX_SEL_WIDTH = 4,
    parameter Depth_added  = 16
)(
    input  wire aclk,
    input  wire aresetn,

    // ============================================================
    // AXI INTERFACES ONLY - No external control signals!
    // ============================================================
    
    // AXI Stream 0 - Weight Loading
    input  wire [DW-1:0]  s0_axis_tdata,
    input  wire           s0_axis_tvalid,
    output wire           s0_axis_tready,
    input  wire           s0_axis_tlast,
    output wire [DW-1:0]  m0_axis_tdata,
    output wire           m0_axis_tvalid,
    input  wire           m0_axis_tready,
    output wire           m0_axis_tlast,

    // AXI Stream 1 - Ifmap Loading
    input  wire [DW-1:0]  s1_axis_tdata,
    input  wire           s1_axis_tvalid,
    output wire           s1_axis_tready,
    input  wire           s1_axis_tlast,
    output wire [DW-1:0]  m1_axis_tdata,
    output wire           m1_axis_tvalid,
    input  wire           m1_axis_tready,
    output wire           m1_axis_tlast,

    // AXI Stream 2 - Bias Loading (WRITE ONLY)
    input  wire [DW-1:0]  s2_axis_tdata,
    input  wire           s2_axis_tvalid,
    output wire           s2_axis_tready,
    input  wire           s2_axis_tlast,

    // AXI Stream 3 - Output Stream
    output wire [DW-1:0]  m_output_axis_tdata,
    output wire           m_output_axis_tvalid,
    input  wire           m_output_axis_tready,
    output wire           m_output_axis_tlast,

    // ============================================================
    // STATUS OUTPUTS (for monitoring/debug)
    // ============================================================
    output wire           sequence_complete,     // Both CONV and TRANSCONV done
    output wire           conv_mode,             // 0=CONV, 1=TRANSCONV
    output wire           conv_stage_done,       // CONV (9 layers) complete
    output wire           transconv_stage_done,  // TRANSCONV (4 layers) complete
    output wire [3:0]     conv_current_layer,    // Current CONV layer (0-8)
    output wire [1:0]     transconv_current_layer, // Current TRANSCONV layer (0-3)
    
    // External BRAM Write Interface (for bias) - kept for compatibility
    input  wire                              input_bias,
    input  wire [NUM_BRAMS-1:0]              bias_ena,
    input  wire [NUM_BRAMS-1:0]              bias_wea,
    input  wire [O_ADDR_W-1:0]               bias_addr,
    input  wire signed [NUM_BRAMS*DW-1:0]    bias_data,

    // External Output Read Interface - kept for compatibility
    input  wire                              ext_read_mode,
    input  wire [NUM_BRAMS-1:0]              ext_enb_output,
    input  wire [O_ADDR_W-1:0]               ext_output_addr,
    output wire signed [NUM_BRAMS*DW-1:0]    output_result,

    // Debug & Status Outputs
    output wire           weight_write_done,
    output wire           weight_read_done,
    output wire           ifmap_write_done,
    output wire           ifmap_read_done,
    output wire [9:0]     weight_mm2s_data_count,
    output wire [9:0]     ifmap_mm2s_data_count,
    output wire [2:0]     weight_parser_state,
    output wire           weight_error_invalid_magic,
    output wire [2:0]     ifmap_parser_state,
    output wire           ifmap_error_invalid_magic
);

    // ========================================================================
    // INTERNAL WIRES - AXI Wrappers to BRAMs
    // ========================================================================
    
    // Weight BRAM Write
    wire [NUM_BRAMS*DW-1:0]      weight_wr_data_flat;
    wire [W_ADDR_W-1:0]          weight_wr_addr;
    wire [NUM_BRAMS-1:0]         weight_wr_en;

    // Ifmap BRAM Write
    wire [NUM_BRAMS*DW-1:0]      ifmap_wr_data_flat;
    wire [I_ADDR_W-1:0]          ifmap_wr_addr;
    wire [NUM_BRAMS-1:0]         ifmap_wr_en;

    // Bias BRAM Write
    wire [NUM_BRAMS*DW-1:0]      bias_wr_data_flat;
    wire [O_ADDR_W-1:0]          bias_wr_addr;
    wire [NUM_BRAMS-1:0]         bias_wr_en;
    wire                         bias_write_done;
    wire [2:0]                   bias_parser_state;
    wire                         bias_error_invalid_magic;

    // ========================================================================
    // INTERNAL WIRES - TRANSCONV Control Signals
    // ========================================================================
    wire [NUM_BRAMS-1:0]            transconv_w_re;
    wire [NUM_BRAMS*W_ADDR_W-1:0]   transconv_w_addr_rd_flat;
    wire [NUM_BRAMS-1:0]            transconv_if_re;
    wire [NUM_BRAMS*I_ADDR_W-1:0]   transconv_if_addr_rd_flat;
    wire [3:0]                      transconv_ifmap_sel;
    
    wire [NUM_BRAMS-1:0]            transconv_en_weight_load;
    wire [NUM_BRAMS-1:0]            transconv_en_ifmap_load;
    wire [NUM_BRAMS-1:0]            transconv_en_psum;
    wire [NUM_BRAMS-1:0]            transconv_clear_psum;
    wire [NUM_BRAMS-1:0]            transconv_en_output;
    wire [NUM_BRAMS-1:0]            transconv_ifmap_sel_ctrl;
    wire [4:0]                      transconv_done_select;
    
    wire [NUM_BRAMS-1:0]            transconv_cmap_snapshot;
    wire [NUM_BRAMS*14-1:0]         transconv_omap_snapshot;
    wire                            transconv_clear_output_bram;
    wire                            transconv_batch_complete;
    wire                            transconv_scheduler_done;
    wire [1:0]                      transconv_current_layer_id;
    wire [2:0]                      transconv_current_batch_id;
    wire                            transconv_all_batches_done;
    wire                            transconv_auto_start_active;

    // ========================================================================
    // INTERNAL WIRES - CONV Control Signals (UNIFIED CONTROL)
    // ========================================================================
    wire [NUM_BRAMS-1:0]              conv_if_re;
    wire [I_ADDR_W-1:0]               conv_ifmap_addr_out;
    wire [NUM_BRAMS-1:0]              conv_w_re;
    wire [I_ADDR_W-1:0]               conv_weight_addr_out;
    
    wire                              conv_buffer_mode;
    wire [Dimension-1:0]              conv_en_shift_reg_ifmap;
    wire [Dimension-1:0]              conv_en_shift_reg_weight;
    wire                              conv_zero_or_data;
    wire                              conv_zero_or_data_weight;
    wire [MUX_SEL_WIDTH-1:0]          conv_sel_input_data_mem;
    wire                              conv_output_bram_dest;
    wire                              conv_en_reg_adder;
    wire                              conv_output_reg_rst;
    
    wire [O_ADDR_W-1:0]               conv_output_addr_wr;
    wire [O_ADDR_W-1:0]               conv_output_addr_rd;
    wire [NUM_BRAMS-1:0]              conv_ena_output;
    wire [NUM_BRAMS-1:0]              conv_wea_output;
    wire [NUM_BRAMS-1:0]              conv_enb_output;
    
    wire                              conv_rst_top;
    wire                              conv_mode_top;
    wire                              conv_output_val_top;
    wire                              conv_start_top;
    wire                              conv_out_new_val_sign;
    wire                              conv_done_count_top;
    wire                              conv_done_top;
    
    wire                              conv_global_done;
    wire                              conv_layer_processing;
    wire [3:0]                        conv_scheduler_state;
    wire [3:0]                        conv_layer_id;
    
    // Systolic array control from unified system
    wire                              conv_en_cntr_systolic;
    wire [Dimension*Dimension-1:0]    conv_en_in_systolic;
    wire [Dimension*Dimension-1:0]    conv_en_out_systolic;
    wire [Dimension*Dimension-1:0]    conv_en_psum_systolic;
    wire [Dimension-1:0]              conv_ifmaps_sel_systolic;
    wire [Dimension-1:0]              conv_output_eject_ctrl_systolic;
    wire                              conv_output_val_count_systolic;

    // ========================================================================
    // INTERNAL WIRES - Output Manager
    // ========================================================================
    wire [15:0] header_word_0, header_word_1, header_word_2;
    wire [15:0] header_word_3, header_word_4, header_word_5;
    wire        send_header;
    wire        out_mgr_trigger_read;
    wire [2:0]  out_mgr_rd_bram_start;
    wire [2:0]  out_mgr_rd_bram_end;
    wire [15:0] out_mgr_rd_addr_count;
    wire        out_mgr_notification_mode;
    wire        out_mgr_transmission_active;
    wire        out_mgr_ext_read_mode;
    wire [NUM_BRAMS*O_ADDR_W-1:0] out_mgr_ext_read_addr_flat;
    
    // ========================================================================
    // INTERNAL WIRES - Datapath
    // ========================================================================
    wire signed [NUM_BRAMS*DW-1:0]    ext_read_data_flat;
    wire [NUM_BRAMS*O_ADDR_W-1:0]     bram_read_addr_flat;
    wire                              start_conv_signal;
    wire                              start_transconv_signal;

    // ========================================================================
    // AUTOMATIC MODE CONTROL - CONV → TRANSCONV SEQUENCING
    // ========================================================================
    
    // Mode register: 0 = CONV, 1 = TRANSCONV
    reg conv_mode_reg;
    
    // Edge detection for CONV completion
    reg conv_global_done_prev;
    wire conv_done_pulse;
    
    always @(posedge aclk or negedge aresetn) begin
        if (~aresetn) begin
            conv_mode_reg <= 1'b0;  // Start in CONV mode
            conv_global_done_prev <= 1'b0;
        end else begin
            conv_global_done_prev <= conv_global_done;
            
            // Transition from CONV to TRANSCONV when CONV completes
            if (conv_done_pulse) begin
                conv_mode_reg <= 1'b1;  // Switch to TRANSCONV mode
                $display("[%0t] AUTO-SEQUENCE: CONV complete (9 layers), switching to TRANSCONV mode", $time);
            end
        end
    end
    
    assign conv_done_pulse = conv_global_done & ~conv_global_done_prev;
    assign conv_mode = conv_mode_reg;
    
    // ========================================================================
    // START SIGNAL GENERATION
    // ========================================================================
    
    // CONV: Always enabled (waits for AXI data internally)
    // The Onedconv_Control_Top has global_start tied HIGH, so it starts
    // automatically when AXI write_done signals arrive
    wire conv_auto_start = 1'b1;  // Always active, waits for data internally
    
    // TRANSCONV: Starts when mode switches to TRANSCONV
    // Edge detect the mode transition to generate a start pulse
    reg conv_mode_prev;
    wire transconv_start_pulse;
    
    always @(posedge aclk or negedge aresetn) begin
        if (~aresetn)
            conv_mode_prev <= 1'b0;
        else
            conv_mode_prev <= conv_mode_reg;
    end
    
    assign transconv_start_pulse = conv_mode_reg & ~conv_mode_prev;
    
    // Start signals for BRAM mode registers (they switch based on start signals)
    assign start_conv_signal = ~conv_mode_reg;  // Active during CONV mode
    assign start_transconv_signal = transconv_start_pulse;  // Pulse on mode transition
    
    // ========================================================================
    // STATUS OUTPUT ASSIGNMENTS
    // ========================================================================
    assign sequence_complete = conv_global_done & transconv_scheduler_done;
    assign conv_stage_done = conv_global_done;
    assign transconv_stage_done = transconv_scheduler_done;
    assign conv_current_layer = conv_layer_id;
    assign transconv_current_layer = transconv_current_layer_id;
    
    // Output result
    assign output_result = ext_read_data_flat;

    // Generate ext_read_addr_flat from scalar address
    wire [NUM_BRAMS*O_ADDR_W-1:0] ext_read_addr_flat_scalar;
    genvar k;
    generate
        for (k = 0; k < NUM_BRAMS; k = k + 1) begin : GEN_EXT_ADDR
            assign ext_read_addr_flat_scalar[k*O_ADDR_W +: O_ADDR_W] = ext_output_addr;
        end
    endgenerate
    
    // Display messages for debug
    always @(posedge aclk) begin
        if (conv_done_pulse) begin
            $display("[%0t] ═══════════════════════════════════════════", $time);
            $display("[%0t] CONV STAGE COMPLETE - All 9 layers done", $time);
            $display("[%0t] Transitioning to TRANSCONV mode...", $time);
            $display("[%0t] ═══════════════════════════════════════════", $time);
        end
        
        if (transconv_start_pulse) begin
            $display("[%0t] TRANSCONV STAGE STARTING - Layer 0", $time);
        end
        
        if (transconv_scheduler_done & ~sequence_complete) begin
            $display("[%0t] ═══════════════════════════════════════════", $time);
            $display("[%0t] TRANSCONV STAGE COMPLETE - All 4 layers done", $time);
            $display("[%0t] ENTIRE SEQUENCE COMPLETE!", $time);
            $display("[%0t] ═══════════════════════════════════════════", $time);
        end
    end

    // ========================================================================
    // INSTANTIATION 1A: AXI WEIGHT WRAPPER
    // ========================================================================
    axis_control_wrapper #(
        .BRAM_DEPTH(W_DEPTH),
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
        
        // AXI Stream Master (to PS)
        .m_axis_tdata(m0_axis_tdata),
        .m_axis_tvalid(m0_axis_tvalid),
        .m_axis_tready(m0_axis_tready),
        .m_axis_tlast(m0_axis_tlast),
        
        // Output Manager Header Interface
        .header_word_0(header_word_0),
        .header_word_1(header_word_1),
        .header_word_2(header_word_2),
        .header_word_3(header_word_3),
        .header_word_4(header_word_4),
        .header_word_5(header_word_5),
        .send_header(send_header),
        
        // Read Control
        .out_mgr_rd_bram_start(out_mgr_rd_bram_start),
        .out_mgr_rd_bram_end(out_mgr_rd_bram_end),
        .out_mgr_rd_addr_count(out_mgr_rd_addr_count),
        .notification_mode(out_mgr_notification_mode),
        
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
        
        // BRAM Read Interface (for output streaming)
        .bram_rd_data_flat(ext_read_data_flat[8*DW-1:0]),
        .bram_rd_addr()
    );

    // ========================================================================
    // INSTANTIATION 1B: AXI IFMAP WRAPPER
    // ========================================================================
    axis_control_wrapper #(
        .BRAM_DEPTH(I_DEPTH),
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
        
        // AXI Stream Master (to PS)
        .m_axis_tdata(m1_axis_tdata),
        .m_axis_tvalid(m1_axis_tvalid),
        .m_axis_tready(m1_axis_tready),
        .m_axis_tlast(m1_axis_tlast),
        
        // Output Manager Header Interface (not used for ifmap)
        .header_word_0(16'd0),
        .header_word_1(16'd0),
        .header_word_2(16'd0),
        .header_word_3(16'd0),
        .header_word_4(16'd0),
        .header_word_5(16'd0),
        .send_header(1'b0),
        
        // Read Control
        .out_mgr_rd_bram_start(3'd8),  // BRAMs 8-15 for ifmap readback
        .out_mgr_rd_bram_end(3'd15),
        .out_mgr_rd_addr_count(out_mgr_rd_addr_count),
        .notification_mode(out_mgr_notification_mode),
        
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
        
        // BRAM Read Interface (for output streaming)
        .bram_rd_data_flat(ext_read_data_flat[16*DW-1:8*DW]),
        .bram_rd_addr()
    );

    // ========================================================================
    // INSTANTIATION 1C: AXI BIAS WRAPPER (WRITE ONLY)
    // ========================================================================
    axis_control_wrapper #(
        .BRAM_DEPTH(O_DEPTH),
        .DATA_WIDTH(DW),
        .BRAM_COUNT(NUM_BRAMS),
        .ADDR_WIDTH(O_ADDR_W)
    ) bias_wrapper (
        .aclk(aclk),
        .aresetn(aresetn),
        
        // AXI Stream Slave (from PS)
        .s_axis_tdata(s2_axis_tdata),
        .s_axis_tvalid(s2_axis_tvalid),
        .s_axis_tready(s2_axis_tready),
        .s_axis_tlast(s2_axis_tlast),
        
        // AXI Stream Master - DISABLED
        .m_axis_tdata(),
        .m_axis_tvalid(),
        .m_axis_tready(1'b1),
        .m_axis_tlast(),
        
        // Output Manager Header Interface - DISABLED
        .header_word_0(16'd0),
        .header_word_1(16'd0),
        .header_word_2(16'd0),
        .header_word_3(16'd0),
        .header_word_4(16'd0),
        .header_word_5(16'd0),
        .send_header(1'b0),
        
        // Read Control - DISABLED
        .out_mgr_rd_bram_start(3'd0),
        .out_mgr_rd_bram_end(3'd0),
        .out_mgr_rd_addr_count(16'd0),
        .notification_mode(1'b0),
        
        // Status
        .write_done(bias_write_done),
        .read_done(),
        .mm2s_data_count(),
        .parser_state(bias_parser_state),
        .error_invalid_magic(bias_error_invalid_magic),
        
        // BRAM Write Interface
        .bram_wr_data_flat(bias_wr_data_flat),
        .bram_wr_addr(bias_wr_addr),
        .bram_wr_en(bias_wr_en),
        
        // BRAM Read Interface - DISABLED
        .bram_rd_data_flat({8*DW{1'b0}}),
        .bram_rd_addr()
    );

    // ========================================================================
    // INSTANTIATION 2A: TRANSPOSE CONTROL TOP (TRANSCONV MODE)
    // ========================================================================
    Transpose_Control_Top #(
        .DW(DW),
        .NUM_BRAMS(NUM_BRAMS),
        .NUM_PE(Dimension),
        .ADDR_WIDTH(I_ADDR_W)
    ) transconv_control (
        .clk(aclk),
        .rst_n(aresetn),
        
        // Automation inputs - waits for data when in TRANSCONV mode
        .weight_write_done(weight_write_done & conv_mode_reg),
        .ifmap_write_done(ifmap_write_done & conv_mode_reg),
        
        // External control - pulse when transitioning to TRANSCONV
        .ext_start(transconv_start_pulse),
        .ext_layer_id(2'b00),  // Start from layer 0
        
        // Status outputs
        .current_layer_id(transconv_current_layer_id),
        .current_batch_id(transconv_current_batch_id),
        .scheduler_done(transconv_scheduler_done),
        .all_batches_done(transconv_all_batches_done),
        .clear_output_bram(transconv_clear_output_bram),
        .auto_active(transconv_auto_start_active),
        .batch_complete_signal(transconv_batch_complete),
        
        // Weight BRAM control
        .w_re(transconv_w_re),
        .w_addr_rd_flat(transconv_w_addr_rd_flat),
        
        // Ifmap BRAM control
        .if_re(transconv_if_re),
        .if_addr_rd_flat(transconv_if_addr_rd_flat),
        .ifmap_sel_out(transconv_ifmap_sel),
        
        // Systolic array control
        .en_weight_load(transconv_en_weight_load),
        .en_ifmap_load(transconv_en_ifmap_load),
        .en_psum(transconv_en_psum),
        .clear_psum(transconv_clear_psum),
        .en_output(transconv_en_output),
        .ifmap_sel_ctrl(transconv_ifmap_sel_ctrl),
        
        // Mapping configuration
        .cmap_snapshot(transconv_cmap_snapshot),
        .omap_snapshot(transconv_omap_snapshot),
        .mapper_done_pulse(),
        .selector_mux_transpose(transconv_done_select)
    );

    // ========================================================================
    // INSTANTIATION 2B: UNIFIED ONEDCONV CONTROL SYSTEM (1DCONV MODE)
    // 
    // AUTOMATIC OPERATION:
    //   - global_start is tied HIGH (always enabled)
    //   - Scheduler FSM waits for write_done signals (AXI data arrival)
    //   - When data arrives, processing begins automatically
    //   - After 9 layers complete, global_done pulses
    //   - This triggers mode transition to TRANSCONV
    // ========================================================================
    Onedconv_Control_Top #(
        .DW(DW),
        .Dimension(Dimension),
        .ADDRESS_LENGTH(I_ADDR_W),
        .MUX_SEL_WIDTH(MUX_SEL_WIDTH)
    ) conv_unified_control (
        .clk(aclk),
        .rst_n(aresetn),
        
        // ============================================================
        // Global Control - ALWAYS ENABLED (waits for AXI data)
        // ============================================================
        .global_start(conv_auto_start),  // Tied HIGH - auto-starts when data arrives
        .global_done(conv_global_done),
        
        // ============================================================
        // AXI Interface - Only active during CONV mode
        // ============================================================
        .write_done((weight_write_done | ifmap_write_done) & ~conv_mode_reg),
        .read_done(weight_read_done & ~conv_mode_reg),
        .transmission_active(out_mgr_transmission_active & ~conv_mode_reg),
        
        // AXI control outputs (not used in current AXI architecture)
        .weight_read_req(),
        .ifmap_read_req(),
        .ofmap_write_req(),
        
        // ============================================================
        // Matrix Multiplication Datapath Inputs
        // ============================================================
        .out_new_val_sign(conv_out_new_val_sign),
        
        // ============================================================
        // BRAM Address Outputs
        // ============================================================
        .inputdata_addr_out(conv_ifmap_addr_out),
        .weight_addr_out(conv_weight_addr_out),
        .output_addr_out_a(conv_output_addr_wr),
        .output_addr_out_b(conv_output_addr_rd),
        
        // ============================================================
        // BRAM Control Outputs
        // ============================================================
        .enb_inputdata_input_bram(conv_if_re),
        .enb_weight_input_bram(conv_w_re),
        .ena_output_result_control(conv_ena_output),
        .wea_output_result(conv_wea_output),
        .enb_output_result_control(conv_enb_output),
        
        // ============================================================
        // Shift Register & Datapath Control
        // ============================================================
        .en_shift_reg_ifmap_input_ctrl(conv_en_shift_reg_ifmap),
        .en_shift_reg_weight_input_ctrl(conv_en_shift_reg_weight),
        .zero_or_data(conv_zero_or_data),
        .zero_or_data_weight(conv_zero_or_data_weight),
        .sel_input_data_mem(conv_sel_input_data_mem),
        .output_bram_destination(conv_output_bram_dest),
        
        // ============================================================
        // Systolic Array Control Outputs
        // ============================================================
        .en_cntr_systolic(conv_en_cntr_systolic),
        .en_in_systolic(conv_en_in_systolic),
        .en_out_systolic(conv_en_out_systolic),
        .en_psum_systolic(conv_en_psum_systolic),
        .ifmaps_sel_systolic(conv_ifmaps_sel_systolic),
        .output_eject_ctrl_systolic(conv_output_eject_ctrl_systolic),
        .output_val_count_systolic(conv_output_val_count_systolic),
        
        // ============================================================
        // Adder-Side Register Control
        // ============================================================
        .en_reg_adder(conv_en_reg_adder),
        .output_result_reg_rst(conv_output_reg_rst),
        
        // ============================================================
        // Top-Level IO Control (for systolic array)
        // ============================================================
        .rst_top(conv_rst_top),
        .mode_top(conv_mode_top),
        .output_val_top(conv_output_val_top),
        .start_top(conv_start_top),
        
        // ============================================================
        // Status Outputs (for monitoring)
        // ============================================================
        .current_layer_id(conv_layer_id),
        .layer_processing(conv_layer_processing),
        .scheduler_state(conv_scheduler_state),
        .done_count_top(conv_done_count_top),
        .done_top(conv_done_top)
    );

    // ========================================================================
    // MODE-BASED ADDRESS GENERATION FOR 1DCONV
    // ========================================================================
    wire [NUM_BRAMS*I_ADDR_W-1:0] conv_if_addr_rd_flat;
    wire [NUM_BRAMS*W_ADDR_W-1:0] conv_w_addr_rd_flat;
    wire [NUM_BRAMS-1:0] conv_ifmaps_sel_ctrl;
    wire [NUM_BRAMS-1:0] conv_output_eject_ctrl;

    genvar g;
    generate
        for (g = 0; g < NUM_BRAMS; g = g + 1) begin : GEN_CONV_ADDR
            assign conv_if_addr_rd_flat[g*I_ADDR_W +: I_ADDR_W] = conv_ifmap_addr_out;
            assign conv_w_addr_rd_flat[g*W_ADDR_W +: W_ADDR_W] = {{(W_ADDR_W-I_ADDR_W){1'b0}}, conv_weight_addr_out};
            assign conv_ifmaps_sel_ctrl[g] = conv_zero_or_data;
            assign conv_output_eject_ctrl[g] = conv_output_val_top;
        end
    endgenerate

    // ========================================================================
    // INSTANTIATION 3: UNIFIED DATAPATH (Conv_Transconv_Super_Top_Level_Modified)
    // ========================================================================
    Conv_Transconv_Super_Top_Level_Modified #(
        .DW(DW),
        .NUM_BRAMS(NUM_BRAMS),
        .W_ADDR_W(W_ADDR_W),
        .W_DEPTH(W_DEPTH),
        .I_ADDR_W(I_ADDR_W),
        .I_DEPTH(I_DEPTH),
        .O_ADDR_W(O_ADDR_W),
        .O_DEPTH(O_DEPTH),
        .Depth_added(Depth_added)
    ) u_datapath (
        .clk(aclk),
        .rst_n(aresetn),
        
        // Mode selection - AUTOMATIC based on control completion
        .conv_mode(conv_mode_reg),
        .start_conv(start_conv_signal),
        .start_transconv(start_transconv_signal),
        
        // Weight BRAM interface
        .w_we(weight_wr_en),
        .w_addr_wr_flat({NUM_BRAMS{weight_wr_addr}}),
        .w_din_flat(weight_wr_data_flat),
        .w_re_conv(conv_w_re),
        .w_addr_rd_conv_flat(conv_w_addr_rd_flat),
        .w_re_transconv(transconv_w_re),
        .w_addr_rd_transconv_flat(transconv_w_addr_rd_flat),
        
        // Ifmap BRAM interface
        .if_we(ifmap_wr_en),
        .if_addr_wr_flat({NUM_BRAMS{ifmap_wr_addr}}),
        .if_din_flat(ifmap_wr_data_flat),
        .if_re_conv(conv_if_re),
        .if_addr_rd_conv_flat(conv_if_addr_rd_flat),
        .if_re_transconv(transconv_if_re),
        .if_addr_rd_transconv_flat(transconv_if_addr_rd_flat),
        .ifmap_sel_transconv(transconv_ifmap_sel),
        
        // 1DCONV control signals (from unified control)
        .conv_buffer_mode(conv_mode_top),
        .conv_en_shift_reg_ifmap_input(|conv_en_shift_reg_ifmap),
        .conv_en_shift_reg_weight_input(|conv_en_shift_reg_weight),
        .conv_en_shift_reg_ifmap_control(|conv_en_shift_reg_ifmap),
        .conv_en_shift_reg_weight_control(|conv_en_shift_reg_weight),
        .conv_en_cntr(conv_en_cntr_systolic),
        .conv_en_in(conv_en_in_systolic),
        .conv_en_out(conv_en_out_systolic),
        .conv_en_psum(conv_en_psum_systolic),
        .conv_clear_psum({(NUM_BRAMS*NUM_BRAMS){~conv_rst_top}}),
        .conv_ifmaps_sel_ctrl(conv_ifmaps_sel_ctrl),
        .conv_output_eject_ctrl(conv_output_eject_ctrl),
        .conv_out_new_val_sign(conv_out_new_val_sign),
        .conv_output_addr_wr(conv_output_addr_wr),
        .conv_output_addr_rd(conv_output_addr_rd),
        .conv_ena_output(conv_ena_output),
        .conv_wea_output(conv_wea_output),
        .conv_enb_output(conv_enb_output),
        .conv_en_reg_adder(conv_en_reg_adder),
        .conv_output_reg_rst(conv_output_reg_rst),
        .conv_output_bram_dest(conv_output_bram_dest),
        
        // Bias interface
        .input_bias(input_bias),
        .bias_ena(input_bias ? bias_ena : bias_wr_en),
        .bias_wea(input_bias ? bias_wea : bias_wr_en),
        .bias_addr(input_bias ? bias_addr : bias_wr_addr),
        .bias_data(input_bias ? bias_data : bias_wr_data_flat),
        
        // TRANSCONV control signals
        .transconv_en_weight_load(transconv_en_weight_load),
        .transconv_en_ifmap_load(transconv_en_ifmap_load),
        .transconv_en_psum(transconv_en_psum),
        .transconv_clear_psum(transconv_clear_psum | {NUM_BRAMS{transconv_clear_output_bram}}),
        .transconv_en_output(transconv_en_output),
        .transconv_ifmap_sel_ctrl(transconv_ifmap_sel_ctrl),
        .transconv_done_select(transconv_done_select),
        
        // Mapping configuration
        .cmap(transconv_cmap_snapshot),
        .omap_flat(transconv_omap_snapshot),
        
        // External read interface
        .ext_read_mode(out_mgr_ext_read_mode | ext_read_mode),
        .ext_read_addr_flat(out_mgr_ext_read_mode ? out_mgr_ext_read_addr_flat : ext_read_addr_flat_scalar),
        
        // Outputs
        .bram_read_data_flat(ext_read_data_flat),
        .bram_read_addr_flat(bram_read_addr_flat)
    );

    // ========================================================================
    // INSTANTIATION 4: OUTPUT MANAGER
    // ========================================================================
    Output_Manager_Simple #(
        .DW(DW)
    ) output_mgr (
        .clk(aclk),
        .rst_n(aresetn),
        
        // Status inputs
        .batch_complete(conv_mode_reg ? transconv_batch_complete : 1'b0),
        .current_batch_id(transconv_current_batch_id),
        .all_batches_done(conv_mode_reg ? transconv_all_batches_done : conv_global_done),
        .completed_layer_id(conv_mode_reg ? transconv_current_layer_id : 2'b00),
        
        // Header outputs
        .header_word_0(header_word_0),
        .header_word_1(header_word_1),
        .header_word_2(header_word_2),
        .header_word_3(header_word_3),
        .header_word_4(header_word_4),
        .header_word_5(header_word_5),
        
        // Control outputs
        .send_header(send_header),
        .trigger_read(out_mgr_trigger_read),
        .rd_bram_start(out_mgr_rd_bram_start),
        .rd_bram_end(out_mgr_rd_bram_end),
        .rd_addr_count(out_mgr_rd_addr_count),
        .notification_mode(out_mgr_notification_mode),
        
        // Handshake
        .read_done(weight_read_done),
        .transmission_active(out_mgr_transmission_active)
    );

    // Output Manager ext_read_mode control
    assign out_mgr_ext_read_mode = out_mgr_transmission_active;

    // Generate ext_read_addr_flat for Output Manager (not yet implemented fully)
    assign out_mgr_ext_read_addr_flat = {NUM_BRAMS{10'd0}};

    // ========================================================================
    // OUTPUT STREAM ROUTING
    // ========================================================================
    assign m_output_axis_tdata  = m0_axis_tdata;
    assign m_output_axis_tvalid = m0_axis_tvalid;
    assign m_output_axis_tlast  = m0_axis_tlast;

endmodule