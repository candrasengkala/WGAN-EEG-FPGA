"""
1D Convolution Golden Model with Bias
Matches the Verilog onedconv module behavior exactly
"""

import numpy as np
import csv
from typing import Tuple, List, Optional
from datetime import datetime

class Conv1DGoldenModel:
    """Golden model for 1D convolution with bias matching hardware implementation"""
    
    def __init__(self, input_channels: int, temporal_length: int, 
                 kernel_size: int, filter_number: int, 
                 stride: int = 1, padding: int = 0, use_bias: bool = True):
        """
        Initialize 1D Convolution Golden Model
        
        Args:
            input_channels: Number of input channels
            temporal_length: Length of input sequence
            kernel_size: Size of convolution kernel
            filter_number: Number of output filters
            stride: Stride for convolution (default: 1)
            padding: Padding on both sides (default: 0)
            use_bias: Whether to use bias (default: True)
        """
        self.input_channels = input_channels
        self.temporal_length = temporal_length
        self.kernel_size = kernel_size
        self.filter_number = filter_number
        self.stride = stride
        self.padding = padding
        self.use_bias = use_bias
        
        # Calculate output length
        self.output_length = self._calc_output_length()
        
        # Initialize data structures
        self.input_data = None
        self.weights = None
        self.bias = None
        self.output = None
        
    def _calc_output_length(self) -> int:
        """Calculate output sequence length"""
        return (self.temporal_length + 2 * self.padding - self.kernel_size) // self.stride + 1
    
    def set_input_data(self, data: np.ndarray):
        """
        Set input data
        
        Args:
            data: Shape (input_channels, temporal_length)
        """
        assert data.shape == (self.input_channels, self.temporal_length), \
            f"Expected shape ({self.input_channels}, {self.temporal_length}), got {data.shape}"
        self.input_data = data.astype(np.int32)
    
    def set_weights(self, weights: np.ndarray):
        """
        Set convolution weights
        
        Args:
            weights: Shape (filter_number, input_channels, kernel_size)
        """
        assert weights.shape == (self.filter_number, self.input_channels, self.kernel_size), \
            f"Expected shape ({self.filter_number}, {self.input_channels}, {self.kernel_size}), got {weights.shape}"
        self.weights = weights.astype(np.int32)
    
    def set_bias(self, bias: np.ndarray):
        """
        Set bias values
        
        Args:
            bias: Shape (filter_number,) - one bias per filter
        """
        assert bias.shape == (self.filter_number,), \
            f"Expected shape ({self.filter_number},), got {bias.shape}"
        self.bias = bias.astype(np.int32)
    
    def convolve(self) -> np.ndarray:
        """
        Perform standard 1D convolution with bias
        
        Returns:
            output: Shape (filter_number, output_length)
        """
        assert self.input_data is not None, "Input data not set"
        assert self.weights is not None, "Weights not set"
        if self.use_bias:
            assert self.bias is not None, "Bias not set (use_bias=True)"
        
        # Apply padding
        if self.padding > 0:
            padded_input = np.pad(self.input_data, 
                                 ((0, 0), (self.padding, self.padding)), 
                                 mode='constant', constant_values=0)
        else:
            padded_input = self.input_data
        
        # Initialize output
        self.output = np.zeros((self.filter_number, self.output_length), dtype=np.int32)
        
        # Perform standard convolution
        for f in range(self.filter_number):
            for t in range(self.output_length):
                # Starting position in padded input
                start_pos = t * self.stride
                
                # Accumulate across all input channels and kernel positions
                acc = 0
                for c in range(self.input_channels):
                    for k in range(self.kernel_size):
                        input_val = padded_input[c, start_pos + k]
                        weight_val = self.weights[f, c, k]
                        acc += input_val * weight_val
                
                # Add bias
                if self.use_bias:
                    acc += self.bias[f]
                
                self.output[f, t] = acc
        
        return self.output
    
    def get_output(self) -> np.ndarray:
        """Get convolution output"""
        assert self.output is not None, "Convolution not performed yet"
        return self.output
    
    def print_config(self):
        """Print configuration"""
        print("=" * 60)
        print("         1D CONVOLUTION GOLDEN MODEL")
        print("=" * 60)
        print(f"Configuration:")
        print(f"  Input Channels:  {self.input_channels}")
        print(f"  Temporal Length: {self.temporal_length}")
        print(f"  Kernel Size:     {self.kernel_size}")
        print(f"  Filters:         {self.filter_number}")
        print(f"  Stride:          {self.stride}")
        print(f"  Padding:         {self.padding}")
        print(f"  Use Bias:        {self.use_bias}")
        print(f"  Output Length:   {self.output_length}")
        print("=" * 60)
    
    def print_input_data(self):
        """Print input data"""
        print("\nInput Data:")
        for c in range(self.input_channels):
            print(f"  Channel {c}: {self.input_data[c, :].tolist()}")
    
    def print_weights(self):
        """Print weights"""
        print("\nWeights:")
        for f in range(self.filter_number):
            print(f"  Filter {f}:")
            for c in range(self.input_channels):
                print(f"    Channel {c}: {self.weights[f, c, :].tolist()}")
    
    def print_bias(self):
        """Print bias values"""
        if self.use_bias and self.bias is not None:
            print("\nBias:")
            for f in range(self.filter_number):
                print(f"  Filter {f}: {self.bias[f]}")
    
    def print_output(self, file=None):
        """
        Print output
        
        Args:
            file: File object to write to (if None, prints to console)
        """
        def write(text):
            if file:
                file.write(text + '\n')
            else:
                print(text)
        
        write("\n" + "=" * 60)
        write("                   RESULTS")
        write("=" * 60)
        for f in range(self.filter_number):
            write(f"\n--- Filter {f} ---")
            for t in range(self.output_length):
                write(f"  Time[{t}] = {self.output[f, t]}")
        
        # Side-by-side comparison for multiple filters
        if self.filter_number > 1:
            write("\n" + "=" * 60)
            write("        SIDE-BY-SIDE COMPARISON")
            write("=" * 60)
            
            # Header
            header = "Time |"
            for f in range(self.filter_number):
                header += f" Filter {f:2d} |"
            write(header)
            
            # Separator
            sep = "-----|"
            for f in range(self.filter_number):
                sep += "-----------|"
            write(sep)
            
            # Data rows
            for t in range(self.output_length):
                row = f"{t:4d} |"
                for f in range(self.filter_number):
                    row += f" {self.output[f, t]:9d} |"
                write(row)
    
    def save_output_csv(self, filename: str = "conv1d_output.csv"):
        """
        Save output to CSV file
        
        Args:
            filename: Output CSV filename
        """
        assert self.output is not None, "Convolution not performed yet"
        
        with open(filename, 'w', newline='') as csvfile:
            writer = csv.writer(csvfile)
            
            # Write header
            header = ['Time_Index'] + [f'Filter_{f}' for f in range(self.filter_number)]
            writer.writerow(header)
            
            # Write data
            for t in range(self.output_length):
                row = [t] + [int(self.output[f, t]) for f in range(self.filter_number)]
                writer.writerow(row)
        
        print(f"Output saved to {filename}")
    
    def save_full_report(self, filename: str = "conv1d_report.txt"):
        """
        Save full report including configuration, input, weights, bias, and output
        
        Args:
            filename: Output text filename
        """
        with open(filename, 'w') as f:
            # Header with timestamp
            f.write("=" * 60 + "\n")
            f.write("         1D CONVOLUTION GOLDEN MODEL REPORT\n")
            f.write(f"         Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
            f.write("=" * 60 + "\n")
            
            # Configuration
            f.write(f"Configuration:\n")
            f.write(f"  Input Channels:  {self.input_channels}\n")
            f.write(f"  Temporal Length: {self.temporal_length}\n")
            f.write(f"  Kernel Size:     {self.kernel_size}\n")
            f.write(f"  Filters:         {self.filter_number}\n")
            f.write(f"  Stride:          {self.stride}\n")
            f.write(f"  Padding:         {self.padding}\n")
            f.write(f"  Use Bias:        {self.use_bias}\n")
            f.write(f"  Output Length:   {self.output_length}\n")
            f.write("=" * 60 + "\n")
            
            # Input data
            f.write("\nInput Data:\n")
            for c in range(self.input_channels):
                f.write(f"  Channel {c}: {self.input_data[c, :].tolist()}\n")
            
            # Weights
            f.write("\nWeights:\n")
            for f_idx in range(self.filter_number):
                f.write(f"  Filter {f_idx}:\n")
                for c in range(self.input_channels):
                    f.write(f"    Channel {c}: {self.weights[f_idx, c, :].tolist()}\n")
            
            # Bias
            if self.use_bias and self.bias is not None:
                f.write("\nBias:\n")
                for f_idx in range(self.filter_number):
                    f.write(f"  Filter {f_idx}: {self.bias[f_idx]}\n")
            
            # Output
            self.print_output(file=f)
            
            f.write("\n" + "=" * 60 + "\n")
            f.write("Report Complete.\n")
            f.write("=" * 60 + "\n")
        
        print(f"Full report saved to {filename}")


def generate_unique_weights(filter_number: int, input_channels: int, kernel_size: int) -> np.ndarray:
    """
    Generate unique weights matching the Verilog testbench pattern
    Pattern: weight[f][c][k] = ((f + k) % 5) + 1
    
    Args:
        filter_number: Number of output filters
        input_channels: Number of input channels
        kernel_size: Size of convolution kernel
        
    Returns:
        weights: Shape (filter_number, input_channels, kernel_size)
    """
    weights = np.zeros((filter_number, input_channels, kernel_size), dtype=np.int32)
    for f in range(filter_number):
        for c in range(input_channels):
            for k in range(kernel_size):
                weights[f, c, k] = ((f + k) % 5) + 1
    return weights
def generate_testbench_data(input_channels: int, temporal_length: int) -> np.ndarray:
    """
    Generate test input data matching the Verilog testbench pattern
    Pattern: ((channel_id + time_index) % 5) + 1

    Args:
        input_channels: Number of input channels
        temporal_length: Length of input sequence

    Returns:
        input_data: Shape (input_channels, temporal_length)
    """
    data = np.zeros((input_channels, temporal_length), dtype=np.int32)
    for c in range(input_channels):
        for t in range(temporal_length):
            # Match testbench pattern: ((ch + t) % 5) + 1
            data[c, t] = ((c + t) % 5) + 1
    return data


def run_test(test_name: str, input_channels: int, temporal_length: int, 
             kernel_size: int, filter_number: int, stride: int, padding: int, 
             bias_value: Optional[int] = None, use_bias: bool = True):
    """
    Run a single test case
    
    Args:
        test_name: Name of the test
        input_channels: Number of input channels
        temporal_length: Length of input sequence
        kernel_size: Size of convolution kernel
        filter_number: Number of output filters
        stride: Stride for convolution
        padding: Padding on both sides
        bias_value: Bias value to use (None for no bias, scalar for all filters)
        use_bias: Whether to use bias
        
    Returns:
        output: Convolution output
    """
    print("\n" + "=" * 60)
    print(f">>> {test_name}")
    print("=" * 60)
    
    # Create golden model
    model = Conv1DGoldenModel(
        input_channels=input_channels,
        temporal_length=temporal_length,
        kernel_size=kernel_size,
        filter_number=filter_number,
        stride=stride,
        padding=padding,
        use_bias=use_bias
    )
    
    # Print configuration
    model.print_config()
    
    # Generate input data (matching Verilog testbench pattern)
    input_data = generate_testbench_data(input_channels, temporal_length)
    model.set_input_data(input_data)
    model.print_input_data()
    
    # Set weights with UNIQUE values per filter (matching Verilog testbench)
    # Pattern: weight[f][c][k] = ((f + k) % 5) + 1
    weights = generate_unique_weights(filter_number, input_channels, kernel_size)
    model.set_weights(weights)
    print("\nWeights: Unique per filter")
    print(f"  Pattern: W[f][c][k] = ((f + k) % 5) + 1")
    model.print_weights()
    
    # Set bias
    if use_bias and bias_value is not None:
        bias = np.full(filter_number, bias_value, dtype=np.int32)
        model.set_bias(bias)
        model.print_bias()
    elif use_bias:
        # Default to zero bias
        bias = np.zeros(filter_number, dtype=np.int32)
        model.set_bias(bias)
        print(f"\nBias: All set to 0")
    
    # Perform convolution
    print("\n--- Starting Convolution ---")
    output = model.convolve()
    print("--- Convolution Finished ---")
    
    # Print results to console
    model.print_output()
    
    return output


def main():
    """Run all test cases matching the Verilog testbench"""
    
    print("\n")
    print("=" * 60)
    print("  1D CONVOLUTION GOLDEN MODEL - TEST SUITE")
    print("  UNIQUE WEIGHTS PER FILTER")
    print("=" * 60)
    print("Weight Pattern: W[f][c][k] = ((f + k) % 5) + 1")
    print("Input Pattern: I[c][t] = ((c + t) % 5) + 1")
    print("=" * 60)
    
    # Test 1: No bias
    print("\n" + "="*60)
    print("TEST 1: Basic Convolution (No Bias)")
    print("="*60)
    output1 = run_test(
        "Test 1: Basic Convolution (No Bias)",
        input_channels=2,
        temporal_length=7,
        kernel_size=4,
        filter_number=1,
        stride=2,
        padding=0,
        bias_value=None,
        use_bias=False
    )
    
    # Test 2: Stride = 2
    print("\n" + "="*60)
    print("TEST 2: Convolution with Stride = 2")
    print("="*60)
    output2 = run_test(
        "Test 2: Convolution with Stride = 2",
        input_channels=1,
        temporal_length=16,
        kernel_size=3,
        filter_number=1,
        stride=2,
        padding=0,
        bias_value=None,
        use_bias=False
    )
    
    # Test 3: Padding = 2
    print("\n" + "="*60)
    print("TEST 3: Convolution with Padding = 2")
    print("="*60)
    output3 = run_test(
        "Test 3: Convolution with Padding = 2",
        input_channels=1,
        temporal_length=16,
        kernel_size=3,
        filter_number=1,
        stride=2,
        padding=2,
        bias_value=None,
        use_bias=False
    )
    
    # Test 4: Kernel Size = 7
    print("\n" + "="*60)
    print("TEST 4: Kernel Size = 7")
    print("="*60)
    output4 = run_test(
        "Test 4: Kernel Size = 7",
        input_channels=1,
        temporal_length=32,
        kernel_size=7,
        filter_number=1,
        stride=1,
        padding=0,
        bias_value=None,
        use_bias=False
    )
    
    # Test 5: Multiple Input Channels
    print("\n" + "="*60)
    print("TEST 5: Multiple Input Channels (4 channels)")
    print("="*60)
    output5 = run_test(
        "Test 5: Multiple Input Channels (4 channels)",
        input_channels=4,
        temporal_length=16,
        kernel_size=3,
        filter_number=1,
        stride=1,
        padding=0,
        bias_value=None,
        use_bias=False
    )

    # Test 6: Complex Scenario
    print("\n" + "="*60)
    print("TEST 6: Complex Scenario")
    print("="*60)
    output6 = run_test(
        "Test 6: Complex Scenario",
        input_channels=32,
        temporal_length=64,
        kernel_size=5,
        filter_number=2,
        stride=2,
        padding=1,
        bias_value=None,
        use_bias=False
    )

    # Test 7: Block-based Weight Loading
    print("\n" + "="*60)
    print("TEST 7: Block-based Weight Loading (70 Channels)")
    print("="*60)
    output7 = run_test(
        "Test 7: Block-based Weight Loading (70 Channels)",
        input_channels=70,
        temporal_length=16,
        kernel_size=3,
        filter_number=1,
        stride=1,
        padding=0,
        bias_value=None,
        use_bias=False
    )

    # Test 8: Large Filter Number
    print("\n" + "="*60)
    print("TEST 8: Large Filter Number (32 Filters)")
    print("="*60)
    output8 = run_test(
        "Test 8: Large Filter Number (32 Filters)",
        input_channels=16,
        temporal_length=16,
        kernel_size=3,
        filter_number=32,
        stride=2, # Matches TB stride=2'd1
        padding=1,
        bias_value=None,
        use_bias=False
    )
    
    print("\n" + "=" * 60)
    print("All Tests Finished.")
    print("=" * 60)
    
    return output1, output2, output3, output4, output5, output6, output7, output8


def run_custom_test(input_channels: int = 3, 
                   temporal_length: int = 8,
                   kernel_size: int = 5,
                   filter_number: int = 4,
                   stride: int = 2,
                   padding: int = 2,
                   use_bias: bool = True,
                   save_files: bool = True):
    """
    Run a custom test with different parameters
    
    Args:
        input_channels: Number of input channels
        temporal_length: Length of input sequence
        kernel_size: Size of convolution kernel
        filter_number: Number of output filters
        stride: Stride for convolution
        padding: Padding on both sides
        use_bias: Whether to use bias
        save_files: Whether to save output files (default: True)
        
    Returns:
        output: Convolution output
    """
    print("\n" + "=" * 60)
    print("         CUSTOM TEST")
    print("=" * 60)
    
    model = Conv1DGoldenModel(
        input_channels=input_channels,
        temporal_length=temporal_length,
        kernel_size=kernel_size,
        filter_number=filter_number,
        stride=stride,
        padding=padding,
        use_bias=use_bias
    )
    
    model.print_config()
    
    # Random input data
    input_data = np.random.randint(-10, 10, 
                                   size=(input_channels, temporal_length),
                                   dtype=np.int32)
    model.set_input_data(input_data)
    model.print_input_data()
    
    # Random weights
    weights = np.random.randint(-2, 2, 
                               size=(filter_number, input_channels, kernel_size),
                               dtype=np.int32)
    model.set_weights(weights)
    model.print_weights()
    
    # Random bias
    if use_bias:
        bias = np.random.randint(-5, 5, size=filter_number, dtype=np.int32)
        model.set_bias(bias)
        model.print_bias()
    
    # Convolve
    output = model.convolve()
    model.print_output()
    
    # Save to files
    if save_files:
        print("\n" + "=" * 60)
        print("Saving results to files...")
        model.save_output_csv("conv1d_custom_output.csv")
        model.save_full_report("conv1d_custom_report.txt")
    
    return output


if __name__ == "__main__":
    # Run all tests matching Verilog testbench
    print("Running tests matching Verilog testbench...\n")
    outputs = main()
    
    # Optionally run custom test with bias
    # print("\n\n")
    # custom_output = run_custom_test(use_bias=True)