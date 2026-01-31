# Final 1D Convolution Layer Implementation

## Overview
This modification adds support for the final 1D convolution layer (Layer 9) that occurs after the transposed convolution decoder, matching the PyTorch architecture where there's a final `nn.Conv1d` output layer.

## Architecture Flow
The system now performs three sequential processing stages:

1. **CONV Encoder** (Layers 0-8): Initial encoding convolution layers
2. **TRANSCONV Decoder** (Layers 0-3): Transposed convolution decoder layers  
3. **CONV Final Output** (Layer 9): Final 1D convolution to produce output

## Modified Files

### 1. Onedconv_Scheduler_FSM.v
**Changes:**
- Extended layer ROM arrays from 9 to 10 layers (0-9)
- Added Layer 9 configuration matching the PyTorch final conv layer:
  - Input channels: 16 (base_ch // 2, where base_ch = 32)
  - Output channels: 1 (single output channel)
  - Kernel size: 7
  - Stride: 1
  - Padding: 3
  - Temporal length: 512 (matches output size after decoder)

**Layer 9 Configuration:**
```verilog
ROM_INPUT_CHANNELS[9] = 10'd16;   ROM_STRIDE[9] = 2'd1;
ROM_TEMPORAL[9] = 10'd512;        ROM_FILTERS[9] = 10'd1;
ROM_KERNEL[9] = 5'd7;             ROM_PADDING[9] = 3'd3;
```

### 2. Onedconv_Auto_Scheduler.v
**Changes:**
- Updated `NUM_LAYERS` from 9 to 10
- Updated documentation to reflect 10-layer sequencing
- System now sequences through all 10 layers (0-9)

### 3. Conv_Transconv_System_Top_Level.v
**Major Changes:**

#### a) Three-Stage Processing State Machine
Added `processing_stage` register to track the current stage:
- `2'd0`: CONV Encoder (layers 0-8)
- `2'd1`: TRANSCONV Decoder (layers 0-3)
- `2'd2`: CONV Final Output (layer 9)

#### b) Mode Control Logic
The system now transitions through three stages:
1. **Stage 0 → Stage 1**: When encoder completes (layers 0-8), switch to TRANSCONV mode
2. **Stage 1 → Stage 2**: When decoder completes (layers 0-3), switch back to CONV mode for layer 9
3. **Stage 2**: Final layer processing

#### c) Edge Detection
Added two pulse detectors:
- `conv_encoder_done_pulse`: Detects completion of layers 0-8
- `transconv_done_pulse`: Detects completion of transconv layers 0-3

#### d) Sequence Completion
Updated `sequence_complete` signal:
```verilog
assign sequence_complete = (processing_stage == 2'd2) && conv_global_done;
```
Now only asserts when all three stages are complete.

#### e) New Status Outputs
Added `processing_stage[1:0]` output port to allow external monitoring of which processing stage is active.

#### f) Debug Messages
Enhanced debug displays to show transitions between all three stages:
- "CONV ENCODER COMPLETE - Layers 0-8 done"
- "TRANSCONV DECODER COMPLETE - Layers 0-3 done"  
- "Transitioning to CONV Final Output (layer 9)"

## Matching PyTorch Architecture

The PyTorch model has:
```python
self.out = nn.Conv1d(base_ch//2, 1, kernel_size=7, stride=1, padding=3, bias=bias)
```

This maps to Layer 9 in Verilog:
| Parameter | PyTorch | Verilog Layer 9 |
|-----------|---------|-----------------|
| Input Channels | base_ch//2 (16) | 16 |
| Output Channels | 1 | 1 |
| Kernel Size | 7 | 7 |
| Stride | 1 | 1 |
| Padding | 3 | 3 |
| Input Length | 512 | 512 |

## Data Flow

```
Input (512 samples)
    ↓
[CONV Encoder: Layers 0-8]
    ↓ (32 samples, 256 channels)
[TRANSCONV Decoder: Layers 0-3]
    ↓ (512 samples, 16 channels)
[CONV Final: Layer 9]
    ↓
Output (512 samples, 1 channel)
```

## Testing Considerations

1. **Stage Monitoring**: Use the new `processing_stage` output to verify correct stage transitions
2. **Layer Sequencing**: Ensure layer 9 starts only after transconv completes
3. **Data Sizing**: Verify that transconv output (16 channels, 512 temporal) matches layer 9 input expectations
4. **Completion Signal**: Check that `sequence_complete` only asserts after layer 9 completes

## Key Benefits

1. **Complete Architecture Match**: Now fully implements the PyTorch U-Net structure
2. **Automatic Sequencing**: No manual intervention needed - system automatically progresses through all stages
3. **Visibility**: New status outputs allow monitoring of processing progress
4. **Robustness**: Proper edge detection ensures clean transitions between stages
