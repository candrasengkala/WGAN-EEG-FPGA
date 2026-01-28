// ============================================================
// Oneconv_Control_Wrapper
// Unified wrapper for all 1D convolution control logic
// Includes: All counters, onedconv_ctrl FSM, and matrix multiplication control
// ============================================================
module Onedconv_Control_Wrapper #(
    parameter DW = 16,
    parameter Dimension = 16,
    parameter ADDRESS_LENGTH = 10,
    parameter MUX_SEL_WIDTH = 4
)(
    input  wire clk,
    input  wire rst,
    
    // --------------------------------------------------------
    // Global control
    // --------------------------------------------------------
    input  wire start_whole,
    output wire done_all,
    output wire done_filter,
    
    // --------------------------------------------------------
    // Weight Update Handshake
    // --------------------------------------------------------
    output wire weight_req_top,
    input  wire weight_ack_top,
    
    // --------------------------------------------------------
    // Convolution parameters
    // --------------------------------------------------------
    input  wire [1:0] stride,
    input  wire [2:0] padding,
    input  wire [4:0] kernel_size,
    input  wire [9:0] input_channels,
    input  wire [9:0] filter_number,
    input  wire [9:0] temporal_length,
    
    // --------------------------------------------------------
    // Matrix multiplication datapath inputs (from top_lvl_io_control)
    // --------------------------------------------------------
    input  wire out_new_val_sign,    // New output value available from systolic array
    // Connect this to sytolic output register.
    // --------------------------------------------------------
    // Counter outputs - addresses for BRAMs
    // --------------------------------------------------------
    output wire [ADDRESS_LENGTH-1:0] inputdata_addr_out,
    output wire [ADDRESS_LENGTH-1:0] weight_addr_out,
    output wire [ADDRESS_LENGTH-1:0] output_addr_out_a,
    output wire [ADDRESS_LENGTH-1:0] output_addr_out_b,
    
    // --------------------------------------------------------
    // BRAM control outputs
    // --------------------------------------------------------
    output wire [Dimension-1:0] enb_inputdata_input_bram,
    output wire [Dimension-1:0] enb_weight_input_bram,
    output wire [Dimension-1:0] ena_output_result_control,
    output wire [Dimension-1:0] wea_output_result,
    output wire [Dimension-1:0] enb_output_result_control,
    
    // --------------------------------------------------------
    // Shift-register & datapath control
    // --------------------------------------------------------
    output wire [Dimension-1:0] en_shift_reg_ifmap_input_ctrl,
    output wire [Dimension-1:0] en_shift_reg_weight_input_ctrl,
    output wire zero_or_data,
    output wire zero_or_data_weight,
    output wire [MUX_SEL_WIDTH-1:0] sel_input_data_mem,
    output wire output_bram_destination,
    
    // --------------------------------------------------------
    // Matrix multiplication control outputs (to systolic array)
    // --------------------------------------------------------
    output wire en_cntr_systolic,
    output wire [Dimension*Dimension-1:0] en_in_systolic,
    output wire [Dimension*Dimension-1:0] en_out_systolic,
    output wire [Dimension*Dimension-1:0] en_psum_systolic,
    output wire [Dimension-1:0] ifmaps_sel_systolic,
    output wire [Dimension-1:0] output_eject_ctrl_systolic,
    output wire output_val_count_systolic,
    output wire done_count_top,
    output wire done_top,
    
    // --------------------------------------------------------
    // Adder-side register control
    // --------------------------------------------------------
    output wire en_reg_adder,
    output wire output_result_reg_rst,
    
    // --------------------------------------------------------
    // Top-level IO control
    // --------------------------------------------------------
    output wire rst_top,
    output wire mode_top,
    output wire output_val_top,
    output wire start_top
);

    // --------------------------------------------------------
    // Internal wires for counter connections
    // --------------------------------------------------------
    
    // Ifmap counter
    wire ifmap_counter_en;
    wire ifmap_counter_done;
    wire ifmap_flag_1per16;
    wire ifmap_counter_rst;
    wire [ADDRESS_LENGTH-1:0] ifmap_counter_start_val;
    wire [ADDRESS_LENGTH-1:0] ifmap_counter_end_val;
    
    // Weight counter
    wire weight_counter_rst;
    wire en_weight_counter;
    wire weight_flag_1per16;
    wire weight_counter_done;
    wire weight_rst_min_16;
    wire [ADDRESS_LENGTH-1:0] weight_counter_start_val;
    wire [ADDRESS_LENGTH-1:0] weight_counter_end_val;
    
    // Output counter A (writing)
    wire output_counter_rst_a;
    wire en_output_counter_a;
    wire output_flag_1per16_a;
    wire output_counter_done_a;
    wire [ADDRESS_LENGTH-1:0] output_counter_start_val_a;
    wire [ADDRESS_LENGTH-1:0] output_counter_end_val_a;
    
    // Output counter B (reading)
    wire output_counter_rst_b;
    wire en_output_counter_b;
    wire output_flag_1per16_b;
    wire output_counter_done_b;
    wire [ADDRESS_LENGTH-1:0] output_counter_start_val_b;
    wire [ADDRESS_LENGTH-1:0] output_counter_end_val_b;
    
    // --------------------------------------------------------
    // Matrix multiplication control internal wires
    // --------------------------------------------------------
    // Counter done signals for matrix mult
    wire done_ifmap_systolic;
    wire done_weight_systolic;
    wire done_count_systolic;
    wire done_all_systolic;
    
    // Counter enables for matrix mult
    wire en_ifmap_counter_systolic;
    wire en_weight_counter_systolic;
    
    // Shift register enables from matrix mult control
    wire [Dimension-1:0] en_shift_reg_ifmap_control;
    wire [Dimension-1:0] en_shift_reg_weight_control;
    
    // Mode mux wires
    wire [Dimension-1:0] en_shift_reg_ifmap_muxed;
    wire [Dimension-1:0] en_shift_reg_weight_muxed;
    
    // --------------------------------------------------------
    // Mode MUX for shift register enables
    // --------------------------------------------------------
    assign en_shift_reg_ifmap_muxed  = mode_top ? en_shift_reg_ifmap_control
                                                 : en_shift_reg_ifmap_input_ctrl;
    
    assign en_shift_reg_weight_muxed = mode_top ? en_shift_reg_weight_control
                                                 : en_shift_reg_weight_input_ctrl;
    
    // --------------------------------------------------------
    // Matrix Multiplication Counters
    // --------------------------------------------------------
    
    // Counter 1: Input counter for ifmap (Dimension+1 cycles)
    counter_input #(
        .Dimension_added(Dimension + 1)
    ) counter_ifmap_systolic_inst (
        .clk(clk),
        .rst(rst),
        .en(en_ifmap_counter_systolic),
        .done(done_ifmap_systolic)
    );
    
    // Counter 2: Input counter for weight (Dimension+1 cycles)
    counter_input #(
        .Dimension_added(Dimension + 1)
    ) counter_weight_systolic_inst (
        .clk(clk),
        .rst(rst),
        .en(en_weight_counter_systolic),
        .done(done_weight_systolic)
    );
    
    // Counter 3: Output counter (Dimension cycles)
    counter_output #(
        .Dimension(Dimension)
    ) counter_output_systolic_inst (
        .clk(clk),
        .rst(rst),
        .en(output_val_count_systolic),
        .done(out_new_val_sign)
    );
    
    // Counter 4: Top-level counter (2*Dimension cycles) for systolic array propagation
    counter_top_lvl #(
        .Dimension(Dimension)
    ) counter_top_lvl_systolic_inst (
        .clk(clk),
        .rst(rst),
        .en(en_cntr_systolic),
        .done(done_count_systolic)
    );
    
    // Assign done signals
    assign done_count_top = done_count_systolic;
    assign done_top = done_all_systolic;
    
    // --------------------------------------------------------
    // Matrix Multiplication Control FSM
    // --------------------------------------------------------
    matrix_mult_control #(
        .DW(DW),
        .Dimension(Dimension)
    ) matrix_mult_control_inst (
        .clk(clk),
        .rst(rst_top),
        .start(start_top),
        
        // Counter done signals
        .done_ifmap(done_ifmap_systolic),
        .done_weight(done_weight_systolic),
        .done_count(done_count_systolic),
        
        // Output control
        .output_val(output_val_top),
        .out_new_val(out_new_val_sign),
        
        // Counter enables
        .en_ifmap_counter(en_ifmap_counter_systolic),
        .en_weight_counter(en_weight_counter_systolic),
        
        // Shift register enables (controlled by mode mux)
        .en_shift_reg_ifmap(en_shift_reg_ifmap_control),
        .en_shift_reg_weight(en_shift_reg_weight_control),
        
        // Systolic array control
        .en_cntr(en_cntr_systolic),
        .en_in(en_in_systolic),
        .en_out(en_out_systolic),
        .en_psum(en_psum_systolic),
        
        .ifmaps_sel(ifmaps_sel_systolic),
        .output_val_count(output_val_count_systolic),
        .output_eject_ctrl(output_eject_ctrl_systolic),
        
        // Done signal
        .done_all(done_all_systolic)
    );
    
    // --------------------------------------------------------
    // Address Counters for BRAM Access
    // --------------------------------------------------------
    
    // --------------------------------------------------------
    // Counter 1: Ifmap counter (inputdata address counter)
    // --------------------------------------------------------
    counter_axon_addr_inputdata #(
        .ADDRESS_LENGTH(ADDRESS_LENGTH)
    ) ifmap_counter_inst (
        .clk(clk),
        .rst(ifmap_counter_rst),
        .en(ifmap_counter_en),
        .start_val(ifmap_counter_start_val),
        .end_val(ifmap_counter_end_val),
        .flag_1per16(ifmap_flag_1per16),
        .addr_out(inputdata_addr_out),
        .done(ifmap_counter_done)
    );

    // --------------------------------------------------------
    // Counter 2: Weight counter
    // --------------------------------------------------------
    counter_axon_addr_weight #(
        .ADDRESS_LENGTH(ADDRESS_LENGTH)
    ) weight_counter_inst (
        .clk(clk),
        .rst(weight_counter_rst),
        .rst_min_16(weight_rst_min_16),
        .en(en_weight_counter),
        .start_val(weight_counter_start_val),
        .end_val(weight_counter_end_val),
        .flag_1per16(weight_flag_1per16),
        .addr_out(weight_addr_out),
        .done(weight_counter_done)
    );

    // --------------------------------------------------------
    // Counter 3: Output Counter A (Writing)
    // --------------------------------------------------------
    counter_axon_addr_inputdata #(
        .ADDRESS_LENGTH(ADDRESS_LENGTH)
    ) output_counter_inst_a (
        .clk(clk),
        .rst(output_counter_rst_a),
        .en(en_output_counter_a),
        .start_val(output_counter_start_val_a),
        .end_val(output_counter_end_val_a),
        .flag_1per16(output_flag_1per16_a),
        .addr_out(output_addr_out_a),
        .done(output_counter_done_a)
    );

    // --------------------------------------------------------
    // Counter 4: Output Counter B (Reading)
    // --------------------------------------------------------
    counter_axon_addr_inputdata #(
        .ADDRESS_LENGTH(ADDRESS_LENGTH)
    ) output_counter_inst_b (
        .clk(clk),
        .rst(output_counter_rst_b),
        .en(en_output_counter_b),
        .start_val(output_counter_start_val_b),
        .end_val(output_counter_end_val_b),
        .flag_1per16(output_flag_1per16_b),
        .addr_out(output_addr_out_b),
        .done(output_counter_done_b)
    );

    // --------------------------------------------------------
    // Main Control FSM: onedconv_ctrl
    // --------------------------------------------------------
    onedconv_ctrl #(
        .DW(DW),
        .Dimension(Dimension),
        .ADDRESS_LENGTH(ADDRESS_LENGTH),
        .MUX_SEL_WIDTH(MUX_SEL_WIDTH)
    ) onedconv_ctrl_inst (
        .clk(clk),
        .rst(rst),

        // Global control
        .start_whole(start_whole),
        .done_all(done_all),
        .done_filter(done_filter),
        .weight_req_top(weight_req_top),
        .weight_ack_top(weight_ack_top),

        // Convolution parameters
        .stride(stride),
        .padding(padding),
        .kernel_size(kernel_size),
        .input_channels(input_channels),
        .temporal_length(temporal_length),
        .filter_number(filter_number),

        // Counter status inputs
        .ifmap_counter_done(ifmap_counter_done),
        .ifmap_flag_1per16(ifmap_flag_1per16),

        .weight_counter_done(weight_counter_done),
        .weight_flag_1per16(weight_flag_1per16),

        .output_counter_done_a(output_counter_done_a),
        .output_flag_1per16_a(output_flag_1per16_a),

        .output_counter_done_b(output_counter_done_b),
        .output_flag_1per16_b(output_flag_1per16_b),

        // Datapath status inputs
        .done_count_top(done_count_top),
        .done_top(done_top),
        .out_new_val_sign(out_new_val_sign),

        // Counter control outputs
        .ifmap_counter_en(ifmap_counter_en),
        .ifmap_counter_rst(ifmap_counter_rst),

        .en_weight_counter(en_weight_counter),
        .weight_rst_min_16(weight_rst_min_16),
        .weight_counter_rst(weight_counter_rst),

        .en_output_counter_a(en_output_counter_a),
        .output_counter_rst_a(output_counter_rst_a),

        .en_output_counter_b(en_output_counter_b),
        .output_counter_rst_b(output_counter_rst_b),

        // Counter start/end values
        .ifmap_counter_start_val(ifmap_counter_start_val),
        .ifmap_counter_end_val(ifmap_counter_end_val),

        .weight_counter_start_val(weight_counter_start_val),
        .weight_counter_end_val(weight_counter_end_val),

        .output_counter_start_val_a(output_counter_start_val_a),
        .output_counter_end_val_a(output_counter_end_val_a),

        .output_counter_start_val_b(output_counter_start_val_b),
        .output_counter_end_val_b(output_counter_end_val_b),

        // BRAM control outputs
        .enb_inputdata_input_bram(enb_inputdata_input_bram),
        .enb_weight_input_bram(enb_weight_input_bram),

        .ena_output_result_control(ena_output_result_control),
        .wea_output_result(wea_output_result),
        .enb_output_result_control(enb_output_result_control),

        // Shift-register & datapath control
        .en_shift_reg_ifmap_input_ctrl(en_shift_reg_ifmap_input_ctrl),
        .en_shift_reg_weight_input_ctrl(en_shift_reg_weight_input_ctrl),

        .zero_or_data(zero_or_data),
        .zero_or_data_weight(zero_or_data_weight),
        .sel_input_data_mem(sel_input_data_mem),

        .output_bram_destination(output_bram_destination),

        // Adder-side register control
        .en_reg_adder(en_reg_adder),
        .output_result_reg_rst(output_result_reg_rst),

        // Top-level IO control
        .rst_top(rst_top),
        .mode_top(mode_top),
        .output_val_top(output_val_top),
        .start_top(start_top)
    );

endmodule