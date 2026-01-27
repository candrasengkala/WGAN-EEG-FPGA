`timescale 1ns/1ps

// ============================================================
// Filter Microsequencer - CORRECTED
// Fix: Enabled shift register during S_LOAD_LAST_VAL to capture
//      the final weight value from BRAM latency.
// ============================================================
module filter_microsequencer #(
    parameter DW = 16,
    parameter Dimension = 16
)(
    input  wire clk,
    input  wire rst,                    // active-low reset
    input  wire en,                     // enable microsequencer
    input  wire restart,                // restart feeding (reload same filter)
    
    // Convolution parameters
    input  wire [4:0] kernel_size,      // 1 to 16
    
    // Counter status inputs
    input  wire weight_counter_done,
    input  wire weight_flag_1per16,
    
    // Control outputs
    output reg  en_weight_counter,
    output reg  [Dimension-1:0] enb_weight_input_bram,
    output reg  [Dimension-1:0] en_shift_reg_weight_input_ctrl,
    output reg zero_or_data_weight,
    output reg  done
);

    // --------------------------------------------------------
    // State encoding
    // --------------------------------------------------------
    localparam S_IDLE           = 4'd0;
    localparam S_INIT           = 4'd1;
    localparam S_SHIFT_WEIGHTS  = 4'd2;
    localparam S_ZERO_PAD_1     = 4'd3;
    localparam S_ZERO_PAD_2     = 4'd4;
    localparam S_DONE           = 4'd5;    
    localparam S_LOAD_LAST_VAL  = 4'd6;
    localparam S_FILL_ZERO      = 4'd7;
    localparam S_PRE_INIT       = 4'd8;
    localparam S_CONSUME_LAST_VAL   = 4'd9;

    reg [3:0] state, next_state;

    // --------------------------------------------------------
    // Helper signals
    // --------------------------------------------------------
    wire all_brams_active;
    assign all_brams_active = (kernel_size >= Dimension);

    // --------------------------------------------------------
    // BRAM Enable Mask Generation
    // --------------------------------------------------------
    wire [Dimension-1:0] bram_enable_mask;
    // integer i;
    
    // always @(*) begin
    //     for (i = 0; i < Dimension; i = i + 1) begin
    //         if (i < kernel_size)
    //             bram_enable_mask[i] = 1'b1;
    //         else
    //             bram_enable_mask[i] = 1'b0;
    //     end
    // end
    assign bram_enable_mask = {Dimension{1'b1}};
    // --------------------------------------------------------
    // State register
    // --------------------------------------------------------
    always @(posedge clk or negedge rst) begin
        if (!rst)
            state <= S_IDLE;
        else
            state <= next_state;
    end
    
    reg signed [Dimension-1 : 0] fill_zero_count = 0;

    // --------------------------------------------------------
    // Next-state logic
    // --------------------------------------------------------
    always @(*) begin
        next_state = state;
        
        case (state)
            S_IDLE: begin
                if (en) next_state = S_PRE_INIT;
            end
            S_PRE_INIT: begin
                next_state = S_INIT;
            end
            S_INIT: begin
                next_state = S_SHIFT_WEIGHTS;
            end
            S_SHIFT_WEIGHTS: begin
                if (weight_counter_done)
                    next_state = S_LOAD_LAST_VAL;
            end
            S_LOAD_LAST_VAL: begin
                next_state = S_CONSUME_LAST_VAL;
            end
            S_CONSUME_LAST_VAL: begin
                next_state = S_ZERO_PAD_1;
            end
            
            S_ZERO_PAD_1: begin
                next_state = S_FILL_ZERO;
            end
            
            S_ZERO_PAD_2: begin
                next_state = S_FILL_ZERO;
            end
            S_FILL_ZERO: begin
                if (fill_zero_count >= $signed(Dimension - kernel_size - 2)) next_state = S_DONE;
            end
            
            S_DONE: begin
                if (restart)
                    next_state = S_PRE_INIT;
            end
            
            default: begin
                next_state = S_IDLE;
            end
        endcase
    end

    // --------------------------------------------------------
    // Output logic
    // --------------------------------------------------------
    always @(*) begin
        // Default values
        en_weight_counter = 1'b0;
        enb_weight_input_bram = {Dimension{1'b0}};
        en_shift_reg_weight_input_ctrl = {Dimension{1'b0}};
        done = 1'b0;
        zero_or_data_weight = 1'b1;
        
        case (state)
            S_IDLE: begin
                // All outputs at default
            end
            S_PRE_INIT: begin
                enb_weight_input_bram = {Dimension{1'b1}};
                en_weight_counter = 1'b1; 
            end
            S_INIT: begin
                en_shift_reg_weight_input_ctrl = {Dimension{1'b1}};
                enb_weight_input_bram = {Dimension{1'b1}};
                en_weight_counter = 1'b1; 
            end
            
            S_SHIFT_WEIGHTS: begin
                en_shift_reg_weight_input_ctrl = {Dimension{1'b1}};
                enb_weight_input_bram = {Dimension{1'b1}};
                en_weight_counter = 1'b1;
            end
            
            S_LOAD_LAST_VAL: begin
                // [FIX] Enable shift register here to capture the last data!
            //    en_shift_reg_weight_input_ctrl = {Dimension{1'b1}};
                enb_weight_input_bram = {Dimension{1'b1}}; // Keep enabled if latency requires
            end
            
            S_CONSUME_LAST_VAL: begin
                en_shift_reg_weight_input_ctrl = {Dimension{1'b1}};                
            end
            S_ZERO_PAD_1: begin
                zero_or_data_weight = 1'b0;
                en_shift_reg_weight_input_ctrl = {Dimension{1'b1}};
                enb_weight_input_bram = {Dimension{1'b0}};
            end
            S_ZERO_PAD_2: begin
                zero_or_data_weight = 1'b0;
                en_shift_reg_weight_input_ctrl = {Dimension{1'b0}};
                enb_weight_input_bram = {Dimension{1'b0}};
            end
            S_FILL_ZERO: begin
                zero_or_data_weight = 1'b0;
                en_shift_reg_weight_input_ctrl = {Dimension{1'b1}};
            end
            S_DONE: begin
                done = 1'b1;
                zero_or_data_weight <= 1'b0;
            end
            
            default: begin
                // Safe defaults
            end
        endcase
    end

    // --------------------------------------------------------
    // Sequential counter updates
    // --------------------------------------------------------
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            // Reset logic
            fill_zero_count <= 0;
        end
        else begin
            case (state)
                S_IDLE: begin
                    fill_zero_count <= 0;
                end
                S_FILL_ZERO: begin
                    fill_zero_count <= fill_zero_count + 1;
                end
                S_DONE: begin
                    fill_zero_count <= 0;
                end
                default: begin
                    // Keep current values
                end
            endcase
        end
    end

endmodule