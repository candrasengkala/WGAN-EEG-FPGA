`timescale 1ns / 1ps

/******************************************************************************
 * Module      : Scheduler_FSM fix
 * Author      : Dharma Anargya Jowandy (Fixed Version 2)
 * Date        : January 2026
 *
 * Description :
 * Finite State Machine that orchestrates the computation flow for a single
 * batch processing cycle. Coordinates weight/ifmap loading, MM2IM mapping,
 * and transpose execution.
 *
 * Key Feature :
 * - Layer-Aware Pass Decoding
 * Interprets the pass counter based on active layer configuration:
 * - Layer 0 : 32 rows per tile (5-bit row index)
 * - Layer 1 : 64 rows per tile (6-bit row index)
 * - Layer 2/3 : 128 rows per tile (7-bit row index)
 *
 * Functionality :
 * - Generates start pulses for Mapper, Weight, Ifmap, and Transpose modules
 * - Computes address ranges for memory accesses per pass
 * - Manages state progression: Data Load -> Compute -> Transpose
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

    // --- PERBAIKAN: UBAH JADI WIRE AGAR INSTAN ---
    output wire [8:0]             num_iterations,

    output reg  [8:0]             row_id,
    output reg  [5:0]             tile_id,
    output reg  [1:0]             layer_id,

    // Status Outputs
    output reg                    done,
    output reg                    batch_complete
);

    // ========================================================================
    // PERBAIKAN LOGIC: ASSIGN INSTAN (COMBINATIONAL)
    // ========================================================================
    // Nilai ini akan langsung berubah saat current_layer_id berubah,
    // sehingga FSM Transpose menerima nilai yang benar (64) sebelum Start.
    assign num_iterations = (current_layer_id == 2'd3) ? 9'd65 :
                            (current_layer_id == 2'd2) ? 9'd127 :
                            (current_layer_id == 2'd1) ? 9'd257 : // Asumsi Layer 1 = 256 (sesuaikan jika beda)
                            9'd257;                               // Default/Layer 0

    // State Encoding
    localparam [2:0]
        IDLE        = 3'd0,
        START_ALL   = 3'd1,
        WAIT_BRAM   = 3'd2,
        START_TRANS = 3'd3,
        WAIT_TRANS  = 3'd4,
        DONE_STATE  = 3'd5;

    reg [2:0] state, next_state;
    reg [1:0] bram_wait_cnt;
    reg [9:0] pass_counter; // 10-bit counter (0..1023) for Layer 2/3

    // ========================================================================
    // Layer Configuration Logic
    // ========================================================================
    reg [9:0] max_passes_per_batch;
    reg [6:0] rows_per_batch;

    always @(*) begin
        case (current_layer_id)
            2'd0: begin
                max_passes_per_batch = 10'd127; // 128 passes
                rows_per_batch       = 7'd31;   // 32 rows
            end
            2'd1: begin
                max_passes_per_batch = 10'd255; // 256 passes
                rows_per_batch       = 7'd63;   // 64 rows
            end
            2'd2: begin
                max_passes_per_batch = 10'd1023; // 1024 passes (128 rows x 8 tiles)
                rows_per_batch       = 7'd127;   // 128 rows
            end
            2'd3: begin
                max_passes_per_batch = 10'd1023;  // 1024 passes (256 rows x 4 tiles)
                rows_per_batch       = 7'd63;    // Not used for Layer 3
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

    reg [2:0] tile_in_batch;  // 3 bits for up to 8 tiles (Layer 2)
    reg [7:0] row_in_tile;    // 8 bits untuk support 256 rows Layer 3

    always @(*) begin
        // Default initialization
        tile_in_batch = 3'd0;
        row_in_tile = 8'd0;

        case (current_layer_id)
            2'd0: begin
                // Layer 0: 32 rows (Row bits [4:0]), 4 tiles
                tile_in_batch = {1'b0, pass_counter[6:5]};
                row_in_tile   = {3'd0, pass_counter[4:0]};
            end
            2'd1: begin
                // Layer 1: 64 rows (Row bits [5:0]), 4 tiles
                tile_in_batch = {1'b0, pass_counter[7:6]};
                row_in_tile   = {2'd0, pass_counter[5:0]};
            end
            default: begin
                // Layer 2 & 3: Different row counts
                if (current_layer_id == 2'd3) begin
                    // Layer 3: 256 rows per tile, 4 tiles
                    tile_in_batch = {1'b0, pass_counter[9:8]};  // Bits [9:8] -> tile 0-3
                    row_in_tile   = pass_counter[7:0];          // Bits [7:0] -> row 0-255
                end else begin
                    // Layer 2: 128 rows per tile, 8 tiles
                    tile_in_batch = pass_counter[9:7];          // Bits [9:7] -> tile 0-7
                    row_in_tile   = pass_counter[6:0];          // Bits [6:0] -> row 0-127
                end
            end
        endcase
    end

    wire [5:0] absolute_tile_id = {current_batch_id, tile_in_batch};

    // ========================================================================
    // Main State Machine
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= IDLE;
            bram_wait_cnt  <= 2'd0;
            pass_counter   <= 8'd0;
            batch_complete <= 1'b0;
        end else begin
            state <= next_state;

            // Clear pulse
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

            // Pass Counter Increment Logic
            if (state == WAIT_TRANS && done_transpose == 5'd16) begin
                if (pass_counter < max_passes_per_batch) begin
                    pass_counter <= pass_counter + 8'd1;
                end else begin
                    pass_counter   <= 8'd0;
                    batch_complete <= 1'b1;
                end
            end else if (state == IDLE) begin
                pass_counter <= 8'd0;
            end
        end
    end

    // State Transitions
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
    // Output Generation Logic
    // ========================================================================

    // Predictive Decoding for Next Pass
    reg [2:0] current_pass_tile;  // 3-bit for up to 8 tiles (Layer 2)
    reg [7:0] current_pass_row;  // 8-bit untuk Layer 3

    always @(*) begin
        if (state == WAIT_TRANS && done_transpose == 5'd16 && pass_counter < max_passes_per_batch) begin
            // Decode NEXT pass
            if (current_layer_id == 2'd0) begin
                // Layer 0 (32 rows)
                current_pass_tile = (pass_counter + 10'd1) >> 5;
                current_pass_row  = {2'd0, (pass_counter + 10'd1) & 10'h1F};
            end else if (current_layer_id == 2'd1) begin
                // Layer 1 (64 rows)
                current_pass_tile = (pass_counter + 10'd1) >> 6;
                current_pass_row  = {1'd0, (pass_counter + 10'd1) & 10'h3F};
            end else if (current_layer_id == 2'd2) begin
                // Layer 2 (128 rows per tile, 8 tiles)
                current_pass_tile = (pass_counter + 10'd1) >> 7;
                current_pass_row  = (pass_counter + 10'd1) & 10'h7F;
            end else begin
                // Layer 3 (256 rows per tile)
                current_pass_tile = (pass_counter + 10'd1) >> 8;
                current_pass_row  = (pass_counter + 10'd1) & 10'hFF;
            end
        end else begin
            // Decode CURRENT pass
            current_pass_tile = tile_in_batch;
            current_pass_row  = row_in_tile;
        end
    end

    wire [5:0] current_absolute_tile_calc = {current_batch_id, current_pass_tile};

    // Output Registers Update
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            start_Mapper <= 0; start_weight <= 0; start_ifmap <= 0;
            start_transpose <= 0; done <= 0;
            if_addr_start <= 0; if_addr_end <= 0;
            ifmap_sel_in <= 0;
            addr_start <= 0; addr_end <= 0;
            Instruction_code_transpose <= 0;
            // num_iterations <= 0; // DIHAPUS
            row_id <= 0; tile_id <= 0; layer_id <= 0;
        end
        else begin
            // Default Low Pulse
            start_Mapper <= 0; start_weight <= 0; start_ifmap <= 0;
            start_transpose <= 0; done <= 0;

            case (next_state)
                START_ALL: begin
                    row_id       <= {1'd0, current_pass_row};  // 9-bit output
                    tile_id      <= current_absolute_tile_calc;
                    layer_id     <= current_layer_id;
                    ifmap_sel_in <= current_pass_row[3:0];

                    // --------------------------------------------------------
                    // IFMAP Address Decoding
                    // --------------------------------------------------------
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
                        // Layer 3: 256 rows, 16 segments (64 addresses each for 64 channels)
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

                    // --------------------------------------------------------
                    // Weight Address Decoding (Based on Tile ID)
                    // *** FIXED: Layer 3 uses 64 addresses per tile ***
                    // --------------------------------------------------------
                    if (current_layer_id == 2'd3) begin
                        // Layer 3: 64 addresses per tile (4 tiles)
                        case (current_pass_tile)
                            3'd0: begin addr_start <= 10'd0;   addr_end <= 10'd63;  end
                            3'd1: begin addr_start <= 10'd64;  addr_end <= 10'd127; end
                            3'd2: begin addr_start <= 10'd128; addr_end <= 10'd191; end
                            3'd3: begin addr_start <= 10'd192; addr_end <= 10'd255; end
                            default: begin addr_start <= 10'd0; addr_end <= 10'd63; end
                        endcase
                    end else if (current_layer_id == 2'd2) begin
                        // Layer 2: 128 addresses per tile (8 tiles)
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
                        // Layer 0/1: 256 addresses per tile (4 tiles)
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

                START_TRANS: begin
                    Instruction_code_transpose <= 8'h03;
                    // HAPUS ASSIGNMENT num_iterations DI SINI! (Sudah di-handle assign di atas)
                    start_transpose <= 1'b1;
                end

                DONE_STATE: begin
                    done <= 1'b1;
                end
            endcase
        end
    end

endmodule
