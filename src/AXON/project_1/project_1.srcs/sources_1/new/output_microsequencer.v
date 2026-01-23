`timescale 1ns/1ps

// ============================================================
// Output Microsequencer
// Controls output BRAM access, adder register, and output counters
// Handles accumulation across input channels for same filter
// Responds to out_new_val signal from systolic array
// ============================================================
module output_microsequencer #(
    parameter integer DW        = 16,
    parameter integer Dimension = 16
)(
    input  wire clk,

    // --------------------------------------------------------
    // Control from main FSM
    // --------------------------------------------------------
    input  wire rst,
    input  wire en,

    // --------------------------------------------------------
    // Signal from datapath (systolic array)
    // --------------------------------------------------------
    input  wire out_new_val_sign,  // New output value ready from systolic array

    // --------------------------------------------------------
    // Status inputs from output counters
    // --------------------------------------------------------
    input  wire output_counter_done_a,
    input  wire output_flag_1per16_a,
    input  wire output_counter_done_b,
    input  wire output_flag_1per16_b,

    // --------------------------------------------------------
    // Counter enable outputs
    // --------------------------------------------------------
    output reg  en_output_counter_a,
    output reg  en_output_counter_b,

    // --------------------------------------------------------
    // Output BRAM control
    // --------------------------------------------------------
    output reg  [Dimension-1:0] ena_output_result_control,
    output reg  [Dimension-1:0] wea_output_result,
    output reg  [Dimension-1:0] enb_output_result_control,

    // --------------------------------------------------------
    // Datapath / adder-side control
    // --------------------------------------------------------
    output reg  en_reg_adder,
    // output reg  output_result_reg_rst,

    // --------------------------------------------------------
    // Status back to main FSM
    // --------------------------------------------------------
    output reg  done
);
    // ========================================================
    // State Machine Definition
    // ========================================================
    localparam S_IDLE              = 4'd0;   // Waiting for enable
    localparam S_WAIT_NEW_VAL      = 4'd1;   // Wait for out_new_val_sign
    localparam S_READ_PREV         = 4'd2;   // Read previous result from BRAM (for accumulation)
    localparam S_LATCH_PREV        = 4'd3;   // Latch previous result into adder register
    localparam S_WRITE_NEW         = 4'd4;   // Write new accumulated result to BRAM
    localparam S_CHECK_DONE        = 4'd5;   // Check if all outputs processed
    localparam S_DONE              = 4'd6;   // Signal completion
    localparam S_WAIT_SETTLE       = 4'd7;
    localparam S_WAIT_SETTLE_2     = 4'd8;

    reg [3:0] state, next_state;
    reg [4:0] output_count;  // Counter for tracking Dimension outputs

    reg output_counter_done_a_pipeline;
    reg output_counter_done_b_pipeline;
    reg output_flag_1per16_a_pipeline;
    always @(posedge clk) begin
        output_flag_1per16_a_pipeline <= output_flag_1per16_a;
    end
    always @(posedge clk) begin
        output_counter_done_a_pipeline <= output_counter_done_a;
    end
    always @(posedge clk) begin
        output_counter_done_b_pipeline <= output_counter_done_b;
    end

    // ========================================================
    // State Machine - Sequential Logic
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
        // Default values
        next_state              = state;
        en_output_counter_a     = 1'b0;
        en_output_counter_b     = 1'b0;
        ena_output_result_control = {Dimension{1'b0}};
        wea_output_result       = {Dimension{1'b0}};
        enb_output_result_control = {Dimension{1'b0}};
        en_reg_adder            = 1'b0;
        // output_result_reg_rst   = 1'b0;
        done                    = 1'b0;

        case (state)
            S_IDLE: begin
                if (en)
                    done = 1'b1;
                    next_state = S_WAIT_NEW_VAL;
            end
            S_WAIT_NEW_VAL: begin
                // Wait for systolic array to signal new output value ready
                if (out_new_val_sign)
                    next_state = S_READ_PREV;
            end
            S_READ_PREV: begin
                enb_output_result_control = {Dimension{1'b1}};
                next_state = S_LATCH_PREV;
            end
            S_LATCH_PREV: begin //Here, BRAM should've settled and its values are put into registers.
                // Latch previous result into adder register
                // This combines with new systolic output via systolic_out_adder                
                en_reg_adder = 1'b1; // OLD VAL Fetched.
                next_state = S_WRITE_NEW;
            end
            S_WRITE_NEW: begin
                // Write accumulated result back to BRAM using counter A (write port)
                ena_output_result_control = {Dimension{1'b1}};
                wea_output_result = {Dimension{1'b1}};
                next_state = S_WAIT_SETTLE_2;
            end
            S_WAIT_SETTLE_2: begin
                next_state = S_CHECK_DONE;                 
                en_output_counter_a = 1'b1;
                en_output_counter_b = 1'b1; //For next value is placed here. CLOCK IS VERY THIGHT.
            end
            S_CHECK_DONE: begin
                if (output_flag_1per16_a_pipeline || output_counter_done_a_pipeline) // STRICT TIMING REQUIREMENTS.
                    next_state = S_DONE;
                else
                    next_state = S_WAIT_NEW_VAL;  // Wait for next output value
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
    // Output Counter - Sequential Logic
    // ========================================================
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            output_count <= 5'd0;
        end
        else begin
            case (state)
                S_IDLE: begin
                    if (en)
                        output_count <= 5'd0;
                end

                S_WRITE_NEW: begin
                    // Increment after writing each output
                    output_count <= output_count + 1'b1;
                end

                default: begin
                    // Hold value
                end
            endcase
        end
    end

endmodule