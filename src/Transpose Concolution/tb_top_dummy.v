`timescale 1ns / 1ps
`include "top_level_dummy_new.v"

module tb_top_dummy;

    reg aclk;
    reg aresetn;
    reg [63:0] s_axis_tdata;
    reg s_axis_tvalid;
    reg s_axis_tlast;
    wire s_axis_tready;
    wire [63:0] m_axis_tdata;
    wire m_axis_tvalid;
    wire m_axis_tlast;
    reg m_axis_tready;
    reg [7:0] instruction_code;
    reg [4:0] wr_bram_start;
    reg [4:0] wr_bram_end;
    reg [15:0] wr_addr_start;
    reg [15:0] wr_addr_count;
    reg [3:0] rd_bram_start;
    reg [3:0] rd_bram_end;
    reg [15:0] rd_addr_start;
    reg [15:0] rd_addr_count;
    
    integer i;
    reg [15:0] data_counter;
    reg [15:0] d0, d1, d2, d3;
    integer print_count;
    
    initial begin
        aclk = 0;
        forever #5 aclk = ~aclk;
    end
    
    top_level_dummy dut (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tlast(s_axis_tlast),
        .s_axis_tready(s_axis_tready),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tlast(m_axis_tlast),
        .m_axis_tready(m_axis_tready),
        .instruction_code(instruction_code),
        .wr_bram_start(wr_bram_start),
        .wr_bram_end(wr_bram_end),
        .wr_addr_start(wr_addr_start),
        .wr_addr_count(wr_addr_count),
        .rd_bram_start(rd_bram_start),
        .rd_bram_end(rd_bram_end),
        .rd_addr_start(rd_addr_start),
        .rd_addr_count(rd_addr_count)
    );
    
    initial begin
        $dumpfile("tb_top_dummy.vcd");
        $dumpvars(0, tb_top_dummy);
        
        aresetn = 0;
        s_axis_tdata = 64'd0;
        s_axis_tvalid = 0;
        s_axis_tlast = 0;
        m_axis_tready = 1;
        instruction_code = 8'h00;
        wr_bram_start = 5'd0;
        wr_bram_end = 5'd3;
        wr_addr_start = 16'd0;
        wr_addr_count = 16'd512;
        rd_bram_start = 4'd0;
        rd_bram_end = 4'd3;
        rd_addr_start = 16'd0;
        rd_addr_count = 16'd512;
        data_counter = 16'd1;
        print_count = 0;
        
        #20 aresetn = 1;
        #20;
        
        instruction_code = 8'h01;
        #10;
        
        for (i = 0; i < 512; i = i + 1) begin
            @(posedge aclk);
            d0 = data_counter;
            d1 = data_counter + 16'd1;
            d2 = data_counter + 16'd2;
            d3 = data_counter + 16'd3;
            s_axis_tvalid = 1;
            s_axis_tdata = {d3, d2, d1, d0};
            data_counter = data_counter + 16'd4;
            s_axis_tlast = (i == 511) ? 1 : 0;
            while (!s_axis_tready) @(posedge aclk);
        end
        
        @(posedge aclk);
        s_axis_tvalid = 0;
        s_axis_tlast = 0;
        
        #1000;
        instruction_code = 8'h00;
        #50;
        
        instruction_code = 8'h02;
        #5000;
        
        instruction_code = 8'h00;
        #100;
        $finish;
    end
    
    // Monitor input yang dikirim testbench
    always @(posedge aclk) begin
        if (s_axis_tvalid && s_axis_tready && print_count < 13) begin
            $display("[%0t] TB SEND: %h (d3=%0d, d2=%0d, d1=%0d, d0=%0d)", 
                     $time, s_axis_tdata, s_axis_tdata[63:48], s_axis_tdata[47:32], 
                     s_axis_tdata[31:16], s_axis_tdata[15:0]);
        end
    end
    
    // Monitor output FIFO ke parser
    always @(posedge aclk) begin
        if (dut.axis_top_inst.mm2s_valid && dut.axis_top_inst.mm2s_ready && print_count < 13) begin
            $display("[%0t] MM2S OUT: %h", $time, dut.axis_top_inst.mm2s_data);
        end
    end
    
    // Monitor output parser - 50 PERTAMA
    always @(posedge aclk) begin
        if (dut.axis_top_inst.parser_data_valid && print_count < 50) begin
            $display("[%0t] PARSER OUT [%0d]: %0d", $time, print_count, dut.axis_top_inst.parser_data_out);
            print_count = print_count + 1;
        end
    end

endmodule
