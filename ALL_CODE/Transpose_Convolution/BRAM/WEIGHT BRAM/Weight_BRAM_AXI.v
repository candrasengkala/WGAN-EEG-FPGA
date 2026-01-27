`timescale 1ns / 1ps

/******************************************************************************
 * Module: Weight_BRAM_AXI (FIXED INSTANTIATION)
 * * Description:
 * Wrapper module that integrates Weight BRAM, AXI Wrapper, and MUX Logic.
 * * UPDATES:
 * - Fully exposed AXI Master Interface (m_axis_*) to match System_Level_Top usage.
 * - Exposed Debug Signals (parser_state, error, data_count).
 * - Correct instantiation of axis_control_wrapper.
 ******************************************************************************/

module Weight_BRAM_AXI #(
    parameter DW         = 16,
    parameter NUM_BRAMS  = 16,
    parameter ADDR_WIDTH = 11,
    parameter DEPTH      = 2048
)(
    input  wire                              clk,
    input  wire                              rst_n,

    // ======================================================
    // 1. AXI STREAM SLAVE INTERFACE (Input from DMA)
    // ======================================================
    input  wire [DW-1:0]                     s_weight_axis_tdata,
    input  wire                              s_weight_axis_tvalid,
    output wire                              s_weight_axis_tready,
    input  wire                              s_weight_axis_tlast,

    // ======================================================
    // 2. AXI STREAM MASTER INTERFACE (Output/Passthrough)
    // ======================================================
    // Ditambahkan agar wiring sesuai System_Level_Top / Wrapper asli
    output wire [DW-1:0]                     m_weight_axis_tdata,
    output wire                              m_weight_axis_tvalid,
    input  wire                              m_weight_axis_tready,
    output wire                              m_weight_axis_tlast,

    // ======================================================
    // 3. EXTERNAL AXI READ INTERFACE (EXPOSED)
    // ======================================================
    output wire [ADDR_WIDTH-1:0]             ext_axi_rd_addr,
    input  wire [8*DW-1:0]                   ext_axi_rd_data_flat,

    // ======================================================
    // 4. CONTROL FOR INTERNAL TRANSPOSE COUNTER (Source 0)
    // ======================================================
    input  wire                              trans_start,
    input  wire [ADDR_WIDTH-1:0]             trans_addr_start,
    input  wire [ADDR_WIDTH-1:0]             trans_addr_end,
    output wire                              trans_done,

    // ======================================================
    // 5. INPUT: STANDARD CONVOLUTION (Source 1 - External)
    // ======================================================
    input  wire [NUM_BRAMS-1:0]              conv_re,
    input  wire [NUM_BRAMS*ADDR_WIDTH-1:0]   conv_addr_rd_flat,
    input  wire signed [NUM_BRAMS*DW-1:0]    trans_shift_in_flat,

    // ======================================================
    // 6. FINAL OUTPUT & STATUS
    // ======================================================
    output wire signed [NUM_BRAMS*DW-1:0]    weight_out_flat,
    
    // Status & Debug Outputs (Sesuai System_Level_Top)
    output wire                              weight_write_done,
    output wire                              weight_read_done,
    output wire [9:0]                        weight_mm2s_data_count,
    output wire [2:0]                        weight_parser_state,
    output wire                              weight_error_invalid_magic
);

    // ======================================================
    // INTERNAL SIGNALS
    // ======================================================
    
    // Output dari AXI Wrapper (Write Signals)
    wire [NUM_BRAMS*DW-1:0]         axi_wr_data_flat;
    wire [ADDR_WIDTH-1:0]           axi_wr_addr_single;
    wire [NUM_BRAMS*ADDR_WIDTH-1:0] axi_wr_addr_flat;
    wire [NUM_BRAMS-1:0]            axi_wr_en_flat;
    
    // Output dari Internal Counter (Transpose Signals)
    wire [NUM_BRAMS-1:0]            counter_re;
    wire [NUM_BRAMS*ADDR_WIDTH-1:0] counter_addr_rd_flat;
    
    // Output dari MUX Read
    wire [NUM_BRAMS*ADDR_WIDTH-1:0] bram_rd_addr_muxed;
    wire [NUM_BRAMS-1:0]            bram_re_muxed;
    
    // Raw Output dari BRAM
    wire signed [NUM_BRAMS*DW-1:0]  bram_dout_raw; 

    // ======================================================
    // 1. AUTOMATIC READ SELECTOR LOGIC
    // ======================================================
    // Priority: Internal Counter Active (0) > Standard Conv (1)
    wire read_sel;
    assign read_sel = (|counter_re) ? 1'b0 : 1'b1;

    // ======================================================
    // 2. INSTANTIATION: AXI CONTROL WRAPPER (FIXED WIRING)
    // ======================================================
    axis_control_wrapper #(
        .BRAM_DEPTH(DEPTH), 
        .DATA_WIDTH(DW), 
        .BRAM_COUNT(NUM_BRAMS), 
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_axi_wrapper (
        .aclk(clk), 
        .aresetn(rst_n),
        
        // Slave Interface (Input)
        .s_axis_tdata(s_weight_axis_tdata), 
        .s_axis_tvalid(s_weight_axis_tvalid), 
        .s_axis_tready(s_weight_axis_tready), 
        .s_axis_tlast(s_weight_axis_tlast),
        
        // Master Interface (Output - Sekarang Di-wiring keluar)
        .m_axis_tdata(m_weight_axis_tdata), 
        .m_axis_tvalid(m_weight_axis_tvalid), 
        .m_axis_tready(m_weight_axis_tready), 
        .m_axis_tlast(m_weight_axis_tlast),
        
        // Status & Debug
        .write_done(weight_write_done), 
        .read_done(weight_read_done), 
        .mm2s_data_count(weight_mm2s_data_count),
        .parser_state(weight_parser_state), 
        .error_invalid_magic(weight_error_invalid_magic),
        
        // BRAM Write Interface (Direct to Internal Logic)
        .bram_wr_data_flat(axi_wr_data_flat), 
        .bram_wr_addr(axi_wr_addr_single), 
        .bram_wr_en(axi_wr_en_flat),
        
        // BRAM Read Interface (Exposed to External Logic)
        .bram_rd_data_flat(ext_axi_rd_data_flat), 
        .bram_rd_addr(ext_axi_rd_addr) 
    );

    // Broadcast AXI Address (Wrapper output 1 addr -> We copy to 16 addr)
    genvar k;
    generate
        for (k = 0; k < NUM_BRAMS; k = k + 1) begin : ADDR_BC
            assign axi_wr_addr_flat[k*ADDR_WIDTH +: ADDR_WIDTH] = axi_wr_addr_single;
        end
    endgenerate

    // ======================================================
    // 3. INSTANTIATION: INTERNAL COUNTER (TRANSPOSE SOURCE)
    // ======================================================
    Counter_Weight_BRAM #(
        .NUM_BRAMS(NUM_BRAMS),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_trans_counter (
        .clk        (clk),
        .rst_n      (rst_n),
        .start      (trans_start),      
        .addr_start (trans_addr_start), 
        .addr_end   (trans_addr_end),   
        .w_re       (counter_re),       
        .w_addr_rd_flat (counter_addr_rd_flat), 
        .done       (trans_done)        
    );

    // ======================================================
    // 4. MUX INSTANTIATIONS (READ INPUTS)
    // ======================================================
    
    // MUX Read Enable
    mux_2to1_array_flat #(.NUM_ELEMENTS(NUM_BRAMS), .DATA_WIDTH(1)) mux_rd_en (
        .sel(read_sel), 
        .in0_flat(counter_re),  // Sel=0: From Internal Counter
        .in1_flat(conv_re),     // Sel=1: From External Conv
        .out_flat(bram_re_muxed)
    );

    // MUX Read Address
    mux_2to1_array_flat #(.NUM_ELEMENTS(NUM_BRAMS), .DATA_WIDTH(ADDR_WIDTH)) mux_rd_addr (
        .sel(read_sel),
        .in0_flat(counter_addr_rd_flat), // Sel=0: From Internal Counter
        .in1_flat(conv_addr_rd_flat),    // Sel=1: From External Conv
        .out_flat(bram_rd_addr_muxed)
    );

    // ======================================================
    // 5. INSTANTIATION: WEIGHT BRAM TOP (RAW ARRAY)
    // ======================================================
    Weight_BRAM_Top #(
        .DW(DW), .NUM_BRAMS(NUM_BRAMS), .ADDR_WIDTH(ADDR_WIDTH), .DEPTH(DEPTH)
    ) u_bram_top (
        .clk(clk), .rst_n(rst_n),
        // Write: Direct from AXI
        .w_we(axi_wr_en_flat), .w_addr_wr_flat(axi_wr_addr_flat), .w_din_flat(axi_wr_data_flat),
        // Read: From MUX
        .w_re(bram_re_muxed), .w_addr_rd_flat(bram_rd_addr_muxed),
        // Output
        .weight_out_flat(bram_dout_raw)
    );

    // ======================================================
    // 6. MUX INSTANTIATION (OUTPUT DATA)
    // ======================================================
    
    mux_2to1_array_flat #(.NUM_ELEMENTS(NUM_BRAMS), .DATA_WIDTH(DW)) mux_data_out (
        .sel(read_sel),          
        .in0_flat(bram_dout_raw),       // Sel=0: Raw BRAM (Transpose)
        .in1_flat(trans_shift_in_flat), // Sel=1: Shift Reg (Conv)
        .out_flat(weight_out_flat)      // FINAL OUTPUT
    );

endmodule