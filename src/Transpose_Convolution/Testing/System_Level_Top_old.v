`timescale 1ns / 1ps
//sleep
module System_Level_Top 
#(
    parameter DW = 16, 
    parameter NUM_BRAMS = 16, 
    parameter ADDR_WIDTH = 10, 
    parameter Dimension = 16, 
    parameter DEPTH = 1024
)(
    input wire aclk, 
    input wire aresetn,
    
    // AXI Stream Interfaces (Tetap sama)
    input wire [DW-1:0] s0_axis_tdata, input wire s0_axis_tvalid, output wire s0_axis_tready, input wire s0_axis_tlast,
    output wire [DW-1:0] m0_axis_tdata, output wire m0_axis_tvalid, input wire m0_axis_tready, output wire m0_axis_tlast,
    
    input wire [DW-1:0] s1_axis_tdata, input wire s1_axis_tvalid, output wire s1_axis_tready, input wire s1_axis_tlast,
    output wire [DW-1:0] m1_axis_tdata, output wire m1_axis_tvalid, input wire m1_axis_tready, output wire m1_axis_tlast,
    
    // AXI Stream Master for Output Results (to PS via DMA S2MM)
    output wire [DW-1:0] m_output_axis_tdata,
    output wire m_output_axis_tvalid,
    input wire m_output_axis_tready,
    output wire m_output_axis_tlast,
    
    // Status Outputs
    output wire weight_write_done, weight_read_done, ifmap_write_done, ifmap_read_done,
    output wire [9:0] weight_mm2s_data_count, ifmap_mm2s_data_count,
    
    // Scheduler Control
    input wire scheduler_start, output wire scheduler_done,
    
    // External Read Interface
    input wire ext_read_mode, 
    input wire [NUM_BRAMS*ADDR_WIDTH-1:0] ext_read_addr_flat,
    
    // Debug Outputs
    output wire [2:0] weight_parser_state, weight_error_invalid_magic, 
    output wire [2:0] ifmap_parser_state, ifmap_error_invalid_magic,
    output wire auto_start_active, data_load_ready
);

    // Internal Wires for Data Path
    wire [NUM_BRAMS*DW-1:0] weight_wr_data_flat, ifmap_wr_data_flat;
    wire [ADDR_WIDTH-1:0] weight_wr_addr, ifmap_wr_addr;
    wire [NUM_BRAMS-1:0] weight_wr_en, ifmap_wr_en;
    wire [8*DW-1:0] weight_rd_data_flat, ifmap_rd_data_flat;
    wire [ADDR_WIDTH-1:0] weight_rd_addr, ifmap_rd_addr;
    
    // Scheduler Wires
    wire start_Mapper, done_mapper, start_transpose, start_ifmap, if_done, start_weight, done_weight;
    wire [8:0] row_id, num_iterations;
    wire [5:0] tile_id;
    wire [1:0] layer_id;
    wire [7:0] Instruction_code_transpose, iter_count;
    wire [4:0] done_transpose;
    wire [ADDR_WIDTH-1:0] if_addr_start, if_addr_end, addr_start, addr_end;
    wire [3:0] ifmap_sel_in;
    wire batch_complete; // Signal from Scheduler FSM indicating one batch is done
    
    // Auto Scheduler Wires (Connecting Auto_Scheduler to others)
    wire scheduler_start_combined;
    wire [2:0] current_batch_id;
    wire all_batches_complete;

    // Read Back Wires
    wire [NUM_BRAMS*DW-1:0] bram_read_data_flat;
    wire [NUM_BRAMS*ADDR_WIDTH-1:0] bram_read_addr_flat;

    // ========================================================================
    // INSTANTIATION 0: AUTO SCHEDULER
    // ========================================================================
    Auto_Scheduler u_auto_scheduler (
        .clk(aclk),
        .rst_n(aresetn),
        
        // Inputs
        .weight_write_done(weight_write_done),
        .ifmap_write_done(ifmap_write_done),
        .ext_scheduler_start(scheduler_start), // Manual Start
        .batch_complete_signal(batch_complete), // From Scheduler FSM
        
        // Outputs
        .final_start_signal(scheduler_start_combined), // To Scheduler FSM
        .current_batch_id(current_batch_id),           // To Scheduler FSM
        .all_batches_complete(all_batches_complete),   // To Output Manager
        
        // Debug Status
        .auto_start_active(auto_start_active),
        .data_load_ready(data_load_ready)

        .current_layer_id(current_layer_id),    // Output: layer ID
        .layer_transition(layer_transition),    // Output: pulse saat ganti layer
        .clear_output_bram(clear_output_bram),  // Output: reset BRAM output
    );

    // ========================================================================
    // INSTANTIATION 1: WEIGHT WRAPPER
    // ========================================================================
    axis_control_wrapper #(
        .BRAM_DEPTH(DEPTH), .DATA_WIDTH(DW), .BRAM_COUNT(NUM_BRAMS), .ADDR_WIDTH(ADDR_WIDTH)
    ) axis_weight_wrapper (
        .aclk(aclk), .aresetn(aresetn),
        .s_axis_tdata(s0_axis_tdata), .s_axis_tvalid(s0_axis_tvalid), .s_axis_tready(s0_axis_tready), .s_axis_tlast(s0_axis_tlast),
        .m_axis_tdata(m0_axis_tdata), .m_axis_tvalid(m0_axis_tvalid), .m_axis_tready(m0_axis_tready), .m_axis_tlast(m0_axis_tlast),
        .write_done(weight_write_done), .read_done(weight_read_done), .mm2s_data_count(weight_mm2s_data_count),
        .parser_state(weight_parser_state), .error_invalid_magic(weight_error_invalid_magic),
        .bram_wr_data_flat(weight_wr_data_flat), .bram_wr_addr(weight_wr_addr), .bram_wr_en(weight_wr_en),
        .bram_rd_data_flat(weight_rd_data_flat), .bram_rd_addr(weight_rd_addr)
    );

    // ========================================================================
    // INSTANTIATION 2: IFMAP WRAPPER
    // ========================================================================
    axis_control_wrapper #(
        .BRAM_DEPTH(DEPTH), .DATA_WIDTH(DW), .BRAM_COUNT(NUM_BRAMS), .ADDR_WIDTH(ADDR_WIDTH)
    ) axis_ifmap_wrapper (
        .aclk(aclk), .aresetn(aresetn),
        .s_axis_tdata(s1_axis_tdata), .s_axis_tvalid(s1_axis_tvalid), .s_axis_tready(s1_axis_tready), .s_axis_tlast(s1_axis_tlast),
        .m_axis_tdata(m1_axis_tdata), .m_axis_tvalid(m1_axis_tvalid), .m_axis_tready(m1_axis_tready), .m_axis_tlast(m1_axis_tlast),
        .write_done(ifmap_write_done), .read_done(ifmap_read_done), .mm2s_data_count(ifmap_mm2s_data_count),
        .parser_state(ifmap_parser_state), .error_invalid_magic(ifmap_error_invalid_magic),
        .bram_wr_data_flat(ifmap_wr_data_flat), .bram_wr_addr(ifmap_wr_addr), .bram_wr_en(ifmap_wr_en),
        .bram_rd_data_flat(ifmap_rd_data_flat), .bram_rd_addr(ifmap_rd_addr)
    );

    // ========================================================================
    // INSTANTIATION 3: SCHEDULER FSM
    // ========================================================================
    Scheduler_FSM #(
        .ADDR_WIDTH(ADDR_WIDTH)
    ) scheduler_inst (
        .clk(aclk), 
        .rst_n(aresetn), 
        .start(scheduler_start_combined), // From Auto_Scheduler
        
        // Batch control
        .current_batch_id(current_batch_id), // From Auto_Scheduler
        .batch_complete(batch_complete),     // To Auto_Scheduler
        
        // Signals to Compute Engine
        .done_mapper(done_mapper), 
        .done_weight(done_weight), 
        .if_done(if_done), 
        .done_transpose(done_transpose),
        
        .start_Mapper(start_Mapper), 
        .start_weight(start_weight), 
        .start_ifmap(start_ifmap), 
        .start_transpose(start_transpose),
        
        .if_addr_start(if_addr_start), 
        .if_addr_end(if_addr_end), 
        .ifmap_sel_in(ifmap_sel_in),
        .addr_start(addr_start), 
        .addr_end(addr_end), 
        .Instruction_code_transpose(Instruction_code_transpose),
        .num_iterations(num_iterations), 
        .row_id(row_id), 
        .tile_id(tile_id), 
        .layer_id(layer_id),

        .current_layer_id(current_layer_id),    // NEW: from Auto_Scheduler
        .current_batch_id(current_batch_id),    // From Auto_Scheduler
        
        .done(scheduler_done)
    );

    // ========================================================================
    // INSTANTIATION 4: COMPUTE ENGINE (SUPER TOP LEVEL)
    // ========================================================================
    Super_TOP_Level #(
        .DW(DW), .NUM_BRAMS(NUM_BRAMS), .ADDR_WIDTH(ADDR_WIDTH), .Dimension(Dimension)
    ) compute_engine (
        .clk(aclk), .rst_n(aresetn),
        // Control Signals from Scheduler
        .if_addr_start(if_addr_start), .if_addr_end(if_addr_end), .ifmap_sel_in(ifmap_sel_in), .start_ifmap(start_ifmap), .if_done(if_done),
        .addr_start(addr_start), .addr_end(addr_end), .start_weight(start_weight), .done_weight(done_weight),
        
        // Koneksi Sinyal Write dari AXI Wrapper
        .w_we(weight_wr_en), 
        .w_addr_wr_flat({NUM_BRAMS{weight_wr_addr}}), 
        .w_din_flat(weight_wr_data_flat),
        .clear_output_bram(clear_output_bram),  // NEW: reset accumulation BRAMs
        
        .if_we(ifmap_wr_en), 
        .if_addr_wr_flat({NUM_BRAMS{ifmap_wr_addr}}), 
        .if_din_flat(ifmap_wr_data_flat),
        
        // Transpose & Mapper
        .start_transpose(start_transpose), .Instruction_code_transpose(Instruction_code_transpose), 
        .num_iterations(num_iterations), .iter_count(iter_count), .done_transpose(done_transpose),
        .start_Mapper(start_Mapper), .row_id(row_id), .tile_id(tile_id), .layer_id(layer_id), .done_mapper(done_mapper),
        
        // Read Interface
        .ext_read_mode(final_ext_read_mode), .ext_read_addr_flat(final_ext_read_addr),
        .bram_read_data_flat(out_mgr_bram_read_data_flat), .bram_read_addr_flat(bram_read_addr_flat)
    );

    // ========================================================================
    // Output Stream Manager Wires
    // ========================================================================
    wire out_mgr_ext_read_mode;
    wire [NUM_BRAMS*ADDR_WIDTH-1:0] out_mgr_ext_read_addr_flat;
    wire [NUM_BRAMS*DW-1:0] out_mgr_bram_read_data_flat;
    
    // MUX between testbench ext_read and output_manager read
    wire final_ext_read_mode = ext_read_mode | out_mgr_ext_read_mode;
    wire [NUM_BRAMS*ADDR_WIDTH-1:0] final_ext_read_addr = ext_read_mode ? ext_read_addr_flat : out_mgr_ext_read_addr_flat;

    // ========================================================================
    // INSTANTIATION 5: OUTPUT STREAM MANAGER
    // ========================================================================
    output_stream_manager #(
        .DW(DW),
        .NUM_BRAMS(NUM_BRAMS),
        .ADDR_WIDTH(ADDR_WIDTH),
        .OUTPUT_DEPTH(512)
    ) output_mgr_inst (
        .clk(aclk),
        .rst_n(aresetn),
        
        // Triggers from Auto Scheduler
        .batch_complete(batch_complete),
        .completed_batch_id(current_batch_id), // From Auto_Scheduler
        .all_batches_complete(all_batches_complete), // From Auto_Scheduler
        
        // Output BRAM Read Interface
        .ext_read_mode(out_mgr_ext_read_mode),
        .ext_read_addr_flat(out_mgr_ext_read_addr_flat),
        .bram_read_data_flat(out_mgr_bram_read_data_flat),
        
        // AXI Stream Master
        .m_axis_tdata(m_output_axis_tdata),
        .m_axis_tvalid(m_output_axis_tvalid),
        .m_axis_tready(m_output_axis_tready),
        .m_axis_tlast(m_output_axis_tlast),
        
        // Status
        .state_debug(),
        .transmission_active()
    );

    // Read Back Mapping (For Debug/External Read)
    assign weight_rd_data_flat = bram_read_data_flat[127:0];
    assign ifmap_rd_data_flat = bram_read_data_flat[255:128];

endmodule