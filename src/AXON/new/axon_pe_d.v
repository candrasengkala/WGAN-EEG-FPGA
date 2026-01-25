module axon_pe_d #(
    parameter DATA_WIDTH = 16
)(
    input  wire                   clk,
    input  wire                   rst_n,
    
    // New Input Mux Signals
    input  wire [DATA_WIDTH-1:0]  ifmap_in_nbr,
    input  wire [DATA_WIDTH-1:0]  ifmap_in_sram,
    
    // Other Data Inputs
    input  wire [DATA_WIDTH-1:0]  weight_in,
    input  wire [DATA_WIDTH-1:0]  output_in, // Labeled 'output' in diagram
    
    // Control Signals
    input  wire                   ifmap_in_sel,
    input  wire                   output_eject_ctrl,
    
    // Data Outputs
    output wire [DATA_WIDTH-1:0]  ifmap_out,
    output wire [DATA_WIDTH-1:0]  weight_out,
    output wire [DATA_WIDTH-1:0]  output_out
);

    // Internal Registers
    reg [DATA_WIDTH-1:0] input_reg;
    reg [DATA_WIDTH-1:0] weight_reg;
    reg [DATA_WIDTH-1:0] psum_reg;
    reg [DATA_WIDTH-1:0] output_reg;

    // Input Mux Logic
    wire [DATA_WIDTH-1:0] selected_ifmap;
    assign selected_ifmap = (ifmap_in_sel) ? ifmap_in_sram : ifmap_in_nbr;

    // MAC Arithmetic Logic
    wire [DATA_WIDTH-1:0] mult_result;
    wire [DATA_WIDTH-1:0] acc_result;

    assign mult_result = input_reg * weight_reg;
    assign acc_result  = mult_result + psum_reg;

    // Sequential Logic Block
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            input_reg  <= {DATA_WIDTH{1'b0}};
            weight_reg <= {DATA_WIDTH{1'b0}};
            psum_reg   <= {DATA_WIDTH{1'b0}};
            output_reg <= {DATA_WIDTH{1'b0}};
        end else begin
            // 1. Buffer the selected input and weight_in
            input_reg  <= selected_ifmap;
            weight_reg <= weight_in;

            // 2. Accumulate Psum every cycle (en_psum removed)
            psum_reg   <= acc_result;

            // 3. Output Ejection Mux + Register
            if (output_eject_ctrl) begin
                output_reg <= psum_reg;
            end else begin
                output_reg <= output_in;
            end
        end
    end

    // Forwarding Assignments
    assign ifmap_out  = input_reg;
    assign weight_out = weight_reg;
    assign output_out = output_reg;

endmodule