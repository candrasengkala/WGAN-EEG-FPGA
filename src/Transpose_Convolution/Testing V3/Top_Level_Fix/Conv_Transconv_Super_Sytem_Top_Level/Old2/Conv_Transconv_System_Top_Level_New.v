`timescale 1ns / 1ps

/******************************************************************************
 * Module: Conv_Transconv_System_Top_Level (MODIFIED for Onedconv_Control_Wrapper)
 *
 * Description:
 *   Top-level system integration for BOTH Normal Convolution (1DCONV) and
 *   Transposed Convolution (TRANSCONV) operations with CLEAN separation:
 *
 *   1. AXI Wrappers (Weight & Ifmap loading via DMA)
 *   2. Onedconv_Control_Wrapper (Unified 1DCONV control wrapper)
 *   3. Transpose_Control_Top (TRANSCONV control)
 *   4. Conv_Transconv_Super_Top_Level (Unified datapath)
 *   5. Output_Stream_Manager (Result transmission to PS)
 *
 * Mode Selection:
 *   - conv_mode = 0: Normal 1D Convolution (uses Onedconv_Control_Wrapper)
 *   - conv_mode = 1: Transposed Convolution (uses Transpose_Control_Top)
 *
 * Features:
 *   - Shared Weight/Ifmap BRAMs for both modes
 *   - Mode-aware control signal routing
 *   - Multi-layer support for TRANSCONV (Layer 0: 8 batches, Layer 1: 4 batches)
 *   - Automatic batch management via Auto_Scheduler (TRANSCONV mode)
 *   - Weight update handshaking (1DCONV mode via Onedconv_Control_Wrapper)
 *   - AXI Stream output for result transmission
 *   - Maintains full transpose convolution control signals
 *
 * Author: Integrated Design (Modified)
 * Date: January 2026
 ******************************************************************************/

module Conv_Transconv_System_Top_Level #(
    parameter DW           = 16,
    parameter NUM_BRAMS    = 16,
    parameter W_ADDR_W     = 11,   // Weight BRAM address width
    parameter I_ADDR_W     = 10,   // Ifmap BRAM address width
    parameter O_ADDR_W     = 10,   // Output BRAM address width
    parameter W_DEPTH      = 2048, // Weight BRAM depth (2^11)
    parameter I_DEPTH      = 1024, // Ifmap BRAM depth (2^10)
    parameter O_DEPTH      = 1024, // Output BRAM depth (2^10)
    parameter Dimension    = 16,
    parameter MUX_SEL_WIDTH = 4
)(
    input  wire aclk,
    input  wire aresetn,

    // ========================================================================
    // MODE SELECTION
    // ========================================================================
    input  wire                              conv_mode,  // 0=1DCONV, 1=TRANSCONV

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
    // AXI Stream 2 - Bias Loading (from PS via DMA MM2S) - WRITE ONLY
    // ========================================================================
    input  wire [DW-1:0]  s2_axis_tdata,
    input  wire           s2_axis_tvalid,
    output wire           s2_axis_tready,
    input  wire           s2_axis_tlast,

    // ========================================================================
    // AXI Stream 3 - Output Stream (to PS via DMA S2MM)
    // ========================================================================
    output wire [DW-1:0]  m_output_axis_tdata,
    output wire           m_output_axis_tvalid,
    input  wire           m_output_axis_tready,
    output wire           m_output_axis_tlast,

    // ========================================================================
    // External Control & Status
    // ========================================================================
    input  wire           ext_start,           // Manual start trigger
    input  wire [1:0]     ext_layer_id,        // Optional: Manual layer ID (TRANSCONV)

    // Status Outputs
    output wire           done_all,            // Processing complete (both modes)
    output wire           done_filter,         // Filter batch done (1DCONV)
    output wire           scheduler_done,      // Processing complete (TRANSCONV)
    output wire [1:0]     current_layer_id,    // Current layer (TRANSCONV)
    output wire [2:0]     current_batch_id,    // Current batch (TRANSCONV)
    output wire           all_batches_done,    // All batches done (TRANSCONV)
    output wire [3:0]     conv_current_layer,  // Current layer (1DCONV, 0-8)
    output wire           conv_all_layers_done, // All 9 layers done (1DCONV)

    // ========================================================================
    // External BRAM Write Interface (for bias loading in 1DCONV)
    // ========================================================================
    input  wire                              input_bias,
    input  wire [NUM_BRAMS-1:0]              bias_ena,
    input  wire [NUM_BRAMS-1:0]              bias_wea,
    input  wire [O_ADDR_W-1:0]               bias_addr,
    input  wire signed [NUM_BRAMS*DW-1:0]    bias_data,

    // ========================================================================
    // External Output Read Interface
    // ========================================================================
    input  wire                              ext_read_mode,
    input  wire [NUM_BRAMS-1:0]              ext_enb_output,
    input  wire [O_ADDR_W-1:0]               ext_output_addr,
    output wire signed [NUM_BRAMS*DW-1:0]    output_result,

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
    wire [8*DW-1:0]              weight_rd_data_flat_unused;
    wire [W_ADDR_W-1:0]          weight_rd_addr_unused;

    // Ifmap BRAM Write Interface
    wire [NUM_BRAMS*DW-1:0]      ifmap_wr_data_flat;
    wire [I_ADDR_W-1:0]          ifmap_wr_addr;
    wire [NUM_BRAMS-1:0]         ifmap_wr_en;
    wire [8*DW-1:0]              ifmap_rd_data_flat_unused;
    wire [I_ADDR_W-1:0]          ifmap_rd_addr_unused;

    // Bias BRAM Write Interface (from AXI wrapper)
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
    wire [NUM_BRAMS*I_ADDR_W-1:0]   transconv_w_addr_rd_flat;
    wire [NUM_BRAMS-1:0]            transconv_if_re;
    wire [NUM_BRAMS*I_ADDR_W-1:0]   transconv_if_addr_rd_flat;
    wire [3:0]                      transconv_ifmap_sel;

    wire [NUM_BRAMS-1:0]            transconv_en_weight_load;
    wire [NUM_BRAMS-1:0]            transconv_en_ifmap_load;
    wire [NUM_BRAMS-1:0]            transconv_en_psum;
    wire [NUM_BRAMS-1:0]            transconv_clear_psum;
    wire [NUM_BRAMS-1:0]            transconv_en_output;
    wire [NUM_BRAMS-1:0]            transconv_ifmap_sel_ctrl;

    wire [NUM_BRAMS-1:0]            transconv_cmap_snapshot;
    wire [NUM_BRAMS*14-1:0]         transconv_omap_snapshot;
    wire                            transconv_clear_output_bram;

    // ========================================================================
    // INTERNAL WIRES - 1DCONV Control Wrapper Signals
    // ========================================================================
    
    // From Onedconv_Control_Wrapper - Weight Update Handshake
    wire                            conv_weight_req;
    wire                            conv_weight_ack;

    // From Onedconv_Control_Wrapper - Counter outputs (addresses)
    wire [I_ADDR_W-1:0]             conv_inputdata_addr_out;
    wire [I_ADDR_W-1:0]             conv_weight_addr_out;
    wire [I_ADDR_W-1:0]             conv_output_addr_out_a;
    wire [I_ADDR_W-1:0]             conv_output_addr_out_b;

    // From Onedconv_Control_Wrapper - BRAM control outputs
    wire [NUM_BRAMS-1:0]            conv_enb_inputdata_input_bram;
    wire [NUM_BRAMS-1:0]            conv_enb_weight_input_bram;
    wire [NUM_BRAMS-1:0]            conv_ena_output_result_control;
    wire [NUM_BRAMS-1:0]            conv_wea_output_result;
    wire [NUM_BRAMS-1:0]            conv_enb_output_result_control;

    // From Onedconv_Control_Wrapper - Shift-register & datapath control
    wire [NUM_BRAMS-1:0]            conv_en_shift_reg_ifmap_input_ctrl;
    wire [NUM_BRAMS-1:0]            conv_en_shift_reg_weight_input_ctrl;
    wire                            conv_zero_or_data;
    wire                            conv_zero_or_data_weight;
    wire [MUX_SEL_WIDTH-1:0]        conv_sel_input_data_mem;
    wire                            conv_output_bram_destination;

    // From Onedconv_Control_Wrapper - Matrix multiplication control
    wire                            conv_en_cntr_systolic;
    wire [NUM_BRAMS*NUM_BRAMS-1:0]  conv_en_in_systolic;
    wire [NUM_BRAMS*NUM_BRAMS-1:0]  conv_en_out_systolic;
    wire [NUM_BRAMS*NUM_BRAMS-1:0]  conv_en_psum_systolic;
    wire [NUM_BRAMS-1:0]            conv_ifmaps_sel_systolic;
    wire [NUM_BRAMS-1:0]            conv_output_eject_ctrl_systolic;
    wire                            conv_output_val_count_systolic;
    wire                            conv_done_count_top;
    wire                            conv_done_top;

    // From Onedconv_Control_Wrapper - Adder-side register control
    wire                            conv_en_reg_adder;
    wire                            conv_output_result_reg_rst;

    // From Onedconv_Control_Wrapper - Top-level IO control
    wire                            conv_rst_top;
    wire                            conv_mode_top;
    wire                            conv_output_val_top;
    wire                            conv_start_top;

    // Status from Onedconv_Control_Wrapper
    wire                            conv_done_all;
    wire                            conv_done_filter;

    // ========================================================================
    // INTERNAL WIRES - Muxed Control Signals to Datapath
    // ========================================================================
    wire [NUM_BRAMS-1:0]            mux_w_re;
    wire [NUM_BRAMS*W_ADDR_W-1:0]   mux_w_addr_rd_flat;
    wire [NUM_BRAMS-1:0]            mux_if_re;
    wire [NUM_BRAMS*I_ADDR_W-1:0]   mux_if_addr_rd_flat;
    wire [3:0]                      mux_ifmap_sel;

    // ========================================================================
    // INTERNAL WIRES - Output Manager (Testing V3 Style)
    // ========================================================================
    wire                            out_mgr_ext_read_mode;
    wire [NUM_BRAMS*O_ADDR_W-1:0]   out_mgr_ext_read_addr_flat;
    wire [NUM_BRAMS*DW-1:0]         ext_read_data_flat;
    wire [NUM_BRAMS*O_ADDR_W-1:0]   bram_read_addr_flat;

    // Output Manager header injection wires
    wire [15:0] header_word_0;
    wire [15:0] header_word_1;
    wire [15:0] header_word_2;
    wire [15:0] header_word_3;
    wire [15:0] header_word_4;
    wire [15:0] header_word_5;
    wire        send_header;

    // Output Manager read control signals
    wire        out_mgr_trigger_read;
    wire [2:0]  out_mgr_rd_bram_start;
    wire [2:0]  out_mgr_rd_bram_end;
    wire [15:0] out_mgr_rd_addr_count;
    wire        out_mgr_notification_mode;
    wire        out_mgr_transmission_active;

    // TRANSCONV additional signals
    wire [4:0]  transconv_done_select;
    wire        transconv_batch_complete;

    // 1DCONV status outputs (for backward compatibility)
    wire [3:0]  conv_sched_current_layer;
    wire        conv_sched_all_done;

    // ========================================================================
    // INSTANTIATION 1: AXI WEIGHT WRAPPER (Testing V3 Style)
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

        // Read Control (from Output Manager)
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

        // BRAM Read Interface (unused in this design)
        .bram_rd_data_flat(weight_rd_data_flat_unused),
        .bram_rd_addr(weight_rd_addr_unused)
    );

    // ========================================================================
    // INSTANTIATION 2: AXI IFMAP WRAPPER (Testing V3 Style)
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

        // Output Manager Header Interface
        .header_word_0(header_word_0),
        .header_word_1(header_word_1),
        .header_word_2(header_word_2),
        .header_word_3(header_word_3),
        .header_word_4(header_word_4),
        .header_word_5(header_word_5),
        .send_header(send_header),

        // Read Control (from Output Manager)
        .out_mgr_rd_bram_start(out_mgr_rd_bram_start),
        .out_mgr_rd_bram_end(out_mgr_rd_bram_end),
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

        // BRAM Read Interface (unused in this design)
        .bram_rd_data_flat(ifmap_rd_data_flat_unused),
        .bram_rd_addr(ifmap_rd_addr_unused)
    );

    // ========================================================================
    // INSTANTIATION 2B: AXI BIAS WRAPPER (WRITE ONLY - Read Disabled)
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

        // AXI Stream Master - DISABLED (tied off)
        .m_axis_tdata(),           // Unconnected
        .m_axis_tvalid(),          // Unconnected
        .m_axis_tready(1'b1),      // Always ready (no read-back)
        .m_axis_tlast(),           // Unconnected

        // Output Manager Header Interface - DISABLED (tied to zero)
        .header_word_0(16'd0),
        .header_word_1(16'd0),
        .header_word_2(16'd0),
        .header_word_3(16'd0),
        .header_word_4(16'd0),
        .header_word_5(16'd0),
        .send_header(1'b0),        // Never send header

        // Read Control - DISABLED (tied to zero)
        .out_mgr_rd_bram_start(3'd0),
        .out_mgr_rd_bram_end(3'd0),
        .out_mgr_rd_addr_count(16'd0),
        .notification_mode(1'b0),

        // Status
        .write_done(bias_write_done),
        .read_done(),              // Unconnected (read disabled)
        .mm2s_data_count(),        // Unconnected
        .parser_state(bias_parser_state),
        .error_invalid_magic(bias_error_invalid_magic),

        // BRAM Write Interface
        .bram_wr_data_flat(bias_wr_data_flat),
        .bram_wr_addr(bias_wr_addr),
        .bram_wr_en(bias_wr_en),

        // BRAM Read Interface - DISABLED (tied off)
        .bram_rd_data_flat({8*DW{1'b0}}),  // Tie to zero
        .bram_rd_addr()                     // Unconnected
    );

    // ========================================================================
    // INSTANTIATION 3A: TRANSPOSE CONTROL TOP (TRANSCONV MODE)
    // ========================================================================
    Transpose_Control_Top #(
        .DW(DW),
        .NUM_BRAMS(NUM_BRAMS),
        .NUM_PE(Dimension),
        .ADDR_WIDTH(I_ADDR_W)
    ) transconv_control (
        .clk(aclk),
        .rst_n(aresetn),

        // Automation inputs (from AXI wrappers)
        .weight_write_done(weight_write_done),
        .ifmap_write_done(ifmap_write_done),

        // External control
        .ext_start(ext_start & conv_mode),  // Only active in TRANSCONV mode
        .ext_layer_id(ext_layer_id),

        // Status outputs
        .current_layer_id(current_layer_id),
        .current_batch_id(current_batch_id),
        .scheduler_done(scheduler_done),
        .all_batches_done(all_batches_done),
        .clear_output_bram(transconv_clear_output_bram),
        .auto_active(auto_start_active),
        .batch_complete_signal(transconv_batch_complete),

        // Weight BRAM control
        .w_re(transconv_w_re),
        .w_addr_rd_flat(transconv_w_addr_rd_flat),

        // Ifmap BRAM control
        .if_re(transconv_if_re),
        .if_addr_rd_flat(transconv_if_addr_rd_flat),
        .ifmap_sel_out(transconv_ifmap_sel),

        // Systolic array control signals
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
    // INSTANTIATION 3B: ONEDCONV CONTROL WRAPPER (1DCONV MODE)
    // ========================================================================
    Onedconv_Control_Wrapper #(
        .DW(DW),
        .Dimension(Dimension),
        .ADDRESS_LENGTH(I_ADDR_W),
        .MUX_SEL_WIDTH(MUX_SEL_WIDTH)
    ) conv_control_wrapper (
        .clk(aclk),
        .rst(aresetn),

        // Global control
        .start_whole(ext_start & ~conv_mode),  // Only active in 1DCONV mode
        .done_all(conv_done_all),
        .done_filter(conv_done_filter),

        // Weight Update Handshake
        .weight_req_top(conv_weight_req),
        .weight_ack_top(conv_weight_ack),

        // Convolution parameters
        .stride(2'd0),                // Default: stride=0 (can be extended)
        .padding(3'd0),               // Default: padding=0 (can be extended)
        .kernel_size(5'd0),           // Default: kernel_size=0 (can be extended)
        .input_channels(10'd16),      // Default: 16 input channels
        .filter_number(10'd16),       // Default: 16 output filters
        .temporal_length(10'd256),    // Default: temporal length

        // Matrix multiplication datapath inputs
        .out_new_val_sign(conv_output_val_count_systolic),

        // Counter outputs - addresses for BRAMs
        .inputdata_addr_out(conv_inputdata_addr_out),
        .weight_addr_out(conv_weight_addr_out),
        .output_addr_out_a(conv_output_addr_out_a),
        .output_addr_out_b(conv_output_addr_out_b),

        // BRAM control outputs
        .enb_inputdata_input_bram(conv_enb_inputdata_input_bram),
        .enb_weight_input_bram(conv_enb_weight_input_bram),
        .ena_output_result_control(conv_ena_output_result_control),
        .wea_output_result(conv_wea_output_result),
        .enb_output_result_control(conv_enb_output_result_control),

        // Shift-register & datapath control
        .en_shift_reg_ifmap_input_ctrl(conv_en_shift_reg_ifmap_input_ctrl),
        .en_shift_reg_weight_input_ctrl(conv_en_shift_reg_weight_input_ctrl),
        .zero_or_data(conv_zero_or_data),
        .zero_or_data_weight(conv_zero_or_data_weight),
        .sel_input_data_mem(conv_sel_input_data_mem),
        .output_bram_destination(conv_output_bram_destination),

        // Matrix multiplication control outputs
        .en_cntr_systolic(conv_en_cntr_systolic),
        .en_in_systolic(conv_en_in_systolic),
        .en_out_systolic(conv_en_out_systolic),
        .en_psum_systolic(conv_en_psum_systolic),
        .ifmaps_sel_systolic(conv_ifmaps_sel_systolic),
        .output_eject_ctrl_systolic(conv_output_eject_ctrl_systolic),
        .output_val_count_systolic(conv_output_val_count_systolic),
        .done_count_top(conv_done_count_top),
        .done_top(conv_done_top),

        // Adder-side register control
        .en_reg_adder(conv_en_reg_adder),
        .output_result_reg_rst(conv_output_result_reg_rst),

        // Top-level IO control
        .rst_top(conv_rst_top),
        .mode_top(conv_mode_top),
        .output_val_top(conv_output_val_top),
        .start_top(conv_start_top)
    );

    // Assign 1DCONV status outputs (for backward compatibility with external interface)
    assign done_all = conv_mode ? 1'b0 : conv_done_all;
    assign done_filter = conv_mode ? 1'b0 : conv_done_filter;
    assign conv_current_layer = conv_sched_current_layer;
    assign conv_all_layers_done = conv_sched_all_done;

    // Placeholder for 1DCONV scheduler status (kept for compatibility)
    // These would be driven by a 1DCONV auto-scheduler if needed
    assign conv_sched_current_layer = 4'd0;
    assign conv_sched_all_done = 1'b0;

    // ========================================================================
    // MODE-BASED CONTROL SIGNAL MUXING FOR DATAPATH
    // ========================================================================

    // Weight BRAM read control muxing
    assign mux_w_re = conv_mode ? transconv_w_re : conv_enb_weight_input_bram;

    // Generate muxed weight address - extend 1DCONV address to match width
    genvar w;
    generate
        for (w = 0; w < NUM_BRAMS; w = w + 1) begin : GEN_W_ADDR_MUX
            assign mux_w_addr_rd_flat[w*W_ADDR_W +: W_ADDR_W] = conv_mode ?
                transconv_w_addr_rd_flat[w*I_ADDR_W +: I_ADDR_W] :
                {{(W_ADDR_W-I_ADDR_W){1'b0}}, conv_weight_addr_out};
        end
    endgenerate

    // Ifmap BRAM read control muxing
    assign mux_if_re = conv_mode ? transconv_if_re : conv_enb_inputdata_input_bram;

    // Generate muxed ifmap address
    genvar f;
    generate
        for (f = 0; f < NUM_BRAMS; f = f + 1) begin : GEN_IF_ADDR_MUX
            assign mux_if_addr_rd_flat[f*I_ADDR_W +: I_ADDR_W] = conv_mode ?
                transconv_if_addr_rd_flat[f*I_ADDR_W +: I_ADDR_W] :
                conv_inputdata_addr_out;
        end
    endgenerate

    // Ifmap selector muxing
    assign mux_ifmap_sel = conv_mode ? transconv_ifmap_sel : conv_sel_input_data_mem;

    // ========================================================================
    // INSTANTIATION 4: DATAPATH (Conv_Transconv_Super_Top_Level)
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
        .Depth_added(Dimension)
    ) datapath (
        .clk(aclk),
        .rst_n(aresetn),

        // Mode control
        .conv_mode(conv_mode),
        .start_conv(conv_start_top & ~conv_mode),
        .start_transconv(1'b1),  // Always enabled for TRANSCONV

        // Weight BRAM interface
        .w_we(weight_wr_en),
        .w_addr_wr_flat({{(W_ADDR_W-W_ADDR_W){1'b0}}, {NUM_BRAMS{weight_wr_addr}}}),
        .w_din_flat(weight_wr_data_flat),
        .w_re_conv(conv_mode ? {NUM_BRAMS{1'b0}} : conv_enb_weight_input_bram),
        .w_addr_rd_conv_flat(conv_mode ? {NUM_BRAMS*W_ADDR_W{1'b0}} : 
                             {{(W_ADDR_W-I_ADDR_W){1'b0}}, {NUM_BRAMS{conv_weight_addr_out}}}),
        .w_re_transconv(conv_mode ? transconv_w_re : {NUM_BRAMS{1'b0}}),
        .w_addr_rd_transconv_flat(mux_w_addr_rd_flat),

        // Ifmap BRAM interface
        .if_we(ifmap_wr_en),
        .if_addr_wr_flat({{(I_ADDR_W-I_ADDR_W){1'b0}}, {NUM_BRAMS{ifmap_wr_addr}}}),
        .if_din_flat(ifmap_wr_data_flat),
        .if_re_conv(conv_mode ? {NUM_BRAMS{1'b0}} : conv_enb_inputdata_input_bram),
        .if_addr_rd_conv_flat(conv_mode ? {NUM_BRAMS*I_ADDR_W{1'b0}} :
                              {NUM_BRAMS{conv_inputdata_addr_out}}),
        .if_re_transconv(conv_mode ? transconv_if_re : {NUM_BRAMS{1'b0}}),
        .if_addr_rd_transconv_flat(mux_if_addr_rd_flat),
        .ifmap_sel_transconv(mux_ifmap_sel),

        // 1DCONV Control
        .conv_buffer_mode(conv_mode_top),
        .conv_en_shift_reg_ifmap_input(conv_en_shift_reg_ifmap_input_ctrl[0]),
        .conv_en_shift_reg_weight_input(conv_en_shift_reg_weight_input_ctrl[0]),
        .conv_en_shift_reg_ifmap_control(conv_en_shift_reg_ifmap_input_ctrl[0]),
        .conv_en_shift_reg_weight_control(conv_en_shift_reg_weight_input_ctrl[0]),
        .conv_en_cntr(conv_en_cntr_systolic),
        .conv_en_in(conv_en_in_systolic),
        .conv_en_out(conv_en_out_systolic),
        .conv_en_psum(conv_en_psum_systolic),
        .conv_clear_psum({NUM_BRAMS*NUM_BRAMS{1'b0}}),  // No clear in systolic
        .conv_ifmaps_sel_ctrl(conv_ifmaps_sel_systolic),
        .conv_output_eject_ctrl(conv_output_eject_ctrl_systolic),
        .conv_out_new_val_sign(conv_output_val_count_systolic),
        .conv_output_addr_wr(conv_output_addr_out_a),
        .conv_output_addr_rd(conv_output_addr_out_b),
        .conv_ena_output(conv_ena_output_result_control),
        .conv_wea_output(conv_wea_output_result),
        .conv_enb_output(conv_enb_output_result_control),
        .conv_en_reg_adder(conv_en_reg_adder),
        .conv_output_reg_rst(conv_output_result_reg_rst),
        .conv_output_bram_dest(conv_output_bram_destination),
        .input_bias(input_bias),
        .bias_ena(input_bias ? bias_ena : bias_wr_en),
        .bias_wea(input_bias ? bias_wea : bias_wr_en),
        .bias_addr(input_bias ? bias_addr : bias_wr_addr),
        .bias_data(input_bias ? bias_data : bias_wr_data_flat),

        // TRANSCONV Control Inputs
        .transconv_en_weight_load(transconv_en_weight_load),
        .transconv_en_ifmap_load(transconv_en_ifmap_load),
        .transconv_en_psum(transconv_en_psum),
        .transconv_clear_psum(transconv_clear_psum | {NUM_BRAMS{transconv_clear_output_bram}}),
        .transconv_en_output(transconv_en_output),
        .transconv_ifmap_sel_ctrl(transconv_ifmap_sel_ctrl),
        .transconv_done_select(transconv_done_select),

        // Mapping configuration (TRANSCONV)
        .cmap(transconv_cmap_snapshot),
        .omap_flat(transconv_omap_snapshot),

        // External read interface
        .ext_read_mode(out_mgr_ext_read_mode | ext_read_mode),
        .ext_read_addr_flat(out_mgr_ext_read_mode ? out_mgr_ext_read_addr_flat :
                            {NUM_BRAMS{ext_output_addr}}),

        // Outputs
        .bram_read_data_flat(ext_read_data_flat),
        .bram_read_addr_flat(bram_read_addr_flat)
    );

    // Output result assignment
    assign output_result = ext_read_data_flat;

    // ========================================================================
    // INSTANTIATION 5: OUTPUT MANAGER (Testing V3 Style - Output_Manager_Simple)
    // ========================================================================
    Output_Manager_Simple #(
        .DW(DW)
    ) output_mgr (
        .clk(aclk),
        .rst_n(aresetn),

        // Status Inputs
        .batch_complete(conv_mode ? transconv_batch_complete : conv_done_filter),
        .current_batch_id(conv_mode ? current_batch_id : 3'd0),
        .all_batches_done(conv_mode ? all_batches_done : conv_done_all),
        .completed_layer_id(conv_mode ? current_layer_id : 2'd0),

        // Header Data Outputs (connected to wrappers)
        .header_word_0(header_word_0),
        .header_word_1(header_word_1),
        .header_word_2(header_word_2),
        .header_word_3(header_word_3),
        .header_word_4(header_word_4),
        .header_word_5(header_word_5),

        // Control Outputs
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

    // FIX: ext_read_mode dikontrol oleh transmission_active
    assign out_mgr_ext_read_mode = out_mgr_transmission_active;

    // ========================================================================
    // OUTPUT STREAM ROUTING (Testing V3 Style)
    // ========================================================================
    // In Testing V3 architecture, output data is sent through m0_axis (weight wrapper)
    // and m1_axis (ifmap wrapper). The separate m_output_axis is deprecated.
    // Route m_output_axis to m0_axis for backward compatibility.
    assign m_output_axis_tdata  = m0_axis_tdata;
    assign m_output_axis_tvalid = m0_axis_tvalid;
    assign m_output_axis_tlast  = m0_axis_tlast;

endmodule