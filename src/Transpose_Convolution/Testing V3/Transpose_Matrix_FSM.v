/******************************************************************************
 * Module      : Transpose_Matrix_FSM
 * Author      : Dharma Anargya Jowandy
 * Date        : January 2026
 *
 * Description :
 * Finite State Machine controller for transposed matrix computation.
 * Orchestrates systolic array operation including data loading, MAC execution,
 * and ordered output ejection for transposed convolution.
 *
 * Key Features :
 * - 5-state FSM: IDLE, CLEAR, LOAD, MAC, DONE
 * - Wavefront-based diagonal PE activation
 * - Programmable iteration count per computation
 * - Output enable aligned with PE completion
 * - Done counter tracking completed PEs (0..NUM_PE)
 *
 * Parameters :
 * - DW     : Data width (default: 16)
 * - NUM_PE : Number of processing elements (default: 16)
 *
 ******************************************************************************/


module Transpose_Matrix_FSM #(
    parameter DW     = 16,  // Data width
    parameter NUM_PE = 16   // Number of PEs
)(
    input wire                   clk,
    input wire                   rst_n,
    input wire                   start,
    input wire [7:0]             Instruction_code,
    input wire [8:0]             num_iterations,
    
    output reg [NUM_PE-1:0]      en_weight_load,
    output reg [NUM_PE-1:0]      en_ifmap_load,
    output reg [NUM_PE-1:0]      en_psum,
    output reg [NUM_PE-1:0]      clear_psum,
    output reg [NUM_PE-1:0]      en_output,
    output reg [NUM_PE-1:0]      ifmap_sel_ctrl,
    
    output reg [4:0]             done,      
    output reg [7:0]             iter_count
);
    
    // State encoding
    localparam [2:0]
        IDLE         = 3'd0,
        CLEAR        = 3'd1,
        LOAD         = 3'd2,
        MAC          = 3'd3,
        DONE         = 3'd4;
    
    // State registers
    reg [2:0] current_state, next_state;
    reg [8:0] phase_counter;
    reg [4:0] active_pe;
    reg [8:0] num_iter_latched;
    reg [4:0] done_reg; 
    integer i;

    // Sequential Logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= IDLE;
            phase_counter <= 9'd0;
            iter_count <= 8'd0;
            active_pe <= 5'd0;
            num_iter_latched <= 8'd0;
            done_reg <= 5'd0; 
        end else begin
            current_state <= next_state;
            
            if (current_state == IDLE && start && Instruction_code == 8'h03) begin
                phase_counter <= 9'd0;
                iter_count <= 8'd0;
                active_pe <= 5'd0;
                num_iter_latched <= num_iterations;
                done_reg <= 5'd0;
            end 
            else if (current_state == MAC) begin
                phase_counter <= phase_counter + 1;
                
                if (iter_count < num_iter_latched) 
                    iter_count <= iter_count + 1;
                
                if (active_pe < 15)
                    active_pe <= active_pe + 1;

                // Done counter: tracks which PE has completed
                // When phase == num_iter, en_output[0] active
                // Next cycle (LOAD), done points to PE 0
                if (phase_counter >= num_iter_latched) begin
                     done_reg <= phase_counter - num_iter_latched;
                end
            end
            else if (current_state == DONE) begin
                done_reg <= 5'd16;
            end
            // During LOAD: done_reg maintains previous value (for MUX hold)
        end
    end

    // Output done assignment
    always @(*) begin
        done = done_reg; 
    end

    // Combinational Logic
    always @(*) begin
        next_state = current_state;
        en_weight_load = {NUM_PE{1'b0}};
        en_ifmap_load = {NUM_PE{1'b0}};
        en_psum = {NUM_PE{1'b0}};
        clear_psum = {NUM_PE{1'b0}};
        en_output = {NUM_PE{1'b0}};
        ifmap_sel_ctrl = {NUM_PE{1'b0}};

        case (current_state)
            IDLE: begin
                if (start && Instruction_code == 8'h03) next_state = CLEAR;
            end
            
            CLEAR: begin
                clear_psum = {NUM_PE{1'b1}};
                next_state = LOAD;
            end
            
            LOAD: begin
                for (i = 0; i <= active_pe; i = i + 1) begin
                    if (phase_counter < (i + num_iter_latched)) begin
                        en_weight_load[i] = 1'b1;
                        en_ifmap_load[i] = 1'b1;
                    end
                end
                ifmap_sel_ctrl[0] = 1'b1;
                for (i = 1; i <= active_pe; i = i + 1) ifmap_sel_ctrl[i] = 1'b0;
                next_state = MAC;
            end
            
            MAC: begin
                for (i = 0; i <= active_pe; i = i + 1) begin
                    if (phase_counter < (i + num_iter_latched)) begin
                        en_psum[i] = 1'b1;
                    end
                end
                
                // Trigger Output
                for (i = 0; i < NUM_PE; i = i + 1) begin
                    if (phase_counter == (i + num_iter_latched)) begin
                        en_output[i] = 1'b1; 
                    end
                end
                
                if (phase_counter >= (15 + num_iter_latched + 1)) 
                    next_state = DONE;
                else 
                    next_state = LOAD;
            end
            
            DONE: next_state = IDLE;
            default: next_state = IDLE;
        endcase
    end

endmodule