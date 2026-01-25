/******************************************************************************
 * Module: Counter_Weight_BRAM
 * 
 * Description:
 *   Wavefront address controller for weight BRAM array.
 *   Generates diagonal wavefront pattern for systolic array weight loading.
 * 
 * Features:
 *   - Wavefront enable pattern (0 → 16 PEs)
 *   - Configurable address scan range
 *   - Pipeline drain before done assertion
 *   - Read enable output for power optimization
 * 
 * Parameters:
 *   NUM_BRAMS  - Number of BRAMs (default: 16)
 *   ADDR_WIDTH - Address width (default: 9)
 * 
 * Author: Dharma Anargya Jowandy
 * Date: January 2026
 ******************************************************************************/

module Counter_Weight_BRAM #(
    parameter NUM_BRAMS  = 16,  // Number of weight BRAMs
    parameter ADDR_WIDTH = 9    // Address width (9 bits = 512 entries)
)(
    input  wire                              clk,
    input  wire                              rst_n,
    input  wire                              start,

    // Configurable address range
    input  wire [ADDR_WIDTH-1:0]             addr_start,
    input  wire [ADDR_WIDTH-1:0]             addr_end,

    // Outputs to BRAM
    output reg  [NUM_BRAMS-1:0]              w_re,            // Read enable
    output reg  [NUM_BRAMS*ADDR_WIDTH-1:0]   w_addr_rd_flat,  // Read addresses
    output reg                               done
);

    // ========================================================
    // Internal registers
    // ========================================================
    reg [ADDR_WIDTH-1:0] addr_pipe [0:NUM_BRAMS-1];  // Address delay chain
    reg [ADDR_WIDTH-1:0] current_addr;

    reg [4:0] wf_cnt;      // Wavefront counter (0..16)
    reg [4:0] drain_cnt;   // Drain counter (0..15)

    reg running;
    reg scan_done;

    integer i;

    // ========================================================
    // MAIN FSM
    // ========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset
            running      <= 1'b0;
            scan_done    <= 1'b0;
            done         <= 1'b0;
            wf_cnt       <= 5'd0;
            drain_cnt    <= 5'd0;
            current_addr <= {ADDR_WIDTH{1'b0}};
            w_re         <= {NUM_BRAMS{1'b0}};

            for (i = 0; i < NUM_BRAMS; i = i + 1)
                addr_pipe[i] <= {ADDR_WIDTH{1'b0}};
        end

        // ----------------------------------------------------
        // START
        // ----------------------------------------------------
        else if (start && !running) begin
            running      <= 1'b1;
            scan_done    <= 1'b0;
            done         <= 1'b0;

            current_addr <= addr_start;
            wf_cnt       <= 5'd0;
            drain_cnt    <= 5'd0;
            w_re         <= {NUM_BRAMS{1'b0}};

            for (i = 0; i < NUM_BRAMS; i = i + 1)
                addr_pipe[i] <= {ADDR_WIDTH{1'b0}};
        end

        // ----------------------------------------------------
        // RUNNING
        // ----------------------------------------------------
        else if (running) begin

            // ==============================
            // PHASE 1: ADDRESS SCAN
            // ==============================
            if (!scan_done) begin

                // Wavefront ramp-up
                if (wf_cnt < 5'd16)
                    wf_cnt <= wf_cnt + 1'b1;

                // Shift address pipeline
                addr_pipe[0] <= current_addr;
                for (i = 1; i < NUM_BRAMS; i = i + 1)
                    addr_pipe[i] <= addr_pipe[i-1];

                // Read enable mask (wavefront pattern)
                for (i = 0; i < NUM_BRAMS; i = i + 1)
                    w_re[i] <= (i < wf_cnt);

                // Address increment or finish scan
                if (current_addr < addr_end)
                    current_addr <= current_addr + 1'b1;
                else begin
                    scan_done <= 1'b1;
                    drain_cnt <= 5'd0;
                end
            end

            // ==============================
            // PHASE 2: DRAIN PIPELINE
            // ==============================
            else begin
                if (drain_cnt < 5'd15) begin
                    drain_cnt <= drain_cnt + 1'b1;

                    addr_pipe[0] <= addr_end;
                    for (i = 1; i < NUM_BRAMS; i = i + 1)
                        addr_pipe[i] <= addr_pipe[i-1];

                    w_re <= {NUM_BRAMS{1'b1}};  // All BRAM read enabled
                end
                else begin
                    // DONE
                    running <= 1'b0;
                    done    <= 1'b1;
                    w_re    <= {NUM_BRAMS{1'b0}};  // Disable all BRAM reads
                end
            end
        end

        // ----------------------------------------------------
        // IDLE
        // ----------------------------------------------------
        else begin
            done <= 1'b0;
            w_re <= {NUM_BRAMS{1'b0}};
        end
    end

    // ========================================================
    // FLATTEN ADDRESS BUS
    // ========================================================
    always @(*) begin
        for (i = 0; i < NUM_BRAMS; i = i + 1)
            w_addr_rd_flat[i*ADDR_WIDTH +: ADDR_WIDTH] = addr_pipe[i];
    end

endmodule