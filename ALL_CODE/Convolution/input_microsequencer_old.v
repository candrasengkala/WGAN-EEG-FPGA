`timescale 1ns/1ps

module input_microsequencer #(
    parameter DW = 16,
    parameter Dimension = 16
)(
    input  wire clk,
    input  wire rst,
    input  wire en,
    input  wire restart,

    // Parameters
    input  wire [1:0] stride,
    input  wire [2:0] padding,
    input  wire [4:0] kernel_size,
    input  wire [9:0] temporal_length,

    // Datapath status
    input  wire ifmap_counter_done,
    input  wire ifmap_flag_1per16,

    // Outputs to datapath
    output reg  counter_bram_en,
    output wire  [Dimension-1:0] en_shift_reg,
    output reg  [Dimension-1:0] enb_inputdata_input_bram,
    output reg  zero_or_data,

    // Output to FSM
    output reg  done
);

    // ============================================================
    // FSM
    // ============================================================
    reg [3:0] state, next_state;

    localparam IDLE         = 4'd0;
    localparam INIT         = 4'd1;
    localparam STREAMING    = 4'd2;
    localparam FLUSH        = 4'd3;
    localparam COMPLETE     = 4'd4;
    localparam FILL_ZERO    = 4'd5;


    // ============================================================
    // Counters & registers
    // ============================================================
    reg [4:0] padding_head_count;
    reg [4:0] padding_tail_count;
    reg [1:0] stride_count;
    reg [9:0] N_in_count;
    reg signed [Dimension-1 : 0] fill_zero_count = 0;

    reg [2*Dimension-1:0] en_shift_reg_ifmap_input_shadow;

    // ============================================================
    // Derived parameters
    // ============================================================
    wire [2:0] stride_val;
    assign stride_val = (stride == 2'd0) ? 3'd1 : {1'b0, stride};

    wire [9:0] N_in;
    assign N_in = (Dimension - 1) * stride_val + kernel_size;

    // Number of active taps per output window
    wire [5:0] overlap;
    // assign overlap = (kernel_size + stride_val - 1) / stride_val;
    assign overlap = (kernel_size) / stride_val;
    // Active BRAM mask (kernel_size wide)
    reg [Dimension-1:0] shift_reg_mask;
    integer i;

    always @(*) begin
        shift_reg_mask = {Dimension{1'b0}};
        for (i = 0; i < kernel_size; i = i + 1)
            shift_reg_mask[i] = 1'b1;
    end

    // ============================================================
    // FIXED: shadow enable generator (runtime-safe)
    // ============================================================
    integer j;
    reg [2*Dimension-1:0] shadow_init;

    always @(*) begin
        shadow_init = {2*Dimension{1'b0}};
        for (j = 0; j < overlap; j = j + 1)
            shadow_init[Dimension-j] = 1'b1;
    end

    // ============================================================
    // FSM state register
    // ============================================================
    always @(posedge clk or negedge rst) begin
        if (!rst)
            state <= IDLE;
        else
            state <= next_state;
    end

    // ============================================================
    // FSM next-state logic
    // ============================================================
    always @(*) begin
        next_state = state;
        case (state)
            IDLE:       if (en) next_state = INIT;
            INIT:               next_state = STREAMING;
            STREAMING: if (N_in_count >= N_in) next_state = FILL_ZERO;
            FILL_ZERO: if (fill_zero_count >= $signed((Dimension - kernel_size - 1))) next_state = COMPLETE;
            FLUSH:              next_state = COMPLETE;
            COMPLETE:  if (restart) next_state = INIT;
            default:            next_state = IDLE;
        endcase
    end

    // ============================================================
    // Sequential outputs & counters
    // ============================================================
    reg one_clock = 0;
    reg first_time = 0;
    assign en_shift_reg = en_shift_reg_ifmap_input_shadow[2*Dimension-1 -: Dimension];
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            counter_bram_en <= 1'b0;
            enb_inputdata_input_bram <= {Dimension{1'b0}};
            zero_or_data <= 1'b0;
            done <= 1'b0;
            one_clock <= 0;
            fill_zero_count <= 0;
            padding_head_count <= 0;
            padding_tail_count <= 0;
            stride_count <= 0;
            N_in_count <= 0;
            en_shift_reg_ifmap_input_shadow <= 0;
        end
        else begin
            case (state)

                IDLE: begin
                    counter_bram_en <= 1'b0;
                    enb_inputdata_input_bram <= 0;
                    zero_or_data <= 1'b0;
                    done <= 1'b0;

                    padding_head_count <= 0;
                    padding_tail_count <= 0;
                    stride_count <= 0;
                    N_in_count <= 0;
                    en_shift_reg_ifmap_input_shadow <= 0;
                end

                INIT: begin
                    en_shift_reg_ifmap_input_shadow <= shadow_init;
                    stride_count <= 0;

                    if (padding_head_count < padding) begin
                        if (padding_head_count == (padding - 1)) begin
                            enb_inputdata_input_bram <= shift_reg_mask;
                            counter_bram_en <= 1'b1;
                        end
                        else begin
                            enb_inputdata_input_bram <= 0;
                            counter_bram_en <= 1'b0;
                        end
                        zero_or_data <= 1'b0;
                        padding_head_count <= padding_head_count + 1;
                    end
                    else begin
                        zero_or_data <= 1'b1;
                        enb_inputdata_input_bram <= shift_reg_mask;
                        counter_bram_en <= 1'b1;
                    end
//DW*(r+1)-1 -: DW
                    N_in_count <= N_in_count + 1;
                end
                STREAMING: begin
                    if (padding_head_count < padding) begin
                        if(padding_head_count == (padding - 1)) begin
                            enb_inputdata_input_bram <= shift_reg_mask;
                            counter_bram_en <= 1'b1; 
                        end
                        else begin
                            enb_inputdata_input_bram <= 0;
                            counter_bram_en <= 1'b0;
                        end
                        zero_or_data <= 1'b0;
                        padding_head_count <= padding_head_count + 1;
                    end
                    else if (!ifmap_counter_done) begin //Design Mismatch
                        zero_or_data <= 1'b1;
                        enb_inputdata_input_bram <= shift_reg_mask;
                        counter_bram_en <= 1'b1;
                    end
                    else if (padding_tail_count < padding) begin
                        if (!one_clock) begin
                            zero_or_data <= 1'b1;
                            enb_inputdata_input_bram <= shift_reg_mask;
                            counter_bram_en <= 1'b1;
                            one_clock <= 1'b1;                            
                        end
                        else begin
                            zero_or_data <= 1'b0;
                            enb_inputdata_input_bram <= 0;
                            padding_tail_count <= padding_tail_count + 1;
                            counter_bram_en <= 1'b0;
                        end
                    end

                    if (stride_count >= stride_val - 1) begin
                        en_shift_reg_ifmap_input_shadow <= en_shift_reg_ifmap_input_shadow << 1;
                        stride_count <= 0;
                    end
                    else
                        stride_count <= stride_count + 1;

                    N_in_count <= N_in_count + 1;
                end
                FILL_ZERO: begin
                    zero_or_data <= 1'b0;
                    en_shift_reg_ifmap_input_shadow <= {2*Dimension{1'b1}};
                    fill_zero_count <= fill_zero_count + 1;
                end

                FLUSH: begin
                    zero_or_data <= 1'b0;
                    en_shift_reg_ifmap_input_shadow <= {2*Dimension{1'b1}};
                    enb_inputdata_input_bram <= 0;
                    counter_bram_en <= 1'b0;
                end

                COMPLETE: begin
                    done <= 1'b1;
                    counter_bram_en <= 1'b0;
                    en_shift_reg_ifmap_input_shadow <= 0;
                end

            endcase
        end
    end

endmodule
