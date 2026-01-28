`timescale 1ns / 1ps

/******************************************************************************
 * Module: Conv_Transconv_Super_Top_Level_Modified
 *
 * Description:
 * Updated unified top-level with modified BRAM interfaces.
 * - Weight_BRAM_Top_Modified: Separate conv/transconv read ports
 * - Ifmap_BRAM_Top_Modified: Separate conv/transconv read ports with routing
 *
 * Author: Modified Design
 * Date: January 2026
 ******************************************************************************/

module Conv_Transconv_Super_Top_Level_Modified #(
    parameter DW          = 16,
    parameter NUM_BRAMS   = 16,
    parameter W_ADDR_W    = 11,
    parameter W_DEPTH     = 2048,
    parameter I_ADDR_W    = 10,
    parameter I_DEPTH     = 1024,
    parameter O_ADDR_W    = 10,
    parameter O_DEPTH     = 1024,
    parameter Depth_added = 16
)(
    input  wire                              clk,
    input  wire                              rst_n,

    // MODE SELECTION
    input  wire                              conv_mode,
    input  wire                              start_conv,
    input  wire                              start_transconv,

    // WEIGHT BRAM INTERFACE
    input  wire [NUM_BRAMS-1:0]              w_we,
    input  wire [NUM_BRAMS*W_ADDR_W-1:0]     w_addr_wr_flat,
    input  wire signed [NUM_BRAMS*DW-1:0]    w_din_flat,
    input  wire [NUM_BRAMS-1:0]              w_re_conv,
    input  wire [NUM_BRAMS*W_ADDR_W-1:0]     w_addr_rd_conv_flat,
    input  wire [NUM_BRAMS-1:0]              w_re_transconv,
    input  wire [NUM_BRAMS*W_ADDR_W-1:0]     w_addr_rd_transconv_flat,

    // IFMAP BRAM INTERFACE
    input  wire [NUM_BRAMS-1:0]              if_we,
    input  wire [NUM_BRAMS*I_ADDR_W-1:0]     if_addr_wr_flat,
    input  wire signed [NUM_BRAMS*DW-1:0]    if_din_flat,
    input  wire [NUM_BRAMS-1:0]              if_re_conv,
    input  wire [NUM_BRAMS*I_ADDR_W-1:0]     if_addr_rd_conv_flat,
    input  wire [NUM_BRAMS-1:0]              if_re_transconv,
    input  wire [NUM_BRAMS*I_ADDR_W-1:0]     if_addr_rd_transconv_flat,
    input  wire [3:0]                        ifmap_sel_transconv,

    // 1DCONV CONTROL
    input  wire                              conv_buffer_mode,
    input  wire                              conv_en_shift_reg_ifmap_input,
    input  wire                              conv_en_shift_reg_weight_input,
    input  wire                              conv_en_shift_reg_ifmap_control,
    input  wire                              conv_en_shift_reg_weight_control,
    input  wire                              conv_en_cntr,
    input  wire [NUM_BRAMS*NUM_BRAMS-1:0]    conv_en_in,
    input  wire [NUM_BRAMS*NUM_BRAMS-1:0]    conv_en_out,
    input  wire [NUM_BRAMS*NUM_BRAMS-1:0]    conv_en_psum,
    input  wire [NUM_BRAMS*NUM_BRAMS-1:0]    conv_clear_psum,
    input  wire [NUM_BRAMS-1:0]              conv_ifmaps_sel_ctrl,
    input  wire [NUM_BRAMS-1:0]              conv_output_eject_ctrl,
    input  wire                              conv_out_new_val_sign,
    input  wire [O_ADDR_W-1:0]               conv_output_addr_wr,
    input  wire [O_ADDR_W-1:0]               conv_output_addr_rd,
    input  wire [NUM_BRAMS-1:0]              conv_ena_output,
    input  wire [NUM_BRAMS-1:0]              conv_wea_output,
    input  wire [NUM_BRAMS-1:0]              conv_enb_output,
    input  wire                              conv_en_reg_adder,
    input  wire                              conv_output_reg_rst,
    input  wire                              conv_output_bram_dest,
    input  wire                              input_bias,
    input  wire [NUM_BRAMS-1:0]              bias_ena,
    input  wire [NUM_BRAMS-1:0]              bias_wea,
    input  wire [O_ADDR_W-1:0]               bias_addr,
    input  wire signed [NUM_BRAMS*DW-1:0]    bias_data,

    // TRANSCONV CONTROL
    input  wire [NUM_BRAMS-1:0]              transconv_en_weight_load,
    input  wire [NUM_BRAMS-1:0]              transconv_en_ifmap_load,
    input  wire [NUM_BRAMS-1:0]              transconv_en_psum,
    input  wire [NUM_BRAMS-1:0]              transconv_clear_psum,
    input  wire [NUM_BRAMS-1:0]              transconv_en_output,
    input  wire [NUM_BRAMS-1:0]              transconv_ifmap_sel_ctrl,
    input  wire [4:0]                        transconv_done_select,

    // MAPPING CONFIGURATION
    input  wire [NUM_BRAMS-1:0]              cmap,
    input  wire [NUM_BRAMS*14-1:0]           omap_flat,

    // EXTERNAL READ INTERFACE
    input  wire                              ext_read_mode,
    input  wire [NUM_BRAMS*O_ADDR_W-1:0]     ext_read_addr_flat,

    // OUTPUTS
    output wire signed [NUM_BRAMS*DW-1:0]    bram_read_data_flat,
    output wire [NUM_BRAMS*O_ADDR_W-1:0]     bram_read_addr_flat
);

    // INTERNAL WIRES
    wire signed [NUM_BRAMS*DW-1:0]     weight_data_flat;
    wire signed [(NUM_BRAMS-1)*DW-1:0] ifmap_out_pe1_to_pe15_flat;
    wire signed [DW-1:0]               ifmap_out_pe0;
    wire signed [NUM_BRAMS*DW-1:0]     ifmap_data_for_engine;
    wire signed [DW-1:0]               transconv_result_out;
    wire [3:0]                         transconv_col_id;
    wire                               transconv_partial_valid;
    wire signed [NUM_BRAMS*DW-1:0]     conv_output_from_array;

    // ASSEMBLE IFMAP FOR ENGINE
    assign ifmap_data_for_engine = {ifmap_out_pe1_to_pe15_flat, ifmap_out_pe0};

    // WEIGHT BRAM
    Weight_BRAM_Top_Modified #(
        .DW(DW), 
        .NUM_BRAMS(NUM_BRAMS), 
        .ADDR_WIDTH(W_ADDR_W), 
        .DEPTH(W_DEPTH)
    ) u_weight_bram (
        .clk(clk), 
        .rst_n(rst_n),

        // WRITE INTERFACE
        .w_we(w_we), 
        .w_addr_wr_flat(w_addr_wr_flat), 
        .w_din_flat(w_din_flat),

        // READ INTERFACE - CONVOLUTION
        .w_re_conv(w_re_conv), 
        .w_addr_rd_conv_flat(w_addr_rd_conv_flat),

        // READ INTERFACE - TRANSPOSED CONVOLUTION
        .w_re_transconv(w_re_transconv), 
        .w_addr_rd_transconv_flat(w_addr_rd_transconv_flat),

        // START SIGNALS
        .start_conv(start_conv), 
        .start_transconv(start_transconv),

        // OUTPUTS
        .weight_out_flat(weight_data_flat)
    );

    // IFMAP BRAM
    ifmap_BRAM_Top_Modified #(
        .DW(DW), 
        .NUM_BRAMS(NUM_BRAMS), 
        .ADDR_WIDTH(I_ADDR_W), 
        .DEPTH(I_DEPTH)
    ) u_ifmap_bram (
        .clk(clk), 
        .rst_n(rst_n),

        // WRITE INTERFACE
        .if_we(if_we), 
        .if_addr_wr_flat(if_addr_wr_flat), 
        .if_din_flat(if_din_flat),

        // READ INTERFACE - CONVOLUTION
        .if_re_conv(if_re_conv), 
        .if_addr_rd_conv_flat(if_addr_rd_conv_flat),

        // READ INTERFACE - TRANSPOSED CONVOLUTION
        .if_re_transconv(if_re_transconv), 
        .if_addr_rd_transconv_flat(if_addr_rd_transconv_flat),
        .ifmap_sel_transconv(ifmap_sel_transconv),

        // START SIGNALS
        .start_conv(start_conv), 
        .start_transconv(start_transconv),

        // OUTPUTS
        .ifmap_out_pe1_to_pe15_flat(ifmap_out_pe1_to_pe15_flat),
        .ifmap_out_pe0(ifmap_out_pe0)
    );

    // COMPUTE ENGINE
    Conv_Transconv_Top #(
        .DW(DW), 
        .Dimension(NUM_BRAMS), 
        .Depth_added(Depth_added)
    ) u_compute_engine (
        .clk(clk), 
        .rst_n(rst_n), 
        .conv_mode(conv_mode),
        .weight_in(weight_data_flat), 
        .ifmap_in(ifmap_data_for_engine),
        .buffer_mode(conv_buffer_mode),
        .weight_brams_in(weight_data_flat), 
        .ifmap_serial_in(ifmap_out_pe0),
        .en_shift_reg_ifmap_input(conv_en_shift_reg_ifmap_input),
        .en_shift_reg_weight_input(conv_en_shift_reg_weight_input),
        .en_shift_reg_ifmap_control(conv_en_shift_reg_ifmap_control),
        .en_shift_reg_weight_control(conv_en_shift_reg_weight_control),
        .conv_en_cntr(conv_en_cntr), 
        .conv_en_in(conv_en_in),
        .conv_en_out(conv_en_out), 
        .conv_en_psum(conv_en_psum),
        .conv_clear_psum(conv_clear_psum),
        .conv_ifmaps_sel_ctrl(conv_ifmaps_sel_ctrl),
        .conv_output_eject_ctrl(conv_output_eject_ctrl),
        .transconv_en_weight_load(transconv_en_weight_load),
        .transconv_en_ifmap_load(transconv_en_ifmap_load),
        .transconv_en_psum(transconv_en_psum),
        .transconv_clear_psum(transconv_clear_psum),
        .transconv_en_output(transconv_en_output),
        .transconv_ifmap_sel_ctrl(transconv_ifmap_sel_ctrl),
        .transconv_done_select(transconv_done_select),
        .transconv_result_out(transconv_result_out),
        .transconv_col_id(transconv_col_id),
        .transconv_partial_valid(transconv_partial_valid),
        .conv_output_from_array(conv_output_from_array)
    );

    // OUTPUT BRAM
    BRAM_Output_Top #(
        .DW(DW), 
        .NUM_BRAMS(NUM_BRAMS), 
        .ADDR_WIDTH(O_ADDR_W), 
        .DEPTH(O_DEPTH)
    ) u_output_bram (
        .clk(clk), .rst_n(rst_n), 
        .conv_mode(conv_mode),
        .transconv_partial_in(transconv_result_out),
        .transconv_col_id(transconv_col_id),
        .transconv_partial_valid(transconv_partial_valid),
        .transconv_cmap(cmap), 
        .transconv_omap_flat(omap_flat),
        .conv_systolic_output(conv_output_from_array),
        .conv_out_new_val_sign(conv_out_new_val_sign),
        .conv_output_addr_wr(conv_output_addr_wr),
        .conv_output_addr_rd(conv_output_addr_rd),
        .conv_ena_output(conv_ena_output), 
        .conv_wea_output(conv_wea_output),
        .conv_enb_output(conv_enb_output),
        .conv_en_reg_adder(conv_en_reg_adder),
        .conv_output_reg_rst(conv_output_reg_rst),
        .conv_output_bram_dest(conv_output_bram_dest),
        .input_bias(input_bias), 
        .bias_ena(bias_ena), 
        .bias_wea(bias_wea),
        .bias_addr(bias_addr), 
        .bias_data(bias_data),
        .ext_read_mode(ext_read_mode), 
        .ext_read_addr_flat(ext_read_addr_flat),
        .bram_read_data_flat(bram_read_data_flat),
        .bram_read_addr_flat(bram_read_addr_flat)
    );

endmodule