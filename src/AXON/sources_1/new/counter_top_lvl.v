// Description: counter_top_lvl digunakan untuk menghitung waktu propagasi sehingga semua terisi. 
module counter_top_lvl #(
    parameter Dimension = 16
)(
    input  wire clk,
    input  wire rst,     // active-low reset (matches your style)
    input  wire en,
    output reg  done
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
            if (cnt == (2*Dimension)) begin
                done <= 1'b1;   // raise done
                cnt  <= cnt;    // stop counting
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
