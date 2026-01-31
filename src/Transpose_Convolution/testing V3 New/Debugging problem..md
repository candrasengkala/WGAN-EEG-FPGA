# Layer 3 Data Organization - Weight & Ifmap

## Overview
Layer 3 adalah **1D Transposed Convolution** dengan spesifikasi:
- **Input channels (K)**: 64
- **Output channels (OC)**: 16
- **Kernel size**: 4 (1D)
- **Input positions**: 256
- **Output positions**: 512
- **Stride**: 2

## WEIGHT DATA

### Weight .mem File Organization

**File**: `decoder_weight.mem` (offset: 212992)  
**Total words**: 4096 (16 OC × 16 K × 16 positions)  
**Format**: Increment per position dalam satu (OC, K) pair

```
Memory Layout: [Output Channel][Input Channel][Position]

Word 0-15:     Oc0,  k0,  Pos[0-15]
Word 16-31:    Oc0,  k1,  Pos[0-15]
Word 32-47:    Oc0,  k2,  Pos[0-15]
...
Word 240-255:  Oc0,  k15, Pos[0-15]  (Total 256 words untuk Oc0)

Word 256-271:  Oc1,  k0,  Pos[0-15]
Word 272-287:  Oc1,  k1,  Pos[0-15]
...
Word 496-511:  Oc1,  k15, Pos[0-15]  (Total 256 words untuk Oc1)

...

Word 3840-3855: Oc15, k0,  Pos[0-15]
Word 3856-3871: Oc15, k1,  Pos[0-15]
...
Word 4080-4095: Oc15, k15, Pos[0-15]  (Total 256 words untuk Oc15)
```

**Formula DDR Address**:
```
ddr_addr = offset + (oc × 256) + (k × 16) + position
```

Dimana:
- `oc`: Output channel index (0-15)
- `k`: Input channel index (0-15)
- `position`: Position dalam kernel (0-15)

### Target Weight BRAM Organization

**Total BRAMs**: 16  
**Depth per BRAM**: 1024  
**Used depth**: 256 (only first 256 addresses per BRAM)

**Organizational Strategy**: K-channel based distribution

```
BRAM 0:  Input channel k0  untuk semua Output Channels
BRAM 1:  Input channel k1  untuk semua Output Channels
BRAM 2:  Input channel k2  untuk semua Output Channels
...
BRAM 15: Input channel k15 untuk semua Output Channels
```

### BRAM 0 (k=0) Detailed Layout:

```
Address Range | Content
-------------- |--------------------------------------------------
0-63           | Oc0,  k0, Pos[0-63]
63-127         | Oc4,  k0, Pos[0-63]
128-191        | Oc8,  k0, Pos[0-63]
192-255        | Oc12, k0, Pos[0-63]
256-1023       | KOSONG
```

### BRAM 1 (k=1) Detailed Layout:

```
Address Range  | Content
-------------- |--------------------------------------------------
0-63           | Oc0,  k1, Pos[0-63]
63-127         | Oc4,  k1, Pos[0-63]
128-191        | Oc8,  k1, Pos[0-63]
192-255        | Oc12, k1, Pos[0-63]
256-1023       | KOSONG
```
### BRAM 2 (k=2) Detailed Layout:

```
Address Range  | Content
-------------- |--------------------------------------------------
0-63           | Oc0,  k2, Pos[0-63]
63-127         | Oc4,  k2, Pos[0-63]
128-191        | Oc8,  k2, Pos[0-63]
192-255        | Oc12, k2, Pos[0-63]
256-1023       | KOSONG
```

### BRAM 3 (k=3) Detailed Layout:

```
Address Range  | Content
-------------- |--------------------------------------------------
0-63           | Oc0,  k3, Pos[0-63]
63-127         | Oc4,  k3, Pos[0-63]
128-191        | Oc8,  k3, Pos[0-63]
192-255        | Oc12, k3, Pos[0-63]
256-1023       | KOSONG
```

