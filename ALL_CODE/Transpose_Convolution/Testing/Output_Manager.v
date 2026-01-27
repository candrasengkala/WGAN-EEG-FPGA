`timescale 1ns / 1ps

/******************************************************************************
 * Module: output_stream_manager
 * 
 * Description:
 *   Autonomous AXI Stream Master yang mengirim hasil komputasi ke PS.
 *   Triggered oleh scheduler events (batch complete atau all complete).
 * 
 * Packet Types:
 *   1. NOTIFICATION (per batch complete):
 *      Header: [0xNOTF, batch_id, tile_start, tile_end]
 *      Payload: None (hanya notifikasi)
 *   
 *   2. FULL DATA (all batches complete):
 *      Header: [0xDATA, num_brams=16, addr_count]
 *      Payload: All 16 BRAMs data
 * 
 * Author: [Your Name]
 * Date: January 2026
 ******************************************************************************/

module output_stream_manager #(
    parameter DW = 16,
    parameter NUM_BRAMS = 16,
    parameter ADDR_WIDTH = 10,
    parameter OUTPUT_DEPTH = 512  // Output BRAM depth
)(
    input  wire clk,
    input  wire rst_n,
    
    // ========================================================================
    // Triggers from Scheduler/Batch Controller
    // ========================================================================
    input  wire       batch_complete,       // Pulse: 1 batch (4 tiles) done
    input  wire [2:0] completed_batch_id,   // Which batch just finished (0-7)
    input  wire       all_batches_complete, // Pulse: All 8 batches done
    
    // ========================================================================
    // Output BRAM Read Interface (to BRAM_Read_Modify_Top)
    // ========================================================================
    output reg                              ext_read_mode,
    output reg  [NUM_BRAMS*ADDR_WIDTH-1:0]  ext_read_addr_flat,
    input  wire [NUM_BRAMS*DW-1:0]          bram_read_data_flat,
    
    // ========================================================================
    // AXI Stream Master (to PS via DMA S2MM)
    // ========================================================================
    output reg  [DW-1:0] m_axis_tdata,
    output reg           m_axis_tvalid,
    input  wire          m_axis_tready,
    output reg           m_axis_tlast,
    
    // ========================================================================
    // Status/Debug
    // ========================================================================
    output wire [3:0]    state_debug,
    output wire          transmission_active
);

    // ========================================================================
    // FSM States
    // ========================================================================
    localparam [3:0]
        IDLE           = 4'd0,
        SEND_NOTIF_HDR = 4'd1,  // Send notification header
        WAIT_NOTIF_ACK = 4'd2,  // Wait for acknowledgment
        SEND_DATA_HDR  = 4'd3,  // Send full data header
        SEND_DATA_PAYLOAD = 4'd4,  // Send BRAM data
        WAIT_COMPLETE  = 4'd5;
    
    reg [3:0] state, next_state;
    
    // ========================================================================
    // Control Registers
    // ========================================================================
    reg [2:0]  header_word_cnt;      // Header word counter (0-3)
    reg [4:0]  current_bram_idx;     // Current BRAM being read (0-15)
    reg [ADDR_WIDTH-1:0] current_addr;  // Current address in BRAM
    reg [15:0] total_word_cnt;       // Total words sent counter
    
    reg [2:0]  latched_batch_id;     // Latched batch ID for notification
    
    // ========================================================================
    // Constants
    // ========================================================================
    localparam HEADER_WORDS = 4;
    localparam NOTIF_MAGIC  = 16'hC0DE;  // Notification magic (0xC0DE)
    localparam DATA_MAGIC   = 16'hDA7A;  // Data magic (0xDA7A)
    
    // ========================================================================
    // Status Outputs
    // ========================================================================
    assign state_debug = state;
    assign transmission_active = (state != IDLE);
    
    // ========================================================================
    // State Transition Logic
    // ========================================================================
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
                if (all_batches_complete)
                    next_state = SEND_DATA_HDR;
                else if (batch_complete)
                    next_state = SEND_NOTIF_HDR;
            end
            
            SEND_NOTIF_HDR: begin
                if (m_axis_tvalid && m_axis_tready && header_word_cnt == HEADER_WORDS-1)
                    next_state = WAIT_NOTIF_ACK;
            end
            
            WAIT_NOTIF_ACK: begin
                // Wait 1 cycle, then back to IDLE
                next_state = IDLE;
            end
            
            SEND_DATA_HDR: begin
                if (m_axis_tvalid && m_axis_tready && header_word_cnt == HEADER_WORDS-1)
                    next_state = SEND_DATA_PAYLOAD;
            end
            
            SEND_DATA_PAYLOAD: begin
                // Send all 16 BRAMs × OUTPUT_DEPTH words
                if (m_axis_tvalid && m_axis_tready && m_axis_tlast)
                    next_state = WAIT_COMPLETE;
            end
            
            WAIT_COMPLETE: begin
                next_state = IDLE;
            end
            
            default: next_state = IDLE;
        endcase
    end
    
    // ========================================================================
    // Control Logic
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            header_word_cnt <= 3'd0;
            current_bram_idx <= 5'd0;
            current_addr <= {ADDR_WIDTH{1'b0}};
            total_word_cnt <= 16'd0;
            latched_batch_id <= 3'd0;
            ext_read_mode <= 1'b0;
            ext_read_addr_flat <= {NUM_BRAMS*ADDR_WIDTH{1'b0}};
            m_axis_tdata <= 16'd0;
            m_axis_tvalid <= 1'b0;
            m_axis_tlast <= 1'b0;
        end else begin
            // Default: deassert control signals
            m_axis_tvalid <= 1'b0;
            m_axis_tlast <= 1'b0;
            
            case (state)
                IDLE: begin
                    ext_read_mode <= 1'b0;
                    header_word_cnt <= 3'd0;
                    current_bram_idx <= 5'd0;
                    current_addr <= {ADDR_WIDTH{1'b0}};
                    total_word_cnt <= 16'd0;
                    
                    // Latch batch ID when batch completes
                    if (batch_complete)
                        latched_batch_id <= completed_batch_id;
                end
                
                // ============================================================
                // NOTIFICATION HEADER
                // ============================================================
                SEND_NOTIF_HDR: begin
                    m_axis_tvalid <= 1'b1;
                    
                    case (header_word_cnt)
                        3'd0: m_axis_tdata <= NOTIF_MAGIC;          // Magic number
                        3'd1: m_axis_tdata <= {13'd0, latched_batch_id};  // Batch ID
                        3'd2: m_axis_tdata <= {10'd0, latched_batch_id, 3'd0};  // Tile start (batch*4)
                        3'd3: begin
                            m_axis_tdata <= {10'd0, latched_batch_id, 3'd3};  // Tile end (batch*4 + 3)
                            m_axis_tlast <= 1'b1;  // Last word of notification
                        end
                        default: m_axis_tdata <= 16'd0;
                    endcase
                    
                    if (m_axis_tready)
                        header_word_cnt <= header_word_cnt + 1;
                end
                
                // ============================================================
                // FULL DATA HEADER
                // ============================================================
                SEND_DATA_HDR: begin
                    m_axis_tvalid <= 1'b1;
                    
                    case (header_word_cnt)
                        3'd0: m_axis_tdata <= DATA_MAGIC;           // Magic number
                        3'd1: m_axis_tdata <= NUM_BRAMS;            // Number of BRAMs
                        3'd2: m_axis_tdata <= OUTPUT_DEPTH;         // Words per BRAM
                        3'd3: m_axis_tdata <= NUM_BRAMS * OUTPUT_DEPTH; // Total words
                        default: m_axis_tdata <= 16'd0;
                    endcase
                    
                    if (m_axis_tready) begin
                        header_word_cnt <= header_word_cnt + 1;
                        
                        // Prepare for data transmission
                        if (header_word_cnt == HEADER_WORDS-1) begin
                            ext_read_mode <= 1'b1;  // Enable external read
                            current_bram_idx <= 5'd0;
                            current_addr <= {ADDR_WIDTH{1'b0}};
                        end
                    end
                end
                
                // ============================================================
                // FULL DATA PAYLOAD
                // ============================================================
                SEND_DATA_PAYLOAD: begin
                    ext_read_mode <= 1'b1;
                    
                    // Set read address for current BRAM
                    ext_read_addr_flat <= {NUM_BRAMS{current_addr}};
                    
                    // Send data from current BRAM (with 1-cycle latency for BRAM read)
                    m_axis_tvalid <= 1'b1;
                    m_axis_tdata <= bram_read_data_flat[current_bram_idx*DW +: DW];
                    
                    // Check if this is the last word
                    if (current_bram_idx == NUM_BRAMS-1 && current_addr == OUTPUT_DEPTH-1)
                        m_axis_tlast <= 1'b1;
                    
                    if (m_axis_tready) begin
                        total_word_cnt <= total_word_cnt + 1;
                        
                        // Increment address
                        if (current_addr < OUTPUT_DEPTH-1) begin
                            current_addr <= current_addr + 1;
                        end else begin
                            current_addr <= {ADDR_WIDTH{1'b0}};
                            
                            // Move to next BRAM
                            if (current_bram_idx < NUM_BRAMS-1)
                                current_bram_idx <= current_bram_idx + 1;
                        end
                    end
                end
                
                WAIT_COMPLETE: begin
                    ext_read_mode <= 1'b0;
                end
                
            endcase
        end
    end

endmodule