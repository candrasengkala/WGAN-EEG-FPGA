module dmux_1_to_2 #(
    parameter MXwidth = 32
)
(
    input wire [MXwidth -1 : 0] D,
    input wire selector,
    output reg [MXwidth -1 : 0] Y0,
    output reg [MXwidth -1 : 0] Y1
);

    // Logika kombinasional (kebalikan dari mux 2:1)
    always@(*)begin
        case(selector)
            1'b0: begin
                Y0 = D; // ke Y0 jika selector = 0
                Y1 = {MXwidth{1'b0}};
            end
            1'b1: begin
                Y0 = {MXwidth{1'b0}};
                Y1 = D; // ke Y1 jika selector = 1
            end
            default: begin
                Y0 = {MXwidth{1'b0}};
                Y1 = {MXwidth{1'b0}};
            end
        endcase
    end
    
endmodule
