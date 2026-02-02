`timescale 1ns / 1ps

/******************************************************************************
 * Module      : Counter_Weight_BRAM
 * Author      : Dharma Anargya Jowandy
 * Date        : January 2026
 * Modified    : January 31, 2026 - FINAL ROBUST VERSION
 *
 * Description :
 * Wavefront-based address controller for the weight BRAM array.
 * * UPDATE: Implemented "Jumpstart" logic with Correct Wavefront Init.
 * - Eliminates 1-cycle dead time at startup.
 * - Initializes wf_cnt to 1 to ensure BRAM 1 triggers immediately in the next cycle.
 * - Guarantees clean state reset on every 'start' pulse (Multi-batch safe).
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
    reg [ADDR_WIDTH-1:0] addr_pipe [0:NUM_BRAMS-1]; // Address delay chain
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
        // START (JUMPSTART LOGIC - MULTI-BATCH SAFE)
        // ----------------------------------------------------
        // Logic ini mereset total seluruh register setiap kali 'start' baru masuk.
        // Tidak ada state 'sampah' yang terbawa dari batch sebelumnya.
        else if (start && !running) begin
            running      <= 1'b1;
            scan_done    <= 1'b0;
            done         <= 1'b0;

            // 1. PRE-LOAD ADDRESS (JUMPSTART)
            // Siapkan alamat berikutnya (Addr 1) untuk cycle depan
            current_addr <= addr_start + 1'b1;

            // Isi Pipeline [0] dengan Alamat Awal (Addr 0) SEKARANG
            addr_pipe[0] <= addr_start;

            // Bersihkan sisa pipeline (Safety Reset)
            for (i = 1; i < NUM_BRAMS; i = i + 1)
                addr_pipe[i] <= {ADDR_WIDTH{1'b0}};

            // 2. IMMEDIATE READ ENABLE
            // Nyalakan BRAM 0 di clock ini juga (T0)
            w_re[0] <= 1'b1;
            for (i = 1; i < NUM_BRAMS; i = i + 1)
                w_re[i] <= 1'b0;

            // 3. WAVEFRONT INIT (CRITICAL FIX)
            // Init ke 1 (bukan 0). Karena langkah ke-0 sudah dieksekusi di sini.
            // Di cycle depan (T1), wf_cnt=1 akan menyalakan BRAM 1.
            wf_cnt       <= 5'd1;
            drain_cnt    <= 5'd0;
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
                // Logic ini memastikan BRAM 1, 2, dst menyala berurutan
                for (i = 0; i < NUM_BRAMS; i = i + 1)
                    w_re[i] <= (i <= wf_cnt);

                // Address increment
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

                    // Flush sisa data di pipeline
                    addr_pipe[0] <= addr_end;
                    for (i = 1; i < NUM_BRAMS; i = i + 1)
                        addr_pipe[i] <= addr_pipe[i-1];

                    w_re <= {NUM_BRAMS{1'b1}};  // Keep reading until drained
                end
                else begin
                    // DONE (Clean Exit)
                    running <= 1'b0; // Siap menerima 'start' berikutnya
                    done    <= 1'b1;
                    w_re    <= {NUM_BRAMS{1'b0}};
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
