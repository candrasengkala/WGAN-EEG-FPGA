// CMSA PE Top Module
// Processing Element for Systolic Array with weight-stationary dataflow

`include "operator.v"
`include "mux_21.v"
`include "mux_31.v"
`include "register.v"
`include "delay_module.v"
`include "dmux_12.v"
`include "PE_control.v"

module PE_top #(
    parameter DATA_WIDTH = 16,
    parameter ACCUM_WIDTH = 32
)
(
    // ========== Clock and Reset ==========
    input wire clk,
    input wire reset,
    
    // ========== Ifmaps/Weight Inputs ==========
    input wire [DATA_WIDTH-1:0] ifmap_weight_from_up,
    input wire [DATA_WIDTH-1:0] ifmap_weight_from_left,
    input wire [DATA_WIDTH-1:0] ifmap_weight_from_down,
    
    // ========== Partial Sum Inputs ==========
    input wire [ACCUM_WIDTH-1:0] partial_sum_from_up,
    input wire [ACCUM_WIDTH-1:0] partial_sum_from_left,
    input wire [ACCUM_WIDTH-1:0] partial_sum_from_down,
    
    // ========== Configuration Inputs (for PE_control) ==========
    input wire operation_mode,          // 0 = Normal, 1 = Split
    input wire [3:0] pe_row,
    input wire [3:0] pe_col,
    input wire start_computation,
    input wire [7:0] ofmap_size,
    input wire [7:0] num_channels,
    input wire [2:0] kernel_size,
    
    // ========== Ifmaps/Weight Outputs ==========
    output wire [DATA_WIDTH-1:0] ifmap_weight_go_up_down,
    output wire [DATA_WIDTH-1:0] ifmap_weight_go_right,
    
    // ========== Partial Sum Outputs ==========
    output wire [ACCUM_WIDTH-1:0] partial_sum_go_up_down_right,
    
    // ========== Final Output ==========
    output wire [ACCUM_WIDTH-1:0] output_data
);

    // ========== Internal Signals - Weight Path (16-bit) ==========
    wire [DATA_WIDTH-1:0] mux_reg;
    wire [DATA_WIDTH-1:0] reg_mul;
    wire [DATA_WIDTH-1:0] reg_left_A;
    wire [DATA_WIDTH-1:0] reg_left_B;
    
    // ========== Internal Signals - Partial Sum Path (32-bit) ==========
    wire [ACCUM_WIDTH-1:0] operation_result;
    wire [ACCUM_WIDTH-1:0] reg_op_out;
    wire [ACCUM_WIDTH-1:0] delay_out;
    wire [ACCUM_WIDTH-1:0] mux31_mux21;
    wire [ACCUM_WIDTH-1:0] mux31_mux21_add;
    wire [ACCUM_WIDTH-1:0] dmux_add;
    
    // ========== Control Signals (driven by PE_control) ==========
    wire en_reg_mul;
    wire en_reg_left_A;
    wire en_reg_left_B;
    wire en_reg_op_out;
    wire ctrl_delay_unit;
    wire ctrl_mux_reg;
    wire ctrl_mux_mux_reg;
    wire [1:0] ctrl_mux31_mux_21;
    wire ctrl_mux_add;
    wire ctrl_dmux;
    wire ctrl_partial_mux;

    // ==========================================================================
    // PE CONTROL UNIT
    // ==========================================================================
    
    CMSA_controller #(
        .ARRAY_SIZE(16),
        .K_SIZE(3)
    ) pe_controller (
        .clk(clk),
        .reset(reset),
        .operation_mode(operation_mode),
        .pe_row(pe_row),
        .pe_col(pe_col),
        .start_computation(start_computation),
        .ofmap_size(ofmap_size),
        .num_channels(num_channels),
        .kernel_size(kernel_size),
        .en_reg_mul(en_reg_mul),
        .en_reg_left_A(en_reg_left_A),
        .en_reg_left_B(en_reg_left_B),
        .en_reg_op_out(en_reg_op_out),
        .ctrl_delay_unit(ctrl_delay_unit),
        .ctrl_mux_reg(ctrl_mux_reg),
        .ctrl_mux_mux_reg(ctrl_mux_mux_reg),
        .ctrl_mux31_mux_21(ctrl_mux31_mux_21),
        .ctrl_mux_add(ctrl_mux_add),
        .ctrl_dmux(ctrl_dmux),
        .ctrl_partial_mux(ctrl_partial_mux)
    );

    // ==========================================================================
    // WEIGHT DATAFLOW PATH (16-bit)
    // ==========================================================================
    
    // MUX 1: Select weight input from up or down
    mux_2_to_1 #(
        .MXwidth(DATA_WIDTH)
    ) mux_up_down (
        .A(ifmap_weight_from_up),
        .B(ifmap_weight_from_down),
        .selector(ctrl_mux_reg),
        .D(mux_reg)
    );

    // Weight register (for weight-stationary mode)
    register #(
        .Xwidth(DATA_WIDTH)
    ) reg_ifmap_weight_mul (
        .clk(clk),
        .reset(reset),
        .enable(en_reg_mul),
        .data_in(mux_reg),
        .data_out(reg_mul)
    );

    // MUX 2: Select weight output (registered or direct)
    mux_2_to_1 #(
        .MXwidth(DATA_WIDTH)
    ) mux_go_up_down (
        .A(reg_mul),
        .B(mux_reg),
        .selector(ctrl_mux_mux_reg),
        .D(ifmap_weight_go_up_down)
    );
    
    // ==========================================================================
    // ACTIVATION DATAFLOW PATH (16-bit)
    // ==========================================================================
    
    // Register B: First stage delay for left input
    register #(
        .Xwidth(DATA_WIDTH)
    ) reg_ifmap_weight_B (
        .clk(clk),
        .reset(reset),
        .enable(en_reg_left_B),
        .data_in(ifmap_weight_from_left),
        .data_out(reg_left_B)
    );

    // Register A: Second stage delay for left input
    register #(
        .Xwidth(DATA_WIDTH)
    ) reg_ifmap_weight_A (
        .clk(clk),
        .reset(reset),
        .enable(en_reg_left_A),
        .data_in(reg_left_B),
        .data_out(reg_left_A)
    );
    
    // Activation goes right (output from reg_left_A)
    assign ifmap_weight_go_right = reg_left_A;
    
    // ==========================================================================
    // MAC OPERATION (16-bit x 16-bit + 32-bit = 32-bit)
    // ==========================================================================
    
    // Multiply-Accumulate operator
    pe_operator #(
        .INPUT_WIDTH(DATA_WIDTH),
        .ACCUM_WIDTH(ACCUM_WIDTH)
    ) operator_PE (
        .weight(reg_mul),
        .activation(reg_left_A),
        .partial_sum_in(mux31_mux21_add),
        .result_out(operation_result)
    );
    
    // ==========================================================================
    // PARTIAL SUM DATAFLOW PATH (32-bit)
    // ==========================================================================
    
    // MUX 3-to-1: Select partial sum input (from left, up, or down)
    mux_3_to_1 #(
        .MXwidth(ACCUM_WIDTH)
    ) mux_addition (
        .A(partial_sum_from_left),
        .B(partial_sum_from_up),
        .C(partial_sum_from_down),
        .selector(ctrl_mux31_mux_21),
        .D(mux31_mux21)
    );

    // MUX 2-to-1: Select between external or feedback partial sum
    mux_2_to_1 #(
        .MXwidth(ACCUM_WIDTH)
    ) mux_before_addition (
        .A(mux31_mux21),
        .B(dmux_add),
        .selector(ctrl_mux_add),
        .D(mux31_mux21_add)
    );

    // Register after MAC operation
    register #(
        .Xwidth(ACCUM_WIDTH)
    ) reg_after_operation (
        .clk(clk),
        .reset(reset),
        .enable(en_reg_op_out),
        .data_in(operation_result),
        .data_out(reg_op_out)
    );

    // Delay unit (2-stage register chain)
    delay_module #(
        .DATA_WIDTH(ACCUM_WIDTH),
        .NUM_STAGES(2)
    ) delay_unit (
        .clk(clk),
        .reset(reset),
        .enable(ctrl_delay_unit),
        .data_in(reg_op_out),
        .data_out(delay_out)
    );

    // DEMUX 1-to-2: Route to output or feedback
    dmux_1_to_2 #(
        .MXwidth(ACCUM_WIDTH)
    ) demux_after_addition (
        .D(delay_out),
        .selector(ctrl_dmux),
        .Y0(output_data),
        .Y1(dmux_add)
    );

    // MUX: Select partial sum output (direct or delayed)
    mux_2_to_1 #(
        .MXwidth(ACCUM_WIDTH)
    ) mux_partial_sum_go_right (
        .A(reg_op_out),
        .B(delay_out),
        .selector(ctrl_partial_mux),
        .D(partial_sum_go_up_down_right)
    );

endmodule
