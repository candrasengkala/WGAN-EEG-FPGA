/******************************************************************************
 * Module: accumulation_unit
 * 
 * Description:
 *   6-stage pipelined accumulation unit for transposed convolution output.
 *   Reads partial sums from systolic array, accumulates with BRAM data,
 *   and writes results back to output BRAMs.
 * 
 * Parameters:
 *   DW        - Data width in bits (default: 16)
 *   NUM_BRAMS - Number of output BRAMs (default: 16)
 * 
 * Author: Dharma Anargya Jowandy
 * Date: January 2026
 ******************************************************************************/

module accumulation_unit #(
    parameter DW        = 16,   // Data width (16-bit fixed-point)
    parameter NUM_BRAMS = 16    // Number of output BRAMs
)(
    input  wire                              clk,
    input  wire                              rst_n,

    input  wire signed [DW-1:0]              partial_in,
    input  wire        [3:0]                 col_id,
    input  wire                              partial_valid,

    input  wire        [NUM_BRAMS-1:0]       cmap,
    input  wire        [NUM_BRAMS*14-1:0]    omap_flat,

    output reg         [NUM_BRAMS*9-1:0]     bram_addr_rd_flat,
    input  wire signed [NUM_BRAMS*DW-1:0]    bram_dout_flat,

    output reg         [NUM_BRAMS-1:0]       bram_we,
    output reg         [NUM_BRAMS*9-1:0]     bram_addr_wr_flat,
    output reg  signed [NUM_BRAMS*DW-1:0]    bram_din_flat
);

    // Internal arrays
    reg        [13:0]       omap     [0:NUM_BRAMS-1];
    reg signed [DW-1:0]     bram_dout[0:NUM_BRAMS-1];
    reg        [8:0]        bram_addr_rd[0:NUM_BRAMS-1];

    integer i;

    // =========================================================
    // UNFLATTEN INPUTS
    // =========================================================
    always @(*) begin
        for (i = 0; i < NUM_BRAMS; i = i + 1) begin
            omap[i]      = omap_flat[i*14 +: 14];
            bram_dout[i] = bram_dout_flat[i*DW +: DW];
        end
    end

    // =========================================================
    // PIPELINE REGISTERS (6-STAGE)
    // =========================================================
    reg signed [DW-1:0] partial_s1, partial_s2, partial_s3, partial_s4;
    reg                 valid_s1, valid_s2, valid_s3, valid_s4, valid_s5;
    reg        [3:0]    bram_sel_s1, bram_sel_s2, bram_sel_s3, bram_sel_s4, bram_sel_s5;
    reg        [8:0]    addr_s1, addr_s2, addr_s3, addr_s4, addr_s5;
    reg signed [DW-1:0] bram_data_s4;
    reg signed [DW-1:0] accumulated_s5;

    // ================= STAGE 1 =================
    // Decode omap to get BRAM selector and address
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            partial_s1  <= 0;
            valid_s1    <= 0;
            bram_sel_s1 <= 0;
            addr_s1     <= 0;
        end else begin
            partial_s1 <= partial_in;
            valid_s1   <= partial_valid && cmap[col_id];

            if (partial_valid && cmap[col_id]) begin
                bram_sel_s1 <= omap[col_id][13:10];
                addr_s1     <= omap[col_id][8:0];
            end else begin
                bram_sel_s1 <= 0;
                addr_s1     <= 0;
            end
        end
    end

    // ================= STAGE 2 =================
    // Set BRAM read address
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            partial_s2  <= 0;
            bram_sel_s2 <= 0;
            addr_s2     <= 0;
            valid_s2    <= 0;
            for (i = 0; i < NUM_BRAMS; i = i + 1)
                bram_addr_rd[i] <= 0;
        end else begin
            partial_s2  <= partial_s1;
            bram_sel_s2 <= bram_sel_s1;
            addr_s2     <= addr_s1;
            valid_s2    <= valid_s1;

            if (valid_s1)
                bram_addr_rd[bram_sel_s1] <= addr_s1;
        end
    end

    // ================= STAGE 3 =================
    // Wait for BRAM read (1 cycle latency)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            partial_s3  <= 0;
            bram_sel_s3 <= 0;
            addr_s3     <= 0;
            valid_s3    <= 0;
        end else begin
            partial_s3  <= partial_s2;
            bram_sel_s3 <= bram_sel_s2;
            addr_s3     <= addr_s2;
            valid_s3    <= valid_s2;
        end
    end

    // ================= STAGE 4 =================
    // Sample BRAM data (handle uninitialized X states)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            partial_s4    <= 0;
            bram_sel_s4   <= 0;
            addr_s4       <= 0;
            valid_s4      <= 0;
            bram_data_s4  <= 0;
        end else begin
            partial_s4   <= partial_s3;
            bram_sel_s4  <= bram_sel_s3;
            addr_s4      <= addr_s3;
            valid_s4     <= valid_s3;
            
            // Handle uninitialized BRAM
            if (valid_s3) begin
                if (^bram_dout[bram_sel_s3] === 1'bx)
                    bram_data_s4 <= {DW{1'b0}};
                else
                    bram_data_s4 <= bram_dout[bram_sel_s3];
            end else begin
                bram_data_s4 <= 0;
            end
        end
    end

    // ================= STAGE 5 =================
    // Accumulate: BRAM data + partial sum
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            accumulated_s5 <= 0;
            bram_sel_s5    <= 0;
            addr_s5        <= 0;
            valid_s5       <= 0;
        end else begin
            bram_sel_s5 <= bram_sel_s4;
            addr_s5     <= addr_s4;
            valid_s5    <= valid_s4;

            if (valid_s4)
                accumulated_s5 <= bram_data_s4 + partial_s4;
            else
                accumulated_s5 <= 0;
        end
    end

    // ================= STAGE 6 =================
    // Write back to BRAM
    // CRITICAL: Clear ALL outputs first to prevent overwrite
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bram_we <= {NUM_BRAMS{1'b0}};
            bram_addr_wr_flat <= {(NUM_BRAMS*9){1'b0}};
            bram_din_flat <= {(NUM_BRAMS*DW){1'b0}};
        end else begin
            // CRITICAL: Clear ALL outputs first
            bram_we <= {NUM_BRAMS{1'b0}};
            bram_addr_wr_flat <= {(NUM_BRAMS*9){1'b0}};
            bram_din_flat <= {(NUM_BRAMS*DW){1'b0}};
            
            // Then set only the active BRAM
            if (valid_s5) begin
                bram_we[bram_sel_s5] <= 1'b1;
                bram_addr_wr_flat[bram_sel_s5*9 +: 9]  <= addr_s5;
                bram_din_flat[bram_sel_s5*DW +: DW]    <= accumulated_s5;
            end
        end
    end

    // =========================================================
    // FLATTEN READ ADDRESSES
    // =========================================================
    always @(*) begin
        for (i = 0; i < NUM_BRAMS; i = i + 1) begin
            bram_addr_rd_flat[i*9 +: 9] = bram_addr_rd[i];
        end
    end

endmodule