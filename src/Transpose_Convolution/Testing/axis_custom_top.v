`timescale 1ns / 1ps

/******************************************************************************
 * axis_custom_top - FIXED FSM LOGIC
 * * BUG FIX:
 * - Changed FSM transition condition for WRITE/READ DONE.
 * - Previous logic failed because word_counter resets to 0 upon BRAM switch.
 * - New logic checks ONLY bram_counter > end.
 ******************************************************************************/

module axis_custom_top #(
    parameter BRAM_DEPTH = 512,
    parameter DATA_WIDTH = 16,
    parameter BRAM_COUNT = 16,
    parameter ADDR_WIDTH = 9
)(
    input wire aclk,
    input wire aresetn,
    
    // AXI Stream Slave
    input wire [DATA_WIDTH-1:0] s_axis_tdata,
    input wire s_axis_tvalid,
    output reg s_axis_tready,
    input wire s_axis_tlast,
    
    // AXI Stream Master
    output reg [DATA_WIDTH-1:0] m_axis_tdata,
    output reg m_axis_tvalid,
    input wire m_axis_tready,
    output reg m_axis_tlast,
    
    // Control signals
    input wire [7:0] Instruction_code,
    input wire [4:0] wr_bram_start,
    input wire [4:0] wr_bram_end,
    input wire [15:0] wr_addr_start,
    input wire [15:0] wr_addr_count,
    input wire [2:0] rd_bram_start,
    input wire [2:0] rd_bram_end,
    input wire [15:0] rd_addr_start,
    input wire [15:0] rd_addr_count,
    
    // Notification data
    input wire [15:0] notification_data_0,
    input wire [15:0] notification_data_1,
    input wire [15:0] notification_data_2,
    input wire [15:0] notification_data_3,
    input wire        notification_mode,
    
    // BRAM interface
    output reg [BRAM_COUNT*DATA_WIDTH-1:0] bram_wr_data_flat,
    output reg [ADDR_WIDTH-1:0] bram_wr_addr,
    output reg [BRAM_COUNT-1:0] bram_wr_en,
    input wire [BRAM_COUNT*DATA_WIDTH-1:0] bram_rd_data_flat,
    output reg [ADDR_WIDTH-1:0] bram_rd_addr,
    
    // Status
    output reg write_done,
    output reg read_done
);
    // FSM States
    localparam IDLE = 3'd0;
    localparam WRITE = 3'd1;
    localparam READ = 3'd2;
    localparam DONE = 3'd3;
    
    reg [2:0] state, next_state;
    
    // Notification packet register
    reg [15:0] notification_packet [0:3];
    always @(posedge aclk) begin
        if (!aresetn) begin
            notification_packet[0] <= 16'd0;
            notification_packet[1] <= 16'd0;
            notification_packet[2] <= 16'd0;
            notification_packet[3] <= 16'd0;
        end else begin
            notification_packet[0] <= notification_data_0;
            notification_packet[1] <= notification_data_1;
            notification_packet[2] <= notification_data_2;
            notification_packet[3] <= notification_data_3;
        end
    end
    
    // Counters
    reg [15:0] word_counter;
    reg [4:0] bram_counter;
    
    // FSM
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn)
            state <= IDLE;
        else
            state <= next_state;
    end
    
    always @(*) begin
        next_state = state;
        case (state)
            IDLE: begin
                if (Instruction_code == 8'h01)
                    next_state = WRITE;
                else if (Instruction_code == 8'h02)
                    next_state = READ;
            end
            
            WRITE: begin
                // FIX: Check only if we passed the last BRAM
                if (bram_counter > wr_bram_end)
                    next_state = DONE;
            end
            
            READ: begin
                if (notification_mode) begin
                    // Notification: 4 words only
                    if (word_counter >= 4)
                        next_state = DONE;
                end else begin
                    // Normal Read: FIX condition here too
                    if (bram_counter > rd_bram_end)
                        next_state = DONE;
                end
            end
            
            DONE: begin
                next_state = IDLE;
            end
        endcase
    end
    
    // Datapath
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            m_axis_tdata <= 16'd0;
            m_axis_tvalid <= 1'b0;
            m_axis_tlast <= 1'b0;
            s_axis_tready <= 1'b0;
            
            bram_wr_data_flat <= {BRAM_COUNT*DATA_WIDTH{1'b0}};
            bram_wr_addr <= {ADDR_WIDTH{1'b0}};
            bram_wr_en <= {BRAM_COUNT{1'b0}};
            bram_rd_addr <= {ADDR_WIDTH{1'b0}};
            
            word_counter <= 16'd0;
            bram_counter <= 5'd0;
            write_done <= 1'b0;
            read_done <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    m_axis_tvalid <= 1'b0;
                    m_axis_tlast <= 1'b0;
                    s_axis_tready <= 1'b0;
                    bram_wr_en <= {BRAM_COUNT{1'b0}};
                    word_counter <= 16'd0;
                    bram_counter <= 5'd0;
                    write_done <= 1'b0;
                    read_done <= 1'b0;
                    
                    if (Instruction_code == 8'h01) begin
                        s_axis_tready <= 1'b1;
                        bram_counter <= wr_bram_start;
                        bram_wr_addr <= wr_addr_start[ADDR_WIDTH-1:0];
                    end else if (Instruction_code == 8'h02) begin
                        bram_counter <= {2'b0, rd_bram_start};
                        bram_rd_addr <= rd_addr_start[ADDR_WIDTH-1:0];
                    end
                end
                
                WRITE: begin
                    if (s_axis_tvalid && s_axis_tready) begin
                        // Safeguard: only write if within bounds
                        if (bram_counter < BRAM_COUNT) begin
                            bram_wr_data_flat[bram_counter*DATA_WIDTH +: DATA_WIDTH] <= s_axis_tdata;
                            bram_wr_en[bram_counter] <= 1'b1;
                        end
                        
                        word_counter <= word_counter + 1;
                        
                        if (word_counter >= wr_addr_count - 1) begin
                            // Move to next BRAM
                            word_counter <= 16'd0;
                            bram_counter <= bram_counter + 1;
                            bram_wr_addr <= wr_addr_start[ADDR_WIDTH-1:0];
                        end else begin
                            bram_wr_addr <= bram_wr_addr + 1;
                        end
                        
                        if (s_axis_tlast) begin
                            s_axis_tready <= 1'b0;
                        end
                    end else begin
                        bram_wr_en <= {BRAM_COUNT{1'b0}};
                    end
                end
                
                READ: begin
                    if (notification_mode) begin
                        // NOTIFICATION MODE
                        m_axis_tdata <= notification_packet[word_counter[1:0]];
                        m_axis_tvalid <= 1'b1;
                        
                        if (word_counter == 3)
                            m_axis_tlast <= 1'b1;
                            
                        if (m_axis_tready) begin
                            word_counter <= word_counter + 1;
                        end
                        
                    end else begin
                        // NORMAL MODE
                        if (bram_counter < BRAM_COUNT)
                            m_axis_tdata <= bram_rd_data_flat[bram_counter*DATA_WIDTH +: DATA_WIDTH];
                        else
                            m_axis_tdata <= 16'd0;

                        m_axis_tvalid <= 1'b1;
                        
                        if (m_axis_tready) begin
                            word_counter <= word_counter + 1;
                            
                            if (word_counter >= rd_addr_count - 1) begin
                                // Move to next BRAM
                                word_counter <= 16'd0;
                                bram_counter <= bram_counter + 1;
                                bram_rd_addr <= rd_addr_start[ADDR_WIDTH-1:0];
                                
                                // Logic for TLAST
                                if (bram_counter >= rd_bram_end)
                                    m_axis_tlast <= 1'b1;
                            end else begin
                                bram_rd_addr <= bram_rd_addr + 1;
                            end
                        end
                    end
                end
                
                DONE: begin
                    m_axis_tvalid <= 1'b0;
                    m_axis_tlast <= 1'b0;
                    bram_wr_en <= {BRAM_COUNT{1'b0}};
                    s_axis_tready <= 1'b0;
                    
                    if (Instruction_code == 8'h01)
                        write_done <= 1'b1;
                    else if (Instruction_code == 8'h02)
                        read_done <= 1'b1;
                end
            endcase
        end
    end

endmodule