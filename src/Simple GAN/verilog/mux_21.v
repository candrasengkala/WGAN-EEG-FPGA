module mux_2_to_1 #(
    parameter MXwidth = 32
)
(
    input wire [MXwidth -1 : 0] A,
    input wire [MXwidth -1 : 0] B,
    input wire selector,
    output reg [MXwidth -1 : 0] D
);

    // Logika kombinasional
    always@(*)begin
        case(selector)
            1'b1: D = B; //B jika selector = 1
            1'b0: D = A; //A jika selector = 0
            default: D = A;
        endcase
    end
    
endmodule
