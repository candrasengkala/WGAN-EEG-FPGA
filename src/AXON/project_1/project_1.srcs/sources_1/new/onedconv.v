// Dibuat untuk sekali Convolution 1D

module onedconv #(
    parameter DW = 16,
    parameter Dimension = 16,
    parameter ADDRESS_LENGTH = 13,
    parameter BRAM_Depth = 8192,
    parameter MAX_COUNT = 512,
    parameter MUX_SEL_WIDTH = 4 // 16 BRAM PADA INPUT//
)
(
    input wire clk,
    input wire rst, 

    input wire start_whole,    
    //1D Convolution Parameters for central control unit.
    input wire stride, // 1 bit is enough for stride 1 and 2
    input wire padding,  // 1 bit is enough for padding of 7 (0) and 3 (1)
    input wire kernel_size, // 1 bit is enough for kernel size 16 (0) and 7 (1)
    input wire [2:0] input_channels, //1 input channel (000), 32 input channels (001), 64 input channels (010), 128 input channels (100), 256 input channels (111).
    input wire [2:0] temporal_length, // Temporal length of input data.
    // For inputs (i.e. inpudata and weights), writing is done externally 
    // Interfacing with AXI controller
    // External BRAM inputs
    input wire [Dimension-1:0] ena_weight_input_bram,
    input wire [Dimension-1:0] wea_weight_input_bram,

    input wire [Dimension-1:0] ena_inputdata_input_bram,
    input wire [Dimension-1:0] wea_inputdata_input_bram,

    input wire [ADDRESS_LENGTH-1:0] weight_bram_addr, // FOR EXTERNAL ADDRESSING. Used in input PROCESS
    input wire [ADDRESS_LENGTH-1:0] inputdata_bram_addr, // FOR EXTERNAL ADDRESSING. Used in input PROCESS

    input wire [DW*Dimension-1:0] weight_input_bram,
    input wire [DW*Dimension-1:0] inputdata_input_bram,
    // For outputs, reading can be done externally OR interally, whereas writing is done internally.
    // Done Signals and Output
    input wire read_mode_output_result, //Reading Externally
    input wire [Dimension-1:0] enb_output_result,
    input wire [ADDRESS_LENGTH-1:0] output_result_bram_addr, // FOR EXTERNAL ADDRESSING. Used in output PROCESS

    output wire done_all,
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

    counter_axon_addr #(
        .ADDRESS_LENGTH(ADDRESS_LENGTH),
        .MAX_COUNT(MAX_COUNT)
    ) ifmap_counter_inst (
        .clk(clk),
        .rst(ifmap_counter_rst),
        .en(ifmap_counter_en),
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
    wire [ADDRESS_LENGTH-1:0] weight_addr_out;

    counter_axon_addr #(
        .ADDRESS_LENGTH(ADDRESS_LENGTH),
        .MAX_COUNT(MAX_COUNT)
    ) weight_counter_inst (
        .clk(clk),
        .rst(weight_counter_rst),
        .en(en_weight_counter),
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
    counter_axon_addr #(
    .ADDRESS_LENGTH(ADDRESS_LENGTH),
    .MAX_COUNT(MAX_COUNT)
    ) output_counter_inst_a (
        .clk(clk),
        .rst(output_counter_rst_a),
        .en(en_output_counter_a),
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
    counter_axon_addr #(
    .ADDRESS_LENGTH(ADDRESS_LENGTH),
    .MAX_COUNT(MAX_COUNT)
    ) output_counter_inst_b (
        .clk(clk),
        .rst(output_counter_rst_b),
        .en(en_output_counter_b),
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
    wire [Dimension-1:0] enb_inputdata_input_bram; // OUTPUT CONTROL
    wire [Dimension*DW-1:0] dob_inputdata_input_bram; 
    genvar i;
    generate
        for (i = 0; i < Dimension; i = i + 1) begin : gen_inputdata_bram
            simple_dual_two_clocks #(
                .DW(DW),
                .ADDRESS_LENGTH(ADDRESS_LENGTH),
                .DEPTH(BRAM_Depth)
            )(
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
    wire [DW-1:0] input_data_stream_memory; 
    wire [DW-1:0] input_data_stream_zero;
    assign input_data_stream_zero = {DW{1'b0}};
    wire [DW-1:0] input_data_stream;
    wire zero_or_data; //OUTPUT CONTROL
    wire [MUX_SEL_WIDTH-1:0] sel_input_data_mem;
    assign input_data_stream = zero_or_data ? input_data_stream_memory : input_data_stream_zero;
    //MUX for selecting input data from multiple BRAMs
    wire [DW-1:0] sel_input_data_stream;
    mux_between_channels #(
        .DW(DW),
        .Inputs(Dimension),
        .Sel_Width(MUX_SEL_WIDTH)
    ) inputdata_mux_inst (
        .sel(sel_input_data_mem),
        .in_data(dob_inputdata_input_bram),
        .out_data(input_data_stream)
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
            )(
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
    // ----------------------------------------
    // OUTPUT BRAMs (ADA 16)
    // ----------------------------------------
    wire [Dimension*DW-1:0] systolic_output_after_adder;

    wire [Dimension-1:0] ena_output_result_control;
    wire [Dimension*DW-1:0] dob_output_result_bram;  // Keluaran BRAM.
    wire [Dimension-1:0] enb_output_result_chosen; 
    wire [Dimension-1:0] enb_output_result_control; // OUTPUT CONTROL
    assign enb_output_result_chosen = read_mode_output_result ? enb_output_result : enb_output_result_control; //Control
    //                                  External
    wire [ADDRESS_LENGTH-1:0] output_result_addr_chosen_b; 
    assign output_result_addr_chosen_b = read_mode_output_result ? output_result_bram_addr : output_addr_out_b;
    //                                  External    
    wire [Dimension-1:0] wea_output_result; // OUTPUT CONTROL
    genvar r;
    generate
        for (r = 0; r < Dimension; r = r + 1) begin : gen_output_result_bram
            simple_dual_two_clocks #(
                .DW(DW),
                .ADDRESS_LENGTH(ADDRESS_LENGTH),
                .DEPTH(BRAM_Depth)
            )(
                .clka(clk),
                .clkb(clk),
                .ena(ena_output_result_control[r]), // Writing is done internally
                .enb(enb_output_result_chosen[r]), // Reading is done externally
                .wea(wea_output_result[r]), // Writing is done internally
                .addra(output_addr_out_a),
                .addrb(output_result_addr_chosen_b),
                .dia(systolic_output_after_adder[DW*(r+1)-1:DW*r]),
                .dob(dob_output_result_bram[DW*(r+1)-1:DW*r])
            );
        end
    endgenerate
    
    wire [Dimension*DW-1:0] systolic_output_before_adder;
    // ----------------------------------------
    // ADD CHANNEL DEMUX
    // ----------------------------------------
    wire output_bram_destination; //CONTROL OUTPUT
    wire [DW*Dimension - 1 : 0] output_result_bram_to_adder;
    // ----------------------------------------
    // Demux + registered top-level output
    // ----------------------------------------

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
        if (rst) begin
            output_result_reg <= {Dimension*DW{1'b0}};
        end
        else begin
            output_result_reg <= output_result_int;
        end
    end

    assign output_result = output_result_reg;
    systolic_out_adder #(
        .DW(DW),
        .Dimension(Dimension)
    ) systolic_out_adder_inst(
        .in_a(output_result_bram_to_adder),
        .in_b(systolic_output_before_adder),
        .out_val(systolic_output_after_adder)
    );
    wire rst_top;   //CONTROL OUTPUT
    wire start_top; //CONTROL OUTPUT
    wire done_top;  //CONTROL OUTPUT 
    top_lvl_io_control #(   
         .DW(DW),
         .Dimension(Dimension)
    ) top_lvl_io_control_inst (
         .clk                    (clk),         
         .rst                    (rst_top),         //OUTPUT CONTROL
         .start                  (start_top), //OUTPUT CONTROL

         .weight_brams_in       (dob_weight_input_bram),
         .ifmap_serial_in        (input_data_stream),

         .done_all               (done_top), //INPUT CONTROL

         .output_out             (systolic_output_before_adder)
    );
endmodule