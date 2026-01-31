`timescale 1ns / 1ps

/******************************************************************************
 * Module: BRAM_Output_Top (UNIFIED)
 *
 * Description:
 *   Unified output BRAM wrapper supporting BOTH:
 *   - TRANSCONV: Accumulation unit with cmap/omap mapping
 *   - 1DCONV: systolic_out_adder with counter-based addressing
 *
 * Features:
 *   - 16 independent dual-port BRAMs
 *   - Mode selection (conv_mode): 0=1DCONV, 1=TRANSCONV
 *   - Write port: MUXed between accumulation styles
 *   - Read port: MUXed between internal and external access
 *   - Bias input support for 1DCONV mode
 *   - Registered output stages
 *
 * Author: Unified Design
 * Date: January 2026
 ******************************************************************************/

module BRAM_Output_Top #(
    parameter DW         = 16,
    parameter NUM_BRAMS  = 16,
    parameter ADDR_WIDTH = 10,
    parameter DEPTH      = 1024
)(
    input  wire                              clk,
    input  wire                              rst_n,

    // ========================================================================
    // MODE SELECTION
    // ========================================================================
    input  wire                              conv_mode,  // 0=1DCONV, 1=TRANSCONV

    // ========================================================================
    // TRANSCONV INPUTS (from Transpose_top)
    // ========================================================================
    input  wire signed [DW-1:0]              transconv_partial_in,
    input  wire        [3:0]                 transconv_col_id,
    input  wire                              transconv_partial_valid,

    // TRANSCONV Mapping (from MM2IM)
    input  wire        [NUM_BRAMS-1:0]       transconv_cmap,
    input  wire        [NUM_BRAMS*14-1:0]    transconv_omap_flat,

    // ========================================================================
    // 1DCONV INPUTS (from top_lvl_io_control / systolic array)
    // ========================================================================
    input  wire signed [NUM_BRAMS*DW-1:0]    conv_systolic_output,   // Direct from systolic array
    input  wire                              conv_out_new_val_sign,  // New value available

    // 1DCONV Counter-based addressing
    input  wire [ADDR_WIDTH-1:0]             conv_output_addr_wr,    // Write address (counter A)
    input  wire [ADDR_WIDTH-1:0]             conv_output_addr_rd,    // Read address (counter B)

    // 1DCONV BRAM control
    input  wire [NUM_BRAMS-1:0]              conv_ena_output,        // Write port enable
    input  wire [NUM_BRAMS-1:0]              conv_wea_output,        // Write enable
    input  wire [NUM_BRAMS-1:0]              conv_enb_output,        // Read port enable

    // 1DCONV Adder control
    input  wire                              conv_en_reg_adder,      // Enable adder register
    input  wire                              conv_output_systolic_reg_rst,      // Reset Systolic Register
    input  wire                              conv_output_adder_reg_rst,         // Reset Adder Register

    // 1DCONV Output demux control
    input  wire                              conv_output_bram_dest,  // 0=to adder, 1=to external

    // ========================================================================
    // BIAS INPUT (1DCONV mode)
    // ========================================================================
    input  wire                              input_bias,             // Bias mode enable
    input  wire [NUM_BRAMS-1:0]              bias_ena,
    input  wire [NUM_BRAMS-1:0]              bias_wea,
    input  wire [ADDR_WIDTH-1:0]             bias_addr,
    input  wire signed [NUM_BRAMS*DW-1:0]    bias_data,

    // ========================================================================
    // EXTERNAL READ INTERFACE
    // ========================================================================
    input  wire                              ext_read_mode,
    input  wire [NUM_BRAMS*ADDR_WIDTH-1:0]   ext_read_addr_flat,

    // ========================================================================
    // OUTPUTS
    // ========================================================================
    output wire signed [NUM_BRAMS*DW-1:0]    bram_read_data_flat,
    output wire [NUM_BRAMS*ADDR_WIDTH-1:0]   bram_read_addr_flat
);

    // ========================================================================
    // INTERNAL WIRES - TRANSCONV PATH
    // ========================================================================
    wire [NUM_BRAMS*ADDR_WIDTH-1:0] transconv_acc_addr_rd_flat;
    wire signed [NUM_BRAMS*DW-1:0]  transconv_bram_dout_flat;
    wire [NUM_BRAMS-1:0]            transconv_bram_we;
    wire [NUM_BRAMS*ADDR_WIDTH-1:0] transconv_bram_addr_wr_flat;
    wire signed [NUM_BRAMS*DW-1:0]  transconv_bram_din_flat;

    // ========================================================================
    // INTERNAL WIRES - 1DCONV PATH
    // ========================================================================
    wire signed [NUM_BRAMS*DW-1:0]  conv_bram_dout_flat;
    wire signed [NUM_BRAMS*DW-1:0]  conv_systolic_after_adder;
    wire signed [NUM_BRAMS*DW-1:0]  conv_bram_to_adder;
    wire signed [NUM_BRAMS*DW-1:0]  conv_bram_to_adder_reg;
    wire signed [NUM_BRAMS*DW-1:0]  conv_systolic_reg;
    wire signed [NUM_BRAMS*DW-1:0]  conv_output_to_external;

    // ========================================================================
    // INTERNAL WIRES - MUXED SIGNALS
    // ========================================================================
    wire [NUM_BRAMS-1:0]            mux_bram_we;
    wire [NUM_BRAMS*ADDR_WIDTH-1:0] mux_bram_addr_wr_flat;
    wire signed [NUM_BRAMS*DW-1:0]  mux_bram_din_flat;
    wire [NUM_BRAMS*ADDR_WIDTH-1:0] mux_bram_addr_rd_flat;
    wire [NUM_BRAMS-1:0]            mux_bram_ena;
    wire [NUM_BRAMS-1:0]            mux_bram_enb;

    // Common BRAM output
    wire signed [NUM_BRAMS*DW-1:0]  bram_dout_flat;

    // ========================================================================
    // TRANSCONV: ACCUMULATION UNIT
    // ========================================================================
    accumulation_unit #(
        .DW       (DW),
        .NUM_BRAMS(NUM_BRAMS)
    ) u_transconv_accum (
        .clk               (clk),
        .rst_n             (rst_n),
        .partial_in        (transconv_partial_in),
        .col_id            (transconv_col_id),
        .partial_valid     (transconv_partial_valid),
        .cmap              (transconv_cmap),
        .omap_flat         (transconv_omap_flat),
        .bram_addr_rd_flat (transconv_acc_addr_rd_flat),
        .bram_dout_flat    (bram_dout_flat),
        .bram_we           (transconv_bram_we),
        .bram_addr_wr_flat (transconv_bram_addr_wr_flat),
        .bram_din_flat     (transconv_bram_din_flat)
    );

    // ========================================================================
    // 1DCONV: REGISTERED SYSTOLIC OUTPUT
    // ========================================================================
    reg_en_rst #(
        .WIDTH(DW * NUM_BRAMS)
    ) u_conv_systolic_reg (
        .clk (clk),
        .rst (conv_output_systolic_reg_rst),
        .en  (conv_out_new_val_sign),
        .d   (conv_systolic_output),
        .q   (conv_systolic_reg)
    );

    // ========================================================================
    // 1DCONV: REGISTERED BRAM OUTPUT (for adder feedback)
    // ========================================================================
    reg_en_rst #(
        .WIDTH(DW * NUM_BRAMS)
    ) u_conv_bram_to_adder_reg (
        .clk (clk),
        .rst (conv_output_adder_reg_rst),
        .en  (conv_en_reg_adder),
        .d   (conv_bram_to_adder),
        .q   (conv_bram_to_adder_reg)
    );

    // ========================================================================
    // 1DCONV: SYSTOLIC OUTPUT ADDER
    // ========================================================================
    systolic_out_adder #(
        .DW       (DW),
        .Dimension(NUM_BRAMS)
    ) u_conv_adder (
        .in_a   (conv_bram_to_adder_reg),
        .in_b   (conv_systolic_reg),
        .out_val(conv_systolic_after_adder)
    );

    // ========================================================================
    // 1DCONV: OUTPUT DEMUX (to adder or to external)
    // ========================================================================
    dmux_out #(
        .DW       (DW),
        .Dimension(NUM_BRAMS)
    ) u_conv_demux (
        .sel  (conv_output_bram_dest),
        .in   (bram_dout_flat),
        .out_a(conv_bram_to_adder),      // To adder feedback
        .out_b(conv_output_to_external)  // To external read
    );

    // ========================================================================
    // 1DCONV: REGISTERED EXTERNAL OUTPUT
    // ========================================================================
    reg signed [NUM_BRAMS*DW-1:0] conv_output_reg;
    always @(posedge clk) begin
        if (!rst_n)
            conv_output_reg <= {NUM_BRAMS*DW{1'b0}};
        else
            conv_output_reg <= conv_output_to_external;
    end

    // ========================================================================
    // CONTROL MUX: SELECT BETWEEN 1DCONV AND TRANSCONV
    // ========================================================================

    // Write enable MUX
    assign mux_bram_we = conv_mode ? transconv_bram_we :
                         (input_bias ? bias_wea : conv_wea_output);

    // Write address MUX
    assign mux_bram_addr_wr_flat = conv_mode ? transconv_bram_addr_wr_flat :
                                   {NUM_BRAMS{input_bias ? bias_addr : conv_output_addr_wr}};

    // Write data MUX
    assign mux_bram_din_flat = conv_mode ? transconv_bram_din_flat :
                               (input_bias ? bias_data : conv_systolic_after_adder);

    // Write port enable MUX
    assign mux_bram_ena = conv_mode ? {NUM_BRAMS{1'b1}} :
                          (input_bias ? bias_ena : conv_ena_output);

    // Read address MUX
    wire [NUM_BRAMS*ADDR_WIDTH-1:0] internal_rd_addr;
    assign internal_rd_addr = conv_mode ? transconv_acc_addr_rd_flat :
                              {NUM_BRAMS{conv_output_addr_rd}};

    assign mux_bram_addr_rd_flat = ext_read_mode ? ext_read_addr_flat : internal_rd_addr;

    // Read port enable MUX
    // In 1DCONV mode, conv_enb_output is already muxed at system level between
    // external enable (ext_enb_output) and internal control (conv_enb_output)
    // This matches onedconv.v behavior: enb_output_result_chosen = read_mode ? enb_external : enb_control
    assign mux_bram_enb = conv_mode ? {NUM_BRAMS{1'b1}} : conv_enb_output;

    // ========================================================================
    // OUTPUT ASSIGNMENTS
    // ========================================================================
    assign bram_read_addr_flat = mux_bram_addr_rd_flat;

    // Output data MUX (TRANSCONV uses direct BRAM output, 1DCONV uses registered)
    assign bram_read_data_flat = conv_mode ? bram_dout_flat : conv_output_reg;

    // ========================================================================
    // BRAM ARRAY INSTANTIATION (16 x Dual-Port)
    // ========================================================================
    genvar i;
    generate
        for (i = 0; i < NUM_BRAMS; i = i + 1) begin : BRAM_ARRAY

            simple_dual_two_clocks_512x16 #(
                .DATA_WIDTH            (DW),
                .ADDR_WIDTH(ADDR_WIDTH),
                .DEPTH         (DEPTH)
            ) bram_i (
                // WRITE PORT
                .clka  (clk),
                .ena   (mux_bram_ena[i]),
                .wea   (mux_bram_we[i]),
                .addra (mux_bram_addr_wr_flat[i*ADDR_WIDTH +: ADDR_WIDTH]),
                .dia   (mux_bram_din_flat[i*DW +: DW]),

                // READ PORT
                .clkb  (clk),
                .enb   (mux_bram_enb[i]),
                .addrb (mux_bram_addr_rd_flat[i*ADDR_WIDTH +: ADDR_WIDTH]),
                .dob   (bram_dout_flat[i*DW +: DW])
            );

        end
    endgenerate

endmodule

