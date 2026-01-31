module counter_axon_addr_inputdata #(
    parameter ADDRESS_LENGTH = 13
)(
    input  wire clk,
    input  wire rst,     // active-low reset
    input  wire en,

    input  wire [ADDRESS_LENGTH-1:0] start_val, // BEGIN value
    input  wire [ADDRESS_LENGTH-1:0] end_val,   // END value (inclusive)

    output reg  flag_1per16,   // every 16 counts
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

            if (en && !reached_end) begin
                addr_out <= count;

                // --------------------------------
                // Every-16 periodic pulse
                // --------------------------------
                if (((count-start_val) & 4'b1111) == 4'b1111)
                    flag_1per16 <= 1'b1;

                // --------------------------------
                // Terminal condition
                // --------------------------------
                if (count == end_val) begin
                    done        <= 1'b1;
                    reached_end <= 1'b1;  // STOP HERE
                end
                else begin
                    count <= count + 1'b1;
                end
            end
            if (reached_end) begin
                done <= 1'b1;
            end
            else begin
                // Hold terminal value forever
                addr_out <= count;
            end
        end
    end

endmodule
