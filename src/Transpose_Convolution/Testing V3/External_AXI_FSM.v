`timescale 1ns / 1ps

/******************************************************************************
 * Module      : External_AXI_FSM
 * Author      : Dharma Anargya Jowandy
 * Date        : January 2026
 *
 * Description :
 * Finite State Machine (FSM) that controls data transfer flow between
 * the AXI-Stream interface and internal multi-bank BRAM resources.
 *
 * Functionality :
 * - Manages Write, Read, and Duplex (simultaneous Read/Write) operations.
 * - Controls BRAM bank selection and address progression across banks.
 * - Latches configuration parameters at operation start to guarantee
 *   stable control signals throughout the transaction.
 *
 * Parameters :
 * - None (all widths are defined by input signal buses)
 *
 * Inputs :
 * - Instruction_code : Operation opcode
 *     • 0x01 : Write
 *     • 0x02 : Read
 *     • 0x03 : Duplex (Read/Write)
 *
 * - wr_bram_*  : Target BRAM bank range for write operations
 * - rd_bram_*  : Target BRAM bank range for read operations
 * - wr_addr_*  : Write address range within BRAM banks
 * - rd_addr_*  : Read address range within BRAM banks
 *
 * Outputs :
 * - wr_counter_* : Control signals for write address counters
 * - rd_counter_* : Control signals for read address counters
 * - demux_sel   : BRAM write data demultiplexer select
 * - mux_sel     : BRAM read data multiplexer select
 * - batch_wr_done: Completion flag for write batch operation
 * - batch_rd_done: Completion flag for read batch operation
 *
 ******************************************************************************/


module External_AXI_FSM(
    // System Signals
    input  wire        aclk,
    input  wire        aresetn,
    
    // Command Interface
    input  wire [7:0]  Instruction_code,
    
    // Write Configuration
    input  wire [4:0]  wr_bram_start,
    input  wire [4:0]  wr_bram_end,
    input  wire [15:0] wr_addr_start,
    input  wire [15:0] wr_addr_count,
    
    // Read Configuration
    input  wire [2:0]  rd_bram_start,
    input  wire [2:0]  rd_bram_end,
    input  wire [15:0] rd_addr_start,
    input  wire [15:0] rd_addr_count,

    // Status / Handshake Inputs
    input  wire        bram_wr_enable,
    input  wire        wr_counter_done,
    input  wire        rd_counter_done,

    // Write Control Outputs
    output reg         wr_counter_enable,
    output reg         wr_counter_start,
    output reg  [15:0] wr_start_addr,
    output reg  [15:0] wr_count_limit,

    // Read Control Outputs
    output reg         rd_counter_enable,
    output reg         rd_counter_start,
    output reg  [15:0] rd_start_addr,
    output reg  [15:0] rd_count_limit,

    // Data Routing Outputs
    output reg  [4:0]  demux_sel,
    output reg  [2:0]  mux_sel,
    output reg         bram_rd_enable,
    
    // Completion Status
    output reg         batch_write_done,
    output reg         batch_read_done
);

    // State Encoding
    localparam [3:0]
        IDLE            = 4'd0,
        WRITE_SETUP     = 4'd1,
        WRITE_WAIT      = 4'd2,
        READ_SETUP      = 4'd3,
        READ_WAIT       = 4'd4,
        DUPLEX_SETUP    = 4'd5,
        DUPLEX_WAIT     = 4'd6,
        DONE            = 4'd7;

    // Internal Registers
    reg [3:0]  current_state, next_state;
    reg [4:0]  bram_write_index;
    reg [2:0]  bram_read_index;
    
    // Parameter Latches
    reg [4:0]  wr_bram_start_reg, wr_bram_end_reg;
    reg [15:0] wr_addr_start_reg, wr_addr_count_reg;
    reg [2:0]  rd_bram_start_reg, rd_bram_end_reg;
    reg [15:0] rd_addr_start_reg, rd_addr_count_reg;

    // ========================================================================
    // Sequential Logic (State & Register Updates)
    // ========================================================================
    always @(posedge aclk) begin
        if (!aresetn) begin
            current_state     <= IDLE;
            bram_write_index  <= 5'd0;
            bram_read_index   <= 3'd0;
            
            wr_bram_start_reg <= 5'd0;  wr_bram_end_reg   <= 5'd0;
            wr_addr_start_reg <= 16'd0; wr_addr_count_reg <= 16'd0;
            rd_bram_start_reg <= 3'd0;  rd_bram_end_reg   <= 3'd0;
            rd_addr_start_reg <= 16'd0; rd_addr_count_reg <= 16'd0;
        end
        else begin
            current_state <= next_state;
            
            // Latch parameters continuously in IDLE to capture updates
            if (current_state == IDLE || next_state == IDLE) begin
                if (Instruction_code == 8'h01) begin // WRITE Mode
                    wr_bram_start_reg <= wr_bram_start;
                    wr_bram_end_reg   <= wr_bram_end;
                    wr_addr_start_reg <= wr_addr_start;
                    wr_addr_count_reg <= wr_addr_count;
                    bram_write_index  <= wr_bram_start;
                end
                else if (Instruction_code == 8'h02) begin // READ Mode
                    rd_bram_start_reg <= rd_bram_start;
                    rd_bram_end_reg   <= rd_bram_end;
                    rd_addr_start_reg <= rd_addr_start;
                    rd_addr_count_reg <= rd_addr_count;
                    bram_read_index   <= rd_bram_start;
                end
                else if (Instruction_code == 8'h03) begin // DUPLEX Mode
                    wr_bram_start_reg <= wr_bram_start;
                    wr_bram_end_reg   <= wr_bram_end;
                    wr_addr_start_reg <= wr_addr_start;
                    wr_addr_count_reg <= wr_addr_count;
                    bram_write_index  <= wr_bram_start;
                    
                    rd_bram_start_reg <= rd_bram_start;
                    rd_bram_end_reg   <= rd_bram_end;
                    rd_addr_start_reg <= rd_addr_start;
                    rd_addr_count_reg <= rd_addr_count;
                    bram_read_index   <= rd_bram_start;
                end
            end
            
            // BRAM Bank Index Increment
            if ((current_state == WRITE_WAIT || current_state == DUPLEX_WAIT) && wr_counter_done) begin
                if (bram_write_index < wr_bram_end_reg)
                    bram_write_index <= bram_write_index + 1;
            end
            
            if ((current_state == READ_WAIT || current_state == DUPLEX_WAIT) && rd_counter_done) begin
                if (bram_read_index < rd_bram_end_reg)
                    bram_read_index <= bram_read_index + 1;
            end
        end
    end

    // ========================================================================
    // Combinational Logic (Next State & Output Generation)
    // ========================================================================
    always @(*) begin
        // Default Assignments
        next_state        = current_state;
        wr_counter_enable = 1'b0;
        wr_counter_start  = 1'b0;
        wr_start_addr     = 16'b0;
        wr_count_limit    = 16'b0;
        
        rd_counter_enable = 1'b0;
        rd_counter_start  = 1'b0;
        rd_start_addr     = 16'b0;
        rd_count_limit    = 16'b0;
        
        demux_sel         = 5'b0;
        mux_sel           = 3'b0;
        bram_rd_enable    = 1'b0;
        
        batch_write_done  = 1'b0;
        batch_read_done   = 1'b0;

        case (current_state)
            IDLE: begin
                if      (Instruction_code == 8'h01) next_state = WRITE_SETUP;
                else if (Instruction_code == 8'h02) next_state = READ_SETUP;
                else if (Instruction_code == 8'h03) next_state = DUPLEX_SETUP;
            end

            // --- WRITE LOGIC ---
            WRITE_SETUP: begin 
                wr_counter_start = 1'b1;
                wr_start_addr    = wr_addr_start_reg;
                wr_count_limit   = wr_addr_count_reg;
                demux_sel        = bram_write_index;
                next_state       = WRITE_WAIT;
            end

            WRITE_WAIT: begin
                demux_sel        = bram_write_index;
                wr_start_addr    = wr_addr_start_reg;
                wr_count_limit   = wr_addr_count_reg;
                
                if (!wr_counter_done) begin
                    wr_counter_enable = bram_wr_enable;
                end
                
                // Transition Check: Next BRAM or Done
                if (wr_counter_done) begin
                    if (bram_write_index < wr_bram_end_reg)
                        next_state = WRITE_SETUP;
                    else
                        next_state = DONE;
                end
            end

            // --- READ LOGIC ---
            READ_SETUP: begin 
                rd_counter_start = 1'b1;
                rd_start_addr    = rd_addr_start_reg;
                rd_count_limit   = rd_addr_count_reg;
                mux_sel          = bram_read_index;
                next_state       = READ_WAIT;
            end

            READ_WAIT: begin
                mux_sel           = bram_read_index;
                rd_start_addr     = rd_addr_start_reg;
                rd_count_limit    = rd_addr_count_reg;
                bram_rd_enable    = 1'b1;
                rd_counter_enable = 1'b1;
                
                // Transition Check: Next BRAM or Done
                if (rd_counter_done) begin 
                    if (bram_read_index < rd_bram_end_reg)
                        next_state = READ_SETUP;
                    else
                        next_state = DONE;
                end
            end

            // --- DUPLEX LOGIC ---
            DUPLEX_SETUP: begin
                // Configure Write
                wr_counter_start = 1'b1;
                wr_start_addr    = wr_addr_start_reg;
                wr_count_limit   = wr_addr_count_reg;
                demux_sel        = bram_write_index;
                
                // Configure Read
                rd_counter_start = 1'b1;
                rd_start_addr    = rd_addr_start_reg;
                rd_count_limit   = rd_addr_count_reg;
                mux_sel          = bram_read_index;
                
                next_state       = DUPLEX_WAIT;
            end

            DUPLEX_WAIT: begin
                // Write Control
                demux_sel        = bram_write_index;
                wr_start_addr    = wr_addr_start_reg;
                wr_count_limit   = wr_addr_count_reg;
                if (bram_wr_enable) wr_counter_enable = 1'b1;
                
                // Read Control
                mux_sel           = bram_read_index;
                rd_start_addr     = rd_addr_start_reg;
                rd_count_limit    = rd_addr_count_reg;
                bram_rd_enable    = 1'b1;
                rd_counter_enable = 1'b1;

                // Transition Check: Wait for BOTH to finish
                if (wr_counter_done && rd_counter_done) begin
                    if (bram_write_index >= wr_bram_end_reg && 
                        bram_read_index >= rd_bram_end_reg) begin
                        next_state = DONE;
                    end
                    else begin
                        next_state = DUPLEX_SETUP;
                    end
                end
            end

            // --- COMPLETION ---
            DONE: begin
                next_state = IDLE;
                if (Instruction_code == 8'h01) begin      // WRITE ONLY
                    batch_write_done = 1'b1;
                end
                else if (Instruction_code == 8'h02) begin // READ ONLY
                    batch_read_done = 1'b1;
                end
                else if (Instruction_code == 8'h03) begin // DUPLEX
                    batch_write_done = 1'b1;
                    batch_read_done  = 1'b1;
                end
            end
            
            default: next_state = IDLE;
        endcase
    end

endmodule