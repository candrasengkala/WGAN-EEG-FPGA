`timescale 1ns / 1ps

/******************************************************************************
 * Module: Output_Manager_Simple
 * 
 * Mengirim output ke PS dengan format:
 *   NOTIFICATION: [Header 6 words] + [BRAM 0 data 512 words] = 518 words
 *   FULL DATA:    [Header 6 words] + [All BRAM 8192 words] = 8198 words
 * 
 * Header format:
 *   [0] = magic (0xC0DE=notification, 0xDA7A=full data)
 *   [1] = packet type (0x0001=notification, 0x0002=full data)
 *   [2] = batch_id/layer_id
 *   [3] = tile_start (notification only)
 *   [4] = tile_end (notification only)
 *   [5] = data word count (512 or 8192)
 ******************************************************************************/

module Output_Manager_Simple #(
    parameter DW = 16
)(
    input  wire clk,
    input  wire rst_n,
    
    // Triggers from Scheduler
    input  wire       batch_complete,      // Pulse per batch complete
    input  wire [2:0] current_batch_id,    // 0-7
    input  wire       all_batches_done,    // Pulse when layer complete
    input  wire [1:0] completed_layer_id,  // 0-3
    
    // Header output ke wrapper
    output reg [15:0] header_word_0,
    output reg [15:0] header_word_1,
    output reg [15:0] header_word_2,
    output reg [15:0] header_word_3,
    output reg [15:0] header_word_4,
    output reg [15:0] header_word_5,
    output reg        send_header,
    
    // Control ke parser (untuk trigger READ instruction)
    output reg        trigger_read,
    output reg [2:0]  rd_bram_start,
    output reg [2:0]  rd_bram_end,
    output reg [15:0] rd_addr_count,
    
    // Status
    input  wire       read_done,
    output reg        transmission_active
);

    // FSM States
    localparam IDLE               = 3'd0;
    localparam SEND_NOTIFICATION  = 3'd1;
    localparam WAIT_NOTIF_DONE    = 3'd2;
    localparam SEND_FULL_DATA     = 3'd3;
    localparam WAIT_DATA_DONE     = 3'd4;
    
    reg [2:0] state, next_state;
    reg [2:0] latched_batch_id;
    reg [1:0] latched_layer_id;
    
    // FSM
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= IDLE;
        else
            state <= next_state;
    end
    
    always @(*) begin
        next_state = state;
        case (state)
            IDLE: begin
                if (batch_complete)
                    next_state = SEND_NOTIFICATION;
                else if (all_batches_done)
                    next_state = SEND_FULL_DATA;
            end
            
            SEND_NOTIFICATION: begin
                next_state = WAIT_NOTIF_DONE;
            end
            
            WAIT_NOTIF_DONE: begin
                if (read_done)
                    next_state = IDLE;
            end
            
            SEND_FULL_DATA: begin
                next_state = WAIT_DATA_DONE;
            end
            
            WAIT_DATA_DONE: begin
                if (read_done)
                    next_state = IDLE;
            end
            
            default: next_state = IDLE;
        endcase
    end
    
    // Output logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            header_word_0 <= 16'd0;
            header_word_1 <= 16'd0;
            header_word_2 <= 16'd0;
            header_word_3 <= 16'd0;
            header_word_4 <= 16'd0;
            header_word_5 <= 16'd0;
            send_header <= 1'b0;
            trigger_read <= 1'b0;
            rd_bram_start <= 3'd0;
            rd_bram_end <= 3'd0;
            rd_addr_count <= 16'd0;
            transmission_active <= 1'b0;
            latched_batch_id <= 3'd0;
            latched_layer_id <= 2'd0;
            
        end else begin
            // Default
            send_header <= 1'b0;
            trigger_read <= 1'b0;
            
            case (state)
                IDLE: begin
                    transmission_active <= 1'b0;
                    
                    // Latch batch/layer ID
                    if (batch_complete) begin
                        latched_batch_id <= current_batch_id;
                        $display("[%0t] [OUT_MGR] Batch %0d complete signal received", 
                                 $time, current_batch_id);
                    end
                    if (all_batches_done) begin
                        latched_layer_id <= completed_layer_id;
                        $display("[%0t] [OUT_MGR] All batches done, Layer %0d complete", 
                                 $time, completed_layer_id);
                    end
                end
                
                SEND_NOTIFICATION: begin
                    transmission_active <= 1'b1;
                    
                    // Build NOTIFICATION header
                    header_word_0 <= 16'hC0DE;              // Magic: notification
                    header_word_1 <= 16'h0001;              // Type: notification
                    header_word_2 <= {13'd0, latched_batch_id};  // Batch ID
                    header_word_3 <= {10'd0, latched_batch_id, 2'd0};  // tile_start = batch*4
                    header_word_4 <= {10'd0, latched_batch_id, 2'd0} + 16'd3;  // tile_end = batch*4+3
                    header_word_5 <= 16'd512;               // Data count: 1 BRAM
                    
                    // Configure READ: 1 BRAM only (BRAM 0 as sample)
                    rd_bram_start <= 3'd0;
                    rd_bram_end <= 3'd0;
                    rd_addr_count <= 16'd512;
                    
                    // Trigger
                    send_header <= 1'b1;
                    trigger_read <= 1'b1;
                    
                    $display("[%0t] [OUT_MGR] Sending NOTIFICATION: Batch %0d (Tiles %0d-%0d) + 512 words", 
                             $time, latched_batch_id, 
                             latched_batch_id * 4, latched_batch_id * 4 + 3);
                end
                
                WAIT_NOTIF_DONE: begin
                    transmission_active <= 1'b1;
                    // Wait for read_done
                end
                
                SEND_FULL_DATA: begin
                    transmission_active <= 1'b1;
                    
                    // Build FULL DATA header
                    header_word_0 <= 16'hDA7A;              // Magic: full data
                    header_word_1 <= 16'h0002;              // Type: full data
                    header_word_2 <= {14'd0, latched_layer_id};  // Layer ID
                    header_word_3 <= 16'd0;                 // Reserved
                    header_word_4 <= 16'd0;                 // Reserved
                    header_word_5 <= 16'd4096;              // Data count: 8 BRAM (per group)
                    
                    // Configure READ: All 8 BRAMs (group 0: BRAM 0-7)
                    rd_bram_start <= 3'd0;
                    rd_bram_end <= 3'd7;
                    rd_addr_count <= 16'd512;  // Per BRAM
                    
                    // Trigger
                    send_header <= 1'b1;
                    trigger_read <= 1'b1;
                    
                    $display("[%0t] [OUT_MGR] Sending FULL DATA: Layer %0d + 4096 words (8 BRAMs)", 
                             $time, latched_layer_id);
                end
                
                WAIT_DATA_DONE: begin
                    transmission_active <= 1'b1;
                    // Wait for read_done
                end
            endcase
        end
    end

endmodule