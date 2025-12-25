module mux_3_to_1 #(
    parameter MXwidth = 32
)
(
    input wire [MXwidth -1 : 0] A,
    input wire [MXwidth -1 : 0] B,
    input wire [MXwidth -1 : 0] C,
    input wire [1:0] selector,
    output reg [MXwidth -1 : 0] D
);

    // Logika kombinasional
    always@(*)begin
        case(selector)
            2'b00: D = A; //A jika selector = 00
            2'b01: D = B; //B jika selector = 01
            2'b10: D = C; //C jika selector = 10
            default: D = A;
        endcase
    end
    
endmodule
