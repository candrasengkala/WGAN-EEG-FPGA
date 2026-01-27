"""
Generate Golden Model Expected Outputs in Table Format
Run this to see what the Verilog testbench SHOULD output
"""

import numpy as np


def generate_testbench_data(input_channels, temporal_length):
    """Generate input data matching testbench pattern: ((ch + t) % 5) + 1"""
    data = np.zeros((input_channels, temporal_length), dtype=np.int32)
    for c in range(input_channels):
        for t in range(temporal_length):
            data[c, t] = ((c + t) % 5) + 1
    return data


def generate_weights(filter_number, input_channels, kernel_size):
    """Generate weights matching testbench pattern: ((f + k) % 5) + 1"""
    weights = np.zeros((filter_number, input_channels, kernel_size), dtype=np.int32)
    for f in range(filter_number):
        for c in range(input_channels):
            for k in range(kernel_size):
                weights[f, c, k] = ((f + k) % 5) + 1
    return weights


def conv1d(input_data, weights, stride, padding):
    """Perform 1D convolution"""
    input_channels, temporal_length = input_data.shape
    filter_number, _, kernel_size = weights.shape

    # Calculate output length
    output_length = (temporal_length + 2 * padding - kernel_size) // stride + 1

    # Apply padding
    if padding > 0:
        padded_input = np.pad(input_data, ((0, 0), (padding, padding)),
                             mode='constant', constant_values=0)
    else:
        padded_input = input_data

    # Initialize output
    output = np.zeros((filter_number, output_length), dtype=np.int32)

    # Perform convolution
    for f in range(filter_number):
        for t in range(output_length):
            start_pos = t * stride
            acc = 0
            for c in range(input_channels):
                for k in range(kernel_size):
                    acc += padded_input[c, start_pos + k] * weights[f, c, k]
            output[f, t] = acc

    return output


def print_table(output, test_name, file_handle=None):
    """Print output in table format"""
    filter_number, output_length = output.shape

    def write(text):
        if file_handle:
            file_handle.write(text + '\n')
        else:
            print(text)

    write(f"\n{'='*80}")
    write(f"{test_name:^80}")
    write(f"{'='*80}")

    # Header
    header = "Time |"
    for f in range(filter_number):
        header += f" Filter {f:2d} |"
    write(header)

    # Separator
    sep = "-----|"
    for f in range(filter_number):
        sep += "-----------|"
    write(sep)

    # Data rows
    for t in range(output_length):
        row = f" {t:3d} |"
        for f in range(filter_number):
            value = int(output[f, t])
            row += f" {value:9d} |"
        write(row)

    write("="*80)


def run_test(name, input_channels, temporal_length, kernel_size, filter_number, stride, padding, file_handle=None):
    """Run a single test and display results"""
    input_data = generate_testbench_data(input_channels, temporal_length)
    weights = generate_weights(filter_number, input_channels, kernel_size)
    output = conv1d(input_data, weights, stride, padding)

    def write(text):
        if file_handle:
            file_handle.write(text + '\n')
        else:
            print(text)

    write(f"\n{name}")
    write(f"Params: ch={input_channels}, len={temporal_length}, k={kernel_size}, "
          f"filters={filter_number}, stride={stride}, pad={padding}")

    print_table(output, name, file_handle)
    return output


def main():
    """Run all tests and save results to file"""
    output_file = "golden_model_expected_outputs.txt"

    with open(output_file, 'w') as f:
        def write(text):
            f.write(text + '\n')
            print(text)  # Also print to console

        write("\n" + "="*80)
        write("GOLDEN MODEL EXPECTED OUTPUTS".center(80))
        write("="*80)
        write("Input Pattern:  I[c][t] = ((c + t) % 5) + 1")
        write("Weight Pattern: W[f][c][k] = ((f + k) % 5) + 1")
        write("="*80)

        # Test 1: Basic convolution
        run_test("TEST 1: Basic Convolution",
                 input_channels=1, temporal_length=16, kernel_size=3,
                 filter_number=1, stride=1, padding=0, file_handle=f)

        # Test 2: Stride = 2 (kernel_size must be divisible by stride)
        run_test("TEST 2: Stride = 2",
                 input_channels=1, temporal_length=16, kernel_size=4,
                 filter_number=1, stride=2, padding=0, file_handle=f)

        # Test 3: Padding = 2
        run_test("TEST 3: Padding = 2",
                 input_channels=1, temporal_length=16, kernel_size=3,
                 filter_number=1, stride=1, padding=2, file_handle=f)

        # Test 4: Kernel size = 7
        run_test("TEST 4: Kernel Size = 7",
                 input_channels=1, temporal_length=32, kernel_size=7,
                 filter_number=1, stride=1, padding=0, file_handle=f)

        # Test 5: Multiple input channels
        run_test("TEST 5: Multiple Input Channels (4)",
                 input_channels=4, temporal_length=16, kernel_size=3,
                 filter_number=1, stride=1, padding=0, file_handle=f)

        # Test 6: Complex scenario
        run_test("TEST 6: Complex Scenario",
                 input_channels=64, temporal_length=64, kernel_size=16,
                 filter_number=64, stride=2, padding=1, file_handle=f)

        # Test 7: Block-based weight loading
        run_test("TEST 7: Block-based Weight Loading (70 channels)",
                 input_channels=70, temporal_length=16, kernel_size=3,
                 filter_number=1, stride=1, padding=0, file_handle=f)

        # Test 8: Large filter number (kernel_size must be divisible by stride)
        run_test("TEST 8: Large Filter Number (32 filters)",
                 input_channels=16, temporal_length=16, kernel_size=4,
                 filter_number=32, stride=2, padding=1, file_handle=f)

        write("\n" + "="*80)
        write("All Golden Model Tests Complete!".center(80))
        write("="*80)
        write(f"\nResults saved to: {output_file}")
        write("Compare these values with your Verilog simulation output.")

    print(f"\n✓ Golden model outputs written to: {output_file}")


if __name__ == "__main__":
    main()
