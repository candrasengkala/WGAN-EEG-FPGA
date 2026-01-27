`timescale 1ns / 1ps
`include "External_AXI_FSM.v"
`include "MM2S_S2MM.v"
`include "axis_counter.v"
`include "demux1to16.v"
`include "mux8to1.v"

/******************************************************************************
 * Module      : axis_custom_top
 * Author      : Dharma Anargya Jowandy
 * Date        : January 2026
 *
 * Description :
 * Top-level integration hub for the custom AXI-Stream processing system.
 * This module interconnects the data movers (FIFOs), control logic (FSM),
 * and physical memory resources (BRAM banks).
 *
 * Key Features :
 * - Header Injection
 *   Temporarily stalls the AXI-Stream data path to insert custom headers
 *   into the outgoing stream.
 *
 * - Auto-Trigger Control Logic
 *   Overrides external instructions to force Read Mode based on internal
 *   requests from the Output Manager (e.g., full data dump operation).
 *
 * - Data Routing
 *   Demultiplexes incoming AXI-Stream data across multiple BRAM banks
 *   and multiplexes data readback from BRAMs to the output stream.
 *
 * Parameters :
 * - BRAM_DEPTH : Depth of each BRAM bank
 * - DATA_WIDTH : Width of the data bus in bits (default: 16)
 * - BRAM_COUNT : Number of BRAM banks (default: 16)
 * - ADDR_WIDTH : Address width for BRAM addressing
 *
 * Inputs :
 * - s_axis_*        : AXI-Stream Slave interface (Data Input)
 * - Instruction_code: Current command from Header Parser
 * - header_word_*  : Custom header payload data
 * - send_header    : Trigger signal to inject header
 *
 * Outputs :
 * - m_axis_*       : AXI-Stream Master interface (Data Output)
 * - bram_wr_*      : BRAM write interface signals
 * - bram_rd_*      : BRAM read interface signals
 * - write_done     : Write completion flag to Output Manager
 * - read_done      : Read completion flag to Output Manager
 *
 ******************************************************************************/


