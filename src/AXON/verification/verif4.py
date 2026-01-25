"""
1D Convolution Golden Model
Matches the Verilog onedconv module behavior
"""

import numpy as np
import csv
from typing import Tuple, List
from datetime import datetime

class Conv1DGoldenModel:
    """Golden model for 1D convolution matching hardware implementation"""
    
    def __init__(self, input_channels: int, temporal_length: int, 
                 kernel_size: int, filter_number: int, 
                 stride: int = 1, padding: int = 0):
        """
        Initialize 1D Convolution Golden Model
        
        Args:
            input_channels: Number of input channels
            temporal_length: Length of input sequence
            kernel_size: Size of convolution kernel
            filter_number: Number of output filters
            stride: Stride for convolution (default: 1)
            padding: Padding on both sides (default: 0)
        """
        self.input_channels = input_channels
        self.temporal_length = temporal_length
        self.kernel_size = kernel_size
        self.filter_number = filter_number
        self.stride = stride
        self.padding = padding
        
        # Calculate output length
        self.output_length = self._calc_output_length()
        
        # Initialize data structures
        self.input_data = None
        self.weights = None
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
    
    def convolve(self) -> np.ndarray:
        """
        Perform 1D convolution
        
        Returns:
            output: Shape (filter_number, output_length)
        """
        assert self.input_data is not None, "Input data not set"
        assert self.weights is not None, "Weights not set"
        
        # Apply padding
        if self.padding > 0:
            padded_input = np.pad(self.input_data, 
                                 ((0, 0), (self.padding, self.padding)), 
                                 mode='constant', constant_values=0)
        else:
            padded_input = self.input_data
        
        # Initialize output
        self.output = np.zeros((self.filter_number, self.output_length), dtype=np.int32)
        
        # Perform convolution
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
        print(f"  Output Length:   {self.output_length}")
        print("=" * 60)
    
    def print_input_data(self):
        """Print input data"""
        print("\nInput Data:")
        for c in range(self.input_channels):
            print(f"  Channel {c}: {self.input_data[c, :]}")
    
    def print_weights(self):
        """Print weights"""
        print("\nWeights:")
        for f in range(self.filter_number):
            print(f"  Filter {f}:")
            for c in range(self.input_channels):
                print(f"    Channel {c}: {self.weights[f, c, :]}")
    
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
            write(f"\nFilter {f} outputs:")
            for t in range(self.output_length):
                write(f"  Filter {f}[{t}] = {self.output[f, t]}")
        
        # Side-by-side comparison
        if self.filter_number > 1:
            write("\n" + "=" * 60)
            write("        SIDE-BY-SIDE COMPARISON")
            write("=" * 60)
            
            # Header
            header = "Time |"
            for f in range(self.filter_number):
                header += f" Filter {f} |"
            write(header)
            
            # Separator
            sep = "-----|"
            for f in range(self.filter_number):
                sep += "----------|"
            write(sep)
            
            # Data rows
            for t in range(self.output_length):
                row = f"{t:4d} |"
                for f in range(self.filter_number):
                    row += f" {self.output[f, t]:8d} |"
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
                row = [t] + [self.output[f, t] for f in range(self.filter_number)]
                writer.writerow(row)
        
        print(f"Output saved to {filename}")
    
    def save_full_report(self, filename: str = "conv1d_report.txt"):
        """
        Save full report including configuration, input, weights, and output
        
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
            
            # Output
            self.print_output(file=f)
            
            f.write("\n" + "=" * 60 + "\n")
            f.write("Report Complete.\n")
            f.write("=" * 60 + "\n")
        
        print(f"Full report saved to {filename}")


def generate_testbench_data(input_channels: int, temporal_length: int) -> np.ndarray:
    """
    Generate test input data matching the Verilog testbench pattern
    Pattern: channel_id * 10 + time_index + 1
    
    Args:
        input_channels: Number of input channels
        temporal_length: Length of input sequence
        
    Returns:
        input_data: Shape (input_channels, temporal_length)
    """
    data = np.zeros((input_channels, temporal_length), dtype=np.int32)
    for c in range(input_channels):
        for t in range(temporal_length):
            data[c, t] = c * 10 + t + 1
    return data


def main():
    """Example usage matching the Verilog testbench"""
    
    # Configuration (matching Verilog testbench)
    input_channels = 2
    temporal_length = 7
    kernel_size = 4
    filter_number = 1
    stride = 2
    padding = 7
    
    # Create golden model
    model = Conv1DGoldenModel(
        input_channels=input_channels,
        temporal_length=temporal_length,
        kernel_size=kernel_size,
        filter_number=filter_number,
        stride=stride,
        padding=padding
    )
    
    # Print configuration
    model.print_config()
    
    # Generate input data (matching Verilog testbench pattern)
    input_data = generate_testbench_data(input_channels, temporal_length)
    model.set_input_data(input_data)
    model.print_input_data()
    
    # Set weights (all ones, matching Verilog testbench)
    weights = np.ones((filter_number, input_channels, kernel_size), dtype=np.int32)
    model.set_weights(weights)
    print("\nWeights: All set to 1")
    
    # Perform convolution
    print("\n--- Starting Convolution ---")
    output = model.convolve()
    print("--- Convolution Finished ---")
    
    # Print results to console
    model.print_output()
    
    # Save results to files
    print("\n" + "=" * 60)
    print("Saving results to files...")
    model.save_output_csv("conv1d_output.csv")
    model.save_full_report("conv1d_report.txt")
    
    print("\n" + "=" * 60)
    print("Test Finished.")
    print("=" * 60)
    
    # Return output for verification
    return output


def run_custom_test(input_channels: int = 3, 
                   temporal_length: int = 8,
                   kernel_size: int = 5,
                   filter_number: int = 4,
                   stride: int = 2,
                   padding: int = 2,
                   save_files: bool = True):
    """
    Run a custom test with different parameters
    
    Args:
        save_files: Whether to save output files (default: True)
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
        padding=padding
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
    # Run test matching Verilog testbench
    print("Running test matching Verilog testbench...\n")
    output = main()
    
    # Optionally run custom test
    # print("\n\n")
    # custom_output = run_custom_test()