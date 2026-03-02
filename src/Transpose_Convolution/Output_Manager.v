`timescale 1ns / 1ps

/******************************************************************************
 * Module      : Output_Manager_Simple
 * 
 * MODIFIKASI (Feb 2026):
 * - Hapus SEND_NOTIFICATION dan WAIT_NOTIF_DONE — tidak ada C0DE per batch
 * - FSM hanya tunggu all_batches_done lalu kirim DA7A satu kali
 * - TLAST hanya muncul sekali di akhir 4096 words
 * - FIX LATCH: weight_read_done dan ifmap_read_done di-latch terpisah
 *   agar pulse 1-clock tidak terlewat jika keduanya tidak bersamaan
 ******************************************************************************/

module Output_Manager_Simple #(
    parameter DW = 16
)(
    input  wire       clk,
    input  wire       rst_n,

    input  wire       batch_complete,
    input  wire [2:0] current_batch_id,
    input  wire       all_batches_done,
    input  wire [1:0] completed_layer_id,

    output reg [15:0] header_word_0,
    output reg [15:0] header_word_1,
    output reg [15:0] header_word_2,
    output reg [15:0] header_word_3,
    output reg [15:0] header_word_4,
    output reg [15:0] header_word_5,

    output reg        send_header,
    output reg        trigger_read,
    output reg [2:0]  rd_bram_start,
    output reg [2:0]  rd_bram_end,
    output reg [15:0] rd_addr_count,
    output reg        notification_mode,

    input  wire       weight_read_done,
    input  wire       ifmap_read_done,

    output reg        transmission_active
);

    localparam IDLE           = 2'd0;
    localparam SEND_FULL_DATA = 2'd1;
    localparam WAIT_DATA_DONE = 2'd2;

    reg [1:0] state, next_state;
    reg [1:0] latched_layer_id;

    // Edge detect all_batches_done
    reg all_batches_done_prev;
    wire all_batches_done_edge = all_batches_done && !all_batches_done_prev;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) all_batches_done_prev <= 1'b0;
        else        all_batches_done_prev <= all_batches_done;
    end

    // Latch pending output request
    reg pending_full_data;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pending_full_data <= 1'b0;
            latched_layer_id  <= 2'd0;
        end else begin
            if (all_batches_done_edge) begin
                pending_full_data <= 1'b1;
                latched_layer_id  <= completed_layer_id;
            end else if (state == SEND_FULL_DATA) begin
                pending_full_data <= 1'b0;
            end
        end
    end

    // =========================================================================
    // LATCH weight_read_done dan ifmap_read_done secara TERPISAH
    // Karena keduanya pulse 1 clock dan bisa tidak bersamaan
    // Di-clear bersama saat FSM balik ke IDLE
    // =========================================================================
    reg weight_done_latched;
    reg ifmap_done_latched;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            weight_done_latched <= 1'b0;
            ifmap_done_latched  <= 1'b0;
        end else begin
            // Set saat pulse datang (hanya valid saat di WAIT_DATA_DONE)
            if (state == WAIT_DATA_DONE) begin
                if (weight_read_done) weight_done_latched <= 1'b1;
                if (ifmap_read_done)  ifmap_done_latched  <= 1'b1;
            end
            // Clear saat balik ke IDLE
            if (next_state == IDLE && state == WAIT_DATA_DONE) begin
                weight_done_latched <= 1'b0;
                ifmap_done_latched  <= 1'b0;
            end
        end
    end

    // FSM state register
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= IDLE;
        else        state <= next_state;
    end

    // FSM next state
    always @(*) begin
        next_state = state;
        case (state)
            IDLE: begin
                if (pending_full_data)
                    next_state = SEND_FULL_DATA;
            end
            SEND_FULL_DATA: begin
                next_state = WAIT_DATA_DONE;
            end
            WAIT_DATA_DONE: begin
                // Tunggu KEDUA latch set — aman meski pulse tidak bersamaan
                if ((weight_done_latched || weight_read_done) &&
                    (ifmap_done_latched  || ifmap_read_done))
                    next_state = IDLE;
            end
            default: next_state = IDLE;
        endcase
    end

    // Output logic
    always @(posedge clk) begin
        if (!rst_n) begin
            header_word_0       <= 16'd0; header_word_1 <= 16'd0;
            header_word_2       <= 16'd0; header_word_3 <= 16'd0;
            header_word_4       <= 16'd0; header_word_5 <= 16'd0;
            send_header         <= 1'b0;
            trigger_read        <= 1'b0;
            rd_bram_start       <= 3'd0;
            rd_bram_end         <= 3'd0;
            rd_addr_count       <= 16'd0;
            notification_mode   <= 1'b0;
            transmission_active <= 1'b0;
        end else begin
            send_header  <= 1'b0;
            trigger_read <= 1'b0;

            case (state)
                IDLE: begin
                    transmission_active <= 1'b0;
                    notification_mode   <= 1'b0;
                end

                SEND_FULL_DATA: begin
                    transmission_active <= 1'b1;
                    notification_mode   <= 1'b0;
                    header_word_0 <= 16'hDA7A;
                    header_word_1 <= 16'h0002;
                    header_word_2 <= {14'd0, latched_layer_id};
                    header_word_3 <= 16'd0;
                    header_word_4 <= 16'd0;
                    header_word_5 <= 16'd4096;
                    rd_bram_start <= 3'd0;
                    rd_bram_end   <= 3'd7;
                    rd_addr_count <= 16'd512;
                    send_header   <= 1'b1;
                    trigger_read  <= 1'b1;
                end

                WAIT_DATA_DONE: begin
                    transmission_active <= 1'b1;
                    notification_mode   <= 1'b0;
                end

                default: begin
                    transmission_active <= 1'b0;
                    notification_mode   <= 1'b0;
                end
            endcase
        end
    end

endmodule