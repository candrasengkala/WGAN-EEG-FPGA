`timescale 1ns / 1ps

/******************************************************************************
 * Scheduler_FSM - MULTI-BATCH VERSION (8 batches × 4 tiles = 32 tiles)
 * 
 * Layer D1: [256 rows × 512 columns]
 * Total tiles: 32 (512 cols ÷ 16 PE)
 * Weight loads: 8 (4 tiles per load)
 * 
 * Architecture:
 *   - External system manages batch_id (0-7)
 *   - Scheduler processes 4 tiles per batch (128 passes)
 *   - Signal need_weight_reload when batch completes
 *   - External system reloads weight, increments batch_id, restarts scheduler
 * 
 * Batch Mapping:
 *   Batch 0: Tiles 0-3   (Cols 0-63)
 *   Batch 1: Tiles 4-7   (Cols 64-127)
 *   Batch 2: Tiles 8-11  (Cols 128-191)
 *   Batch 3: Tiles 12-15 (Cols 192-255)
 *   Batch 4: Tiles 16-19 (Cols 256-319)
 *   Batch 5: Tiles 20-23 (Cols 320-383)
 *   Batch 6: Tiles 24-27 (Cols 384-447)
 *   Batch 7: Tiles 28-31 (Cols 448-511)
 * 
 * Weight BRAM Address (repeats for each batch):
 *   Tile 0 (within batch): Addr 0-255
 *   Tile 1 (within batch): Addr 256-511
 *   Tile 2 (within batch): Addr 512-767
 *   Tile 3 (within batch): Addr 768-1023
 ******************************************************************************/

module Scheduler_FSM #(
    parameter ADDR_WIDTH = 10 
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       start,
    
    // NEW: Batch control from external system
    input  wire [2:0] current_batch_id,  // 0-7 (which set of 4 tiles)
    
    input  wire [7:0] current_layer_id, 
    
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
    
    // NEW: Signal to external system that this batch is complete
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
    reg [6:0] pass_counter;  // 0-127 (128 passes per batch, for 4 tiles)
    
    // Decode pass counter
    wire [1:0] tile_in_batch = pass_counter[6:5];  // Upper 2 bits: tile 0-3 within batch
    wire [4:0] row_in_tile   = pass_counter[4:0];  // Lower 5 bits: row 0-31
    
    // Calculate absolute tile ID
    wire [5:0] absolute_tile_id = {current_batch_id, tile_in_batch};  // batch*4 + tile_in_batch
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            bram_wait_cnt <= 2'd0;
            pass_counter <= 7'd0;
            batch_complete <= 1'b0;
        end else begin
            state <= next_state;
            
            // Clear batch_complete after 1 cycle
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
                if (pass_counter < 7'd127)
                    pass_counter <= pass_counter + 7'd1;
                else begin
                    pass_counter <= 7'd0;  // Reset for next batch
                    batch_complete <= 1'b1;  // Signal batch done
                end
            end else if (state == IDLE) begin
                pass_counter <= 7'd0;
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
                    if (pass_counter == 7'd127)
                        next_state = DONE_STATE;  // Batch done
                    else
                        next_state = START_ALL;   // Next pass in batch
                end
            end
            DONE_STATE:  next_state = IDLE;
            default:     next_state = IDLE;
        endcase
    end

    // Wire untuk current pass parameters
    wire [1:0] current_pass_tile_in_batch = (state == WAIT_TRANS && done_transpose == 5'd16 && pass_counter < 7'd127) 
                                             ? (pass_counter + 7'd1) >> 5  // Next tile
                                             : pass_counter >> 5;          // Current tile
    
    wire [4:0] current_pass_row = (state == WAIT_TRANS && done_transpose == 5'd16 && pass_counter < 7'd127)
                                  ? (pass_counter + 7'd1) & 7'h1F  // Next row
                                  : pass_counter & 7'h1F;          // Current row
    
    wire [5:0] current_absolute_tile = {current_batch_id, current_pass_tile_in_batch};
    
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
                    // Row ID = current row in tile (0-31)
                    row_id   <= {4'd0, current_pass_row};
                    
                    // Tile ID = ABSOLUTE tile ID (0-31)
                    tile_id  <= current_absolute_tile;
                    
                    // Layer ID = 0 (d1)
                    layer_id <= 2'd0;
                    
                    // Ifmap selector cycles 0-15 twice per tile
                    ifmap_sel_in <= current_pass_row[3:0];
                    
                    // Ifmap address: row 0-15 use 0-255, row 16-31 use 256-511
                    if (current_pass_row < 5'd16) begin
                        if_addr_start <= 10'd0;
                        if_addr_end   <= 10'd255;
                    end else begin
                        if_addr_start <= 10'd256;
                        if_addr_end   <= 10'd511;
                    end
                    
                    // Weight address: based on tile WITHIN BATCH (0-3)
                    // NOTE: Weight BRAM reloaded per batch, so address repeats!
                    case (current_pass_tile_in_batch)
                        2'd0: begin  // Tile 0 within batch
                            addr_start <= 10'd0;
                            addr_end   <= 10'd255;
                        end
                        2'd1: begin  // Tile 1 within batch
                            addr_start <= 10'd256;
                            addr_end   <= 10'd511;
                        end
                        2'd2: begin  // Tile 2 within batch
                            addr_start <= 10'd512;
                            addr_end   <= 10'd767;
                        end
                        2'd3: begin  // Tile 3 within batch
                            addr_start <= 10'd768;
                            addr_end   <= 10'd1023;
                        end
                    endcase
                    
                    start_Mapper <= 1'b1;
                    start_weight <= 1'b1;
                    start_ifmap  <= 1'b1;
                    
                    $display("[%0t] SCHEDULER: Batch=%0d, Pass=%0d, AbsTile=%0d, Row=%0d, ifmap_sel=%0d, w_addr=%0d-%0d", 
                             $time, current_batch_id,
                             (state == WAIT_TRANS && done_transpose == 5'd16 && pass_counter < 7'd127) ? pass_counter + 1 : pass_counter,
                             current_absolute_tile, current_pass_row, current_pass_row[3:0],
                             (current_pass_tile_in_batch == 0) ? 0 : (current_pass_tile_in_batch == 1) ? 256 : (current_pass_tile_in_batch == 2) ? 512 : 768,
                             (current_pass_tile_in_batch == 0) ? 255 : (current_pass_tile_in_batch == 1) ? 511 : (current_pass_tile_in_batch == 2) ? 767 : 1023);
                end
                
                START_TRANS: begin
                    Instruction_code_transpose <= 8'h03;
                    num_iterations <= 9'd256;
                    start_transpose <= 1'b1;
                end
                
                DONE_STATE: begin
                    done <= 1'b1;
                    $display("[%0t] SCHEDULER: *** BATCH %0d COMPLETE (128 passes, 4 tiles) ***", $time, current_batch_id);
                end
            endcase
        end
    end

endmodule