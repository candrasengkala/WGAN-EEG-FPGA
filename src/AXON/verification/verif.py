import torch
import torch.nn as nn

# -----------------------------
# 1) Define your input
# -----------------------------
# shape: (batch=1, in_channels=1, length=10)
ifmap = torch.tensor(
    [[
        [5, 5, 4, 8, 7, 6, 5, 4, 3, 2]
    ]], dtype=torch.float32
)

# -----------------------------
# 2) Create Conv1d layer
# -----------------------------
# in_channels=1, out_channels=4, kernel_size=4, stride=2, no bias
conv = nn.Conv1d(in_channels=1, out_channels=4, kernel_size=4, stride=2, bias=False)

# -----------------------------
# 3) Assign your specific weights
#    PyTorch stores weights as:
#    shape (out_channels, in_channels, kernel_size)
# -----------------------------
with torch.no_grad():
    # define the weight values
    weight_values = torch.tensor([
        [[1, 2, 3, 4]],   # filter 1
        [[2, 3, 4, 5]],   # filter 2
        [[3, 4, 3, 2]],   # filter 3
        [[4, 3, 2, 4]],   # filter 4
    ], dtype=torch.float32)

    conv.weight.copy_(weight_values)

# -----------------------------
# 4) Run the convolution
# -----------------------------
output = conv(ifmap)

# -----------------------------
# 5) Print results per output channel
# -----------------------------
print("Input:", ifmap)
print("\nWeights:", weight_values)
print("\nOutput shape:", output.shape)
print("\n" + "="*50)
print("Output per channel:")
print("="*50)

# Extract and display each output channel separately
for channel_idx in range(output.shape[1]):
    channel_output = output[0, channel_idx, :]
    print(f"\nChannel {channel_idx} (Filter {channel_idx+1}):")
    print(f"  Values: {channel_output.tolist()}")
    print(f"  Tensor: {channel_output}")

print("\n" + "="*50)
print("Complete output tensor:")
print(output)