`timescale 1ns / 1ps

/******************************************************************************
 * Module      : Onedconv_Auto_Scheduler
 * Author      : January 2026
 *
 * Description :
 * Automatic scheduler for 1D Convolution Engine following the Auto_Scheduler
 * architecture pattern from Transpose_Control_Top.
 *
 * Key Features :
 * - Data Reuse Policy
 *   • New Layer: Requires both Ifmap AND Weights loaded
 *   • Same Layer: Reuses Ifmap, waits only for new Weights
 *
 * - Automatic Start Generation
 *   Generates start_whole signal when data dependencies are satisfied
 *
 * - 9-Layer Sequencing
 *   Automatically progresses through WGAN-EEG network layers (0-8)
 *
 * Functionality :
 * - Monitors write_done from AXI to detect data arrival
 * - Tracks ifmap_loaded and weight_loaded flags
 * - Generates final_start_signal when dependencies met
 * - Sequences through 9 hardcoded convolution layers
 *
 ******************************************************************************/

module Onedconv_Auto_Scheduler #(
    parameter DW = 16
)(
    // System Signals
    input  wire       clk,
    input  wire       rst_n,
    
    // Data Load Status (From AXI Write Operations)
    input  wire       weight_write_done,
    input  wire       ifmap_write_done,
    
    // External Controls (Optional Override)
    input  wire       ext_scheduler_start,
    input  wire [3:0] external_layer_id,
    
    // Execution Status (From Main Scheduler)
    input  wire       layer_complete_signal,
    
    // Output Controls
    output wire       final_start_signal,
    output reg  [3:0] current_layer_id,
    output wire       all_layers_complete,
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
    
    // Data Ready Conditions
    wire both_loaded_ready = ifmap_loaded & weight_loaded;
    wire weight_only_ready = weight_loaded & !ifmap_loaded;

    // ========================================================================
    // State Definitions
    // ========================================================================
    localparam [2:0]
        LAYER_IDLE         = 3'd0,
        LAYER_WAIT_INITIAL = 3'd1,
        LAYER_RUNNING      = 3'd2,
        LAYER_NEXT         = 3'd3,
        LAYER_ALL_DONE     = 3'd4;
        
    reg [2:0] layer_state, layer_next_state;
    reg layer_auto_start;
    reg layer_changed;
    reg first_load_done;
    
    // ========================================================================
    // Layer Constants (9 Layers: 0-8)
    // ========================================================================
    localparam NUM_LAYERS = 9;

    // ========================================================================
    // Layer Transition Logic
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_layer_id <= 4'd0;
            layer_changed    <= 1'b0;
            first_load_done  <= 1'b0;
        end else begin
            layer_changed <= 1'b0;
            
            // Trigger Layer Change: When layer complete AND both inputs ready
            if (both_loaded_ready && layer_state == LAYER_ALL_DONE) begin
                if (current_layer_id < NUM_LAYERS - 1) begin
                    current_layer_id <= current_layer_id + 4'd1;
                    layer_changed <= 1'b1;
                    $display("[%0t] [ONEDCONV_AUTO] NEW LAYER: %0d -> %0d", 
                             $time, current_layer_id, current_layer_id + 4'd1);
                end
            end
            
            // First Load Detection (Layer 0 Start)
            if (both_loaded_ready && layer_state == LAYER_IDLE && !first_load_done) begin
                first_load_done <= 1'b1;
                $display("[%0t] [ONEDCONV_AUTO] First load (Layer 0)", $time);
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
                $display("[%0t] [ONEDCONV_AUTO] ifmap_loaded = 1", $time);
            end
            
            if (weight_done_posedge) begin
                weight_loaded <= 1'b1;
                $display("[%0t] [ONEDCONV_AUTO] weight_loaded = 1", $time);
            end
            
            // Clear Flags Logic
            if (layer_state == LAYER_WAIT_INITIAL) begin
                // ALWAYS clear weight flag (reload for every layer start)
                weight_loaded <= 1'b0;
                $display("[%0t] [ONEDCONV_AUTO] weight_loaded cleared", $time);
                
                // Clear ifmap flag when changing layers
                if (layer_changed) begin
                    ifmap_loaded <= 1'b0;
                    $display("[%0t] [ONEDCONV_AUTO] ifmap_loaded cleared (new layer)", $time);
                end
            end
        end
    end
    
    assign data_load_ready = weight_loaded;

    // ========================================================================
    // Layer State Machine
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            layer_state <= LAYER_IDLE;
        else
            layer_state <= layer_next_state;
    end
    
    always @(*) begin
        layer_next_state = layer_state;
        case (layer_state)
            LAYER_IDLE: begin
                // Initial Start: Needs both inputs
                if (both_loaded_ready)
                    layer_next_state = LAYER_WAIT_INITIAL;
            end
            
            LAYER_WAIT_INITIAL: begin
                // Generate start pulse
                layer_next_state = LAYER_RUNNING;
            end
            
            LAYER_RUNNING: begin
                // Wait for layer to complete
                if (layer_complete_signal)
                    layer_next_state = LAYER_NEXT;
            end
            
            LAYER_NEXT: begin
                // Check if more layers remain
                if (current_layer_id >= NUM_LAYERS - 1)
                    layer_next_state = LAYER_ALL_DONE;
                else begin
                    // Next layer: Wait for both inputs (new layer requires new ifmap)
                    if (both_loaded_ready)
                        layer_next_state = LAYER_WAIT_INITIAL;
                end
            end
            
            LAYER_ALL_DONE: begin
                // All 9 layers complete - stay here
                layer_next_state = LAYER_ALL_DONE;
            end
            
            default: layer_next_state = LAYER_IDLE;
        endcase
    end
    
    // ========================================================================
    // Auto Start Pulse Generation
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            layer_auto_start <= 1'b0;
        end else begin
            layer_auto_start <= 1'b0;
            if (layer_state == LAYER_WAIT_INITIAL) begin
                layer_auto_start <= 1'b1;
                $display("[%0t] [ONEDCONV_AUTO] AUTO-START Layer %0d", $time, current_layer_id);
            end
        end
    end
    
    assign final_start_signal   = layer_auto_start | ext_scheduler_start;
    assign auto_start_active    = layer_auto_start;
    assign all_layers_complete  = (layer_state == LAYER_ALL_DONE);

endmodule