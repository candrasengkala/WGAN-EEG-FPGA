/******************************************************************************
 * Module: Weight_BRAM_Top_Modified
 * 
 * Description:
 *   Modified Weight BRAM Top with MUX for conv/transconv routing.
 *   - Conv: BRAM out direct to PE
 *   - Transconv: MUX between BRAM out and shift register out
 * 
 * Author: Dharma Anargya Jowandy
 * Date: January 2026
 ******************************************************************************/

module Weight_BRAM_Top_Modified #(
    parameter DW         = 16,
    parameter NUM_BRAMS  = 16,
    parameter ADDR_WIDTH = 11,
    parameter DEPTH      = 2048
)(
    input  wire                              clk,
    input  wire                              rst_n,

    // WRITE INTERFACE
    input  wire        [NUM_BRAMS-1:0]       w_we,
    input  wire        [NUM_BRAMS*ADDR_WIDTH-1:0] w_addr_wr_flat,
    input  wire signed [NUM_BRAMS*DW-1:0]    w_din_flat,

    // READ INTERFACE - CONVOLUTION
    input  wire        [NUM_BRAMS-1:0]       w_re_conv,
    input  wire        [NUM_BRAMS*ADDR_WIDTH-1:0] w_addr_rd_conv_flat,
    
    // READ INTERFACE - TRANSPOSED CONVOLUTION
    input  wire        [NUM_BRAMS-1:0]       w_re_transconv,
    input  wire        [NUM_BRAMS*ADDR_WIDTH-1:0] w_addr_rd_transconv_flat,

    // MODE SELECTOR
    input  wire                              start_conv,
    input  wire                              start_transconv,

    // OUTPUTS
    output wire signed [NUM_BRAMS*DW-1:0]    weight_out_flat
);

    // BRAM outputs
    wire signed [NUM_BRAMS*DW-1:0] bram_out_flat;

    // MUX for read address and enable
    wire [NUM_BRAMS-1:0] w_re_muxed;
    wire [NUM_BRAMS*ADDR_WIDTH-1:0] w_addr_rd_muxed_flat;
    
    // // SHIFT REGISTER OUTPUT (internal wire - dari shift register module)
    // wire signed [NUM_BRAMS*DW-1:0] shift_reg_out_flat;
    
    // MODE REGISTER & SIGNAL
    reg mode_transconv_reg;
    wire mode_transconv;
    
    // Mode combinational logic (no delay):
    // - start_transconv pulse → immediate mode=1
    // - start_conv pulse → immediate mode=0
    // - otherwise → hold mode_transconv_reg
    assign mode_transconv = start_transconv ? 1'b1 : 
                           (start_conv ? 1'b0 : mode_transconv_reg);

    // ========================================================================
    // MODE REGISTER (HOLD STATE)
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            mode_transconv_reg <= 1'b0;
        else if (start_conv)
            mode_transconv_reg <= 1'b0;
        else if (start_transconv)
            mode_transconv_reg <= 1'b1;
    end

    // ========================================================================
    // MUX READ ADDRESS AND ENABLE (2-to-1 for all bits)
    // ========================================================================
    assign w_re_muxed = (mode_transconv == 1'b0) ? w_re_conv : w_re_transconv;
    assign w_addr_rd_muxed_flat = (mode_transconv == 1'b0) ? w_addr_rd_conv_flat : w_addr_rd_transconv_flat;

    // ========================================================================
    // 16 BRAM INSTANCES
    // ========================================================================
    genvar i;
    generate
        for (i = 0; i < NUM_BRAMS; i = i + 1) begin : WEIGHT_BRAM_ARRAY
            simple_dual_two_clocks_512x16 #(
                .DEPTH      (DEPTH),
                .DATA_WIDTH (DW),
                .ADDR_WIDTH (ADDR_WIDTH)
            ) u_weight_bram (
                .clka  (clk),
                .ena   (1'b1),
                .wea   (w_we[i]),
                .addra (w_addr_wr_flat[i*ADDR_WIDTH +: ADDR_WIDTH]),
                .dia   (w_din_flat[i*DW +: DW]),
                .clkb  (clk),
                .enb   (w_re_muxed[i]),
                .addrb (w_addr_rd_muxed_flat[i*ADDR_WIDTH +: ADDR_WIDTH]),
                .dob   (bram_out_flat[i*DW +: DW])
            );
        end
    endgenerate

    // ========================================================================
    // MUX OUTPUT: CONV vs TRANSCONV
    // ========================================================================
    // Conv mode: shift_reg_out → PE (BRAM → shift register → PE)
    // Transconv mode: BRAM → PE (direct)
    assign weight_out_flat = bram_out_flat;
endmodule