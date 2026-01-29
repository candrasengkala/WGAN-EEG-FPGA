`timescale 1ns / 1ps
//lol
/******************************************************************************
 * Auto_Scheduler - CORRECT CONCEPT woi woi woi 
 * 
 * KONSEP:
 * - both_loaded_ready (ifmap + weight) = NEW LAYER
 * - weight_loaded ONLY (ifmap reuse) = NEXT BATCH in same layer
 * 
 * FLOW:
 * Layer 0:
 *   1. ifmap + weight batch 0 → both=1 → start
 *   2. weight batch 1 → weight=1 → start
 *   3. weight batch 2 → weight=1 → start
 *   ... (8 batches total)
 * 
 * Layer 1:
 *   9. ifmap + weight batch 0 → both=1 → NEW LAYER → start
 ******************************************************************************/

module Auto_Scheduler (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       weight_write_done,
    input  wire       ifmap_write_done,
    input  wire       ext_scheduler_start,
    input  wire [1:0] external_layer_id,
    input  wire       batch_complete_signal,
    output wire       final_start_signal,
    output reg  [2:0] current_batch_id,
    output reg  [1:0] current_layer_id,
    output wire       all_batches_complete,
    output wire       layer_transition,
    output wire       clear_output_bram,
    output wire       auto_start_active,
    output wire       data_load_ready
);

    // Load detection
    reg weight_write_done_prev, ifmap_write_done_prev;
    wire weight_done_posedge = weight_write_done & ~weight_write_done_prev;
    wire ifmap_done_posedge = ifmap_write_done & ~ifmap_write_done_prev;
    
    reg ifmap_loaded, weight_loaded;
    wire both_loaded_ready = ifmap_loaded & weight_loaded;
    wire weight_only_ready = weight_loaded & !ifmap_loaded;  // NEW: weight-only reload

    // FSM States
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
    reg [2:0] max_batch_for_current_layer;
    
    always @(*) begin
        case (current_layer_id)
            2'd0:    max_batch_for_current_layer = 3'd7;
            2'd1:    max_batch_for_current_layer = 3'd3;
            2'd2:    max_batch_for_current_layer = 3'd0;
            2'd3:    max_batch_for_current_layer = 3'd0;
            default: max_batch_for_current_layer = 3'd7;
        endcase
    end

    // Layer change detection (ONLY when both loaded)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_layer_id <= 2'd0;
            layer_changed <= 1'b0;
            first_load_done <= 1'b0;
        end else begin
            layer_changed <= 1'b0;
            
            // NEW LAYER: Only when BOTH ifmap + weight loaded after ALL_DONE
            if (both_loaded_ready && batch_state == BATCH_ALL_DONE) begin
                if (current_layer_id < 2'd3)
                    current_layer_id <= current_layer_id + 2'd1;
                else
                    current_layer_id <= 2'd0;
                layer_changed <= 1'b1;
                $display("[%0t] [AUTO_SCHED] NEW LAYER: %0d → %0d", $time, current_layer_id, current_layer_id + 2'd1);
            end
            
            // First load
            if (both_loaded_ready && batch_state == BATCH_IDLE && !first_load_done) begin
                first_load_done <= 1'b1;
                $display("[%0t] [AUTO_SCHED] First load (Layer 0)", $time);
            end
        end
    end
    
    assign layer_transition = layer_changed;
    
    reg [1:0] clear_bram_counter;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            clear_bram_counter <= 2'd0;
        else if (layer_changed)
            clear_bram_counter <= 2'd2;
        else if (clear_bram_counter > 0)
            clear_bram_counter <= clear_bram_counter - 2'd1;
    end
    
    assign clear_output_bram = (clear_bram_counter > 0);

    // Load flag management (MODIFIED!)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            weight_write_done_prev <= 1'b0;
            ifmap_write_done_prev <= 1'b0;
            ifmap_loaded <= 1'b0;
            weight_loaded <= 1'b0;
        end else begin
            weight_write_done_prev <= weight_write_done;
            ifmap_write_done_prev <= ifmap_write_done;
            
            if (ifmap_done_posedge) begin
                ifmap_loaded <= 1'b1;
                $display("[%0t] [AUTO_SCHED] ifmap_loaded = 1", $time);
            end
            
            if (weight_done_posedge) begin
                weight_loaded <= 1'b1;
                $display("[%0t] [AUTO_SCHED] weight_loaded = 1", $time);
            end
            
            // Clear ONLY weight_loaded after starting batch (ifmap reused!)
            if (batch_state == BATCH_WAIT_INITIAL) begin
                weight_loaded <= 1'b0;
                $display("[%0t] [AUTO_SCHED] weight_loaded cleared (ifmap reused)", $time);
                
                // Clear ifmap ONLY on layer change
                if (layer_changed) begin
                    ifmap_loaded <= 1'b0;
                    $display("[%0t] [AUTO_SCHED] ifmap_loaded cleared (new layer)", $time);
                end
            end
        end
    end
    
    assign data_load_ready = weight_loaded;  // Ready when weight loaded (ifmap can be old)

    // Batch State Machine (CORRECT!)
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
                // First batch: need both ifmap + weight
                if (both_loaded_ready)
                    batch_next_state = BATCH_WAIT_INITIAL;
            end
            
            BATCH_WAIT_INITIAL: begin
                batch_next_state = BATCH_RUNNING;
            end
            
            BATCH_RUNNING: begin
                if (batch_complete_signal) begin
                    if (current_batch_id >= max_batch_for_current_layer)
                        batch_next_state = BATCH_ALL_DONE;
                    else
                        batch_next_state = BATCH_NEXT;
                end
            end
            
            // CORRECT: Wait for weight (ifmap reused)
            BATCH_NEXT: begin
                if (weight_loaded)  // Only need weight! (ifmap reused from previous)
                    batch_next_state = BATCH_WAIT_INITIAL;
                // else STAY in BATCH_NEXT
            end
            
            BATCH_ALL_DONE: begin
                // New layer needs both ifmap + weight
                if (both_loaded_ready)
                    batch_next_state = BATCH_WAIT_INITIAL;
            end
            
            default: batch_next_state = BATCH_IDLE;
        endcase
    end
    
    // Batch counter
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
                        $display("[%0t] [AUTO_SCHED] Batch %0d → %0d", $time, current_batch_id, current_batch_id + 3'd1);
                    end
                end
                
                BATCH_ALL_DONE: begin
                    if (both_loaded_ready)
                        current_batch_id <= 3'd0;
                end
            endcase
        end
    end
    
    // Auto-start generation
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
    
    assign final_start_signal = batch_auto_start | ext_scheduler_start;
    assign auto_start_active = batch_auto_start;
    assign all_batches_complete = (batch_state == BATCH_ALL_DONE);

endmodule