module axis_custom_top #(
    parameter BRAM_DEPTH = 512,
    parameter DATA_WIDTH = 16,
    parameter BRAM_COUNT = 16,
    parameter ADDR_WIDTH = 9
)(
    input wire aclk,
    input wire aresetn,
    
    // AXI Stream Slave (Input from DMA/Host)
    input wire [DATA_WIDTH-1:0] s_axis_tdata,
    input wire s_axis_tvalid,
    output wire s_axis_tready,
    input wire s_axis_tlast,
    
    // AXI Stream Master (Output to DMA/Host)
    output wire [DATA_WIDTH-1:0] m_axis_tdata,
    output wire m_axis_tvalid,
    input wire m_axis_tready,
    output wire m_axis_tlast,
    
    // FSM Control Signals (From Parser)
    input wire [7:0] Instruction_code,
    input wire [4:0] wr_bram_start, input wire [4:0] wr_bram_end,
    input wire [15:0] wr_addr_start, input wire [15:0] wr_addr_count,
    input wire [2:0] rd_bram_start, input wire [2:0] rd_bram_end,
    input wire [15:0] rd_addr_start, input wire [15:0] rd_addr_count,
    
    // Header Injection Interface (From Output Manager)
    input wire [15:0] header_word_0, header_word_1, header_word_2,
    input wire [15:0] header_word_3, header_word_4, header_word_5,
    input wire        send_header,
    input wire        notification_only,
    
    // Status Outputs
    output wire write_done, read_done,
    output wire [9:0] mm2s_data_count,
    
    // Physical BRAM Interface
    output wire [BRAM_COUNT*DATA_WIDTH-1:0] bram_wr_data_flat,
    output wire [ADDR_WIDTH-1:0]            bram_wr_addr,
    output wire [BRAM_COUNT-1:0]            bram_wr_en,
    input  wire [8*DATA_WIDTH-1:0]          bram_rd_data_flat,
    output wire [ADDR_WIDTH-1:0]            bram_rd_addr
);

    // Internal Signal Declarations
    wire [DATA_WIDTH-1:0] mm2s_tdata, s2mm_tdata, mux_out;
    wire mm2s_tvalid, mm2s_tready, mm2s_tlast;
    wire s2mm_tvalid, s2mm_tready, s2mm_tlast;
    wire wr_counter_enable, wr_counter_start, rd_counter_enable, rd_counter_start;
    wire [15:0] wr_counter, rd_counter, wr_start_addr, wr_count_limit, rd_start_addr, rd_count_limit;
    wire wr_counter_done, rd_counter_done;
    wire [4:0] demux_sel;
    wire [2:0] mux_sel;
    wire bram_rd_enable;
    wire [DATA_WIDTH-1:0] demux_out [0:BRAM_COUNT-1];
    wire [DATA_WIDTH-1:0] bram_dout [0:7];
    wire fsm_batch_write_done, fsm_batch_read_done;
    
    wire bram_wr_enable_original;
    assign bram_wr_enable_original = mm2s_tvalid && mm2s_tready;

    // ========================================================================
    // HEADER INJECTION & AUTO TRIGGER LOGIC
    // ========================================================================
    // Buffers and state for hijacking the output stream to send headers
    reg [15:0] header_buffer [0:5];
    reg [2:0]  header_word_count;
    reg        sending_header;
    reg        header_sent;
    reg        auto_read_active;
    reg        is_notification_mode;
    
    // Latches to store Read parameters during Auto-Mode
    reg [2:0]  latched_rd_bram_start;
    reg [2:0]  latched_rd_bram_end;
    reg [15:0] latched_rd_addr_count;

    always @(posedge aclk) begin
        if (!aresetn) begin
            header_word_count <= 0;
            sending_header <= 0; 
            header_sent <= 0;
            auto_read_active <= 0;
            is_notification_mode <= 0;
            latched_rd_bram_start <= 0;
            latched_rd_bram_end <= 0;
            latched_rd_addr_count <= 0;
        end else begin
            // 1. Trigger Logic: Capture header data when requested
            if (send_header && !sending_header && !header_sent) begin
                header_buffer[0] <= header_word_0;
                header_buffer[1] <= header_word_1;
                header_buffer[2] <= header_word_2;
                header_buffer[3] <= header_word_3;
                header_buffer[4] <= header_word_4;
                header_buffer[5] <= header_word_5;
                
                latched_rd_bram_start <= rd_bram_start;
                latched_rd_bram_end   <= rd_bram_end;
                latched_rd_addr_count <= rd_addr_count;
                
                is_notification_mode <= notification_only;
                sending_header <= 1;
                header_word_count <= 0;
                auto_read_active <= 1;
                $display("[%0t] [TOP] send_header: notif_mode=%b, rd_start=%0d, rd_end=%0d, rd_count=%0d",
                         $time, notification_only, rd_bram_start, rd_bram_end, rd_addr_count);
            end
            
            // 2. Sending Logic: Shift out the 6 header words
            if (sending_header && s2mm_tready) begin
                if (header_word_count < 5) begin
                    header_word_count <= header_word_count + 1;
                end else begin
                    sending_header <= 0;
                    header_sent <= 1;
                    $display("[%0t] [TOP] Header complete, header_sent=1, notif_mode=%b", 
                             $time, is_notification_mode);
                end
            end
            
            // 3. Cleanup Logic: Determine when to release control
            if (header_sent) begin
                if (is_notification_mode) begin
                    // For notifications, we are done immediately after header
                    header_sent <= 0;
                    auto_read_active <= 0;
                    is_notification_mode <= 0;
                    $display("[%0t] [TOP] Notification done, reset state", $time);
                end else begin
                    // For Full Data, wait until the FSM finishes reading BRAMs
                    if (fsm_batch_read_done) begin
                        header_sent <= 0;
                        auto_read_active <= 0;
                        is_notification_mode <= 0;
                        $display("[%0t] [TOP] Full data read done, reset state", $time);
                    end
                end
            end
        end
    end
    
    // Mux output: Select between Header Buffer or BRAM Data
    assign s2mm_tdata = sending_header ? header_buffer[header_word_count] : mux_out;

    // ========================================================================
    // INSTRUCTION & PARAMETER ROUTING
    // ========================================================================
    // Switch between external instructions (from Parser) and internal Auto-Read
    wire use_auto_mode = auto_read_active;

    // CRITICAL: Force instruction to 0x02 (READ) if in Auto-Mode and header is sent
    wire [7:0] instruction_to_fsm;
    assign instruction_to_fsm = (use_auto_mode && header_sent && !is_notification_mode) ? 8'h02 : 
                                 Instruction_code;

    // Parameter Muxing
    wire [2:0]  rd_bram_start_to_fsm = use_auto_mode ? latched_rd_bram_start : rd_bram_start;
    wire [2:0]  rd_bram_end_to_fsm   = use_auto_mode ? latched_rd_bram_end   : rd_bram_end;
    wire [15:0] rd_addr_count_to_fsm = use_auto_mode ? latched_rd_addr_count : rd_addr_count;
    
    // Wake up FSM if it was IDLE but we need to start Auto-Read
    wire fsm_needs_trigger = use_auto_mode && header_sent && !is_notification_mode;
    wire fsm_trigger_enable = bram_wr_enable_original || fsm_needs_trigger;

    // Debugging
    always @(posedge aclk) begin
        if (use_auto_mode && header_sent && !is_notification_mode) begin
            $display("[%0t] [TOP] AUTO READ MODE: instruction=0x%02h, trigger=%b", 
                     $time, instruction_to_fsm, fsm_needs_trigger);
        end
    end

    // Core FSM Instance
    External_AXI_FSM fsm_inst (
        .aclk(aclk),
        .aresetn(aresetn),
        .Instruction_code(instruction_to_fsm), 
        .wr_bram_start(wr_bram_start),
        .wr_bram_end(wr_bram_end),
        .wr_addr_start(wr_addr_start),
        .wr_addr_count(wr_addr_count),
        .rd_bram_start(rd_bram_start_to_fsm),
        .rd_bram_end(rd_bram_end_to_fsm),
        .rd_addr_start(rd_addr_start),
        .rd_addr_count(rd_addr_count_to_fsm),
        .bram_wr_enable(fsm_trigger_enable),
        .wr_counter_done(wr_counter_done),
        .rd_counter_done(rd_counter_done),
        .wr_counter_enable(wr_counter_enable),
        .wr_counter_start(wr_counter_start),
        .wr_start_addr(wr_start_addr),
        .wr_count_limit(wr_count_limit),
        .rd_counter_enable(rd_counter_enable),
        .rd_counter_start(rd_counter_start),
        .rd_start_addr(rd_start_addr),
        .rd_count_limit(rd_count_limit),
        .demux_sel(demux_sel),
        .mux_sel(mux_sel),
        .bram_rd_enable(bram_rd_enable),
        .batch_write_done(fsm_batch_write_done),
        .batch_read_done(fsm_batch_read_done)
    );

    // FIFO Wrapper for AXI Stream buffering
    MM2S_S2MM #(.FIFO_DEPTH(512), .DATA_WIDTH(DATA_WIDTH)) fifo_wrapper (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tlast(s_axis_tlast),
        .mm2s_tdata(mm2s_tdata),
        .mm2s_tvalid(mm2s_tvalid),
        .mm2s_tready(mm2s_tready),
        .mm2s_tlast(mm2s_tlast),
        .mm2s_data_count(mm2s_data_count),
        .s2mm_tdata(s2mm_tdata),
        .s2mm_tvalid(s2mm_tvalid),
        .s2mm_tready(s2mm_tready),
        .s2mm_tlast(s2mm_tlast),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast(m_axis_tlast)
    );

    // Address Counters
    axis_counter wr_counter_inst (
        .aclk(aclk),
        .aresetn(aresetn),
        .counter_enable(wr_counter_enable),
        .counter_start(wr_counter_start),
        .start_addr(wr_start_addr),
        .count_limit(wr_count_limit),
        .counter(wr_counter),
        .counter_done(wr_counter_done)
    );
    assign write_done = fsm_batch_write_done;

    axis_counter rd_counter_inst (
        .aclk(aclk),
        .aresetn(aresetn),
        .counter_enable(rd_counter_enable),
        .counter_start(rd_counter_start),
        .start_addr(rd_start_addr),
        .count_limit(rd_count_limit),
        .counter(rd_counter),
        .counter_done(rd_counter_done)
    );
    assign read_done = fsm_batch_read_done;

    // Data Routing (Demux for Write, Mux for Read)
    demux1to16 #(.DATA_WIDTH(DATA_WIDTH)) demux_inst (
        .data_in(mm2s_tdata),
        .sel(demux_sel[3:0]),
        .out_0(demux_out[0]), .out_1(demux_out[1]), .out_2(demux_out[2]), .out_3(demux_out[3]),
        .out_4(demux_out[4]), .out_5(demux_out[5]), .out_6(demux_out[6]), .out_7(demux_out[7]),
        .out_8(demux_out[8]), .out_9(demux_out[9]), .out_10(demux_out[10]), .out_11(demux_out[11]),
        .out_12(demux_out[12]), .out_13(demux_out[13]), .out_14(demux_out[14]), .out_15(demux_out[15])
    );
    
    // Note: Currently using 8-to-1 Mux. Ensure BRAM_COUNT/rd_bram_end aligns with this constraint.
    mux8to1 #(.DATA_WIDTH(DATA_WIDTH)) mux_inst (
        .in_0(bram_dout[0]), .in_1(bram_dout[1]), .in_2(bram_dout[2]), .in_3(bram_dout[3]),
        .in_4(bram_dout[4]), .in_5(bram_dout[5]), .in_6(bram_dout[6]), .in_7(bram_dout[7]),
        .sel(mux_sel[2:0]),
        .data_out(mux_out)
    );

    // Handshaking Logic
    wire fsm_write_active = (fsm_inst.current_state == 4'd2) || (fsm_inst.current_state == 4'd6);
    assign mm2s_tready = fsm_write_active && !wr_counter_done;
    assign s2mm_tvalid = sending_header || (bram_rd_enable && rd_counter_enable);

    // TLAST Generation Logic
    wire is_last_bram = (mux_sel >= latched_rd_bram_end);
    wire auto_read_tlast = rd_counter_done && is_last_bram && header_sent && !is_notification_mode;
    wire normal_read_tlast = rd_counter_done && !use_auto_mode;
    wire notification_tlast = sending_header && (header_word_count == 5) && is_notification_mode;
    
    assign s2mm_tlast = notification_tlast || auto_read_tlast || normal_read_tlast;
    
    // BRAM Connectivity
    genvar i;
    generate
        for (i = 0; i < BRAM_COUNT; i = i + 1) begin : WR_DATA_FLATTEN
            assign bram_wr_data_flat[i*DATA_WIDTH +: DATA_WIDTH] = demux_out[i];
        end
        // Unflattening only first 8 for read due to Mux8to1 limitation
        for (i = 0; i < 8; i = i + 1) begin : RD_DATA_UNFLATTEN
            assign bram_dout[i] = bram_rd_data_flat[i*DATA_WIDTH +: DATA_WIDTH];
        end
    endgenerate
    
    assign bram_wr_addr = wr_counter[ADDR_WIDTH-1:0];
    assign bram_wr_en = (16'b1 << demux_sel) & {16{wr_counter_enable}};
    assign bram_rd_addr = rd_counter[ADDR_WIDTH-1:0];

    // ==========================================
    // DEBUG: COLLISION DETECTOR
    // ==========================================
    always @(posedge aclk) begin
        // Check if Output_Manager requests a header while one is already being sent
        if (send_header && sending_header) begin
            $display("[%0t] [TOP] CRITICAL WARNING: Request 'send_header' IGNORED!", $time);
            $display("             Reason: System busy sending previous header.");
        end

        // Monitor Instruction Override
        if (Instruction_code != instruction_to_fsm) begin
             $display("[%0t] [TOP] Instruction Change: Port=0x%h -> Internal=0x%h (Trigger=%b)", 
                      $time, Instruction_code, instruction_to_fsm, fsm_needs_trigger);
        end
    end

endmodule