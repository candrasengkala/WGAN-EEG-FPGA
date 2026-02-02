`timescale 1ns / 1ps

/******************************************************************************
 * Module      : Transpose_Matrix_FSM ifx
 * Author      : Dharma Anargya Jowandy
 * Date        : January 2026
 * Modified    : January 31, 2026 - FINAL PIPELINED FIX
 *
 * Description :
 * Finite State Machine controller for transposed matrix computation.
 * * CRITICAL FIX:
 * - Changed from Stop-and-Go (Load->MAC->Load) to Fully Pipelined (MAC->MAC).
 * - Now processes 1 data per clock cycle to match BRAM throughput.
 * - Eliminates "Gap" and "Ghost Data" accumulation issues.
 *
 * Parameters :
 * - DW     : Data width (default: 16)
 * - NUM_PE : Number of processing elements (default: 16)
 *
 ******************************************************************************/

module Transpose_Matrix_FSM #(
    parameter DW     = 16,
    parameter NUM_PE = 16
)(
    input wire                   clk,
    input wire                   rst_n,
    input wire                   start,
    input wire [7:0]             Instruction_code,
    input wire [8:0]             num_iterations, // Input ini sekarang akan dipatuhi

    output reg [NUM_PE-1:0]      en_weight_load,
    output reg [NUM_PE-1:0]      en_ifmap_load,
    output reg [NUM_PE-1:0]      en_psum,
    output reg [NUM_PE-1:0]      clear_psum,
    output reg [NUM_PE-1:0]      en_output,
    output reg [NUM_PE-1:0]      ifmap_sel_ctrl,

    output reg [4:0]             done,
    output reg [7:0]             iter_count
);

    localparam [2:0] IDLE=0, LOAD=2, MAC=3, DONE=4;
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

            // LATCH NUM_ITERATIONS SAAT START
            if (current_state == IDLE && start && Instruction_code == 8'h03) begin
                phase_counter <= 9'd0;
                iter_count <= 8'd0;
                active_pe <= 5'd0;

                // KEMBALI KE INPUT SCHEDULER (Bukan Hardcode)
                num_iter_latched <= num_iterations;

                done_reg <= 5'd0;
            end
            else if (current_state == MAC) begin
                phase_counter <= phase_counter + 1;

                if (iter_count < num_iter_latched)
                    iter_count <= iter_count + 1;

                if (active_pe < 15)
                    active_pe <= active_pe + 1;

                if (phase_counter >= num_iter_latched) begin
                     done_reg <= phase_counter - num_iter_latched;
                end
            end
            else if (current_state == DONE) begin
                done_reg <= 5'd16;
            end
        end
    end

    always @(*) done = done_reg;

    // Combinational Logic
    always @(*) begin
        next_state = current_state;
        en_weight_load = 0; en_ifmap_load = 0; en_psum = 0;
        clear_psum = 0; en_output = 0; ifmap_sel_ctrl = 0;

        case (current_state)
            IDLE: begin
                if (start && Instruction_code == 8'h03) begin
                    clear_psum = {NUM_PE{1'b1}};
                    next_state = LOAD;
                end
            end

            LOAD: begin
                for (i = 0; i <= active_pe; i = i + 1) begin
                    if (phase_counter < (i + num_iter_latched)) begin
                        en_weight_load[i] = 1'b1;
                        en_ifmap_load[i] = 1'b1;
                    end
                end
                ifmap_sel_ctrl = 16'b0000_0000_0000_0001;
                next_state = MAC;
            end

            MAC: begin
                // PIPELINE MODE (1 CLOCK = 1 DATA)
                for (i = 0; i < NUM_PE; i = i + 1) begin
                    if (phase_counter < (i + num_iter_latched)) begin
                        en_weight_load[i] = 1'b1;
                        en_ifmap_load[i]  = 1'b1;
                    end
                end

                for (i = 0; i <= active_pe; i = i + 1) begin
                    if (phase_counter < (i + num_iter_latched)) begin
                        en_psum[i] = 1'b1;
                    end
                end

                ifmap_sel_ctrl = 16'b0000_0000_0000_0001;

                for (i = 0; i < NUM_PE; i = i + 1) begin
                    if (phase_counter == (i + num_iter_latched)) begin
                        en_output[i] = 1'b1;
                    end
                end

                if (phase_counter >= (15 + num_iter_latched + 1))
                    next_state = DONE;
                else
                    next_state = MAC;
            end

            DONE: next_state = IDLE;
            default: next_state = IDLE;
        endcase
    end
endmodule
