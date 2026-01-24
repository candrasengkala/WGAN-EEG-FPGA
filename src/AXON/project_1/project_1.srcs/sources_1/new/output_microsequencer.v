`timescale 1ns/1ps

// ============================================================
// Output Microsequencer
// FIXED: Added S_WAIT_DATA to handle BRAM Read Latency
// ============================================================
module output_microsequencer #(
    parameter integer DW        = 16,
    parameter integer Dimension = 16
)(
    input  wire clk,
    input  wire rst, // Active Low
    input  wire en,

    input  wire out_new_val_sign,

    input  wire output_counter_done_a,
    input  wire output_flag_1per16_a,
    input  wire output_counter_done_b,
    input  wire output_flag_1per16_b,

    output reg  en_output_counter_a,
    output reg  en_output_counter_b,

    output reg  [Dimension-1:0] ena_output_result_control,
    output reg  [Dimension-1:0] wea_output_result,
    output reg  [Dimension-1:0] enb_output_result_control,

    output reg  en_reg_adder,
    output reg  done
);
    // ========================================================
    // State Machine Definition
    // ========================================================
    localparam S_IDLE              = 4'd0;
    localparam S_WAIT_NEW_VAL      = 4'd1;
    localparam S_READ_PREV         = 4'd2; 
    localparam S_WAIT_DATA         = 4'd9; // [NEW] Wait state for BRAM latency
    localparam S_LATCH_PREV        = 4'd3;
    localparam S_WRITE_NEW         = 4'd4;
    localparam S_CHECK_DONE        = 4'd5;
    localparam S_DONE              = 4'd6;
    localparam S_WAIT_SETTLE       = 4'd7;
    localparam S_WAIT_SETTLE_2     = 4'd8;

    reg [3:0] state, next_state;
    reg [4:0] output_count;

    reg output_counter_done_a_pipeline;
    reg output_counter_done_b_pipeline;
    reg output_flag_1per16_a_pipeline;

    always @(posedge clk) begin
        output_flag_1per16_a_pipeline <= output_flag_1per16_a;
        output_counter_done_a_pipeline <= output_counter_done_a;
        output_counter_done_b_pipeline <= output_counter_done_b;
    end

    // ========================================================
    // State Machine - Sequential Logic (Active Low Reset)
    // ========================================================
    always @(posedge clk or negedge rst) begin
        if (!rst)
            state <= S_IDLE;
        else
            state <= next_state;
    end

    // ========================================================
    // State Machine - Combinational Logic
    // ========================================================
    always @(*) begin
        // Defaults
        next_state              = state;
        en_output_counter_a     = 1'b0;
        en_output_counter_b     = 1'b0;
        ena_output_result_control = {Dimension{1'b0}};
        wea_output_result       = {Dimension{1'b0}};
        enb_output_result_control = {Dimension{1'b0}};
        en_reg_adder            = 1'b0;
        done                    = 1'b0;

        case (state)
            S_IDLE: begin
                if (en)
                    next_state = S_WAIT_NEW_VAL;
            end

            S_WAIT_NEW_VAL: begin
                if (out_new_val_sign)
                    next_state = S_READ_PREV;
            end

            S_READ_PREV: begin
                // Initiate Read
                enb_output_result_control = {Dimension{1'b1}};
                // [FIX] Go to Wait State instead of Latch immediately
                next_state = S_WAIT_DATA; 
            end

            S_WAIT_DATA: begin
                // [FIX] Hold Enable high, allow data to settle on bus
                enb_output_result_control = {Dimension{1'b1}};
                next_state = S_LATCH_PREV;
            end

            S_LATCH_PREV: begin
                // Latch the now-valid BRAM data
                en_reg_adder = 1'b1;
                next_state = S_WRITE_NEW;
            end

            S_WRITE_NEW: begin
                // Write New + Old to BRAM
                ena_output_result_control = {Dimension{1'b1}};
                wea_output_result = {Dimension{1'b1}};
                next_state = S_WAIT_SETTLE_2;
            end

            S_WAIT_SETTLE_2: begin
                // Advance counters
                en_output_counter_a = 1'b1;
                en_output_counter_b = 1'b1; 
                next_state = S_CHECK_DONE;
            end

            S_CHECK_DONE: begin
                if (output_flag_1per16_a_pipeline || output_counter_done_a_pipeline) 
                    next_state = S_DONE;
                else
                    next_state = S_WAIT_NEW_VAL;
            end

            S_DONE: begin
                done = 1'b1;
                next_state = S_IDLE;
            end

            default: begin
                next_state = S_IDLE;
            end
        endcase
    end

    // ========================================================
    // Output Counter Logic
    // ========================================================
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            output_count <= 5'd0;
        end
        else begin
            case (state)
                S_IDLE: begin
                    if (en) output_count <= 5'd0;
                end
                S_WRITE_NEW: begin
                    output_count <= output_count + 1'b1;
                end
                default: begin end
            endcase
        end
    end

endmodule