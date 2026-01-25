/******************************************************************************
 * Module: MM2IM_Top
 * 
 * Description:
 *   Top-level wrapper for MM2IM (Memory Mapped to Image Mapping) subsystem.
 *   Integrates mapper, cmap buffer, and omap buffer.
 *   Precomputes and outputs full snapshots for accumulation unit.
 * 
 * Features:
 *   - MM2IM mapper for computing channel and output maps
 *   - CMap and OMap buffers (internal, for legacy compatibility)
 *   - Full snapshot outputs for direct accumulation unit connection
 *   - One-time computation per tile
 * 
 * Parameters:
 *   NUM_PE - Number of PE columns (default: 16)
 * 
 * Author: Dharma Anargya Jowandy
 * Date: January 2026
 ******************************************************************************/


module MM2IM_Top #(
    parameter NUM_PE = 16  // Number of PE columns
)(
    input  wire              clk,
    input  wire              rst_n,
    input  wire              start,

    // Control inputs
    input  wire [8:0]        row_id,
    input  wire [5:0]        tile_id,
    input  wire [1:0]        layer_id,

    // From Transpose FSM
    input  wire [4:0]        done_PE,     // 0..16 (counter)

    // ========================================================
    // OUTPUTS - FULL SNAPSHOT (for Accumulation Unit)
    // ========================================================
    output wire [NUM_PE-1:0]      cmap_snapshot,    // Full 16-bit CMap snapshot
    output wire [NUM_PE*14-1:0]   omap_snapshot,    // Full 16×14-bit OMap snapshot (flattened)
    output wire                   done              // Mapper done (snapshot ready)
);

    // ---------------------------------------------------------
    // Snapshot wires from MM2IM (FLAT ONLY)
    // ---------------------------------------------------------
    wire [NUM_PE-1:0]      cmap_snap_internal;
    wire [NUM_PE*14-1:0]   omap_flat_internal;
    wire                   mapper_done;

    // ---------------------------------------------------------
    // MM2IM Mapper (precompute snapshot ONCE per tile)
    // ---------------------------------------------------------
    mm2im_mapper_final #(
        .NUM_PE(NUM_PE)
    ) u_mm2im_mapper (
        .clk       (clk),
        .rst_n     (rst_n),
        .start     (start),
        .row_id    (row_id),
        .tile_id   (tile_id),
        .layer_id  (layer_id),
        .cmap      (cmap_snap_internal),
        .omap_flat (omap_flat_internal),
        .done      (mapper_done)
    );

    // Expose mapper_done
    assign done = mapper_done;
    
    // ========================================================
    // EXPOSE FULL SNAPSHOT (for Accumulation Unit)
    // ========================================================
    assign cmap_snapshot = cmap_snap_internal;
    assign omap_snapshot = omap_flat_internal;

    // ---------------------------------------------------------
    // CMap Buffer (internal - not exposed to port)
    // ---------------------------------------------------------
    wire cmap_out_unused;  // Not connected to any output port
    
    cmap_buffer #(
        .WIDTH(NUM_PE)
    ) u_cmap_buffer (
        .clk      (clk),
        .rst_n    (rst_n),
        .cmap_in  (cmap_snap_internal),
        .load     (mapper_done),   // Snapshot load (1x per tile)
        .done     (done_PE),        // 0..16
        .cmap_out (cmap_out_unused) // Internal only
    );

    // ---------------------------------------------------------
    // OMap Buffer (internal - not exposed to port)
    // ---------------------------------------------------------
    wire [3:0] bram_sel_unused;   // Not connected to any output port
    wire [9:0] bram_addr_unused;  // Not connected to any output port
    
    omap_buffer #(
        .NUM_PE(NUM_PE)
    ) u_omap_buffer (
        .clk          (clk),
        .rst_n        (rst_n),
        .omap_in_flat (omap_flat_internal),
        .load         (mapper_done),
        .done         (done_PE),
        .bram_sel     (bram_sel_unused),
        .bram_addr    (bram_addr_unused)
    );

endmodule