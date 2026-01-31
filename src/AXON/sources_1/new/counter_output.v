// Deskripsi: menghitung sampai semua output dikeluarkan. 
module counter_output #(
    parameter Dimension = 16
)(
    input  wire clk,
    input  wire rst,     // active-low reset (matches your style)
    input  wire en,
    output reg  done
    // Hitung sebanyak dimension (waktu yang diperlukan untuk propagasi dari atas banget ke bawah). Done signal
    // Made high on one clock cycle.       
);

    // counter width: enough bits for 2*Dimension
    localparam CNT_W = $clog2(2*Dimension + 1);
    reg [CNT_W-1:0] cnt = 0;

    always @(posedge clk) begin
        if (!rst) begin
            cnt  <= {CNT_W{1'b0}};
            done <= 1'b0;
        end
        else if (en) begin
            if (cnt == (Dimension)) begin
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
