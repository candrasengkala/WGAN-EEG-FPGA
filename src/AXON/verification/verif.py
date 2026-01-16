import numpy as np

# Weight matrix (4x4)
W = np.array([
    [ 1,  2,  3,  4],
    [ 5,  6,  7,  8],
    [ 9, 10, 11, 12],
    [13, 14, 15, 16]
], dtype=int)

# Ifmap matrix (4x4)
I = np.array([
    [ 1,  1,  -1,  0],
    [ 4,  2,  2, 0],
    [ 5,  1,  0, 0],
    [ 0,  1,  0,  -7]
], dtype=int)

# Matrix multiplication
C = I @ W

print("Weight matrix (W):")
print(W)
print("\nIfmap matrix (I):")
print(I)
print("\nResult (W @ I):")
print(C)
# [[  26    9   11  -33]
#  [  74   29   35  -77]
#  [ 122   49   59 -121]
#  [ 170   69   83 -165]]