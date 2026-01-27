`timescale 1ns / 1ps

/******************************************************************************
 * Module      : Output_Manager_Simple
 * Author      : Dharma Anargya Jowandy
 * Date        : January 2026
 *
 * Description :
 * Finite State Machine (FSM) responsible for orchestrating outbound
 * AXI-Stream communication. This module prioritizes and manages two
 * transmission event types:
 *
 *   1. Batch Notification
 *      Sends a standalone header packet when an individual batch completes.
 *
 *   2. Full Data Dump
 *      Sends a header packet and triggers a BRAM readout sequence when all
 *      processing across batches and layers has completed.
 *
 * Critical Feature :
 * - Safety Interlock / Delay State
 *   Introduces a mandatory idle cycle between consecutive transmission
 *   requests to prevent AXI-Stream collisions when events occur in rapid
 *   succession.
 *
 * Inputs :
 * - clk                 : System clock
 * - rst_n               : Active-low synchronous reset
 * - batch_complete      : Pulse indicating completion of a single batch
 * - current_batch_id    : Identifier of the completed batch
 * - all_batches_done    : Pulse indicating completion of the entire operation
 * - completed_layer_id  : Identifier of the completed processing layer
 * - read_done           : Acknowledge from top-level logic indicating BRAM
 *                         readout completion
 *
 * Outputs :
 * - header_word_[0:5]   : Six-word custom header packet payload
 * - send_header         : Single-cycle trigger to inject header into AXI stream
 * - trigger_read        : Control signal forcing main control FSM into READ mode
 * - rd_bram_start       : Starting BRAM bank index for readout
 * - rd_bram_end         : Ending BRAM bank index for readout
 * - rd_addr_count       : Total number of addresses to be read
 * - notification_mode  : Transmission mode flag
 *                         • 1 = Header-only notification
 *                         • 0 = Header followed by data payload
 * - transmission_active: Status flag indicating an active transmission sequence
 *
 ******************************************************************************/


module Output_Manager_Simple #(
    parameter DW = 16
)(
    input  wire clk,
    input  wire rst_n,
    
    // Status Inputs
    input  wire       batch_complete,
    input  wire [2:0] current_batch_id,
    input  wire       all_batches_done,
    input  wire [1:0] completed_layer_id,
    
    // Header Data Outputs
    output reg [15:0] header_word_0,
    output reg [15:0] header_word_1,
    output reg [15:0] header_word_2,
    output reg [15:0] header_word_3,
    output reg [15:0] header_word_4,
    output reg [15:0] header_word_5,
    
    // Control Outputs
    output reg        send_header,
    output reg        trigger_read,
    output reg [2:0]  rd_bram_start,
    output reg [2:0]  rd_bram_end,
    output reg [15:0] rd_addr_count,
    output reg        notification_mode,
    
    // Handshake
    input  wire       read_done,
    output reg        transmission_active
);

    // State Encoding
    localparam IDLE               = 3'd0;
    localparam SEND_NOTIFICATION  = 3'd1;
    localparam WAIT_NOTIF_DONE    = 3'd2;
    localparam SEND_FULL_DATA     = 3'd3;
    localparam WAIT_DATA_DONE     = 3'd4;
    
    reg [2:0] state, next_state;
    reg [2:0] latched_batch_id;
    reg [1:0] latched_layer_id;
    
    // Safety delay counter to prevent collision in Top Module
    reg [3:0] delay_counter; 
    
    // Edge detection logic
    reg batch_complete_prev;
    reg all_batches_done_prev;
    
    wire batch_complete_edge = batch_complete && !batch_complete_prev;
    wire all_batches_done_edge = all_batches_done && !all_batches_done_prev;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            batch_complete_prev <= 1'b0;
            all_batches_done_prev <= 1'b0;
        end else begin
            batch_complete_prev <= batch_complete;
            all_batches_done_prev <= all_batches_done;
        end
    end
    
    // Request Latching Logic
    // Captures incoming pulses because FSM might be busy
    reg pending_notification;
    reg pending_full_data;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pending_notification <= 1'b0;
            pending_full_data <= 1'b0;
            latched_batch_id <= 3'd0;
            latched_layer_id <= 2'd0;
        end else begin
            // Capture batch completion
            if (batch_complete_edge) begin
                pending_notification <= 1'b1;
                latched_batch_id <= current_batch_id;
            end else if (state == SEND_NOTIFICATION) begin
                pending_notification <= 1'b0; // Clear request when serviced
            end
            
            // Capture all done signal
            if (all_batches_done_edge) begin
                pending_full_data <= 1'b1;
                latched_layer_id <= completed_layer_id;
            end else if (state == SEND_FULL_DATA) begin
                pending_full_data <= 1'b0; // Clear request when serviced
            end
        end
    end
    
    // FSM State Register & Delay Logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            delay_counter <= 4'd0;
        end else begin
            state <= next_state;
            
            // Increment counter only in WAIT_NOTIF_DONE state
            if (state == WAIT_NOTIF_DONE) begin
                delay_counter <= delay_counter + 1;
            end else begin
                delay_counter <= 4'd0; // Reset otherwise
            end
            
            // Debugging display (optional)
            if (state != next_state) begin
                 $display("[%0t] [OUT_MGR] FSM: %0d -> %0d (pending_notif=%b, pending_full=%b)", 
                          $time, state, next_state, pending_notification, pending_full_data);
            end
        end
    end
    
    // FSM Next State Logic
    always @(*) begin
        next_state = state;
        case (state)
            IDLE: begin
                // Priority: Notification > Full Data
                if (pending_notification) begin
                    next_state = SEND_NOTIFICATION;
                end else if (pending_full_data) begin
                    next_state = SEND_FULL_DATA;
                end
            end
            
            SEND_NOTIFICATION: begin
                next_state = WAIT_NOTIF_DONE;
            end
            
            WAIT_NOTIF_DONE: begin
                // SAFETY DELAY: Wait ~15 cycles.
                // Ensures Top Module finishes sending the physical header (6 words)
                // before we potentially trigger the next state.
                if (delay_counter > 4'd14) 
                    next_state = IDLE;
                else 
                    next_state = WAIT_NOTIF_DONE;
            end
            
            SEND_FULL_DATA: begin
                next_state = WAIT_DATA_DONE;
            end
            
            WAIT_DATA_DONE: begin
                // Wait for the main FSM to signal read completion
                if (read_done)
                    next_state = IDLE;
            end
            
            default: next_state = IDLE;
        endcase
    end
    
    // Output Logic Generation
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            header_word_0 <= 16'd0; header_word_1 <= 16'd0;
            header_word_2 <= 16'd0; header_word_3 <= 16'd0;
            header_word_4 <= 16'd0; header_word_5 <= 16'd0;
            send_header <= 1'b0;
            trigger_read <= 1'b0;
            rd_bram_start <= 3'd0; rd_bram_end <= 3'd0;
            rd_addr_count <= 16'd0;
            notification_mode <= 1'b0;
            transmission_active <= 1'b0;
        end else begin
            send_header <= 1'b0;   // Default: Pulse low
            trigger_read <= 1'b0;
            
            case (state)
                IDLE: begin
                    transmission_active <= 1'b0;
                    notification_mode <= 1'b0;
                end
                
                SEND_NOTIFICATION: begin
                    transmission_active <= 1'b1;
                    notification_mode <= 1'b1;
                    
                    // Construct Notification Header (Magic: 0xC0DE)
                    header_word_0 <= 16'hC0DE;
                    header_word_1 <= 16'h0001; // Type: Notification
                    header_word_2 <= {13'd0, latched_batch_id};
                    header_word_3 <= {10'd0, latched_batch_id, 2'd0};
                    header_word_4 <= {10'd0, latched_batch_id, 2'd0} + 16'd3;
                    header_word_5 <= 16'd0;
                    
                    // No BRAM read required for notification
                    rd_bram_start <= 3'd0;
                    rd_bram_end <= 3'd0;
                    rd_addr_count <= 16'd0;
                    
                    send_header <= 1'b1; // Trigger Top Module
                    trigger_read <= 1'b0;
                    
                    $display("[%0t] [OUT_MGR] >>> Sending NOTIFICATION: Batch %0d <<<", 
                             $time, latched_batch_id);
                end
                
                WAIT_NOTIF_DONE: begin
                    transmission_active <= 1'b1;
                    notification_mode <= 1'b1;
                end
                
                SEND_FULL_DATA: begin
                    transmission_active <= 1'b1;
                    notification_mode <= 1'b0;
                    
                    // Construct Full Data Header (Magic: 0xDA7A)
                    header_word_0 <= 16'hDA7A;
                    header_word_1 <= 16'h0002; // Type: Full Data
                    header_word_2 <= {14'd0, latched_layer_id};
                    header_word_3 <= 16'd0;
                    header_word_4 <= 16'd0;
                    header_word_5 <= 16'd4096;
                    
                    // Configure BRAM read parameters
                    rd_bram_start <= 3'd0;
                    rd_bram_end <= 3'd7;
                    rd_addr_count <= 16'd512;
                    
                    send_header <= 1'b1; // Trigger Top Module
                    trigger_read <= 1'b1; // Override FSM to READ mode
                    
                    $display("[%0t] [OUT_MGR] >>> Sending FULL DATA: Layer %0d <<<", 
                             $time, latched_layer_id);
                end
                
                WAIT_DATA_DONE: begin
                    transmission_active <= 1'b1;
                    notification_mode <= 1'b0;
                    if (read_done) begin
                        $display("[%0t] [OUT_MGR] >>> FULL DATA complete <<<", $time);
                    end
                end
            endcase
        end
    end

endmodule