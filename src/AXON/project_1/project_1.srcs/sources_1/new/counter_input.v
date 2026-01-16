// Deskripsi: menghitung sampai semua input dikeluarkan dari shift register. 
module counter_input #(
    parameter Dimension_added = 17
)(
    input  wire clk,
    input  wire rst,     // active-low reset (matches your style)
    input  wire en,
    output reg  done
    // Hitung sebanyak Dimension_added (waktu yang diperlukan untuk propagasi dari atas banget ke bawah). Done signal
    // Made high on one clock cycle.       
);

    // counter width: enough bits for 2*Dimension_added_added
    localparam CNT_W = $clog2(Dimension_added);
    reg [CNT_W-1:0] cnt = 0;

    always @(posedge clk) begin
        if (!rst) begin
            cnt  <= {CNT_W{1'b0}};
            done <= 1'b0;
        end
        else if (en) begin
            if (cnt == (Dimension_added - 1)) begin
                done <= 1'b1;   // raise done
                cnt  <= 0;      // stop counting // Recount.
            end
            else begin
                cnt  <= cnt + 1'b1;
                done <= 1'b0;
            end
        end
        else begin
            done <= 1'b0;
        end
    end

endmodule
