/******************************************************************************
 * Module: cmap_buffer
 * 
 * Description:
 *   Buffer for channel map (cmap) from MM2IM mapper.
 *   Stores 16-bit snapshot and outputs single bit indexed by done counter.
 * 
 * Features:
 *   - Single-cycle snapshot capture on load signal
 *   - Combinational output (no delay)
 *   - Indexed access by done counter (0..16)
 * 
 * Parameters:
 *   WIDTH - Number of channels (default: 16)
 * 
 * Author: Dharma Anargya Jowandy
 * Date: January 2026
 ******************************************************************************/

module cmap_buffer #(
    parameter WIDTH = 16  // Number of channels (PE columns)
)(
    input  wire              clk,
    input  wire              rst_n,

    // Snapshot from MM2IM
    input  wire [WIDTH-1:0]  cmap_in,
    input  wire              load,     // Load snapshot (1x per tile)

    // Selector from Transpose FSM
    input  wire [4:0]        done,     // 0..16

    // Output to Accumulation / Write-back
    output reg               cmap_out
);

    // ---------------------------------------------------------
    // Internal storage
    // ---------------------------------------------------------
    reg [WIDTH-1:0] cmap_reg;

    // ---------------------------------------------------------
    // Load snapshot
    // ---------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            cmap_reg <= {WIDTH{1'b0}};
        else if (load)
            cmap_reg <= cmap_in;
    end

    // ---------------------------------------------------------
    // Output 1-bit indexed by done (combinational, no delay)
    // ---------------------------------------------------------
    always @(*) begin
        if (done >= 5'd1 && done <= 5'd16) begin
            cmap_out = cmap_reg[done - 5'd1];
        end else begin
            cmap_out = 1'b0;
        end
    end

endmodule