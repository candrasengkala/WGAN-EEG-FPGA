`timescale 1ns / 1ps

/******************************************************************************
 * Module: Inference_Top_Level
 *
 * Description:
 *   Complete inference system top-level integrating:
 *   1. layer_sequencer - Manages layer-by-layer execution
 *   2. Conv_Transconv_System_Top_Level - Unified datapath for Conv/Transconv
 *
 *   Implements the U-Net-ish generator architecture for EEG denoising:
 *   - Encoder: 4 Conv layers (e1-e4)
 *   - Bottleneck: N MultiScale ResBlocks
 *   - Decoder: 4 Transposed Conv layers (d1-d4)
 *   - Output: 1 Conv layer
 *
 * Interface:
 *   - AXI Stream for weight/ifmap loading from PS
 *   - AXI Stream for output results to PS
 *   - Simple start/done handshaking
 *
 * Author: Integrated Inference System
 * Date: January 2026
 ******************************************************************************/

module Inference_Top_Level #(
    parameter DW              = 16,
    parameter NUM_BRAMS       = 16,
    parameter W_ADDR_W        = 11,
    parameter I_ADDR_W        = 10,
    parameter O_ADDR_W        = 10,
    parameter W_DEPTH         = 2048,
    parameter I_DEPTH         = 1024,
    parameter O_DEPTH         = 1024,
    parameter Dimension       = 16,
    parameter MUX_SEL_WIDTH   = 4,
    parameter BASE_CH         = 32,
    parameter BOTTLENECK_BLOCKS = 4,
    parameter INITIAL_TEMPORAL = 512
)(
    input  wire aclk,
    input  wire aresetn,

    // ========================================================================
    // Inference Control
    // ========================================================================
    input  wire        start_inference,    // Start full inference
    output wire        inference_done,     // All layers complete

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
    // Debug & Status Outputs
    // ========================================================================
    output wire [4:0]     current_layer,
    output wire [3:0]     layer_type,
    output wire           is_encoder,
    output wire           is_bottleneck,
    output wire           is_decoder,
    output wire           weight_write_done,
    output wire           ifmap_write_done
);

    // ========================================================================
    // Internal Wires - Layer Sequencer to Compute System
    // ========================================================================
    wire        seq_layer_start;
    wire        seq_request_weights;
    wire        seq_conv_mode;
    wire [1:0]  seq_stride;
    wire [2:0]  seq_padding;
    wire [4:0]  seq_kernel_size;
    wire [9:0]  seq_input_channels;
    wire [9:0]  seq_filter_number;
    wire [9:0]  seq_temporal_length;

    wire [1:0]  seq_skip_write_idx;
    wire        seq_skip_write_en;
    wire [1:0]  seq_skip_read_idx;
    wire        seq_skip_read_en;

    // Layer done feedback
    wire        layer_done;
    wire        weight_loaded;

    // Compute system outputs
    wire        done_all;
    wire        done_filter;
    wire        scheduler_done;
    wire [1:0]  current_layer_id;
    wire [2:0]  current_batch_id;
    wire        all_batches_done;

    // ========================================================================
    // Layer Sequencer Instance
    // ========================================================================
    layer_sequencer #(
        .BASE_CH(BASE_CH),
        .BOTTLENECK_BLOCKS(BOTTLENECK_BLOCKS),
        .INITIAL_TEMPORAL(INITIAL_TEMPORAL)
    ) u_layer_sequencer (
        .clk(aclk),
        .rst_n(aresetn),

        // Control
        .start(start_inference),
        .layer_done(layer_done),
        .weight_loaded(weight_loaded),

        .layer_start(seq_layer_start),
        .request_weights(seq_request_weights),
        .inference_done(inference_done),

        // Layer configuration
        .conv_mode(seq_conv_mode),
        .stride(seq_stride),
        .padding(seq_padding),
        .kernel_size(seq_kernel_size),
        .input_channels(seq_input_channels),
        .filter_number(seq_filter_number),
        .temporal_length(seq_temporal_length),

        // Layer identification
        .current_layer(current_layer),
        .layer_type(layer_type),
        .is_encoder(is_encoder),
        .is_bottleneck(is_bottleneck),
        .is_decoder(is_decoder),

        // Skip connections
        .skip_write_idx(seq_skip_write_idx),
        .skip_write_en(seq_skip_write_en),
        .skip_read_idx(seq_skip_read_idx),
        .skip_read_en(seq_skip_read_en)
    );

    // ========================================================================
    // Layer Done Logic
    // ========================================================================
    // Layer is done when either:
    // - 1DCONV: done_all from onedconv_ctrl
    // - TRANSCONV: all_batches_done from Transpose_Control_Top
    assign layer_done = seq_conv_mode ? all_batches_done : done_all;

    // Weight loaded when AXI wrapper signals write_done
    assign weight_loaded = weight_write_done;

    // ========================================================================
    // Conv_Transconv_System_Top_Level Instance
    // ========================================================================
    Conv_Transconv_System_Top_Level #(
        .DW(DW),
        .NUM_BRAMS(NUM_BRAMS),
        .W_ADDR_W(W_ADDR_W),
        .I_ADDR_W(I_ADDR_W),
        .O_ADDR_W(O_ADDR_W),
        .W_DEPTH(W_DEPTH),
        .I_DEPTH(I_DEPTH),
        .O_DEPTH(O_DEPTH),
        .Dimension(Dimension),
        .MUX_SEL_WIDTH(MUX_SEL_WIDTH)
    ) u_compute_system (
        .aclk(aclk),
        .aresetn(aresetn),

        // Mode selection
        .conv_mode(seq_conv_mode),

        // AXI Stream 0 - Weight
        .s0_axis_tdata(s0_axis_tdata),
        .s0_axis_tvalid(s0_axis_tvalid),
        .s0_axis_tready(s0_axis_tready),
        .s0_axis_tlast(s0_axis_tlast),
        .m0_axis_tdata(m0_axis_tdata),
        .m0_axis_tvalid(m0_axis_tvalid),
        .m0_axis_tready(m0_axis_tready),
        .m0_axis_tlast(m0_axis_tlast),

        // AXI Stream 1 - Ifmap
        .s1_axis_tdata(s1_axis_tdata),
        .s1_axis_tvalid(s1_axis_tvalid),
        .s1_axis_tready(s1_axis_tready),
        .s1_axis_tlast(s1_axis_tlast),
        .m1_axis_tdata(m1_axis_tdata),
        .m1_axis_tvalid(m1_axis_tvalid),
        .m1_axis_tready(m1_axis_tready),
        .m1_axis_tlast(m1_axis_tlast),

        // AXI Stream 2 - Output
        .m_output_axis_tdata(m_output_axis_tdata),
        .m_output_axis_tvalid(m_output_axis_tvalid),
        .m_output_axis_tready(m_output_axis_tready),
        .m_output_axis_tlast(m_output_axis_tlast),

        // Control
        .ext_start(seq_layer_start),
        .ext_layer_id(2'b00),

        // 1DCONV Parameters (from sequencer)
        .stride(seq_stride),
        .padding(seq_padding),
        .kernel_size(seq_kernel_size),
        .input_channels(seq_input_channels),
        .filter_number(seq_filter_number),
        .temporal_length(seq_temporal_length),

        // Status outputs
        .done_all(done_all),
        .done_filter(done_filter),
        .scheduler_done(scheduler_done),
        .current_layer_id(current_layer_id),
        .current_batch_id(current_batch_id),
        .all_batches_done(all_batches_done),

        // Bias (not used in this configuration)
        .input_bias(1'b0),
        .bias_ena({NUM_BRAMS{1'b0}}),
        .bias_wea({NUM_BRAMS{1'b0}}),
        .bias_addr({O_ADDR_W{1'b0}}),
        .bias_data({(NUM_BRAMS*DW){1'b0}}),

        // External read (not used)
        .ext_read_mode(1'b0),
        .ext_enb_output({NUM_BRAMS{1'b0}}),
        .ext_output_addr({O_ADDR_W{1'b0}}),
        .output_result(),

        // Debug
        .weight_write_done(weight_write_done),
        .weight_read_done(),
        .ifmap_write_done(ifmap_write_done),
        .ifmap_read_done(),
        .weight_mm2s_data_count(),
        .ifmap_mm2s_data_count(),
        .weight_parser_state(),
        .weight_error_invalid_magic(),
        .ifmap_parser_state(),
        .ifmap_error_invalid_magic(),
        .auto_start_active()
    );

endmodule
