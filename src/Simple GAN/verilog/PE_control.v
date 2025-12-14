// PE Control Unit - Simplified for 3x3 GAN Systolic Array
// Supports: Normal mode and Split mode only

module CMSA_controller #(
    parameter ARRAY_SIZE = 16,
    parameter K_SIZE = 3
)(
    input wire clk,
    input wire reset,
    
    // Configuration
    input wire operation_mode,          // 0 = Normal, 1 = Split
    input wire [3:0] pe_row,
    input wire [3:0] pe_col,
    input wire start_computation,
    
    // Layer parameters (simplified)
    input wire [7:0] ofmap_size,
    input wire [7:0] num_channels,
    input wire [2:0] kernel_size,
    
    // Output control signals to PE
    output reg en_reg_mul,
    output reg en_reg_left_A,
    output reg en_reg_left_B,
    output reg en_reg_op_out,
    output reg ctrl_delay_unit,
    output reg ctrl_mux_reg,
    output reg ctrl_mux_mux_reg,
    output reg [1:0] ctrl_mux31_mux_21,
    output reg ctrl_mux_add,
    output reg ctrl_dmux,
    output reg ctrl_partial_mux
);

    // State machine
    localparam IDLE = 2'b00;
    localparam LOAD_WEIGHTS = 2'b01;
    localparam COMPUTE = 2'b10;
    localparam DRAIN = 2'b11;
    
    reg [1:0] current_state, next_state;
    reg [15:0] cycle_counter;
    
    // Split mode detection
    wire is_top_half;
    wire is_bottom_half;
    
    assign is_top_half = (pe_row < ARRAY_SIZE/2);
    assign is_bottom_half = (pe_row >= ARRAY_SIZE/2);

    // ========================================
    // Control Logic Generation
    // ========================================
    
    always @(*) begin
        // Default values
        en_reg_mul = 1'b0;
        en_reg_left_A = 1'b0;
        en_reg_left_B = 1'b0;
        en_reg_op_out = 1'b0;
        ctrl_delay_unit = 1'b0;
        ctrl_mux_reg = 1'b0;
        ctrl_mux_mux_reg = 1'b0;
        ctrl_mux31_mux_21 = 2'b00;
        ctrl_mux_add = 1'b0;
        ctrl_dmux = 1'b0;
        ctrl_partial_mux = 1'b0;
        
        if (operation_mode == 1'b0) begin
            // ============================================
            // Normal Mode
            // ============================================
            case (current_state)
                LOAD_WEIGHTS: begin
                    en_reg_mul = 1'b1;           // Load weight from top
                    ctrl_mux_reg = 1'b0;         // Select from_up
                    ctrl_mux_mux_reg = 1'b0;     // Pass registered weight down
                end
                
                COMPUTE: begin
                    // Enable registers based on PE column position for timing alignment
                    // Column 0: no delay, Column 1: 1-stage, Column 2+: 2-stage
                    if (pe_col >= 2) begin
                        en_reg_left_A = 1'b1;    // Enable both for 2-stage delay
                        en_reg_left_B = 1'b1;
                    end else if (pe_col == 1) begin
                        en_reg_left_A = 1'b0;    // Only B for 1-stage delay
                        en_reg_left_B = 1'b1;
                    end else begin
                        en_reg_left_A = 1'b0;    // No delay for column 0
                        en_reg_left_B = 1'b0;
                    end
                    
                    en_reg_op_out = 1'b1;        // Enable MAC output register
                    ctrl_delay_unit = 1'b1;      // Enable delay unit
                    
                    ctrl_mux31_mux_21 = 2'b00;   // Partial sum from left
                    ctrl_mux_add = 1'b0;         // Use external partial sum
                    ctrl_dmux = 1'b0;            // Output to final output
                    ctrl_partial_mux = 1'b0;     // Pass reg_op_out
                end
                
                DRAIN: begin
                    en_reg_op_out = 1'b1;
                    ctrl_partial_mux = 1'b0;
                end
            endcase
            
        end else begin
            // ============================================
            // Split Mode
            // ============================================
            case (current_state)
                LOAD_WEIGHTS: begin
                    en_reg_mul = 1'b1;
                    
                    // Top half gets weights from top
                    // Bottom half gets weights from bottom
                    if (is_top_half) begin
                        ctrl_mux_reg = 1'b0;      // from_up
                        ctrl_mux_mux_reg = 1'b0;  // pass down
                    end else begin
                        ctrl_mux_reg = 1'b1;      // from_down
                        ctrl_mux_mux_reg = 1'b0;  // pass up
                    end
                end
                
                COMPUTE: begin
                    // Enable registers based on PE column position for timing alignment
                    if (pe_col >= 2) begin
                        en_reg_left_A = 1'b1;
                        en_reg_left_B = 1'b1;
                    end else if (pe_col == 1) begin
                        en_reg_left_A = 1'b0;
                        en_reg_left_B = 1'b1;
                    end else begin
                        en_reg_left_A = 1'b0;
                        en_reg_left_B = 1'b0;
                    end
                    
                    en_reg_op_out = 1'b1;
                    ctrl_delay_unit = 1'b1;      // Enable delay unit
                    
                    // Same ifmap data for both halves
                    ctrl_mux31_mux_21 = 2'b00;   // Partial sum from left
                    ctrl_mux_add = 1'b0;
                    ctrl_dmux = 1'b0;
                    ctrl_partial_mux = 1'b0;
                end
                
                DRAIN: begin
                    en_reg_op_out = 1'b1;
                    ctrl_partial_mux = 1'b0;
                end
            endcase
        end
    end
    
    // ========================================
    // State Machine
    // ========================================
    
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            current_state <= IDLE;
            cycle_counter <= 0;
        end else begin
            current_state <= next_state;
            
            if (current_state == COMPUTE) begin
                cycle_counter <= cycle_counter + 1;
            end else if (current_state == IDLE) begin
                cycle_counter <= 0;
            end
        end
    end
    
    always @(*) begin
        next_state = current_state;
        
        case (current_state)
            IDLE: begin
                if (start_computation)
                    next_state = LOAD_WEIGHTS;
            end
            
            LOAD_WEIGHTS: begin
                // Weight loading cycles
                if (cycle_counter >= ARRAY_SIZE - 1)
                    next_state = COMPUTE;
            end
            
            COMPUTE: begin
                // Computation cycles = K^2 * C
                if (cycle_counter >= (kernel_size * kernel_size * num_channels))
                    next_state = DRAIN;
            end
            
            DRAIN: begin
                if (cycle_counter >= ARRAY_SIZE)
                    next_state = IDLE;
            end
            
            default: next_state = IDLE;
        endcase
    end

endmodule