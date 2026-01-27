`timescale 1ns / 1ps

/******************************************************************************
 * Module: mux_2to1_array_flat
 * * Description:
 * Multiplexer 2-to-1 generik untuk array sinyal yang di-flatten.
 * Cocok untuk memilih antara 2 sumber (misal: Accumulation vs External Read).
 * * Inputs:
 * - in0_flat: Input 0 (Default, e.g., Accumulation Unit)
 * - in1_flat: Input 1 (e.g., External AXI / Read)
 * * Parameters:
 * - NUM_ELEMENTS: Jumlah elemen (misal: 16 BRAM)
 * - DATA_WIDTH:   Lebar data per elemen (misal: 16 bit data, 10 bit addr, 1 bit enable)
 * * Author: Dharma Anargya Jowandy
 ******************************************************************************/

module mux_2to1_array_flat #(
    parameter NUM_ELEMENTS = 16,
    parameter DATA_WIDTH   = 16
)(
    input  wire sel, // 0=In0, 1=In1
    
    // Flattened Inputs
    input  wire [NUM_ELEMENTS*DATA_WIDTH-1:0] in0_flat,
    input  wire [NUM_ELEMENTS*DATA_WIDTH-1:0] in1_flat,
    
    // Flattened Output
    output wire [NUM_ELEMENTS*DATA_WIDTH-1:0] out_flat
);

    // Array internal untuk unflattening (memudahkan debugging di waveform)
    wire [DATA_WIDTH-1:0] in0_arr [0:NUM_ELEMENTS-1];
    wire [DATA_WIDTH-1:0] in1_arr [0:NUM_ELEMENTS-1];
    wire [DATA_WIDTH-1:0] out_arr [0:NUM_ELEMENTS-1];

    genvar i;
    generate
        for (i = 0; i < NUM_ELEMENTS; i = i + 1) begin : MUX_ARRAY
            // 1. Unpack / Unflatten
            assign in0_arr[i] = in0_flat[i*DATA_WIDTH +: DATA_WIDTH];
            assign in1_arr[i] = in1_flat[i*DATA_WIDTH +: DATA_WIDTH];
            
            // 2. Multiplexing Logic
            assign out_arr[i] = (sel) ? in1_arr[i] : in0_arr[i];
            
            // 3. Pack / Flatten Output
            assign out_flat[i*DATA_WIDTH +: DATA_WIDTH] = out_arr[i];
        end
    endgenerate

endmodule