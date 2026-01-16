`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Rizmi Ahmad Raihan
// 
// Create Date: 01/13/2026 02:58:05 PM
// Design Name: 
// Module Name: top_lvl_tb
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

//2 CLOCKS TO REACH PSUM. HOLD INPUTS FOR 2 CYCLES BEFORE SHIFTING.
//3 CLOCKS TO REACH OUTPUT.
//Input -> Psum -> Output. 3 clcoks. One more register, one more clock.
// Testbench ini Y = I x W
module top_lvl_tb(out_0, out_1, out_2, out_3, in_0, in_1, in_2, in_3, w_0, w_1, w_2, w_3);
    // Change data on negative edge. 
    // Parameters
    // Right after input all datas, diagonals are ready but the rest arent. 
    parameter DW = 16;
    parameter Dimension = 4; // Reduced dimension for testbench.
    // Make sure that INITIAL VALUES ARE ZERO for each registers.
    // Inputs
    reg clk;
    reg rst = 1; // Active low reset disabled. 
    reg en_cntr;
    reg [Dimension*Dimension-1 : 0] en_in = 1;
    reg [Dimension*Dimension-1 : 0] en_out = 0;
    reg [Dimension*Dimension-1 : 0] en_psum = 0;
    reg [Dimension-1:0] ifmaps_sel = {Dimension{1'b0}};
    reg [Dimension-1:0] output_eject_ctrl = {Dimension{1'b0}};
    reg signed [DW*Dimension - 1:0] weight_in = {DW*Dimension{1'b0}};
    reg signed [DW*Dimension - 1:0] ifmap_in = {DW*Dimension{1'b0}};
    
    // Outputs
    wire signed [DW*Dimension -  1:0] output_out;
    wire done_count;
    output wire signed [DW-1:0] out_0, out_1, out_2, out_3, w_0, w_1, w_2, w_3, in_0, in_1, in_2, in_3;
    assign out_0 = output_out[DW*1-1 : DW*0];
    assign out_1 = output_out[DW*2-1 : DW*1];
    assign out_2 = output_out[DW*3-1 : DW*2];
    assign out_3 = output_out[DW*4-1 : DW*3];
    assign w_0 = weight_in[DW*1-1 : DW*0];
    assign w_1 = weight_in[DW*2-1 : DW*1];
    assign w_2 = weight_in[DW*3-1 : DW*2];
    assign w_3 = weight_in[DW*4-1 : DW*3];
    assign in_0 = ifmap_in[DW*1-1 : DW*0];
    assign in_1 = ifmap_in[DW*2-1 : DW*1];
    assign in_2 = ifmap_in[DW*3-1 : DW*2];
    assign in_3 = ifmap_in[DW*4-1 : DW*3];

    // Instantiate the Unit Under Test (UUT)
    top_lvl #(
        .DW(DW),
        .Dimension(Dimension)
    ) uut (
        .clk(clk),
        .rst(rst), // Reset is kept inactive high for this testbench.
        .en_cntr(en_cntr),
        .en_in(en_in), // Always enabled for this testbench
        .en_out(en_out), // Always enabled for this testbench
        .en_psum(en_psum),
        .ifmaps_sel(ifmaps_sel),
        .output_eject_ctrl(output_eject_ctrl),
        .weight_in(weight_in),
        .ifmap_in(ifmap_in),
        .done_count(done_count),
        .output_out(output_out)
    );

    // Clock generation
    initial begin
        clk = 1; // Supaya ada negative edge terlebih dahulu.
        forever #5 clk = ~clk; // 10 time units clock period
    end

    reg [DW-1:0] weight_matrix [0:Dimension-1][0:Dimension-1];
    reg [DW-1:0] ifmap_matrix [0:Dimension-1][0:Dimension-1];
    //1 = BRAM, 0 = Neighbor PE
    // Initialize weight and ifmap matrices
    // Test sequence
    integer row, col;
       // Ini udah dari sebelum posedge. Be careful with this
        // output_selected = output_eject_ctrl ? output_in : psum_reg_out;
        // Initialize Inputs
        // Pecah menjadi beberapa kanal. 
        // Create two 4x4 matrices
    initial begin
        rst = 1'b1;
        en_cntr = 1'b1;
        en_in = {Dimension*Dimension{1'b1}};
        en_out = {Dimension*Dimension{1'b1}};
        en_psum = {Dimension*Dimension{1'b1}};
        ifmaps_sel = {Dimension{1'b1}};
        output_eject_ctrl = {Dimension{1'b1}};
    end

    // Systolic assumes ready data on FIRST POSITIVE EDGE. Make sure that data is okay. 
    // Make a FSM out of this, make sure to have ALL WHEN DATA READY (LOADED, enable SYSTOLIC)
    initial begin
        weight_matrix[0][0] = 16'sd1; weight_matrix[0][1] = 16'sd2; weight_matrix[0][2] = 16'sd3; weight_matrix[0][3] = 16'sd4;
        weight_matrix[1][0] = 16'sd5; weight_matrix[1][1] = 16'sd6; weight_matrix[1][2] = 16'sd7; weight_matrix[1][3] = 16'sd8;
        weight_matrix[2][0] = 16'sd9; weight_matrix[2][1] = 16'sd10; weight_matrix[2][2] = 16'sd11; weight_matrix[2][3] = 16'sd12;
        weight_matrix[3][0] = 16'sd13; weight_matrix[3][1] = 16'sd14; weight_matrix[3][2] = 16'sd15; weight_matrix[3][3] = 16'sd16;
        
        ifmap_matrix[0][0] = 16'sd1; ifmap_matrix[0][1] = 16'sd1; ifmap_matrix[0][2] = -16'sd1; ifmap_matrix[0][3] = 16'sd0;
        ifmap_matrix[1][0] = 16'sd4; ifmap_matrix[1][1] = 16'sd2; ifmap_matrix[1][2] = 16'sd2; ifmap_matrix[1][3] = 16'sd0;
        ifmap_matrix[2][0] = 16'sd5; ifmap_matrix[2][1] = 16'sd1; ifmap_matrix[2][2] = 16'sd0; ifmap_matrix[2][3] = 16'sd0;
        ifmap_matrix[3][0] = 16'sd0; ifmap_matrix[3][1] = 16'sd1; ifmap_matrix[3][2] = 16'sd0; ifmap_matrix[3][3] = -16'sd7;                 

        // wait for clock to be stable
        for (col = Dimension-1; col >= 0; col = col - 1) begin
            @(negedge clk); // Wait for one clock cycle
            ifmap_in  = { ifmap_matrix[3][col],
                        ifmap_matrix[2][col],
                        ifmap_matrix[1][col],
                        ifmap_matrix[0][col] };

            weight_in = { weight_matrix[col][3],
                        weight_matrix[col][2],
                        weight_matrix[col][1],
                        weight_matrix[col][0] };
            // Jauh lebihi mudah, bila sudah selesai, menjadikan semuanya nol supaya nilai gak terus-terusan berubah.
        end
        @(negedge clk);
        ifmap_in = 0;
        weight_in = 0;
    end
    // Output ejection.
    // LSB untuk yang paling atas. 
    integer i;
    // LSB PE yang paling atas
    // MSB    LSB
    // 1 1 1 0
    // 1 1 0 0
    // 1 0 0 0
    // 0 0 0 0
    initial begin
        @(posedge done_count);
        output_eject_ctrl = 4'b1110;
        for (i = 0; i < Dimension; i = i + 1) begin
            repeat (4) @(posedge clk); // Tunggu 4 clock. Implementasikan dengan counter. 
            // 4 CLOCKS ini paling lama. Treat it as is
            // Kalau 16x16 ya 16 clock.
            output_eject_ctrl = output_eject_ctrl << 1;
        end
    end
    // Test if the hypothesis is correct
    // Y = A x B
    // Cara memasukkan matriks A:
    //   0  1  2   3 
    //0 [1  2  3  4] => Masuk ke weight_in dalam weight_in[DW*Dimension-1: DW*(Dimension-1)]
    //1 [5  6  7  8] => Masuk ke weight_in dalam weight_in[(DW)*(Dimension-1)-1: DW*(Dimension-2)]
    //2 [9  10 11 12] => Masuk ke weight_in dalam weight_in[(DW)*(Dimension-2)-1: DW*(Dimension-3)]
    //  ____________
    //3 [13 14 15 16] => Masuk ke weight_in dalam weight_in[(DW)*(Dimension-3)-1: DW*(Dimension-4)]
    // Cara memasukkan matriks B:
    //0 [1 1 1 |1]
    //1 [1 1 1 |1]
    //2 [1 1 1 |1]
    //3 [1 1 1 |1]
    // For testbench, ALWAYS put the loop inside initial block.
endmodule
