import numpy as np

def oned_conv_numpy(input_data, weights, bias_val, stride, padding):
    """
    Performs 1D convolution matching the Verilog hardware logic:
    1. Initialize Accumulator with Bias.
    2. Sum (Input * Weights) into the Accumulator.
    """
    # Shapes
    filters, in_ch, k_size = weights.shape
    _, temp_len = input_data.shape
    
    # Calculate Output Length
    out_len = (temp_len + 2 * padding - k_size) // stride + 1
    
    # 1. Initialize Accumulator with Bias (Hardware Logic)
    # Handle both scalar bias (Test 1/2) and per-filter bias (Test 3)
    if np.isscalar(bias_val):
        output = np.full((filters, out_len), bias_val, dtype=np.int32)
    else:
        # If bias is an array [filters], broadcast it to [filters, out_len]
        bias_arr = np.array(bias_val, dtype=np.int32)
        output = np.tile(bias_arr[:, None], (1, out_len))
    
    # 2. Perform Convolution
    # Iterate over each output time step
    for t in range(out_len):
        # Handle Padding logic manually to match hardware windowing exactly
        # Pad temporal dim only: ((0,0), (padding, padding))
        pad_width = ((0, 0), (padding, padding)) 
        padded_input = np.pad(input_data, pad_width, mode='constant', constant_values=0)
        
        # Calculate window position in the PADDED array
        p_start = (t * stride) 
        p_end   = p_start + k_size
        
        window = padded_input[:, p_start:p_end] # Shape: [in_ch, k_size]
        
        # Compute Dot Product for each filter
        for f in range(filters):
            # Sum over Input Channels and Kernel Size
            # Hardware does: Accum += Input * Weight
            product = np.sum(window * weights[f])
            output[f, t] += product
            
    return output

def print_test_config_numpy(test_name, stride, padding, kernel_size, input_channels, temporal_length, filter_number, bias_val, input_data, weights):
    """Prints the configuration, input data, and weights for a test case."""
    print("\n" + "="*60)
    print(f"TEST: {test_name}")
    print("="*60)
    print("CONFIGURATION:")
    print(f"  Stride:          {stride}")
    print(f"  Padding:         {padding}")
    print(f"  Kernel Size:     {kernel_size}")
    print(f"  Input Channels:  {input_channels}")
    print(f"  Temporal Length: {temporal_length}")
    print(f"  Filter Number:   {filter_number}")
    print(f"  Bias (Init Val): {bias_val}")
    
    print("\nINPUT DATA:")
    for c in range(input_channels):
        # Convert numpy array to list string for cleaner display
        print(f"  Channel {c}: {np.array2string(input_data[c], separator=', ')}")

    print("\nWEIGHTS:")
    for f in range(filter_number):
        print(f"  Filter {f}:")
        for c in range(input_channels):
            print(f"    Channel {c}: {np.array2string(weights[f,c], separator=', ')}")
    print("-" * 60)

def run_tests():
    print("=======================================================")
    print("      1D CONVOLUTION NUMPY GOLDEN MODEL")
    print("      (Matches Verilog Unique Test Vectors)")
    print("=======================================================")

    # =========================================================
    # TEST 1: Basic (S=1, P=1) - No Bias
    # =========================================================
    S, P, K = 1, 1, 3
    IN_CH, LEN, FILTERS = 2, 8, 1
    BIAS = 0

    # Init Data: (c + 1) * 10 + i
    input_data = np.zeros((IN_CH, LEN), dtype=np.int32)
    for c in range(IN_CH):
        input_data[c, :] = np.arange(LEN) + (c + 1) * 10
        
    # Init Weights: (f + 1) * 10 + (c + 1) * 5 + k + 1
    weights = np.zeros((FILTERS, IN_CH, K), dtype=np.int32)
    for f in range(FILTERS):
        for c in range(IN_CH):
            weights[f, c, :] = np.arange(K) + (f + 1) * 10 + (c + 1) * 5 + 1

    # Print Config
    print_test_config_numpy("1: Basic (S=1, P=1, No Bias)", S, P, K, IN_CH, LEN, FILTERS, BIAS, input_data, weights)

    # Run
    res = oned_conv_numpy(input_data, weights, BIAS, S, P)

    # Print Results
    print("RESULTS:")
    for f in range(FILTERS):
        for i in range(res.shape[1]):
            print(f"  Filter {f}[{i}] = {res[f, i]}")


    # =========================================================
    # TEST 2: High Padding (S=2, P=7) - No Bias
    # =========================================================
    S, P, K = 2, 7, 4
    IN_CH, LEN, FILTERS = 2, 7, 1
    BIAS = 0

    # Init Data: (c + 1) * 10 + i
    input_data = np.zeros((IN_CH, LEN), dtype=np.int32)
    for c in range(IN_CH):
        input_data[c, :] = np.arange(LEN) + (c + 1) * 10

    # Init Weights: (f + 1) * 10 + (c + 1) * 5 + k + 1
    weights = np.zeros((FILTERS, IN_CH, K), dtype=np.int32)
    for f in range(FILTERS):
        for c in range(IN_CH):
            weights[f, c, :] = np.arange(K) + (f + 1) * 10 + (c + 1) * 5 + 1

    # Print Config
    print_test_config_numpy("2: High Padding (S=2, P=7, No Bias)", S, P, K, IN_CH, LEN, FILTERS, BIAS, input_data, weights)

    # Run
    res = oned_conv_numpy(input_data, weights, BIAS, S, P)

    # Print Results
    print("RESULTS:")
    for f in range(FILTERS):
        for i in range(res.shape[1]):
            print(f"  Filter {f}[{i}] = {res[f, i]}")


    # =========================================================
    # TEST 3: Multi-Filter + Bias
    # =========================================================
    S, P, K = 1, 0, 3
    IN_CH, LEN, FILTERS = 2, 8, 3
    
    # Init Bias: (f + 1) * 100
    BIAS = [(f + 1) * 100 for f in range(FILTERS)]

    # Init Data: (c + 1) * 10 + i
    input_data = np.zeros((IN_CH, LEN), dtype=np.int32)
    for c in range(IN_CH):
        input_data[c, :] = np.arange(LEN) + (c + 1) * 10

    # Init Weights: (f + 1) * 10 + (c + 1) * 5 + k + 1
    weights = np.zeros((FILTERS, IN_CH, K), dtype=np.int32)
    for f in range(FILTERS):
        for c in range(IN_CH):
            weights[f, c, :] = np.arange(K) + (f + 1) * 10 + (c + 1) * 5 + 1

    # Print Config
    print_test_config_numpy("3: Multi-Filter + Bias (Unique Values)", S, P, K, IN_CH, LEN, FILTERS, BIAS, input_data, weights)

    # Run
    res = oned_conv_numpy(input_data, weights, BIAS, S, P)

    # Print Results
    print("RESULTS:")
    for f in range(FILTERS):
        print(f"Filter {f}:")
        for i in range(res.shape[1]):
            print(f"  Filter {f}[{i}] = {res[f, i]}")

    print("\n--- All Tests Finished ---")

if __name__ == "__main__":
    run_tests()