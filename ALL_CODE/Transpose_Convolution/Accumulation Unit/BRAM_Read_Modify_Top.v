`timescale 1ns / 1ps

/******************************************************************************
 * Module: BRAM_Read_Modify_Top (FULL MUX VERSION)
 * * Description:
 * Top-level wrapper for output BRAM array and accumulation unit.
 * Manages 16 dual-port BRAMs with FULL read/write arbitration using 3-to-1 MUXs.
 * * * ARBITRATION (WRITE PORT A):
 * - Source 0: Accumulation Unit (Transposed Conv)
 * - Source 1: AXI Bias Wrapper (Bias Loading)
 * - Source 2: Standard Convolution (Future)
 * * * ARBITRATION (READ PORT B):
 * - Source 0: Accumulation Unit (Read-Modify-Write)
 * - Source 1: External Read / AXI (Result Extraction)
 * - Source 2: Standard Convolution Read (Future)
 ******************************************************************************/

module BRAM_Read_Modify_Top #(
    parameter DW         = 16,  // Data width
    parameter NUM_BRAMS  = 16,  // Number of output BRAMs
    parameter ADDR_WIDTH = 9,   // Address width
    parameter DEPTH      = 512
)(
    input  wire                              clk,
    input  wire                              rst_n,

    // ======================================================
    // BIAS LOAD INTERFACE (AXI Stream Slave)
    // ======================================================
    input  wire [DW-1:0]                     s_bias_axis_tdata,
    input  wire                              s_bias_axis_tvalid,
    output wire                              s_bias_axis_tready,
    input  wire                              s_bias_axis_tlast,

    // ======================================================
    // INPUT FROM SYSTOLIC ARRAY
    // ======================================================
    input  wire signed [DW-1:0]              partial_in,
    input  wire        [3:0]                 col_id,
    input  wire                              partial_valid,

    // Input from MM2IM buffers
    input  wire        [NUM_BRAMS-1:0]       cmap,
    input  wire        [NUM_BRAMS*14-1:0]    omap_flat,   
    
    // ======================================================
    // EXTERNAL READ CONTROL
    // ======================================================
    input  wire                              ext_read_mode,       
    input  wire        [NUM_BRAMS*ADDR_WIDTH-1:0] ext_read_addr_flat,
    input  wire        [NUM_BRAMS-1:0]       ext_read_en, // ENABLE SIGNAL DARI LUAR
    
    // ======================================================
    // OUTPUT (READ PORT DATA)
    // ======================================================
    output wire signed [NUM_BRAMS*DW-1:0]    bram_read_data_flat,  
    output wire        [NUM_BRAMS*ADDR_WIDTH-1:0] bram_read_addr_flat
);

    // ======================================================
    // 1. SOURCE 0 SIGNALS: ACCUMULATION UNIT
    // ======================================================
    wire [NUM_BRAMS*ADDR_WIDTH-1:0] acc_addr_rd_flat;
    wire signed [NUM_BRAMS*DW-1:0]  bram_dout_flat; 
    wire        [NUM_BRAMS-1:0]     acc_we_flat;    
    wire        [NUM_BRAMS*ADDR_WIDTH-1:0] acc_addr_wr_flat;
    wire signed [NUM_BRAMS*DW-1:0]  acc_din_flat;
    
    // Internal Read Enable untuk Accumulation (Default: Always ON saat aktif)
    // Note: Accumulation Unit saat ini belum output RE, jadi kita set 1.
    wire        [NUM_BRAMS-1:0]     acc_re_flat;
    assign acc_re_flat = {NUM_BRAMS{1'b1}}; 

    // ======================================================
    // 2. SOURCE 1 SIGNALS: AXI BIAS WRAPPER & EXTERNAL READ
    // ======================================================
    // Write Signals (Bias Load)
    wire [NUM_BRAMS*DW-1:0]         axi_wr_data_flat;
    wire [ADDR_WIDTH-1:0]           axi_wr_addr_single; 
    wire [NUM_BRAMS*ADDR_WIDTH-1:0] axi_wr_addr_flat;   
    wire [NUM_BRAMS-1:0]            axi_wr_en_flat;
    wire                            axi_write_done;
    
    // Broadcast single AXI address to all BRAMs
    genvar k;
    generate
        for (k = 0; k < NUM_BRAMS; k = k + 1) begin : AXI_ADDR_BROADCAST
            assign axi_wr_addr_flat[k*ADDR_WIDTH +: ADDR_WIDTH] = axi_wr_addr_single;
        end
    endgenerate

    // ======================================================
    // 3. SOURCE 2 SIGNALS: STANDARD CONVOLUTION (FUTURE)
    // ======================================================
    // Tied to 0 for now (Placeholder)
    wire [NUM_BRAMS*DW-1:0]         conv_wr_data_flat;
    wire [NUM_BRAMS*ADDR_WIDTH-1:0] conv_wr_addr_flat;
    wire [NUM_BRAMS-1:0]            conv_wr_en_flat;
    
    wire [NUM_BRAMS*ADDR_WIDTH-1:0] conv_rd_addr_flat;
    wire [NUM_BRAMS-1:0]            conv_rd_en_flat;
    
    assign conv_wr_data_flat = {(NUM_BRAMS*DW){1'b0}};
    assign conv_wr_addr_flat = {(NUM_BRAMS*ADDR_WIDTH){1'b0}};
    assign conv_wr_en_flat   = {NUM_BRAMS{1'b0}};
    
    assign conv_rd_addr_flat = {(NUM_BRAMS*ADDR_WIDTH){1'b0}};
    assign conv_rd_en_flat   = {NUM_BRAMS{1'b0}};

    // ======================================================
    // SELECTOR LOGIC (3-WAY ARBITRATION)
    // ======================================================
    wire [1:0] write_sel;
    wire [1:0] read_sel;
    
    // Priority: Bias Load (1) > Conv (2) > Acc (0)
    assign write_sel = (u_bias_wrapper.instruction_code_reg != 8'd0) ? 2'd1 : 
                       /* (conv_active) ? 2'd2 : */                    2'd0;

    // Priority: External Read (1) > Conv (2) > Acc (0)
    assign read_sel = (ext_read_mode) ? 2'd1 : 
                      /* (conv_active) ? 2'd2 : */ 2'd0;

    // ======================================================
    // INSTANTIATION: Accumulation Unit (Source 0)
    // ======================================================
    accumulation_unit #(
        .DW(DW),
        .NUM_BRAMS(NUM_BRAMS)
    ) u_accumulation (
        .clk               (clk),
        .rst_n             (rst_n),
        .partial_in        (partial_in),
        .col_id            (col_id),
        .partial_valid     (partial_valid),
        .cmap              (cmap),
        .omap_flat         (omap_flat),
        .bram_addr_rd_flat (acc_addr_rd_flat),  
        .bram_dout_flat    (bram_dout_flat),    
        .bram_we           (acc_we_flat),
        .bram_addr_wr_flat (acc_addr_wr_flat),
        .bram_din_flat     (acc_din_flat)
    );

    // ======================================================
    // INSTANTIATION: AXI Control Wrapper (Source 1 - Write)
    // ======================================================
    axis_control_wrapper #(
        .BRAM_DEPTH(DEPTH),
        .DATA_WIDTH(DW),
        .BRAM_COUNT(NUM_BRAMS),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_bias_wrapper (
        .aclk           (clk),
        .aresetn        (rst_n),
        .s_axis_tdata   (s_bias_axis_tdata),
        .s_axis_tvalid  (s_bias_axis_tvalid),
        .s_axis_tready  (s_bias_axis_tready),
        .s_axis_tlast   (s_bias_axis_tlast),
        .m_axis_tdata   (), .m_axis_tvalid(), .m_axis_tready(1'b1), .m_axis_tlast(),
        .write_done     (axi_write_done),
        .read_done      (),
        .mm2s_data_count(),
        .parser_state   (),
        .error_invalid_magic(),
        .bram_wr_data_flat (axi_wr_data_flat),
        .bram_wr_addr      (axi_wr_addr_single), 
        .bram_wr_en        (axi_wr_en_flat),
        .bram_rd_data_flat ({ (8*DW){1'b0} }),
        .bram_rd_addr      () 
    );

    // ======================================================
    // MUX INSTANTIATIONS FOR WRITE PORT (PORT A)
    // ======================================================
    wire [NUM_BRAMS*DW-1:0]         bram_din_muxed;
    wire [NUM_BRAMS*ADDR_WIDTH-1:0] bram_addr_wr_muxed;
    wire [NUM_BRAMS-1:0]            bram_we_muxed;

    // 1. MUX WRITE DATA
    mux_3to1_array_flat #(.NUM_ELEMENTS(NUM_BRAMS), .DATA_WIDTH(DW)) mux_wr_data (
        .sel(write_sel),
        .in0_flat(acc_din_flat),
        .in1_flat(axi_wr_data_flat),
        .in2_flat(conv_wr_data_flat),
        .out_flat(bram_din_muxed)
    );

    // 2. MUX WRITE ADDRESS
    mux_3to1_array_flat #(.NUM_ELEMENTS(NUM_BRAMS), .DATA_WIDTH(ADDR_WIDTH)) mux_wr_addr (
        .sel(write_sel),
        .in0_flat(acc_addr_wr_flat),
        .in1_flat(axi_wr_addr_flat), 
        .in2_flat(conv_wr_addr_flat),
        .out_flat(bram_addr_wr_muxed)
    );

    // 3. MUX WRITE ENABLE
    mux_3to1_array_flat #(.NUM_ELEMENTS(NUM_BRAMS), .DATA_WIDTH(1)) mux_wr_we (
        .sel(write_sel),
        .in0_flat(acc_we_flat),
        .in1_flat(axi_wr_en_flat),
        .in2_flat(conv_wr_en_flat),
        .out_flat(bram_we_muxed)
    );

    // ======================================================
    // MUX INSTANTIATIONS FOR READ PORT (PORT B)
    // ======================================================
    wire [NUM_BRAMS*ADDR_WIDTH-1:0] bram_addr_rd_muxed;
    wire [NUM_BRAMS-1:0]            bram_re_muxed; // New MUX Output

    // 4. MUX READ ADDRESS
    mux_3to1_array_flat #(.NUM_ELEMENTS(NUM_BRAMS), .DATA_WIDTH(ADDR_WIDTH)) mux_rd_addr (
        .sel(read_sel),
        .in0_flat(acc_addr_rd_flat),    
        .in1_flat(ext_read_addr_flat),  
        .in2_flat(conv_rd_addr_flat),   
        .out_flat(bram_addr_rd_muxed)
    );
    
    // 5. MUX READ ENABLE (YANG ANDA MINTA)
    mux_3to1_array_flat #(.NUM_ELEMENTS(NUM_BRAMS), .DATA_WIDTH(1)) mux_rd_en (
        .sel(read_sel),
        .in0_flat(acc_re_flat),     // Accumulation (Always 1)
        .in1_flat(ext_read_en),     // External Read Enable
        .in2_flat(conv_rd_en_flat), // Conv Read Enable (0)
        .out_flat(bram_re_muxed)    // Masuk ke Port B Enable
    );
    
    // Output assignment
    assign bram_read_addr_flat = bram_addr_rd_muxed;
    assign bram_read_data_flat = bram_dout_flat;

    // ======================================================
    // 16 × BRAM INSTANTIATION
    // ======================================================
    genvar i;
    generate
        for (i = 0; i < NUM_BRAMS; i = i + 1) begin : BRAM_ARRAY

            simple_dual_two_clocks_512x16 #(
                .DEPTH      (DEPTH),
                .DATA_WIDTH (DW),
                .ADDR_WIDTH (ADDR_WIDTH)
            ) bram_i (
                // WRITE PORT (Port A) - MUXED
                .clka  (clk),
                .ena   (1'b1), // Port Enable selalu ON (Write dikontrol WEA)
                .wea   (bram_we_muxed[i]),
                .addra (bram_addr_wr_muxed[i*ADDR_WIDTH +: ADDR_WIDTH]),
                .dia   (bram_din_muxed[i*DW +: DW]),

                // READ PORT (Port B) - MUXED
                .clkb  (clk),
                .enb   (bram_re_muxed[i]), // SEKARANG MENGGUNAKAN HASIL MUX
                .addrb (bram_addr_rd_muxed[i*ADDR_WIDTH +: ADDR_WIDTH]),
                .dob   (bram_dout_flat[i*DW +: DW])
            );
        end
    endgenerate

endmodule