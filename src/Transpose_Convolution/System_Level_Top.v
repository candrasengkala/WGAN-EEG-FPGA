`timescale 1ns / 1ps

// System_Level_Top.v
// Verilog-2001 (IEEE 1364-2001) -- NO SystemVerilog constructs
//
// FIX (Feb 2026) - MINIMAL:
// 1. Tambah wire ifmap_read_done dari ifmap_wrapper ke Output_Manager.
//    Sebelumnya .read_done() di ifmap_wrapper dibiarkan floating —
//    Output Manager tidak tahu kapan M1 selesai.
//
// 2. send_header TETAP SATU SINYAL ke kedua wrapper (tidak dipecah).
//    Ini identik dengan versi original yang sudah lulus simulasi.
//    Perbedaan perilaku di hardware diselesaikan oleh fix #1 saja.
//
// 3. Port Output_Manager diubah: read_done → weight_read_done + ifmap_read_done
//
// Semua hal lain tidak berubah dari versi original.

module System_Level_Top #(
    parameter DW        = 24,
    parameter NUM_BRAMS = 16,
    parameter W_ADDR_W  = 10,
    parameter I_ADDR_W  = 10,
    parameter O_ADDR_W  = 9,
    parameter W_DEPTH   = 1024,
    parameter I_DEPTH   = 1024,
    parameter O_DEPTH   = 512,
    parameter Dimension = 16
)(
    input  wire        aclk,
    input  wire        aresetn,

    input  wire [31:0] s0_axis_tdata,
    input  wire [3:0]  s0_axis_tkeep,
    input  wire        s0_axis_tvalid,
    output wire        s0_axis_tready,
    input  wire        s0_axis_tlast,
    output wire [31:0] m0_axis_tdata,
    output wire [3:0]  m0_axis_tkeep,
    output wire        m0_axis_tvalid,
    input  wire        m0_axis_tready,
    output wire        m0_axis_tlast,

    input  wire [31:0] s1_axis_tdata,
    input  wire [3:0]  s1_axis_tkeep,
    input  wire        s1_axis_tvalid,
    output wire        s1_axis_tready,
    input  wire        s1_axis_tlast,
    output wire [31:0] m1_axis_tdata,
    output wire [3:0]  m1_axis_tkeep,
    output wire        m1_axis_tvalid,
    input  wire        m1_axis_tready,
    output wire        m1_axis_tlast,

    input  wire [31:0] s2_axis_tdata,
    input  wire [3:0]  s2_axis_tkeep,
    input  wire        s2_axis_tvalid,
    output wire        s2_axis_tready,
    input  wire        s2_axis_tlast
);

    // ========================================================================
    // Internal Wires
    // ========================================================================
    wire           weight_write_done;
    wire           ifmap_write_done;
    wire           bias_write_done;
    wire           weight_read_done;
    wire           ifmap_read_done;       // FIX: baru, dari M1
    wire [1:0]     current_layer_id;
    wire [2:0]     current_batch_id;
    wire           all_batches_done;
    wire           auto_start_active;

    wire [NUM_BRAMS*DW-1:0]        weight_wr_data_flat;
    wire [W_ADDR_W-1:0]            weight_wr_addr;
    wire [NUM_BRAMS-1:0]           weight_wr_en;
    wire [W_ADDR_W-1:0]            weight_rd_addr;

    wire [NUM_BRAMS*DW-1:0]        ifmap_wr_data_flat;
    wire [I_ADDR_W-1:0]            ifmap_wr_addr;
    wire [NUM_BRAMS-1:0]           ifmap_wr_en;
    wire [I_ADDR_W-1:0]            ifmap_rd_addr;

    wire [NUM_BRAMS*DW-1:0]        bias_wr_data_flat;
    wire [O_ADDR_W-1:0]            bias_wr_addr;
    wire [NUM_BRAMS-1:0]           bias_wr_en;
    wire                           bias_write_active;

    wire [NUM_BRAMS-1:0]           w_re;
    wire [NUM_BRAMS*W_ADDR_W-1:0]  w_addr_rd_flat;
    wire [NUM_BRAMS-1:0]           if_re;
    wire [NUM_BRAMS*I_ADDR_W-1:0]  if_addr_rd_flat;
    wire [3:0]                     ifmap_sel;
    wire [NUM_BRAMS-1:0]           en_weight_load;
    wire [NUM_BRAMS-1:0]           en_ifmap_load;
    wire [NUM_BRAMS-1:0]           en_psum;
    wire [NUM_BRAMS-1:0]           clear_psum;
    wire [NUM_BRAMS-1:0]           en_output;
    wire [NUM_BRAMS-1:0]           ifmap_sel_ctrl;
    wire [NUM_BRAMS-1:0]           cmap_snapshot;
    wire [NUM_BRAMS*14-1:0]        omap_snapshot;
    wire                           clear_output_bram;
    wire                           internal_scheduler_done;
    wire [NUM_BRAMS*DW-1:0]        ext_read_data_flat;

    localparam TKEEP_INT = (DW + 7) / 8;

    wire [DW-1:0]          m0_axis_tdata_int;
    wire [DW-1:0]          m1_axis_tdata_int;
    wire [TKEEP_INT-1:0]   m0_axis_tkeep_int;
    wire [TKEEP_INT-1:0]   m1_axis_tkeep_int;

    assign m0_axis_tdata = {{(32-DW){1'b0}}, m0_axis_tdata_int};
    assign m1_axis_tdata = {{(32-DW){1'b0}}, m1_axis_tdata_int};
    // FIX (Feb 2026): TKEEP harus 4'b1111 di setiap beat (termasuk non-TLAST).
    // Sebelumnya: {{(4-TKEEP_INT){1'b0}}, tkeep_int} → DW=24 menghasilkan 4'b0111
    // permanen, menyebabkan DMAIntErr di setiap transfer karena AXI-Stream
    // melarang TKEEP parsial kecuali di beat terakhir (TLAST=1).
    // Data selalu 32-bit aligned sehingga 4'b1111 valid dan aman.
    assign m0_axis_tkeep = 4'b1111;
    assign m1_axis_tkeep = 4'b1111;

    wire [15:0] header_word_0;
    wire [15:0] header_word_1;
    wire [15:0] header_word_2;
    wire [15:0] header_word_3;
    wire [15:0] header_word_4;
    wire [15:0] header_word_5;
    wire        send_header;

    wire        out_mgr_trigger_read;
    wire [2:0]  out_mgr_rd_bram_start;
    wire [2:0]  out_mgr_rd_bram_end;
    wire [15:0] out_mgr_rd_addr_count;
    wire        out_mgr_notification_mode;
    wire        out_mgr_transmission_active;
    wire        out_mgr_ext_read_mode;

    wire [8*DW-1:0] out_group0_bram_data;
    wire [8*DW-1:0] out_group1_bram_data;
    wire [4:0]      done_transpose;
    wire [NUM_BRAMS*O_ADDR_W-1:0] out_mgr_ext_read_addr_flat;

    assign out_mgr_ext_read_mode = out_mgr_transmission_active;

    genvar k;
    generate
        for (k = 0; k < 8; k = k + 1) begin : MAP_ADDR_GRP0
            assign out_mgr_ext_read_addr_flat[k*O_ADDR_W +: O_ADDR_W] =
                   weight_rd_addr[O_ADDR_W-1:0];
        end
        for (k = 8; k < 16; k = k + 1) begin : MAP_ADDR_GRP1
            assign out_mgr_ext_read_addr_flat[k*O_ADDR_W +: O_ADDR_W] =
                   ifmap_rd_addr[O_ADDR_W-1:0];
        end
    endgenerate

    assign out_group0_bram_data = ext_read_data_flat[8*DW-1 : 0];
    assign out_group1_bram_data = ext_read_data_flat[16*DW-1 : 8*DW];

    // ========================================================================
    // WEIGHT WRAPPER / M0
    // ========================================================================
    axis_control_wrapper #(
        .BRAM_DEPTH  (W_DEPTH),
        .DATA_WIDTH  (DW),
        .BRAM_COUNT  (NUM_BRAMS),
        .ADDR_WIDTH  (W_ADDR_W),
        .ENABLE_S2MM (1)
    ) weight_wrapper (
        .aclk                 (aclk),
        .aresetn              (aresetn),
        .s_axis_tdata         (s0_axis_tdata[DW-1:0]),
        .s_axis_tvalid        (s0_axis_tvalid),
        .s_axis_tready        (s0_axis_tready),
        .s_axis_tlast         (s0_axis_tlast),
        .m_axis_tdata         (m0_axis_tdata_int),
        .m_axis_tkeep         (m0_axis_tkeep_int),
        .m_axis_tvalid        (m0_axis_tvalid),
        .m_axis_tready        (m0_axis_tready),
        .m_axis_tlast         (m0_axis_tlast),
        .header_word_0        (header_word_0),
        .header_word_1        (header_word_1),
        .header_word_2        (header_word_2),
        .header_word_3        (header_word_3),
        .header_word_4        (header_word_4),
        .header_word_5        (header_word_5),
        .send_header          (send_header),
        .out_mgr_rd_bram_start(out_mgr_rd_bram_start),
        .out_mgr_rd_bram_end  (out_mgr_rd_bram_end),
        .out_mgr_rd_addr_count(out_mgr_rd_addr_count),
        .notification_mode    (out_mgr_notification_mode),
        .write_done           (weight_write_done),
        .read_done            (weight_read_done),
        .mm2s_data_count      (),
        .parser_state         (),
        .error_invalid_magic  (),
        .bram_wr_data_flat    (weight_wr_data_flat),
        .bram_wr_addr         (weight_wr_addr),
        .bram_wr_en           (weight_wr_en),
        .bram_rd_data_flat    (out_group0_bram_data),
        .bram_rd_addr         (weight_rd_addr)
    );

    // ========================================================================
    // IFMAP WRAPPER / M1
    // ========================================================================
    axis_control_wrapper #(
        .BRAM_DEPTH  (I_DEPTH),
        .DATA_WIDTH  (DW),
        .BRAM_COUNT  (NUM_BRAMS),
        .ADDR_WIDTH  (I_ADDR_W),
        .ENABLE_S2MM (1)
    ) ifmap_wrapper (
        .aclk                 (aclk),
        .aresetn              (aresetn),
        .s_axis_tdata         (s1_axis_tdata[DW-1:0]),
        .s_axis_tvalid        (s1_axis_tvalid),
        .s_axis_tready        (s1_axis_tready),
        .s_axis_tlast         (s1_axis_tlast),
        .m_axis_tdata         (m1_axis_tdata_int),
        .m_axis_tkeep         (m1_axis_tkeep_int),
        .m_axis_tvalid        (m1_axis_tvalid),
        .m_axis_tready        (m1_axis_tready),
        .m_axis_tlast         (m1_axis_tlast),
        .header_word_0        (header_word_0),
        .header_word_1        (header_word_1),
        .header_word_2        (header_word_2),
        .header_word_3        (header_word_3),
        .header_word_4        (header_word_4),
        .header_word_5        (header_word_5),
        .send_header          (send_header),  // FIX: data dump saja
        .out_mgr_rd_bram_start(out_mgr_rd_bram_start),
        .out_mgr_rd_bram_end  (out_mgr_rd_bram_end),
        .out_mgr_rd_addr_count(out_mgr_rd_addr_count),
        .notification_mode    (out_mgr_notification_mode),
        .write_done           (ifmap_write_done),
        .read_done            (ifmap_read_done),
        .mm2s_data_count      (),
        .parser_state         (),
        .error_invalid_magic  (),
        .bram_wr_data_flat    (ifmap_wr_data_flat),
        .bram_wr_addr         (ifmap_wr_addr),
        .bram_wr_en           (ifmap_wr_en),
        .bram_rd_data_flat    (out_group1_bram_data),
        .bram_rd_addr         (ifmap_rd_addr)
    );

    // ========================================================================
    // BIAS WRAPPER -- WRITE ONLY (ENABLE_S2MM=0)
    // ========================================================================
    axis_control_wrapper #(
        .BRAM_DEPTH  (O_DEPTH),
        .DATA_WIDTH  (DW),
        .BRAM_COUNT  (NUM_BRAMS),
        .ADDR_WIDTH  (O_ADDR_W),
        .ENABLE_S2MM (0)
    ) bias_wrapper (
        .aclk                 (aclk),
        .aresetn              (aresetn),
        .s_axis_tdata         (s2_axis_tdata[DW-1:0]),
        .s_axis_tvalid        (s2_axis_tvalid),
        .s_axis_tready        (s2_axis_tready),
        .s_axis_tlast         (s2_axis_tlast),
        .m_axis_tdata         (),
        .m_axis_tkeep         (),
        .m_axis_tvalid        (),
        .m_axis_tready        (1'b0),
        .m_axis_tlast         (),
        .header_word_0        (16'h0),
        .header_word_1        (16'h0),
        .header_word_2        (16'h0),
        .header_word_3        (16'h0),
        .header_word_4        (16'h0),
        .header_word_5        (16'h0),
        .send_header          (1'b0),
        .out_mgr_rd_bram_start(3'b0),
        .out_mgr_rd_bram_end  (3'b0),
        .out_mgr_rd_addr_count(16'b0),
        .notification_mode    (1'b0),
        .write_done           (bias_write_done),
        .read_done            (),
        .mm2s_data_count      (),
        .parser_state         (),
        .error_invalid_magic  (),
        .bram_wr_data_flat    (bias_wr_data_flat),
        .bram_wr_addr         (bias_wr_addr),
        .bram_wr_en           (bias_wr_en),
        .bram_rd_data_flat    ({(8*DW){1'b0}}),
        .bram_rd_addr         ()
    );

    assign bias_write_active = |bias_wr_en;

    // ========================================================================
    // TRANSPOSE CONTROL TOP
    // ========================================================================
    Transpose_Control_Top #(
        .DW        (DW),
        .NUM_BRAMS (NUM_BRAMS),
        .NUM_PE    (Dimension),
        .ADDR_WIDTH(I_ADDR_W)
    ) control_top (
        .clk                  (aclk),
        .rst_n                (aresetn),
        .weight_write_done    (weight_write_done),
        .ifmap_write_done     (ifmap_write_done),
        .bias_write_done      (bias_write_done),
        .batch_complete_signal(internal_scheduler_done),
        .ext_start            (1'b0),
        .ext_layer_id         (2'd0),
        // FIX: sambungkan output_busy agar scheduler tidak transition layer
        // saat Output_Manager masih kirim DA7A (mencegah clear_output_bram corrupt)
        .output_busy          (out_mgr_transmission_active),
        .current_layer_id     (current_layer_id),
        .current_batch_id     (current_batch_id),
        .scheduler_done       (),
        .all_batches_done     (all_batches_done),
        .clear_output_bram    (clear_output_bram),
        .auto_active          (auto_start_active),
        .w_re                 (w_re),
        .w_addr_rd_flat       (w_addr_rd_flat),
        .if_re                (if_re),
        .if_addr_rd_flat      (if_addr_rd_flat),
        .ifmap_sel_out        (ifmap_sel),
        .en_weight_load       (en_weight_load),
        .en_ifmap_load        (en_ifmap_load),
        .en_psum              (en_psum),
        .clear_psum           (clear_psum),
        .en_output            (en_output),
        .ifmap_sel_ctrl       (ifmap_sel_ctrl),
        .cmap_snapshot        (cmap_snapshot),
        .omap_snapshot        (omap_snapshot),
        .mapper_done_pulse    (),
        .selector_mux_transpose(done_transpose)
    );

    // ========================================================================
    // DATAPATH
    // ========================================================================
    Super_TOP_Level #(
        .DW       (DW),
        .NUM_BRAMS(NUM_BRAMS),
        .W_ADDR_W (W_ADDR_W),
        .I_ADDR_W (I_ADDR_W),
        .O_ADDR_W (O_ADDR_W)
    ) datapath (
        .clk                 (aclk),
        .rst_n               (aresetn),
        .w_we                (weight_wr_en),
        .w_addr_wr_flat      ({NUM_BRAMS{weight_wr_addr}}),
        .w_din_flat          (weight_wr_data_flat),
        .w_re                (w_re),
        .w_addr_rd_flat      (w_addr_rd_flat),
        .if_we               (ifmap_wr_en),
        .if_addr_wr_flat     ({NUM_BRAMS{ifmap_wr_addr}}),
        .if_din_flat         (ifmap_wr_data_flat),
        .if_re               (if_re),
        .if_addr_rd_flat     (if_addr_rd_flat),
        .ifmap_sel           (ifmap_sel),
        .en_weight_load      (en_weight_load),
        .en_ifmap_load       (en_ifmap_load),
        .en_psum             (en_psum),
        .clear_psum          (clear_psum),
        .en_output           (en_output),
        .ifmap_sel_ctrl      (ifmap_sel_ctrl),
        .done_select         (done_transpose),
        .cmap                (cmap_snapshot),
        .omap_flat           (omap_snapshot),
        .ext_read_mode       (out_mgr_ext_read_mode),
        .ext_read_addr_flat  (out_mgr_ext_read_addr_flat),
        .ext_read_data_flat  (ext_read_data_flat),
        .ext_write_mode      (bias_write_active),
        .ext_write_en        (bias_wr_en),
        .ext_write_addr_flat ({NUM_BRAMS{bias_wr_addr}}),
        .ext_write_data_flat (bias_wr_data_flat)
    );

    // ========================================================================
    // OUTPUT STREAM MANAGER
    // ========================================================================
    Output_Manager_Simple #(
        .DW(DW)
    ) output_mgr (
        .clk                (aclk),
        .rst_n              (aresetn),
        .batch_complete     (internal_scheduler_done),
        .current_batch_id   (current_batch_id),
        .all_batches_done   (all_batches_done),
        .completed_layer_id (current_layer_id),
        .header_word_0      (header_word_0),
        .header_word_1      (header_word_1),
        .header_word_2      (header_word_2),
        .header_word_3      (header_word_3),
        .header_word_4      (header_word_4),
        .header_word_5      (header_word_5),
        .send_header        (send_header),
        .trigger_read       (out_mgr_trigger_read),
        .rd_bram_start      (out_mgr_rd_bram_start),
        .rd_bram_end        (out_mgr_rd_bram_end),
        .rd_addr_count      (out_mgr_rd_addr_count),
        .notification_mode  (out_mgr_notification_mode),
        // FIX: kedua sinyal disambung
        .weight_read_done   (weight_read_done),
        .ifmap_read_done    (ifmap_read_done),
        .transmission_active(out_mgr_transmission_active)
    );

    ila_0 ila_debug (
        .clk(aclk),

        // ===== S0 AXIS =====
        .probe0  (s0_axis_tdata),
        .probe1  (s0_axis_tkeep),
        .probe2  (s0_axis_tvalid),
        .probe3  (s0_axis_tready),
        .probe4  (s0_axis_tlast),

        // ===== M0 AXIS =====
        .probe5  (m0_axis_tdata),
        .probe6  (m0_axis_tkeep),
        .probe7  (m0_axis_tvalid),
        .probe8  (m0_axis_tready),
        .probe9  (m0_axis_tlast),

        // ===== S1 AXIS =====
        .probe10 (s1_axis_tdata),
        .probe11 (s1_axis_tkeep),
        .probe12 (s1_axis_tvalid),
        .probe13 (s1_axis_tready),
        .probe14 (s1_axis_tlast),

        // ===== M1 AXIS =====
        .probe15 (m1_axis_tdata),
        .probe16 (m1_axis_tkeep),
        .probe17 (m1_axis_tvalid),
        .probe18 (m1_axis_tready),
        .probe19 (m1_axis_tlast),

        // ===== S2 AXIS =====
        .probe20 (s2_axis_tdata),
        .probe21 (s2_axis_tkeep),
        .probe22 (s2_axis_tvalid),
        .probe23 (s2_axis_tready),
        .probe24 (s2_axis_tlast)
    );

endmodule