### BRAM 4 (k=0) Detailed Layout:

```
Address Range  | Content
-------------- |--------------------------------------------------
0-63           | Oc1,  k0, Pos[0-63]
63-127         | Oc5,  k0, Pos[0-63]
128-191        | Oc9,  k0, Pos[0-63]
192-255        | Oc13, k0, Pos[0-63]
256-1023       | KOSONG
```
### BRAM 5 (k=1) Detailed Layout:

```
Address Range  | Content
-------------- |--------------------------------------------------
0-63           | Oc1,  k1, Pos[0-63]
63-127         | Oc5,  k1, Pos[0-63]
128-191        | Oc9,  k1, Pos[0-63]
192-255        | Oc13, k1, Pos[0-63]
256-1023       | KOSONG
```
### BRAM 6 (k=2) Detailed Layout:

```
Address Range  | Content
-------------- |--------------------------------------------------
0-63           | Oc1,  k2, Pos[0-63]
63-127         | Oc5,  k2, Pos[0-63]
128-191        | Oc9,  k2, Pos[0-63]
192-255        | Oc13, k2, Pos[0-63]
256-1023       | KOSONG
```
### BRAM 7 (k=3) Detailed Layout:

```
Address Range  | Content
-------------- |--------------------------------------------------
0-63           | Oc1,  k3, Pos[0-63]
63-127         | Oc5,  k3, Pos[0-63]
128-191        | Oc9,  k3, Pos[0-63]
192-255        | Oc13, k3, Pos[0-63]
256-1023       | KOSONG
```

### BRAM 8 (k=0) Detailed Layout:

```
Address Range  | Content
-------------- |--------------------------------------------------
0-63           | Oc2,  k0, Pos[0-63]
63-127         | Oc6,  k0, Pos[0-63]
128-191        | Oc10,  k0, Pos[0-63]
192-255        | Oc14, k0, Pos[0-63]
256-1023       | KOSONG
```

### BRAM 9 (k=0) Detailed Layout:

```
Address Range  | Content
-------------- |--------------------------------------------------
0-63           | Oc2,  k1, Pos[0-63]
63-127         | Oc6,  k1, Pos[0-63]
128-191        | Oc10,  k1, Pos[0-63]
192-255        | Oc14, k1, Pos[0-63]
256-1023       | KOSONG
```

### BRAM 16 (k=0) Detailed Layout:

```
Address Range  | Content
-------------- |--------------------------------------------------
0-63           | Oc3,  k3, Pos[0-63]
63-127         | Oc7,  k3, Pos[0-63]
128-191        | Oc11,  k3, Pos[0-63]
192-255        | Oc15, k3, Pos[0-63]
256-1023       | KOSONG
```



### BRAM 15 (k=15) Detailed Layout:

```
Address Range | Content
Address Range | Content
--------------|--------------------------------------------------
0-63          | Oc0,  k15, Pos[0-63]
63-127       | Oc4,  k15, Pos[0-63]
128-191      | Oc8,  k15, Pos[0-63]
192-255        | Oc12, k15, Pos[0-63]
256-1023       | KOSONG
```

### Weight Loading Logic

```verilog
for (k = 0; k < 16; k++) {              // Loop through all K-channels
    bram_target = k;                     // BRAM determined by K
    
    for (oc = 0; oc < 16; oc += 4) {    // Loop Oc0, Oc4, Oc8, Oc12
        
        for (pos = 0; pos < 16; pos++) { // 16 positions
            ddr_addr = offset + (oc × 256) + (k × 16) + pos;
            send_to_bram(weight_ddr_mem[ddr_addr]);
        }
    }
}
```

**Testbench Task**: `send_packet_weight_layer3(212992)`

---

## IFMAP DATA

### Ifmap .mem File Organization

**File**: `decoder_last_input_new.mem` (offset: 0, no offset)  
**Total words**: 16,384 (256 positions × 64 channels)  
**Format**: Increment per channel dalam satu position

