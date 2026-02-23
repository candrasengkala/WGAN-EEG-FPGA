`timescale 1ns / 1ps

/******************************************************************************
 * Module      : Scheduler_FSM fix
 * Author      : Dharma Anargya Jowandy (Fixed Version 3)
 * Date        : February 2026
 *
 * Description :
 * Finite State Machine that orchestrates the computation flow for a single
 * batch processing cycle. Coordinates weight/ifmap loading, MM2IM mapping,
 * and transpose execution.
 *
 * Key Feature :
 * - Layer-Aware Pass Decoding
 * Interprets the pass counter based on active layer configuration:
 *   Layer 0 : 32 rows per tile (5-bit row index)
 *   Layer 1 : 64 rows per tile (6-bit row index)
 *   Layer 2  : 128 rows per tile (7-bit row index)
 *   Layer 3  : 256 rows per tile (8-bit row index)
 *
 * BUG FIX (v3) - absolute_tile_id:
 *   SEBELUMNYA: wire [5:0] absolute_tile_id = {current_batch_id, tile_in_batch};
 *   MASALAH   : tile_in_batch adalah 3-bit tapi untuk Layer 0/1/3 hanya
 *               menggunakan 2-bit efektif (MSB selalu 0). Concatenation
 *               {3-bit batch, 3-bit tile} menghasilkan lompatan per-batch
 *               sebesar 8, bukan 4.
 *               Contoh Layer 1:
 *                 Batch 0: {000, 0, 00..11} = 0,1,2,3      (benar)
 *                 Batch 1: {001, 0, 00..11} = 8,9,10,11    (SALAH, harusnya 4..7)
 *                 Batch 2: {010, 0, 00..11} = 16,17,18,19  (SALAH, harusnya 8..11)
 *               Akibat: channel = tile_id*4 → Batch 1 menulis ke Ch 32-47
 *               padahal seharusnya Ch 16-31. Output batch 1 dan 3 hanya berisi
 *               nilai bias karena tidak ada yang menulis ke lokasi yang benar.
 *   FIX       : Gunakan aritmatika perkalian:
 *               absolute_tile_id = current_batch_id * tiles_per_batch + tile_in_batch
 *               Contoh Layer 1 (tiles_per_batch=4):
 *                 Batch 0: 0*4 + 0..3 = 0..3    ✓
 *                 Batch 1: 1*4 + 0..3 = 4..7    ✓
 *                 Batch 2: 2*4 + 0..3 = 8..11   ✓
 *                 Batch 3: 3*4 + 0..3 = 12..15  ✓
 *
 * Parameters :
 * - ADDR_WIDTH : Address bus width (default: 10)
 *
 ******************************************************************************/

module Scheduler_FSM #(
    parameter ADDR_WIDTH = 10 
)(
    // System Signals
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire                   start,
    
    // Execution Context
    input  wire [1:0]             current_layer_id,
    input  wire [2:0]             current_batch_id,
    
    // Sub-module Status Flags
    input  wire                   done_mapper,
    input  wire                   done_weight,
    input  wire                   if_done,
    input  wire [4:0]             done_transpose,
    
    // Sub-module Triggers
    output reg                    start_Mapper,
    output reg                    start_weight,
    output reg                    start_ifmap,
    output reg                    start_transpose,
    
    // Memory Addressing (Ifmap)
    output reg  [ADDR_WIDTH-1:0]  if_addr_start,
    output reg  [ADDR_WIDTH-1:0]  if_addr_end,
    output reg  [3:0]             ifmap_sel_in,
    
    // Memory Addressing (Weight)
    output reg  [ADDR_WIDTH-1:0]  addr_start,
    output reg  [ADDR_WIDTH-1:0]  addr_end,
    
    // Transpose/Mapper Parameters
    output reg  [7:0]             Instruction_code_transpose,
    
    // num_iterations: combinational agar langsung valid saat layer berganti
    output wire [8:0]             num_iterations,
    
    output reg  [8:0]             row_id,
    output reg  [5:0]             tile_id,
    output reg  [1:0]             layer_id,
    
    // Status Outputs
    output reg                    done,
    output reg                    batch_complete
);

    // ========================================================================
    // num_iterations: combinational
    // ========================================================================
    assign num_iterations = (current_layer_id == 2'd3) ? 9'd63  : 
                            (current_layer_id == 2'd2) ? 9'd129 : 
                            (current_layer_id == 2'd1) ? 9'd257 :
                            9'd257;                               // Layer 0 //new

    // ========================================================================
    // State Encoding
    // ========================================================================
    localparam [2:0]
        IDLE        = 3'd0,
        START_ALL   = 3'd1,
        WAIT_BRAM   = 3'd2,
        START_TRANS = 3'd3,
        WAIT_TRANS  = 3'd4,
        DONE_STATE  = 3'd5;
        
    reg [2:0] state, next_state;
    reg [1:0] bram_wait_cnt;
    reg [9:0] pass_counter;

    // ========================================================================
    // Layer Configuration Logic
    // ========================================================================
    reg [9:0] max_passes_per_batch;
    reg [6:0] rows_per_batch;
    
    always @(*) begin
        case (current_layer_id)
            2'd0: begin
                max_passes_per_batch = 10'd127;  // 128 passes (32 rows × 4 tiles)
                rows_per_batch       = 7'd31;
            end
            2'd1: begin
                max_passes_per_batch = 10'd255;  // 256 passes (64 rows × 4 tiles)
                rows_per_batch       = 7'd63;
            end
            2'd2: begin
                max_passes_per_batch = 10'd1023; // 1024 passes (128 rows × 8 tiles)
                rows_per_batch       = 7'd127;
            end
            2'd3: begin
                max_passes_per_batch = 10'd1023; // 1024 passes (256 rows × 4 tiles)
                rows_per_batch       = 7'd63;
            end
            default: begin
                max_passes_per_batch = 10'd127;
                rows_per_batch       = 7'd31;
            end
        endcase
    end
    
    // ========================================================================
    // Pass Counter Decoding (Layer-Aware)
    // ========================================================================
    reg [2:0] tile_in_batch;
    reg [7:0] row_in_tile;
    
    always @(*) begin
        tile_in_batch = 3'd0;
        row_in_tile   = 8'd0;

        case (current_layer_id)
            2'd0: begin
                // Layer 0: 4 tiles, 32 rows per tile
                tile_in_batch = {1'b0, pass_counter[6:5]};
                row_in_tile   = {3'd0,  pass_counter[4:0]};
            end
            2'd1: begin
                // Layer 1: 4 tiles, 64 rows per tile
                tile_in_batch = {1'b0, pass_counter[7:6]};
                row_in_tile   = {2'd0,  pass_counter[5:0]};
            end
            default: begin
                if (current_layer_id == 2'd3) begin
                    // Layer 3: 4 tiles, 256 rows per tile
                    tile_in_batch = {1'b0, pass_counter[9:8]};
                    row_in_tile   = pass_counter[7:0];
                end else begin
                    // Layer 2: 8 tiles, 128 rows per tile
                    tile_in_batch = pass_counter[9:7];
                    row_in_tile   = pass_counter[6:0];
                end
            end
        endcase
    end

    // ========================================================================
    // FIX: tiles_per_batch untuk aritmatika absolute_tile_id
    // ========================================================================
    reg [3:0] tiles_per_batch;
    always @(*) begin
        case (current_layer_id)
            2'd2:    tiles_per_batch = 4'd8; // Layer 2: 8 tiles per batch
            default: tiles_per_batch = 4'd4; // Layer 0/1/3: 4 tiles per batch
        endcase
    end

    // ========================================================================
    // FIX: absolute_tile_id menggunakan perkalian, bukan bit-concatenation
    // ========================================================================
    wire [5:0] absolute_tile_id = current_batch_id * tiles_per_batch + tile_in_batch;

    // ========================================================================
    // Main State Machine (Sequential)
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= IDLE;
            bram_wait_cnt  <= 2'd0;
            pass_counter   <= 10'd0;
            batch_complete <= 1'b0;
        end else begin
            state <= next_state;
            
            if (batch_complete)
                batch_complete <= 1'b0;

            // BRAM Wait Timer
            if (state == WAIT_BRAM) begin
                if (bram_wait_cnt < 2'd2)
                    bram_wait_cnt <= bram_wait_cnt + 1'b1;
                else
                    bram_wait_cnt <= 2'd0;
            end else begin
                bram_wait_cnt <= 2'd0;
            end
            
            // Pass Counter
            if (state == WAIT_TRANS && done_transpose == 5'd16) begin
                if (pass_counter < max_passes_per_batch) begin
                    pass_counter <= pass_counter + 10'd1;
                end else begin
                    pass_counter   <= 10'd0;
                    batch_complete <= 1'b1;
                end
            end else if (state == IDLE) begin
                pass_counter <= 10'd0;
            end
        end
    end
    
    // ========================================================================
    // State Transitions (Combinational)
    // ========================================================================
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
    // Predictive Decoding (Next Pass Prefetch)
    // ========================================================================
    reg [2:0] current_pass_tile;
    reg [7:0] current_pass_row;
    
    // Wire bantu untuk next pass (Verilog 2001 compatible)
    wire [9:0] next_pass = pass_counter + 10'd1;

    always @(*) begin
        if (state == WAIT_TRANS && done_transpose == 5'd16 && pass_counter < max_passes_per_batch) begin
            // Prefetch: decode pass berikutnya
            if (current_layer_id == 2'd0) begin
                current_pass_tile = next_pass[9:5];
                current_pass_row  = {3'd0, next_pass[4:0]};
            end else if (current_layer_id == 2'd1) begin
                current_pass_tile = {1'b0, next_pass[9:6]};
                current_pass_row  = {2'd0, next_pass[5:0]};
            end else if (current_layer_id == 2'd2) begin
                current_pass_tile = next_pass[9:7];
                current_pass_row  = {1'd0, next_pass[6:0]};
            end else begin
                // Layer 3
                current_pass_tile = {1'b0, next_pass[9:8]};
                current_pass_row  = next_pass[7:0];
            end
        end else begin
            // Decode pass saat ini
            current_pass_tile = tile_in_batch;
            current_pass_row  = row_in_tile;
        end
    end
    
    // FIX: gunakan tiles_per_batch juga untuk current_absolute_tile_calc
    wire [5:0] current_absolute_tile_calc = current_batch_id * tiles_per_batch + current_pass_tile;

    // ========================================================================
    // Output Registers
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            start_Mapper               <= 0;
            start_weight               <= 0;
            start_ifmap                <= 0; 
            start_transpose            <= 0;
            done                       <= 0;
            if_addr_start              <= 0;
            if_addr_end                <= 0;
            ifmap_sel_in               <= 0;
            addr_start                 <= 0;
            addr_end                   <= 0;
            Instruction_code_transpose <= 0; 
            row_id                     <= 0;
            tile_id                    <= 0;
            layer_id                   <= 0;
        end 
        else begin
            // Default: semua pulse rendah
            start_Mapper    <= 0;
            start_weight    <= 0;
            start_ifmap     <= 0; 
            start_transpose <= 0;
            done            <= 0;
            
            case (next_state)
                // ------------------------------------------------------------
                START_ALL: begin
                // ------------------------------------------------------------
                    row_id       <= {1'd0, current_pass_row};
                    tile_id      <= current_absolute_tile_calc;
                    layer_id     <= current_layer_id;
                    ifmap_sel_in <= current_pass_row[3:0];
                    
                    // IFMAP Address Decoding
                    if (current_layer_id == 2'd0) begin
                        if (current_pass_row[4] == 1'b0) begin
                            if_addr_start <= 10'd0;   if_addr_end <= 10'd255;
                        end else begin
                            if_addr_start <= 10'd256; if_addr_end <= 10'd511;
                        end
                    end 
                    else if (current_layer_id == 2'd1) begin
                        case (current_pass_row[5:4])
                            2'b00: begin if_addr_start <= 10'd0;   if_addr_end <= 10'd255;  end
                            2'b01: begin if_addr_start <= 10'd256; if_addr_end <= 10'd511;  end
                            2'b10: begin if_addr_start <= 10'd512; if_addr_end <= 10'd767;  end
                            2'b11: begin if_addr_start <= 10'd768; if_addr_end <= 10'd1023; end
                        endcase
                    end 
                    else if (current_layer_id == 2'd2) begin
                        case (current_pass_row[6:4])
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
                        case (current_pass_row[7:4])
                            4'h0: begin if_addr_start <= 10'd0;   if_addr_end <= 10'd63;   end
                            4'h1: begin if_addr_start <= 10'd64;  if_addr_end <= 10'd127;  end
                            4'h2: begin if_addr_start <= 10'd128; if_addr_end <= 10'd191;  end
                            4'h3: begin if_addr_start <= 10'd192; if_addr_end <= 10'd255;  end
                            4'h4: begin if_addr_start <= 10'd256; if_addr_end <= 10'd319;  end
                            4'h5: begin if_addr_start <= 10'd320; if_addr_end <= 10'd383;  end
                            4'h6: begin if_addr_start <= 10'd384; if_addr_end <= 10'd447;  end
                            4'h7: begin if_addr_start <= 10'd448; if_addr_end <= 10'd511;  end
                            4'h8: begin if_addr_start <= 10'd512; if_addr_end <= 10'd575;  end
                            4'h9: begin if_addr_start <= 10'd576; if_addr_end <= 10'd639;  end
                            4'hA: begin if_addr_start <= 10'd640; if_addr_end <= 10'd703;  end
                            4'hB: begin if_addr_start <= 10'd704; if_addr_end <= 10'd767;  end
                            4'hC: begin if_addr_start <= 10'd768; if_addr_end <= 10'd831;  end
                            4'hD: begin if_addr_start <= 10'd832; if_addr_end <= 10'd895;  end
                            4'hE: begin if_addr_start <= 10'd896; if_addr_end <= 10'd959;  end
                            4'hF: begin if_addr_start <= 10'd960; if_addr_end <= 10'd1023; end
                        endcase
                    end 
                    else begin
                        if_addr_start <= 10'd0; if_addr_end <= 10'd255;
                    end
                    
                    // Weight Address Decoding (berdasarkan tile dalam batch, bukan absolute)
                    if (current_layer_id == 2'd3) begin
                        // Layer 3: 64 addresses per tile
                        case (current_pass_tile)
                            3'd0: begin addr_start <= 10'd0;   addr_end <= 10'd63;  end
                            3'd1: begin addr_start <= 10'd64;  addr_end <= 10'd127; end
                            3'd2: begin addr_start <= 10'd128; addr_end <= 10'd191; end
                            3'd3: begin addr_start <= 10'd192; addr_end <= 10'd255; end
                            default: begin addr_start <= 10'd0; addr_end <= 10'd63; end
                        endcase
                    end else if (current_layer_id == 2'd2) begin
                        // Layer 2: 128 addresses per tile
                        case (current_pass_tile)
                            3'd0: begin addr_start <= 10'd0;   addr_end <= 10'd127;  end
                            3'd1: begin addr_start <= 10'd128; addr_end <= 10'd255;  end
                            3'd2: begin addr_start <= 10'd256; addr_end <= 10'd383;  end
                            3'd3: begin addr_start <= 10'd384; addr_end <= 10'd511;  end
                            3'd4: begin addr_start <= 10'd512; addr_end <= 10'd639;  end
                            3'd5: begin addr_start <= 10'd640; addr_end <= 10'd767;  end
                            3'd6: begin addr_start <= 10'd768; addr_end <= 10'd895;  end
                            3'd7: begin addr_start <= 10'd896; addr_end <= 10'd1023; end
                        endcase
                    end else begin
                        // Layer 0/1: 256 addresses per tile
                        case (current_pass_tile)
                            3'd0: begin addr_start <= 10'd0;   addr_end <= 10'd255;  end
                            3'd1: begin addr_start <= 10'd256; addr_end <= 10'd511;  end
                            3'd2: begin addr_start <= 10'd512; addr_end <= 10'd767;  end
                            3'd3: begin addr_start <= 10'd768; addr_end <= 10'd1023; end
                            default: begin addr_start <= 10'd0; addr_end <= 10'd255; end
                        endcase
                    end
                    
                    start_Mapper <= 1'b1;
                    start_weight <= 1'b1;
                    start_ifmap  <= 1'b1;
                end
                
                // ------------------------------------------------------------
                START_TRANS: begin
                // ------------------------------------------------------------
                    Instruction_code_transpose <= 8'h03;
                    start_transpose            <= 1'b1;
                end
                
                // ------------------------------------------------------------
                DONE_STATE: begin
                // ------------------------------------------------------------
                    done <= 1'b1;
                end
                
                default: ; // do nothing
            endcase
        end
    end

endmodule