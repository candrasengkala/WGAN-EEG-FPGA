`timescale 1ns / 1ps
// MM2S and S2MM FIFO Module - FIXED VERSION
// Modular AXI Stream FIFO for data buffering with parameterized width

module MM2S_S2MM #(
    parameter FIFO_DEPTH = 512,
    parameter DATA_WIDTH = 20  
)
(
    input wire                    aclk,
    input wire                    aresetn,
        
    // *** MM2S - Slave AXI Stream Input ***
    output wire                   s_axis_tready,
    input wire [DATA_WIDTH-1:0]   s_axis_tdata,   
    input wire                    s_axis_tvalid,
    input wire                    s_axis_tlast,
    
    // *** MM2S - Master Output to Processing ***
    input wire                    mm2s_tready,
    output wire [DATA_WIDTH-1:0]  mm2s_tdata,     
    output wire                   mm2s_tvalid,
    output wire                   mm2s_tlast,
    output wire [9:0]             mm2s_data_count,
    
    // *** S2MM - Slave Input from Processing ***
    output wire                   s2mm_tready,
    input wire [DATA_WIDTH-1:0]   s2mm_tdata,     
    input wire                    s2mm_tvalid,
    input wire                    s2mm_tlast,
    
    // *** S2MM - Master AXI Stream Output ***
    input wire                    m_axis_tready,
    output wire [DATA_WIDTH-1:0]  m_axis_tdata,   
    output wire                   m_axis_tvalid,
    output wire                   m_axis_tlast
);

    // ✅ Calculate TKEEP width based on DATA_WIDTH
    localparam TKEEP_WIDTH = (DATA_WIDTH + 7) / 8;  // Ceiling division

    // *** MM2S FIFO ************************************************************
    xpm_fifo_axis
    #(
        .CDC_SYNC_STAGES(2),                 
        .CLOCKING_MODE("common_clock"),      
        .ECC_MODE("no_ecc"),                 
        .FIFO_DEPTH(FIFO_DEPTH),            
        .FIFO_MEMORY_TYPE("auto"),           
        .PACKET_FIFO("false"),               
        .PROG_EMPTY_THRESH(10),              
        .PROG_FULL_THRESH(10),               
        .RD_DATA_COUNT_WIDTH(1),             
        .RELATED_CLOCKS(0),                  
        .SIM_ASSERT_CHK(0),                  
        .TDATA_WIDTH(DATA_WIDTH),            
        .TDEST_WIDTH(1),                     
        .TID_WIDTH(1),                       
        .TUSER_WIDTH(1),                     
        .USE_ADV_FEATURES("0004"),           
        .WR_DATA_COUNT_WIDTH(10)             
    )
    xpm_fifo_axis_mm2s
    (
        .almost_empty_axis(), 
        .almost_full_axis(), 
        .dbiterr_axis(), 
        .prog_empty_axis(), 
        .prog_full_axis(), 
        .rd_data_count_axis(), 
        .sbiterr_axis(), 
        .injectdbiterr_axis(1'b0), 
        .injectsbiterr_axis(1'b0), 
    
        .s_aclk(aclk),
        .m_aclk(aclk),
        .s_aresetn(aresetn),
        
        // Slave port - Input from DMA
        .s_axis_tready(s_axis_tready),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tdest(1'b0), 
        .s_axis_tid(1'b0), 
        .s_axis_tkeep({TKEEP_WIDTH{1'b1}}),  
        .s_axis_tlast(s_axis_tlast),
        .s_axis_tstrb({TKEEP_WIDTH{1'b1}}),  
        .s_axis_tuser(1'b0), 
        
        // Master port - Output to processing
        .m_axis_tready(mm2s_tready),
        .m_axis_tdata(mm2s_tdata),
        .m_axis_tvalid(mm2s_tvalid),
        .m_axis_tdest(), 
        .m_axis_tid(), 
        .m_axis_tkeep(), 
        .m_axis_tlast(mm2s_tlast), 
        .m_axis_tstrb(), 
        .m_axis_tuser(),  
        
        .wr_data_count_axis(mm2s_data_count)
    );
    
    // *** S2MM FIFO ************************************************************
    xpm_fifo_axis
    #(
        .CDC_SYNC_STAGES(2),                 
        .CLOCKING_MODE("common_clock"),      
        .ECC_MODE("no_ecc"),                 
        .FIFO_DEPTH(FIFO_DEPTH),             
        .FIFO_MEMORY_TYPE("auto"),           
        .PACKET_FIFO("false"),               
        .PROG_EMPTY_THRESH(10),              
        .PROG_FULL_THRESH(10),               
        .RD_DATA_COUNT_WIDTH(1),             
        .RELATED_CLOCKS(0),                  
        .SIM_ASSERT_CHK(0),                  
        .TDATA_WIDTH(DATA_WIDTH),            
        .TDEST_WIDTH(1),                     
        .TID_WIDTH(1),                       
        .TUSER_WIDTH(1),                     
        .USE_ADV_FEATURES("0000"),           
        .WR_DATA_COUNT_WIDTH(1)              
    )
    xpm_fifo_axis_s2mm
    (
        .almost_empty_axis(), 
        .almost_full_axis(), 
        .dbiterr_axis(), 
        .prog_empty_axis(), 
        .prog_full_axis(), 
        .rd_data_count_axis(), 
        .sbiterr_axis(), 
        .injectdbiterr_axis(1'b0), 
        .injectsbiterr_axis(1'b0), 
    
        .s_aclk(aclk),
        .m_aclk(aclk),
        .s_aresetn(aresetn),
        
        // Slave port - Input from processing
        .s_axis_tready(s2mm_tready),
        .s_axis_tdata(s2mm_tdata),
        .s_axis_tvalid(s2mm_tvalid),
        .s_axis_tdest(1'b0), 
        .s_axis_tid(1'b0), 
        .s_axis_tkeep({TKEEP_WIDTH{1'b1}}),  
        .s_axis_tlast(s2mm_tlast),
        .s_axis_tstrb({TKEEP_WIDTH{1'b1}}),  
        .s_axis_tuser(1'b0), 
        
        // Master port - Output to DMA
        .m_axis_tready(m_axis_tready),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tdest(), 
        .m_axis_tid(), 
        .m_axis_tkeep(), 
        .m_axis_tlast(m_axis_tlast), 
        .m_axis_tstrb(), 
        .m_axis_tuser(),  
        
        .wr_data_count_axis()
    );

endmodule