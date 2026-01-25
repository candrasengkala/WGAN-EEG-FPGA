module axon_pe_h #(
    parameter DATA_WIDTH = 16
)(
    input  wire                   clk,
    input  wire                   rst_n,      // Active low reset
    
    // Data Inputs
    input  wire [DATA_WIDTH-1:0]  ifmap_in,
    input  wire [DATA_WIDTH-1:0]  weight_in,
    input  wire [DATA_WIDTH-1:0]  output_in, // Labeled 'output' in diagram
    
    // Control Signals
    input  wire                   output_eject_ctrl,
    
    // Data Outputs
    output wire [DATA_WIDTH-1:0]  ifmap_out,
    output wire [DATA_WIDTH-1:0]  weight_out,
    output wire [DATA_WIDTH-1:0]  output_out
);

    // Internal Registers (The squares in your diagram)
    reg [DATA_WIDTH-1:0] input_reg;
    reg [DATA_WIDTH-1:0] weight_reg;
    reg [DATA_WIDTH-1:0] psum_reg;
    reg [DATA_WIDTH-1:0] output_reg;

    // Combinational logic for MAC
    wire [DATA_WIDTH-1:0] mult_result;
    wire [DATA_WIDTH-1:0] acc_result;

    assign mult_result = input_reg * weight_reg;
    assign acc_result  = mult_result + psum_reg;

    // Sequential Logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin // Low Active Reset.
            input_reg  <= {DATA_WIDTH{1'b0}};
            weight_reg <= {DATA_WIDTH{1'b0}};
            psum_reg   <= {DATA_WIDTH{1'b0}};
            output_reg <= {DATA_WIDTH{1'b0}};
        end else begin
            // Input and weight_in buffering
            input_reg  <= ifmap_in;
            weight_reg <= weight_in;

            // Partial Sum accumulation (controlled by en_psum)
            psum_reg <= acc_result;

            // Output Ejection MUX and Register
            // If ctrl is high, eject local Psum; else pass through external output
            if (output_eject_ctrl) begin
                output_reg <= psum_reg;
            end else begin
                output_reg <= output_in;
            end
        end
    end

    // Direct forwarding / Output assignments
    assign ifmap_out  = input_reg;
    assign weight_out = weight_reg;
    assign output_out = output_reg;

endmodule