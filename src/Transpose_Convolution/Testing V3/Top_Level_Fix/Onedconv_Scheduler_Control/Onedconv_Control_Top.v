// ============================================================
// Onedconv_Control_Top
// Unified Control Module for 1D Convolution Operations
// 
// This module combines three control layers into a single block:
// 1. Auto Scheduler - Layer sequencing and dependency tracking
// 2. Scheduler FSM - AXI handshaking and layer configuration
// 3. Control Wrapper - Datapath control (counters, FSMs, systolic array)
//
// Direct interface with:
// - AXI interface (write_done, read_done)
// - Datapath (systolic array, BRAMs, counters)
// - Host (global_start, global_done)
// ============================================================
module Onedconv_Control_Top #(
    parameter DW = 16,
    parameter Dimension = 16,
    parameter ADDRESS_LENGTH = 10,
    parameter MUX_SEL_WIDTH = 4
)(
    input  wire clk,
    input  wire rst_n,          // Active-low reset for compatibility
    
    // ============================================================
    // Global Control Interface
    // ============================================================
    input  wire global_start,   // Start entire 9-layer sequence
    output wire global_done,    // All 9 layers complete
    
    // ============================================================
    // AXI Interface
    // ============================================================
    input  wire write_done,     // AXI write complete (weight or ifmap)
    input  wire read_done,      // AXI read complete
    input  wire transmission_active,  // Optional: set to 1'b0 if unused
    
    // AXI control outputs
    output wire weight_read_req,      // Request weight data from DDR
    output wire ifmap_read_req,       // Request ifmap data from DDR
    output wire ofmap_write_req,      // Request to write ofmap to DDR
    
    // ============================================================
    // Matrix Multiplication Datapath Inputs
    // ============================================================
    input  wire out_new_val_sign,     // New output value from systolic array
    
    // ============================================================
    // BRAM Address Outputs
    // ============================================================
    output wire [ADDRESS_LENGTH-1:0] inputdata_addr_out,
    output wire [ADDRESS_LENGTH-1:0] weight_addr_out,
    output wire [ADDRESS_LENGTH-1:0] output_addr_out_a,
    output wire [ADDRESS_LENGTH-1:0] output_addr_out_b,
    
    // ============================================================
    // BRAM Control Outputs
    // ============================================================
    output wire [Dimension-1:0] enb_inputdata_input_bram,
    output wire [Dimension-1:0] enb_weight_input_bram,
    output wire [Dimension-1:0] ena_output_result_control,
    output wire [Dimension-1:0] wea_output_result,
    output wire [Dimension-1:0] enb_output_result_control,
    
    // ============================================================
    // Shift Register & Datapath Control
    // ============================================================
    output wire [Dimension-1:0] en_shift_reg_ifmap_input_ctrl,
    output wire [Dimension-1:0] en_shift_reg_weight_input_ctrl,
    output wire zero_or_data,
    output wire zero_or_data_weight,
    output wire [MUX_SEL_WIDTH-1:0] sel_input_data_mem,
    output wire output_bram_destination,
    
    // ============================================================
    // Systolic Array Control Outputs
    // ============================================================
    output wire en_cntr_systolic,
    output wire [Dimension*Dimension-1:0] en_in_systolic,
    output wire [Dimension*Dimension-1:0] en_out_systolic,
    output wire [Dimension*Dimension-1:0] en_psum_systolic,
    output wire [Dimension-1:0] ifmaps_sel_systolic,
    output wire [Dimension-1:0] output_eject_ctrl_systolic,
    output wire output_val_count_systolic,
    
    // ============================================================
    // Adder-Side Register Control
    // ============================================================
    output wire en_reg_adder,
    output wire output_result_reg_rst,
    
    // ============================================================
    // Top-Level IO Control (for systolic array)
    // ============================================================
    output wire rst_top,
    output wire mode_top,
    output wire output_val_top,
    output wire start_top,
    
    // ============================================================
    // Status Outputs (for monitoring)
    // ============================================================
    output wire [3:0] current_layer_id,
    output wire layer_processing,
    output wire [3:0] scheduler_state,
    output wire done_count_top,
    output wire done_top
);

    // ============================================================
    // Internal Wiring Between Control Layers
    // ============================================================
    
    // Positive reset for internal modules
    wire rst = ~rst_n;
    
    // Auto Scheduler <-> Scheduler FSM
    wire auto_to_fsm_start;
    wire [1:0] auto_stride;
    wire [2:0] auto_padding;
    wire [4:0] auto_kernel_size;
    wire [9:0] auto_input_channels;
    wire [9:0] auto_filter_number;
    wire [9:0] auto_temporal_length;
    wire [3:0] auto_layer_id;
    
    wire fsm_to_auto_layer_complete;
    
    // Scheduler FSM <-> Control Wrapper
    wire fsm_to_wrapper_start;
    wire [1:0] fsm_stride;
    wire [2:0] fsm_padding;
    wire [4:0] fsm_kernel_size;
    wire [9:0] fsm_input_channels;
    wire [9:0] fsm_filter_number;
    wire [9:0] fsm_temporal_length;
    
    wire wrapper_to_fsm_done_all;
    wire wrapper_to_fsm_done_filter;
    wire wrapper_to_fsm_weight_req;
    wire fsm_to_wrapper_weight_ack;
    
    // Edge detection for layer completion
    reg done_all_prev;
    wire done_all_pulse;
    
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n)
            done_all_prev <= 1'b0;
        else
            done_all_prev <= wrapper_to_fsm_done_all;
    end
    
    assign done_all_pulse = wrapper_to_fsm_done_all & ~done_all_prev;
    assign fsm_to_auto_layer_complete = done_all_pulse;
    
    // Status outputs
    assign current_layer_id = auto_layer_id;
    assign scheduler_state = 4'b0;  // Can connect to FSM state if needed
    
    // ============================================================
    // Layer 1: Auto Scheduler
    // Manages 9-layer sequence (Layer 0-8)
    // ============================================================
    Onedconv_Auto_Scheduler auto_scheduler_inst (
        .clk(clk),
        .rst_n(rst_n),
        
        // Global control
        .global_start(global_start),
        .global_done(global_done),
        
        // Layer completion from FSM
        .layer_complete(fsm_to_auto_layer_complete),
        
        // Layer configuration outputs to FSM
        .layer_start(auto_to_fsm_start),
        .stride(auto_stride),
        .padding(auto_padding),
        .kernel_size(auto_kernel_size),
        .input_channels(auto_input_channels),
        .filter_number(auto_filter_number),
        .temporal_length(auto_temporal_length),
        .layer_id(auto_layer_id),
        
        // Status
        .layer_processing(layer_processing)
    );
    
    // ============================================================
    // Layer 2: Scheduler FSM
    // Handles AXI handshaking and layer execution
    // ============================================================
    Onedconv_Scheduler_FSM scheduler_fsm_inst (
        .clk(clk),
        .rst_n(rst_n),
        
        // Layer configuration from Auto Scheduler
        .layer_start(auto_to_fsm_start),
        .stride(auto_stride),
        .padding(auto_padding),
        .kernel_size(auto_kernel_size),
        .input_channels(auto_input_channels),
        .filter_number(auto_filter_number),
        .temporal_length(auto_temporal_length),
        .layer_id(auto_layer_id),
        
        // AXI interface
        .write_done(write_done),
        .read_done(read_done),
        .transmission_active(transmission_active),
        
        .weight_read_req(weight_read_req),
        .ifmap_read_req(ifmap_read_req),
        .ofmap_write_req(ofmap_write_req),
        
        // Control Wrapper interface
        .start_compute(fsm_to_wrapper_start),
        .compute_done_all(wrapper_to_fsm_done_all),
        .compute_done_filter(wrapper_to_fsm_done_filter),
        .weight_req_top(wrapper_to_fsm_weight_req),
        .weight_ack_top(fsm_to_wrapper_weight_ack),
        
        // Pass-through parameters to wrapper
        .stride_out(fsm_stride),
        .padding_out(fsm_padding),
        .kernel_size_out(fsm_kernel_size),
        .input_channels_out(fsm_input_channels),
        .filter_number_out(fsm_filter_number),
        .temporal_length_out(fsm_temporal_length)
    );
    
    // ============================================================
    // Layer 3: Control Wrapper
    // Datapath control (counters, FSMs, systolic array)
    // ============================================================
    Onedconv_Control_Wrapper #(
        .DW(DW),
        .Dimension(Dimension),
        .ADDRESS_LENGTH(ADDRESS_LENGTH),
        .MUX_SEL_WIDTH(MUX_SEL_WIDTH)
    ) control_wrapper_inst (
        .clk(clk),
        .rst(rst),
        
        // Control from Scheduler FSM
        .start_whole(fsm_to_wrapper_start),
        .done_all(wrapper_to_fsm_done_all),
        .done_filter(wrapper_to_fsm_done_filter),
        
        // Weight handshake
        .weight_req_top(wrapper_to_fsm_weight_req),
        .weight_ack_top(fsm_to_wrapper_weight_ack),
        
        // Convolution parameters from FSM
        .stride(fsm_stride),
        .padding(fsm_padding),
        .kernel_size(fsm_kernel_size),
        .input_channels(fsm_input_channels),
        .filter_number(fsm_filter_number),
        .temporal_length(fsm_temporal_length),
        
        // Datapath inputs
        .out_new_val_sign(out_new_val_sign),
        
        // BRAM addresses
        .inputdata_addr_out(inputdata_addr_out),
        .weight_addr_out(weight_addr_out),
        .output_addr_out_a(output_addr_out_a),
        .output_addr_out_b(output_addr_out_b),
        
        // BRAM control
        .enb_inputdata_input_bram(enb_inputdata_input_bram),
        .enb_weight_input_bram(enb_weight_input_bram),
        .ena_output_result_control(ena_output_result_control),
        .wea_output_result(wea_output_result),
        .enb_output_result_control(enb_output_result_control),
        
        // Shift register & datapath control
        .en_shift_reg_ifmap_input_ctrl(en_shift_reg_ifmap_input_ctrl),
        .en_shift_reg_weight_input_ctrl(en_shift_reg_weight_input_ctrl),
        .zero_or_data(zero_or_data),
        .zero_or_data_weight(zero_or_data_weight),
        .sel_input_data_mem(sel_input_data_mem),
        .output_bram_destination(output_bram_destination),
        
        // Systolic array control
        .en_cntr_systolic(en_cntr_systolic),
        .en_in_systolic(en_in_systolic),
        .en_out_systolic(en_out_systolic),
        .en_psum_systolic(en_psum_systolic),
        .ifmaps_sel_systolic(ifmaps_sel_systolic),
        .output_eject_ctrl_systolic(output_eject_ctrl_systolic),
        .output_val_count_systolic(output_val_count_systolic),
        .done_count_top(done_count_top),
        .done_top(done_top),
        
        // Adder register control
        .en_reg_adder(en_reg_adder),
        .output_result_reg_rst(output_result_reg_rst),
        
        // Top-level IO control
        .rst_top(rst_top),
        .mode_top(mode_top),
        .output_val_top(output_val_top),
        .start_top(start_top)
    );

endmodule