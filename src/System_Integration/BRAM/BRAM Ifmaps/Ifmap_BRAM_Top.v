/******************************************************************************
 * Module: ifmap_BRAM_Top_Modified
 * 
 * Description:
 *   Modified Ifmap BRAM Top with inline DEMUX 1-to-2 and MUX routing.
 *   - 16 BRAM outputs → 16 DEMUX 1-to-2 (inline)
 *   - DEMUX branch 0 → PE 1-15 flatten + PE0 conv path
 *   - DEMUX branch 1 → MUX 16-to-1 → PE0 transconv path
 *   - MUX 2-to-1 (inline) → PE0 final output
 * 
 * Author: Dharma Anargya Jowandy
 * Date: January 2026
 ******************************************************************************/

module ifmap_BRAM_Top_Modified #(
    parameter DW         = 16,
    parameter NUM_BRAMS  = 16,
    parameter ADDR_WIDTH = 10,
    parameter DEPTH      = 1024
)(
    input  wire                                  clk,
    input  wire                                  rst_n,

    // WRITE INTERFACE
    input  wire        [NUM_BRAMS-1:0]           if_we,
    input  wire        [NUM_BRAMS*ADDR_WIDTH-1:0] if_addr_wr_flat,
    input  wire signed [NUM_BRAMS*DW-1:0]        if_din_flat,

    // READ INTERFACE - CONVOLUTION
    input  wire        [NUM_BRAMS-1:0]           if_re_conv,
    input  wire        [NUM_BRAMS*ADDR_WIDTH-1:0] if_addr_rd_conv_flat,
    
    // READ INTERFACE - TRANSPOSED CONVOLUTION
    input  wire        [NUM_BRAMS-1:0]           if_re_transconv,
    input  wire        [NUM_BRAMS*ADDR_WIDTH-1:0] if_addr_rd_transconv_flat,
    input  wire        [3:0]                     ifmap_sel_transconv,

    // MODE SELECTOR
    input  wire                                  start_conv,
    input  wire                                  start_transconv,

    // OUTPUTS
    output wire signed [(NUM_BRAMS-1)*DW-1:0]    ifmap_out_pe1_to_pe15_flat,
    output wire signed [DW-1:0]                  ifmap_out_pe0
);

    // BRAM outputs
    wire signed [NUM_BRAMS*DW-1:0] ifmap_out_flat;

    // DEMUX outputs
    wire signed [NUM_BRAMS*DW-1:0] demux_branch0;
    wire signed [NUM_BRAMS*DW-1:0] demux_branch1;
    
    // MUX for read address and enable (per BRAM)
    wire [NUM_BRAMS-1:0] if_re_muxed;
    wire [NUM_BRAMS*ADDR_WIDTH-1:0] if_addr_rd_muxed_flat;
    
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
    // 16x MUX 2-to-1 FOR READ ADDRESS AND ENABLE (PER BRAM)
    // ========================================================================
    genvar i;
    generate
        for (i = 0; i < NUM_BRAMS; i = i + 1) begin : MUX_READ_CTRL
            // MUX read enable per BRAM
            assign if_re_muxed[i] = (mode_transconv == 1'b0) ? if_re_conv[i] : if_re_transconv[i];
            
            // MUX read address per BRAM
            assign if_addr_rd_muxed_flat[i*ADDR_WIDTH +: ADDR_WIDTH] = 
                (mode_transconv == 1'b0) ? if_addr_rd_conv_flat[i*ADDR_WIDTH +: ADDR_WIDTH] 
                                         : if_addr_rd_transconv_flat[i*ADDR_WIDTH +: ADDR_WIDTH];
        end
    endgenerate

    // ========================================================================
    // 16 BRAM INSTANCES
    // ========================================================================
    generate
        for (i = 0; i < NUM_BRAMS; i = i + 1) begin : IFMAP_BRAM_ARRAY
            simple_dual_two_clocks_512x16 #(
                .DEPTH      (DEPTH),
                .DATA_WIDTH (DW),
                .ADDR_WIDTH (ADDR_WIDTH)
            ) u_ifmap_bram (
                .clka  (clk),
                .ena   (1'b1),
                .wea   (if_we[i]),
                .addra (if_addr_wr_flat[i*ADDR_WIDTH +: ADDR_WIDTH]),
                .dia   (if_din_flat[i*DW +: DW]),
                .clkb  (clk),
                .enb   (if_re_muxed[i]),
                .addrb (if_addr_rd_muxed_flat[i*ADDR_WIDTH +: ADDR_WIDTH]),
                .dob   (ifmap_out_flat[i*DW +: DW])
            );
        end
    endgenerate

    // ========================================================================
    // INLINE DEMUX 1-to-2 (16x)
    // ========================================================================
    generate
        for (i = 0; i < NUM_BRAMS; i = i + 1) begin : DEMUX_INLINE
            assign demux_branch0[i*DW +: DW] = (mode_transconv == 1'b0) ? ifmap_out_flat[i*DW +: DW] : {DW{1'b0}};
            assign demux_branch1[i*DW +: DW] = (mode_transconv == 1'b1) ? ifmap_out_flat[i*DW +: DW] : {DW{1'b0}};
        end
    endgenerate

    // ========================================================================
    // OUTPUT PE 1-15 (from BRAM 1-15, branch 0)
    // ========================================================================
    assign ifmap_out_pe1_to_pe15_flat = demux_branch0[(NUM_BRAMS-1)*DW-1:0];

    // ========================================================================
    // MUX 16-to-1 WITH CASE (for transconv path - area efficient)
    // ========================================================================
    reg signed [DW-1:0] mux16_out;
    
    always @(*) begin
        case (ifmap_sel_transconv)
            4'd0:  mux16_out = demux_branch1[  0 +: DW];
            4'd1:  mux16_out = demux_branch1[ DW +: DW];
            4'd2:  mux16_out = demux_branch1[ 2*DW +: DW];
            4'd3:  mux16_out = demux_branch1[ 3*DW +: DW];
            4'd4:  mux16_out = demux_branch1[ 4*DW +: DW];
            4'd5:  mux16_out = demux_branch1[ 5*DW +: DW];
            4'd6:  mux16_out = demux_branch1[ 6*DW +: DW];
            4'd7:  mux16_out = demux_branch1[ 7*DW +: DW];
            4'd8:  mux16_out = demux_branch1[ 8*DW +: DW];
            4'd9:  mux16_out = demux_branch1[ 9*DW +: DW];
            4'd10: mux16_out = demux_branch1[10*DW +: DW];
            4'd11: mux16_out = demux_branch1[11*DW +: DW];
            4'd12: mux16_out = demux_branch1[12*DW +: DW];
            4'd13: mux16_out = demux_branch1[13*DW +: DW];
            4'd14: mux16_out = demux_branch1[14*DW +: DW];
            4'd15: mux16_out = demux_branch1[15*DW +: DW];
            default: mux16_out = {DW{1'b0}};
        endcase
    end

    // ========================================================================
    // INLINE MUX 2-to-1 FOR PE0
    // ========================================================================
    assign ifmap_out_pe0 = (mode_transconv == 1'b0) ? demux_branch0[0 +: DW]  // Conv: BRAM 0
                                                     : mux16_out;               // Transconv: MUX 16-to-1

endmodule