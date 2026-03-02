`timescale 1ns / 1ps

/******************************************************************************
 * Module      : Auto_Scheduler
 *
 * FIX (Feb 2026):
 * - Tambah input output_busy (dari Output_Manager.transmission_active)
 * - BATCH_ALL_DONE tidak boleh transition ke layer berikutnya selama
 *   output_busy=1 — mencegah clear_output_bram corrupt data yang sedang
 *   dibaca Output_Manager
 * - layer_changed hanya di-assert setelah output_busy=0
 ******************************************************************************/

module Auto_Scheduler (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       weight_write_done,
    input  wire       ifmap_write_done,
    input  wire       bias_write_done,
    input  wire       ext_scheduler_start,
    input  wire [1:0] external_layer_id,
    input  wire       batch_complete_signal,
    input  wire       output_busy,          // NEW: dari Output_Manager.transmission_active
    output wire       final_start_signal,
    output reg  [2:0] current_batch_id,
    output reg  [1:0] current_layer_id,
    output wire       all_batches_complete,
    output wire       layer_transition,
    output wire       clear_output_bram,
    output wire       auto_start_active,
    output wire       data_load_ready
);

    reg weight_write_done_prev, ifmap_write_done_prev, bias_write_done_prev;
    wire weight_done_posedge = weight_write_done & ~weight_write_done_prev;
    wire ifmap_done_posedge  = ifmap_write_done  & ~ifmap_write_done_prev;
    wire bias_done_posedge   = bias_write_done   & ~bias_write_done_prev;

    reg ifmap_loaded, weight_loaded, bias_loaded;

    wire all_three_loaded  = ifmap_loaded & weight_loaded & bias_loaded;
    wire weight_only_ready = weight_loaded;

    localparam [2:0]
        BATCH_IDLE         = 3'd0,
        BATCH_WAIT_INITIAL = 3'd1,
        BATCH_RUNNING      = 3'd2,
        BATCH_NEXT         = 3'd3,
        BATCH_ALL_DONE     = 3'd4;

    reg [2:0] batch_state, batch_next_state;
    reg       batch_auto_start;
    reg       layer_changed;
    reg       first_load_done;

    reg [2:0] max_batch_for_current_layer;
    always @(*) begin
        case (current_layer_id)
            2'd0:    max_batch_for_current_layer = 3'd7;
            2'd1:    max_batch_for_current_layer = 3'd3;
            2'd2:    max_batch_for_current_layer = 3'd0;
            2'd3:    max_batch_for_current_layer = 3'd0;
            default: max_batch_for_current_layer = 3'd7;
        endcase
    end

    // Layer ID counter — hanya naik saat output_busy=0
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_layer_id <= 2'd0;
            layer_changed    <= 1'b0;
            first_load_done  <= 1'b0;
        end else begin
            layer_changed <= 1'b0;
            // FIX: tambah !output_busy — jangan transition jika Output_Manager
            // masih kirim data (mencegah clear_output_bram corrupt BRAM)
            if (all_three_loaded && batch_state == BATCH_ALL_DONE && !output_busy) begin
                if (current_layer_id < 2'd3)
                    current_layer_id <= current_layer_id + 2'd1;
                else
                    current_layer_id <= 2'd0;
                layer_changed <= 1'b1;
            end
            if (all_three_loaded && batch_state == BATCH_IDLE && !first_load_done)
                first_load_done <= 1'b1;
        end
    end

    assign layer_transition = layer_changed;

    reg [1:0] clear_bram_counter;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            clear_bram_counter <= 2'd0;
        else if (layer_changed)
            clear_bram_counter <= 2'd2;
        else if (clear_bram_counter > 0)
            clear_bram_counter <= clear_bram_counter - 2'd1;
    end
    assign clear_output_bram = (clear_bram_counter > 0);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            weight_write_done_prev <= 1'b0;
            ifmap_write_done_prev  <= 1'b0;
            bias_write_done_prev   <= 1'b0;
            ifmap_loaded           <= 1'b0;
            weight_loaded          <= 1'b0;
            bias_loaded            <= 1'b0;
        end else begin
            weight_write_done_prev <= weight_write_done;
            ifmap_write_done_prev  <= ifmap_write_done;
            bias_write_done_prev   <= bias_write_done;

            if (ifmap_done_posedge)  ifmap_loaded  <= 1'b1;
            if (weight_done_posedge) weight_loaded <= 1'b1;
            if (bias_done_posedge)   bias_loaded   <= 1'b1;

            if (batch_state == BATCH_WAIT_INITIAL) begin
                weight_loaded <= 1'b0;
                if (layer_changed) begin
                    ifmap_loaded <= 1'b0;
                    bias_loaded  <= 1'b0;
                end
            end
        end
    end

    assign data_load_ready = weight_loaded;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) batch_state <= BATCH_IDLE;
        else        batch_state <= batch_next_state;
    end

    always @(*) begin
        batch_next_state = batch_state;
        case (batch_state)
            BATCH_IDLE: begin
                if (all_three_loaded)
                    batch_next_state = BATCH_WAIT_INITIAL;
            end
            BATCH_WAIT_INITIAL: begin
                batch_next_state = BATCH_RUNNING;
            end
            BATCH_RUNNING: begin
                if (batch_complete_signal) begin
                    if (current_batch_id >= max_batch_for_current_layer)
                        batch_next_state = BATCH_ALL_DONE;
                    else
                        batch_next_state = BATCH_NEXT;
                end
            end
            BATCH_NEXT: begin
                if (weight_only_ready)
                    batch_next_state = BATCH_WAIT_INITIAL;
            end
            BATCH_ALL_DONE: begin
                // FIX: tunggu output_busy=0 sebelum terima data layer berikutnya
                if (all_three_loaded && !output_busy)
                    batch_next_state = BATCH_WAIT_INITIAL;
            end
            default: batch_next_state = BATCH_IDLE;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_batch_id <= 3'd0;
        end else begin
            case (batch_state)
                BATCH_IDLE: begin
                    if (all_three_loaded)
                        current_batch_id <= 3'd0;
                end
                BATCH_NEXT: begin
                    if (weight_only_ready)
                        current_batch_id <= current_batch_id + 3'd1;
                end
                BATCH_ALL_DONE: begin
                    // FIX: juga tunggu !output_busy sebelum reset batch_id
                    if (all_three_loaded && !output_busy)
                        current_batch_id <= 3'd0;
                end
            endcase
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            batch_auto_start <= 1'b0;
        end else begin
            batch_auto_start <= 1'b0;
            if (batch_state == BATCH_WAIT_INITIAL)
                batch_auto_start <= 1'b1;
        end
    end

    assign final_start_signal   = batch_auto_start | ext_scheduler_start;
    assign auto_start_active    = batch_auto_start;
    assign all_batches_complete = (batch_state == BATCH_ALL_DONE);

endmodule