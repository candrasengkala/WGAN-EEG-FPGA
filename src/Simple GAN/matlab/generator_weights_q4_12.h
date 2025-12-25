#ifndef GENERATOR_WEIGHTS_Q4_12_H
#define GENERATOR_WEIGHTS_Q4_12_H

// Q4.12 Fixed-Point Format
// 16-bit signed: 1 sign + 3 integer + 12 fractional
#include <stdint.h>

#define FRAC_BITS 12
#define INT_BITS 3
#define SCALE_FACTOR (1 << FRAC_BITS)  // 4096

// Layer 1 Weight: 3x2
const int16_t Wg2[3][2] = {
    {0x0075, 0x010B},
    {0x02B3, 0x0071},
    {0xFC83, 0xFDF6}
};

// Layer 1 Bias: 3x1
const int16_t bg2[3] = {0x070F, 0x0328, 0xFE3D};

// Layer 2 Weight: 9x3
const int16_t Wg3[9][3] = {
    {0xFF46, 0xFFA8, 0x00CD},
    {0x02C0, 0x00C8, 0x0119},
    {0x058A, 0x024C, 0x0135},
    {0x064F, 0x030A, 0xFF1E},
    {0xFDBB, 0x0238, 0x0081},
    {0x06C0, 0x01DE, 0xFE58},
    {0x013A, 0xFE19, 0x0168},
    {0x021E, 0x0214, 0xFDB0},
    {0x0113, 0x0294, 0xFE4D}
};

// Layer 2 Bias: 9x1
const int16_t bg3[9] = {0xFE21, 0x091E, 0x0056, 0x08EF, 0xFF06, 0x0966, 0xFFA3, 0x0B26, 0xFFF4};

#endif // GENERATOR_WEIGHTS_Q4_12_H
