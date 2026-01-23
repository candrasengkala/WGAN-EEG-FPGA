`timescale 1ns/1ps

// ============================================================
// Filter Microsequencer
// Controls feeding filter weights to systolic array via shift registers
// Supports arbitrary kernel sizes (1-16)
// Done stays HIGH until restart is asserted
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
    localparam S_IDLE           = 3'd0;
    localparam S_INIT           = 3'd1;
    localparam S_SHIFT_WEIGHTS  = 3'd2;
    localparam S_ZERO_PAD_1     = 3'd3;
    localparam S_ZERO_PAD_2     = 3'd4;
    localparam S_DONE           = 3'd5;    
    localparam S_LOAD_LAST_VAL           = 3'd6;
    localparam S_FILL_ZERO  = 3'd7;

    reg [2:0] state, next_state;

    // --------------------------------------------------------
    // Internal counter
    // --------------------------------------------------------
    reg [4:0] shift_count;          // Count shifts (0 to kernel_size-1)

    // --------------------------------------------------------
    // Helper signals
    // --------------------------------------------------------
    wire all_brams_active;
    
    // Shift until counter says stop.

    // Generate mask for active BRAMs based on kernel_size
    // If kernel_size=7, enable BRAMs 0-6 (7 BRAMs)
    // If kernel_size=16, enable all 16 BRAMs
    assign all_brams_active = (kernel_size >= Dimension);

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
                if (en)
                    next_state = S_INIT;
                // Note: restart is handled in S_DONE, not here
            end
            
            S_INIT: begin
                next_state = S_SHIFT_WEIGHTS;
            end
            
            S_SHIFT_WEIGHTS: begin
                if (weight_counter_done)
                    next_state = S_LOAD_LAST_VAL;
            end
            S_LOAD_LAST_VAL: begin
                next_state = S_FILL_ZERO;
            end
            
            S_ZERO_PAD_1: begin
                next_state = S_ZERO_PAD_2;
            end
            
            S_ZERO_PAD_2: begin
                next_state = S_FILL_ZERO;
            end
            S_FILL_ZERO: begin
                if (fill_zero_count >= $signed(Dimension - kernel_size - 1)) next_state = S_DONE;
            end
            
            S_DONE: begin
                // Stay in DONE until restart is asserted
                if (restart)
                    next_state = S_INIT;  // Go directly to INIT on restart
                // Otherwise stay in S_DONE
            end
            
            default: begin
                next_state = S_IDLE;
            end
        endcase
    end

    // --------------------------------------------------------
    // BRAM Enable Mask Generation
    // --------------------------------------------------------
    reg [Dimension-1:0] bram_enable_mask;
    integer i;
    
    always @(*) begin
        for (i = 0; i < Dimension; i = i + 1) begin
            if (i < kernel_size)
                bram_enable_mask[i] = 1'b1;
            else
                bram_enable_mask[i] = 1'b0;
        end
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
            
            S_INIT: begin
                // Enable all shift registers at once (like i==0 in testbench)
                en_shift_reg_weight_input_ctrl = {Dimension{1'b1}};
                // Enable only the BRAMs needed for this kernel_size
                enb_weight_input_bram = bram_enable_mask;
                en_weight_counter = 1'b1; //Must be done since INIT. Ini karena clocknya agak telat.
            end
            
            S_SHIFT_WEIGHTS: begin
                // Keep all shift registers enabled for uniform shifting
                en_shift_reg_weight_input_ctrl = {Dimension{1'b1}};
                // Keep only necessary BRAMs enabled for reading
                enb_weight_input_bram = bram_enable_mask;
                // Enable counter to advance through weight memory
                en_weight_counter = 1'b1;
            end
            S_LOAD_LAST_VAL: begin
                en_shift_reg_weight_input_ctrl = {Dimension{1'b1}};
            end
            S_ZERO_PAD_1: begin
                // Keep shift registers enabled for zero padding
                // This shifts in zeros for positions beyond kernel_size
                zero_or_data_weight = 1'b0;
                en_shift_reg_weight_input_ctrl = {Dimension{1'b1}};
                // Disable BRAMs (external logic sets weight_brams_in = 0)
                enb_weight_input_bram = {Dimension{1'b0}};
            end
            S_ZERO_PAD_2: begin
                // Disable shift registers (final padding cycle)
                zero_or_data_weight = 1'b0;
                en_shift_reg_weight_input_ctrl = {Dimension{1'b0}};
                enb_weight_input_bram = {Dimension{1'b0}};
            end
            S_FILL_ZERO: begin
                zero_or_data_weight = 1'b0;
                en_shift_reg_weight_input_ctrl = {Dimension{1'b1}};
            end
            S_DONE: begin
                done = 1'b1;  // Stay HIGH until restart
                zero_or_data_weight <= 1'b0;
            end
            
            default: begin
                // Safe defaults already set
            end
        endcase
    end

    // --------------------------------------------------------
    // Sequential counter updates
    // --------------------------------------------------------
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            shift_count <= 5'd0;
        end
        else begin
            case (state)
                S_IDLE: begin
                    if (en) begin
                        shift_count <= 5'd0;
                    end
                    fill_zero_count <= 0;
                end
                
                S_INIT: begin
                    // Reset counter when starting/restarting
                    shift_count <= 5'd0;
                end
                S_LOAD_LAST_VAL: begin
                    
                end
                S_SHIFT_WEIGHTS: begin
                end
                
                S_ZERO_PAD_1, S_ZERO_PAD_2: begin
                    // Hold counter during padding
                end
                S_FILL_ZERO: begin
                    fill_zero_count <= fill_zero_count + 1;
                end
                S_DONE: begin
                    // Hold counter in done state
                    // Will reset when restart takes us back to INIT
                end
                
                default: begin
                    // Keep current values
                end
            endcase
        end
    end

endmodule