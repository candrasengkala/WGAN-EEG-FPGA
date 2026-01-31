/******************************************************************************
 * Module      : Counter_Ifmap_BRAM
 * Author      : Dharma Anargya Jowandy
 * Date        : January 2026
 *
 * Description :
 * Address control module for Input Feature Map (Ifmap) BRAMs.
 * This module selects a single BRAM bank and generates a sequential
 * read address stream over a programmable address range.
 *
 * Key Features :
 * - Programmable Address Window
 *   Supports configurable start and end addresses for sequential scanning.
 *
 * - Single-BRAM Selection
 *   Activates exactly one BRAM bank (1-of-N) during an access window.
 *
 * - Read Enable Gating
 *   Generates per-BRAM read-enable signals to reduce unnecessary memory
 *   activity and improve power efficiency.
 *
 * - Combinational Address Output
 *   Exposes flattened BRAM read addresses with no additional pipeline delay,
 *   enabling tight synchronization with external controllers (e.g., weight
 *   address generators).
 *
 * Parameters :
 * - NUM_BRAMS  : Number of Ifmap BRAM banks (default: 16)
 * - ADDR_WIDTH : Address width per BRAM (default: 9, depth = 512)
 *
 ******************************************************************************/


module Counter_Ifmap_BRAM #(
    parameter NUM_BRAMS  = 16,  // Number of ifmap BRAMs
    parameter ADDR_WIDTH = 9    // Address width (9 bits = 512 entries)
)(
    input  wire                              clk,
    input  wire                              rst_n,
    input  wire                              start,

    // Configurable address range
    input  wire [ADDR_WIDTH-1:0]             if_addr_start,
    input  wire [ADDR_WIDTH-1:0]             if_addr_end,
    input  wire [3:0]                        ifmap_sel_in,  // Select which BRAM (0-15)

    // Outputs to BRAM
    output reg  [NUM_BRAMS-1:0]              if_re,            // Read enable
    output wire [NUM_BRAMS*ADDR_WIDTH-1:0]   if_addr_rd_flat,  // Read addresses (combinational)
    output reg  [3:0]                        ifmap_sel_out,    // Pass-through to MUX
    output reg                               if_done
);

    // ========================================================
    // Internal registers
    // ========================================================
    reg [ADDR_WIDTH-1:0] current_addr;
    reg                  running;
    
    // ========================================================
    // Address register array
    // ========================================================
    reg [ADDR_WIDTH-1:0] addr_reg [0:NUM_BRAMS-1];
    
    integer i;

    // ========================================================
    // Sequential logic
    // ========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset
            if_done       <= 1'b0;
            current_addr  <= {ADDR_WIDTH{1'b0}};
            if_re         <= {NUM_BRAMS{1'b0}};
            running       <= 1'b0;
            ifmap_sel_out <= 4'd0;
            
            for (i = 0; i < NUM_BRAMS; i = i + 1)
                addr_reg[i] <= {ADDR_WIDTH{1'b0}};
        end
        else if (start && !running) begin
            // ========================================
            // START: Initialize
            // ========================================
            running       <= 1'b1;
            if_done       <= 1'b0;
            current_addr  <= if_addr_start;
            ifmap_sel_out <= ifmap_sel_in;  // Latch selector
            
            // Enable only selected BRAM
            if_re <= {NUM_BRAMS{1'b0}};
            if_re[ifmap_sel_in] <= 1'b1;
            
            // Initialize address register for selected BRAM
            addr_reg[ifmap_sel_in] <= if_addr_start;
        end
        else if (running) begin
            // ========================================
            // RUNNING: Increment address
            // ========================================
            if (current_addr < if_addr_end) begin
                // Increment current address
                current_addr <= current_addr + 1'b1;
                
                // Update address register for selected BRAM
                addr_reg[ifmap_sel_out] <= current_addr + 1'b1;
            end
            else begin
                // DONE: Reached addr_end
                running <= 1'b0;
                if_done <= 1'b1;
                if_re   <= {NUM_BRAMS{1'b0}};  // Disable all
            end
        end
        else begin
            // IDLE: Clear done flag
            if_done <= 1'b0;
        end
    end

    // ========================================================
    // COMBINATIONAL ADDRESS OUTPUT
    // ========================================================
    genvar j;
    generate
        for (j = 0; j < NUM_BRAMS; j = j + 1) begin : ADDR_FLATTEN
            assign if_addr_rd_flat[j*ADDR_WIDTH +: ADDR_WIDTH] = addr_reg[j];
        end
    endgenerate

endmodule