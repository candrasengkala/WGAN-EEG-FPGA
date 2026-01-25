"""
1D Convolution Golden Model - Channel 0 Only
Matches the original testbench: channel*100 + position, weights all 1s
"""

import numpy as np
from typing import List, Tuple

class Conv1DGoldenModel:
    """Golden model for 1D convolution - only processes Channel 0"""
    
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
            input_channels: Number of input channels (stored, but only ch0 used)
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
        
        # Storage - keep full structure
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
        """Load input data matching testbench pattern: channel*100 + position"""
        for c in range(self.input_channels):
            for t in range(self.temporal_length):
                self.input_data[c, t] = c * 100 + t
                
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
        Compute 1D convolution - CHANNEL 0 ONLY
        Only convolves channel 0 with each filter (no accumulation across channels)
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
            # Only process channel 0
            c = 0  # Channel 0 only
            
            # Convolve channel 0 with this filter's weights for channel 0
            for out_idx in range(self.output_length):
                # Calculate input position
                in_pos = out_idx * self.stride
                
                # Accumulate over kernel
                accumulator = 0
                for k in range(self.kernel_size):
                    input_val = padded_input[c, in_pos + k]
                    weight_val = self.weights[f, c, k]  # Use filter's ch0 weights
                    accumulator += input_val * weight_val
                    
                # Store output
                self.output[f, out_idx] = accumulator
            
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
        print("1D Convolution Golden Model (Channel 0 Only)")
        print("=" * 60)
        print(f"Input Channels:    {self.input_channels} (only using channel 0)")
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
            marker = " ← USED" if c == 0 else " (ignored)"
            print(f"Channel {c}: {self.input_data[c, :]}{marker}")
            
    def print_weights(self):
        """Print weight data"""
        print("\nWeights:")
        print("-" * 60)
        for f in range(self.filter_number):
            print(f"Filter {f}:")
            for c in range(self.input_channels):
                marker = " ← USED" if c == 0 else " (ignored)"
                print(f"  Channel {c}: {self.weights[f, c, :]}{marker}")
                
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
    """Run the same test as the Verilog testbench - CHANNEL 0 ONLY"""
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
    # Input: channel*100 + position
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
    print("Detailed Calculation (Channel 0 Only)")
    print("=" * 60)
    
    print("\nChannel 0 input: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]")
    print("With padding=1: [0, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 0]")
    print("All weights: [1, 1, 1]")
    
    print("\nFilter 0, Output Position 0:")
    print("  Kernel at positions: -1, 0, 1")
    print("  0 (pad) * 1 + 0 * 1 + 1 * 1 = 0 + 0 + 1 = 1")
    print(f"  Computed: {model.output[0, 0]}")
    
    print("\nFilter 0, Output Position 1:")
    print("  Kernel at positions: 0, 1, 2")
    print("  0 * 1 + 1 * 1 + 2 * 1 = 0 + 1 + 2 = 3")
    print(f"  Computed: {model.output[0, 1]}")
    
    print("\nFilter 1 gives same result (weights are [1,1,1])")
    print(f"  Filter 1, Position 0: {model.output[1, 0]}")
    print(f"  Filter 1, Position 1: {model.output[1, 1]}")
    
    return model


if __name__ == "__main__":
    # Run testbench example
    model1 = run_testbench_example()
    
    print("\n" + "=" * 60)
    print("Test completed!")
    print("=" * 60)