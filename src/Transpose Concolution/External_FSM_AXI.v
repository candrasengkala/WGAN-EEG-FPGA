module External_FSM_AXI(
    input wire aclk, //clock
    input wire aresetn, //Reset
    input wire [7:0] Instruction_code,  // Instruksi dari software (decode di FSM atas)
    
    // Parameter untuk WRITE (dari FSM atas / instruction decoder)
    input wire [4:0] wr_bram_start,     // BRAM awal untuk write (0-31)
    input wire [4:0] wr_bram_end,       // BRAM akhir untuk write (0-31)
    input wire [15:0] wr_addr_start,    // Address awal untuk write
    input wire [15:0] wr_addr_count,    // Jumlah word per BRAM
    
    // Parameter untuk READ (dari FSM atas / instruction decoder)
    input wire [3:0] rd_bram_start,     // BRAM awal untuk read (0-15)
    input wire [3:0] rd_bram_end,       // BRAM akhir untuk read (0-15)
    input wire [15:0] rd_addr_start,    // Address awal untuk read
    input wire [15:0] rd_addr_count,    // Jumlah word per BRAM

    input wire bram_wr_enable,          // flag dari parser (untuk WRITE)

    input wire wr_counter_done,         //flag dari write counter
    input wire rd_counter_done,         // flag dari read counter

    output reg wr_counter_enable,       //enable write counter (setiap kali enambel maka counter increment 1)
    output reg wr_counter_start,        //start write counter (load start address)
    output reg [15:0] wr_start_addr,    //alamat awal sebagai initial value counter
    output reg [15:0] wr_count_limit,   //jumlah count yang diinginkan

    output reg rd_counter_enable,       //enable read counter (setiap kali enambel maka counter increment 1)
    output reg rd_counter_start,        //start read counter (load start address)
    output reg [15:0] rd_start_addr,    //alamat awal sebagai initial value counter
    output reg [15:0] rd_count_limit,   //jumlah count yang diinginkan

    output reg [4:0] demux_sel,         //selector demux 1 to 32
    output reg [3:0] mux_sel,           //selector mux 16 to 1
    output reg bram_rd_enable           //trigger packer untuk READ (output!)

);

    localparam [2:0]
        IDLE            = 3'd0,
        WRITE_SETUP     = 3'd1,
        WRITE_WAIT      = 3'd2,
        READ_SETUP      = 3'd3,
        READ_WAIT       = 3'd4,
        DONE            = 3'd5;
    
    reg [2:0] current_state, next_state;
    reg [4:0] bram_write_index;  // Current BRAM untuk write
    reg [3:0] bram_read_index;   // Current BRAM untuk read
    
    // Latch parameter saat mulai operasi (dari input)
    reg [4:0] wr_bram_start_reg, wr_bram_end_reg;
    reg [15:0] wr_addr_start_reg, wr_addr_count_reg;
    reg [3:0] rd_bram_start_reg, rd_bram_end_reg;
    reg [15:0] rd_addr_start_reg, rd_addr_count_reg;

    // State register
    always @(posedge aclk) begin
        if (!aresetn) begin
            current_state <= IDLE;
            bram_write_index <= 5'd0;
            bram_read_index <= 4'd0;
            wr_bram_start_reg <= 5'd0;
            wr_bram_end_reg <= 5'd0;
            wr_addr_start_reg <= 16'd0;
            wr_addr_count_reg <= 16'd0;
            rd_bram_start_reg <= 4'd0;
            rd_bram_end_reg <= 4'd0;
            rd_addr_start_reg <= 16'd0;
            rd_addr_count_reg <= 16'd0;
        end
        else begin
            current_state <= next_state;
            
            // Latch parameter saat IDLE jika ada instruksi WRITE
            if (current_state == IDLE && Instruction_code == 8'h01) begin
                wr_bram_start_reg <= wr_bram_start;
                wr_bram_end_reg <= wr_bram_end;
                wr_addr_start_reg <= wr_addr_start;
                wr_addr_count_reg <= wr_addr_count;
                bram_write_index <= wr_bram_start;  // Init ke start
            end
            
            // Latch parameter saat IDLE jika ada instruksi READ
            if (current_state == IDLE && Instruction_code == 8'h02) begin
                rd_bram_start_reg <= rd_bram_start;
                rd_bram_end_reg <= rd_bram_end;
                rd_addr_start_reg <= rd_addr_start;
                rd_addr_count_reg <= rd_addr_count;
                bram_read_index <= rd_bram_start;  // Init ke start
            end
            
            // Increment write index setelah satu BRAM selesai
            if (current_state == WRITE_WAIT && wr_counter_done) begin
                if (bram_write_index < wr_bram_end_reg)
                    bram_write_index <= bram_write_index + 1;
            end
            
            // Increment read index setelah satu BRAM selesai
            if (current_state == READ_WAIT && rd_counter_done) begin
                if (bram_read_index < rd_bram_end_reg)
                    bram_read_index <= bram_read_index + 1;
            end
        end
    end

    always @(*) begin
        next_state = current_state;
        wr_counter_enable = 1'b0;
        wr_counter_start = 1'b0;
        wr_start_addr = 16'b0;
        wr_count_limit = 16'b0;
        rd_counter_enable = 1'b0;
        rd_counter_start = 1'b0;
        rd_start_addr = 16'b0;
        rd_count_limit = 16'b0;
        demux_sel = 5'b0;
        mux_sel = 4'b0;
        bram_rd_enable = 1'b0;  // Default OFF

        case (current_state)
            IDLE: begin
                if (Instruction_code == 8'h01) begin
                    next_state = WRITE_SETUP;  // Mode write
                end
                else if (Instruction_code == 8'h02) begin
                    next_state = READ_SETUP;   // Mode read
                end
            end

            WRITE_SETUP: begin 
                wr_counter_start = 1'b1;
                wr_start_addr = wr_addr_start_reg;     // Dari parameter
                wr_count_limit = wr_addr_count_reg;    // Dari parameter
                demux_sel = bram_write_index;
                next_state = WRITE_WAIT;  
            end

            WRITE_WAIT: begin
                demux_sel = bram_write_index;
                
                if (bram_wr_enable) begin
                    wr_counter_enable = 1'b1;
                end
                
                if (wr_counter_done) begin
                    if (bram_write_index < wr_bram_end_reg) begin
                        next_state = WRITE_SETUP;  // Lanjut BRAM berikutnya
                    end
                    else begin
                        next_state = DONE;  // Selesai range BRAM
                    end
                end
            end

            READ_SETUP: begin 
                rd_counter_start = 1'b1;
                rd_start_addr = rd_addr_start_reg;     // Dari parameter
                rd_count_limit = rd_addr_count_reg;    // Dari parameter
                mux_sel = bram_read_index;
                next_state = READ_WAIT;
            end

            READ_WAIT: begin
                mux_sel = bram_read_index;
                bram_rd_enable = 1'b1;
                rd_counter_enable = 1'b1;

                if (rd_counter_done) begin 
                    if (bram_read_index < rd_bram_end_reg) begin
                        next_state = READ_SETUP;  // Lanjut BRAM berikutnya
                    end
                    else begin
                        next_state = DONE;  // Selesai range BRAM
                    end
                end
            end

            DONE: begin
                next_state = IDLE;  // Kembali ke IDLE setelah selesai
            end
        endcase
    end

endmodule