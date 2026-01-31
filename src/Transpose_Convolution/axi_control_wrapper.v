`timescale 1ns / 1ps
`include "axi_header_parser.v"
`include "axis_custom_top.v"

/******************************************************************************
 * Module      : axis_control_wrapper
 * Author      : Dharma Anargya Jowandy
 * Date        : January 2026
 *
 * Description :
 * Top-level control wrapper acting as the central integration hub.
 * This module connects the AXI Header Parser with the Custom Processing Core
 * and manages control flow arbitration between:
 *   - External commands from the Host (via AXI-Stream)
 *   - Internal triggers from the Output Manager
 *
 * Key Features :
 * - Auto-Reset Instruction Logic
 *   Clears instruction registers immediately after operation completion
 *   to prevent stale or "zombie" states.
 *
 * - Parameter Multiplexing
 *   Dynamically selects between:
 *     • External parameters from AXI Header Parser
 *     • Internal parameters from Output Manager (Auto-Read mode)
 *
 * - Unified BRAM Interface
 *   Exposes flattened BRAM address, data, and control signals to the top level
 *   for simplified physical BRAM integration.
 *
 * Parameters :
 * - BRAM_DEPTH : Depth of each BRAM buffer (default: 512)
 * - DATA_WIDTH : Data path width in bits (default: 16)
 * - BRAM_COUNT : Number of BRAM banks (default: 16)
 * - ADDR_WIDTH : Address bus width (default: 9)
 *
 * Inputs :
 * - s_axis_*   : AXI-Stream Slave interface (DMA → Device)
 * - send_header: Control trigger from Output Manager
 * - header_*   : Internal header parameters from Output Manager
 *
 * Outputs :
 * - m_axis_*   : AXI-Stream Master interface (Device → DMA)
 * - bram_*     : Flattened physical BRAM interfaces
 *
 ******************************************************************************/


module axis_control_wrapper #(
    parameter BRAM_DEPTH = 512,
    parameter DATA_WIDTH = 16,
    parameter BRAM_COUNT = 16,
    parameter ADDR_WIDTH = 9
)(
    // System Signals
    input  wire                              aclk,
    input  wire                              aresetn,
    
    // AXI Stream Slave Interface (From DMA)
    input  wire [DATA_WIDTH-1:0]             s_axis_tdata,
    input  wire                              s_axis_tvalid,
    output wire                              s_axis_tready,
    input  wire                              s_axis_tlast,
    
    // AXI Stream Master Interface (To DMA)
    output wire [DATA_WIDTH-1:0]             m_axis_tdata,
    output wire                              m_axis_tvalid,
    input  wire                              m_axis_tready,
    output wire                              m_axis_tlast,
    
    // Status & Handshake Flags
    output wire                              write_done,
    output wire                              read_done,
    output wire [9:0]                        mm2s_data_count,
    
    // Debug & Parser Status
    output wire [2:0]                        parser_state,
    output wire                              error_invalid_magic,
    
    // Physical BRAM Interface (Write Port)
    output wire [BRAM_COUNT*DATA_WIDTH-1:0]  bram_wr_data_flat,
    output wire [ADDR_WIDTH-1:0]             bram_wr_addr,
    output wire [BRAM_COUNT-1:0]             bram_wr_en,
    
    // Physical BRAM Interface (Read Port)
    input  wire [8*DATA_WIDTH-1:0]           bram_rd_data_flat,
    output wire [ADDR_WIDTH-1:0]             bram_rd_addr,
    
    // Output Manager Control Interface
    input  wire [15:0]                       header_word_0,
    input  wire [15:0]                       header_word_1,
    input  wire [15:0]                       header_word_2,
    input  wire [15:0]                       header_word_3,
    input  wire [15:0]                       header_word_4,
    input  wire [15:0]                       header_word_5,
    input  wire                              send_header,
    input  wire [2:0]                        out_mgr_rd_bram_start,
    input  wire [2:0]                        out_mgr_rd_bram_end,
    input  wire [15:0]                       out_mgr_rd_addr_count,
    input  wire                              notification_mode
);

    // ========================================================================
    // Internal Signals & Registers
    // ========================================================================
    
    // Parser to Control Logic Wires
    wire [7:0]   instruction_code;
    wire [4:0]   wr_bram_start, wr_bram_end;
    wire [15:0]  wr_addr_start, wr_addr_count;
    wire [2:0]   rd_bram_start, rd_bram_end;
    wire [15:0]  rd_addr_start, rd_addr_count;
    wire         header_valid;
    
    // Parser Stream Interconnect
    wire [DATA_WIDTH-1:0] parser_tdata;
    wire                  parser_tvalid;
    wire                  parser_tready;
    wire                  parser_tlast;
    
    // Control Registers (Latched Configuration)
    reg  [7:0]   instruction_code_reg;
    reg  [4:0]   wr_bram_start_reg, wr_bram_end_reg;
    reg  [15:0]  wr_addr_start_reg, wr_addr_count_reg;
    reg  [2:0]   rd_bram_start_reg, rd_bram_end_reg;
    reg  [15:0]  rd_addr_start_reg, rd_addr_count_reg;

    // ========================================================================
    // Module Instantiation: AXI Header Parser
    // ========================================================================
    axi_header_parser #(
        .DATA_WIDTH(DATA_WIDTH)
    ) parser_inst (
        // System
        .aclk                (aclk), 
        .aresetn             (aresetn),
        
        // AXI Slave (Input)
        .s_axis_tdata        (s_axis_tdata), 
        .s_axis_tvalid       (s_axis_tvalid),
        .s_axis_tready       (s_axis_tready), 
        .s_axis_tlast        (s_axis_tlast),
        
        // AXI Master (Pass-through)
        .m_axis_tdata        (parser_tdata), 
        .m_axis_tvalid       (parser_tvalid),
        .m_axis_tready       (parser_tready), 
        .m_axis_tlast        (parser_tlast),
        
        // Extracted Parameters
        .instruction_code    (instruction_code),
        .bram_start          (wr_bram_start), 
        .bram_end            (wr_bram_end),
        .addr_start          (wr_addr_start), 
        .addr_count          (wr_addr_count),
        
        // Status
        .header_valid        (header_valid),
        .error_invalid_magic (error_invalid_magic),
        .parser_state_debug  (parser_state)
    );
    
    // ========================================================================
    // Parameter Multiplexing Logic
    // ========================================================================
    // Determines whether to use External Parameters (from Parser) or
    // Internal Parameters (from Output Manager) based on 'send_header'.
    
    assign rd_bram_start = send_header ? out_mgr_rd_bram_start : wr_bram_start[2:0];
    assign rd_bram_end   = send_header ? out_mgr_rd_bram_end   : wr_bram_end[2:0];
    assign rd_addr_start = send_header ? 16'd0 : wr_addr_start; // FIX: Use 0 for auto-read // Address start is shared/inherited
    assign rd_addr_count = send_header ? out_mgr_rd_addr_count : wr_addr_count;
    
    // ========================================================================
    // Control Register Logic (CRITICAL FIX)
    // ========================================================================
    always @(posedge aclk) begin
        if (!aresetn) begin
            instruction_code_reg <= 8'b0;
            wr_bram_start_reg    <= 5'b0;   wr_bram_end_reg    <= 5'b0;
            wr_addr_start_reg    <= 16'b0;  wr_addr_count_reg  <= 16'b0;
            rd_bram_start_reg    <= 3'b0;   rd_bram_end_reg    <= 3'b0;
            rd_addr_start_reg    <= 16'b0;  rd_addr_count_reg  <= 16'b0;
        end 
        // --------------------------------------------------------------------
        // SAFETY RESET: Clear instruction immediately after operation done.
        // This prevents the "Zombie State" loop in the FSM.
        // --------------------------------------------------------------------
        else if (write_done || read_done) begin
            instruction_code_reg <= 8'b0;
        end
        // --------------------------------------------------------------------
        // LATCHING: Capture new parameters when header is valid
        // --------------------------------------------------------------------
        else if (header_valid) begin
            instruction_code_reg <= instruction_code;
            wr_bram_start_reg    <= wr_bram_start;  wr_bram_end_reg    <= wr_bram_end;
            wr_addr_start_reg    <= wr_addr_start;  wr_addr_count_reg  <= wr_addr_count;
            rd_bram_start_reg    <= rd_bram_start;  rd_bram_end_reg    <= rd_bram_end;
            rd_addr_start_reg    <= rd_addr_start;  rd_addr_count_reg  <= rd_addr_count;
        end
    end
    
    // ========================================================================
    // Module Instantiation: Custom Axis Top
    // ========================================================================
    axis_custom_top #(
        .BRAM_DEPTH (BRAM_DEPTH), 
        .DATA_WIDTH (DATA_WIDTH),
        .BRAM_COUNT (BRAM_COUNT), 
        .ADDR_WIDTH (ADDR_WIDTH)
    ) axis_top_inst (
        // System
        .aclk                (aclk), 
        .aresetn             (aresetn),
        
        // Stream Input (From Parser)
        .s_axis_tdata        (parser_tdata), 
        .s_axis_tvalid       (parser_tvalid),
        .s_axis_tready       (parser_tready), 
        .s_axis_tlast        (parser_tlast),
        
        // Stream Output (To DMA)
        .m_axis_tdata        (m_axis_tdata), 
        .m_axis_tvalid       (m_axis_tvalid),
        .m_axis_tready       (m_axis_tready), 
        .m_axis_tlast        (m_axis_tlast),
        
        // Control Signals (Using auto-clearing register)
        .Instruction_code    (instruction_code_reg),
    
        // Write Parameters
        .wr_bram_start       (wr_bram_start_reg), 
        .wr_bram_end         (wr_bram_end_reg),
        .wr_addr_start       (wr_addr_start_reg), 
        .wr_addr_count       (wr_addr_count_reg),
        
        // Read Parameters (Multiplexed)
        .rd_bram_start       (send_header ? out_mgr_rd_bram_start : rd_bram_start_reg),
        .rd_bram_end         (send_header ? out_mgr_rd_bram_end   : rd_bram_end_reg),
        .rd_addr_start       (rd_addr_start_reg),
        .rd_addr_count       (send_header ? out_mgr_rd_addr_count : rd_addr_count_reg),
        
        // Header Injection Data
        .header_word_0       (header_word_0), .header_word_1 (header_word_1),
        .header_word_2       (header_word_2), .header_word_3 (header_word_3),
        .header_word_4       (header_word_4), .header_word_5 (header_word_5),
        .send_header         (send_header), 
        .notification_only   (notification_mode),
      
        // Status & BRAM
        .write_done          (write_done), 
        .read_done           (read_done),
        .mm2s_data_count     (mm2s_data_count),
        
        .bram_wr_data_flat   (bram_wr_data_flat), 
        .bram_wr_addr        (bram_wr_addr), 
        .bram_wr_en          (bram_wr_en),
        
        .bram_rd_data_flat   (bram_rd_data_flat), 
        .bram_rd_addr        (bram_rd_addr)
    );

endmodule