```
Memory Layout: [Position][Channel]

Word 0-63:      Pos0,   Ch[0-63]    (64 words)
Word 64-127:    Pos1,   Ch[0-63]    (64 words)
Word 128-191:   Pos2,   Ch[0-63]    (64 words)
...
Word 16320-16383: Pos255, Ch[0-63]  (64 words)
```

**Formula DDR Address**:
```
ddr_addr = (position × 64) + channel
```

Dimana:
- `position`: Position index (0-255)
- `channel`: Channel index (0-63)

### Target Ifmap BRAM Organization

**Total BRAMs**: 16  
**Depth per BRAM**: 1024  
**Used depth**: 1024 (fully utilized)

**Organizational Strategy**: Strided position distribution

```
BRAM 0:  Positions 0, 16, 32, 48, ..., 240   (16 positions × 64 channels = 1024 words)
BRAM 1:  Positions 1, 17, 33, 49, ..., 241   (16 positions × 64 channels = 1024 words)
BRAM 2:  Positions 2, 18, 34, 50, ..., 242   (16 positions × 64 channels = 1024 words)
...
BRAM 15: Positions 15, 31, 47, 63, ..., 255  (16 positions × 64 channels = 1024 words)
```

**Stride**: 16 (setiap BRAM handle positions dengan stride 16)

### BRAM 0 Detailed Layout:

```
Address Range | Content
--------------|--------------------------------------------------
0-63          | Pos0,   Ch[0-63]   (position = 0 + 0×16)
64-127        | Pos16,  Ch[0-63]   (position = 0 + 1×16)
128-191       | Pos32,  Ch[0-63]   (position = 0 + 2×16)
192-255       | Pos48,  Ch[0-63]   (position = 0 + 3×16)
...
960-1023      | Pos240, Ch[0-63]   (position = 0 + 15×16)
```

### BRAM 1 Detailed Layout:

```
Address Range | Content
--------------|--------------------------------------------------
0-63          | Pos1,   Ch[0-63]   (position = 1 + 0×16)
64-127        | Pos17,  Ch[0-63]   (position = 1 + 1×16)
128-191       | Pos33,  Ch[0-63]   (position = 1 + 2×16)
...
960-1023      | Pos241, Ch[0-63]   (position = 1 + 15×16)
```

### BRAM 15 Detailed Layout:

```
Address Range | Content
--------------|--------------------------------------------------
0-63          | Pos15,  Ch[0-63]   (position = 15 + 0×16)
64-127        | Pos31,  Ch[0-63]   (position = 15 + 1×16)
128-191       | Pos47,  Ch[0-63]   (position = 15 + 2×16)
...
960-1023      | Pos255, Ch[0-63]   (position = 15 + 15×16)
```

### Ifmap Loading Logic

```verilog
for (bram_id = 0; bram_id < 16; bram_id++) {
    
    for (pos_group = 0; pos_group < 16; pos_group++) {
        // Calculate actual position with stride 16
        position = bram_id + (pos_group × 16);
        
        for (channel = 0; channel < 64; channel++) {
            ddr_idx = (position × 64) + channel;
            send_to_bram(ifmap_ddr_mem[ddr_idx]);
        }
    }
}
```

**Testbench Task**: `send_ifmap_layer3_stride16()`

---

## COMPARISON TABLE

| Aspect | Weight | Ifmap |
|--------|--------|-------|
| **MEM Layout** | `[OC][K][Pos]` | `[Pos][Ch]` |
| **BRAM Distribution** | By K-channel | By Position (stride 16) |
| **BRAM 0 Contains** | All OCs for k0 | Pos 0,16,32,...,240 for all Ch |
| **Words per BRAM** | 64 (4 OCs × 16 pos) | 1024 (16 pos × 64 ch) |
| **Total Words** | 1024 (16 BRAM × 64) | 16,384 (16 BRAM × 1024) |
| **MEM File Size** | 4096 words | 16,384 words |

