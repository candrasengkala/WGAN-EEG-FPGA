// ============================================================================
// Module: Onedconv_Scheduler_FSM (Complete Multi-Filter & Multi-Channel)
//
// Description:
//   Main scheduler FSM for single layer execution following Scheduler_FSM
//   architecture pattern from Transpose_Control_Top.
//  
//   Orchestrates the execution of a single 1D convolution layer with:
//   - Configuration from ROM based on current_layer_id
//   - Multi-filter support (32, 64, 128, or 256 filters per layer)
//   - Multi-channel batch support (handles >64 input channels)
//   - Weight request/acknowledge handshaking
//   - Output transmission coordination
//
// EXECUTION MODEL:
//   Each layer processes multiple FILTERS, each filter processes multiple 
//   INPUT CHANNEL BATCHES:
//
//   Layer N (e.g., 256 input channels, 256 filters):
//     Filter 0:
//       ├─ Channels 0-63:   weight_req_top → load 4 batches → process
//       ├─ Channels 64-127: weight_req_top → load 4 batches → process
//       ├─ Channels 128-191: weight_req_top → load 4 batches → process
//       └─ Channels 192-255: weight_req_top → load 4 batches → process
//       → done_filter = 1
//     Filter 1:
//       ├─ weight_req_top → load 4 batches for new filter
//       ├─ Process all channel batches...
//       → done_filter = 1
//     ...
//     Filter 255:
//       └─ Last filter completes → done_all = 1
//
// Layer Configuration Summary:
//   Layer 0: 1 ch,   stride 2, 512 temporal, 32 filters,  kernel 16, pad 7
//   Layer 1: 32 ch,  stride 2, 256 temporal, 64 filters,  kernel 16, pad 7
//   Layer 2: 64 ch,  stride 2, 128 temporal, 128 filters, kernel 16, pad 7
//   Layer 3: 128 ch, stride 2, 64 temporal,  256 filters, kernel 16, pad 7
//   Layer 4-8: 256 ch, stride 1, 32 temporal, 256 filters, kernel 7, pad 3
//
// Author: Updated January 2026
// ============================================================================

