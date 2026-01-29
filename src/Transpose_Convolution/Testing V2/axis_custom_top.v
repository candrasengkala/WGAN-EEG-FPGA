`timescale 1ns / 1ps
`include "External_AXI_FSM.v"
`include "MM2S_S2MM.v"
`include "axis_counter.v"
`include "demux1to16.v"
`include "mux8to1.v"

module axis_custom_top #(
    parameter BRAM_DEPTH = 512,
    parameter DATA_WIDTH = 16,
    parameter BRAM_COUNT = 16,
    parameter ADDR_WIDTH = 9
)(
    input wire aclk,
    input wire aresetn,
    
    // AXI Stream Slave
    input wire [DATA_WIDTH-1:0] s_axis_tdata,
    input wire s_axis_tvalid,
    output wire s_axis_tready,
    input wire s_axis_tlast,
    
    // AXI Stream Master
    output wire [DATA_WIDTH-1:0] m_axis_tdata,
    output wire m_axis_tvalid,
    input wire m_axis_tready,
    output wire m_axis_tlast,
    
    // FSM Control
    input wire [7:0] Instruction_code,
    input wire [4:0] wr_bram_start, input wire [4:0] wr_bram_end,
    input wire [15:0] wr_addr_start, input wire [15:0] wr_addr_count,
    input wire [2:0] rd_bram_start, input wire [2:0] rd_bram_end,
    input wire [15:0] rd_addr_start, input wire [15:0] rd_addr_count,
    
    // Header Injection
    input wire [15:0] header_word_0, header_word_1, header_word_2,
    input wire [15:0] header_word_3, header_word_4, header_word_5,
    input wire        send_header,
    input wire        notification_only, // NEW
    
    // Status
    output wire write_done, read_done,
    output wire [9:0] mm2s_data_count,
    
    // BRAM Interface
    output wire [BRAM_COUNT*DATA_WIDTH-1:0] bram_wr_data_flat,
    output wire [ADDR_WIDTH-1:0]            bram_wr_addr,
    output wire [BRAM_COUNT-1:0]            bram_wr_en,
    input  wire [8*DATA_WIDTH-1:0]          bram_rd_data_flat,
    output wire [ADDR_WIDTH-1:0]            bram_rd_addr
);

    // Internal Wires
    wire [DATA_WIDTH-1:0] mm2s_tdata, s2mm_tdata, mux_out;
    wire mm2s_tvalid, mm2s_tready, mm2s_tlast;
    wire s2mm_tvalid, s2mm_tready, s2mm_tlast;
    wire wr_counter_enable, wr_counter_start, rd_counter_enable, rd_counter_start;
    wire [15:0] wr_counter, rd_counter, wr_start_addr, wr_count_limit, rd_start_addr, rd_count_limit;
    wire wr_counter_done, rd_counter_done;
    wire [4:0] demux_sel;
    wire [2:0] mux_sel;
    wire bram_rd_enable;
    wire [DATA_WIDTH-1:0] demux_out [0:BRAM_COUNT-1];
    wire [DATA_WIDTH-1:0] bram_dout [0:7];
    wire fsm_batch_write_done, fsm_batch_read_done;
    
    // Sinyal valid original (hanya 1 kalau ada input dari DMA)
    wire bram_wr_enable_original;
    assign bram_wr_enable_original = mm2s_tvalid && mm2s_tready;

    // ========================================================================
    // HEADER INJECTION & AUTO TRIGGER LOGIC
    // ========================================================================
    reg [15:0] header_buffer [0:5];
    reg [2:0]  header_word_count;
    reg        sending_header;
    reg        header_sent;
    reg        auto_read_triggered;
    
    // Register untuk menyimpan parameter kontrol dari Output Manager
    reg [2:0]  latched_auto_bram_end;
    reg [15:0] latched_auto_addr_count;
    
    wire auto_instruction_valid;
    assign auto_instruction_valid = send_header && !auto_read_triggered;
    
    always @(posedge aclk) begin
        if (!aresetn) begin
            header_word_count <= 0; sending_header <= 0; 
            header_sent <= 0; auto_read_triggered <= 0;
            latched_auto_bram_end <= 0; latched_auto_addr_count <= 0;
        end else begin
            // Trigger start
            if (send_header && !sending_header && !header_sent) begin
                header_buffer[0] <= header_word_0; header_buffer[1] <= header_word_1;
                header_buffer[2] <= header_word_2; header_buffer[3] <= header_word_3;
                header_buffer[4] <= header_word_4; header_buffer[5] <= header_word_5;
                
                // CRITICAL FIX: Tangkap parameter kontrol langsung dari port input (Output Manager)
                // Jangan menebak dari isi header_word_5 karena header isinya Total Size (4096),
                // sedangkan FSM butuh Size per BRAM (512).
                latched_auto_bram_end   <= rd_bram_end;
                latched_auto_addr_count <= rd_addr_count;
                
                sending_header <= 1; header_word_count <= 0;
                auto_read_triggered <= 1;
            end
            
            // Proses pengiriman Header
            if (sending_header && s2mm_tready) begin
                if (header_word_count < 5) header_word_count <= header_word_count + 1;
                else begin sending_header <= 0; header_sent <= 1; end
            end
            
            // CRITICAL FIX: Reset trigger when FSM BATCH READ is DONE (not counter done!)
            // This prevents premature reset when reading multiple BRAMs
            // fsm_batch_read_done pulses only when ALL BRAMs are finished
            // For header-only, just reset after header is sent.
            if ((fsm_batch_read_done && header_sent) || (notification_only && header_sent)) begin
                header_sent <= 0; auto_read_triggered <= 0;
            end
        end
    end
    
    // Mux output: Pilih Header saat sending_header, selebihnya Data BRAM
    assign s2mm_tdata = sending_header ? header_buffer[header_word_count] : mux_out;

    // ========================================================================
    // LOGIC FIX: FSM TIMING & PARAMETER RETENTION
    // ========================================================================
    wire use_auto_mode = send_header || auto_read_triggered;

    // Gunakan nilai input saat pulse trigger, selebihnya gunakan nilai yang sudah di-latch
    // (Ini mencegah FSM membaca nilai 0 saat sinyal send_header turun)
    wire [15:0] current_auto_count = (send_header) ? rd_addr_count : latched_auto_addr_count;
    wire [2:0]  current_auto_end   = (send_header) ? rd_bram_end   : latched_auto_bram_end;

    wire [7:0] instruction_to_fsm;
    // PENTING: Tahan instruksi 0x02 (READ) sampai Header SELESAI dikirim (!sending_header).
    // JANGAN kirim instruksi READ jika ini adalah notifikasi header-saja.
    assign instruction_to_fsm = (use_auto_mode && !sending_header && !notification_only) ? 8'h02 : Instruction_code;
    
    wire [2:0] rd_bram_start_to_fsm = use_auto_mode ? 3'd0 : rd_bram_start;
    
    // FIX: Gunakan BRAM End yang benar (bisa 0 untuk Notif, atau 7 untuk Full Data)
    wire [2:0] rd_bram_end_to_fsm   = use_auto_mode ? current_auto_end : rd_bram_end;
    
    // FIX: Gunakan Count per BRAM (512) yang benar, BUKAN total size header (4096)
    wire [15:0] rd_addr_count_to_fsm = use_auto_mode ? current_auto_count : rd_addr_count;

    // ========================================================================
    // FIX UTAMA (YANG SEBELUMNYA MASIH SALAH): FAKE VALID
    // ========================================================================
    // Kita buat sinyal "palsu" supaya FSM mengira ada data valid masuk (bram_wr_enable = 1),
    // sehingga dia mau pindah state dari IDLE ke READ_SETUP/WAIT.
    wire fsm_trigger_enable;
    assign fsm_trigger_enable = bram_wr_enable_original || (use_auto_mode && !sending_header);

    External_AXI_FSM fsm_inst (
        .aclk(aclk), .aresetn(aresetn),
        .Instruction_code(instruction_to_fsm), 
        .wr_bram_start(wr_bram_start), .wr_bram_end(wr_bram_end),
        .wr_addr_start(wr_addr_start), .wr_addr_count(wr_addr_count),
        .rd_bram_start(rd_bram_start_to_fsm), .rd_bram_end(rd_bram_end_to_fsm),
        .rd_addr_start(rd_addr_start), .rd_addr_count(rd_addr_count_to_fsm),
        
        .bram_wr_enable(fsm_trigger_enable), // <-- TERHUBUNG KE FAKE VALID SIGNAL
        
        .wr_counter_done(wr_counter_done), .rd_counter_done(rd_counter_done),
        .wr_counter_enable(wr_counter_enable), .wr_counter_start(wr_counter_start),
        .wr_start_addr(wr_start_addr), .wr_count_limit(wr_count_limit),
        .rd_counter_enable(rd_counter_enable), .rd_counter_start(rd_counter_start),
        .rd_start_addr(rd_start_addr), .rd_count_limit(rd_count_limit),
        .demux_sel(demux_sel), .mux_sel(mux_sel), .bram_rd_enable(bram_rd_enable),
        .batch_write_done(fsm_batch_write_done), .batch_read_done(fsm_batch_read_done)
    );

    // MM2S/S2MM FIFO Wrapper
    MM2S_S2MM #(.FIFO_DEPTH(512), .DATA_WIDTH(DATA_WIDTH)) fifo_wrapper (
        .aclk(aclk), .aresetn(aresetn),
        .s_axis_tdata(s_axis_tdata), .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready), .s_axis_tlast(s_axis_tlast),
        .mm2s_tdata(mm2s_tdata), .mm2s_tvalid(mm2s_tvalid),
        .mm2s_tready(mm2s_tready), .mm2s_tlast(mm2s_tlast), .mm2s_data_count(mm2s_data_count),
        .s2mm_tdata(s2mm_tdata), .s2mm_tvalid(s2mm_tvalid),
        .s2mm_tready(s2mm_tready), .s2mm_tlast(s2mm_tlast),
        .m_axis_tdata(m_axis_tdata), .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready), .m_axis_tlast(m_axis_tlast)
    );

    // Counters
    axis_counter wr_counter_inst (
        .aclk(aclk), .aresetn(aresetn),
        .counter_enable(wr_counter_enable), .counter_start(wr_counter_start),
        .start_addr(wr_start_addr), .count_limit(wr_count_limit),
        .counter(wr_counter), .counter_done(wr_counter_done)
    );
    assign write_done = fsm_batch_write_done;

    axis_counter rd_counter_inst (
        .aclk(aclk), .aresetn(aresetn),
        .counter_enable(rd_counter_enable), .counter_start(rd_counter_start),
        .start_addr(rd_start_addr), .count_limit(rd_count_limit),
        .counter(rd_counter), .counter_done(rd_counter_done)
    );
    assign read_done = fsm_batch_read_done;

    // Demux & Mux
    demux1to16 #(.DATA_WIDTH(DATA_WIDTH)) demux_inst (
        .data_in(mm2s_tdata), .sel(demux_sel[3:0]),
        .out_0(demux_out[0]), .out_1(demux_out[1]), .out_2(demux_out[2]), .out_3(demux_out[3]),
        .out_4(demux_out[4]), .out_5(demux_out[5]), .out_6(demux_out[6]), .out_7(demux_out[7]),
        .out_8(demux_out[8]), .out_9(demux_out[9]), .out_10(demux_out[10]), .out_11(demux_out[11]),
        .out_12(demux_out[12]), .out_13(demux_out[13]), .out_14(demux_out[14]), .out_15(demux_out[15])
    );

    mux8to1 #(.DATA_WIDTH(DATA_WIDTH)) mux_inst (
        .in_0(bram_dout[0]), .in_1(bram_dout[1]), .in_2(bram_dout[2]), .in_3(bram_dout[3]),
        .in_4(bram_dout[4]), .in_5(bram_dout[5]), .in_6(bram_dout[6]), .in_7(bram_dout[7]),
        .sel(mux_sel[2:0]), .data_out(mux_out)
    );

    // Control Logic
    wire fsm_write_active = (fsm_inst.current_state == 4'd2) || (fsm_inst.current_state == 4'd6);
    assign mm2s_tready = fsm_write_active && !wr_counter_done;
    
    // TValid Logic: Active for Header OR Data
    assign s2mm_tvalid = sending_header || (bram_rd_enable && rd_counter_enable);

    // CRITICAL FIX: TLAST should only assert on the LAST BRAM of the read sequence
    // For auto-read mode: check if current BRAM (mux_sel) >= target end (latched_auto_bram_end)
    // For normal mode: use original behavior (TLAST on every counter done)
    wire is_last_bram_in_auto = (mux_sel >= latched_auto_bram_end);
    wire auto_read_tlast = rd_counter_done && is_last_bram_in_auto && header_sent;
    wire normal_read_tlast = rd_counter_done && !use_auto_mode;
    
    // NEW TLAST LOGIC
    wire notification_tlast = sending_header && (header_word_count == 5);
    wire data_read_tlast = auto_read_tlast || normal_read_tlast;
    assign s2mm_tlast = notification_only ? notification_tlast : data_read_tlast;
    
    // BRAM Connectivity
    genvar i;
    generate
        for (i = 0; i < BRAM_COUNT; i = i + 1) begin : WR_DATA_FLATTEN
            assign bram_wr_data_flat[i*DATA_WIDTH +: DATA_WIDTH] = demux_out[i];
        end
        for (i = 0; i < 8; i = i + 1) begin : RD_DATA_UNFLATTEN
            assign bram_dout[i] = bram_rd_data_flat[i*DATA_WIDTH +: DATA_WIDTH];
        end
    endgenerate
    
    assign bram_wr_addr = wr_counter[ADDR_WIDTH-1:0];
    assign bram_wr_en = (16'b1 << demux_sel) & {16{wr_counter_enable}};
    assign bram_rd_addr = rd_counter[ADDR_WIDTH-1:0];

endmodule