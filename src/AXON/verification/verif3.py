"""
1D Convolution Golden Model
Matches the Verilog testbench behavior exactly
"""

import numpy as np
from typing import List, Tuple

class Conv1DGoldenModel:
    """Golden model for 1D convolution matching hardware implementation"""
    
    def __init__(self, 
                 input_channels: int,
                 temporal_length: int,
                 kernel_size: int,
                 filter_number: int,
                 stride: int = 1,
                 padding: int = 0,
                 data_width: int = 16):
        """
        Initialize the golden model
        
        Args:
            input_channels: Number of input channels
            temporal_length: Length of input sequence
            kernel_size: Size of convolution kernel
            filter_number: Number of output filters
            stride: Convolution stride (default 1)
            padding: Zero padding on both sides (default 0)
            data_width: Bit width of data (default 16)
        """
        self.input_channels = input_channels
        self.temporal_length = temporal_length
        self.kernel_size = kernel_size
        self.filter_number = filter_number
        self.stride = stride if stride != 0 else 1  # Match Verilog: stride=0 means 1
        self.padding = padding
        self.data_width = data_width
        
        # Calculate output length using same formula as Verilog
        self.output_length = self._calc_output_length()
        
        # Storage
        self.input_data = np.zeros((input_channels, temporal_length), dtype=np.int32)
        self.weights = np.zeros((filter_number, input_channels, kernel_size), dtype=np.int32)
        self.output = np.zeros((filter_number, self.output_length), dtype=np.int32)
        
    def _calc_output_length(self) -> int:
        """Calculate output length using Verilog formula"""
        numerator = self.temporal_length + (2 * self.padding) - self.kernel_size
        if numerator < 0:
            numerator = 0
        output_len = (numerator // self.stride) + 1
        return output_len
    
    def load_input_data(self, channel: int, data: List[int]):
        """
        Load input data for a channel
        
        Args:
            channel: Channel index (0 to input_channels-1)
            data: List of input values
        """
        assert channel < self.input_channels, f"Channel {channel} out of range"
        assert len(data) == self.temporal_length, f"Data length mismatch"
        self.input_data[channel, :] = data
        
    def load_input_data_from_testbench(self):
        """Load input data matching testbench pattern: channel*10 + position + 1"""
        for c in range(self.input_channels):
            for t in range(self.temporal_length):
                self.input_data[c, t] = c * 10 + t + 1
                
    def load_weights(self, filter_id: int, channel_id: int, weights: List[int]):
        """
        Load weights for a specific filter and channel
        
        Args:
            filter_id: Filter index (0 to filter_number-1)
            channel_id: Channel index (0 to input_channels-1)
            weights: List of kernel weights
        """
        assert filter_id < self.filter_number, f"Filter {filter_id} out of range"
        assert channel_id < self.input_channels, f"Channel {channel_id} out of range"
        assert len(weights) == self.kernel_size, f"Weight length mismatch"
        self.weights[filter_id, channel_id, :] = weights
        
    def load_weights_from_testbench(self):
        """Load weights matching testbench pattern: all weights = 1"""
        self.weights.fill(1)
        
    def compute_convolution(self):
        """
        Compute 1D convolution
        Matches hardware behavior: accumulate across all input channels
        """
        # Pad input if needed
        if self.padding > 0:
            padded_input = np.pad(self.input_data, 
                                  ((0, 0), (self.padding, self.padding)), 
                                  mode='constant', 
                                  constant_values=0)
        else:
            padded_input = self.input_data
            
        # For each filter
        for f in range(self.filter_number):
            # Reset output for this filter
            filter_output = np.zeros(self.output_length, dtype=np.int32)
            
            # Accumulate across all input channels
            for c in range(self.input_channels):
                # Convolve this channel with this filter's weights
                for out_idx in range(self.output_length):
                    # Calculate input position
                    in_pos = out_idx * self.stride
                    
                    # Accumulate over kernel
                    for k in range(self.kernel_size):
                        input_val = padded_input[c, in_pos + k]
                        weight_val = self.weights[f, c, k]
                        filter_output[out_idx] += input_val * weight_val
                        
            # Store final accumulated output
            self.output[f, :] = filter_output
            
    def get_output(self, filter_id: int) -> np.ndarray:
        """
        Get output for a specific filter
        
        Args:
            filter_id: Filter index
            
        Returns:
            Output array for the filter
        """
        return self.output[filter_id, :]
    
    def print_configuration(self):
        """Print model configuration"""
        print("=" * 60)
        print("1D Convolution Golden Model Configuration")
        print("=" * 60)
        print(f"Input Channels:    {self.input_channels}")
        print(f"Temporal Length:   {self.temporal_length}")
        print(f"Kernel Size:       {self.kernel_size}")
        print(f"Filter Number:     {self.filter_number}")
        print(f"Stride:            {self.stride}")
        print(f"Padding:           {self.padding}")
        print(f"Output Length:     {self.output_length}")
        print("=" * 60)
        
    def print_inputs(self):
        """Print input data"""
        print("\nInput Data:")
        print("-" * 60)
        for c in range(self.input_channels):
            print(f"Channel {c}: {self.input_data[c, :]}")
            
    def print_weights(self):
        """Print weight data"""
        print("\nWeights:")
        print("-" * 60)
        for f in range(self.filter_number):
            print(f"Filter {f}:")
            for c in range(self.input_channels):
                print(f"  Channel {c}: {self.weights[f, c, :]}")
                
    def print_outputs(self):
        """Print output data"""
        print("\nOutputs:")
        print("-" * 60)
        for f in range(self.filter_number):
            print(f"Filter {f}: {self.output[f, :]}")
            
    def verify_output(self, filter_id: int, expected: List[int], tolerance: int = 0) -> bool:
        """
        Verify output against expected values
        
        Args:
            filter_id: Filter to verify
            expected: Expected output values
            tolerance: Allowed difference (default 0)
            
        Returns:
            True if verification passes
        """
        actual = self.output[filter_id, :]
        expected_arr = np.array(expected)
        
        if len(expected_arr) != len(actual):
            print(f"ERROR: Length mismatch - Expected {len(expected_arr)}, Got {len(actual)}")
            return False
            
        diff = np.abs(actual - expected_arr)
        max_diff = np.max(diff)
        
        if max_diff > tolerance:
            print(f"ERROR: Max difference {max_diff} exceeds tolerance {tolerance}")
            print(f"Expected: {expected_arr}")
            print(f"Actual:   {actual}")
            print(f"Diff:     {diff}")
            return False
            
        print(f"✓ Filter {filter_id} verification PASSED (max diff: {max_diff})")
        return True


def run_testbench_example():
    """Run the same test as the Verilog testbench"""
    print("\n" + "=" * 60)
    print("Running Testbench Example")
    print("=" * 60)
    
    # Match testbench parameters
    model = Conv1DGoldenModel(
        input_channels=2,
        temporal_length=10,
        kernel_size=3,
        filter_number=2,
        stride=1,  # stride=0 in Verilog means 1
        padding=1
    )
    
    model.print_configuration()
    
    # Load data matching testbench
    # Input: channel*10 + position + 1
    model.load_input_data_from_testbench()
    
    # Weights: all 1s
    model.load_weights_from_testbench()
    
    model.print_inputs()
    model.print_weights()
    
    # Compute
    print("\nComputing convolution...")
    model.compute_convolution()
    
    model.print_outputs()
    
    # Show detailed calculation for first few outputs
    print("\n" + "=" * 60)
    print("Detailed Calculation (First Output Position)")
    print("=" * 60)
    
    # Output[0] for Filter 0:
    # Position 0, stride=1, padding=1
    # Input positions: -1 (padded=0), 0, 1
    # Channel 0: input[0,0]=1, input[0,1]=2, padded_left=0
    # Channel 1: input[1,0]=11, input[1,1]=12, padded_left=0
    # Filter 0 weights: all 1s
    
    print("\nFilter 0, Output Position 0:")
    print("  Kernel positions: -1, 0, 1 (with padding)")
    print("  Channel 0:")
    print("    pos=-1: 0 (padding) * 1 = 0")
    print("    pos=0:  1 * 1 = 1")
    print("    pos=1:  2 * 1 = 2")
    print("    Channel 0 sum: 0 + 1 + 2 = 3")
    print("  Channel 1:")
    print("    pos=-1: 0 (padding) * 1 = 0")
    print("    pos=0:  11 * 1 = 11")
    print("    pos=1:  12 * 1 = 12")
    print("    Channel 1 sum: 0 + 11 + 12 = 23")
    print("  Total (both channels): 3 + 23 = 26")
    print(f"  Computed: {model.output[0, 0]}")
    
    return model


def run_simple_test():
    """Run a simple verification test"""
    print("\n" + "=" * 60)
    print("Running Simple Verification Test")
    print("=" * 60)
    
    # Simple case: 1 channel, 1 filter, no padding
    model = Conv1DGoldenModel(
        input_channels=1,
        temporal_length=5,
        kernel_size=3,
        filter_number=1,
        stride=1,
        padding=0
    )
    
    # Input: [1, 2, 3, 4, 5]
    model.load_input_data(0, [1, 2, 3, 4, 5])
    
    # Weights: [1, 1, 1] (simple sum)
    model.load_weights(0, 0, [1, 1, 1])
    
    model.print_configuration()
    model.print_inputs()
    model.print_weights()
    
    model.compute_convolution()
    model.print_outputs()
    
    # Expected: [1+2+3, 2+3+4, 3+4+5] = [6, 9, 12]
    expected = [6, 9, 12]
    model.verify_output(0, expected)
    
    return model


if __name__ == "__main__":
    # Run testbench example
    model1 = run_testbench_example()
    
    print("\n" + "=" * 60)
    print("\n")
    
    # Run simple test
    model2 = run_simple_test()
    
    print("\n" + "=" * 60)
    print("All tests completed!")
    print("=" * 60)