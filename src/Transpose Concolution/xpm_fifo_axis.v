`timescale 1ns / 1ps
// Behavioral model of xpm_fifo_axis for simulation purposes
// Simplified version - only implements the signals used in axis_custom.v

module xpm_fifo_axis #(
    parameter CDC_SYNC_STAGES = 2,
    parameter CLOCKING_MODE = "common_clock",
    parameter ECC_MODE = "no_ecc",
    parameter FIFO_DEPTH = 128,
    parameter FIFO_MEMORY_TYPE = "auto",
    parameter PACKET_FIFO = "false",
    parameter PROG_EMPTY_THRESH = 10,
    parameter PROG_FULL_THRESH = 10,
    parameter RD_DATA_COUNT_WIDTH = 1,
    parameter RELATED_CLOCKS = 0,
    parameter SIM_ASSERT_CHK = 0,
    parameter TDATA_WIDTH = 64,
    parameter TDEST_WIDTH = 1,
    parameter TID_WIDTH = 1,
    parameter TUSER_WIDTH = 1,
    parameter USE_ADV_FEATURES = "0004",
    parameter WR_DATA_COUNT_WIDTH = 8
)(
    // Unused outputs
    output wire almost_empty_axis,
    output wire almost_full_axis,
    output wire dbiterr_axis,
    output wire prog_empty_axis,
    output wire prog_full_axis,
    output wire [RD_DATA_COUNT_WIDTH-1:0] rd_data_count_axis,
    output wire sbiterr_axis,
    
    // Unused inputs
    input wire injectdbiterr_axis,
    input wire injectsbiterr_axis,
    
    // Clock and reset
    input wire s_aclk,
    input wire m_aclk,
    input wire s_aresetn,
    
    // Slave (write) interface
    input wire s_axis_tvalid,
    output wire s_axis_tready,
    input wire [TDATA_WIDTH-1:0] s_axis_tdata,
    input wire s_axis_tlast,
    input wire [TDEST_WIDTH-1:0] s_axis_tdest,
    input wire [TID_WIDTH-1:0] s_axis_tid,
    input wire [TUSER_WIDTH-1:0] s_axis_tuser,
    input wire [(TDATA_WIDTH/8)-1:0] s_axis_tstrb,
    input wire [(TDATA_WIDTH/8)-1:0] s_axis_tkeep,
    
    // Master (read) interface
    output reg m_axis_tvalid,
    input wire m_axis_tready,
    output reg [TDATA_WIDTH-1:0] m_axis_tdata,
    output reg m_axis_tlast,
    output wire [TDEST_WIDTH-1:0] m_axis_tdest,
    output wire [TID_WIDTH-1:0] m_axis_tid,
    output wire [TUSER_WIDTH-1:0] m_axis_tuser,
    output wire [(TDATA_WIDTH/8)-1:0] m_axis_tstrb,
    output wire [(TDATA_WIDTH/8)-1:0] m_axis_tkeep,
    
    // Write data count
    output wire [WR_DATA_COUNT_WIDTH-1:0] wr_data_count_axis
);

    // Internal memory
    reg [TDATA_WIDTH-1:0] fifo_mem [0:FIFO_DEPTH-1];
    reg [FIFO_DEPTH-1:0] fifo_last;
    
    // Pointers
    reg [WR_DATA_COUNT_WIDTH-1:0] wr_ptr;
    reg [WR_DATA_COUNT_WIDTH-1:0] rd_ptr;
    reg [WR_DATA_COUNT_WIDTH-1:0] count;
    
    // Status signals
    wire full;
    wire empty;
    
    assign full = (count == FIFO_DEPTH);
    assign empty = (count == 0);
    
    assign s_axis_tready = !full;
    assign wr_data_count_axis = count;
    
    // Unused outputs tied off
    assign almost_empty_axis = (count < 5);
    assign almost_full_axis = (count > (FIFO_DEPTH - 5));
    assign prog_empty_axis = (count < PROG_EMPTY_THRESH);
    assign prog_full_axis = (count > (FIFO_DEPTH - PROG_FULL_THRESH));
    assign dbiterr_axis = 1'b0;
    assign sbiterr_axis = 1'b0;
    assign rd_data_count_axis = {RD_DATA_COUNT_WIDTH{1'b0}};
    assign m_axis_tdest = {TDEST_WIDTH{1'b0}};
    assign m_axis_tid = {TID_WIDTH{1'b0}};
    assign m_axis_tuser = {TUSER_WIDTH{1'b0}};
    assign m_axis_tstrb = {(TDATA_WIDTH/8){1'b1}};
    assign m_axis_tkeep = {(TDATA_WIDTH/8){1'b1}};
    
    // Write logic
    always @(posedge s_aclk) begin
        if (!s_aresetn) begin
            wr_ptr <= 0;
        end
        else if (s_axis_tvalid && s_axis_tready) begin
            fifo_mem[wr_ptr] <= s_axis_tdata;
            fifo_last[wr_ptr] <= s_axis_tlast;
            wr_ptr <= (wr_ptr + 1) % FIFO_DEPTH;
        end
    end
    
    // Read logic - deassert valid after handshake to force reload
    always @(posedge s_aclk) begin
        if (!s_aresetn) begin
            rd_ptr <= 0;
            m_axis_tvalid <= 1'b0;
            m_axis_tdata <= 0;
            m_axis_tlast <= 0;
        end
        else begin
            if (m_axis_tvalid && m_axis_tready) begin
                // Data consumed - increment pointer and DEASSERT valid
                rd_ptr <= (rd_ptr + 1) % FIFO_DEPTH;
                m_axis_tvalid <= 1'b0;
                // Data will be reloaded next cycle when valid=0 and !empty
            end
            else if (!m_axis_tvalid && !empty) begin
                // Load data from current rd_ptr
                m_axis_tdata <= fifo_mem[rd_ptr];
                m_axis_tlast <= fifo_last[rd_ptr];
                m_axis_tvalid <= 1'b1;
            end
        end
    end
    
    // Count logic - same clock domain for simulation
    always @(posedge s_aclk) begin
        if (!s_aresetn) begin
            count <= 0;
        end
        else begin
            case ({s_axis_tvalid && s_axis_tready, m_axis_tvalid && m_axis_tready})
                2'b10: count <= count + 1; // Write only
                2'b01: count <= count - 1; // Read only
                default: count <= count;   // Both or neither
            endcase
        end
    end

endmodule
