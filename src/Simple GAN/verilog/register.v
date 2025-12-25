module register #(
    parameter Xwidth = 32
)
(
    input wire clk,
    input wire reset,
    input wire enable,
    input wire [Xwidth -1 : 0] data_in,
    output reg [Xwidth -1 : 0] data_out
);

    // Register logic
    always@(posedge clk or posedge reset)begin
        if(reset)begin
            data_out <= {Xwidth{1'b0}}; // Reset ke 0
        end else if(enable)begin
            data_out <= data_in; // Simpan data
        end
    end
    
endmodule
