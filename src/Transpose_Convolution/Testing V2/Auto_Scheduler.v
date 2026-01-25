`timescale 1ns / 1ps

/******************************************************************************
 * Module: Auto_Scheduler (MULTI-LAYER VERSION)
 * 
 * Description:
 * Handles automatic start logic for multiple layers with different batch counts.
 * Detects layer changes when BOTH ifmap and weight are reloaded.
 * Generates BRAM output reset signal when switching layers.
 * 
 * Supported Layers:
 * - Layer 0 (D1): 8 batches, 32 tiles
 * - Layer 1 (D2): 4 batches, 16 tiles
 * 
 * Layer Change Detection:
 * When BOTH ifmap_done_posedge AND weight_done_posedge occur:
 *   → New layer started
 *   → Trigger output BRAM reset
 *   → Reset batch counter
 ******************************************************************************/

module Auto_Scheduler (
    input  wire       clk,
    input  wire       rst_n,

    // Inputs from AXI Wrappers
    input  wire       weight_write_done,
    input  wire       ifmap_write_done,

    // Inputs from External / Top Level
    input  wire       ext_scheduler_start,     // Manual start
    input  wire [1:0] external_layer_id,       // Layer ID from PS/external (optional)

    // Inputs from Main Scheduler FSM
    input  wire       batch_complete_signal,   // Signal when one batch finishes

    // Outputs to Main Scheduler & Output Manager
    output wire       final_start_signal,      // To Scheduler_FSM
    output reg  [2:0] current_batch_id,        // 0-7
    output reg  [1:0] current_layer_id,        // 0=D1, 1=D2
    output wire       all_batches_complete,    // To Output Manager
    output wire       layer_transition,        // Pulse when layer changes
    output wire       clear_output_bram,       // Reset output BRAM
    
    // Debug / LED Status
    output wire       auto_start_active,
    output wire       data_load_ready
);

    // ========================================================================
    // Auto-start edge detection logic
    // ========================================================================
    reg weight_write_done_prev, ifmap_write_done_prev;
    wire weight_done_posedge = weight_write_done & ~weight_write_done_prev;
    wire ifmap_done_posedge = ifmap_write_done & ~ifmap_write_done_prev;
    
    reg ifmap_loaded, weight_loaded;
    
    // BOTH loaded simultaneously = NEW LAYER!
    wire both_loaded_together = ifmap_done_posedge & weight_done_posedge;

    // FSM State Definitions
    localparam [2:0]
        BATCH_IDLE         = 3'd0,
        BATCH_WAIT_INITIAL = 3'd1,
        BATCH_RUNNING      = 3'd2,
        BATCH_WAIT_RELOAD  = 3'd3,
        BATCH_ALL_DONE     = 3'd4;
    
    reg [2:0] batch_state, batch_next_state;
    reg batch_auto_start;
    
    // Layer tracking
    reg layer_changed;        // Pulse when layer switches
    reg [2:0] max_batch_for_current_layer;
    
    // Determine max batches based on layer
    always @(*) begin
        case (current_layer_id)
            2'd0:    max_batch_for_current_layer = 3'd7;  // Layer 0: 8 batches (0-7)
            2'd1:    max_batch_for_current_layer = 3'd3;  // Layer 1: 4 batches (0-3)
            default: max_batch_for_current_layer = 3'd7;
        endcase
    end

    // ========================================================================
    // Layer change detection & BRAM reset control
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_layer_id <= 2'd0;
            layer_changed <= 1'b0;
        end else begin
            layer_changed <= 1'b0;  // Default pulse
            
            // Detect layer change: BOTH ifmap and weight loaded together
            if (both_loaded_together && batch_state == BATCH_IDLE) begin
                // Increment layer when starting fresh
                if (current_layer_id < 2'd3)
                    current_layer_id <= current_layer_id + 2'd1;
                else
                    current_layer_id <= 2'd0;  // Wrap around
                
                layer_changed <= 1'b1;  // Pulse
                
                $display("[%0t] AUTO_SCHED: Layer transition detected! New Layer = %0d", 
                         $time, (current_layer_id < 2'd3) ? current_layer_id + 1 : 0);
            end
            
            // Alternative: Use external layer_id if provided
            // Uncomment if PS explicitly sets layer
            // else if (external_layer_id != current_layer_id && batch_state == BATCH_IDLE) begin
            //     current_layer_id <= external_layer_id;
            //     layer_changed <= 1'b1;
            // end
        end
    end
    
    // Output BRAM clear signal (pulse for 2 cycles for safety)
    reg [1:0] clear_bram_counter;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clear_bram_counter <= 2'd0;
        end else begin
            if (layer_changed) begin
                clear_bram_counter <= 2'd2;  // Hold clear for 2 cycles
            end else if (clear_bram_counter > 0) begin
                clear_bram_counter <= clear_bram_counter - 1;
            end
        end
    end
    
    assign clear_output_bram = (clear_bram_counter > 0);
    assign layer_transition = layer_changed;

    // ========================================================================
    // Loading flags logic
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            weight_write_done_prev <= 1'b0;
            ifmap_write_done_prev <= 1'b0;
            ifmap_loaded <= 1'b0;
            weight_loaded <= 1'b0;
        end else begin
            weight_write_done_prev <= weight_write_done;
            ifmap_write_done_prev <= ifmap_write_done;
            
            if (ifmap_done_posedge)
                ifmap_loaded <= 1'b1;
            if (weight_done_posedge)
                weight_loaded <= 1'b1;

            // Clear flags when batch starts running
            if (batch_state == BATCH_IDLE && batch_next_state == BATCH_RUNNING) begin
                ifmap_loaded <= 1'b0;
                weight_loaded <= 1'b0;
            end
        end
    end

    // ========================================================================
    // MULTI-BATCH CONTROL STATE MACHINE
    // ========================================================================
    
    // Batch state transition & Counter
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            batch_state <= BATCH_IDLE;
            current_batch_id <= 3'd0;
            batch_auto_start <= 1'b0;
        end else begin
            batch_state <= batch_next_state;

            // Clear start pulse after 1 cycle
            if (batch_auto_start)
                batch_auto_start <= 1'b0;

            // Increment batch counter when batch completes
            if (batch_complete_signal && batch_state == BATCH_RUNNING) begin
                if (current_batch_id < max_batch_for_current_layer)
                    current_batch_id <= current_batch_id + 3'd1;
                else
                    current_batch_id <= 3'd0; // Reset for next layer
            end
            
            // Reset counter on idle or layer change
            if (batch_state == BATCH_IDLE || layer_changed)
                current_batch_id <= 3'd0;
        end
    end
    
    // Batch Next State Logic
    always @(*) begin
        batch_next_state = batch_state;
        case (batch_state)
            BATCH_IDLE: begin
                // Wait for BOTH ifmap and weight loaded initially
                if (ifmap_loaded && weight_loaded)
                    batch_next_state = BATCH_RUNNING;
            end
            
            BATCH_RUNNING: begin
                // When scheduler signals batch complete
                if (batch_complete_signal) begin
                    if (current_batch_id < max_batch_for_current_layer)
                        batch_next_state = BATCH_WAIT_RELOAD; // Need more weight
                    else
                        batch_next_state = BATCH_ALL_DONE;    // All batches done!
                end
            end
            
            BATCH_WAIT_RELOAD: begin
                // Wait for new weight data (ifmap unchanged)
                if (weight_done_posedge)
                    batch_next_state = BATCH_RUNNING;
            end
            
            BATCH_ALL_DONE: begin
                // Wait for next layer data (both ifmap + weight)
                if (both_loaded_together)
                    batch_next_state = BATCH_RUNNING;  // Start next layer
                else
                    batch_next_state = BATCH_IDLE;     // Or go back to idle
            end
            
            default: batch_next_state = BATCH_IDLE;
        endcase
    end
    
    // Generate start pulse for scheduler
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            batch_auto_start <= 1'b0;
        end else begin
            // Start scheduler when:
            // 1. Initial data loaded (IDLE -> RUNNING)
            // 2. New weight loaded (WAIT_RELOAD -> RUNNING)
            // 3. New layer loaded (ALL_DONE -> RUNNING)
            if ((batch_state == BATCH_IDLE && batch_next_state == BATCH_RUNNING) ||
                (batch_state == BATCH_WAIT_RELOAD && batch_next_state == BATCH_RUNNING) ||
                (batch_state == BATCH_ALL_DONE && batch_next_state == BATCH_RUNNING)) begin
                batch_auto_start <= 1'b1;
            end else begin
                batch_auto_start <= 1'b0;
            end
        end
    end
    
    // ========================================================================
    // OUTPUT ASSIGNMENTS
    // ========================================================================
    // Combined start signal (external manual start OR batch auto-start)
    assign final_start_signal = ext_scheduler_start | batch_auto_start;
    
    // Status outputs
    assign auto_start_active = (batch_state == BATCH_RUNNING);
    assign data_load_ready = (batch_state == BATCH_WAIT_RELOAD) ? 1'b0 : (ifmap_loaded | weight_loaded);
    assign all_batches_complete = (batch_state == BATCH_ALL_DONE);

    // Debug displays
    always @(posedge clk) begin
        if (batch_state == BATCH_RUNNING && batch_next_state == BATCH_WAIT_RELOAD)
            $display("[%0t] AUTO_SCHED: Batch %0d complete, waiting for next weight...", 
                     $time, current_batch_id);
        
        if (batch_state == BATCH_RUNNING && batch_next_state == BATCH_ALL_DONE)
            $display("[%0t] AUTO_SCHED: Layer %0d COMPLETE! All %0d batches done.", 
                     $time, current_layer_id, max_batch_for_current_layer + 1);
    end

endmodule