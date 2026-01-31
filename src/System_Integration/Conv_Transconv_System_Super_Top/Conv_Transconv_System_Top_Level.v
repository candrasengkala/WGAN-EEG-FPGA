`timescale 1ns / 1ps

/******************************************************************************
 * Module: Conv_Transconv_System_Top_Level
 *
 * Description:
 *   Hybrid Conv-TransConv Architecture (WGAN-EEG Style)
 *   
 *   ENCODER (4 Conv Layers - Downsampling):
 *   - Layer 0: 1 → 32 channels    (512 → 256 samples) [stride=2, k=16, p=7]
 *   - Layer 1: 32 → 64 channels   (256 → 128 samples) [stride=2, k=16, p=7]
 *   - Layer 2: 64 → 128 channels  (128 → 64 samples)  [stride=2, k=16, p=7]
 *   - Layer 3: 128 → 256 channels (64 → 32 samples)   [stride=2, k=16, p=7]
 *   
 *   BOTTLENECK (5 Conv Layers - Residual Processing):
 *   - Layers 4-8: 256 → 256 channels (32 samples) [stride=1, k=7, p=3]
 *   
 *   DECODER (4 TransConv Layers - Upsampling):
 *   - TransConv Layers 0-3 handle upsampling from 32 → 512 samples
 *   - Uses Transpose_Control_Top for transposed convolution operations
 *   
 *   OUTPUT HEAD (1 Conv Layer):
 *   - Layer 9: 16 → 1 channel (512 samples) [stride=1, k=7, p=3]
 *
 * CONTROL FLOW:
 *   1. Onedconv_Control_Top: Handles encoder (0-3), bottleneck (4-8), output (9)
 *      - 10 layers total configured in ROM
 *      - Automatic sequencing via Auto_Scheduler
 *   2. Transpose_Control_Top: Handles decoder transposed convolutions
 *      - Activated between bottleneck and output layer
 *      - 4 transconv layers for upsampling
 *
 * AXI WRAPPER ARCHITECTURE (matches System_Level_Top):
 *   - Weight wrapper: WRITE weights, READ output from BRAM 0-7
 *   - Ifmap wrapper: WRITE ifmaps, READ output from BRAM 8-15
 *   - Bias wrapper: WRITE ONLY to output BRAMs
 *   - Both output wrappers share the same header and timing from Output Manager
 *
 * Author: Updated for new Control Top Interface
 * Date: January 30, 2026
 ******************************************************************************/

module Conv_Transconv_System_Top_Level #(
    parameter DW           = 16,
    parameter NUM_BRAMS    = 16,
    parameter W_ADDR_W     = 11,
    parameter I_ADDR_W     = 10,
    parameter O_ADDR_W     = 10,
    parameter W_DEPTH      = 2048,
    parameter I_DEPTH      = 1024,
    parameter O_DEPTH      = 1024,
    parameter Dimension    = 16,
    parameter MUX_SEL_WIDTH = 4,
    parameter Depth_added  = 17 //Kept at Dimension + 1. Its for buffers.
)(
    input  wire aclk,
    input  wire aresetn,

    // ============================================================
    // AXI STREAM INTERFACES
    // ============================================================
    
    // AXI Stream 0 - Weight (WRITE + READ OUTPUT from BRAM 0-7)
    input  wire [DW-1:0]  s0_axis_tdata,
    input  wire           s0_axis_tvalid,
    output wire           s0_axis_tready,
    input  wire           s0_axis_tlast,
    output wire [DW-1:0]  m0_axis_tdata,
    output wire           m0_axis_tvalid,
    input  wire           m0_axis_tready,
    output wire           m0_axis_tlast,

    // AXI Stream 1 - Ifmap (WRITE + READ OUTPUT from BRAM 8-15)
    input  wire [DW-1:0]  s1_axis_tdata,
    input  wire           s1_axis_tvalid,
    output wire           s1_axis_tready,
    input  wire           s1_axis_tlast,
    output wire [DW-1:0]  m1_axis_tdata,
    output wire           m1_axis_tvalid,
    input  wire           m1_axis_tready,
    output wire           m1_axis_tlast,

    // AXI Stream 2 - Bias (WRITE ONLY)
    input  wire [DW-1:0]  s2_axis_tdata,
    input  wire           s2_axis_tvalid,
    output wire           s2_axis_tready,
    input  wire           s2_axis_tlast,

    // ============================================================
    // STATUS OUTPUTS
    // ============================================================
    output wire           sequence_complete,        // All 10 layers done
    output wire           encoder_complete,         // Layers 0-3 done
    output wire           bottleneck_complete,      // Layer 4 done
    output wire           decoder_complete,         // Layers 5-8 done
    output wire           output_head_complete,     // Layer 9 done
    output wire [3:0]     current_layer,            // 0-9
    output wire [2:0]     current_stage,            // 0=ENCODER, 1=BOTTLENECK, 2=DECODER, 3=OUTPUT
    output wire [1:0]     transconv_batch,          // Current decoder batch
    
    // External BRAM Write Interface (for bias)
    input  wire                              input_bias,
    input  wire [NUM_BRAMS-1:0]              bias_ena,
    input  wire [NUM_BRAMS-1:0]              bias_wea,
    input  wire [O_ADDR_W-1:0]               bias_addr,
    input  wire signed [NUM_BRAMS*DW-1:0]    bias_data,

    // External Output Read Interface
    input  wire                              ext_read_mode,
    input  wire [NUM_BRAMS-1:0]              ext_enb_output,
    input  wire [O_ADDR_W-1:0]               ext_output_addr,
    output wire signed [NUM_BRAMS*DW-1:0]    output_result,

    // Debug & Status Outputs
    output wire           weight_write_done,
    output wire           weight_read_done,
    output wire           ifmap_write_done,
    output wire           ifmap_read_done,
    output wire           bias_write_done,
    output wire [9:0]     weight_mm2s_data_count,
    output wire [9:0]     ifmap_mm2s_data_count,
    output wire [2:0]     weight_parser_state,
    output wire           weight_error_invalid_magic,
    output wire [2:0]     ifmap_parser_state,
    output wire           ifmap_error_invalid_magic,
    output wire [2:0]     bias_parser_state,
    output wire           bias_error_invalid_magic
);

    // ========================================================================
    // ARCHITECTURE STATE MACHINE
    // ========================================================================
    localparam STAGE_ENCODER    = 3'd0;  // Layers 0-3: Encoder (Conv)
    localparam STAGE_BOTTLENECK = 3'd1;  // Layers 4-8: Bottleneck (Conv)
    localparam STAGE_DECODER    = 3'd2;  // TransConv Layers 0-3: Decoder
    localparam STAGE_OUTPUT     = 3'd3;  // Layer 9: Output Head (Conv)
    localparam STAGE_DONE       = 3'd4;  // Complete
    
    reg [2:0] unet_stage;
    reg [3:0] layer_counter;
    reg encoder_done_reg, bottleneck_done_reg, decoder_done_reg, output_done_reg;
    
    // Stage tracking
    wire stage_transition;
    reg stage_transition_prev;
    wire stage_transition_pulse;
    
    // ========================================================================
    // AXI WRAPPER SIGNALS
    // ========================================================================
    
    // Weight BRAM Write
    wire [NUM_BRAMS*DW-1:0]      weight_wr_data_flat;
    wire [W_ADDR_W-1:0]          weight_wr_addr;
    wire [NUM_BRAMS-1:0]         weight_wr_en;
    wire [W_ADDR_W-1:0]          weight_rd_addr;

    // Ifmap BRAM Write
    wire [NUM_BRAMS*DW-1:0]      ifmap_wr_data_flat;
    wire [I_ADDR_W-1:0]          ifmap_wr_addr;
    wire [NUM_BRAMS-1:0]         ifmap_wr_en;
    wire [I_ADDR_W-1:0]          ifmap_rd_addr;

    // Bias BRAM Write
    wire [NUM_BRAMS*DW-1:0]      bias_wr_data_flat;
    wire [O_ADDR_W-1:0]          bias_wr_addr;
    wire [NUM_BRAMS-1:0]         bias_wr_en;
    wire                         bias_write_active;

    // Output Manager signals (SHARED by both wrappers)
    wire [15:0] header_word_0, header_word_1, header_word_2;
    wire [15:0] header_word_3, header_word_4, header_word_5;
    wire        send_header;       // SAME trigger for both wrappers!
    wire        out_mgr_trigger_read;
    wire [2:0]  out_mgr_rd_bram_start;
    wire [2:0]  out_mgr_rd_bram_end;
    wire [15:0] out_mgr_rd_addr_count;
    wire        out_mgr_notification_mode;
    wire        out_mgr_transmission_active;

    // Datapath signals
    wire signed [NUM_BRAMS*DW-1:0]    ext_read_data_flat;
    wire [8*DW-1:0]  out_group0_bram_data;  // BRAM 0-7 for weight wrapper
    wire [8*DW-1:0]  out_group1_bram_data;  // BRAM 8-15 for ifmap wrapper

    // ========================================================================
    // CONVOLUTION CONTROL SIGNALS (ENCODER + BOTTLENECK + OUTPUT)
    // ========================================================================
    wire [NUM_BRAMS-1:0]              conv_if_re;
    wire [I_ADDR_W-1:0]               conv_ifmap_addr_out;
    wire [NUM_BRAMS-1:0]              conv_w_re;
    wire [I_ADDR_W-1:0]               conv_weight_addr_out;
    
    wire [Dimension-1:0]              conv_en_shift_reg_ifmap_muxed;
    wire [Dimension-1:0]              conv_en_shift_reg_weight_muxed;
    wire                              conv_zero_or_data;
    wire                              conv_zero_or_data_weight;
    wire [MUX_SEL_WIDTH-1:0]          conv_sel_input_data_mem;
    wire                              conv_output_bram_dest;
    wire                              conv_en_reg_adder;
    wire                              conv_output_result_reg_rst;
    
    wire [O_ADDR_W-1:0]               conv_output_addr_wr;
    wire [O_ADDR_W-1:0]               conv_output_addr_rd;
    wire [NUM_BRAMS-1:0]              conv_ena_output;
    wire [NUM_BRAMS-1:0]              conv_wea_output;
    wire [NUM_BRAMS-1:0]              conv_enb_output;
    
    wire                              conv_rst_top;
    wire                              conv_out_new_val_sign;
    
    wire                              conv_global_done;
    wire                              conv_layer_processing;
    wire [3:0]                        conv_layer_id;
    
    wire [Dimension*Dimension-1:0]    conv_en_in_systolic;
    wire [Dimension*Dimension-1:0]    conv_en_out_systolic;
    wire [Dimension*Dimension-1:0]    conv_en_psum_systolic;
    wire [Dimension-1:0]              conv_ifmaps_sel_systolic;
    wire [Dimension-1:0]              conv_output_eject_ctrl_systolic;

    // ========================================================================
    // TRANSPOSED CONVOLUTION CONTROL SIGNALS (DECODER) - UNCHANGED
    // ========================================================================
    wire [NUM_BRAMS-1:0]            transconv_w_re;
    wire [NUM_BRAMS*W_ADDR_W-1:0]   transconv_w_addr_rd_flat;
    wire [NUM_BRAMS-1:0]            transconv_if_re;
    wire [NUM_BRAMS*I_ADDR_W-1:0]   transconv_if_addr_rd_flat;
    wire [3:0]                      transconv_ifmap_sel;
    
    wire [NUM_BRAMS-1:0]            transconv_en_weight_load;
    wire [NUM_BRAMS-1:0]            transconv_en_ifmap_load;
    wire [NUM_BRAMS-1:0]            transconv_en_psum;
    wire [NUM_BRAMS-1:0]            transconv_clear_psum;
    wire [NUM_BRAMS-1:0]            transconv_en_output;
    wire [NUM_BRAMS-1:0]            transconv_ifmap_sel_ctrl;
    wire [4:0]                      transconv_done_select;
    
    wire [NUM_BRAMS-1:0]            transconv_cmap_snapshot;
    wire [NUM_BRAMS*14-1:0]         transconv_omap_snapshot;
    wire                            transconv_clear_output_bram;
    wire                            transconv_batch_complete;
    wire                            transconv_scheduler_done;
    wire [1:0]                      transconv_current_layer_id;
    wire [2:0]                      transconv_current_batch_id;
    wire                            transconv_all_batches_done;

    // ========================================================================
    // MODE CONTROL
    // ========================================================================
    wire                              conv_mode;
    wire                              start_conv_signal;
    wire                              start_transconv_signal;

    // Output Manager control
    wire out_mgr_ext_read_mode;
    wire [NUM_BRAMS*O_ADDR_W-1:0] out_mgr_ext_read_addr_flat;

    // ========================================================================
    // ARCHITECTURE SEQUENCING STATE MACHINE
    // ========================================================================
    
    always @(posedge aclk or negedge aresetn) begin
        if (~aresetn) begin
            unet_stage <= STAGE_ENCODER;
            layer_counter <= 4'd0;
            encoder_done_reg <= 1'b0;
            bottleneck_done_reg <= 1'b0;
            decoder_done_reg <= 1'b0;
            output_done_reg <= 1'b0;
            stage_transition_prev <= 1'b0;
        end else begin
            stage_transition_prev <= stage_transition;
            
            case (unet_stage)
                STAGE_ENCODER: begin
                    // Layers 0-3: Encoder (downsampling)
                    if (conv_global_done && layer_counter == 4'd3) begin
                        encoder_done_reg <= 1'b1;
                        layer_counter <= 4'd4;
                        unet_stage <= STAGE_BOTTLENECK;
                        $display("[%0t] ARCHITECTURE: ENCODER complete (Layers 0-3), moving to BOTTLENECK", $time);
                    end else if (conv_global_done) begin
                        layer_counter <= layer_counter + 1;
                    end
                end
                
                STAGE_BOTTLENECK: begin
                    // Layers 4-8: Bottleneck (residual processing)
                    if (conv_global_done && layer_counter == 4'd8) begin
                        bottleneck_done_reg <= 1'b1;
                        layer_counter <= 4'd0;  // Reset for transconv layers
                        unet_stage <= STAGE_DECODER;
                        $display("[%0t] ARCHITECTURE: BOTTLENECK complete (Layers 4-8), moving to DECODER", $time);
                    end else if (conv_global_done) begin
                        layer_counter <= layer_counter + 1;
                    end
                end
                
                STAGE_DECODER: begin
                    // TransConv Layers 0-3: Decoder (upsampling)
                    if (transconv_scheduler_done && transconv_current_layer_id == 2'd3) begin
                        decoder_done_reg <= 1'b1;
                        layer_counter <= 4'd9;
                        unet_stage <= STAGE_OUTPUT;
                        $display("[%0t] ARCHITECTURE: DECODER complete (TransConv 0-3), moving to OUTPUT HEAD", $time);
                    end
                end
                
                STAGE_OUTPUT: begin
                    // Layer 9: Output head (final convolution)
                    if (conv_global_done) begin
                        output_done_reg <= 1'b1;
                        unet_stage <= STAGE_DONE;
                        $display("[%0t] ARCHITECTURE: OUTPUT HEAD complete (Layer 9), SEQUENCE COMPLETE!", $time);
                    end
                end
                
                STAGE_DONE: begin
                    // Remain in done state
                end
                
                default: unet_stage <= STAGE_ENCODER;
            endcase
        end
    end
    
    // Stage transition pulse
    assign stage_transition = (unet_stage != STAGE_ENCODER) && (unet_stage != stage_transition_prev);
    assign stage_transition_pulse = stage_transition & ~stage_transition_prev;
    
    // ========================================================================
    // MODE CONTROL: CONV vs TRANSCONV
    // ========================================================================
    // CONV mode: Encoder (0-3), Bottleneck (4-8), Output (9)
    // TRANSCONV mode: Decoder
    
    assign conv_mode = (unet_stage == STAGE_DECODER) ? 1'b1 : 1'b0;
    
    // Start signals
    assign start_conv_signal = (unet_stage == STAGE_ENCODER || 
                                 unet_stage == STAGE_BOTTLENECK || 
                                 unet_stage == STAGE_OUTPUT) ? 1'b1 : 1'b0;
    
    assign start_transconv_signal = (unet_stage == STAGE_DECODER) ? stage_transition_pulse : 1'b0;
    
    // ========================================================================
    // STATUS OUTPUT ASSIGNMENTS
    // ========================================================================
    assign sequence_complete = (unet_stage == STAGE_DONE);
    assign encoder_complete = encoder_done_reg;
    assign bottleneck_complete = bottleneck_done_reg;
    assign decoder_complete = decoder_done_reg;
    assign output_head_complete = output_done_reg;
    assign current_layer = layer_counter;
    assign current_stage = unet_stage;
    assign transconv_batch = transconv_current_batch_id;
    
    // Output result
    assign output_result = ext_read_data_flat;

    // Bias write activity detector
    assign bias_write_active = |bias_wr_en;

    // ========================================================================
    // OUTPUT MANAGER CONTROL
    // ext_read_mode controlled by transmission_active
    // - During accumulation (transmission_active=0): use internal addresses
    // - During output (transmission_active=1): use ext_read_addr_flat from wrappers
    // ========================================================================
    assign out_mgr_ext_read_mode = out_mgr_transmission_active;

    // Map addresses for BOTH output groups (BRAM 0-7 and 8-15)
    genvar k;
    generate
        for(k=0; k<8; k=k+1) begin : MAP_ADDR_GRP0
            assign out_mgr_ext_read_addr_flat[k*O_ADDR_W +: O_ADDR_W] = weight_rd_addr[O_ADDR_W-1:0];
        end
        for(k=8; k<16; k=k+1) begin : MAP_ADDR_GRP1
            assign out_mgr_ext_read_addr_flat[k*O_ADDR_W +: O_ADDR_W] = ifmap_rd_addr[O_ADDR_W-1:0];
        end
    endgenerate

    // Split datapath output to 2 groups
    assign out_group0_bram_data = ext_read_data_flat[8*DW-1 : 0];      // BRAM 0-7 for weight wrapper
    assign out_group1_bram_data = ext_read_data_flat[16*DW-1 : 8*DW];  // BRAM 8-15 for ifmap wrapper

    // ========================================================================
    // INSTANTIATION: AXI WEIGHT WRAPPER
    // Handles: WRITE weight data, READ output from BRAM 0-7
    // ========================================================================
    axis_control_wrapper #(
        .BRAM_DEPTH(W_DEPTH),
        .DATA_WIDTH(DW),
        .BRAM_COUNT(NUM_BRAMS),
        .ADDR_WIDTH(W_ADDR_W)
    ) weight_wrapper (
        .aclk(aclk),
        .aresetn(aresetn),
        
        // AXI Stream Slave - WRITE weight data
        .s_axis_tdata(s0_axis_tdata),
        .s_axis_tvalid(s0_axis_tvalid),
        .s_axis_tready(s0_axis_tready),
        .s_axis_tlast(s0_axis_tlast),
        
        // AXI Stream Master - READ output data from BRAM 0-7
        .m_axis_tdata(m0_axis_tdata),
        .m_axis_tvalid(m0_axis_tvalid),
        .m_axis_tready(m0_axis_tready),
        .m_axis_tlast(m0_axis_tlast),
        
        // SHARED header from Output Manager
        .header_word_0(header_word_0),
        .header_word_1(header_word_1),
        .header_word_2(header_word_2),
        .header_word_3(header_word_3),
        .header_word_4(header_word_4),
        .header_word_5(header_word_5),
        .send_header(send_header),  // SAME trigger as ifmap wrapper!
        
        // Read control: BRAM 0-7
        .out_mgr_rd_bram_start(out_mgr_rd_bram_start),  // 0
        .out_mgr_rd_bram_end(out_mgr_rd_bram_end),      // 7
        .out_mgr_rd_addr_count(out_mgr_rd_addr_count),
        .notification_mode(out_mgr_notification_mode),
        
        // Status
        .write_done(weight_write_done),
        .read_done(weight_read_done),
        .mm2s_data_count(weight_mm2s_data_count),
        .parser_state(weight_parser_state),
        .error_invalid_magic(weight_error_invalid_magic),
        
        // BRAM Write Interface - for weight loading
        .bram_wr_data_flat(weight_wr_data_flat),
        .bram_wr_addr(weight_wr_addr),
        .bram_wr_en(weight_wr_en),
        
        // BRAM Read Interface - for output streaming
        .bram_rd_data_flat(out_group0_bram_data),
        .bram_rd_addr(weight_rd_addr)
    );

    // ========================================================================
    // INSTANTIATION: AXI IFMAP WRAPPER
    // Handles: WRITE ifmap data, READ output from BRAM 8-15
    // ========================================================================
    axis_control_wrapper #(
        .BRAM_DEPTH(I_DEPTH),
        .DATA_WIDTH(DW),
        .BRAM_COUNT(NUM_BRAMS),
        .ADDR_WIDTH(I_ADDR_W)
    ) ifmap_wrapper (
        .aclk(aclk),
        .aresetn(aresetn),
        
        // AXI Stream Slave - WRITE ifmap data
        .s_axis_tdata(s1_axis_tdata),
        .s_axis_tvalid(s1_axis_tvalid),
        .s_axis_tready(s1_axis_tready),
        .s_axis_tlast(s1_axis_tlast),
        
        // AXI Stream Master - READ output data from BRAM 8-15
        .m_axis_tdata(m1_axis_tdata),
        .m_axis_tvalid(m1_axis_tvalid),
        .m_axis_tready(m1_axis_tready),
        .m_axis_tlast(m1_axis_tlast),
        
        // SHARED header from Output Manager (SAME timing as weight wrapper!)
        .header_word_0(header_word_0),
        .header_word_1(header_word_1),
        .header_word_2(header_word_2),
        .header_word_3(header_word_3),
        .header_word_4(header_word_4),
        .header_word_5(header_word_5),
        .send_header(send_header),  // SAME trigger!
        
        // Read control: BRAM 8-15
        .out_mgr_rd_bram_start(out_mgr_rd_bram_start),
        .out_mgr_rd_bram_end(out_mgr_rd_bram_end),
        .out_mgr_rd_addr_count(out_mgr_rd_addr_count),
        .notification_mode(out_mgr_notification_mode),
        
        // Status
        .write_done(ifmap_write_done),
        .read_done(ifmap_read_done),
        .mm2s_data_count(ifmap_mm2s_data_count),
        .parser_state(ifmap_parser_state),
        .error_invalid_magic(ifmap_error_invalid_magic),
        
        // BRAM Write Interface - for ifmap loading
        .bram_wr_data_flat(ifmap_wr_data_flat),
        .bram_wr_addr(ifmap_wr_addr),
        .bram_wr_en(ifmap_wr_en),
        
        // BRAM Read Interface - for output streaming
        .bram_rd_data_flat(out_group1_bram_data),
        .bram_rd_addr(ifmap_rd_addr)
    );

    // ========================================================================
    // INSTANTIATION: AXI BIAS WRAPPER
    // Handles: WRITE ONLY to output BRAMs (no read capability)
    // ========================================================================
    axis_control_wrapper #(
        .BRAM_DEPTH(O_DEPTH),
        .DATA_WIDTH(DW),
        .BRAM_COUNT(8),  // Only 8 BRAMs for bias
        .ADDR_WIDTH(O_ADDR_W)
    ) bias_wrapper (
        .aclk(aclk),
        .aresetn(aresetn),
        
        // AXI Stream Slave - WRITE bias data
        .s_axis_tdata(s2_axis_tdata),
        .s_axis_tvalid(s2_axis_tvalid),
        .s_axis_tready(s2_axis_tready),
        .s_axis_tlast(s2_axis_tlast),
        
        // AXI Stream Master - DISABLED (no output)
        .m_axis_tdata(),  // Unused
        .m_axis_tvalid(),  // Unused
        .m_axis_tready(1'b0),
        .m_axis_tlast(),  // Unused
        
        // Header - DISABLED (no output)
        .header_word_0(16'b0),
        .header_word_1(16'b0),
        .header_word_2(16'b0),
        .header_word_3(16'b0),
        .header_word_4(16'b0),
        .header_word_5(16'b0),
        .send_header(1'b0),
        
        // Read control - DISABLED
        .out_mgr_rd_bram_start(3'b0),
        .out_mgr_rd_bram_end(3'b0),
        .out_mgr_rd_addr_count(16'b0),
        .notification_mode(1'b0),
        
        // Status
        .write_done(bias_write_done),
        .read_done(),  // Unused
        .mm2s_data_count(),  // Unused
        .parser_state(bias_parser_state),
        .error_invalid_magic(bias_error_invalid_magic),
        
        // BRAM Write Interface - to Output BRAM
        .bram_wr_data_flat(bias_wr_data_flat),
        .bram_wr_addr(bias_wr_addr),
        .bram_wr_en(bias_wr_en),
        
        // BRAM Read Interface - DISABLED
        .bram_rd_data_flat({8*DW{1'b0}}),  // Tied to zero
        .bram_rd_addr()  // Unused
    );

    // ========================================================================
    // INSTANTIATION: CONVOLUTION CONTROL (ENCODER + BOTTLENECK + OUTPUT)
    // UPDATED to match new Onedconv_Control_Top interface
    // ========================================================================
    Onedconv_Control_Top #(
        .DW(DW),
        .Dimension(Dimension),
        .ADDRESS_LENGTH(I_ADDR_W),
        .MUX_SEL_WIDTH(MUX_SEL_WIDTH)
    ) conv_control (
        .clk(aclk),
        .rst_n(aresetn),
        
        // Global Control Interface
        .global_start(start_conv_signal),
        .global_done(conv_global_done),
        
        // AXI Interface
        .weight_write_done(weight_write_done & start_conv_signal),
        .ifmap_write_done(ifmap_write_done & start_conv_signal),
        .read_done(weight_read_done & start_conv_signal),
        .transmission_active(out_mgr_transmission_active & start_conv_signal),
        
        // BRAM Address Outputs
        .inputdata_addr_out(conv_ifmap_addr_out),
        .weight_addr_out(conv_weight_addr_out),
        .output_addr_out_a(conv_output_addr_wr),
        .output_addr_out_b(conv_output_addr_rd),
        
        // BRAM Control Outputs
        .enb_inputdata_input_bram(conv_if_re),
        .enb_weight_input_bram(conv_w_re),
        .ena_output_result_control(conv_ena_output),
        .wea_output_result(conv_wea_output),
        .enb_output_result_control(conv_enb_output),
        
        // Shift Register & Datapath Control
        .en_shift_reg_ifmap_muxed(conv_en_shift_reg_ifmap_muxed),
        .en_shift_reg_weight_muxed(conv_en_shift_reg_weight_muxed),
        .zero_or_data(conv_zero_or_data),
        .zero_or_data_weight(conv_zero_or_data_weight),
        .sel_input_data_mem(conv_sel_input_data_mem),
        .output_bram_destination(conv_output_bram_dest),
        
        // Systolic Array Control Outputs
        .en_in_systolic(conv_en_in_systolic),
        .en_out_systolic(conv_en_out_systolic),
        .en_psum_systolic(conv_en_psum_systolic),
        .ifmaps_sel_systolic(conv_ifmaps_sel_systolic),
        .output_eject_ctrl_systolic(conv_output_eject_ctrl_systolic),
        
        // Adder-Side Register Control
        .en_reg_adder(conv_en_reg_adder),
        .output_result_reg_rst(conv_output_result_reg_rst),
        
        // Top-Level IO Control
        .rst_top(conv_rst_top),
        .out_new_val_sign(conv_out_new_val_sign),
        
        // Status Outputs
        .current_layer_id(conv_layer_id),
        .layer_processing(conv_layer_processing),
        
        // Auto Scheduler Status Outputs
        .all_layers_complete(),  // Not used (global_done is the same)
        .layer_transition(),
        .clear_output_bram(),
        .auto_start_active(),
        .data_load_ready()
    );

    // ========================================================================
    // INSTANTIATION: TRANSPOSED CONVOLUTION CONTROL (DECODER)
    // COMPLETELY UNCHANGED - transconv interactions remain sacrosanct
    // ========================================================================
    Transpose_Control_Top #(
        .DW(DW),
        .NUM_BRAMS(NUM_BRAMS),
        .NUM_PE(Dimension),
        .ADDR_WIDTH(I_ADDR_W)
    ) transconv_control (
        .clk(aclk),
        .rst_n(aresetn),
        
        .weight_write_done(weight_write_done & conv_mode),
        .ifmap_write_done(ifmap_write_done & conv_mode),
        .bias_write_done(bias_write_done & conv_mode),
        
        .ext_start(start_transconv_signal),
        .ext_layer_id(2'b00),
        
        .current_layer_id(transconv_current_layer_id),
        .current_batch_id(transconv_current_batch_id),
        .scheduler_done(transconv_scheduler_done),
        .all_batches_done(transconv_all_batches_done),
        .clear_output_bram(transconv_clear_output_bram),
        .auto_active(),
        .batch_complete_signal(transconv_batch_complete),
        
        .w_re(transconv_w_re),
        .w_addr_rd_flat(transconv_w_addr_rd_flat),
        
        .if_re(transconv_if_re),
        .if_addr_rd_flat(transconv_if_addr_rd_flat),
        .ifmap_sel_out(transconv_ifmap_sel),
        
        .en_weight_load(transconv_en_weight_load),
        .en_ifmap_load(transconv_en_ifmap_load),
        .en_psum(transconv_en_psum),
        .clear_psum(transconv_clear_psum),
        .en_output(transconv_en_output),
        .ifmap_sel_ctrl(transconv_ifmap_sel_ctrl),
        
        .cmap_snapshot(transconv_cmap_snapshot),
        .omap_snapshot(transconv_omap_snapshot),
        .mapper_done_pulse(),
        .selector_mux_transpose(transconv_done_select)
    );

    // ========================================================================
    // ADDRESS GENERATION FOR CONV MODE
    // ========================================================================
    wire [NUM_BRAMS*I_ADDR_W-1:0] conv_if_addr_rd_flat;
    wire [NUM_BRAMS*W_ADDR_W-1:0] conv_w_addr_rd_flat;
    wire [NUM_BRAMS-1:0] conv_ifmaps_sel_ctrl;
    wire [NUM_BRAMS-1:0] conv_output_eject_ctrl;

    genvar g;
    generate
        for (g = 0; g < NUM_BRAMS; g = g + 1) begin : GEN_CONV_ADDR
            assign conv_if_addr_rd_flat[g*I_ADDR_W +: I_ADDR_W] = conv_ifmap_addr_out;
            assign conv_w_addr_rd_flat[g*W_ADDR_W +: W_ADDR_W] = {{(W_ADDR_W-I_ADDR_W){1'b0}}, conv_weight_addr_out};
            assign conv_ifmaps_sel_ctrl[g] = conv_ifmaps_sel_systolic[g];
            assign conv_output_eject_ctrl[g] = conv_output_eject_ctrl_systolic[g];
        end
    endgenerate

    // ========================================================================
    // INSTANTIATION: UNIFIED DATAPATH (SUPER TOP LEVEL)
    // UPDATED to match Conv_Transconv_Super_Top_Level_Modified interface
    // ========================================================================
    Conv_Transconv_Super_Top_Level_Modified #(
        .DW(DW),
        .NUM_BRAMS(NUM_BRAMS),
        .W_ADDR_W(W_ADDR_W),
        .W_DEPTH(W_DEPTH),
        .I_ADDR_W(I_ADDR_W),
        .I_DEPTH(I_DEPTH),
        .O_ADDR_W(O_ADDR_W),
        .O_DEPTH(O_DEPTH),
        .Depth_added(Depth_added)
    ) u_datapath (
        .clk(aclk),
        .rst_n(aresetn),
        
        // MODE SELECTION
        .conv_mode(conv_mode),
        .start_conv(start_conv_signal),
        .start_transconv(start_transconv_signal),
        
        // WEIGHT BRAM INTERFACE
        .w_we(weight_wr_en),
        .w_addr_wr_flat({NUM_BRAMS{weight_wr_addr}}),
        .w_din_flat(weight_wr_data_flat),
        .w_re_conv(conv_w_re),
        .w_addr_rd_conv_flat(conv_w_addr_rd_flat),
        .w_re_transconv(transconv_w_re),
        .w_addr_rd_transconv_flat(transconv_w_addr_rd_flat),
        
        // IFMAP BRAM INTERFACE
        .if_we(ifmap_wr_en),
        .if_addr_wr_flat({NUM_BRAMS{ifmap_wr_addr}}),
        .if_din_flat(ifmap_wr_data_flat),
        .if_re_conv(conv_if_re),
        .if_addr_rd_conv_flat(conv_if_addr_rd_flat),
        .if_re_transconv(transconv_if_re),
        .if_addr_rd_transconv_flat(transconv_if_addr_rd_flat),
        .ifmap_sel_transconv(transconv_ifmap_sel),
        
        // 1DCONV CONTROL SIGNALS
        .rst_top(conv_rst_top),
        .conv_en_shift_reg_ifmap_muxed(conv_en_shift_reg_ifmap_muxed),
        .conv_en_shift_reg_weight_muxed(conv_en_shift_reg_weight_muxed),
        .conv_zero_or_data(conv_zero_or_data),
        .conv_zero_or_data_weight(conv_zero_or_data_weight),
        .conv_en_in(conv_en_in_systolic),
        .conv_en_out(conv_en_out_systolic),
        .conv_en_psum(conv_en_psum_systolic),
        .conv_clear_psum({(NUM_BRAMS*NUM_BRAMS){1'b0}}),  // Clear handled by rst_top
        .conv_ifmaps_sel_ctrl(conv_ifmaps_sel_ctrl),
        .conv_output_eject_ctrl(conv_output_eject_ctrl),
        .conv_out_new_val_sign(conv_out_new_val_sign),  // Not used in new interface
        .conv_output_addr_wr(conv_output_addr_wr),
        .conv_output_result_reg_rst(conv_output_result_reg_rst),
        .conv_output_addr_rd(conv_output_addr_rd),
        .conv_ena_output(conv_ena_output),
        .conv_wea_output(conv_wea_output),
        .conv_enb_output(conv_enb_output),
        .conv_en_reg_adder(conv_en_reg_adder),
        .conv_output_bram_dest(conv_output_bram_dest),
        
        // BIAS INTERFACE
        .input_bias(input_bias | bias_write_active),  // External OR AXI bias
        .bias_ena(input_bias ? bias_ena : bias_wr_en),
        .bias_wea(input_bias ? bias_wea : bias_wr_en),
        .bias_addr(input_bias ? bias_addr : bias_wr_addr),
        .bias_data(input_bias ? bias_data : bias_wr_data_flat),
        
        // TRANSCONV CONTROL SIGNALS - UNCHANGED
        .transconv_en_weight_load(transconv_en_weight_load),
        .transconv_en_ifmap_load(transconv_en_ifmap_load),
        .transconv_en_psum(transconv_en_psum),
        .transconv_clear_psum(transconv_clear_psum | {NUM_BRAMS{transconv_clear_output_bram}}),
        .transconv_en_output(transconv_en_output),
        .transconv_ifmap_sel_ctrl(transconv_ifmap_sel_ctrl),
        .transconv_done_select(transconv_done_select),
        
        // MAPPING CONFIGURATION - UNCHANGED
        .cmap(transconv_cmap_snapshot),
        .omap_flat(transconv_omap_snapshot),
        
        // EXTERNAL READ INTERFACE
        .ext_read_mode(out_mgr_ext_read_mode),
        .ext_read_addr_flat(out_mgr_ext_read_addr_flat),
        
        // OUTPUTS
        .bram_read_data_flat(ext_read_data_flat),
        .bram_read_addr_flat()  // Not used
    );

    // ========================================================================
    // INSTANTIATION: OUTPUT MANAGER
    // Drives BOTH weight and ifmap wrappers simultaneously for output
    // UNCHANGED
    // ========================================================================
    Output_Manager_Simple #(
        .DW(DW)
    ) output_mgr (
        .clk(aclk),
        .rst_n(aresetn),
        
        .batch_complete(transconv_batch_complete),
        .current_batch_id(transconv_current_batch_id),
        .all_batches_done(sequence_complete),
        .completed_layer_id(current_layer[1:0]),
        
        // SHARED header outputs (connected to BOTH wrappers)
        .header_word_0(header_word_0),
        .header_word_1(header_word_1),
        .header_word_2(header_word_2),
        .header_word_3(header_word_3),
        .header_word_4(header_word_4),
        .header_word_5(header_word_5),
        .send_header(send_header),  // SAME trigger for both!
        
        .trigger_read(out_mgr_trigger_read),
        .rd_bram_start(out_mgr_rd_bram_start),
        .rd_bram_end(out_mgr_rd_bram_end),
        .rd_addr_count(out_mgr_rd_addr_count),
        .notification_mode(out_mgr_notification_mode),
        
        // Use weight_read_done as primary done signal
        .read_done(weight_read_done),
        .transmission_active(out_mgr_transmission_active)
    );

endmodule