// Block RAM with Resettable Data Output
// Single-port synchronous RAM with registered output and reset capability
// File: rams_sp_rf_rst.v

module rams_sp_rf_rst (clk, en, we, rst, addr, di, dout);

// ============================================
// PORT DECLARATIONS
// ============================================

input clk;              // Clock signal - synchronizes all operations
input en;               // Enable signal - master enable for the RAM block
                        // When low (0), RAM is inactive (no read/write)
input we;               // Write Enable - when high (1), allows writing to RAM
                        // Only effective when 'en' is also high
input rst;              // Reset signal - clears the output register to 0
                        // Does NOT clear the RAM contents, only the output
input [9:0] addr;       // Address bus - 10 bits wide (addresses 0-1023)
                        // Used for BOTH reading and writing (single port)
input [15:0] di;        // Data Input - 16-bit data to be written into RAM

output [15:0] dout;     // Data Output - 16-bit registered output
                        // Synchronous read (clocked)

// ============================================
// MEMORY AND OUTPUT REGISTER DECLARATIONS
// ============================================

reg [15:0] ram [1023:0]; // RAM array: 1024 locations × 16 bits each
                         // [15:0] = each location stores 16 bits
                         // [1023:0] = 1024 total memory locations (2^10 = 1024)
                         // Total memory: 1024 × 16 = 16,384 bits = 2 KB

reg [15:0] dout;         // Output register - holds the read data
                         // Being a 'reg' makes this a registered output

// ============================================
// SYNCHRONOUS READ/WRITE OPERATION
// ============================================

always @(posedge clk)    // Triggered on positive edge of clock
begin
    if (en)              // Check if RAM is enabled
    begin
        
        // WRITE OPERATION (highest priority after enable)
        if (we)          // Check if write enable is active
            ram[addr] <= di;  // Write data 'di' to RAM at address 'addr'
                              // Non-blocking assignment for synchronous logic
        
        // READ OPERATION WITH RESET
        if (rst)         // Check if reset is active
            dout <= 0;   // Clear output register to zero
                         // RAM contents are NOT affected
        else
            dout <= ram[addr];  // Read data from RAM at address 'addr'
                                // Output is registered (1 clock cycle delay)
                                // This happens regardless of 'we' state
    end
    // If 'en' is low, nothing happens - RAM holds its state
end

endmodule