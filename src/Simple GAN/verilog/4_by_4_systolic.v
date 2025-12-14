// 4x4 Systolic Array using CMSA PE
// Weight dataflow: vertical (top to bottom)
// Activation dataflow: horizontal (left to right)
// Partial sum dataflow: horizontal (left to right)

`include "PE_top.v"

module systolic_4x4 #(
    parameter DATA_WIDTH = 16,
    parameter ACCUM_WIDTH = 32
)
(
    // Clock and Reset
    input wire clk,
    input wire reset,
    
    // Configuration for all PEs
    input wire operation_mode,
    input wire start_computation,
    input wire [7:0] ofmap_size,
    input wire [7:0] num_channels,
    input wire [2:0] kernel_size,
    
    // Weight inputs from top (16-bit, 4 columns)
    input wire [DATA_WIDTH-1:0] weight_in_col0,
    input wire [DATA_WIDTH-1:0] weight_in_col1,
    input wire [DATA_WIDTH-1:0] weight_in_col2,
    input wire [DATA_WIDTH-1:0] weight_in_col3,
    
    // Activation inputs from left (16-bit, 4 rows)
    input wire [DATA_WIDTH-1:0] activation_in_row0,
    input wire [DATA_WIDTH-1:0] activation_in_row1,
    input wire [DATA_WIDTH-1:0] activation_in_row2,
    input wire [DATA_WIDTH-1:0] activation_in_row3,
    
    // Partial sum inputs from left (32-bit, 4 rows, usually 0)
    input wire [ACCUM_WIDTH-1:0] partial_sum_in_row0,
    input wire [ACCUM_WIDTH-1:0] partial_sum_in_row1,
    input wire [ACCUM_WIDTH-1:0] partial_sum_in_row2,
    input wire [ACCUM_WIDTH-1:0] partial_sum_in_row3,
    
    // Final outputs (32-bit, 4x4 = 16 outputs)
    output wire [ACCUM_WIDTH-1:0] output_data_00,
    output wire [ACCUM_WIDTH-1:0] output_data_01,
    output wire [ACCUM_WIDTH-1:0] output_data_02,
    output wire [ACCUM_WIDTH-1:0] output_data_03,
    output wire [ACCUM_WIDTH-1:0] output_data_10,
    output wire [ACCUM_WIDTH-1:0] output_data_11,
    output wire [ACCUM_WIDTH-1:0] output_data_12,
    output wire [ACCUM_WIDTH-1:0] output_data_13,
    output wire [ACCUM_WIDTH-1:0] output_data_20,
    output wire [ACCUM_WIDTH-1:0] output_data_21,
    output wire [ACCUM_WIDTH-1:0] output_data_22,
    output wire [ACCUM_WIDTH-1:0] output_data_23,
    output wire [ACCUM_WIDTH-1:0] output_data_30,
    output wire [ACCUM_WIDTH-1:0] output_data_31,
    output wire [ACCUM_WIDTH-1:0] output_data_32,
    output wire [ACCUM_WIDTH-1:0] output_data_33
);

    // Internal weight connections (vertical: up-down)
    wire [DATA_WIDTH-1:0] weight_01, weight_02, weight_03;
    wire [DATA_WIDTH-1:0] weight_11, weight_12, weight_13;
    wire [DATA_WIDTH-1:0] weight_21, weight_22, weight_23;
    wire [DATA_WIDTH-1:0] weight_31, weight_32, weight_33;
    
    // Internal activation connections (horizontal: left-right)
    wire [DATA_WIDTH-1:0] act_01, act_02, act_03;
    wire [DATA_WIDTH-1:0] act_11, act_12, act_13;
    wire [DATA_WIDTH-1:0] act_21, act_22, act_23;
    wire [DATA_WIDTH-1:0] act_31, act_32, act_33;
    
    // Internal partial sum connections (horizontal: left-right)
    wire [ACCUM_WIDTH-1:0] psum_01, psum_02, psum_03;
    wire [ACCUM_WIDTH-1:0] psum_11, psum_12, psum_13;
    wire [ACCUM_WIDTH-1:0] psum_21, psum_22, psum_23;
    wire [ACCUM_WIDTH-1:0] psum_31, psum_32, psum_33;

    // ==========================================================================
    // Row 0
    // ==========================================================================
    
    PE_top #(
        .DATA_WIDTH(DATA_WIDTH),
        .ACCUM_WIDTH(ACCUM_WIDTH)
    ) PE_0_0 (
        .clk(clk),
        .reset(reset),
        .ifmap_weight_from_up(weight_in_col0),
        .ifmap_weight_from_left(activation_in_row0),
        .ifmap_weight_from_down({DATA_WIDTH{1'b0}}),
        .partial_sum_from_up({ACCUM_WIDTH{1'b0}}),
        .partial_sum_from_left(partial_sum_in_row0),
        .partial_sum_from_down({ACCUM_WIDTH{1'b0}}),
        .operation_mode(operation_mode),
        .pe_row(4'd0),
        .pe_col(4'd0),
        .start_computation(start_computation),
        .ofmap_size(ofmap_size),
        .num_channels(num_channels),
        .kernel_size(kernel_size),
        .ifmap_weight_go_up_down(weight_01),
        .ifmap_weight_go_right(act_01),
        .partial_sum_go_up_down_right(psum_01),
        .output_data(output_data_00)
    );
    
    PE_top #(
        .DATA_WIDTH(DATA_WIDTH),
        .ACCUM_WIDTH(ACCUM_WIDTH)
    ) PE_0_1 (
        .clk(clk),
        .reset(reset),
        .ifmap_weight_from_up(weight_in_col1),
        .ifmap_weight_from_left(act_01),
        .ifmap_weight_from_down({DATA_WIDTH{1'b0}}),
        .partial_sum_from_up({ACCUM_WIDTH{1'b0}}),
        .partial_sum_from_left(psum_01),
        .partial_sum_from_down({ACCUM_WIDTH{1'b0}}),
        .operation_mode(operation_mode),
        .pe_row(4'd0),
        .pe_col(4'd1),
        .start_computation(start_computation),
        .ofmap_size(ofmap_size),
        .num_channels(num_channels),
        .kernel_size(kernel_size),
        .ifmap_weight_go_up_down(weight_11),
        .ifmap_weight_go_right(act_02),
        .partial_sum_go_up_down_right(psum_02),
        .output_data(output_data_01)
    );
    
    PE_top #(
        .DATA_WIDTH(DATA_WIDTH),
        .ACCUM_WIDTH(ACCUM_WIDTH)
    ) PE_0_2 (
        .clk(clk),
        .reset(reset),
        .ifmap_weight_from_up(weight_in_col2),
        .ifmap_weight_from_left(act_02),
        .ifmap_weight_from_down({DATA_WIDTH{1'b0}}),
        .partial_sum_from_up({ACCUM_WIDTH{1'b0}}),
        .partial_sum_from_left(psum_02),
        .partial_sum_from_down({ACCUM_WIDTH{1'b0}}),
        .operation_mode(operation_mode),
        .pe_row(4'd0),
        .pe_col(4'd2),
        .start_computation(start_computation),
        .ofmap_size(ofmap_size),
        .num_channels(num_channels),
        .kernel_size(kernel_size),
        .ifmap_weight_go_up_down(weight_21),
        .ifmap_weight_go_right(act_03),
        .partial_sum_go_up_down_right(psum_03),
        .output_data(output_data_02)
    );
    
    PE_top #(
        .DATA_WIDTH(DATA_WIDTH),
        .ACCUM_WIDTH(ACCUM_WIDTH)
    ) PE_0_3 (
        .clk(clk),
        .reset(reset),
        .ifmap_weight_from_up(weight_in_col3),
        .ifmap_weight_from_left(act_03),
        .ifmap_weight_from_down({DATA_WIDTH{1'b0}}),
        .partial_sum_from_up({ACCUM_WIDTH{1'b0}}),
        .partial_sum_from_left(psum_03),
        .partial_sum_from_down({ACCUM_WIDTH{1'b0}}),
        .operation_mode(operation_mode),
        .pe_row(4'd0),
        .pe_col(4'd3),
        .start_computation(start_computation),
        .ofmap_size(ofmap_size),
        .num_channels(num_channels),
        .kernel_size(kernel_size),
        .ifmap_weight_go_up_down(weight_31),
        .ifmap_weight_go_right(),  // Not used
        .partial_sum_go_up_down_right(),  // Not used
        .output_data(output_data_03)
    );

    // ==========================================================================
    // Row 1
    // ==========================================================================
    
    PE_top #(
        .DATA_WIDTH(DATA_WIDTH),
        .ACCUM_WIDTH(ACCUM_WIDTH)
    ) PE_1_0 (
        .clk(clk),
        .reset(reset),
        .ifmap_weight_from_up(weight_01),
        .ifmap_weight_from_left(activation_in_row1),
        .ifmap_weight_from_down({DATA_WIDTH{1'b0}}),
        .partial_sum_from_up({ACCUM_WIDTH{1'b0}}),
        .partial_sum_from_left(partial_sum_in_row1),
        .partial_sum_from_down({ACCUM_WIDTH{1'b0}}),
        .operation_mode(operation_mode),
        .pe_row(4'd1),
        .pe_col(4'd0),
        .start_computation(start_computation),
        .ofmap_size(ofmap_size),
        .num_channels(num_channels),
        .kernel_size(kernel_size),
        .ifmap_weight_go_up_down(weight_02),
        .ifmap_weight_go_right(act_11),
        .partial_sum_go_up_down_right(psum_11),
        .output_data(output_data_10)
    );
    
    PE_top #(
        .DATA_WIDTH(DATA_WIDTH),
        .ACCUM_WIDTH(ACCUM_WIDTH)
    ) PE_1_1 (
        .clk(clk),
        .reset(reset),
        .ifmap_weight_from_up(weight_11),
        .ifmap_weight_from_left(act_11),
        .ifmap_weight_from_down({DATA_WIDTH{1'b0}}),
        .partial_sum_from_up({ACCUM_WIDTH{1'b0}}),
        .partial_sum_from_left(psum_11),
        .partial_sum_from_down({ACCUM_WIDTH{1'b0}}),
        .operation_mode(operation_mode),
        .pe_row(4'd1),
        .pe_col(4'd1),
        .start_computation(start_computation),
        .ofmap_size(ofmap_size),
        .num_channels(num_channels),
        .kernel_size(kernel_size),
        .ifmap_weight_go_up_down(weight_12),
        .ifmap_weight_go_right(act_12),
        .partial_sum_go_up_down_right(psum_12),
        .output_data(output_data_11)
    );
    
    PE_top #(
        .DATA_WIDTH(DATA_WIDTH),
        .ACCUM_WIDTH(ACCUM_WIDTH)
    ) PE_1_2 (
        .clk(clk),
        .reset(reset),
        .ifmap_weight_from_up(weight_21),
        .ifmap_weight_from_left(act_12),
        .ifmap_weight_from_down({DATA_WIDTH{1'b0}}),
        .partial_sum_from_up({ACCUM_WIDTH{1'b0}}),
        .partial_sum_from_left(psum_12),
        .partial_sum_from_down({ACCUM_WIDTH{1'b0}}),
        .operation_mode(operation_mode),
        .pe_row(4'd1),
        .pe_col(4'd2),
        .start_computation(start_computation),
        .ofmap_size(ofmap_size),
        .num_channels(num_channels),
        .kernel_size(kernel_size),
        .ifmap_weight_go_up_down(weight_22),
        .ifmap_weight_go_right(act_13),
        .partial_sum_go_up_down_right(psum_13),
        .output_data(output_data_12)
    );
    
    PE_top #(
        .DATA_WIDTH(DATA_WIDTH),
        .ACCUM_WIDTH(ACCUM_WIDTH)
    ) PE_1_3 (
        .clk(clk),
        .reset(reset),
        .ifmap_weight_from_up(weight_31),
        .ifmap_weight_from_left(act_13),
        .ifmap_weight_from_down({DATA_WIDTH{1'b0}}),
        .partial_sum_from_up({ACCUM_WIDTH{1'b0}}),
        .partial_sum_from_left(psum_13),
        .partial_sum_from_down({ACCUM_WIDTH{1'b0}}),
        .operation_mode(operation_mode),
        .pe_row(4'd1),
        .pe_col(4'd3),
        .start_computation(start_computation),
        .ofmap_size(ofmap_size),
        .num_channels(num_channels),
        .kernel_size(kernel_size),
        .ifmap_weight_go_up_down(weight_32),
        .ifmap_weight_go_right(),
        .partial_sum_go_up_down_right(),
        .output_data(output_data_13)
    );

    // ==========================================================================
    // Row 2
    // ==========================================================================
    
    PE_top #(
        .DATA_WIDTH(DATA_WIDTH),
        .ACCUM_WIDTH(ACCUM_WIDTH)
    ) PE_2_0 (
        .clk(clk),
        .reset(reset),
        .ifmap_weight_from_up(weight_02),
        .ifmap_weight_from_left(activation_in_row2),
        .ifmap_weight_from_down({DATA_WIDTH{1'b0}}),
        .partial_sum_from_up({ACCUM_WIDTH{1'b0}}),
        .partial_sum_from_left(partial_sum_in_row2),
        .partial_sum_from_down({ACCUM_WIDTH{1'b0}}),
        .operation_mode(operation_mode),
        .pe_row(4'd2),
        .pe_col(4'd0),
        .start_computation(start_computation),
        .ofmap_size(ofmap_size),
        .num_channels(num_channels),
        .kernel_size(kernel_size),
        .ifmap_weight_go_up_down(weight_03),
        .ifmap_weight_go_right(act_21),
        .partial_sum_go_up_down_right(psum_21),
        .output_data(output_data_20)
    );
    
    PE_top #(
        .DATA_WIDTH(DATA_WIDTH),
        .ACCUM_WIDTH(ACCUM_WIDTH)
    ) PE_2_1 (
        .clk(clk),
        .reset(reset),
        .ifmap_weight_from_up(weight_12),
        .ifmap_weight_from_left(act_21),
        .ifmap_weight_from_down({DATA_WIDTH{1'b0}}),
        .partial_sum_from_up({ACCUM_WIDTH{1'b0}}),
        .partial_sum_from_left(psum_21),
        .partial_sum_from_down({ACCUM_WIDTH{1'b0}}),
        .operation_mode(operation_mode),
        .pe_row(4'd2),
        .pe_col(4'd1),
        .start_computation(start_computation),
        .ofmap_size(ofmap_size),
        .num_channels(num_channels),
        .kernel_size(kernel_size),
        .ifmap_weight_go_up_down(weight_13),
        .ifmap_weight_go_right(act_22),
        .partial_sum_go_up_down_right(psum_22),
        .output_data(output_data_21)
    );
    
    PE_top #(
        .DATA_WIDTH(DATA_WIDTH),
        .ACCUM_WIDTH(ACCUM_WIDTH)
    ) PE_2_2 (
        .clk(clk),
        .reset(reset),
        .ifmap_weight_from_up(weight_22),
        .ifmap_weight_from_left(act_22),
        .ifmap_weight_from_down({DATA_WIDTH{1'b0}}),
        .partial_sum_from_up({ACCUM_WIDTH{1'b0}}),
        .partial_sum_from_left(psum_22),
        .partial_sum_from_down({ACCUM_WIDTH{1'b0}}),
        .operation_mode(operation_mode),
        .pe_row(4'd2),
        .pe_col(4'd2),
        .start_computation(start_computation),
        .ofmap_size(ofmap_size),
        .num_channels(num_channels),
        .kernel_size(kernel_size),
        .ifmap_weight_go_up_down(weight_23),
        .ifmap_weight_go_right(act_23),
        .partial_sum_go_up_down_right(psum_23),
        .output_data(output_data_22)
    );
    
    PE_top #(
        .DATA_WIDTH(DATA_WIDTH),
        .ACCUM_WIDTH(ACCUM_WIDTH)
    ) PE_2_3 (
        .clk(clk),
        .reset(reset),
        .ifmap_weight_from_up(weight_32),
        .ifmap_weight_from_left(act_23),
        .ifmap_weight_from_down({DATA_WIDTH{1'b0}}),
        .partial_sum_from_up({ACCUM_WIDTH{1'b0}}),
        .partial_sum_from_left(psum_23),
        .partial_sum_from_down({ACCUM_WIDTH{1'b0}}),
        .operation_mode(operation_mode),
        .pe_row(4'd2),
        .pe_col(4'd3),
        .start_computation(start_computation),
        .ofmap_size(ofmap_size),
        .num_channels(num_channels),
        .kernel_size(kernel_size),
        .ifmap_weight_go_up_down(weight_33),
        .ifmap_weight_go_right(),
        .partial_sum_go_up_down_right(),
        .output_data(output_data_23)
    );

    // ==========================================================================
    // Row 3
    // ==========================================================================
    
    PE_top #(
        .DATA_WIDTH(DATA_WIDTH),
        .ACCUM_WIDTH(ACCUM_WIDTH)
    ) PE_3_0 (
        .clk(clk),
        .reset(reset),
        .ifmap_weight_from_up(weight_03),
        .ifmap_weight_from_left(activation_in_row3),
        .ifmap_weight_from_down({DATA_WIDTH{1'b0}}),
        .partial_sum_from_up({ACCUM_WIDTH{1'b0}}),
        .partial_sum_from_left(partial_sum_in_row3),
        .partial_sum_from_down({ACCUM_WIDTH{1'b0}}),
        .operation_mode(operation_mode),
        .pe_row(4'd3),
        .pe_col(4'd0),
        .start_computation(start_computation),
        .ofmap_size(ofmap_size),
        .num_channels(num_channels),
        .kernel_size(kernel_size),
        .ifmap_weight_go_up_down(),  // Not used (last row)
        .ifmap_weight_go_right(act_31),
        .partial_sum_go_up_down_right(psum_31),
        .output_data(output_data_30)
    );
    
    PE_top #(
        .DATA_WIDTH(DATA_WIDTH),
        .ACCUM_WIDTH(ACCUM_WIDTH)
    ) PE_3_1 (
        .clk(clk),
        .reset(reset),
        .ifmap_weight_from_up(weight_13),
        .ifmap_weight_from_left(act_31),
        .ifmap_weight_from_down({DATA_WIDTH{1'b0}}),
        .partial_sum_from_up({ACCUM_WIDTH{1'b0}}),
        .partial_sum_from_left(psum_31),
        .partial_sum_from_down({ACCUM_WIDTH{1'b0}}),
        .operation_mode(operation_mode),
        .pe_row(4'd3),
        .pe_col(4'd1),
        .start_computation(start_computation),
        .ofmap_size(ofmap_size),
        .num_channels(num_channels),
        .kernel_size(kernel_size),
        .ifmap_weight_go_up_down(),
        .ifmap_weight_go_right(act_32),
        .partial_sum_go_up_down_right(psum_32),
        .output_data(output_data_31)
    );
    
    PE_top #(
        .DATA_WIDTH(DATA_WIDTH),
        .ACCUM_WIDTH(ACCUM_WIDTH)
    ) PE_3_2 (
        .clk(clk),
        .reset(reset),
        .ifmap_weight_from_up(weight_23),
        .ifmap_weight_from_left(act_32),
        .ifmap_weight_from_down({DATA_WIDTH{1'b0}}),
        .partial_sum_from_up({ACCUM_WIDTH{1'b0}}),
        .partial_sum_from_left(psum_32),
        .partial_sum_from_down({ACCUM_WIDTH{1'b0}}),
        .operation_mode(operation_mode),
        .pe_row(4'd3),
        .pe_col(4'd2),
        .start_computation(start_computation),
        .ofmap_size(ofmap_size),
        .num_channels(num_channels),
        .kernel_size(kernel_size),
        .ifmap_weight_go_up_down(),
        .ifmap_weight_go_right(act_33),
        .partial_sum_go_up_down_right(psum_33),
        .output_data(output_data_32)
    );
    
    PE_top #(
        .DATA_WIDTH(DATA_WIDTH),
        .ACCUM_WIDTH(ACCUM_WIDTH)
    ) PE_3_3 (
        .clk(clk),
        .reset(reset),
        .ifmap_weight_from_up(weight_33),
        .ifmap_weight_from_left(act_33),
        .ifmap_weight_from_down({DATA_WIDTH{1'b0}}),
        .partial_sum_from_up({ACCUM_WIDTH{1'b0}}),
        .partial_sum_from_left(psum_33),
        .partial_sum_from_down({ACCUM_WIDTH{1'b0}}),
        .operation_mode(operation_mode),
        .pe_row(4'd3),
        .pe_col(4'd3),
        .start_computation(start_computation),
        .ofmap_size(ofmap_size),
        .num_channels(num_channels),
        .kernel_size(kernel_size),
        .ifmap_weight_go_up_down(),
        .ifmap_weight_go_right(),
        .partial_sum_go_up_down_right(),
        .output_data(output_data_33)
    );

endmodule
