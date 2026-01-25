import numpy as np

Dimension = 16

# Create matrices
A = np.zeros((Dimension, Dimension), dtype=int)
B = np.ones((Dimension, Dimension), dtype=int)

# Equivalent to Verilog initialization
for r in range(Dimension):
    for c in range(Dimension):
        A[r, c] = r * Dimension + c + 1

# Matrix multiplication
Y = B @ A

print("Matrix A:")
print(A)

print("\nMatrix B:")
print(B)

print("\nResult Y = A x B:")
print(Y)
