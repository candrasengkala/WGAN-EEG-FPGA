`timescale 1ns / 1ps
// Parser 64-bit to 4 × 16-bit
// Converts one 64-bit word into four 16-bit words sequentially

module parser64bit (
    input wire         aclk,
    input wire         aresetn,
    
    // *** Input from FIFO (64-bit) ***
    input wire [63:0]  data_in,        // 64-bit input data
    input wire         data_in_valid,  // Valid signal dari FIFO
    output reg         data_in_ready,  // Ready signal ke FIFO
    
    // *** Output to DEMUX (16-bit) ***
    output reg [15:0]  data_out,       // 16-bit output data
    output reg         data_out_valid, // Valid signal
    input wire         data_out_ready, // Ready signal dari user logic
    
    // *** Status ***
    output wire [1:0]  word_index      // Current word index (0-3)
);

    // Internal registers
    reg [63:0] data_buffer;     // Buffer untuk simpan 64-bit word
    reg [1:0]  count_reg;       // Counter 0-3 untuk 4 words
    reg [1:0]  state_reg;       // FSM state
    
    // State definitions
    localparam IDLE     = 2'd0;  // Tunggu data dari FIFO
    localparam PARSE    = 2'd1;  // Output 4 × 16-bit sequential
    localparam DONE     = 2'd2;  // Selesai, siap terima data baru
    
    // Word index output
    assign word_index = count_reg;
    
    // ============================================================================
    // FSM - State Register
    // ============================================================================
    
    always @(posedge aclk) begin
        if (!aresetn)
            state_reg <= IDLE;
        else
            case (state_reg)
                IDLE: begin
                    if (data_in_valid && data_in_ready) begin
                        state_reg <= PARSE;
                    end
                end
                
                PARSE: begin
                    if (data_out_valid && data_out_ready) begin
                        if (count_reg == 2'd3) begin
                            state_reg <= DONE;
                        end
                    end
                end
                
                DONE: begin
                    state_reg <= IDLE;
                end
                
                default: state_reg <= IDLE;
            endcase
    end
    
    // ============================================================================
    // Data Buffer
    // ============================================================================
    // Simpan 64-bit word saat IDLE state
    
    always @(posedge aclk) begin
        if (!aresetn) begin
            data_buffer <= 64'b0;
        end
        else if (state_reg == IDLE && data_in_valid && data_in_ready) begin
            data_buffer <= data_in;  // Load 64-bit data
        end
    end
    
    // ============================================================================
    // Counter
    // ============================================================================
    // Count 0 → 1 → 2 → 3 untuk 4 words
    
    always @(posedge aclk) begin
        if (!aresetn) begin
            count_reg <= 2'd0;
        end
        else if (state_reg == IDLE) begin
            count_reg <= 2'd0;  // Reset counter
        end
        else if (state_reg == PARSE && data_out_valid && data_out_ready) begin
            count_reg <= count_reg + 1;  // Increment setiap transfer
        end
    end
    
    // ============================================================================
    // Output Logic
    // ============================================================================
    
    // data_out: Select 16-bit berdasarkan count_reg
    always @(*) begin
        case (count_reg)
            2'd0: data_out = data_buffer[15:0];   // Lower 16-bit
            2'd1: data_out = data_buffer[31:16];  // 
            2'd2: data_out = data_buffer[47:32];  // 
            2'd3: data_out = data_buffer[63:48];  // Upper 16-bit
            default: data_out = 16'b0;
        endcase
    end
    
    // data_out_valid: HIGH saat PARSE state
    always @(*) begin
        if (state_reg == PARSE)
            data_out_valid = 1'b1;
        else
            data_out_valid = 1'b0;
    end
    
    // data_in_ready: HIGH saat IDLE state dan siap terima data
    always @(*) begin
        if (state_reg == IDLE)
            data_in_ready = 1'b1;
        else
            data_in_ready = 1'b0;
    end

endmodule
