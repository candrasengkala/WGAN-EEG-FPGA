// ============================================================
// 1D Convolution Control FSM - Simplified
// Single-run controller (once per convolution)
// ============================================================
module onedconv_ctrl #(
    parameter DW = 16,
    parameter Dimension = 16,
    parameter ADDRESS_LENGTH = 9,
    parameter MUX_SEL_WIDTH = 4
)(
    input  wire clk,
    input  wire rst,
    // --------------------------------------------------------
    // Global control
    // --------------------------------------------------------
    input  wire start_whole,
    output reg  done_all,
    // --------------------------------------------------------
    // Convolution parameters (static during run)
    // --------------------------------------------------------
    input  wire [1:0] stride,
    input  wire [2:0] padding,
    input  wire [4:0] kernel_size,
    input  wire [9:0] input_channels,
    input  wire [9:0] filter_number,
    input  wire [9:0] temporal_length,
    // --------------------------------------------------------
    // Counter status inputs
    // --------------------------------------------------------
    input  wire ifmap_counter_done,
    input  wire ifmap_flag_1per16,

    input  wire weight_counter_done,
    input  wire weight_flag_1per16,

    input  wire output_counter_done_a,
    input  wire output_flag_1per16_a,

    input  wire output_counter_done_b,
    input  wire output_flag_1per16_b,

    // --------------------------------------------------------
    // Datapath status inputs
    // --------------------------------------------------------
    input  wire done_count_top,
    input  wire done_top,
    input  wire out_new_val_sign,
    // --------------------------------------------------------
    // Counter control outputs
    // --------------------------------------------------------
    output wire ifmap_counter_en,
    output reg  ifmap_counter_rst,

    output wire en_weight_counter,
    output reg  weight_rst_min_16,
    output reg  weight_counter_rst,

    output wire en_output_counter_a,
    output reg  output_counter_rst_a,

    output wire en_output_counter_b,
    output reg  output_counter_rst_b,
    // --------------------------------------------------------
    // Counter start end val
    // --------------------------------------------------------
    output reg [ADDRESS_LENGTH-1:0] ifmap_counter_start_val = 0,
    output reg [ADDRESS_LENGTH-1:0] ifmap_counter_end_val = 0,

    output reg [ADDRESS_LENGTH-1:0] weight_counter_start_val = 0,
    output reg [ADDRESS_LENGTH-1:0] weight_counter_end_val  = 0,

    output reg [ADDRESS_LENGTH-1:0] output_counter_start_val_a = 0,
    output reg [ADDRESS_LENGTH-1:0] output_counter_end_val_a = 0,

    output reg [ADDRESS_LENGTH-1:0] output_counter_start_val_b = 0,
    output reg [ADDRESS_LENGTH-1:0] output_counter_end_val_b = 0,
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
    output reg  [MUX_SEL_WIDTH-1:0] sel_input_data_mem = 0,

    output reg  output_bram_destination,

    // --------------------------------------------------------
    // Adder-side register control
    // --------------------------------------------------------
    output wire en_reg_adder,
    output reg output_result_reg_rst,

    // --------------------------------------------------------
    // Top-level IO control
    // --------------------------------------------------------
    output reg  rst_top,
    output reg  mode_top,
    output reg  output_val_top,
    output reg  start_top
);
    // --------------------------------------------------------
    // State encoding - SIMPLIFIED (10 states instead of 15)
    // --------------------------------------------------------
    localparam S_IDLE                     = 5'd0;
    localparam S_PICK_INPUT_LAYER_INIT    = 5'd1;
    localparam S_LOAD_INITIAL             = 5'd2;
    localparam S_RUN                      = 5'd3;
    localparam S_RESTART_MICROSEQUENCER   = 5'd4;
    localparam S_OUTPUT_VAL               = 5'd5;
    localparam S_CHECK_COUNTER            = 5'd6; //
    localparam S_CHANGE_INPUT_CHANNEL     = 5'd7; //
    localparam S_CHANGE_FILTER            = 5'd8; //
    localparam S_DONE                     = 5'd9;
    localparam S_RESET_OUTPUT             = 5'd10;
    localparam S_WAIT_SETTLE              = 5'd11;
    localparam S_CHECK_COUNTER_INCREMENT = 5'd12;
    localparam S_CHANGE_INPUT_CHANNEL_INCREMENT = 5'd13;
    localparam S_CHANGE_FILTER_INCREMENT    = 5'd14;
    localparam S_RESTART_WAIT_DONE = 5'd15;
    localparam S_PICK_INPUT_LAYER_INIT_SET_ADDRESS    = 5'd16;
    localparam S_RESTART_MICROSEQUENCER_SET_ADDRESS   = 5'd17;
    localparam S_PRE_RESTART_MICROSEQUENCER = 5'd18;

    
    reg [4:0] state, next_state;

    // --------------------------------------------------------
    // MICRO SEQUENCER (FOR INPUT BRAM SIDE)
    // --------------------------------------------------------
    reg rst_inputmicrosequencer;
    reg en_inputmicrosequencer;
    wire done_inputmicrosequencer;
    reg restart_inputmicrosequencer;
    
    input_microsequencer #(
        .DW(DW),
        .Dimension(Dimension)
    ) input_microsequencer_inst (
        .clk(clk),
        .rst(rst_inputmicrosequencer),
        .en(en_inputmicrosequencer),
        .restart(restart_inputmicrosequencer),
        .stride(stride),
        .padding(padding),
        .kernel_size(kernel_size),
        .temporal_length(temporal_length),
        .ifmap_counter_done(ifmap_counter_done),
        .ifmap_flag_1per16(ifmap_flag_1per16),
        .counter_bram_en(ifmap_counter_en),
        .en_shift_reg(en_shift_reg_ifmap_input_ctrl),
        .enb_inputdata_input_bram(enb_inputdata_input_bram),
        .zero_or_data(zero_or_data),
        .done(done_inputmicrosequencer)
    );

    // --------------------------------------------------------
    // MICRO SEQUENCER (FOR FILTER BRAM SIDE)
    // --------------------------------------------------------
    reg rst_filtermicrosequencer;
    reg en_filtermicrosequencer;
    wire done_filtermicrosequencer;
    reg restart_filtermicrosequencer;

    filter_microsequencer #(
        .DW(DW),
        .Dimension(Dimension)
    ) filter_microsequencer_inst (
        .clk(clk),
        .rst(rst_filtermicrosequencer),
        .en(en_filtermicrosequencer), 
        .restart(restart_filtermicrosequencer),
        .kernel_size(kernel_size),
        .weight_counter_done(weight_counter_done),
        .weight_flag_1per16(weight_flag_1per16),
        .en_weight_counter(en_weight_counter),
        .enb_weight_input_bram(enb_weight_input_bram),
        .en_shift_reg_weight_input_ctrl(en_shift_reg_weight_input_ctrl),
        .zero_or_data_weight(zero_or_data_weight),
        .done(done_filtermicrosequencer)
    );

    // --------------------------------------------------------
    // MICRO SEQUENCER (FOR OUTPUT BRAM SIDE)
    // --------------------------------------------------------
    reg rst_outputmicrosequencer;
    reg en_outputmicrosequencer;
    wire done_outputmicrosequencer;

    reg [Dimension-1 : 0] wea_output_result_central;
    reg [Dimension-1 : 0] ena_output_result_control_central;

    wire [Dimension-1 : 0] wea_output_result_microsequencer;
    wire [Dimension-1 : 0] ena_output_result_control_microsequencer;

    reg en_output_counter_a_central;
    wire en_output_counter_a_microsequencer;
    output_microsequencer #(
        .DW(DW),
        .Dimension(Dimension)
    ) output_microsequencer_inst (
        .clk(clk),
        .rst(rst_outputmicrosequencer),
        .en(en_outputmicrosequencer),
        .out_new_val_sign(out_new_val_sign),
        .output_counter_done_a(output_counter_done_a),
        .output_flag_1per16_a(output_flag_1per16_a),
        .output_counter_done_b(output_counter_done_b),
        .output_flag_1per16_b(output_flag_1per16_b),
        .en_output_counter_a(en_output_counter_a_microsequencer),
        .en_output_counter_b(en_output_counter_b),
        .ena_output_result_control(ena_output_result_control_microsequencer),
        .wea_output_result(wea_output_result_microsequencer),
        .enb_output_result_control(enb_output_result_control),
        .en_reg_adder(en_reg_adder),
        // .output_result_reg_rst(output_result_reg_rst),
        .done(done_outputmicrosequencer)
    );
    
    reg mux_reset_output;
    assign wea_output_result = mux_reset_output? wea_output_result_central : wea_output_result_microsequencer;
    assign ena_output_result_control = mux_reset_output? ena_output_result_control_central : ena_output_result_control_microsequencer;
    assign en_output_counter_a = mux_reset_output? en_output_counter_a_central : en_output_counter_a_microsequencer;

    // --------------------------------------------------------
    // Counters
    // --------------------------------------------------------
    reg [9:0] input_channel_count;
    reg [9:0] filter_number_count;
    reg [9:0] needed_amount_count;

    // --------------------------------------------------------
    // Output length calculation
    // --------------------------------------------------------
    wire [11:0] numerator;
    wire [11:0] output_length;
    wire [11:0] needed_amount;
    wire [2:0] stride_val;

    assign stride_val = (stride == 2'd0) ? 3'd1 : {1'b0, stride};
    assign numerator = (temporal_length + (padding << 1) >= kernel_size) ?
                       (temporal_length + (padding << 1) - kernel_size) : 12'd0;
    assign output_length = (numerator / stride_val) + 1;
    assign needed_amount = (output_length + Dimension - 1) / Dimension;


    // --------------------------------------------------------
    // Helper wires for addressing
    // --------------------------------------------------------
    // INPUT ADDRESSING
    // Channel 0-15  → BRAM 0-15, address 0 to temporal_length-1
    // Channel 16-31 → BRAM 0-15, address temporal_length to 2*temporal_length-1
    wire [3:0] input_bram_index;
    wire [9:0] input_slot;
    wire [ADDRESS_LENGTH-1:0] base_addr_ifmap;
    
    assign input_bram_index = input_channel_count[3:0];
    assign input_slot = input_channel_count >> 4;
    assign base_addr_ifmap = input_slot * temporal_length;

    // WEIGHT ADDRESSING
    // BRAM[f % 16] stores filter f
    // Filter 0-15   → BRAM 0-15, address 0
    // Filter 16-31  → BRAM 0-15, address (input_channels * kernel_size)
    // Within each filter: weights for all input channels stored sequentially
    wire [3:0] filter_bram_index;
    wire [9:0] filter_slot;
    wire [ADDRESS_LENGTH-1:0] filter_base_addr;
    wire [ADDRESS_LENGTH-1:0] base_addr_weight;
    //EACH CONVOLUTION PROCESS IS 16 IFMAPS by 16 FILTERS.
    //FILTERS ARE ADDRESSED DIFFERENTLY THAN IFMAPS AND OUTPUTS. 
    // assign filter_bram_index = filter_number_count[3:0];
    // assign filter_slot = filter_number_count >> 4;
    // assign filter_base_addr = filter_slot * (input_channels * kernel_size);
    // assign base_addr_weight = filter_number_count * kernel_size;//(input_channel_count * kernel_size);
// Correct: Offsets by input channel
    assign base_addr_weight = (filter_number_count * input_channels * kernel_size) + 
                            (input_channel_count * kernel_size);
    wire [11:0] needed_amount_weight;
    assign needed_amount_weight = (filter_number + Dimension - 1) / Dimension;
    // OUTPUT ADDRESSING
    // Similar to input and weight: 16 BRAMs, stacked storage
    // Filter 0-15   → BRAM 0-15, address 0
    // Filter 16-31  → BRAM 0-15, address output_length
    wire [3:0] output_bram_index;
    wire [9:0] output_slot;
    wire [ADDRESS_LENGTH-1:0] base_addr_output;
    
    // assign output_bram_index = filter_number_count[3:0];
    // assign output_slot = filter_number_count >> 4;
    assign base_addr_output = filter_number_count*output_length;

    // --------------------------------------------------------
    // State register
    // --------------------------------------------------------
    always @(posedge clk or negedge rst) begin
        if (!rst)
            state <= S_IDLE;
        else
            state <= next_state;
    end

    // --------------------------------------------------------
    // Next-state logic - SIMPLIFIED
    // --------------------------------------------------------
    always @(*) begin
        next_state = state;
        
        case (state)
            S_IDLE: begin
                if (start_whole)
                    next_state = S_PICK_INPUT_LAYER_INIT_SET_ADDRESS;
            end
            S_RESET_OUTPUT: begin
                if (output_counter_done_a) next_state = S_PICK_INPUT_LAYER_INIT_SET_ADDRESS;
            end
            S_PICK_INPUT_LAYER_INIT_SET_ADDRESS: begin
                next_state = S_PICK_INPUT_LAYER_INIT;
            end
            S_PICK_INPUT_LAYER_INIT: begin
                next_state = S_WAIT_SETTLE;
            end
            S_WAIT_SETTLE: begin
                next_state = S_LOAD_INITIAL;
            end

            S_LOAD_INITIAL: begin
                if (done_inputmicrosequencer && done_filtermicrosequencer)
                    next_state = S_RUN;
            end

            S_RUN: begin
                if (done_count_top)
                    next_state = S_OUTPUT_VAL;
            end
            S_RESTART_MICROSEQUENCER_SET_ADDRESS: begin
                next_state = S_PRE_RESTART_MICROSEQUENCER;
            end
            S_PRE_RESTART_MICROSEQUENCER: begin
                next_state = S_RESTART_MICROSEQUENCER;
            end
            S_RESTART_MICROSEQUENCER: begin
                next_state = S_RESTART_WAIT_DONE;
            end
            S_RESTART_WAIT_DONE: begin
                if (done_inputmicrosequencer && done_filtermicrosequencer) next_state = S_RUN;
            end

            S_OUTPUT_VAL: begin
                if (done_outputmicrosequencer)
                    next_state = S_CHECK_COUNTER_INCREMENT;
            end
            S_CHECK_COUNTER_INCREMENT: begin
                next_state = S_CHECK_COUNTER;
            end

            S_CHECK_COUNTER: begin
                // Check if we need more iterations for current input channel
                if (needed_amount_count < needed_amount)
                    next_state = S_RESTART_MICROSEQUENCER_SET_ADDRESS;
                else
                    next_state = S_CHANGE_INPUT_CHANNEL_INCREMENT;
            end
            S_CHANGE_INPUT_CHANNEL_INCREMENT: begin
                next_state = S_CHANGE_INPUT_CHANNEL;
            end
            S_CHANGE_INPUT_CHANNEL: begin
                // Check if we need to process more input channels
                if (input_channel_count < input_channels)
                    next_state = S_PICK_INPUT_LAYER_INIT_SET_ADDRESS;
                else
                    next_state = S_CHANGE_FILTER_INCREMENT;
            end
            S_CHANGE_FILTER_INCREMENT: begin
                next_state = S_CHANGE_FILTER;
            end
            S_CHANGE_FILTER: begin
                // Check if we need to process more filters
                if (filter_number_count < needed_amount_weight)
                    next_state = S_PICK_INPUT_LAYER_INIT_SET_ADDRESS;
                else
                    next_state = S_DONE;
            end

            S_DONE: begin
                next_state = S_IDLE;
            end

            default: begin
                next_state = S_IDLE;
            end
        endcase
    end

    // --------------------------------------------------------
    // Output logic - SIMPLIFIED
    // --------------------------------------------------------
    always @(*) begin
        // Default values
        done_all = 1'b0;
        rst_top = 1'b1;
        mode_top = 1'b0;
        output_val_top = 1'b0;
        start_top = 1'b0;
        
        ifmap_counter_rst = 1'b1;
        weight_counter_rst = 1'b1;
        output_counter_rst_a = 1'b1;
        output_counter_rst_b = 1'b1;
        weight_rst_min_16 = 1'b0;
        
        output_bram_destination = 1'b0;
        
        rst_inputmicrosequencer = 1'b1; 
        en_inputmicrosequencer = 1'b0;
        restart_inputmicrosequencer = 1'b0;
        
        rst_filtermicrosequencer = 1'b1;
        en_filtermicrosequencer = 1'b0;
        restart_filtermicrosequencer = 1'b0;
        
        rst_outputmicrosequencer = 1'b1;
        en_outputmicrosequencer = 1'b0;

        output_result_reg_rst = 1'b1;
        
        mux_reset_output = 0;
        wea_output_result_central = 0;
        ena_output_result_control_central = 0;
        en_output_counter_a_central = 0;

        case (state)
            S_IDLE: begin
                rst_top = 1'b0;
                output_bram_destination = 1'b1;  // Route to external output
                ifmap_counter_rst = 1'b0;
                weight_counter_rst = 1'b0;
                output_counter_rst_a = 1'b0;
                output_counter_rst_b = 1'b0;
                rst_inputmicrosequencer = 1'b0;
                rst_filtermicrosequencer = 1'b0;
                rst_outputmicrosequencer = 1'b0;
                output_result_reg_rst = 1'b0;
            end
            S_RESET_OUTPUT: begin
                mux_reset_output = 1;
                wea_output_result_central = {Dimension{1'b1}};
                ena_output_result_control_central = {Dimension{1'b1}};
                en_output_counter_a_central = 1;
            end
            S_PICK_INPUT_LAYER_INIT_SET_ADDRESS: begin
                
            end
            S_PICK_INPUT_LAYER_INIT: begin
                // Reset all microsequencers and counters for new channel/filter
                output_result_reg_rst = 1'b0;
                rst_top = 1'b0;
                rst_inputmicrosequencer = 1'b0;
                rst_filtermicrosequencer = 1'b0;
                rst_outputmicrosequencer = 1'b0;
                weight_counter_rst = 1'b0;
                output_counter_rst_a = 1'b0;
                output_counter_rst_b = 1'b0;
                ifmap_counter_rst = 1'b0;
            end
            S_WAIT_SETTLE: begin
                
            end
            S_LOAD_INITIAL: begin
                mode_top = 1'b0;
                en_inputmicrosequencer = 1'b1;
                en_filtermicrosequencer = 1'b1;
            end

            S_RUN: begin
                start_top = 1'b1;
                mode_top = 1'b1;
            end
            S_PRE_RESTART_MICROSEQUENCER: begin
                ifmap_counter_rst = 1'b0;
                rst_outputmicrosequencer = 1'b0;  // Reset output microsequencer
                weight_counter_rst = 1'b0;  // Reset weight counter for next iteration
            end
            S_RESTART_MICROSEQUENCER: begin
                restart_inputmicrosequencer = 1'b1;
                restart_filtermicrosequencer = 1'b1;
                mode_top = 1'b0;
            end
            S_RESTART_WAIT_DONE: begin
                mode_top = 1'b0;
            end

            S_OUTPUT_VAL: begin
                en_outputmicrosequencer = 1'b1;
                output_val_top = 1'b1;
                output_bram_destination = 1'b0;  // Route to adder for accumulation
            end

            S_CHECK_COUNTER: begin
                rst_top = 1'b0;
                // Counter increment happens in sequential block
            end

            S_CHANGE_INPUT_CHANNEL: begin
                // Counter increment happens in sequential block
            end

            S_CHANGE_FILTER: begin
                // Counter increment happens in sequential block
            end

            S_DONE: begin
                done_all = 1'b1;
                output_bram_destination = 1'b1;  // Route to external output
            end

            default: begin
                // Safe defaults already set
            end
        endcase
    end
    // --------------------------------------------------------
    // ADDRESSES
    // --------------------------------------------------------
    wire [5:0] overlap;
        assign overlap = (kernel_size) / stride_val;

    always @(posedge clk or negedge rst) begin
        if(!rst) begin
            ifmap_counter_start_val = {ADDRESS_LENGTH{1'b0}};
            ifmap_counter_end_val = temporal_length - 1;
            weight_counter_start_val = {ADDRESS_LENGTH{1'b0}};
            weight_counter_end_val = kernel_size - 1;
            output_counter_start_val_a = {ADDRESS_LENGTH{1'b0}};
            output_counter_end_val_a = output_length - 1;
            output_counter_start_val_b = {ADDRESS_LENGTH{1'b0}};
            output_counter_end_val_b = output_length - 1;
            sel_input_data_mem = {MUX_SEL_WIDTH{1'b0}};
        end
        else begin
            case (state) 
                S_PICK_INPUT_LAYER_INIT_SET_ADDRESS: begin
                                    // Select input BRAM based on channel
                sel_input_data_mem = input_bram_index;
                // Set address ranges
                ifmap_counter_start_val = base_addr_ifmap[ADDRESS_LENGTH-1:0];
                ifmap_counter_end_val = (base_addr_ifmap + temporal_length - 1);
                
                weight_counter_start_val = base_addr_weight[ADDRESS_LENGTH-1:0];
                weight_counter_end_val = (base_addr_weight + kernel_size - 1);

                output_counter_start_val_a = base_addr_output[ADDRESS_LENGTH-1:0];
                output_counter_end_val_a = (base_addr_output + output_length - 1);
                
                output_counter_start_val_b = base_addr_output[ADDRESS_LENGTH-1:0];
                output_counter_end_val_b = (base_addr_output + output_length - 1);
                end
                S_RESET_OUTPUT: begin
                    output_counter_start_val_a = 0;
                    output_counter_end_val_a = {ADDRESS_LENGTH{1'b1}};
                end
                S_RESTART_MICROSEQUENCER_SET_ADDRESS: begin
                    ifmap_counter_start_val = base_addr_ifmap[ADDRESS_LENGTH-1:0] + stride_val*(needed_amount_count*Dimension - 1);
                    ifmap_counter_end_val = (base_addr_ifmap + temporal_length - 1);
                end
            endcase
        end
    end
    // --------------------------------------------------------
    // Sequential counter updates - SIMPLIFIED
    // --------------------------------------------------------
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            input_channel_count <= 10'd0;
            filter_number_count <= 10'd0;
            needed_amount_count <= 10'd0;
        end
        else begin
            case (state)
                S_IDLE: begin
                    if (start_whole) begin
                        input_channel_count <= 10'd0;
                        filter_number_count <= 10'd0;
                        needed_amount_count <= 10'd0;
                    end
                end

                S_CHECK_COUNTER_INCREMENT: begin
                    // Increment counter for next iteration
                    needed_amount_count <= needed_amount_count + 1;
                end

                S_CHANGE_INPUT_CHANNEL_INCREMENT: begin
                    input_channel_count <= input_channel_count + 1;
                    needed_amount_count <= 10'd0;  // Reset for next channel
                end

                S_CHANGE_FILTER_INCREMENT: begin
                    filter_number_count <= filter_number_count + 1;
                    input_channel_count <= 10'd0;  // Reset for next filter
                end
            endcase
        end
    end

endmodule