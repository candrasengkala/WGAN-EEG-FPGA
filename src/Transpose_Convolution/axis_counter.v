`timescale 1ns / 1ps

/******************************************************************************
 * Module      : axis_counter
 * Author      : Dharma Anargya Jowandy
 * Date        : January 2026
 *
 * Description :
 * Generic address counter intended for BRAM addressing applications.
 * The counter supports programmable start addresses and configurable
 * count limits, enabling sequential burst-based memory access.
 *
 * Functionality :
 * - Loads 'start_addr' into the counter when 'counter_start' is asserted.
 * - Increments the address counter and an internal progress tracker when
 *   'counter_enable' is asserted.
 * - Asserts 'counter_done' when the number of increments reaches the
 *   programmed 'count_limit'.
 *
 * Parameters :
 * - None (signal widths define addressing and count range)
 *
 * Inputs :
 * - counter_enable : Enables counter increment
 * - counter_start  : Loads the initial start address
 * - start_addr     : Initial address value (e.g., 256)
 * - count_limit    : Total number of addresses to generate (e.g., 128)
 *
 * Outputs :
 * - counter        : Current BRAM address pointer
 * - counter_done   : Completion flag indicating count limit reached
 *
 ******************************************************************************/


module axis_counter (
    // System Signals
    input  wire        aclk,
    input  wire        aresetn,
    
    // Control Signals
    input  wire        counter_enable, // Enable counter increment
    input  wire        counter_start,  // Load start_addr and reset internal count
    input  wire [15:0] start_addr,     // Starting address
    input  wire [15:0] count_limit,    // Number of cycles to count
    
    // Outputs
    output reg  [15:0] counter,        // Current address output
    output wire        counter_done    // High when limit reached
);

    // Internal register to track the number of increments performed
    reg [15:0] count_reg;

    // ========================================================================
    // Counter Logic
    // ========================================================================
    // Operation:
    // 1. Configure 'start_addr' and 'count_limit' from external FSM.
    // 2. Pulse 'counter_start' to load 'start_addr' into 'counter'.
    // 3. Assert 'counter_enable' to increment.
    // 4. 'counter_done' goes HIGH when 'count_reg' >= 'count_limit'.
    
    always @(posedge aclk) begin
        if (!aresetn) begin
            counter   <= 16'b0;
            count_reg <= 16'b0;
        end
        else if (counter_start) begin
            // Load start address and reset tracking register
            counter   <= start_addr;
            count_reg <= 16'b0;
        end
        else if (counter_enable) begin
            // Increment address and tracking register
            counter   <= counter + 1;
            count_reg <= count_reg + 1;
        end
    end
    
    // Done signal generation
    // Returns HIGH when the tracked count meets or exceeds the limit
    assign counter_done = (count_reg >= count_limit) && (count_limit != 0);

endmodule