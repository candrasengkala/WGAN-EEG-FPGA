`timescale 1ns / 1ps

/**
 * AXI Stream Header Parser (FIXED & CLEAN)
 */

module axi_header_parser #(
    parameter DATA_WIDTH = 16
)(
    input wire aclk,
    input wire aresetn,
    
    // Input from DMA
    input wire [DATA_WIDTH-1:0] s_axis_tdata,
    input wire s_axis_tvalid,
    output reg s_axis_tready,
    input wire s_axis_tlast,
    
    // Output to BRAM controller
    output reg [DATA_WIDTH-1:0] m_axis_tdata,
    output reg m_axis_tvalid,
    input wire m_axis_tready,
    output reg m_axis_tlast,
    
    // Extracted Control Parameters
    output reg [7:0]  instruction_code,
    output reg [4:0]  bram_start,
    output reg [4:0]  bram_end,
    output reg [15:0] addr_start,
    output reg [15:0] addr_count,
    output reg        header_valid,
    
    // Status
    output reg        error_invalid_magic,
    output wire [2:0] parser_state_debug
);

    // State Encoding
    localparam [2:0]
        HEADER_0    = 3'd0,  // Expect 0xC0DE
        HEADER_1    = 3'd1,  // Instruction
        HEADER_2    = 3'd2,  // BRAM start
        HEADER_3    = 3'd3,  // BRAM end
        HEADER_4    = 3'd4,  // Address start
        HEADER_5    = 3'd5,  // Address count
        DATA_PASS   = 3'd6;  // Pass-through data
    
    reg [2:0] current_state, next_state;

    assign parser_state_debug = current_state;

    // State Transition
    always @(posedge aclk) begin
        if (!aresetn)
            current_state <= HEADER_0;
        else
            current_state <= next_state;
    end
    
    // FSM Logic
    always @(*) begin
        next_state = current_state;
        s_axis_tready = 1'b0;
        m_axis_tdata = 16'b0;
        m_axis_tvalid = 1'b0;
        m_axis_tlast = 1'b0;

        case (current_state)
            HEADER_0: begin  // Expect magic number
                s_axis_tready = 1'b1;
                if (s_axis_tvalid) next_state = HEADER_1;
            end
            
            HEADER_1: begin  // Instruction code
                s_axis_tready = 1'b1;
                if (s_axis_tvalid) next_state = HEADER_2;
            end
            
            HEADER_2: begin  // BRAM start
                s_axis_tready = 1'b1;
                if (s_axis_tvalid) next_state = HEADER_3;
            end
            
            HEADER_3: begin  // BRAM end
                s_axis_tready = 1'b1;
                if (s_axis_tvalid) next_state = HEADER_4;
            end
            
            HEADER_4: begin  // Address start
                s_axis_tready = 1'b1;
                if (s_axis_tvalid) next_state = HEADER_5;
            end
            
            HEADER_5: begin  // Address count
                s_axis_tready = 1'b1;
                if (s_axis_tvalid) next_state = DATA_PASS;
            end
            
            DATA_PASS: begin  // Pass-through mode
                s_axis_tready = m_axis_tready;
                m_axis_tdata = s_axis_tdata;
                m_axis_tvalid = s_axis_tvalid;
                m_axis_tlast = s_axis_tlast;
                
                // When TLAST, go back to start
                if (s_axis_tvalid && m_axis_tready && s_axis_tlast)
                    next_state = HEADER_0;
            end
            
            default: next_state = HEADER_0;
        endcase
    end
    
    // Register Capture
    always @(posedge aclk) begin
        if (!aresetn) begin
            instruction_code <= 8'b0;
            bram_start <= 5'b0;
            bram_end <= 5'b0;
            addr_start <= 16'b0;
            addr_count <= 16'b0;
            header_valid <= 1'b0;
            error_invalid_magic <= 1'b0;
        end else begin
            header_valid <= 1'b0; 
            
            case (current_state)
                HEADER_0: begin
                    if (s_axis_tvalid && s_axis_tready) begin
                        if (s_axis_tdata != 16'hC0DE)
                            error_invalid_magic <= 1'b1;
                        else
                            error_invalid_magic <= 1'b0;
                    end
                end
                
                HEADER_1: if (s_axis_tvalid && s_axis_tready) instruction_code <= s_axis_tdata[7:0];
                HEADER_2: if (s_axis_tvalid && s_axis_tready) bram_start <= s_axis_tdata[4:0];
                HEADER_3: if (s_axis_tvalid && s_axis_tready) bram_end <= s_axis_tdata[4:0];
                HEADER_4: if (s_axis_tvalid && s_axis_tready) addr_start <= s_axis_tdata[15:0];
                
                HEADER_5: begin
                    if (s_axis_tvalid && s_axis_tready) begin
                        addr_count <= s_axis_tdata[15:0];
                        header_valid <= 1'b1;  // Pulse valid
                    end
                end
            endcase
        end
    end

endmodule