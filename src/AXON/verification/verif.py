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
# 5) Print results for comparison
# -----------------------------
print("Input:", ifmap)
print("Weights:", weight_values)
print("Conv1d Output (batch, channels, length):")
print(output)
print("Output shape:", output.shape)
