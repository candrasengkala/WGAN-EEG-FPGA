// ============================================================================
// Module: Onedconv_Auto_Scheduler
//
// Description:
//   Auto-scheduler FSM that sequences through 9 layers (0-8) of 1D convolution.
//   Hardcoded layer configurations for WGAN-EEG network.
//   Uses passive wait for AXI done signals (weight_write_done, ifmap_write_done).
//   Interfaces with onedconv_ctrl via weight_req_top/weight_ack_top handshake.
//
// Layer Configuration Summary:
//   Layer 0: 1 ch,   stride 2, 512 temporal, 32 filters,  kernel 16, pad 7
//   Layer 1: 32 ch,  stride 2, 256 temporal, 64 filters,  kernel 16, pad 7
//   Layer 2: 64 ch,  stride 2, 128 temporal, 128 filters, kernel 16, pad 7
//   Layer 3: 128 ch, stride 2, 64 temporal,  256 filters, kernel 16, pad 7
//   Layer 4-8: 256 ch, stride 1, 32 temporal, 256 filters, kernel 7, pad 3
//
// Author: Auto-generated
// Date: January 2026
// ============================================================================

module Onedconv_Auto_Scheduler #(
    parameter DW = 16
)(
    input wire clk,
    input wire rst_n,

    // ========================================================================
    // Trigger
    // ========================================================================
    input wire start,                   // Start from System Top

    // ========================================================================
    // Inputs from AXI Wrappers
    // ========================================================================
    input wire weight_write_done,       // AXI weight write complete
    input wire ifmap_write_done,        // AXI ifmap write complete

    // ========================================================================
    // Inputs from onedconv_ctrl
    // ========================================================================
    input wire done_all,                // Entire layer convolution done
    input wire done_filter,             // One filter batch done (unused for now)
    input wire weight_req_top,          // Request for new weights (every 64 ch or new filter)
    // ========================================================================
    // Outputs to onedconv_ctrl
    // ========================================================================
    output reg weight_ack_top,          // Weight acknowledge (new weights ready)
    output reg start_whole,             // Pulse to start onedconv_ctrl
    // ========================================================================
    // Configuration Outputs to onedconv_ctrl
    // ========================================================================
    output reg [1:0]  stride,
    output reg [2:0]  padding,
    output reg [4:0]  kernel_size,
    output reg [9:0]  input_channels,
    output reg [9:0]  filter_number,
    output reg [9:0]  temporal_length,
    // ========================================================================
    // Status Outputs
    // ========================================================================
    output reg [3:0]  current_layer_id, // Current layer being processed (0-8)
    output reg        all_layers_done   // All 9 layers complete
);

    // ========================================================================
    // Parameters
    // ========================================================================
    localparam NUM_LAYERS = 9;

    // ========================================================================
    // State Definitions
    // ========================================================================
    localparam [3:0] S_IDLE             = 4'd0;
    localparam [3:0] S_LOAD_CONFIG      = 4'd1;
    localparam [3:0] S_WAIT_IFMAP       = 4'd2;
    localparam [3:0] S_WAIT_WEIGHT      = 4'd3;
    localparam [3:0] S_START_CONV       = 4'd4;
    localparam [3:0] S_RUNNING          = 4'd5;
    localparam [3:0] S_WEIGHT_HANDSHAKE = 4'd6;
    localparam [3:0] S_WAIT_WEIGHT_HS   = 4'd7;  // Wait for weight during handshake
    localparam [3:0] S_LAYER_DONE       = 4'd8;
    localparam [3:0] S_ALL_DONE         = 4'd9;

    reg [3:0] state, next_state;

    // ========================================================================
    // Layer Configuration ROM (9 layers: 0-8)
    // ========================================================================
    reg [9:0] ROM_INPUT_CHANNELS [0:8];
    reg [1:0] ROM_STRIDE [0:8];
    reg [9:0] ROM_TEMPORAL [0:8];
    reg [9:0] ROM_FILTERS [0:8];
    reg [4:0] ROM_KERNEL [0:8];
    reg [2:0] ROM_PADDING [0:8];

    initial begin
        // Layer 0: 1 ch, stride 2, 512 temporal, 32 filters, kernel 16, pad 7
        ROM_INPUT_CHANNELS[0] = 10'd1;
        ROM_STRIDE[0]         = 2'd2;
        ROM_TEMPORAL[0]       = 10'd512;
        ROM_FILTERS[0]        = 10'd32;
        ROM_KERNEL[0]         = 5'd16;
        ROM_PADDING[0]        = 3'd7;

        // Layer 1: 32 ch, stride 2, 256 temporal, 64 filters, kernel 16, pad 7
        ROM_INPUT_CHANNELS[1] = 10'd32;
        ROM_STRIDE[1]         = 2'd2;
        ROM_TEMPORAL[1]       = 10'd256;
        ROM_FILTERS[1]        = 10'd64;
        ROM_KERNEL[1]         = 5'd16;
        ROM_PADDING[1]        = 3'd7;

        // Layer 2: 64 ch, stride 2, 128 temporal, 128 filters, kernel 16, pad 7
        ROM_INPUT_CHANNELS[2] = 10'd64;
        ROM_STRIDE[2]         = 2'd2;
        ROM_TEMPORAL[2]       = 10'd128;
        ROM_FILTERS[2]        = 10'd128;
        ROM_KERNEL[2]         = 5'd16;
        ROM_PADDING[2]        = 3'd7;

        // Layer 3: 128 ch, stride 2, 64 temporal, 256 filters, kernel 16, pad 7
        ROM_INPUT_CHANNELS[3] = 10'd128;
        ROM_STRIDE[3]         = 2'd2;
        ROM_TEMPORAL[3]       = 10'd64;
        ROM_FILTERS[3]        = 10'd256;
        ROM_KERNEL[3]         = 5'd16;
        ROM_PADDING[3]        = 3'd7;

        // Layers 4-8: 256 ch, stride 1, 32 temporal, 256 filters, kernel 7, pad 3
        ROM_INPUT_CHANNELS[4] = 10'd256;
        ROM_STRIDE[4]         = 2'd1;
        ROM_TEMPORAL[4]       = 10'd32;
        ROM_FILTERS[4]        = 10'd256;
        ROM_KERNEL[4]         = 5'd7;
        ROM_PADDING[4]        = 3'd3;

        ROM_INPUT_CHANNELS[5] = 10'd256;
        ROM_STRIDE[5]         = 2'd1;
        ROM_TEMPORAL[5]       = 10'd32;
        ROM_FILTERS[5]        = 10'd256;
        ROM_KERNEL[5]         = 5'd7;
        ROM_PADDING[5]        = 3'd3;

        ROM_INPUT_CHANNELS[6] = 10'd256;
        ROM_STRIDE[6]         = 2'd1;
        ROM_TEMPORAL[6]       = 10'd32;
        ROM_FILTERS[6]        = 10'd256;
        ROM_KERNEL[6]         = 5'd7;
        ROM_PADDING[6]        = 3'd3;

        ROM_INPUT_CHANNELS[7] = 10'd256;
        ROM_STRIDE[7]         = 2'd1;
        ROM_TEMPORAL[7]       = 10'd32;
        ROM_FILTERS[7]        = 10'd256;
        ROM_KERNEL[7]         = 5'd7;
        ROM_PADDING[7]        = 3'd3;

        ROM_INPUT_CHANNELS[8] = 10'd256;
        ROM_STRIDE[8]         = 2'd1;
        ROM_TEMPORAL[8]       = 10'd32;
        ROM_FILTERS[8]        = 10'd256;
        ROM_KERNEL[8]         = 5'd7;
        ROM_PADDING[8]        = 3'd3;
    end

    // ========================================================================
    // Edge Detection for AXI Done Signals
    // ========================================================================
    reg weight_write_done_prev;
    reg ifmap_write_done_prev;

    wire weight_done_posedge = weight_write_done & ~weight_write_done_prev;
    wire ifmap_done_posedge  = ifmap_write_done & ~ifmap_write_done_prev;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            weight_write_done_prev <= 1'b0;
            ifmap_write_done_prev  <= 1'b0;
        end else begin
            weight_write_done_prev <= weight_write_done;
            ifmap_write_done_prev  <= ifmap_write_done;
        end
    end

    // ========================================================================
    // Layer Counter
    // ========================================================================
    reg [3:0] layer_counter;

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
                    next_state = S_LOAD_CONFIG;
            end

            S_LOAD_CONFIG: begin
                // Config loaded in one cycle, move to wait for ifmap
                next_state = S_WAIT_IFMAP;
            end

            S_WAIT_IFMAP: begin
                // Wait for ifmap data from AXI
                if (ifmap_done_posedge)
                    next_state = S_WAIT_WEIGHT;
            end

            S_WAIT_WEIGHT: begin
                // Wait for weight data from AXI
                if (weight_done_posedge)
                    next_state = S_START_CONV;
            end

            S_START_CONV: begin
                // Pulse start_whole for one cycle
                next_state = S_RUNNING;
            end

            S_RUNNING: begin
                if (done_all)
                    // Layer complete
                    next_state = S_LAYER_DONE;
                else if (weight_req_top)
                    // onedconv_ctrl needs new weights
                    next_state = S_WEIGHT_HANDSHAKE;
            end

            S_WEIGHT_HANDSHAKE: begin
                // Wait for new weight data from AXI
                next_state = S_WAIT_WEIGHT_HS;
            end

            S_WAIT_WEIGHT_HS: begin
                // Wait for weight_write_done, then ack
                if (weight_done_posedge)
                    next_state = S_RUNNING;
            end

            S_LAYER_DONE: begin
                // Check if more layers remain
                if (layer_counter >= NUM_LAYERS - 1)
                    next_state = S_ALL_DONE;
                else
                    next_state = S_LOAD_CONFIG;  // Next layer
            end

            S_ALL_DONE: begin
                // Stay here until start deasserts, then return to idle
                if (!start)
                    next_state = S_IDLE;
            end

            default: next_state = S_IDLE;
        endcase
    end

    // ========================================================================
    // Output Logic & Layer Counter
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset outputs
            start_whole      <= 1'b0;
            weight_ack_top   <= 1'b0;
            all_layers_done  <= 1'b0;
            current_layer_id <= 4'd0;
            layer_counter    <= 4'd0;

            // Default configuration (Layer 0)
            stride           <= 2'd0;
            padding          <= 3'd0;
            kernel_size      <= 5'd0;
            input_channels   <= 10'd0;
            filter_number    <= 10'd0;
            temporal_length  <= 10'd0;
        end else begin
            // Default: clear pulses
            start_whole    <= 1'b0;
            weight_ack_top <= 1'b0;

            case (state)
                S_IDLE: begin
                    all_layers_done  <= 1'b0;
                    layer_counter    <= 4'd0;
                    current_layer_id <= 4'd0;
                end

                S_LOAD_CONFIG: begin
                    // Load configuration from ROM
                    stride          <= ROM_STRIDE[layer_counter];
                    padding         <= ROM_PADDING[layer_counter];
                    kernel_size     <= ROM_KERNEL[layer_counter];
                    input_channels  <= ROM_INPUT_CHANNELS[layer_counter];
                    filter_number   <= ROM_FILTERS[layer_counter];
                    temporal_length <= ROM_TEMPORAL[layer_counter];
                    current_layer_id <= layer_counter;

                    $display("[%0t] SCHEDULER: Loading Layer %0d config - Ch=%0d, Stride=%0d, Temporal=%0d, Filters=%0d, Kernel=%0d, Pad=%0d",
                             $time, layer_counter,
                             ROM_INPUT_CHANNELS[layer_counter],
                             ROM_STRIDE[layer_counter],
                             ROM_TEMPORAL[layer_counter],
                             ROM_FILTERS[layer_counter],
                             ROM_KERNEL[layer_counter],
                             ROM_PADDING[layer_counter]);
                end

                S_WAIT_IFMAP: begin
                    // Waiting for ifmap data
                    if (ifmap_done_posedge)
                        $display("[%0t] SCHEDULER: Layer %0d - Ifmap loaded", $time, layer_counter);
                end

                S_WAIT_WEIGHT: begin
                    // Waiting for weight data
                    if (weight_done_posedge)
                        $display("[%0t] SCHEDULER: Layer %0d - Initial weights loaded", $time, layer_counter);
                end

                S_START_CONV: begin
                    // Pulse start_whole
                    start_whole <= 1'b1;
                    $display("[%0t] SCHEDULER: Layer %0d - Starting convolution", $time, layer_counter);
                end

                S_RUNNING: begin
                    // Monitor onedconv_ctrl
                end

                S_WEIGHT_HANDSHAKE: begin
                    // Waiting for new weights - PS should be sending them
                    $display("[%0t] SCHEDULER: Layer %0d - Weight request, waiting for new weights", $time, layer_counter);
                end

                S_WAIT_WEIGHT_HS: begin
                    // Wait for weight_done, then assert ack
                    if (weight_done_posedge) begin
                        weight_ack_top <= 1'b1;
                        $display("[%0t] SCHEDULER: Layer %0d - New weights loaded, sending ACK", $time, layer_counter);
                    end
                end

                S_LAYER_DONE: begin
                    // Increment layer counter
                    layer_counter <= layer_counter + 1;
                    $display("[%0t] SCHEDULER: Layer %0d COMPLETE", $time, layer_counter);
                end

                S_ALL_DONE: begin
                    all_layers_done <= 1'b1;
                    $display("[%0t] SCHEDULER: ALL %0d LAYERS COMPLETE!", $time, NUM_LAYERS);
                end
            endcase
        end
    end

endmodule
