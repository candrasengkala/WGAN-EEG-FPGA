`timescale 1ns / 1ps

/******************************************************************************
 * Module      : Auto_Scheduler
 * Author      : Dharma Anargya Jowandy
 * Date        : January 2026
 *
 * Description :
 * Central scheduling unit for a multi-batch accelerator.
 * This module automatically sequences batch execution and layer transitions
 * based on data availability and compute completion status.
 *
 * Key Feature — Data Reuse Policy :
 * - New Layer
 *   Requires both Input Feature Maps (Ifmap) and Weights to be fully loaded
 *   before issuing a start command.
 *
 * - Next Batch (Same Layer)
 *   Reuses existing Ifmap data and waits only for new Weights to be loaded
 *   before issuing a start command.
 *
 * Functionality :
 * - Generates automatic start signals when all required data dependencies
 *   are satisfied.
 * - Tracks and updates the current Batch ID and Layer ID.
 * - Issues BRAM clear / reset signals upon layer transitions to maintain
 *   memory consistency.
 *
 * Inputs :
 * - ifmap_write_done     : Handshake indicating Ifmap load completion
 * - weight_write_done    : Handshake indicating Weight load completion
 * - batch_complete_signal: Pulse from compute core indicating batch completion
 *
 * Outputs :
 * - final_start_signal   : Start trigger to the compute core
 * - current_batch_id    : Current batch identifier (status output)
 * - current_layer_id    : Current layer identifier (status output)
 * - layer_transition    : Single-cycle pulse indicating a layer switch event
 *
 ******************************************************************************/


module Auto_Scheduler (
    // System Signals
    input  wire       clk,
    input  wire       rst_n,
    
    // Data Load Status Handshake
    input  wire       weight_write_done,
    input  wire       ifmap_write_done,
    
    // External Controls
    input  wire       ext_scheduler_start,
    input  wire [1:0] external_layer_id,
    
    // Execution Status
    input  wire       batch_complete_signal,
    
    // Output Controls
    output wire       final_start_signal,
    output reg  [2:0] current_batch_id,
    output reg  [1:0] current_layer_id,
    output wire       all_batches_complete,
    output wire       layer_transition,
    output wire       clear_output_bram,
    output wire       auto_start_active,
    output wire       data_load_ready
);

    // ========================================================================
    // Load Detection Logic
    // ========================================================================
    reg weight_write_done_prev, ifmap_write_done_prev;
    wire weight_done_posedge = weight_write_done & ~weight_write_done_prev;
    wire ifmap_done_posedge = ifmap_write_done & ~ifmap_write_done_prev;
    
    reg ifmap_loaded, weight_loaded;
    
    // Logic: New layer needs both; Subsequent batches reuse Ifmap (need weight only)
    wire both_loaded_ready = ifmap_loaded & weight_loaded;
    wire weight_only_ready = weight_loaded & !ifmap_loaded;

    // ========================================================================
    // State Definitions
    // ========================================================================
    localparam [2:0]
        BATCH_IDLE         = 3'd0,
        BATCH_WAIT_INITIAL = 3'd1,
        BATCH_RUNNING      = 3'd2,
        BATCH_NEXT         = 3'd3,
        BATCH_ALL_DONE     = 3'd4;
        
    reg [2:0] batch_state, batch_next_state;
    reg batch_auto_start;
    reg layer_changed;
    reg first_load_done;
    
    // ========================================================================
    // Batch Configuration (Per Layer)
    // ========================================================================
    reg [2:0] max_batch_for_current_layer;
    
    always @(*) begin
        case (current_layer_id)
            2'd0:    max_batch_for_current_layer = 3'd7; // Layer 0: 8 Batches (0-7)
            2'd1:    max_batch_for_current_layer = 3'd3; // Layer 1: 4 Batches (0-3)
            2'd2:    max_batch_for_current_layer = 3'd0; // Layer 2: 1 Batch
            2'd3:    max_batch_for_current_layer = 3'd0; // Layer 3: 1 Batch
            default: max_batch_for_current_layer = 3'd7;
        endcase
    end

    // ========================================================================
    // Layer Transition Logic
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_layer_id <= 2'd0;
            layer_changed    <= 1'b0;
            first_load_done  <= 1'b0;
        end else begin
            layer_changed <= 1'b0;
            
            // Trigger Layer Change: Only when ALL DONE and BOTH Ifmap+Weight are ready
            if (both_loaded_ready && batch_state == BATCH_ALL_DONE) begin
                if (current_layer_id < 2'd3)
                    current_layer_id <= current_layer_id + 2'd1;
                else
                    current_layer_id <= 2'd0;
                
                layer_changed <= 1'b1;
                $display("[%0t] [AUTO_SCHED] NEW LAYER: %0d -> %0d", 
                         $time, current_layer_id, current_layer_id + 2'd1);
            end
            
            // First Load Detection (Layer 0 Start)
            if (both_loaded_ready && batch_state == BATCH_IDLE && !first_load_done) begin
                first_load_done <= 1'b1;
                $display("[%0t] [AUTO_SCHED] First load (Layer 0)", $time);
            end
        end
    end
    
    assign layer_transition = layer_changed;

    // ========================================================================
    // Output BRAM Clearing Logic
    // ========================================================================
    reg [1:0] clear_bram_counter;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            clear_bram_counter <= 2'd0;
        else if (layer_changed)
            clear_bram_counter <= 2'd2; // Pulse width for clear
        else if (clear_bram_counter > 0)
            clear_bram_counter <= clear_bram_counter - 2'd1;
    end
    
    assign clear_output_bram = (clear_bram_counter > 0);

    // ========================================================================
    // Load Flag Management
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            weight_write_done_prev <= 1'b0;
            ifmap_write_done_prev  <= 1'b0;
            ifmap_loaded           <= 1'b0;
            weight_loaded          <= 1'b0;
        end else begin
            weight_write_done_prev <= weight_write_done;
            ifmap_write_done_prev  <= ifmap_write_done;
            
            // Set Flags on rising edge
            if (ifmap_done_posedge) begin
                ifmap_loaded <= 1'b1;
                $display("[%0t] [AUTO_SCHED] ifmap_loaded = 1", $time);
            end
            
            if (weight_done_posedge) begin
                weight_loaded <= 1'b1;
                $display("[%0t] [AUTO_SCHED] weight_loaded = 1", $time);
            end
            
            // Clear Flags Logic
            if (batch_state == BATCH_WAIT_INITIAL) begin
                // ALWAYS clear weight flag (must reload for every batch)
                weight_loaded <= 1'b0;
                $display("[%0t] [AUTO_SCHED] weight_loaded cleared (ifmap reused)", $time);
                
                // ONLY clear ifmap flag if changing layers
                if (layer_changed) begin
                    ifmap_loaded <= 1'b0;
                    $display("[%0t] [AUTO_SCHED] ifmap_loaded cleared (new layer)", $time);
                end
            end
        end
    end
    
    assign data_load_ready = weight_loaded;

    // ========================================================================
    // Batch State Machine
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            batch_state <= BATCH_IDLE;
        else
            batch_state <= batch_next_state;
    end
    
    always @(*) begin
        batch_next_state = batch_state;
        case (batch_state)
            BATCH_IDLE: begin
                // Initial Start: Needs both inputs
                if (both_loaded_ready)
                    batch_next_state = BATCH_WAIT_INITIAL;
            end
            
            BATCH_WAIT_INITIAL: begin
                // Generate Pulse
                batch_next_state = BATCH_RUNNING;
            end
            
            BATCH_RUNNING: begin
                // Wait for compute core to finish
                if (batch_complete_signal) begin
                    if (current_batch_id >= max_batch_for_current_layer)
                        batch_next_state = BATCH_ALL_DONE;
                    else
                        batch_next_state = BATCH_NEXT;
                end
            end
            
            BATCH_NEXT: begin
                // Subsequent Batches: Wait for Weight ONLY (Reuse Ifmap)
                if (weight_loaded)
                    batch_next_state = BATCH_WAIT_INITIAL;
            end
            
            BATCH_ALL_DONE: begin
                // Layer Complete: Wait for Both (New Layer)
                if (both_loaded_ready)
                    batch_next_state = BATCH_WAIT_INITIAL;
            end
            
            default: batch_next_state = BATCH_IDLE;
        endcase
    end
    
    // ========================================================================
    // Batch Counter & Auto Start
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_batch_id <= 3'd0;
        end else begin
            case (batch_state)
                BATCH_IDLE: begin
                    if (both_loaded_ready)
                        current_batch_id <= 3'd0;
                end
                
                BATCH_NEXT: begin
                    if (weight_loaded) begin
                        current_batch_id <= current_batch_id + 3'd1;
                        $display("[%0t] [AUTO_SCHED] Batch %0d -> %0d", 
                                 $time, current_batch_id, current_batch_id + 3'd1);
                    end
                end
                
                BATCH_ALL_DONE: begin
                    if (both_loaded_ready)
                        current_batch_id <= 3'd0;
                end
            endcase
        end
    end
    
    // Auto-Start Pulse Generation
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            batch_auto_start <= 1'b0;
        end else begin
            batch_auto_start <= 1'b0;
            if (batch_state == BATCH_WAIT_INITIAL) begin
                batch_auto_start <= 1'b1;
                $display("[%0t] [AUTO_SCHED] AUTO-START Batch %0d", $time, current_batch_id);
            end
        end
    end
    
    assign final_start_signal   = batch_auto_start | ext_scheduler_start;
    assign auto_start_active    = batch_auto_start;
    assign all_batches_complete = (batch_state == BATCH_ALL_DONE);

endmodule