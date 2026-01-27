"""
VCD Parser and Result Comparison Tool
Compares Verilog simulation output with Python golden model
"""

import re
import numpy as np
from verif6 import Conv1DGoldenModel, generate_testbench_data, generate_unique_weights


def parse_vcd_output(vcd_file: str, signal_name: str = "output_result",
                     dimension: int = 16, dw: int = 16):
    """
    Parse VCD file to extract output_result signal over time

    Args:
        vcd_file: Path to VCD file
        signal_name: Signal name to extract (default: "output_result")
        dimension: Number of parallel outputs (default: 16)
        dw: Data width per element (default: 16)

    Returns:
        Dictionary mapping time -> list of signed integers
    """
    print(f"Parsing VCD file: {vcd_file}")
    print(f"Looking for signal: {signal_name}")

    # This is a simplified VCD parser - may need enhancement
    # For now, we'll just extract the signal values

    # TODO: Implement VCD parsing
    # For demonstration, return empty dict
    return {}


def compare_with_golden_model(test_config: dict, vcd_results: dict):
    """
    Compare VCD simulation results with golden model

    Args:
        test_config: Dictionary with test configuration
        vcd_results: Dictionary from VCD parser
    """
    # Extract configuration
    input_channels = test_config['input_channels']
    temporal_length = test_config['temporal_length']
    kernel_size = test_config['kernel_size']
    filter_number = test_config['filter_number']
    stride = test_config['stride']
    padding = test_config['padding']

    # Create golden model
    model = Conv1DGoldenModel(
        input_channels=input_channels,
        temporal_length=temporal_length,
        kernel_size=kernel_size,
        filter_number=filter_number,
        stride=stride,
        padding=padding,
        use_bias=False
    )

    # Generate input data (matching testbench pattern)
    input_data = generate_testbench_data(input_channels, temporal_length)
    model.set_input_data(input_data)

    # Generate weights (matching testbench pattern)
    weights = generate_unique_weights(filter_number, input_channels, kernel_size)
    model.set_weights(weights)

    # Set bias to zero
    bias = np.zeros(filter_number, dtype=np.int32)
    model.set_bias(bias)

    # Run convolution
    golden_output = model.convolve()

    # Print configuration
    model.print_config()

    # Print results in side-by-side format
    print_side_by_side_comparison(golden_output, filter_number, model.output_length)

    return golden_output


