// Dibuat untuk sekali Convolution 1D
module onedconv #(
    parameter DW = 16,
    parameter Dimension = 16,
    parameter ADDRESS_LENGTH = 10,
    parameter BRAM_Depth = 512,
    //parameter MAX_COUNT = 512,
    parameter MUX_SEL_WIDTH = 4 // 16 BRAM PADA INPUT//
)
(
    input wire clk,
    input wire rst, 

    input wire start_whole,    // INPUT CONTROL
    // Handshake for weight loading
    output wire weight_req_top,
    input wire weight_ack_top,

    //1D Convolution Parameters for central control unit.
    input wire [1:0] stride, // 0, 1, 2, 3 of stride. INPUT CONTROL
    input wire [2:0] padding,  // LIMITED TO 15. UNSIGNED. INPUT CONTROL
    input wire [4:0] kernel_size, // LIMITED TO 0 to 16. UNSIGNED NUMBER. INPUT CONTROL
    input wire [9:0] input_channels,    //INPUT CONTROL
    input wire [9:0] temporal_length,   //INPUT CONTROL
    input wire [9:0] filter_number,
    // For inputs (i.e. inpudata and weights), writing is done externally 
    // Interfacing with AXI controller
    // External BRAM inputs
    input wire [Dimension-1:0] ena_weight_input_bram,
    input wire [Dimension-1:0] wea_weight_input_bram,

    input wire [Dimension-1:0] ena_inputdata_input_bram,
    input wire [Dimension-1:0] wea_inputdata_input_bram,

    input wire [Dimension-1:0] ena_bias_output_bram,
    input wire [Dimension-1:0] wea_bias_output_bram,

    input wire [ADDRESS_LENGTH-1:0] weight_bram_addr, // FOR EXTERNAL ADDRESSING. Used in input PROCESS
    input wire [ADDRESS_LENGTH-1:0] inputdata_bram_addr, // FOR EXTERNAL ADDRESSING. Used in input PROCESS
    input wire [ADDRESS_LENGTH-1:0] bias_output_bram_addr,

    input wire [DW*Dimension-1:0] weight_input_bram,
    input wire [DW*Dimension-1:0] inputdata_input_bram,
    input wire [DW*Dimension-1:0] bias_output_bram, //Initial datas...
    
    input wire input_bias, // KEEP 0 DURING PROCESS.

    // For outputs, reading can be done externally OR interally, whereas writing is done internally.
    // Done Signals and Output
    input wire read_mode_output_result, //Reading Externally // KEEP 0 DURING PROCESS.
    input wire [Dimension-1:0] enb_output_result,
    input wire [ADDRESS_LENGTH-1:0] output_result_bram_addr, // FOR EXTERNAL ADDRESSING. Used in output PROCESS

    output wire done_all,
    output wire done_filter,
    output wire signed [DW*Dimension-1:0] output_result    
);
    // ...........................................
    // Counter DECLARATION
    // ...........................................
    // ----------------------------------------
    // Counter 1: Ifmap counter
    // ----------------------------------------

    wire ifmap_counter_en;      //OUTPUT CONTROL
    wire ifmap_counter_done;    //INPUT CONTROL
    wire ifmap_flag_1per16;     //INPUT CONTROL
    wire ifmap_counter_rst;     //OUTPUT CONTROL
    wire [ADDRESS_LENGTH-1:0] inputdata_addr_out;
    wire [ADDRESS_LENGTH-1:0] ifmap_counter_start_val; //OUTPUT CONTROL
    wire [ADDRESS_LENGTH-1:0] ifmap_counter_end_val; //OUTPUT CONTROL
    counter_axon_addr_inputdata #(
        .ADDRESS_LENGTH(ADDRESS_LENGTH)
        // .MAX_COUNT(MAX_COUNT)
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

    // ----------------------------------------
    // Counter 2: Weight counter
    // ----------------------------------------
    wire weight_counter_rst; //OUTPUT CONTROL
    wire en_weight_counter;  //OUTPUT CONTROL

    wire weight_flag_1per16; //INPUT CONTROL
    wire weight_counter_done; //INPUT CONTROL
    wire weight_rst_min_16;
    wire [ADDRESS_LENGTH-1:0] weight_addr_out;
    wire [ADDRESS_LENGTH-1:0] weight_counter_start_val; //OUTPUT CONTROL
    wire [ADDRESS_LENGTH-1:0] weight_counter_end_val; //OUTPUT CONTROL

    counter_axon_addr_weight #(
        .ADDRESS_LENGTH(ADDRESS_LENGTH)
        // .MAX_COUNT(MAX_COUNT)
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
    // ----------------------------------------
    // Counter 3: Output Counter (A) WRITING 
    // ----------------------------------------
    wire output_counter_rst_a; //OUTPUT CONTROL
    wire en_output_counter_a; //OUTPUT CONTROL
    wire output_flag_1per16_a; //INPUT CONTROL
    wire output_counter_done_a; //INPUT CONTROL
    wire [ADDRESS_LENGTH-1:0] output_addr_out_a;
    wire [ADDRESS_LENGTH-1:0] output_counter_start_val_a; //OUTPUT CONTROL
    wire [ADDRESS_LENGTH-1:0] output_counter_end_val_a; //OUTPUT CONTROL

    counter_axon_addr_inputdata #(
    .ADDRESS_LENGTH(ADDRESS_LENGTH)
    // .MAX_COUNT(MAX_COUNT)
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
    // ----------------------------------------
    // Counter 3: Output Counter (B) READING
    // ---------------------------------------- 
    wire output_counter_rst_b; //OUTPUT CONTROL
    wire en_output_counter_b; //OUTPUT CONTROL
    wire output_flag_1per16_b; //INPUT CONTROL
    wire output_counter_done_b; //INPUT CONTROL
    wire [ADDRESS_LENGTH-1:0] output_addr_out_b;
    wire [ADDRESS_LENGTH-1:0] output_counter_start_val_b; //OUTPUT CONTROL
    wire [ADDRESS_LENGTH-1:0] output_counter_end_val_b; //OUTPUT CONTROL

    counter_axon_addr_inputdata #(
    .ADDRESS_LENGTH(ADDRESS_LENGTH)
    // .MAX_COUNT(MAX_COUNT)
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
    // ...........................................
    // BRAM DECLARATION AND MUX
    // ...........................................
    // ----------------------------------------
    // INPUT BRAM (ADA 16)
    // ----------------------------------------
    // a is used to write.
    // b is used to read.
    wire zero_or_data_weight;
    wire [Dimension-1:0] enb_inputdata_input_bram; // OUTPUT CONTROL
    wire [Dimension*DW-1:0] dob_inputdata_input_bram; 
    genvar i;
    generate
        for (i = 0; i < Dimension; i = i + 1) begin : gen_inputdata_bram
            simple_dual_two_clocks #(
                .DW(DW),
                .ADDRESS_LENGTH(ADDRESS_LENGTH),
                .DEPTH(BRAM_Depth)
            )
            bram_input
            (
                .clka(clk),
                .clkb(clk),
                .ena(ena_inputdata_input_bram[i]),
                .enb(enb_inputdata_input_bram[i]),
                .wea(wea_inputdata_input_bram[i]),
                .addra(inputdata_bram_addr),
                .addrb(inputdata_addr_out),
                .dia(inputdata_input_bram[DW*(i+1)-1:DW*i]),
                .dob(dob_inputdata_input_bram[DW*(i+1)-1:DW*i])
            );
        end
    endgenerate
    //Zero multiplexer for padding
    wire [DW-1:0] input_data_stream_zero;
    assign input_data_stream_zero = {DW{1'b0}};
    wire [DW-1:0] input_data_stream;
    wire zero_or_data; //OUTPUT CONTROL
    wire [MUX_SEL_WIDTH-1:0] sel_input_data_mem; //OUTPUT CONTROL
    // CORRECT - Need intermediate signal:
    wire [DW-1:0] input_data_stream_from_mux;
    assign input_data_stream = zero_or_data ? input_data_stream_from_mux : input_data_stream_zero;

    // MUX outputs to intermediate signal:
    mux_between_channels #(
        .DW(DW),
        .Inputs(Dimension),
        .Sel_Width(MUX_SEL_WIDTH)
    )
    inputdata_mux_inst (
        .sel(sel_input_data_mem),
        .data_in(dob_inputdata_input_bram),
        .data_out(input_data_stream_from_mux)  // Not input_data_stream!
    );

    // ----------------------------------------
    // WEIGHT BRAMs (ADA 16)
    // ----------------------------------------
    wire [Dimension-1:0] enb_weight_input_bram; // OUTPUT CONTROL
    wire [Dimension*DW-1:0] dob_weight_input_bram; 
    genvar j;
    generate
        for (j = 0; j < Dimension; j = j + 1) begin : gen_weight_bram
            simple_dual_two_clocks #(
                .DW(DW),
                .ADDRESS_LENGTH(ADDRESS_LENGTH),
                .DEPTH(BRAM_Depth)
            )
            bram_filter
            (
                .clka(clk),
                .clkb(clk),
                .ena(ena_weight_input_bram[j]),
                .enb(enb_weight_input_bram[j]),
                .wea(wea_weight_input_bram[j]),
                .addra(weight_bram_addr),
                .addrb(weight_addr_out),
                .dia(weight_input_bram[DW*(j+1)-1:DW*j]),
                .dob(dob_weight_input_bram[DW*(j+1)-1:DW*j])
            );
        end
    endgenerate
    wire [Dimension*DW-1:0] dob_weight_input_bram_zero = {{Dimension*DW}{1'b0}};
    wire [Dimension*DW-1:0] dob_weight_input_bram_choosen;

    assign dob_weight_input_bram_choosen = (zero_or_data_weight)? dob_weight_input_bram : dob_weight_input_bram_zero;

    // ----------------------------------------
    // OUTPUT BRAMs (ADA 16)
    // ----------------------------------------
    wire [Dimension*DW-1:0] systolic_output_after_adder;

    wire [Dimension-1:0] ena_output_result_control;
    wire [Dimension*DW-1:0] dob_output_result_bram;  // Keluaran BRAM.
    wire [Dimension-1:0] enb_output_result_chosen; 
    wire [Dimension-1:0] enb_output_result_control; // OUTPUT CONTROL
    // I advise against doing this. Let us see, though.
    assign enb_output_result_chosen = read_mode_output_result ? enb_output_result : enb_output_result_control; //Control
    //                                  External
    wire [ADDRESS_LENGTH-1:0] output_result_addr_chosen_b; 
    assign output_result_addr_chosen_b = read_mode_output_result ? output_result_bram_addr : output_addr_out_b;
    //                                 External    
    wire [Dimension-1:0] wea_output_result_chosen;
    wire [Dimension-1:0] ena_output_result_chosen;
    
    wire [Dimension-1:0] wea_output_result; // OUTPUT CONTROL
//    input wire [Dimension-1:0] ena_bias_output_bram,
//    input wire [Dimension-1:0] wea_bias_output_bram,
//    input wire [ADDRESS_LENGTH-1:0] bias_output_bram_addr,
//    input wire [DW*Dimension-1:0] bias_output_bram
    wire [ADDRESS_LENGTH-1:0] output_addr_out_a_chosen;
    wire [DW*Dimension-1:0] dia_output_bram_chosen;
    assign wea_output_result_chosen = (input_bias)? wea_bias_output_bram  : wea_output_result;
    assign ena_output_result_chosen = (input_bias)? ena_bias_output_bram  : ena_output_result_control;
    assign output_addr_out_a_chosen = (input_bias)? bias_output_bram_addr : output_addr_out_a;
    assign dia_output_bram_chosen   = (input_bias)? bias_output_bram      : systolic_output_after_adder;
    genvar r;
    generate
        for (r = 0; r < Dimension; r = r + 1) begin : gen_output_result_bram
            simple_dual_two_clocks #(
                .DW(DW),
                .ADDRESS_LENGTH(ADDRESS_LENGTH),
                .DEPTH(BRAM_Depth)
            )
            bram_output
            (
                .clka(clk),
                .clkb(clk),
                .ena(ena_output_result_chosen[r]), // Writing is done internally
                .enb(enb_output_result_chosen[r]), // Reading is done externally
                .wea(wea_output_result_chosen[r]), // Writing is done internally
                .addra(output_addr_out_a_chosen),
                .addrb(output_result_addr_chosen_b),
                .dia(dia_output_bram_chosen[DW*(r+1)-1:DW*r]),
                .dob(dob_output_result_bram[DW*(r+1)-1:DW*r])
            );
        end
    endgenerate
    
    wire [(Dimension*DW)-1:0] systolic_output_before_adder;
    // ----------------------------------------
    // ADD CHANNEL DEMUX
    // ----------------------------------------
    wire output_bram_destination; //CONTROL OUTPUT
    wire [DW*Dimension - 1 : 0] output_result_bram_to_adder;
    // ----------------------------------------
    // Demux + registered top-level output
    // ----------------------------------------
    wire [DW*Dimension-1:0] output_result_bram_to_adder_reg;
    wire en_reg_adder; // CONTROL OUTPUT
    wire output_result_reg_rst; //CONTROL OUTPUT
    reg_en_rst #(
        .WIDTH(DW * Dimension)
    ) output_result_bram_to_adder_reg_inst (
        .clk(clk), 
        .rst(output_result_reg_rst), //Active low reset
        .en(en_reg_adder), // control from FSM
        .d(output_result_bram_to_adder), // D Input
        .q(output_result_bram_to_adder_reg) // Q output
    );
    
    wire [Dimension*DW-1:0] output_result_int;
    reg  [Dimension*DW-1:0] output_result_reg;

    // Demultiplex: either feed adder or external output
    dmux_out #(
        .DW(DW),
        .Dimension(Dimension)
    ) dmux_out_inst (
        .sel(output_bram_destination),
        .in(dob_output_result_bram),
        .out_a(output_result_bram_to_adder),
        .out_b(output_result_int)
    );


    // Register the output before driving top-level pin
    always @(posedge clk) begin
        if (!rst) begin
            output_result_reg <= {Dimension*DW{1'b0}};
        end
        else begin
            output_result_reg <= output_result_int;
        end
    end

    wire out_new_val_sign; // CONTROL INPUT
    wire [(Dimension*DW)-1:0] systolic_output_before_adder_after_reg;
    wire rst_top;   //CONTROL OUTPUT
    reg_en_rst #(
        .WIDTH(DW*Dimension)
    ) output_systolic_reg (
        .clk(clk), 
        .rst(rst_top), //Active low reset
        .en(out_new_val_sign), // control from FSM
        .d(systolic_output_before_adder), // D Input
        .q(systolic_output_before_adder_after_reg) // Q output
    );

    assign output_result = output_result_reg;
    systolic_out_adder #(
        .DW(DW),
        .Dimension(Dimension)
    ) systolic_out_adder_inst(
        .in_a(output_result_bram_to_adder_reg),
        .in_b(systolic_output_before_adder_after_reg),
        .out_val(systolic_output_after_adder)
    );
    wire start_top; //CONTROL OUTPUT
    wire done_top;  //CONTROL OUTPUT 
    wire [Dimension-1 : 0] en_shift_reg_ifmap_input_ctrl; // CONTROL OUTPUT
    wire [Dimension-1 : 0] en_shift_reg_weight_input_ctrl; // CONTROL OUTPUT
    wire output_val_top; //CONTROL INPUT
    wire mode_top; // CONTROL INPUT
    wire done_count_top;
    top_lvl_io_control #(   
         .DW(DW),
         .Dimension(Dimension)
    ) top_lvl_io_control_inst (
         .clk                    (clk),         
         .rst                    (rst_top),         
         .start                  (start_top), 
         .output_val            (output_val_top),
         .weight_brams_in       (dob_weight_input_bram_choosen),
         .ifmap_serial_in        (input_data_stream),

         .en_shift_reg_ifmap_input(en_shift_reg_ifmap_input_ctrl),
         .en_shift_reg_weight_input(en_shift_reg_weight_input_ctrl),

         .mode(mode_top),
         .out_new_val(out_new_val_sign),
         .done_count            (done_count_top),
         .done_all               (done_top), //INPUT CONTROL

         .output_out             (systolic_output_before_adder)
    );
    onedconv_ctrl #(
    .DW(DW),
    .Dimension(Dimension),
    .ADDRESS_LENGTH(ADDRESS_LENGTH),
    .MUX_SEL_WIDTH(MUX_SEL_WIDTH)
    ) onedconv_ctrl_inst (
        .clk(clk),
        .rst(rst),

        // ----------------------------------------------------
        // Global control
        // ----------------------------------------------------
        .start_whole(start_whole),
        .done_all(done_all),
        .done_filter(done_filter),
        .weight_req_top(weight_req_top),
        .weight_ack_top(weight_ack_top),

        // ----------------------------------------------------
        // Convolution parameters
        // ----------------------------------------------------
        .stride(stride),
        .padding(padding),
        .kernel_size(kernel_size),
        .input_channels(input_channels),
        .temporal_length(temporal_length),
        .filter_number(filter_number),

        // ----------------------------------------------------
        // Counter status inputs
        // ----------------------------------------------------
        .ifmap_counter_done(ifmap_counter_done),
        .ifmap_flag_1per16(ifmap_flag_1per16),

        .weight_counter_done(weight_counter_done),
        .weight_flag_1per16(weight_flag_1per16),

        .output_counter_done_a(output_counter_done_a),
        .output_flag_1per16_a(output_flag_1per16_a),

        .output_counter_done_b(output_counter_done_b),
        .output_flag_1per16_b(output_flag_1per16_b),

        // ----------------------------------------------------
        // Datapath status inputs
        // ----------------------------------------------------
        .done_count_top(done_count_top),
        .done_top(done_top),
        .out_new_val_sign(out_new_val_sign),

        // ----------------------------------------------------
        // Counter control outputs
        // ----------------------------------------------------
        .ifmap_counter_en(ifmap_counter_en),
        .ifmap_counter_rst(ifmap_counter_rst),

        .en_weight_counter(en_weight_counter),
        .weight_rst_min_16(weight_rst_min_16),
        .weight_counter_rst(weight_counter_rst),

        .en_output_counter_a(en_output_counter_a),
        .output_counter_rst_a(output_counter_rst_a),

        .en_output_counter_b(en_output_counter_b),
        .output_counter_rst_b(output_counter_rst_b),
        // ----------------------------------------------------
        // Counter control address
        // ----------------------------------------------------

        .ifmap_counter_start_val(ifmap_counter_start_val),
        .ifmap_counter_end_val(ifmap_counter_end_val),

        .weight_counter_start_val(weight_counter_start_val),
        .weight_counter_end_val(weight_counter_end_val),

        .output_counter_start_val_a(output_counter_start_val_a),
        .output_counter_end_val_a(output_counter_end_val_a),

        .output_counter_start_val_b(output_counter_start_val_b),
        .output_counter_end_val_b(output_counter_end_val_b),
        // ----------------------------------------------------
        // BRAM control outputs
        // ----------------------------------------------------
        .enb_inputdata_input_bram(enb_inputdata_input_bram),
        .enb_weight_input_bram(enb_weight_input_bram),

        .ena_output_result_control(ena_output_result_control),
        .wea_output_result(wea_output_result),
        .enb_output_result_control(enb_output_result_control),

        // ----------------------------------------------------
        // Shift-register & datapath control
        // ----------------------------------------------------
        .en_shift_reg_ifmap_input_ctrl(en_shift_reg_ifmap_input_ctrl),
        .en_shift_reg_weight_input_ctrl(en_shift_reg_weight_input_ctrl),

        .zero_or_data(zero_or_data),
        .zero_or_data_weight(zero_or_data_weight),
        .sel_input_data_mem(sel_input_data_mem),

        .output_bram_destination(output_bram_destination),

        // ----------------------------------------------------
        // Adder-side register control
        // ----------------------------------------------------
        .en_reg_adder(en_reg_adder),
        .output_result_reg_rst(output_result_reg_rst),

        // ----------------------------------------------------
        // Top-level IO control
        // ----------------------------------------------------
        .rst_top(rst_top),
        .mode_top(mode_top),
        .output_val_top(output_val_top),
        .start_top(start_top)
    );

endmodule