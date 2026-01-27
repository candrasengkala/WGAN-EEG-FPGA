`timescale 1ns / 1ps

/******************************************************************************
 * Module: Conv_Transconv_System_Top_Level
 *
 * Description:
 *   Top-level system integration for BOTH Normal Convolution (1DCONV) and
 *   Transposed Convolution (TRANSCONV) operations with CLEAN separation:
 *
 *   1. AXI Wrappers (Weight & Ifmap loading via DMA)
 *   2. Conv_Transconv_Control_Top (Unified control with mode selection)
 *   3. Conv_Transconv_Super_Top_Level (Unified datapath)
 *   4. Output_Stream_Manager (Result transmission to PS)
 *
 * Mode Selection:
 *   - conv_mode = 0: Normal 1D Convolution (uses onedconv_ctrl)
 *   - conv_mode = 1: Transposed Convolution (uses Transpose_Control_Top)
 *
 * Features:
 *   - Shared Weight/Ifmap BRAMs for both modes
 *   - Mode-aware control signal routing
 *   - Multi-layer support for TRANSCONV (Layer 0: 8 batches, Layer 1: 4 batches)
 *   - Automatic batch management via Auto_Scheduler (TRANSCONV mode)
 *   - Weight update handshaking (1DCONV mode)
 *   - AXI Stream output for result transmission
 *
 * Author: Integrated Design
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
    // INTERNAL WIRES - 1DCONV Auto Scheduler Signals
    // ========================================================================
    wire                            conv_sched_start_whole;
    wire                            conv_sched_weight_ack;
    wire [1:0]                      conv_sched_stride;
    wire [2:0]                      conv_sched_padding;
    wire [4:0]                      conv_sched_kernel_size;
    wire [9:0]                      conv_sched_input_channels;
    wire [9:0]                      conv_sched_filter_number;
    wire [9:0]                      conv_sched_temporal_length;
    wire [3:0]                      conv_sched_current_layer;
    wire                            conv_sched_all_done;

    // ========================================================================
    // INTERNAL WIRES - 1DCONV Control Signals
    // ========================================================================
    wire                            conv_weight_req;
    wire                            conv_weight_ack;

    // Counter signals
    wire                            conv_ifmap_counter_en;
    wire                            conv_ifmap_counter_rst;
    wire                            conv_ifmap_counter_done;
    wire                            conv_ifmap_flag_1per16;
    wire [I_ADDR_W-1:0]             conv_ifmap_counter_start_val;
    wire [I_ADDR_W-1:0]             conv_ifmap_counter_end_val;
    wire [I_ADDR_W-1:0]             conv_ifmap_addr_out;

    wire                            conv_weight_counter_en;
    wire                            conv_weight_counter_rst;
    wire                            conv_weight_rst_min_16;
    wire                            conv_weight_counter_done;
    wire                            conv_weight_flag_1per16;
    wire [I_ADDR_W-1:0]             conv_weight_counter_start_val;
    wire [I_ADDR_W-1:0]             conv_weight_counter_end_val;
    wire [I_ADDR_W-1:0]             conv_weight_addr_out;

    wire                            conv_output_counter_en_a;
    wire                            conv_output_counter_rst_a;
    wire                            conv_output_counter_done_a;
    wire                            conv_output_flag_1per16_a;
    wire [I_ADDR_W-1:0]             conv_output_counter_start_val_a;
    wire [I_ADDR_W-1:0]             conv_output_counter_end_val_a;
    wire [I_ADDR_W-1:0]             conv_output_addr_out_a;

    wire                            conv_output_counter_en_b;
    wire                            conv_output_counter_rst_b;
    wire                            conv_output_counter_done_b;
    wire                            conv_output_flag_1per16_b;
    wire [I_ADDR_W-1:0]             conv_output_counter_start_val_b;
    wire [I_ADDR_W-1:0]             conv_output_counter_end_val_b;
    wire [I_ADDR_W-1:0]             conv_output_addr_out_b;

    // BRAM control
    wire [NUM_BRAMS-1:0]            conv_enb_inputdata;
    wire [NUM_BRAMS-1:0]            conv_enb_weight;
    wire [NUM_BRAMS-1:0]            conv_ena_output;
    wire [NUM_BRAMS-1:0]            conv_wea_output;
    wire [NUM_BRAMS-1:0]            conv_enb_output;

    // Shift register & datapath control
    wire [NUM_BRAMS-1:0]            conv_en_shift_reg_ifmap;
    wire [NUM_BRAMS-1:0]            conv_en_shift_reg_weight;
    wire                            conv_zero_or_data;
    wire                            conv_zero_or_data_weight;
    wire [MUX_SEL_WIDTH-1:0]        conv_sel_input_data_mem;
    wire                            conv_output_bram_dest;

    // Adder control
    wire                            conv_en_reg_adder;
    wire                            conv_output_reg_rst;

    // Top-level IO control
    wire                            conv_rst_top;
    wire                            conv_mode_top;
    wire                            conv_output_val_top;
    wire                            conv_start_top;
    wire                            conv_done_count_top;
    wire                            conv_done_top;
    wire                            conv_out_new_val_sign;

    // ========================================================================
    // INTERNAL WIRES - Muxed Control Signals to Datapath
    // ========================================================================
    wire [NUM_BRAMS-1:0]            mux_w_re;
    wire [NUM_BRAMS*W_ADDR_W-1:0]   mux_w_addr_rd_flat;
    wire [NUM_BRAMS-1:0]            mux_if_re;
    wire [NUM_BRAMS*I_ADDR_W-1:0]   mux_if_addr_rd_flat;
    wire [3:0]                      mux_ifmap_sel;

    // ========================================================================
    // INTERNAL WIRES - Output Manager
    // ========================================================================
    wire                            out_mgr_ext_read_mode;
    wire [NUM_BRAMS*O_ADDR_W-1:0]   out_mgr_ext_read_addr_flat;
    wire [NUM_BRAMS*DW-1:0]         ext_read_data_flat;
    wire [NUM_BRAMS*O_ADDR_W-1:0]   bram_read_addr_flat;

    // ========================================================================
    // INSTANTIATION 1: AXI WEIGHT WRAPPER
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
        .bram_rd_data_flat(weight_rd_data_flat_unused),
        .bram_rd_addr(weight_rd_addr_unused)
    );

    // ========================================================================
    // INSTANTIATION 2: AXI IFMAP WRAPPER
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
        .bram_rd_data_flat(ifmap_rd_data_flat_unused),
        .bram_rd_addr(ifmap_rd_addr_unused)
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
        .mapper_done_pulse()
    );

    // ========================================================================
    // INSTANTIATION 3B: 1DCONV COUNTERS
    // ========================================================================

    // Ifmap Counter
    counter_axon_addr_inputdata #(
        .ADDRESS_LENGTH(I_ADDR_W)
    ) conv_ifmap_counter (
        .clk(aclk),
        .rst(conv_ifmap_counter_rst),
        .en(conv_ifmap_counter_en),
        .start_val(conv_ifmap_counter_start_val),
        .end_val(conv_ifmap_counter_end_val),
        .flag_1per16(conv_ifmap_flag_1per16),
        .addr_out(conv_ifmap_addr_out),
        .done(conv_ifmap_counter_done)
    );

    // Weight Counter
    counter_axon_addr_weight #(
        .ADDRESS_LENGTH(I_ADDR_W)
    ) conv_weight_counter (
        .clk(aclk),
        .rst(conv_weight_counter_rst),
        .rst_min_16(conv_weight_rst_min_16),
        .en(conv_weight_counter_en),
        .start_val(conv_weight_counter_start_val),
        .end_val(conv_weight_counter_end_val),
        .flag_1per16(conv_weight_flag_1per16),
        .addr_out(conv_weight_addr_out),
        .done(conv_weight_counter_done)
    );

    // Output Counter A (Writing)
    counter_axon_addr_inputdata #(
        .ADDRESS_LENGTH(I_ADDR_W)
    ) conv_output_counter_a (
        .clk(aclk),
        .rst(conv_output_counter_rst_a),
        .en(conv_output_counter_en_a),
        .start_val(conv_output_counter_start_val_a),
        .end_val(conv_output_counter_end_val_a),
        .flag_1per16(conv_output_flag_1per16_a),
        .addr_out(conv_output_addr_out_a),
        .done(conv_output_counter_done_a)
    );

    // Output Counter B (Reading)
    counter_axon_addr_inputdata #(
        .ADDRESS_LENGTH(I_ADDR_W)
    ) conv_output_counter_b (
        .clk(aclk),
        .rst(conv_output_counter_rst_b),
        .en(conv_output_counter_en_b),
        .start_val(conv_output_counter_start_val_b),
        .end_val(conv_output_counter_end_val_b),
        .flag_1per16(conv_output_flag_1per16_b),
        .addr_out(conv_output_addr_out_b),
        .done(conv_output_counter_done_b)
    );

    // ========================================================================
    // INSTANTIATION 3B-1: 1DCONV AUTO SCHEDULER (Layer Sequencing)
    // ========================================================================
    Onedconv_Auto_Scheduler #(
        .DW(DW)
    ) conv_auto_scheduler (
        .clk(aclk),
        .rst_n(aresetn),

        // Trigger
        .start(ext_start & ~conv_mode),  // Only active in 1DCONV mode

        // Inputs from AXI Wrappers
        .weight_write_done(weight_write_done),
        .ifmap_write_done(ifmap_write_done),

        // Inputs from onedconv_ctrl
        .done_all(done_all),
        .done_filter(done_filter),
        .weight_req_top(conv_weight_req),

        // Outputs to onedconv_ctrl
        .weight_ack_top(conv_sched_weight_ack),
        .start_whole(conv_sched_start_whole),

        // Configuration Outputs to onedconv_ctrl
        .stride(conv_sched_stride),
        .padding(conv_sched_padding),
        .kernel_size(conv_sched_kernel_size),
        .input_channels(conv_sched_input_channels),
        .filter_number(conv_sched_filter_number),
        .temporal_length(conv_sched_temporal_length),

        // Status Outputs
        .current_layer_id(conv_sched_current_layer),
        .all_layers_done(conv_sched_all_done)
    );

    // Assign 1DCONV status outputs
    assign conv_current_layer = conv_sched_current_layer;
    assign conv_all_layers_done = conv_sched_all_done;

    // ========================================================================
    // INSTANTIATION 3C: 1DCONV CONTROL FSM
    // ========================================================================
    onedconv_ctrl #(
        .DW(DW),
        .Dimension(Dimension),
        .ADDRESS_LENGTH(I_ADDR_W),
        .MUX_SEL_WIDTH(MUX_SEL_WIDTH)
    ) conv_control (
        .clk(aclk),
        .rst(aresetn),

        // Global control - driven by Auto Scheduler
        .start_whole(conv_sched_start_whole),
        .done_all(done_all),
        .done_filter(done_filter),
        .weight_req_top(conv_weight_req),
        .weight_ack_top(conv_sched_weight_ack),

        // Convolution parameters - from Auto Scheduler ROM
        .stride(conv_sched_stride),
        .padding(conv_sched_padding),
        .kernel_size(conv_sched_kernel_size),
        .input_channels(conv_sched_input_channels),
        .filter_number(conv_sched_filter_number),
        .temporal_length(conv_sched_temporal_length),

        // Counter status inputs
        .ifmap_counter_done(conv_ifmap_counter_done),
        .ifmap_flag_1per16(conv_ifmap_flag_1per16),
        .weight_counter_done(conv_weight_counter_done),
        .weight_flag_1per16(conv_weight_flag_1per16),
        .output_counter_done_a(conv_output_counter_done_a),
        .output_flag_1per16_a(conv_output_flag_1per16_a),
        .output_counter_done_b(conv_output_counter_done_b),
        .output_flag_1per16_b(conv_output_flag_1per16_b),

        // Datapath status inputs
        .done_count_top(conv_done_count_top),
        .done_top(conv_done_top),
        .out_new_val_sign(conv_out_new_val_sign),

        // Counter control outputs
        .ifmap_counter_en(conv_ifmap_counter_en),
        .ifmap_counter_rst(conv_ifmap_counter_rst),
        .en_weight_counter(conv_weight_counter_en),
        .weight_rst_min_16(conv_weight_rst_min_16),
        .weight_counter_rst(conv_weight_counter_rst),
        .en_output_counter_a(conv_output_counter_en_a),
        .output_counter_rst_a(conv_output_counter_rst_a),
        .en_output_counter_b(conv_output_counter_en_b),
        .output_counter_rst_b(conv_output_counter_rst_b),

        // Counter address values
        .ifmap_counter_start_val(conv_ifmap_counter_start_val),
        .ifmap_counter_end_val(conv_ifmap_counter_end_val),
        .weight_counter_start_val(conv_weight_counter_start_val),
        .weight_counter_end_val(conv_weight_counter_end_val),
        .output_counter_start_val_a(conv_output_counter_start_val_a),
        .output_counter_end_val_a(conv_output_counter_end_val_a),
        .output_counter_start_val_b(conv_output_counter_start_val_b),
        .output_counter_end_val_b(conv_output_counter_end_val_b),

        // BRAM control outputs
        .enb_inputdata_input_bram(conv_enb_inputdata),
        .enb_weight_input_bram(conv_enb_weight),
        .ena_output_result_control(conv_ena_output),
        .wea_output_result(conv_wea_output),
        .enb_output_result_control(conv_enb_output),

        // Shift-register & datapath control
        .en_shift_reg_ifmap_input_ctrl(conv_en_shift_reg_ifmap),
        .en_shift_reg_weight_input_ctrl(conv_en_shift_reg_weight),
        .zero_or_data(conv_zero_or_data),
        .zero_or_data_weight(conv_zero_or_data_weight),
        .sel_input_data_mem(conv_sel_input_data_mem),
        .output_bram_destination(conv_output_bram_dest),

        // Adder-side register control
        .en_reg_adder(conv_en_reg_adder),
        .output_result_reg_rst(conv_output_reg_rst),

        // Top-level IO control
        .rst_top(conv_rst_top),
        .mode_top(conv_mode_top),
        .output_val_top(conv_output_val_top),
        .start_top(conv_start_top)
    );

    // ========================================================================
    // MODE-BASED CONTROL SIGNAL MUXING
    // ========================================================================

    // Weight BRAM read control muxing
    assign mux_w_re = conv_mode ? transconv_w_re : conv_enb_weight;

    // Generate muxed weight address - extend 1DCONV address to match width
    genvar w;
    generate
        for (w = 0; w < NUM_BRAMS; w = w + 1) begin : GEN_W_ADDR_MUX
            assign mux_w_addr_rd_flat[w*W_ADDR_W +: W_ADDR_W] = conv_mode ?
                transconv_w_addr_rd_flat[w*I_ADDR_W +: I_ADDR_W] :  // Zero-extend
                {{(W_ADDR_W-I_ADDR_W){1'b0}}, conv_weight_addr_out};
        end
    endgenerate

    // Ifmap BRAM read control muxing
    assign mux_if_re = conv_mode ? transconv_if_re : conv_enb_inputdata;

    // Generate muxed ifmap address
    genvar f;
    generate
        for (f = 0; f < NUM_BRAMS; f = f + 1) begin : GEN_IF_ADDR_MUX
            assign mux_if_addr_rd_flat[f*I_ADDR_W +: I_ADDR_W] = conv_mode ?
                transconv_if_addr_rd_flat[f*I_ADDR_W +: I_ADDR_W] :
                conv_ifmap_addr_out;
        end
    endgenerate

    // Ifmap selector muxing
    assign mux_ifmap_sel = conv_mode ? transconv_ifmap_sel : conv_sel_input_data_mem;

    // ========================================================================
    // INSTANTIATION 4: UNIFIED DATAPATH (Conv_Transconv_Super_Top_Level)
    // ========================================================================
    Conv_Transconv_Super_Top_Level #(
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

        // Mode selection
        .conv_mode(conv_mode),

        // Weight BRAM interface
        .w_we(weight_wr_en),
        .w_addr_wr_flat({NUM_BRAMS{weight_wr_addr}}),
        .w_din_flat(weight_wr_data_flat),
        .w_re(mux_w_re),
        .w_addr_rd_flat(mux_w_addr_rd_flat),

        // Ifmap BRAM interface
        .if_we(ifmap_wr_en),
        .if_addr_wr_flat({NUM_BRAMS{ifmap_wr_addr}}),
        .if_din_flat(ifmap_wr_data_flat),
        .if_re(mux_if_re),
        .if_addr_rd_flat(mux_if_addr_rd_flat),
        .ifmap_sel(mux_ifmap_sel),

        // 1DCONV Control Inputs
        .conv_buffer_mode(conv_mode_top),
        .conv_en_shift_reg_ifmap_input(|conv_en_shift_reg_ifmap),
        .conv_en_shift_reg_weight_input(|conv_en_shift_reg_weight),
        .conv_en_shift_reg_ifmap_control(|conv_en_shift_reg_ifmap),
        .conv_en_shift_reg_weight_control(|conv_en_shift_reg_weight),
        .conv_en_cntr(conv_start_top),
        .conv_en_in({(NUM_BRAMS*NUM_BRAMS){conv_start_top}}),
        .conv_en_out({(NUM_BRAMS*NUM_BRAMS){conv_output_val_top}}),
        .conv_en_psum({(NUM_BRAMS*NUM_BRAMS){conv_start_top}}),
        .conv_clear_psum({(NUM_BRAMS*NUM_BRAMS){~conv_rst_top}}),
        .conv_ifmaps_sel_ctrl({NUM_BRAMS{conv_zero_or_data}}),
        .conv_output_eject_ctrl({NUM_BRAMS{conv_output_val_top}}),

        // 1DCONV Output BRAM control
        .conv_out_new_val_sign(conv_out_new_val_sign),
        .conv_output_addr_wr(conv_output_addr_out_a),
        .conv_output_addr_rd(ext_read_mode ? ext_output_addr : conv_output_addr_out_b),
        .conv_ena_output(conv_ena_output),
        .conv_wea_output(conv_wea_output),
        .conv_enb_output(ext_read_mode ? ext_enb_output : conv_enb_output),
        .conv_en_reg_adder(conv_en_reg_adder),
        .conv_output_reg_rst(conv_output_reg_rst),
        .conv_output_bram_dest(conv_output_bram_dest),

        // Bias control
        .input_bias(input_bias),
        .bias_ena(bias_ena),
        .bias_wea(bias_wea),
        .bias_addr(bias_addr),
        .bias_data(bias_data),

        // TRANSCONV Control Inputs
        .transconv_en_weight_load(transconv_en_weight_load),
        .transconv_en_ifmap_load(transconv_en_ifmap_load),
        .transconv_en_psum(transconv_en_psum),
        .transconv_clear_psum(transconv_clear_psum | {NUM_BRAMS{transconv_clear_output_bram}}),
        .transconv_en_output(transconv_en_output),
        .transconv_ifmap_sel_ctrl(transconv_ifmap_sel_ctrl),
        .transconv_done_select(5'd0),

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
    // INSTANTIATION 5: OUTPUT STREAM MANAGER
    // ========================================================================
    output_stream_manager #(
        .DW(DW),
        .NUM_BRAMS(NUM_BRAMS),
        .ADDR_WIDTH(O_ADDR_W),
        .OUTPUT_DEPTH(O_DEPTH)
    ) output_mgr (
        .clk(aclk),
        .rst_n(aresetn),

        // Triggers from control
        .batch_complete(1'b0),
        .completed_batch_id(current_batch_id),
        .all_batches_complete(conv_mode ? all_batches_done : done_all),

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

    // ========================================================================
    // 1DCONV INTERNAL COUNTERS FOR DATAPATH FEEDBACK
    // ========================================================================

    // Internal counter wires
    wire conv_done_ifmap_internal;
    wire conv_done_weight_internal;
    wire conv_out_new_val_internal;
    wire conv_done_all_internal;
    wire conv_done_count_internal;

    // Internal control wires from matrix_mult_control
    wire                            mmc_en_ifmap_counter;
    wire                            mmc_en_weight_counter;
    wire [Dimension-1:0]            mmc_en_shift_reg_ifmap;
    wire [Dimension-1:0]            mmc_en_shift_reg_weight;
    wire                            mmc_en_cntr;
    wire [Dimension*Dimension-1:0]  mmc_en_in;
    wire [Dimension*Dimension-1:0]  mmc_en_out;
    wire [Dimension*Dimension-1:0]  mmc_en_psum;
    wire [Dimension-1:0]            mmc_ifmaps_sel;
    wire                            mmc_output_val_count;
    wire [Dimension-1:0]            mmc_output_eject_ctrl;

    // Ifmap shift counter (for 1DCONV internal timing)
    counter_input #(
        .Dimension_added(Dimension + 1)
    ) conv_internal_ifmap_counter (
        .clk(aclk),
        .rst(aresetn & ~conv_mode),  // Only active in 1DCONV mode
        .en(mmc_en_ifmap_counter),
        .done(conv_done_ifmap_internal)
    );

    // Weight shift counter
    counter_input #(
        .Dimension_added(Dimension + 1)
    ) conv_internal_weight_counter (
        .clk(aclk),
        .rst(aresetn & ~conv_mode),
        .en(mmc_en_weight_counter),
        .done(conv_done_weight_internal)
    );

    // Output counter
    counter_output #(
        .Dimension(Dimension)
    ) conv_internal_output_counter (
        .clk(aclk),
        .rst(aresetn & ~conv_mode),
        .en(mmc_output_val_count),
        .done(conv_out_new_val_internal)
    );

    // Top-level counter for done_count (counts Dimension*Dimension cycles)
    counter_top_lvl #(
        .Dimension(Dimension)
    ) conv_done_counter (
        .clk(aclk),
        .rst(aresetn & ~conv_mode),
        .en(mmc_en_cntr),
        .done(conv_done_count_internal)
    );

    // Matrix Multiply Control FSM (for 1DCONV mode)
    matrix_mult_control #(
        .DW(DW),
        .Dimension(Dimension)
    ) conv_matrix_mult_ctrl (
        .clk(aclk),
        .rst(aresetn),

        .start(conv_start_top & ~conv_mode),  // Only in 1DCONV mode

        .done_ifmap(conv_done_ifmap_internal),
        .done_weight(conv_done_weight_internal),
        .done_count(conv_done_count_internal),

        .output_val(conv_output_val_top),
        .out_new_val(conv_out_new_val_internal),

        .en_ifmap_counter(mmc_en_ifmap_counter),
        .en_weight_counter(mmc_en_weight_counter),

        .en_shift_reg_ifmap(mmc_en_shift_reg_ifmap),
        .en_shift_reg_weight(mmc_en_shift_reg_weight),

        .en_cntr(mmc_en_cntr),
        .en_in(mmc_en_in),
        .en_out(mmc_en_out),
        .en_psum(mmc_en_psum),

        .ifmaps_sel(mmc_ifmaps_sel),

        .done_all(conv_done_all_internal),
        .output_val_count(mmc_output_val_count),
        .output_eject_ctrl(mmc_output_eject_ctrl)
    );

    // Assign feedback signals to onedconv_ctrl
    assign conv_done_count_top = conv_done_count_internal;
    assign conv_done_top = conv_done_all_internal;
    assign conv_out_new_val_sign = conv_out_new_val_internal;

endmodule