def print_side_by_side_comparison(output: np.ndarray, filter_number: int, output_length: int):
    """
    Print output in side-by-side format with signed integers

    Args:
        output: Shape (filter_number, output_length)
        filter_number: Number of filters
        output_length: Length of output sequence
    """
    print("\n" + "=" * 80)
    print("          GOLDEN MODEL OUTPUT (Signed Integers)")
    print("=" * 80)

    # Print individual filter outputs
    for f in range(filter_number):
        print(f"\n--- Filter {f} ---")
        for t in range(output_length):
            value = int(output[f, t])
            # Convert to signed if needed
            print(f"  Time[{t:3d}] = {value:8d} (0x{value & 0xFFFF:04X})")

    # Side-by-side comparison for multiple filters
    if filter_number > 1:
        print("\n" + "=" * 80)
        print("            SIDE-BY-SIDE COMPARISON")
        print("=" * 80)

        # Calculate column width based on filter_number
        col_width = max(12, 80 // (filter_number + 1) - 2)

        # Header
        header = f"{'Time':<6} |"
        for f in range(filter_number):
            header += f" {f'Filter {f}':^{col_width}} |"
        print(header)

        # Separator
        sep = "-------+"
        for f in range(filter_number):
            sep += "-" * (col_width + 2) + "+"
        print(sep)

        # Data rows
        for t in range(output_length):
            row = f"{t:5d}  |"
            for f in range(filter_number):
                value = int(output[f, t])
                row += f" {value:>{col_width}d} |"
            print(row)

    print("=" * 80)


def run_test_1():
    """Test 1: Basic Convolution (No Bias)"""
    config = {
        'input_channels': 1,
        'temporal_length': 16,
        'kernel_size': 3,
        'filter_number': 1,
        'stride': 1,  # stride=2'd0 means stride=1
        'padding': 0
    }

    print("\n" + "="*80)
    print("TEST 1: Basic Convolution (kernel=3, stride=1, no padding)")
    print("="*80)

    return compare_with_golden_model(config, {})


def run_test_2():
    """Test 2: Convolution with Stride=2"""
    config = {
        'input_channels': 1,
        'temporal_length': 16,
        'kernel_size': 3,
        'filter_number': 1,
        'stride': 2,  # stride=2'd1 means stride=2
        'padding': 0
    }

    print("\n" + "="*80)
    print("TEST 2: Convolution with Stride=2")
    print("="*80)

    return compare_with_golden_model(config, {})


def run_test_3():
    """Test 3: Convolution with Padding=2"""
    config = {
        'input_channels': 1,
        'temporal_length': 16,
        'kernel_size': 3,
        'filter_number': 1,
        'stride': 1,
        'padding': 2
    }

    print("\n" + "="*80)
    print("TEST 3: Convolution with Padding=2")
    print("="*80)

    return compare_with_golden_model(config, {})


def run_test_4():
    """Test 4: Kernel Size = 7"""
    config = {
        'input_channels': 1,
        'temporal_length': 32,
        'kernel_size': 7,
        'filter_number': 1,
        'stride': 1,
        'padding': 0
    }

    print("\n" + "="*80)
    print("TEST 4: Kernel Size = 7")
    print("="*80)

    return compare_with_golden_model(config, {})


def run_test_5():
    """Test 5: Multiple Input Channels (4 channels)"""
    config = {
        'input_channels': 4,
        'temporal_length': 16,
        'kernel_size': 3,
        'filter_number': 1,
        'stride': 1,
        'padding': 0
    }

    print("\n" + "="*80)
    print("TEST 5: Multiple Input Channels (4 channels)")
    print("="*80)

    return compare_with_golden_model(config, {})


def run_test_6():
    """Test 6: Complex Scenario"""
    config = {
        'input_channels': 32,
        'temporal_length': 64,
        'kernel_size': 5,
        'filter_number': 2,
        'stride': 2,
        'padding': 1
    }

    print("\n" + "="*80)
    print("TEST 6: Complex Scenario (32 channels, kernel=5, stride=2, padding=1)")
    print("="*80)

    return compare_with_golden_model(config, {})


def run_test_7():
    """Test 7: Block-based Weight Loading (70 Channels)"""
    config = {
        'input_channels': 70,
        'temporal_length': 16,
        'kernel_size': 3,
        'filter_number': 1,
        'stride': 1,
        'padding': 0
    }

    print("\n" + "="*80)
    print("TEST 7: Block-based Weight Loading (70 Channels)")
    print("="*80)

    return compare_with_golden_model(config, {})


def run_test_8():
    """Test 8: Large Filter Number (32 Filters)"""
    config = {
        'input_channels': 16,
        'temporal_length': 16,
        'kernel_size': 3,
        'filter_number': 32,
        'stride': 2,
        'padding': 1
    }

    print("\n" + "="*80)
    print("TEST 8: Large Filter Number (32 Filters)")
    print("="*80)

    return compare_with_golden_model(config, {})


def main():
    """Run all tests and display golden model outputs"""
    print("\n" + "="*80)
    print("     GOLDEN MODEL EXPECTED OUTPUTS")
    print("     Matching Verilog Testbench Patterns")
    print("="*80)
    print("Input Pattern:  I[c][t] = ((c + t) % 5) + 1")
    print("Weight Pattern: W[f][c][k] = ((f + k) % 5) + 1")
    print("="*80)

    # Run all tests
    output1 = run_test_1()
    output2 = run_test_2()
    output3 = run_test_3()
    output4 = run_test_4()
    output5 = run_test_5()
    output6 = run_test_6()
    output7 = run_test_7()
    output8 = run_test_8()

    print("\n" + "="*80)
    print("All Golden Model Tests Complete!")
    print("="*80)
    print("\nUse these values to verify against Verilog simulation outputs.")
    print("Compare the 'output_result' signal from the VCD waveform viewer")
    print("with the values shown above.")

    return (output1, output2, output3, output4, output5, output6, output7, output8)


if __name__ == "__main__":
    outputs = main()
