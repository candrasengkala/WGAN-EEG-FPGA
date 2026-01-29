`timescale 1ns / 1ps

/******************************************************************************
 * Scheduler_FSM - MULTI-LAYER VERSION (3 LAYERS)
 * * Supports:
 * Layer 0 (D1): 32 rows, 512 cols → 32 tiles → 8 batches (4 tiles/batch)
 * Layer 1 (D2): 64 rows, 256 cols → 16 tiles → 4 batches (4 tiles/batch)
 * Layer 3 (D4): 256 rows, 64 cols → 4 tiles → 1 batch (ALL tiles at once!)
 * Layer 2 (D3): 128 rows, 128 cols → 8 tiles → 1 batch (ALL tiles at once!)
 * * Layer 2 Special Case:
 * - Weight depth 2048 can fit ALL 8 tiles (128×128 = 16384 ÷ 16 BRAMs = 1024/BRAM)
 * - NO weight reload needed!
 * - Process all 128 rows in single batch
 * - num_iterations = 128 (not 256)
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
    reg [7:0] pass_counter; 
    // 0-255 (max for layer 1: 64 rows × 4 = 256 passes)
    
    // ========================================================================
    // Layer-specific parameters
    // ========================================================================
    reg [9:0] max_passes_per_batch;
    reg [6:0] rows_per_batch;
    
    // --- FIX 1: Corrected Case Syntax ---
    always @(*) begin
        case (current_layer_id)
            2'd0: begin
                max_passes_per_batch = 10'd127;
                rows_per_batch = 7'd31;
            end
            2'd1: begin
                max_passes_per_batch = 10'd255;
                rows_per_batch = 7'd63;
            end
            2'd2: begin
                max_passes_per_batch = 10'd127;
                rows_per_batch = 7'd127;
            end
            2'd3: begin  // Layer D4: 256 rows, 1 batch
                max_passes_per_batch = 10'd255;
                rows_per_batch = 7'd127; // Adjusted to match reg width (7-bit), was 8'd255 in original but reg is 7-bit
            end
            default: begin
                max_passes_per_batch = 10'd127;
                rows_per_batch = 7'd31;
            end
        endcase
    end
    
    // ========================================================================
    // Pass counter decode (SAMA untuk semua layer!)
    // pass[7:6] = tile dalam batch (0-3)
    // pass[5:0] = row dalam tile (0-31 atau 0-63)
    // ========================================================================
    wire [1:0] tile_in_batch = pass_counter[7:6]; // Tile 0-3
    wire [5:0] row_in_tile   = pass_counter[5:0]; // Row 0-31 (L0) or 0-63 (L1)
    
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
            // --- FIX 2: Closed begin/end block ---
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
    
    // RENAMED THIS WIRE to avoid confusion. It represents the full pass index.
    wire [7:0] current_pass_index = (state == WAIT_TRANS && done_transpose == 5'd16 && pass_counter < max_passes_per_batch)
                                  ? (pass_counter + 8'd1)          // Next pass index
                                  : pass_counter;                  // Current pass index
    
    wire [5:0] current_absolute_tile = {current_batch_id, current_pass_tile};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            start_Mapper <= 0;
            start_weight <= 0; start_ifmap  <= 0; start_transpose <= 0; done <= 0;
            if_addr_start <= 0; if_addr_end <= 0;
            ifmap_sel_in <= 0;
            addr_start <= 0; addr_end <= 0;
            Instruction_code_transpose <= 0; num_iterations <= 0;
            row_id <= 0;
            tile_id <= 0; layer_id <= 0;
        end 
        else begin
            start_Mapper <= 0;
            start_weight <= 0; start_ifmap  <= 0; start_transpose <= 0; done <= 0;
            
            case (next_state)
                START_ALL: begin
                    row_id   <= {3'd0, current_pass_index[5:0]}; // Use only lower 6 bits for row_id
                    tile_id  <= current_absolute_tile;
                    layer_id <= current_layer_id;
                    
                    ifmap_sel_in <= current_pass_index[3:0]; // Always lower 4 bits
                    
                    // IFMAP address decode based on row
                    if (current_layer_id == 2'd0) begin
                        // Layer 0: 2 ranges (bit 4 determines range)
                        if (current_pass_index[4] == 1'b0) begin
                            if_addr_start <= 10'd0;
                            if_addr_end   <= 10'd255;
                        end else begin
                            if_addr_start <= 10'd256;
                            if_addr_end   <= 10'd511;
                        end
                    end 
                    else if (current_layer_id == 2'd1) begin
                        // Layer 1: 4 ranges (bits [5:4] determine range)
                        case (current_pass_index[5:4])
                            2'b00: begin if_addr_start <= 10'd0;   if_addr_end <= 10'd255;  end
                            2'b01: begin if_addr_start <= 10'd256; if_addr_end <= 10'd511;  end
                            2'b10: begin if_addr_start <= 10'd512; if_addr_end <= 10'd767;  end
                            2'b11: begin if_addr_start <= 10'd768; if_addr_end <= 10'd1023; end
                        endcase
                    end 
                    // --- FIX 3: Corrected Else-If Structure ---
                    else if (current_layer_id == 2'd2) begin
                        // Layer 2: 8 ranges (bits [6:4] determine range)
                        case (current_pass_index[6:4])
                            3'b000: begin if_addr_start <= 10'd0;   if_addr_end <= 10'd127;  end
                            3'b001: begin if_addr_start <= 10'd128; if_addr_end <= 10'd255;  end
                            3'b010: begin if_addr_start <= 10'd256; if_addr_end <= 10'd383;  end
                            3'b011: begin if_addr_start <= 10'd384; if_addr_end <= 10'd511;  end
                            3'b100: begin if_addr_start <= 10'd512; if_addr_end <= 10'd639;  end
                            3'b101: begin if_addr_start <= 10'd640; if_addr_end <= 10'd767;  end
                            3'b110: begin if_addr_start <= 10'd768; if_addr_end <= 10'd895;  end
                            3'b111: begin if_addr_start <= 10'd896; if_addr_end <= 10'd1023; end
                        endcase
                    end 
                    else if (current_layer_id == 2'd3) begin
                        // Layer 3: 16 ranges (bits [7:4] determine range)
                        case (current_pass_index[7:4])
                            4'h0: begin if_addr_start <= 10'd0;   if_addr_end <= 10'd15;   end
                            4'h1: begin if_addr_start <= 10'd16;  if_addr_end <= 10'd31;   end
                            4'h2: begin if_addr_start <= 10'd32;  if_addr_end <= 10'd47;   end
                            4'h3: begin if_addr_start <= 10'd48;  if_addr_end <= 10'd63;   end
                            4'h4: begin if_addr_start <= 10'd64;  if_addr_end <= 10'd79;   end
                            4'h5: begin if_addr_start <= 10'd80;  if_addr_end <= 10'd95;   end
                            4'h6: begin if_addr_start <= 10'd96;  if_addr_end <= 10'd111;  end
                            4'h7: begin if_addr_start <= 10'd112; if_addr_end <= 10'd127;  end
                            4'h8: begin if_addr_start <= 10'd128; if_addr_end <= 10'd143;  end
                            4'h9: begin if_addr_start <= 10'd144; if_addr_end <= 10'd159;  end
                            4'hA: begin if_addr_start <= 10'd160; if_addr_end <= 10'd175;  end
                            4'hB: begin if_addr_start <= 10'd176; if_addr_end <= 10'd191;  end
                            4'hC: begin if_addr_start <= 10'd192; if_addr_end <= 10'd207;  end
                            4'hD: begin if_addr_start <= 10'd208; if_addr_end <= 10'd223;  end
                            4'hE: begin if_addr_start <= 10'd224; if_addr_end <= 10'd239;  end
                            4'hF: begin if_addr_start <= 10'd240; if_addr_end <= 10'd255;  end
                        endcase
                    end 
                    else begin
                        // Default fallback
                        if_addr_start <= 10'd0;
                        if_addr_end <= 10'd255;
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
                             current_absolute_tile, current_pass_index, current_pass_index[3:0]);
                end
                
                START_TRANS: begin
                    Instruction_code_transpose <= 8'h03;
                    num_iterations <= (current_layer_id == 2'd3) ? 9'd64 : (current_layer_id == 2'd2) ? 9'd128 : 9'd256;
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
    // --- FIX 4: Added closing module keywords ---
endmodule
