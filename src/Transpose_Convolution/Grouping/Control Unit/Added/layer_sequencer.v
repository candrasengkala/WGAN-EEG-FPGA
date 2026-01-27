`timescale 1ns / 1ps

/******************************************************************************
 * Module: layer_sequencer
 *
 * Description:
 *   Layer Sequencer FSM for multi-layer CNN inference.
 *   Manages layer-by-layer execution of the U-Net-ish generator architecture:
 *
 *   ENCODER (1D Convolution - conv_mode=0):
 *     e1: in=1,   out=32,  k=16, s=2, p=7, temporal: 512→256
 *     e2: in=32,  out=64,  k=16, s=2, p=7, temporal: 256→128
 *     e3: in=64,  out=128, k=16, s=2, p=7, temporal: 128→64
 *     e4: in=128, out=256, k=16, s=2, p=7, temporal: 64→32
 *
 *   BOTTLENECK (MultiScale ResBlocks - conv_mode=0):
 *     For each of N blocks, run 3 parallel branches + fuse:
 *       b3: k=3, s=1, p=1
 *       b5: k=5, s=1, p=2
 *       b7: k=7, s=1, p=3
 *       fuse: k=1, s=1, p=0
 *     All maintain ch=256, temporal=32
 *
 *   DECODER (Transpose Convolution - conv_mode=1):
 *     d1: in=256, out=128, k=4, s=2, p=1, temporal: 32→64
 *     d2: in=256, out=64,  k=4, s=2, p=1, temporal: 64→128  (concat)
 *     d3: in=128, out=32,  k=4, s=2, p=1, temporal: 128→256 (concat)
 *     d4: in=64,  out=16,  k=4, s=2, p=1, temporal: 256→512 (concat)
 *
 *   OUTPUT HEAD (1D Convolution - conv_mode=0):
 *     out: in=16, out=1, k=7, s=1, p=3, temporal: 512→512
 *
 * Features:
 *   - Configurable base_ch parameter
 *   - Configurable number of bottleneck blocks
 *   - Automatic layer parameter output
 *   - Skip connection management for U-Net
 *   - Handshaking with Conv_Transconv_System_Top_Level
 *
 * Author: Auto-generated Layer Sequencer
 * Date: January 2026
 ******************************************************************************/

module layer_sequencer #(
    parameter BASE_CH = 32,           // Base channel count
    parameter BOTTLENECK_BLOCKS = 4,  // Number of residual blocks in bottleneck
    parameter INITIAL_TEMPORAL = 512  // Initial temporal length
)(
    input  wire        clk,
    input  wire        rst_n,

    // ========================================================================
    // Control Interface
    // ========================================================================
    input  wire        start,           // Start inference
    input  wire        layer_done,      // Current layer computation done
    input  wire        weight_loaded,   // Weights for current layer loaded

    output reg         layer_start,     // Start current layer computation
    output reg         request_weights, // Request weight loading for current layer
    output reg         inference_done,  // All layers complete

    // ========================================================================
    // Layer Configuration Outputs
    // ========================================================================
    output reg         conv_mode,       // 0=1DCONV, 1=TRANSCONV
    output reg  [1:0]  stride,          // Stride value (0=1, 1=1, 2=2, 3=3)
    output reg  [2:0]  padding,         // Padding value (0-7)
    output reg  [4:0]  kernel_size,     // Kernel size (1-16)
    output reg  [9:0]  input_channels,  // Input channel count
    output reg  [9:0]  filter_number,   // Output channel count (filters)
    output reg  [9:0]  temporal_length, // Current temporal length

    // ========================================================================
    // Layer Identification
    // ========================================================================
    output reg  [4:0]  current_layer,   // Current layer index
    output reg  [3:0]  layer_type,      // Layer type encoding
    output reg         is_encoder,      // Currently in encoder phase
    output reg         is_bottleneck,   // Currently in bottleneck phase
    output reg         is_decoder,      // Currently in decoder phase

    // ========================================================================
    // Skip Connection Management
    // ========================================================================
    output reg  [1:0]  skip_write_idx,  // Which skip buffer to write (0-3)
    output reg         skip_write_en,   // Enable skip buffer write
    output reg  [1:0]  skip_read_idx,   // Which skip buffer to read (0-3)
    output reg         skip_read_en     // Enable skip buffer read (for concat)
);

    // ========================================================================
    // Layer Type Encoding
    // ========================================================================
    localparam LTYPE_ENCODER      = 4'd0;
    localparam LTYPE_BOTTLENECK_3 = 4'd1;  // k=3 branch
    localparam LTYPE_BOTTLENECK_5 = 4'd2;  // k=5 branch
    localparam LTYPE_BOTTLENECK_7 = 4'd3;  // k=7 branch
    localparam LTYPE_BOTTLENECK_F = 4'd4;  // k=1 fuse
    localparam LTYPE_DECODER      = 4'd5;
    localparam LTYPE_OUTPUT       = 4'd6;

    // ========================================================================
    // State Encoding
    // ========================================================================
    localparam S_IDLE              = 5'd0;
    localparam S_WAIT_WEIGHTS      = 5'd1;
    localparam S_RUN_LAYER         = 5'd2;
    localparam S_WAIT_DONE         = 5'd3;
    localparam S_NEXT_LAYER        = 5'd4;
    localparam S_DONE              = 5'd5;

    // Encoder layers
    localparam S_E1 = 5'd6;
    localparam S_E2 = 5'd7;
    localparam S_E3 = 5'd8;
    localparam S_E4 = 5'd9;

    // Bottleneck states (for each block: b3, b5, b7, fuse)
    localparam S_BN_B3 = 5'd10;
    localparam S_BN_B5 = 5'd11;
    localparam S_BN_B7 = 5'd12;
    localparam S_BN_FUSE = 5'd13;

    // Decoder layers
    localparam S_D1 = 5'd14;
    localparam S_D2 = 5'd15;
    localparam S_D3 = 5'd16;
    localparam S_D4 = 5'd17;

    // Output head
    localparam S_OUT = 5'd18;

    reg [4:0] state, next_state;
    reg [3:0] bottleneck_count;  // Current bottleneck block (0 to BOTTLENECK_BLOCKS-1)

    // Channel calculations based on BASE_CH
    wire [9:0] ch_1   = 10'd1;
    wire [9:0] ch_b   = BASE_CH;
    wire [9:0] ch_2b  = BASE_CH * 2;
    wire [9:0] ch_4b  = BASE_CH * 4;
    wire [9:0] ch_8b  = BASE_CH * 8;
    wire [9:0] ch_hb  = BASE_CH / 2;

    // ========================================================================
    // State Register
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= S_IDLE;
        else
            state <= next_state;
    end

    // ========================================================================
    // Next State Logic
    // ========================================================================
    always @(*) begin
        next_state = state;

        case (state)
            S_IDLE: begin
                if (start)
                    next_state = S_E1;
            end

            // ============ ENCODER ============
            S_E1: next_state = S_WAIT_WEIGHTS;
            S_E2: next_state = S_WAIT_WEIGHTS;
            S_E3: next_state = S_WAIT_WEIGHTS;
            S_E4: next_state = S_WAIT_WEIGHTS;

            // ============ BOTTLENECK ============
            S_BN_B3: next_state = S_WAIT_WEIGHTS;
            S_BN_B5: next_state = S_WAIT_WEIGHTS;
            S_BN_B7: next_state = S_WAIT_WEIGHTS;
            S_BN_FUSE: next_state = S_WAIT_WEIGHTS;

            // ============ DECODER ============
            S_D1: next_state = S_WAIT_WEIGHTS;
            S_D2: next_state = S_WAIT_WEIGHTS;
            S_D3: next_state = S_WAIT_WEIGHTS;
            S_D4: next_state = S_WAIT_WEIGHTS;

            // ============ OUTPUT ============
            S_OUT: next_state = S_WAIT_WEIGHTS;

            // ============ COMMON FLOW ============
            S_WAIT_WEIGHTS: begin
                if (weight_loaded)
                    next_state = S_RUN_LAYER;
            end

            S_RUN_LAYER: begin
                next_state = S_WAIT_DONE;
            end

            S_WAIT_DONE: begin
                if (layer_done)
                    next_state = S_NEXT_LAYER;
            end

            S_NEXT_LAYER: begin
                case (current_layer)
                    // Encoder transitions
                    5'd0: next_state = S_E2;
                    5'd1: next_state = S_E3;
                    5'd2: next_state = S_E4;
                    5'd3: next_state = S_BN_B3;  // Start bottleneck

                    // Bottleneck transitions (per block: b3→b5→b7→fuse→next_block)
                    5'd4: next_state = S_BN_B5;
                    5'd5: next_state = S_BN_B7;
                    5'd6: next_state = S_BN_FUSE;
                    5'd7: begin
                        if (bottleneck_count < BOTTLENECK_BLOCKS - 1)
                            next_state = S_BN_B3;  // Next block
                        else
                            next_state = S_D1;     // Start decoder
                    end

                    // Decoder transitions
                    5'd8:  next_state = S_D2;
                    5'd9:  next_state = S_D3;
                    5'd10: next_state = S_D4;
                    5'd11: next_state = S_OUT;

                    // Output
                    5'd12: next_state = S_DONE;

                    default: next_state = S_DONE;
                endcase
            end

            S_DONE: begin
                next_state = S_IDLE;
            end

            default: next_state = S_IDLE;
        endcase
    end

    // ========================================================================
    // Output Logic
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            layer_start     <= 1'b0;
            request_weights <= 1'b0;
            inference_done  <= 1'b0;
            conv_mode       <= 1'b0;
            stride          <= 2'd0;
            padding         <= 3'd0;
            kernel_size     <= 5'd1;
            input_channels  <= 10'd1;
            filter_number   <= 10'd1;
            temporal_length <= INITIAL_TEMPORAL;
            current_layer   <= 5'd0;
            layer_type      <= LTYPE_ENCODER;
            is_encoder      <= 1'b0;
            is_bottleneck   <= 1'b0;
            is_decoder      <= 1'b0;
            skip_write_idx  <= 2'd0;
            skip_write_en   <= 1'b0;
            skip_read_idx   <= 2'd0;
            skip_read_en    <= 1'b0;
            bottleneck_count <= 4'd0;
        end
        else begin
            // Default: clear one-shot signals
            layer_start     <= 1'b0;
            request_weights <= 1'b0;
            inference_done  <= 1'b0;
            skip_write_en   <= 1'b0;
            skip_read_en    <= 1'b0;

            case (state)
                S_IDLE: begin
                    current_layer    <= 5'd0;
                    bottleneck_count <= 4'd0;
                    temporal_length  <= INITIAL_TEMPORAL;
                end

                // ==================== ENCODER LAYERS ====================
                S_E1: begin
                    current_layer   <= 5'd0;
                    layer_type      <= LTYPE_ENCODER;
                    is_encoder      <= 1'b1;
                    is_bottleneck   <= 1'b0;
                    is_decoder      <= 1'b0;
                    conv_mode       <= 1'b0;  // 1DCONV

                    // e1: in=1, out=base_ch, k=16, s=2, p=7
                    input_channels  <= ch_1;
                    filter_number   <= ch_b;
                    kernel_size     <= 5'd16;
                    stride          <= 2'd2;
                    padding         <= 3'd7;
                    temporal_length <= INITIAL_TEMPORAL;  // 512

                    skip_write_idx  <= 2'd0;  // Save for d4
                    request_weights <= 1'b1;
                end

                S_E2: begin
                    current_layer   <= 5'd1;
                    layer_type      <= LTYPE_ENCODER;
                    conv_mode       <= 1'b0;

                    // e2: in=base_ch, out=base_ch*2, k=16, s=2, p=7
                    input_channels  <= ch_b;
                    filter_number   <= ch_2b;
                    kernel_size     <= 5'd16;
                    stride          <= 2'd2;
                    padding         <= 3'd7;
                    temporal_length <= INITIAL_TEMPORAL / 2;  // 256

                    skip_write_idx  <= 2'd1;  // Save for d3
                    request_weights <= 1'b1;
                end

                S_E3: begin
                    current_layer   <= 5'd2;
                    layer_type      <= LTYPE_ENCODER;
                    conv_mode       <= 1'b0;

                    // e3: in=base_ch*2, out=base_ch*4, k=16, s=2, p=7
                    input_channels  <= ch_2b;
                    filter_number   <= ch_4b;
                    kernel_size     <= 5'd16;
                    stride          <= 2'd2;
                    padding         <= 3'd7;
                    temporal_length <= INITIAL_TEMPORAL / 4;  // 128

                    skip_write_idx  <= 2'd2;  // Save for d2
                    request_weights <= 1'b1;
                end

                S_E4: begin
                    current_layer   <= 5'd3;
                    layer_type      <= LTYPE_ENCODER;
                    conv_mode       <= 1'b0;

                    // e4: in=base_ch*4, out=base_ch*8, k=16, s=2, p=7
                    input_channels  <= ch_4b;
                    filter_number   <= ch_8b;
                    kernel_size     <= 5'd16;
                    stride          <= 2'd2;
                    padding         <= 3'd7;
                    temporal_length <= INITIAL_TEMPORAL / 8;  // 64

                    skip_write_idx  <= 2'd3;  // Save for d1
                    request_weights <= 1'b1;
                end

                // ==================== BOTTLENECK LAYERS ====================
                S_BN_B3: begin
                    current_layer   <= 5'd4;
                    layer_type      <= LTYPE_BOTTLENECK_3;
                    is_encoder      <= 1'b0;
                    is_bottleneck   <= 1'b1;
                    is_decoder      <= 1'b0;
                    conv_mode       <= 1'b0;

                    // b3: k=3, s=1, p=1, ch=base_ch*8
                    input_channels  <= ch_8b;
                    filter_number   <= ch_8b;
                    kernel_size     <= 5'd3;
                    stride          <= 2'd1;
                    padding         <= 3'd1;
                    temporal_length <= INITIAL_TEMPORAL / 16;  // 32

                    request_weights <= 1'b1;
                end

                S_BN_B5: begin
                    current_layer   <= 5'd5;
                    layer_type      <= LTYPE_BOTTLENECK_5;
                    conv_mode       <= 1'b0;

                    // b5: k=5, s=1, p=2, ch=base_ch*8
                    input_channels  <= ch_8b;
                    filter_number   <= ch_8b;
                    kernel_size     <= 5'd5;
                    stride          <= 2'd1;
                    padding         <= 3'd2;
                    temporal_length <= INITIAL_TEMPORAL / 16;  // 32

                    request_weights <= 1'b1;
                end

                S_BN_B7: begin
                    current_layer   <= 5'd6;
                    layer_type      <= LTYPE_BOTTLENECK_7;
                    conv_mode       <= 1'b0;

                    // b7: k=7, s=1, p=3, ch=base_ch*8
                    input_channels  <= ch_8b;
                    filter_number   <= ch_8b;
                    kernel_size     <= 5'd7;
                    stride          <= 2'd1;
                    padding         <= 3'd3;
                    temporal_length <= INITIAL_TEMPORAL / 16;  // 32

                    request_weights <= 1'b1;
                end

                S_BN_FUSE: begin
                    current_layer   <= 5'd7;
                    layer_type      <= LTYPE_BOTTLENECK_F;
                    conv_mode       <= 1'b0;

                    // fuse: k=1, s=1, p=0, ch=base_ch*8
                    input_channels  <= ch_8b;
                    filter_number   <= ch_8b;
                    kernel_size     <= 5'd1;
                    stride          <= 2'd1;
                    padding         <= 3'd0;
                    temporal_length <= INITIAL_TEMPORAL / 16;  // 32

                    request_weights <= 1'b1;
                end

                // ==================== DECODER LAYERS ====================
                S_D1: begin
                    current_layer   <= 5'd8;
                    layer_type      <= LTYPE_DECODER;
                    is_encoder      <= 1'b0;
                    is_bottleneck   <= 1'b0;
                    is_decoder      <= 1'b1;
                    conv_mode       <= 1'b1;  // TRANSCONV

                    // d1: in=base_ch*8, out=base_ch*4, k=4, s=2, p=1
                    input_channels  <= ch_8b;
                    filter_number   <= ch_4b;
                    kernel_size     <= 5'd4;
                    stride          <= 2'd2;
                    padding         <= 3'd1;
                    temporal_length <= INITIAL_TEMPORAL / 16;  // 32→64

                    skip_read_idx   <= 2'd3;  // Read e4 skip
                    skip_read_en    <= 1'b1;
                    request_weights <= 1'b1;
                end

                S_D2: begin
                    current_layer   <= 5'd9;
                    layer_type      <= LTYPE_DECODER;
                    conv_mode       <= 1'b1;

                    // d2: in=base_ch*8 (concat), out=base_ch*2, k=4, s=2, p=1
                    input_channels  <= ch_8b;  // After concat
                    filter_number   <= ch_2b;
                    kernel_size     <= 5'd4;
                    stride          <= 2'd2;
                    padding         <= 3'd1;
                    temporal_length <= INITIAL_TEMPORAL / 8;  // 64→128

                    skip_read_idx   <= 2'd2;  // Read e3 skip
                    skip_read_en    <= 1'b1;
                    request_weights <= 1'b1;
                end

                S_D3: begin
                    current_layer   <= 5'd10;
                    layer_type      <= LTYPE_DECODER;
                    conv_mode       <= 1'b1;

                    // d3: in=base_ch*4 (concat), out=base_ch, k=4, s=2, p=1
                    input_channels  <= ch_4b;  // After concat
                    filter_number   <= ch_b;
                    kernel_size     <= 5'd4;
                    stride          <= 2'd2;
                    padding         <= 3'd1;
                    temporal_length <= INITIAL_TEMPORAL / 4;  // 128→256

                    skip_read_idx   <= 2'd1;  // Read e2 skip
                    skip_read_en    <= 1'b1;
                    request_weights <= 1'b1;
                end

                S_D4: begin
                    current_layer   <= 5'd11;
                    layer_type      <= LTYPE_DECODER;
                    conv_mode       <= 1'b1;

                    // d4: in=base_ch*2 (concat), out=base_ch/2, k=4, s=2, p=1
                    input_channels  <= ch_2b;  // After concat
                    filter_number   <= ch_hb;
                    kernel_size     <= 5'd4;
                    stride          <= 2'd2;
                    padding         <= 3'd1;
                    temporal_length <= INITIAL_TEMPORAL / 2;  // 256→512

                    skip_read_idx   <= 2'd0;  // Read e1 skip
                    skip_read_en    <= 1'b1;
                    request_weights <= 1'b1;
                end

                // ==================== OUTPUT HEAD ====================
                S_OUT: begin
                    current_layer   <= 5'd12;
                    layer_type      <= LTYPE_OUTPUT;
                    is_encoder      <= 1'b0;
                    is_bottleneck   <= 1'b0;
                    is_decoder      <= 1'b0;
                    conv_mode       <= 1'b0;  // 1DCONV

                    // out: in=base_ch/2, out=1, k=7, s=1, p=3
                    input_channels  <= ch_hb;
                    filter_number   <= ch_1;
                    kernel_size     <= 5'd7;
                    stride          <= 2'd1;
                    padding         <= 3'd3;
                    temporal_length <= INITIAL_TEMPORAL;  // 512

                    request_weights <= 1'b1;
                end

                // ==================== COMMON FLOW ====================
                S_RUN_LAYER: begin
                    layer_start <= 1'b1;
                    // Enable skip write for encoder layers
                    if (is_encoder)
                        skip_write_en <= 1'b1;
                end

                S_WAIT_DONE: begin
                    // Just wait
                end

                S_NEXT_LAYER: begin
                    // Update bottleneck counter if exiting fuse
                    if (layer_type == LTYPE_BOTTLENECK_F) begin
                        bottleneck_count <= bottleneck_count + 1;
                    end
                end

                S_DONE: begin
                    inference_done <= 1'b1;
                end

            endcase
        end
    end

endmodule
