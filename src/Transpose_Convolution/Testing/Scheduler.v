`timescale 1ns / 1ps

/******************************************************************************
 * Scheduler_FSM - MULTI-LAYER VERSION
 * 
 * Supports:
 *   Layer 0 (D1): 32 rows, 512 cols → 32 tiles → 8 batches
 *   Layer 1 (D2): 64 rows, 256 cols → 16 tiles → 4 batches
 * 
 * Parameters controlled by layer_id input:
 *   - Number of rows
 *   - Number of batches
 *   - IFMAP address ranges
 *   - Tile count
 ******************************************************************************/

module Scheduler_FSM #(
    parameter ADDR_WIDTH = 10 
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       start,
    
    // Layer configuration
    input  wire [1:0] current_layer_id,    // 0=D1, 1=D2, etc
    input  wire [2:0] current_batch_id,    // 0-7 (which set of 4 tiles)
    
    input  wire       done_mapper,
    input  wire       done_weight,
    input  wire       if_done,
    input  wire [4:0] done_transpose,
    
    output reg        start_Mapper,
    output reg        start_weight,
    output reg        start_ifmap,
    output reg        start_transpose,
    
    output reg [ADDR_WIDTH-1:0]  if_addr_start,
    output reg [ADDR_WIDTH-1:0]  if_addr_end,
    output reg [3:0]             ifmap_sel_in,
    output reg [ADDR_WIDTH-1:0]  addr_start,
    output reg [ADDR_WIDTH-1:0]  addr_end,
    
    output reg [7:0]  Instruction_code_transpose,
    output reg [8:0]  num_iterations,
    output reg [8:0]  row_id,
    output reg [5:0]  tile_id,
    output reg [1:0]  layer_id,
    
    output reg        done,
    output reg        batch_complete
);

    localparam [2:0]
        IDLE        = 3'd0,
        START_ALL   = 3'd1,
        WAIT_BRAM   = 3'd2,
        START_TRANS = 3'd3,
        WAIT_TRANS  = 3'd4,
        DONE_STATE  = 3'd5;

    reg [2:0] state, next_state;
    reg [1:0] bram_wait_cnt;
    reg [7:0] pass_counter;  // 0-255 (max for layer 1: 64 rows × 4 = 256 passes)
    
    // ========================================================================
    // Layer-specific parameters
    // ========================================================================
    reg [7:0] max_passes_per_batch;   // Layer 0: 128, Layer 1: 256
    reg [5:0] rows_per_batch;         // Layer 0: 32,  Layer 1: 64
    
    always @(*) begin
        case (current_layer_id)
            2'd0: begin  // Layer D1: 32 rows, 8 batches
                max_passes_per_batch = 8'd127;  // 0-127 = 128 passes (32 rows × 4 tiles)
                rows_per_batch = 6'd31;         // 0-31 = 32 rows
            end
            2'd1: begin  // Layer D2: 64 rows, 4 batches
                max_passes_per_batch = 8'd255;  // 0-255 = 256 passes (64 rows × 4 tiles)
                rows_per_batch = 6'd63;         // 0-63 = 64 rows
            end
            default: begin
                max_passes_per_batch = 8'd127;
                rows_per_batch = 6'd31;
            end
        endcase
    end
    
    // ========================================================================
    // Pass counter decode (SAMA untuk semua layer!)
    // pass[7:6] = tile dalam batch (0-3)
    // pass[5:0] = row dalam tile (0-31 atau 0-63)
    // ========================================================================
    wire [1:0] tile_in_batch = pass_counter[7:6];  // Tile 0-3
    wire [5:0] row_in_tile   = pass_counter[5:0];  // Row 0-31 (L0) or 0-63 (L1)
    
    wire [5:0] absolute_tile_id = {current_batch_id, tile_in_batch};
    
    // ========================================================================
    // State Machine
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            bram_wait_cnt <= 2'd0;
            pass_counter <= 8'd0;
            batch_complete <= 1'b0;
        end else begin
            state <= next_state;
            
            if (batch_complete)
                batch_complete <= 1'b0;
            
            if (state == WAIT_BRAM) begin
                if (bram_wait_cnt < 2'd2)
                    bram_wait_cnt <= bram_wait_cnt + 1'b1;
                else
                    bram_wait_cnt <= 2'd0;
            end else begin
                bram_wait_cnt <= 2'd0;
            end
            
            // Pass counter increment
            if (state == WAIT_TRANS && done_transpose == 5'd16) begin
                if (pass_counter < max_passes_per_batch)
                    pass_counter <= pass_counter + 8'd1;
                else begin
                    pass_counter <= 8'd0;
                    batch_complete <= 1'b1;
                end
            end else if (state == IDLE) begin
                pass_counter <= 8'd0;
            end
        end
    end
    
    always @(*) begin
        next_state = state;
        
        case (state)
            IDLE:        if (start) next_state = START_ALL;
            START_ALL:   next_state = WAIT_BRAM;
            WAIT_BRAM:   if (bram_wait_cnt >= 2'd2) next_state = START_TRANS;
            START_TRANS: next_state = WAIT_TRANS;
            WAIT_TRANS: begin
                if (done_transpose == 5'd16) begin
                    if (pass_counter >= max_passes_per_batch)
                        next_state = DONE_STATE;
                    else
                        next_state = START_ALL;
                end
            end
            DONE_STATE:  next_state = IDLE;
            default:     next_state = IDLE;
        endcase
    end

    // ========================================================================
    // Output Logic
    // ========================================================================
    wire [1:0] current_pass_tile = (state == WAIT_TRANS && done_transpose == 5'd16 && pass_counter < max_passes_per_batch) 
                                    ? (pass_counter + 8'd1) >> 6  // Next tile
                                    : pass_counter >> 6;          // Current tile
    
    wire [5:0] current_pass_row = (state == WAIT_TRANS && done_transpose == 5'd16 && pass_counter < max_passes_per_batch)
                                  ? (pass_counter + 8'd1) & 8'h3F  // Next row (mask lower 6 bits)
                                  : pass_counter & 8'h3F;          // Current row
    
    wire [5:0] current_absolute_tile = {current_batch_id, current_pass_tile};
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            start_Mapper <= 0; start_weight <= 0; start_ifmap  <= 0; start_transpose <= 0; done <= 0;
            if_addr_start <= 0; if_addr_end <= 0; ifmap_sel_in <= 0;
            addr_start <= 0; addr_end <= 0;
            Instruction_code_transpose <= 0; num_iterations <= 0;
            row_id <= 0; tile_id <= 0; layer_id <= 0;
        end 
        else begin
            start_Mapper <= 0; start_weight <= 0; start_ifmap  <= 0; start_transpose <= 0; done <= 0;
            
            case (next_state)
                START_ALL: begin
                    row_id   <= {3'd0, current_pass_row};
                    tile_id  <= current_absolute_tile;
                    layer_id <= current_layer_id;
                    
                    ifmap_sel_in <= current_pass_row[3:0];  // Always lower 4 bits
                    
                    // IFMAP address decode based on row
                    if (current_layer_id == 2'd0) begin
                        // Layer 0: 2 ranges (bit 4 determines range)
                        if (current_pass_row[4] == 1'b0) begin
                            if_addr_start <= 10'd0;
                            if_addr_end   <= 10'd255;
                        end else begin
                            if_addr_start <= 10'd256;
                            if_addr_end   <= 10'd511;
                        end
                    end else begin
                        // Layer 1: 4 ranges (bits [5:4] determine range)
                        case (current_pass_row[5:4])
                            2'b00: begin if_addr_start <= 10'd0;   if_addr_end <= 10'd255;  end
                            2'b01: begin if_addr_start <= 10'd256; if_addr_end <= 10'd511;  end
                            2'b10: begin if_addr_start <= 10'd512; if_addr_end <= 10'd767;  end
                            2'b11: begin if_addr_start <= 10'd768; if_addr_end <= 10'd1023; end
                        endcase
                    end
                    
                    // Weight address (same for both layers)
                    case (current_pass_tile)
                        2'd0: begin addr_start <= 10'd0;   addr_end <= 10'd255;  end
                        2'd1: begin addr_start <= 10'd256; addr_end <= 10'd511;  end
                        2'd2: begin addr_start <= 10'd512; addr_end <= 10'd767;  end
                        2'd3: begin addr_start <= 10'd768; addr_end <= 10'd1023; end
                    endcase
                    
                    start_Mapper <= 1'b1;
                    start_weight <= 1'b1;
                    start_ifmap  <= 1'b1;
                    
                    $display("[%0t] SCHED L%0d: Batch=%0d, Pass=%0d, Tile=%0d, Row=%0d, sel=%0d", 
                             $time, current_layer_id, current_batch_id, pass_counter,
                             current_absolute_tile, current_pass_row, current_pass_row[3:0]);
                end
                
                START_TRANS: begin
                    Instruction_code_transpose <= 8'h03;
                    num_iterations <= 9'd256;
                    start_transpose <= 1'b1;
                end
                
                DONE_STATE: begin
                    done <= 1'b1;
                    $display("[%0t] SCHED L%0d: *** BATCH %0d COMPLETE ***", 
                             $time, current_layer_id, current_batch_id);
                end
            endcase
        end
    end

endmodule