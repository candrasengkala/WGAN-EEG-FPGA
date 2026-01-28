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
    
    // NEW: AXI Stream Master for Output Results (to PS via DMA S2MM)
    output wire [DW-1:0] m_output_axis_tdata,
    output wire m_output_axis_tvalid,
    input wire m_output_axis_tready,
    output wire m_output_axis_tlast,
    
    // Status Outputs (Tetap sama)
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

    // Internal Wires
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
    
    // Read Back Wires
    wire [NUM_BRAMS*DW-1:0] bram_read_data_flat;
    wire [NUM_BRAMS*ADDR_WIDTH-1:0] bram_read_addr_flat;


    // ========================================================================
    // Auto-start edge detection logic
    // ========================================================================
    reg weight_write_done_prev, ifmap_write_done_prev;
    wire weight_done_posedge = weight_write_done & ~weight_write_done_prev;
    wire ifmap_done_posedge = ifmap_write_done & ~ifmap_write_done_prev;
    reg ifmap_loaded, weight_loaded;
    
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            weight_write_done_prev <= 1'b0;
            ifmap_write_done_prev <= 1'b0;
            ifmap_loaded <= 1'b0;
            weight_loaded <= 1'b0;
        end else begin
            weight_write_done_prev <= weight_write_done;
            ifmap_write_done_prev <= ifmap_write_done;
            
            if (ifmap_done_posedge)
                ifmap_loaded <= 1'b1;
            if (weight_done_posedge)
                weight_loaded <= 1'b1;
                
            // Clear flags when batch starts
            if (batch_state == BATCH_IDLE && batch_next_state == BATCH_RUNNING) begin
                ifmap_loaded <= 1'b0;
                weight_loaded <= 1'b0;
            end
        end
    end
    // ========================================================================
    // MULTI-BATCH CONTROL STATE MACHINE (untuk 8 weight loads)
    // ========================================================================
    localparam [2:0]
        BATCH_IDLE         = 3'd0,
        BATCH_WAIT_INITIAL = 3'd1,
        BATCH_RUNNING      = 3'd2,
        BATCH_WAIT_RELOAD  = 3'd3,
        BATCH_ALL_DONE     = 3'd4;
    
    reg [2:0] batch_state, batch_next_state;
    reg [2:0] batch_counter;  // 0-7 (8 batches untuk 32 tiles)
    reg batch_auto_start;     // Internal start signal untuk scheduler
    wire batch_complete;      // From scheduler
    
    // Batch state transition
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            batch_state <= BATCH_IDLE;
            batch_counter <= 3'd0;
            batch_auto_start <= 1'b0;
        end else begin
            batch_state <= batch_next_state;
            
            // Clear start pulse after 1 cycle
            if (batch_auto_start)
                batch_auto_start <= 1'b0;
            
            // Increment batch counter when batch completes
            if (batch_complete && batch_state == BATCH_RUNNING) begin
                if (batch_counter < 3'd7)
                    batch_counter <= batch_counter + 3'd1;
                else
                    batch_counter <= 3'd0;  // Reset for next full cycle
            end
            
            // Reset counter on idle
            if (batch_state == BATCH_IDLE)
                batch_counter <= 3'd0;
        end
    end
    
    // Batch state logic
    always @(*) begin
        batch_next_state = batch_state;
        
        case (batch_state)
            BATCH_IDLE: begin
                // Wait for BOTH ifmap and weight loaded initially
                if (ifmap_loaded && weight_loaded)
                    batch_next_state = BATCH_RUNNING;
            end
            
            BATCH_RUNNING: begin
                // When scheduler signals batch complete
                if (batch_complete) begin
                    if (batch_counter < 3'd7)
                        batch_next_state = BATCH_WAIT_RELOAD;  // Need more weight
                    else
                        batch_next_state = BATCH_ALL_DONE;     // All 8 batches done!
                end
            end
            
            BATCH_WAIT_RELOAD: begin
                // Wait for new weight data
                if (weight_done_posedge)
                    batch_next_state = BATCH_RUNNING;
            end
            
            BATCH_ALL_DONE: begin
                // Stay here or go back to IDLE based on external control
                batch_next_state = BATCH_IDLE;
            end
            
            default: batch_next_state = BATCH_IDLE;
        endcase
    end
    
    // Generate start pulse for scheduler
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            batch_auto_start <= 1'b0;
        end else begin
            // Start scheduler when:
            // 1. Initial data loaded (IDLE → RUNNING)
            // 2. New weight loaded (WAIT_RELOAD → RUNNING)
            if ((batch_state == BATCH_IDLE && batch_next_state == BATCH_RUNNING) ||
                (batch_state == BATCH_WAIT_RELOAD && batch_next_state == BATCH_RUNNING)) begin
                batch_auto_start <= 1'b1;
            end else begin
                batch_auto_start <= 1'b0;
            end
        end
    end
    
    // Combined start signal (external manual start OR batch auto-start)
    wire scheduler_start_combined = scheduler_start | batch_auto_start;
    
    // Status outputs
    assign auto_start_active = (batch_state == BATCH_RUNNING);
    assign data_load_ready = (batch_state == BATCH_WAIT_RELOAD) ? 1'b0 : (ifmap_loaded | weight_loaded);

    // --- INSTANTIATION 1: WEIGHT WRAPPER ---
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

    // --- INSTANTIATION 2: IFMAP WRAPPER ---
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

    // --- INSTANTIATION 3: SCHEDULER ---
    // --- INSTANTIATION 3: SCHEDULER (MULTI-BATCH VERSION) ---
    Scheduler_FSM #(
        .ADDR_WIDTH(ADDR_WIDTH)
    ) scheduler_inst (
        .clk(aclk), 
        .rst_n(aresetn), 
        .start(scheduler_start_combined),
        
        // NEW: Batch control
        .current_batch_id(batch_counter),
        .batch_complete(batch_complete),
        
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
        
        .done(scheduler_done)
    );

    // --- INSTANTIATION 4: COMPUTE ENGINE (SUPER TOP LEVEL) ---
    Super_TOP_Level #(
        .DW(DW), .NUM_BRAMS(NUM_BRAMS), .ADDR_WIDTH(ADDR_WIDTH), .Dimension(Dimension)
    ) compute_engine (
        .clk(aclk), .rst_n(aresetn),
        // Koneksikan Control Signals dari Scheduler
        .if_addr_start(if_addr_start), .if_addr_end(if_addr_end), .ifmap_sel_in(ifmap_sel_in), .start_ifmap(start_ifmap), .if_done(if_done),
        .addr_start(addr_start), .addr_end(addr_end), .start_weight(start_weight), .done_weight(done_weight),
        
        // *** BAGIAN PENTING: Koneksikan Sinyal Write dari AXI Wrapper ***
        .w_we(weight_wr_en), 
        .w_addr_wr_flat({NUM_BRAMS{weight_wr_addr}}), 
        .w_din_flat(weight_wr_data_flat),
        
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
    // Output Stream Manager Instantiation
    // ========================================================================
    output_stream_manager #(
        .DW(DW),
        .NUM_BRAMS(NUM_BRAMS),
        .ADDR_WIDTH(ADDR_WIDTH),
        .OUTPUT_DEPTH(512)
    ) output_mgr_inst (
        .clk(aclk),
        .rst_n(aresetn),
        
        // Triggers from batch controller (ADD THESE SIGNALS TO BATCH FSM)
        .batch_complete(batch_complete),
        .completed_batch_id(batch_counter),
        .all_batches_complete(batch_state == BATCH_ALL_DONE),
        
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
    

    // Read Back Mapping
    assign weight_rd_data_flat = bram_read_data_flat[127:0];
    assign ifmap_rd_data_flat = bram_read_data_flat[255:128];

    // *** HAPUS SEMUA INSTANSIASI GANDA DI BAWAH SINI (Weight_BRAM_Top, Transpose_top, dll) ***
    // Modul-modul itu SUDAH ADA di dalam Super_TOP_Level (compute_engine).
    // Jangan dipanggil lagi di sini.

endmodule