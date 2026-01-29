`timescale 1ns / 1ps
// Packer 4 × 16-bit to 64-bit
// Collects four 16-bit words and packs them into one 64-bit word

module packed64bit (
    input wire         aclk,
    input wire         aresetn,
    
    // *** Input from MUX (16-bit) ***
    input wire [15:0]  data_in,        // 16-bit input data
    input wire         data_in_valid,  // Valid signal
    output reg         data_in_ready,  // Ready signal (output)
    
    // *** Output to S2MM FIFO (64-bit) ***
    output reg [63:0]  data_out,       // 64-bit output data
    output reg         data_out_valid, // Valid signal
    input wire         data_out_ready, // Ready signal dari FIFO
    
    // *** Status ***
    output wire [1:0]  word_index      // Current word index (0-3)
);

    // Internal registers
    reg [15:0] word_0_reg;  // Buffer untuk word 0 [15:0]
    reg [15:0] word_1_reg;  // Buffer untuk word 1 [31:16]
    reg [15:0] word_2_reg;  // Buffer untuk word 2 [47:32]
    reg [15:0] word_3_reg;  // Buffer untuk word 3 [63:48]
    
    reg [1:0]  count_reg;   // Counter 0-3 untuk 4 words
    reg [1:0]  state_reg;   // FSM state
    
    // State definitions
    localparam IDLE     = 2'd0;  // Siap terima word pertama
    localparam COLLECT  = 2'd1;  // Collect 4 words
    localparam OUTPUT   = 2'd2;  // Output 64-bit word
    localparam DONE     = 2'd3;  // Selesai, siap terima data baru
    
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
                        state_reg <= COLLECT;
                    end
                end
                
                COLLECT: begin
                    if (data_in_valid && data_in_ready) begin
                        if (count_reg == 2'd3) begin
                            state_reg <= OUTPUT;
                        end
                    end
                end
                
                OUTPUT: begin
                    if (data_out_valid && data_out_ready) begin
                        state_reg <= DONE;
                    end
                end
                
                DONE: begin
                    state_reg <= IDLE;
                end
                
                default: state_reg <= IDLE;
            endcase
    end
    
    // ============================================================================
    // Counter
    // ============================================================================
    // Count 0 → 1 → 2 → 3 untuk collect 4 words
    
    always @(posedge aclk) begin
        if (!aresetn) begin
            count_reg <= 2'd0;
        end
        else if (state_reg == IDLE || state_reg == DONE) begin
            count_reg <= 2'd0;  // Reset counter
        end
        else if ((state_reg == IDLE || state_reg == COLLECT) && data_in_valid && data_in_ready) begin
            count_reg <= count_reg + 1;  // Increment setiap terima word
        end
    end
    
    // ============================================================================
    // Data Collection
    // ============================================================================
    // Collect 4 × 16-bit words ke register buffer
    
    always @(posedge aclk) begin
        if (!aresetn) begin
            word_0_reg <= 16'b0;
            word_1_reg <= 16'b0;
            word_2_reg <= 16'b0;
            word_3_reg <= 16'b0;
        end
        else if (data_in_valid && data_in_ready) begin
            case (count_reg)
                2'd0: word_0_reg <= data_in;  // Collect word 0 [15:0]
                2'd1: word_1_reg <= data_in;  // Collect word 1 [31:16]
                2'd2: word_2_reg <= data_in;  // Collect word 2 [47:32]
                2'd3: word_3_reg <= data_in;  // Collect word 3 [63:48]
            endcase
        end
    end
    
    // ============================================================================
    // Output Logic
    // ============================================================================
    
    // data_out: Pack 4 × 16-bit jadi 1 × 64-bit
    always @(*) begin
        data_out = {word_3_reg, word_2_reg, word_1_reg, word_0_reg};
        // [63:48]      [47:32]      [31:16]      [15:0]
    end
    
    // data_out_valid: HIGH saat OUTPUT state
    always @(*) begin
        if (state_reg == OUTPUT)
            data_out_valid = 1'b1;
        else
            data_out_valid = 1'b0;
    end
    
    // data_in_ready: HIGH saat IDLE atau COLLECT state
    always @(*) begin
        if (state_reg == IDLE || state_reg == COLLECT)
            data_in_ready = 1'b1;
        else
            data_in_ready = 1'b0;
    end

endmodule
