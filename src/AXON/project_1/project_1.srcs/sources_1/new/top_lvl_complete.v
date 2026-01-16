module top_lvl_io_control #( // Tanpa FSM untuk memasukkan data ke shift register.
    parameter DW = 16,
    parameter Dimension = 16
)
(
    input wire clk,
    input wire rst,
    input wire start,
    input wire output_val,

    input  wire signed [DW-1:0] weight_serial_in,       //Serial Inputs 
    input  wire signed [DW-1:0] ifmap_serial_in,        //Serial Inputs
    input  wire en_shift_reg_ifmap_input, // Start signal to begin shiftin
    input  wire en_shift_reg_weight_input,
    
    output wire out_new_val, // From counter
    output wire done_count,
    output wire done_all,


    output wire signed [DW*Dimension-1:0] output_out    // Output Value
);
    wire en_cntr;

    top_lvl_with_mem #(
        .DW(DW),
        .Dimension(Dimension)
    ) top_lvl_with_mem_inst (
        .clk                    (clk),
        .rst                    (rst),

        .en_shift_reg_ifmap     (), // Start signal to begin shifting
        .en_shift_reg_weight    (),

        .en_cntr                (1'b1), // Always enable counting when shifting is happening
        .en_in                  (), // Always enable inputs
        .en_out                 (), // Always enable outputs
        .en_psum                (), // Always enable psum registers

        .ifmaps_sel             (), // Always select all ifmaps
        .output_eject_ctrl      (), // Always eject all outputs

        .weight_serial_in       (),
        .ifmap_serial_in        (),

        .output_val_count       (),
        .out_new_val            (),

        .done_ifmap             (), // Not used here
        .done_weight            (), // Not used here

        .done_count             (),
        .output_out             ()
    );
    matrix_mult_control #(
        .DW(DW),
        .Dimension(Dimension)
    ) matrix_mult_control_inst (
        .clk                    (clk),
        .rst                    (rst),
        .start                  (start),

        .done_ifmap             (), // Not used here
        .done_weight            (), // Not used here

        .done_count             (),
        .output_val             (),
        .out_new_val            (),

        .en_shift_reg_ifmap     (), // Not used here
        .en_shift_reg_weight    (), // Not used here

        .en_cntr                (), // Not used here
        .en_in                  (), // Not used here
        .en_out                 (), // Not used here
        .en_psum                (), // Not used here

        .ifmaps_sel             (), // Not used here
        .output_val_count       (), // Not used here
        .output_eject_ctrl      ()  // Not used here
    );
endmodule

module top_lvl_with_mem
#(
    parameter DW        = 16,
    parameter Dimension = 16
)
(
    input  wire clk,
    input  wire rst,
    /* ---------------- Control Shift Register---------------- */
    input wire en_shift_reg_ifmap,                      // Input From Controller
    input wire en_shift_reg_weight,                     // Input From Controller
    /* ---------------- Control Systolic Array---------------- */
    input  wire en_cntr,                                // Input From Controller
    input  wire [Dimension*Dimension-1:0] en_in,        // Input From Controller
    input  wire [Dimension*Dimension-1:0] en_out,       // Input From Controller
    input  wire [Dimension*Dimension-1:0] en_psum,      // Input From Controller
    input  wire [Dimension-1:0] ifmaps_sel,             // Input From Controller
    input  wire [Dimension-1:0] output_eject_ctrl,      // Input From Controller
    /* ------------- Serial Inputs ------------- */
    input  wire signed [DW-1:0] weight_serial_in,       //Serial Inputs 
    input  wire signed [DW-1:0] ifmap_serial_in,        //Serial Inputs
    /* ------------- Output Control ------------- */
    input wire output_val_count,                        // Signal from controller
    output wire out_new_val,                            // Signal to controller that a new output value is available.
    /* ---------------- Outputs Dones (Inputs)---------------- */
    output wire done_ifmap,                             // To Controller
    output wire done_weight,                            // To Controller
    /* ---------------- Outputs Systolic Array---------------- */
    output wire done_count,                             // To Controller and External
    output wire signed [DW*Dimension-1:0] output_out    // Output Value
);
    wire neg_clk = ~clk;
    /* ============================================================
     * Input counter and output counters.
     * ============================================================ */
    // For the sake of good practice, do make counters only recieve inputs from control logic, except necassary
    generate
        counter_input #(.Dimension_added(Dimension + 1)) counter_ifmap_inst ( //Count sampai Dimension + 1;
            .clk(neg_clk),
            .rst(rst),
            .en(en_shift_reg_ifmap), // Digunakan untuk menghitung shifting.
            .done(done_ifmap)
        );
        counter_input #(.Dimension_added(Dimension + 1)) counter_weight_inst (
            .clk(neg_clk),
            .rst(rst),
            .en(en_shift_reg_weight),
            .done(done_weight)
        );
        counter_output #(.Dimension(Dimension)) counter_output_inst (
            .clk(clk),
            .rst(rst),
            .en(output_val_count), // 
            .done(out_new_val)
        );
    endgenerate
    /* ============================================================
     * Shift registers for weights and ifmaps
     * ============================================================ */
    wire signed [DW-1:0] weight_sr [0:Dimension-1];
    wire signed [DW-1:0] ifmap_sr  [0:Dimension-1];
    genvar i;
    generate
        for (i = 0; i < Dimension; i = i + 1) begin : INPUT_SHIFT_REGS
            /* ---- Weight shift register ---- */
            shift_reg_input #(
                .DW(DW),
                .Depth_added(Dimension + 1) // Added depth for zero padding. For first shifting, fill it with zero (Logic developed later)
            ) weight_shift (
                .clk   (neg_clk),
                .rst   (rst),
                .clken (en_shift_reg_weight),
                .SI    (weight_serial_in),
                .SO    (weight_sr[i])
            );
            /* ---- IFMAP shift register ---- */
            shift_reg_input #(
                .DW(DW),
                .Depth_added(Dimension + 1)
            ) ifmap_shift (
                .clk   (clk), // Sesuai dengan yang mengeluarkannya
                .rst   (rst),
                .clken (en_shift_reg_ifmap),
                .SI    (ifmap_serial_in),
                .SO    (ifmap_sr[i])
            );
        end
    endgenerate
    /* ============================================================
     * Flatten for top_lvl
     * ============================================================ */
    wire signed [DW*Dimension-1:0] weight_flat;
    wire signed [DW*Dimension-1:0] ifmap_flat;
    generate
        for (i = 0; i < Dimension; i = i + 1) begin : FLATTEN_INPUTS
            assign weight_flat[(i+1)*DW-1 -: DW] = weight_sr[i];
            assign ifmap_flat [(i+1)*DW-1 -: DW] = ifmap_sr[i];
        end
    endgenerate 
    /* ============================================================
     * AXON's top_lvl
     * ============================================================ */
    top_lvl #(
        .DW(DW),
        .Dimension(Dimension)
    ) dut (
        .clk                (clk),
        .rst                (rst),

        .en_cntr            (en_cntr),
        .en_in              (en_in),
        .en_out             (en_out),
        .en_psum            (en_psum),

        .ifmaps_sel         (ifmaps_sel),
        .output_eject_ctrl  (output_eject_ctrl),

        .weight_in          (weight_flat),
        .ifmap_in           (ifmap_flat),

        .done_count         (done_count), //Raised if all counting have been done.
        .output_out         (output_out)
    );

endmodule
