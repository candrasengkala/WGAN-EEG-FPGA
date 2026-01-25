`timescale 1ns / 1ps

/******************************************************************************
 * Module: mux_3to1_array_flat
 * * Description:
 * Multiplexer 3-to-1 untuk array sinyal yang di-flatten.
 * Digunakan untuk arbitrase Write Port BRAM (Accumulation vs Bias Load vs Convolution).
 * * Inputs:
 * - in0_flat: Input 0 (Default, e.g., Accumulation Unit)
 * - in1_flat: Input 1 (e.g., Bias Loading / AXI)
 * - in2_flat: Input 2 (e.g., Standard Convolution)
 * * Parameters:
 * - NUM_ELEMENTS: Jumlah elemen (misal: 16 BRAM)
 * - DATA_WIDTH:   Lebar data per elemen (misal: 16 bit untuk data, 10 bit untuk addr)
 * * Author: Dharma Anargya Jowandy
 ******************************************************************************/

module mux_3to1_array_flat #(
    parameter NUM_ELEMENTS = 16,
    parameter DATA_WIDTH   = 16
)(
    input  wire [1:0] sel, // 00=In0, 01=In1, 10=In2
    
    // Flattened Inputs
    input  wire [NUM_ELEMENTS*DATA_WIDTH-1:0] in0_flat,
    input  wire [NUM_ELEMENTS*DATA_WIDTH-1:0] in1_flat,
    input  wire [NUM_ELEMENTS*DATA_WIDTH-1:0] in2_flat,
    
    // Flattened Output
    output wire [NUM_ELEMENTS*DATA_WIDTH-1:0] out_flat
);

    // Array internal untuk unflattening (memudahkan debugging di waveform)
    wire [DATA_WIDTH-1:0] in0_arr [0:NUM_ELEMENTS-1];
    wire [DATA_WIDTH-1:0] in1_arr [0:NUM_ELEMENTS-1];
    wire [DATA_WIDTH-1:0] in2_arr [0:NUM_ELEMENTS-1];
    wire [DATA_WIDTH-1:0] out_arr [0:NUM_ELEMENTS-1];

    genvar i;
    generate
        for (i = 0; i < NUM_ELEMENTS; i = i + 1) begin : MUX_ARRAY
            // 1. Unpack / Unflatten
            assign in0_arr[i] = in0_flat[i*DATA_WIDTH +: DATA_WIDTH];
            assign in1_arr[i] = in1_flat[i*DATA_WIDTH +: DATA_WIDTH];
            assign in2_arr[i] = in2_flat[i*DATA_WIDTH +: DATA_WIDTH];
            
            // 2. Multiplexing Logic
            // Menggunakan assign conditional agar sintetis menjadi LUT/MUX efisien
            assign out_arr[i] = (sel == 2'd0) ? in0_arr[i] :
                                (sel == 2'd1) ? in1_arr[i] :
                                (sel == 2'd2) ? in2_arr[i] :
                                {DATA_WIDTH{1'b0}}; // Default case (sel=3) -> 0
            
            // 3. Pack / Flatten Output
            assign out_flat[i*DATA_WIDTH +: DATA_WIDTH] = out_arr[i];
        end
    endgenerate

endmodule