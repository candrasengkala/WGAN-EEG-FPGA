`timescale 1ns / 1ps

// Generic Counter untuk BRAM Addressing
// Counter yang bisa mulai dari address mana saja dan count sebanyak yang diinginkan

module axis_counter
    (
        input wire         aclk,
        input wire         aresetn,
        
        // *** Control Signals ***
        input wire         counter_enable,    // Enable counter increment
        input wire         counter_start,     // Start/load counter dengan start_addr
        input wire [15:0]  start_addr,        // Alamat awal (misal: 256)
        input wire [15:0]  count_limit,       // Jumlah count yang diinginkan (misal: 128)
        
        // *** Output ***
        output reg [15:0]  counter,           // Counter output (address untuk BRAM)
        output wire        counter_done       // Done signal (sudah count sebanyak count_limit)
    );

    // Internal register untuk tracking berapa kali sudah count
    reg [15:0] count_reg;
    
    // ============================================================================
    // Counter Logic
    // ============================================================================
    // Counter generic yang bisa mulai dari address mana saja dan count sebanyak yang diinginkan
    // 
    // Cara kerja:
    // 1. Set start_addr dan count_limit dari FSM top
    // 2. Berikan pulse counter_start untuk load start_addr ke counter
    // 3. Setiap counter_enable=1, counter akan increment
    // 4. Setelah count sebanyak count_limit, counter_done akan HIGH
    //
    // Contoh:
    // - start_addr = 256, count_limit = 128
    // - Counter akan count dari 256, 257, 258, ..., 383 (total 128 count)
    // - Setelah 128 count, counter_done = 1
    
    always @(posedge aclk)
    begin
        if (!aresetn)
        begin
            counter <= 16'b0;
            count_reg <= 16'b0;
        end
        else if (counter_start)
        begin
            // Load start address dan reset count register
            counter <= start_addr;
            count_reg <= 16'b0;
        end
        else if (counter_enable)
        begin
            // Increment counter dan count register
            counter <= counter + 1;
            count_reg <= count_reg + 1;
        end
    end
    
    // Done signal: HIGH ketika sudah count sebanyak count_limit
    // Check apakah NEXT count akan >= limit (karena counter increment di clock berikutnya)
    assign counter_done = (count_reg >= count_limit) && (count_limit != 0);

endmodule