---

## WHY THIS ORGANIZATION?

### Weight BRAM:
- **K-channel based**: Memudahkan systolic array mengakses semua K untuk satu OC
- **Oc-interleaved**: Karena hardware hanya proses 4 OCs per tile (Oc0,4,8,12)
- **Sparse filling**: Hanya 64 dari 1024 addresses terpakai per BRAM

### Ifmap BRAM:
- **Stride 16**: Distribusi merata ke 16 BRAMs untuk parallelism
- **Full utilization**: Semua 1024 addresses terpakai
- **Channel-complete**: Setiap position punya semua 64 channels

---

## VERIFICATION CHECKLIST

### Weight Loading:
- ✅ BRAM 0 berisi k0 untuk Oc0,4,8,12
- ✅ BRAM 1 berisi k1 untuk Oc0,4,8,12
- ✅ Formula: `ddr_addr = offset + (oc × 256) + (k × 16) + pos`
- ✅ Total words sent: 1024

### Ifmap Loading:
- ✅ BRAM 0 berisi Pos 0,16,32,...,240 dengan Ch0-63
- ✅ BRAM 1 berisi Pos 1,17,33,...,241 dengan Ch0-63
- ✅ Formula: `ddr_addr = (position × 64) + channel`
- ✅ Total words sent: 16,384

---

## NOTES

1. **Weight BRAM under-utilization**: Ini design choice karena hardware hanya process 1 tile (4 OCs) per batch. Untuk full 16 OCs, butuh 4 batch runs dengan weight reload.

2. **Ifmap stride 16**: Ini untuk balance load distribution. Alternatif bisa sequential (BRAM0=Pos0-15, BRAM1=Pos16-31, dll) tapi stride memberikan better parallelism.

3. **1D Convolution**: Kernel width = 4, tapi position dimension = 16 karena format data storage. Output akan 256 positions (input) → 512 positions (output) dengan stride 2.

---

Generated: 2026-01-30


ini probelmnya.  

=== TABEL OUTPUT DECODER D5 (16 KOLOM CHANNEL) ===
      Ch0    Ch1    Ch2    Ch3    Ch4    Ch5    Ch6    Ch7    Ch8    Ch9   Ch10   Ch11   Ch12   Ch13   Ch14   Ch15
0     542   3118      0      0      0      0  14353      0   6166      0      0      0   8610      0   9272   1178
1    4028      0      0      0   6802   2723      0  16135      0      0   8912   1737   2247      0   5095      0
2       0     77   3371      0      0      0      0   6726   8141  17284   8660  11176   6185  13750      0   6759
3    1284   4085   3929      0   7663  22960   4236   1625      0  12197   1547   9444      0    607      0  18617
4       0   1401      0      0      0  20650      0  13610      0   6170      0  13903  13441   4607      0      0
5       0      0   1375      0   3628   4286      0  12435      0  17411   5529      0      0    432      0   9314
6       0  12457      0      0   3583   9546   8232   4475  17584  16783   3392   5819      0   7724      0      0
7   13284  11652    709      0      0  10876      0   7137      0  12566      0   3204      0  14833  11071      0
8   13839  12257   8657   3851   1905      0      0    618      0  11251    469   8619   2988  12572      0      0
9       0      0      0      0      0      0      0   6836   1555      0   3471   7369   1583   4394      0      0
10  11470  17842   3518  21478      0  17317      0      0  13630   8220      0  10792   7469      0      0   9680

seharusnya output layer 3 itu seperti ini inis ay potong 10sja karena seharusnya ada 512 pos. 

