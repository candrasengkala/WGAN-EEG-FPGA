`timescale 1ns / 1ps

/******************************************************************************
 * Module      : Output_Manager_Simple
 * Author      : Dharma Anargya Jowandy
 * Date        : January 2026
 *
 * FIX (Feb 2026) - MINIMAL:
 * Hanya satu perubahan dari versi original yang sudah proven di simulasi:
 *
 *   1. send_header TETAP SATU SINYAL — identik dengan original.
 *      Timing tidak berubah, testbench tetap lulus.
 *
 *   2. WAIT_DATA_DONE menunggu KEDUA weight_read_done & ifmap_read_done
 *      sebelum kembali ke IDLE.
 *      → Di simulasi (tready=1): tidak ada efek negatif, keduanya hampir
 *        bersamaan.
 *      → Di hardware (backpressure DMA nyata): M1 tidak lagi ditinggalkan
 *        tanpa TLAST saat M0 selesai lebih dulu.
 *
 *   3. Port baru: ifmap_read_done (input) disambung dari ifmap_wrapper
 *      di System_Level_Top.
 *
 ******************************************************************************/

module Output_Manager_Simple #(
    parameter DW = 16
)(
    input  wire clk,
    input  wire rst_n,

    // Status Inputs
    input  wire       batch_complete,
    input  wire [2:0] current_batch_id,
    input  wire       all_batches_done,
    input  wire [1:0] completed_layer_id,

    // Header Data Outputs
    output reg [15:0] header_word_0,
    output reg [15:0] header_word_1,
    output reg [15:0] header_word_2,
    output reg [15:0] header_word_3,
    output reg [15:0] header_word_4,
    output reg [15:0] header_word_5,

    // Satu sinyal trigger — sama seperti original
    output reg        send_header,

    output reg        trigger_read,
    output reg [2:0]  rd_bram_start,
    output reg [2:0]  rd_bram_end,
    output reg [15:0] rd_addr_count,
    output reg        notification_mode,

    // FIX: dua input read_done, tunggu keduanya sebelum IDLE
    input  wire       weight_read_done,
    input  wire       ifmap_read_done,

    output reg        transmission_active
);

    localparam IDLE              = 3'd0;
    localparam SEND_NOTIFICATION = 3'd1;
    localparam WAIT_NOTIF_DONE   = 3'd2;
    localparam SEND_FULL_DATA    = 3'd3;
    localparam WAIT_DATA_DONE    = 3'd4;

    reg [2:0] state, next_state;
    reg [2:0] latched_batch_id;
    reg [1:0] latched_layer_id;
    reg [3:0] delay_counter;

    // Edge detection
    reg batch_complete_prev;
    reg all_batches_done_prev;

    wire batch_complete_edge   = batch_complete   && !batch_complete_prev;
    wire all_batches_done_edge = all_batches_done && !all_batches_done_prev;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            batch_complete_prev   <= 1'b0;
            all_batches_done_prev <= 1'b0;
        end else begin
            batch_complete_prev   <= batch_complete;
            all_batches_done_prev <= all_batches_done;
        end
    end

    // Request Latching
    reg pending_notification;
    reg pending_full_data;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pending_notification <= 1'b0;
            pending_full_data    <= 1'b0;
            latched_batch_id     <= 3'd0;
            latched_layer_id     <= 2'd0;
        end else begin
            if (batch_complete_edge) begin
                pending_notification <= 1'b1;
                latched_batch_id     <= current_batch_id;
            end else if (state == SEND_NOTIFICATION) begin
                pending_notification <= 1'b0;
            end

            if (all_batches_done_edge) begin
                pending_full_data <= 1'b1;
                latched_layer_id  <= completed_layer_id;
            end else if (state == SEND_FULL_DATA) begin
                pending_full_data <= 1'b0;
            end
        end
    end

    // FSM state register & delay counter
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= IDLE;
            delay_counter <= 4'd0;
        end else begin
            state <= next_state;
            if (state == WAIT_NOTIF_DONE)
                delay_counter <= delay_counter + 4'd1;
            else
                delay_counter <= 4'd0;
        end
    end

    // FSM next state
    always @(*) begin
        next_state = state;
        case (state)
            IDLE: begin
                if (pending_notification)
                    next_state = SEND_NOTIFICATION;
                else if (pending_full_data)
                    next_state = SEND_FULL_DATA;
            end
            SEND_NOTIFICATION: next_state = WAIT_NOTIF_DONE;
            WAIT_NOTIF_DONE: begin
                if (delay_counter > 4'd14)
                    next_state = IDLE;
            end
            SEND_FULL_DATA: next_state = WAIT_DATA_DONE;
            WAIT_DATA_DONE: begin
                // FIX: tunggu KEDUA wrapper selesai
                if (weight_read_done && ifmap_read_done)
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

                SEND_NOTIFICATION: begin
                    transmission_active <= 1'b1;
                    notification_mode   <= 1'b1;
                    header_word_0 <= 16'hC0DE;
                    header_word_1 <= 16'h0001;
                    header_word_2 <= {13'd0, latched_batch_id};
                    header_word_3 <= {10'd0, latched_batch_id, 2'd0};
                    header_word_4 <= {10'd0, latched_batch_id, 2'd0} + 16'd3;
                    header_word_5 <= 16'd0;
                    rd_bram_start <= 3'd0;
                    rd_bram_end   <= 3'd0;
                    rd_addr_count <= 16'd0;
                    send_header   <= 1'b1;
                end

                WAIT_NOTIF_DONE: begin
                    transmission_active <= 1'b1;
                    notification_mode   <= 1'b1;
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