module Onedconv_Scheduler_FSM #(
    parameter DW = 16,
    parameter CHANNELS_PER_BATCH = 64  // Hardware processes 64 channels per weight batch
)(
    input wire clk,
    input wire rst_n,

    // ========================================================================
    // Trigger (from Auto_Scheduler)
    // ========================================================================
    input wire start,                   // Start from Auto Scheduler

    // ========================================================================
    // Layer Context (from Auto_Scheduler)
    // ========================================================================
    input wire [3:0] current_layer_id,  // Current layer being processed

    // ========================================================================
    // Inputs from AXI
    // ========================================================================
    input wire write_done,              // AXI write complete
    input wire transmission_active,     // Output Manager is sending data
    input wire read_done,               // AXI read complete

    // ========================================================================
    // Inputs from onedconv_ctrl (via Onedconv_Control_Wrapper)
    // ========================================================================
    input wire done_all,                // Entire layer convolution done (all filters)
    input wire done_filter,             // One filter batch done (all channels for 1 filter)
    input wire weight_req_top,          // Request for new weights (new channel batch OR new filter)
    
    // ========================================================================
    // Outputs to onedconv_ctrl (via Onedconv_Control_Wrapper)
    // ========================================================================
    output reg weight_ack_top,          // Weight acknowledge
    output reg start_whole,             // Pulse to start onedconv_ctrl
    
    // ========================================================================
    // Configuration Outputs to onedconv_ctrl
    // ========================================================================
    output reg [1:0]  stride,
    output reg [2:0]  padding,
    output reg [4:0]  kernel_size,
    output reg [9:0]  input_channels,
    output reg [9:0]  filter_number,
    output reg [9:0]  temporal_length
);

    // ========================================================================
    // State Definitions
    // ========================================================================
    localparam [3:0] S_IDLE             = 4'd0;
    localparam [3:0] S_LOAD_CONFIG      = 4'd1;
    localparam [3:0] S_WAIT_DATA_WRITE  = 4'd2;
    localparam [3:0] S_START_CONV       = 4'd3;
    localparam [3:0] S_RUNNING          = 4'd4;
    localparam [3:0] S_WEIGHT_HANDSHAKE = 4'd5;
    localparam [3:0] S_WAIT_WEIGHT_HS   = 4'd6;
    localparam [3:0] S_WAIT_OUTPUT      = 4'd7;
    localparam [3:0] S_DONE             = 4'd8;

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
        // Layer 0
        ROM_INPUT_CHANNELS[0] = 10'd1;    ROM_STRIDE[0] = 2'd2;
        ROM_TEMPORAL[0] = 10'd512;        ROM_FILTERS[0] = 10'd32;
        ROM_KERNEL[0] = 5'd16;            ROM_PADDING[0] = 3'd7;

        // Layer 1
        ROM_INPUT_CHANNELS[1] = 10'd32;   ROM_STRIDE[1] = 2'd2;
        ROM_TEMPORAL[1] = 10'd256;        ROM_FILTERS[1] = 10'd64;
        ROM_KERNEL[1] = 5'd16;            ROM_PADDING[1] = 3'd7;

        // Layer 2
        ROM_INPUT_CHANNELS[2] = 10'd64;   ROM_STRIDE[2] = 2'd2;
        ROM_TEMPORAL[2] = 10'd128;        ROM_FILTERS[2] = 10'd128;
        ROM_KERNEL[2] = 5'd16;            ROM_PADDING[2] = 3'd7;

        // Layer 3
        ROM_INPUT_CHANNELS[3] = 10'd128;  ROM_STRIDE[3] = 2'd2;
        ROM_TEMPORAL[3] = 10'd64;         ROM_FILTERS[3] = 10'd256;
        ROM_KERNEL[3] = 5'd16;            ROM_PADDING[3] = 3'd7;

        // Layers 4-8
        ROM_INPUT_CHANNELS[4] = 10'd256;  ROM_STRIDE[4] = 2'd1;
        ROM_TEMPORAL[4] = 10'd32;         ROM_FILTERS[4] = 10'd256;
        ROM_KERNEL[4] = 5'd7;             ROM_PADDING[4] = 3'd3;

        ROM_INPUT_CHANNELS[5] = 10'd256;  ROM_STRIDE[5] = 2'd1;
        ROM_TEMPORAL[5] = 10'd32;         ROM_FILTERS[5] = 10'd256;
        ROM_KERNEL[5] = 5'd7;             ROM_PADDING[5] = 3'd3;

        ROM_INPUT_CHANNELS[6] = 10'd256;  ROM_STRIDE[6] = 2'd1;
        ROM_TEMPORAL[6] = 10'd32;         ROM_FILTERS[6] = 10'd256;
        ROM_KERNEL[6] = 5'd7;             ROM_PADDING[6] = 3'd3;

        ROM_INPUT_CHANNELS[7] = 10'd256;  ROM_STRIDE[7] = 2'd1;
        ROM_TEMPORAL[7] = 10'd32;         ROM_FILTERS[7] = 10'd256;
        ROM_KERNEL[7] = 5'd7;             ROM_PADDING[7] = 3'd3;

        ROM_INPUT_CHANNELS[8] = 10'd256;  ROM_STRIDE[8] = 2'd1;
        ROM_TEMPORAL[8] = 10'd32;         ROM_FILTERS[8] = 10'd256;
        ROM_KERNEL[8] = 5'd7;             ROM_PADDING[8] = 3'd3;
    end

    // ========================================================================
    // Edge Detection for Control Signals
    // ========================================================================
    reg write_done_prev;
    reg read_done_prev;
    reg done_filter_prev;

    wire write_done_posedge  = write_done & ~write_done_prev;
    wire read_done_posedge   = read_done & ~read_done_prev;
    wire done_filter_posedge = done_filter & ~done_filter_prev;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            write_done_prev  <= 1'b0;
            read_done_prev   <= 1'b0;
            done_filter_prev <= 1'b0;
        end else begin
            write_done_prev  <= write_done;
            read_done_prev   <= read_done;
            done_filter_prev <= done_filter;
        end
    end

    // ========================================================================
    // Multi-Channel & Multi-Filter Tracking
    // ========================================================================
    
    // Channel batch calculation (how many 64-ch batches per filter)
    reg [3:0] required_channel_batches;
    always @(*) begin
        if (input_channels == 0)
            required_channel_batches = 4'd1;
        else if (input_channels <= CHANNELS_PER_BATCH)
            required_channel_batches = 4'd1;  // 1-64 channels = 1 batch
        else
            // Ceiling division: (input_channels + 63) / 64
            required_channel_batches = (input_channels + (CHANNELS_PER_BATCH - 1)) / CHANNELS_PER_BATCH;
    end
    
    // For initial layer start: 1 ifmap + (channel_batches × filter_number)
    // Actually, initial load is: 1 ifmap + weights_for_first_filter
    // Subsequent filters request weights via weight_req_top during execution
    reg [3:0] initial_write_batches;
    always @(*) begin
        // Initial: 1 ifmap + channel batches for first filter only
        initial_write_batches = 4'd1 + required_channel_batches;
    end

    // ========================================================================
    // Write Counter & Expected Writes
    // ========================================================================
    reg [3:0] write_count;
    reg [3:0] expected_writes;
    
    // ========================================================================
    // Filter Tracking
    // ========================================================================
    reg [9:0] current_filter_count;  // Which filter are we on (0 to filter_number-1)
    reg [9:0] total_weight_requests;  // Total weight requests in this layer
    
    // Calculate total weight requests for the layer:
    // = filter_number × (required_channel_batches per filter)
    // BUT the first filter's weights are loaded initially, so:
    // = (filter_number - 1) × required_channel_batches
    // Actually, each filter triggers weight_req_top for each channel batch, so:
    // Total weight requests = filter_number × required_channel_batches
    // BUT first filter's first batch is preloaded, so:
    // = filter_number × required_channel_batches - 1 (if we count the initial load)
    
    // Let me reconsider: Based on conversation history, weight_req_top triggers:
    // 1. Every 64 channels within a filter
    // 2. At the start of each new filter
    
    // For Layer 4 (256 ch, 256 filters):
    // Filter 0: weight_req at ch64, ch128, ch192 = 3 requests (initial ch0-63 preloaded)
    // Filter 1: weight_req at filter_start, ch64, ch128, ch192 = 4 requests
    // ...
    // Total = 3 + (255 × 4) = 3 + 1020 = 1023 weight requests
    
    // Generalized:
    // First filter: (required_channel_batches - 1) requests (skip first batch, it's preloaded)
    // Remaining filters: required_channel_batches requests each
    // Total = (required_channel_batches - 1) + (filter_number - 1) × required_channel_batches
    //       = filter_number × required_channel_batches - 1

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
                next_state = S_WAIT_DATA_WRITE;
            end

            S_WAIT_DATA_WRITE: begin
                // Wait for ifmap + first filter's weights
                if (write_count >= expected_writes)
                    next_state = S_START_CONV;
            end

            S_START_CONV: begin
                next_state = S_RUNNING;
            end

            S_RUNNING: begin
                if (done_all)
                    // All filters complete
                    next_state = S_WAIT_OUTPUT;
                else if (weight_req_top)
                    // Need weights for next channel batch OR next filter
                    next_state = S_WEIGHT_HANDSHAKE;
            end

            S_WEIGHT_HANDSHAKE: begin
                next_state = S_WAIT_WEIGHT_HS;
            end

            S_WAIT_WEIGHT_HS: begin
                // Wait for all required weight batches
                if (write_count >= expected_writes)
                    next_state = S_RUNNING;
            end
            
            S_WAIT_OUTPUT: begin
                // Wait for Output Manager to finish transmission
                if (!transmission_active && read_done_posedge)
                    next_state = S_DONE;
            end

            S_DONE: begin
                // Hold done state until Auto Scheduler triggers next layer
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
            start_whole           <= 1'b0;
            weight_ack_top        <= 1'b0;
            write_count           <= 4'd0;
            expected_writes       <= 4'd0;
            current_filter_count  <= 10'd0;
            total_weight_requests <= 10'd0;

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
                    write_count          <= 4'd0;
                    expected_writes      <= 4'd0;
                    current_filter_count <= 10'd0;
                    total_weight_requests <= 10'd0;
                end

                S_LOAD_CONFIG: begin
                    // Load configuration from ROM
                    stride          <= ROM_STRIDE[current_layer_id];
                    padding         <= ROM_PADDING[current_layer_id];
                    kernel_size     <= ROM_KERNEL[current_layer_id];
                    input_channels  <= ROM_INPUT_CHANNELS[current_layer_id];
                    filter_number   <= ROM_FILTERS[current_layer_id];
                    temporal_length <= ROM_TEMPORAL[current_layer_id];
                    write_count     <= 4'd0;
                    
                    // Set expected writes for initial load (1 ifmap + first filter weights)
                    expected_writes <= initial_write_batches;
                    
                    // Calculate total expected weight requests for this layer
                    // = filter_number × required_channel_batches - 1 (first batch preloaded)
                    total_weight_requests <= ROM_FILTERS[current_layer_id] * required_channel_batches - 10'd1;
                    
                    current_filter_count <= 10'd0;

                    $display("[%0t] [SCHED_FSM] ========================================", $time);
                    $display("[%0t] [SCHED_FSM] Loading Layer %0d Configuration:", $time, current_layer_id);
                    $display("[%0t] [SCHED_FSM]   Input Channels:  %0d", $time, ROM_INPUT_CHANNELS[current_layer_id]);
                    $display("[%0t] [SCHED_FSM]   Filters:         %0d", $time, ROM_FILTERS[current_layer_id]);
                    $display("[%0t] [SCHED_FSM]   Stride:          %0d", $time, ROM_STRIDE[current_layer_id]);
                    $display("[%0t] [SCHED_FSM]   Temporal Length: %0d", $time, ROM_TEMPORAL[current_layer_id]);
                    $display("[%0t] [SCHED_FSM]   Kernel Size:     %0d", $time, ROM_KERNEL[current_layer_id]);
                    $display("[%0t] [SCHED_FSM]   Padding:         %0d", $time, ROM_PADDING[current_layer_id]);
                    $display("[%0t] [SCHED_FSM] ----------------------------------------", $time);
                    $display("[%0t] [SCHED_FSM]   Channel batches per filter: %0d (each %0d channels)", 
                             $time, required_channel_batches, CHANNELS_PER_BATCH);
                    $display("[%0t] [SCHED_FSM]   Total weight requests expected: %0d", 
                             $time, ROM_FILTERS[current_layer_id] * required_channel_batches - 10'd1);
                    $display("[%0t] [SCHED_FSM]   Initial writes: %0d (1 ifmap + %0d weight batches)", 
                             $time, initial_write_batches, required_channel_batches);
                    $display("[%0t] [SCHED_FSM] ========================================", $time);
                end

                S_WAIT_DATA_WRITE: begin
                    if (write_done_posedge) begin
                        write_count <= write_count + 1;
                        
                        if (write_count == 0)
                            $display("[%0t] [SCHED_FSM] Layer %0d - Ifmap write complete (1/%0d)", 
                                     $time, current_layer_id, expected_writes);
                        else
                            $display("[%0t] [SCHED_FSM] Layer %0d - Weight batch %0d/%0d complete", 
                                     $time, current_layer_id, write_count, expected_writes - 1);
                        
                        if (write_count + 1 >= expected_writes)
                            $display("[%0t] [SCHED_FSM] Layer %0d - All initial data received (Filter 0, Channels 0-%0d ready)", 
                                     $time, current_layer_id, required_channel_batches * CHANNELS_PER_BATCH - 1);
                    end
                end

                S_START_CONV: begin
                    start_whole <= 1'b1;
                    $display("[%0t] [SCHED_FSM] Layer %0d - Starting convolution (Filter 0)", 
                             $time, current_layer_id);
                end

                S_RUNNING: begin
                    // Track filter completion
                    if (done_filter_posedge) begin
                        current_filter_count <= current_filter_count + 1;
                        $display("[%0t] [SCHED_FSM] Layer %0d - Filter %0d COMPLETE (%0d/%0d filters done)", 
                                 $time, current_layer_id, current_filter_count, 
                                 current_filter_count + 1, filter_number);
                    end
                    
                    if (done_all) begin
                        $display("[%0t] [SCHED_FSM] Layer %0d - ALL FILTERS COMPLETE (Total: %0d filters)", 
                                 $time, current_layer_id, filter_number);
                        $display("[%0t] [SCHED_FSM] Layer %0d - Convolution complete, waiting for output transmission", 
                                 $time, current_layer_id);
                    end else if (weight_req_top) begin
                        $display("[%0t] [SCHED_FSM] Layer %0d - Weight request (Filter %0d)", 
                                 $time, current_layer_id, current_filter_count);
                    end
                end

                S_WEIGHT_HANDSHAKE: begin
                    // Reset write counter and set expected writes
                    write_count     <= 4'd0;
                    expected_writes <= required_channel_batches;
                    
                    $display("[%0t] [SCHED_FSM] Layer %0d - Weight handshake: expecting %0d batches", 
                             $time, current_layer_id, required_channel_batches);
                end

                S_WAIT_WEIGHT_HS: begin
                    if (write_done_posedge) begin
                        write_count <= write_count + 1;
                        $display("[%0t] [SCHED_FSM] Layer %0d - Weight batch %0d/%0d received (Filter %0d)", 
                                 $time, current_layer_id, write_count + 1, expected_writes, current_filter_count);
                        
                        if (write_count + 1 >= expected_writes) begin
                            weight_ack_top <= 1'b1;
                            $display("[%0t] [SCHED_FSM] Layer %0d - All %0d weight batches loaded, ACK sent (Filter %0d)", 
                                     $time, current_layer_id, expected_writes, current_filter_count);
                        end
                    end
                end
                
                S_WAIT_OUTPUT: begin
                    if (read_done_posedge)
                        $display("[%0t] [SCHED_FSM] Layer %0d - Output transmission complete", 
                                 $time, current_layer_id);
                end

                S_DONE: begin
                    $display("[%0t] [SCHED_FSM] ======== Layer %0d COMPLETE ========", $time, current_layer_id);
                end
            endcase
        end
    end

endmodule