=============================================================
Position |  Ch0  |  Ch1  |  Ch2  |  Ch3  |  Ch4  |  Ch5  |  Ch6  |  Ch7  |  Ch8  |  Ch9  | Ch10  | Ch11  | Ch12  | Ch13  | Ch14  | Ch15  |
---------|-------|-------|-------|-------|-------|-------|-------|-------|-------|-------|-------|-------|-------|-------|-------|-------|
     0   |  8668 | 11105 |  9106 | 20361 |  2122 |     0 |     0 |     0 |     0 |  7705 |     0 |     0 |     0 |  3382 |  1023 |     0 |
     1   | 11351 |     0 |     0 |     0 |     0 |     0 |     0 |     0 |  1628 |     0 |     0 |     0 |     0 |  1343 |  3461 |  1168 |
     2   |  8668 |  5957 |     0 |     0 |  2374 | 16130 |   492 |  1750 |     0 |     0 | 11233 |  8483 | 15125 | 30132 |     0 |     0 |
     3   |     0 |     0 |     0 |  2557 |     0 |     0 |     0 |  2080 |     0 |     0 |   678 |  8855 |     0 | 24136 | 19846 |     0 |
     4   |     0 |     0 |     0 |  1874 |     0 |  6344 |     0 |     0 |  7216 |  9096 | 11233 |  2798 |     0 |  1661 |     0 |     0 |
     5   |  6394 |   112 | 14859 |  2557 |     0 |  8479 |     0 |     0 |  4539 |     0 |  6860 |  8855 | 12299 |     0 | 22200 |  3761 |
     6   |     0 |  3747 |  2260 |   922 |     0 |     0 |  9888 |  4641 | 16087 |     0 |     0 |     0 |     0 |   614 |     0 |   358 |
     7   | 26808 |     0 |     0 |     0 |  8731 |  8479 |     0 |     0 | 13899 | 19679 |     0 |     0 |     0 |     0 |  1076 | 23028 |
     8   | 16519 | 14392 | 13634 |     0 |     0 | 26961 |  9888 |     0 |     0 |     0 |     0 |     0 |  3348 | 14693 |     0 |  3969 |
     9   |     0 |  2429 |     0 |     0 |     0 |     0 |  7541 |     0 |     0 |     0 |     0 |     0 |   547 |  6990 |     0 | 23028 |
    10   |     0 |     0 |     0 |  1567 | 16165 |     0 |     0 | 12946 | 36092 |  8353 | 16336 | 10208 | 27986 |     0 |     0 |     0 |
    11   | 57646 |  5662 | 12186 |  4249 |     0 |     0 |     0 |  1839 | 37417 | 51795 |  7495 | 10128 | 19253 | 20508 |     0 |     0 |

    namun yang saya dapat kan mala begini sangat berbeda jauh dari ahsil py toch sya tidak tau apakah load ifmap, load bram atau load bias saay yangsalah atau mungkin operasi saya yang salah temans ayamengatakan untuk  

    [10:08, 30/01/2026] Aryo W: y0 = b[0].item()
for cin in range(64):
    y0 += x[cin, 0].item() * W[cin, 0, 1].item()
[10:08, 30/01/2026] Aryo W: Coba cek dah, value pertama kalkulasinya kek gitu bukan
[10:09, 30/01/2026] Aryo W: W[cin, 0, 1], kernelnya pakai index 1 gegara padding, stride, ama kernel size

inicamkan note catat ini untuk pos 0 ch0. sebenarnya apa yang salah kenapa bisa beda jauh begitu atau mungkin scheduler say salah.


disini coba ceks cheduler saya untuk layer 3. ingat bahwa bram memangada 1024 tai untuk layer 3 bram sepertinya ahnya terisi 256 sperempatnya saja. dan ingat dibagi menjadi 4 tile. jadi 1 tile seharusnya 64 adress incre,etn. lau untuk scheduler ifmap layer 3 apakah benar. coba kamu lakukan pemeriksaan terlebih dahulu. mulai dari pahami testbench. lalu pahami scheduer, lalu pahami mapper, lau cek apakah ada latency pada accumualtion unti dan lain lain. 