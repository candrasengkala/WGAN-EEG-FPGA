`ifndef SIMPLE_BRAM_V
`define SIMPLE_BRAM_V

module simple_dual_two_clocks_512x16 #(
    parameter DEPTH      = 1024,  // Memory depth
    parameter DATA_WIDTH = 16,   // Data width (16-bit fixed-point)
    parameter ADDR_WIDTH = 10     // Address width (2^10 = 1024)
)(
    input  wire                      clka,   // Write clock
    input  wire                      clkb,   // Read clock
    input  wire                      ena,    // Enable write port
    input  wire                      enb,    // Enable read port
    input  wire                      wea,    // Write enable
    input  wire [ADDR_WIDTH-1:0]     addra,  // Write address (0..511)
    input  wire [ADDR_WIDTH-1:0]     addrb,  // Read address (0..511)
    input  wire signed [DATA_WIDTH-1:0] dia, // Write data
    output reg  signed [DATA_WIDTH-1:0] dob  // Read data (registered)
);

    // Memory array
    reg signed [DATA_WIDTH-1:0] ram [0:DEPTH-1];

    // -----------------------------
    // WRITE PORT (Port A)
    // -----------------------------
    always @(posedge clka) begin
        if (ena && wea) begin
            ram[addra] <= dia; 
        end
    end

    // -----------------------------
    // READ PORT (Port B)
    // -----------------------------
    always @(posedge clkb) begin
        if (enb) begin
            dob <= ram[addrb];
        end
    end

endmodule

`endif // SIMPLE_BRAM_V