// ============================================================
// Onedconv_Control_Top
// Unified Control Module for 1D Convolution Operations
// 
// This module combines three control layers into a single block:
// 1. Auto Scheduler - Layer sequencing and dependency tracking
// 2. Scheduler FSM - AXI handshaking and layer configuration (with ROM)
// 3. Control Wrapper - Datapath control (counters, FSMs, systolic array)
//
// Direct interface with:
// - AXI interface (write_done, read_done)
// - Datapath (systolic array, BRAMs, counters)
// - Host (global_start, global_done)
//
// Updated: January 30, 2026
// Changes: Fixed reset polarity to match wrapper's rst_n interface
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
    input  wire global_start,   // Start entire 10-layer sequence (optional override)
    output wire global_done,    // All 10 layers complete
    
    // ============================================================
    // AXI Interface
    // ============================================================
    input  wire weight_write_done,    // AXI weight write complete
    input  wire ifmap_write_done,     // AXI ifmap write complete
    input  wire read_done,            // AXI read complete
    input  wire transmission_active,  // Output Manager is sending data
    
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
    output wire [Dimension-1:0] en_shift_reg_ifmap_muxed,
    output wire [Dimension-1:0] en_shift_reg_weight_muxed,
    output wire zero_or_data,
    output wire zero_or_data_weight,
    output wire [MUX_SEL_WIDTH-1:0] sel_input_data_mem,
    output wire output_bram_destination,
    
    // ============================================================
    // Systolic Array Control Outputs
    // ============================================================
    output wire [Dimension*Dimension-1:0] en_in_systolic,
    output wire [Dimension*Dimension-1:0] en_out_systolic,
    output wire [Dimension*Dimension-1:0] en_psum_systolic,
    output wire [Dimension-1:0] ifmaps_sel_systolic,
    output wire [Dimension-1:0] output_eject_ctrl_systolic,
    
    // ============================================================
    // Adder-Side Register Control
    // ============================================================
    output wire en_reg_adder,
    output wire output_result_reg_rst,
    
    // ============================================================
    // Top-Level IO Control (for systolic array)
    // ============================================================
    output wire rst_top,
    output wire out_new_val_sign,
    // ============================================================
    // Status Outputs (for monitoring)
    // ============================================================
    output wire [3:0] current_layer_id,
    output wire layer_processing,
    
    // ============================================================
    // Auto Scheduler Status Outputs (optional, for debugging)
    // ============================================================
    output wire all_layers_complete,
    output wire layer_transition,
    output wire clear_output_bram,
    output wire auto_start_active,
    output wire data_load_ready
);

    // ============================================================
    // Internal Wiring Between Control Layers
    // ============================================================
    
    // Auto Scheduler <-> Scheduler FSM
    wire auto_to_fsm_start;
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
    assign layer_processing = ~all_layers_complete;
    assign global_done = all_layers_complete;
    
    // ============================================================
    // Layer 1: Auto Scheduler
    // Manages 10-layer sequence (Layer 0-9) with automatic data dependency tracking
    // ============================================================
    Onedconv_Auto_Scheduler #(
        .DW(DW)
    ) auto_scheduler_inst (
        .clk(clk),
        .rst_n(rst_n),
        
        // Data Load Status (From AXI Write Operations)
        .weight_write_done(weight_write_done),
        .ifmap_write_done(ifmap_write_done),
        
        // External Controls (Optional Override)
        .ext_scheduler_start(global_start),
        .external_layer_id(4'd0),  // Not used when using automatic sequencing
        
        // Execution Status (From Main Scheduler via pulse)
        .layer_complete_signal(fsm_to_auto_layer_complete),
        
        // Output Controls
        .final_start_signal(auto_to_fsm_start),
        .current_layer_id(current_layer_id),
        .all_layers_complete(all_layers_complete),
        .layer_transition(layer_transition),
        .clear_output_bram(clear_output_bram),
        .auto_start_active(auto_start_active),
        .data_load_ready(data_load_ready)
    );
    
    // ============================================================
    // Layer 2: Scheduler FSM
    // Handles AXI handshaking and layer execution
    // Layer configurations stored in internal ROM
    // ============================================================
    Onedconv_Scheduler_FSM #(
        .DW(DW),
        .CHANNELS_PER_BATCH(64)
    ) scheduler_fsm_inst (
        .clk(clk),
        .rst_n(rst_n),
        
        // Trigger from Auto Scheduler
        .start(auto_to_fsm_start),
        
        // Layer Context from Auto Scheduler
        .current_layer_id(current_layer_id),
        
        // AXI interface
        .write_done(weight_write_done | ifmap_write_done),  // Combined for FSM
        .read_done(read_done),
        .transmission_active(transmission_active),
        
        // Control Wrapper interface
        .done_all(wrapper_to_fsm_done_all),
        .done_filter(wrapper_to_fsm_done_filter),
        .weight_req_top(wrapper_to_fsm_weight_req),
        .weight_ack_top(fsm_to_wrapper_weight_ack),
        .start_whole(fsm_to_wrapper_start),
        
        // Configuration outputs to wrapper (from internal ROM)
        .stride(fsm_stride),
        .padding(fsm_padding),
        .kernel_size(fsm_kernel_size),
        .input_channels(fsm_input_channels),
        .filter_number(fsm_filter_number),
        .temporal_length(fsm_temporal_length)
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
        .rst_n(rst_n),              // FIXED: Now passing rst_n to match wrapper's interface
        
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
        .en_shift_reg_ifmap_muxed(en_shift_reg_ifmap_muxed),
        .en_shift_reg_weight_muxed(en_shift_reg_weight_muxed),
        .zero_or_data(zero_or_data),
        .zero_or_data_weight(zero_or_data_weight),
        .sel_input_data_mem(sel_input_data_mem),
        .output_bram_destination(output_bram_destination),
        
        // Systolic array control
        .en_in_systolic(en_in_systolic),
        .en_out_systolic(en_out_systolic),
        .en_psum_systolic(en_psum_systolic),
        .ifmaps_sel_systolic(ifmaps_sel_systolic),
        .output_eject_ctrl_systolic(output_eject_ctrl_systolic),
        
        // Adder register control
        .en_reg_adder(en_reg_adder),
        .output_result_reg_rst(output_result_reg_rst),
        
        // Top-level IO control
        .rst_top(rst_top),
        .out_new_val_sign(out_new_val_sign)
    );

endmodule