`timescale 1ns / 1ps
`include "axi_header_parser.v"
`include "axis_custom_top.v"

/**
 * AXI Stream Custom Top with Header Parser
 * 
 * Adds packet-based control protocol:
 *   - First 6 words = header (control parameters)
 *   - Remaining words = data payload
 * 
 * Usage from PS:
 *   1. Send packet header (6 words)
 *   2. Send data payload (N words)
 *   3. Assert TLAST on last word
 */

module axis_control_wrapper #(
    parameter BRAM_DEPTH = 512,
    parameter DATA_WIDTH = 16,
    parameter BRAM_COUNT = 16,
    parameter ADDR_WIDTH = 9
)(
    // Clock and Reset
    input wire aclk,
    input wire aresetn,
    
    // ========================================================================
    // AXI Stream Slave (from DMA MM2S) - WITH HEADER
    // ========================================================================
    input wire [DATA_WIDTH-1:0] s_axis_tdata,
    input wire s_axis_tvalid,
    output wire s_axis_tready,
    input wire s_axis_tlast,
    
    // ========================================================================
    // AXI Stream Master (to DMA S2MM)
    // ========================================================================
    output wire [DATA_WIDTH-1:0] m_axis_tdata,
    output wire m_axis_tvalid,
    input wire m_axis_tready,
    output wire m_axis_tlast,
    
    // ========================================================================
    // Status outputs
    // ========================================================================
    output wire write_done,
    output wire read_done,
    output wire [9:0] mm2s_data_count,
    
    // Debug
    output wire [2:0] parser_state,
    output wire error_invalid_magic,
    
    // ========================================================================
    // BRAM Write Interface - FLATTENED (to 16 BRAM)
    // ========================================================================
    output wire [BRAM_COUNT*DATA_WIDTH-1:0] bram_wr_data_flat,
    output wire [ADDR_WIDTH-1:0]            bram_wr_addr,
    output wire [BRAM_COUNT-1:0]            bram_wr_en,
    
    // ========================================================================
    // BRAM Read Interface - FLATTENED (from 8 BRAM)
    // ========================================================================
    input  wire [8*DATA_WIDTH-1:0]          bram_rd_data_flat,
    output wire [ADDR_WIDTH-1:0]            bram_rd_addr
);

    // ========================================================================
    // Internal Signals
    // ========================================================================
    
    // Parsed header to axis_custom_top
    wire [7:0]  instruction_code;
    wire [4:0]  wr_bram_start, wr_bram_end;
    wire [15:0] wr_addr_start, wr_addr_count;
    wire [2:0]  rd_bram_start, rd_bram_end;
    wire [15:0] rd_addr_start, rd_addr_count;
    wire        header_valid;
    
    // Registered control (latched on header_valid)
    reg [7:0]  instruction_code_reg;
    reg [4:0]  wr_bram_start_reg, wr_bram_end_reg;
    reg [15:0] wr_addr_start_reg, wr_addr_count_reg;
    reg [2:0]  rd_bram_start_reg, rd_bram_end_reg;
    reg [15:0] rd_addr_start_reg, rd_addr_count_reg;
    
    // Parser to axis_custom_top connection
    wire [DATA_WIDTH-1:0] parser_tdata;
    wire parser_tvalid;
    wire parser_tready;
    wire parser_tlast;
    
    // ========================================================================
    // Header Parser
    // ========================================================================
    axi_header_parser #(
        .DATA_WIDTH(DATA_WIDTH)
    ) parser_inst (
        .aclk(aclk),
        .aresetn(aresetn),
        
        // Input from DMA
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tlast(s_axis_tlast),
        
        // Output to axis_custom_top (data only, no header)
        .m_axis_tdata(parser_tdata),
        .m_axis_tvalid(parser_tvalid),
        .m_axis_tready(parser_tready),
        .m_axis_tlast(parser_tlast),
        
        // Extracted parameters
        .instruction_code(instruction_code),
        .bram_start(wr_bram_start),      // For write
        .bram_end(wr_bram_end),          // For write
        .addr_start(wr_addr_start),
        .addr_count(wr_addr_count),
        .header_valid(header_valid),
        
        // Status
        .error_invalid_magic(error_invalid_magic),
        .parser_state_debug(parser_state)
    );
    
    // For read parameters, use same fields (or extend parser if needed)
    assign rd_bram_start = wr_bram_start[2:0];  // Lower 3 bits
    assign rd_bram_end = wr_bram_end[2:0];
    assign rd_addr_start = wr_addr_start;
    assign rd_addr_count = wr_addr_count;
    
    // ========================================================================
    // Latch Control Parameters
    // ========================================================================
    always @(posedge aclk) begin
        if (!aresetn) begin
            instruction_code_reg <= 8'b0;
            wr_bram_start_reg <= 5'b0;
            wr_bram_end_reg <= 5'b0;
            wr_addr_start_reg <= 16'b0;
            wr_addr_count_reg <= 16'b0;
            rd_bram_start_reg <= 3'b0;
            rd_bram_end_reg <= 3'b0;
            rd_addr_start_reg <= 16'b0;
            rd_addr_count_reg <= 16'b0;
        end else if (header_valid) begin
            // Latch when header complete
            instruction_code_reg <= instruction_code;
            wr_bram_start_reg <= wr_bram_start;
            wr_bram_end_reg <= wr_bram_end;
            wr_addr_start_reg <= wr_addr_start;
            wr_addr_count_reg <= wr_addr_count;
            rd_bram_start_reg <= rd_bram_start;
            rd_bram_end_reg <= rd_bram_end;
            rd_addr_start_reg <= rd_addr_start;
            rd_addr_count_reg <= rd_addr_count;
        end
    end
    
    // ========================================================================
    // Instantiate axis_custom_top
    // ========================================================================
    axis_custom_top #(
        .BRAM_DEPTH(BRAM_DEPTH),
        .DATA_WIDTH(DATA_WIDTH),
        .BRAM_COUNT(BRAM_COUNT),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) axis_top_inst (
        .aclk(aclk),
        .aresetn(aresetn),
        
        // Data stream (header already removed by parser)
        .s_axis_tdata(parser_tdata),
        .s_axis_tvalid(parser_tvalid),
        .s_axis_tready(parser_tready),
        .s_axis_tlast(parser_tlast),
        
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast(m_axis_tlast),
        
        // Control (from latched registers)
        .Instruction_code(instruction_code_reg),
        .wr_bram_start(wr_bram_start_reg),
        .wr_bram_end(wr_bram_end_reg),
        .wr_addr_start(wr_addr_start_reg),
        .wr_addr_count(wr_addr_count_reg),
        .rd_bram_start(rd_bram_start_reg),
        .rd_bram_end(rd_bram_end_reg),
        .rd_addr_start(rd_addr_start_reg),
        .rd_addr_count(rd_addr_count_reg),
        
        .write_done(write_done),
        .read_done(read_done),
        .mm2s_data_count(mm2s_data_count),
        
        // BRAM interface
        .bram_wr_data_flat(bram_wr_data_flat),
        .bram_wr_addr(bram_wr_addr),
        .bram_wr_en(bram_wr_en),
        .bram_rd_data_flat(bram_rd_data_flat),
        .bram_rd_addr(bram_rd_addr)
    );

endmodule