`timescale 1ns/1ps

module counter_axon_addr_weight #(
    parameter ADDRESS_LENGTH = 13
)(
    input  wire clk,
    input  wire rst,         // active-low reset
    input  wire rst_min_16,  // go to previous 16-block
    input  wire en,

    input  wire [ADDRESS_LENGTH-1:0] start_val, // BEGIN value
    input  wire [ADDRESS_LENGTH-1:0] end_val,   // END value (inclusive)

    output reg  flag_1per16,   // every 16 counts (pulse)
    output reg  [ADDRESS_LENGTH-1:0] addr_out,
    output reg  done
);

    reg [ADDRESS_LENGTH-1:0] count;
    reg reached_end;

    always @(negedge clk) begin
        if (!rst) begin
            count        <= start_val;
            addr_out     <= start_val;
            done         <= 1'b0;
            flag_1per16  <= 1'b0;
            reached_end  <= 1'b0;
        end
        else begin
            // default pulses low
            done        <= 1'b0;
            flag_1per16 <= 1'b0;

            // ------------------------------------------------
            // GO TO PREVIOUS 16-BLOCK
            // ------------------------------------------------
            if (rst_min_16) begin
                if (count >= (start_val + 16))
                    count <= count - 16;
                else
                    count <= start_val;

                addr_out    <= (count >= (start_val + 16)) ? (count - 16)
                                                           : start_val;
                reached_end <= 1'b0;   // allow counting again
            end

            // ------------------------------------------------
            // NORMAL COUNTING
            // ------------------------------------------------
            else if (en && !reached_end) begin
                addr_out <= count;

                // every-16 pulse (absolute)
                if ((count & 4'b1111) == 4'b1111)
                    flag_1per16 <= 1'b1;

                if (count == end_val) begin
                    done        <= 1'b1;
                    reached_end <= 1'b1;
                end
                else begin
                    count <= count + 1'b1;
                end
            end

            // ------------------------------------------------
            // HOLD
            // ------------------------------------------------
            else begin
                addr_out <= count;
            end
        end
    end

endmodule
