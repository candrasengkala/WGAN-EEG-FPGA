# TRANSCONV Data Reception Flow Analysis

## Current Data Reception Flow

### **CURRENT ARCHITECTURE (Independent Parallel Streams)**

```
PS Software (Zynq ARM)
     │
     ├─────────────────────────────────┬─────────────────────────────────┐
     │                                 │                                 │
     ▼ DMA MM2S Stream 0                ▼ DMA MM2S Stream 1                │
┌─────────────────────────┐      ┌─────────────────────────┐              │
│ AXI Stream 0            │      │ AXI Stream 1            │              │
│ (Weight Load)           │      │ (Ifmap/Input Load)      │              │
│ s0_axis_tdata/tvalid    │      │ s1_axis_tdata/tvalid    │              │
│ s0_axis_tlast           │      │ s1_axis_tlast           │              │
└───────────┬─────────────┘      └───────────┬─────────────┘              │
            │                                │                            │
            ▼                                ▼                            │
     ┌──────────────────────────────────────────────────────┐             │
     │   axis_control_wrapper (Weight)                      │             │
     │   ┌─────────────────────────────────────────────┐    │             │
     │   │ axi_header_parser                           │    │             │
     │   │  Receives 6-word header:                    │    │             │
     │   │   - Word 0: Magic (0xC0DE)                  │    │             │
     │   │   - Word 1: Instruction code                │    │             │
     │   │   - Word 2: BRAM start index                │    │             │
     │   │   - Word 3: BRAM end index                  │    │             │
     │   │   - Word 4: Start address                   │    │             │
     │   │   - Word 5: Data count                      │    │             │
     │   └─────────────────────────────────────────────┘    │             │
     │         ▼                                             │             │
     │   axis_custom_top                                    │             │
     │   (Distribute to BRAM slices based on header)        │             │
     │         ▼                                             │             │
     │   weight_wr_data_flat                                │             │
     │   weight_wr_addr                                     │             │
     │   weight_wr_en[15:0]  (one enable per BRAM)          │             │
     │         ▼                                             │             │
     └──────────────────────────────────────────────────────┘             │
            │                                                             │
            ▼                                    ┌──────────────────────────────────┐
     ┌────────────────────────────────┐         │   axis_control_wrapper (Ifmap)   │
     │  Weight BRAM Block              │         │  (Identical structure)           │
     │  ┌──────┬──────┬──────┐ ┌──────┐         │  Parses header → distributes      │
     │  │BRAM 0│BRAM 1│ ... │ │BRAM15│         │  ifmap data to BRAM slices       │
     │  └──────┴──────┴──────┘ └──────┘         │         ▼                        │
     │  Address width: 11 bits (2K entries)      │  ifmap_wr_data_flat              │
     │  Each BRAM: 16-bit × 2048                │  ifmap_wr_addr                   │
     │  Total: 16 × 16-bit × 2K = 512 Kb       │  ifmap_wr_en[15:0]               │
     └────────────────────────────────┘         │         ▼                        │
            │                                    │  Ifmap BRAM Block                │
            │ weight_write_done                  │  ┌──────┬──────┬──────┐ ┌──────┐│
            │ (signal HIGH when done)            │  │BRAM 0│BRAM 1│ ... │ │BRAM15││
            │                                    │  └──────┴──────┴──────┘ └──────┘│
            │                                    │  Address width: 10 bits (1K)     │
            │                                    │  Each BRAM: 16-bit × 1024        │
            │                                    │  Total: 16 × 16-bit × 1K = 256Kb│
            │                                    │         ▼                        │
            │                                    │  ifmap_write_done                │
            │                                    │  (signal HIGH when done)          │
            │                                    └──────────────────────────────────┘
            │
            ▼
     ┌──────────────────────────────────────────────────────────┐
     │           AUTO_SCHEDULER                                 │
     │                                                           │
     │  Logic: Wait for BOTH signals to be HIGH                │
     │  ├─ Detects weight_write_done posedge                   │
     │  ├─ Detects ifmap_write_done posedge                    │
     │  ├─ If BOTH together = NEW LAYER                         │
     │  ├─ If only one followed by other = new batch           │
     │  └─ Generates final_start_signal when both ready        │
     │                                                           │
     │  current_batch_id (0-7 or 0-3 depending on layer)       │
     │  current_layer_id (0-3)                                 │
     │  final_start_signal → Scheduler_FSM                      │
     └──────────────────────────────────────────────────────────┘
```

**Key Points:**
- ✅ Weight & Ifmap loads are **INDEPENDENT** 
- ✅ Both can happen in ANY order
- ✅ Both can happen in PARALLEL (different AXI streams)
- ✅ Auto_Scheduler waits for BOTH to complete before starting

---

## Proposed Flow: "Input First, Then Weights"

### **QUESTION: Is this applicable?**

**Short Answer:** ✅ **YES, it is applicable** under the current AXI interfaces, but requires **SOFTWARE changes only** (no hardware changes).

### **How to Implement "Input First, Then Weights" Protocol**

The current hardware supports any load order because:

1. **Independent BRAM systems:** Weight and Ifmap have separate BRAMs, separate AXI wrappers, separate write ports
2. **Independent AXI streams:** Stream 0 (weights) and Stream 1 (ifmap) are completely decoupled
3. **Auto_Scheduler waits for both:** Regardless of which arrives first, scheduler waits for BOTH signals

### **Implementation Strategy**

```
PS Software Timeline for "Input First, Then Weights" Protocol:

Clock  | PS Action                          | AXI Stream | BRAM | Signal State
-------|------------------------------------|-----------┼──────┼─────────────
   0   | Start                              |           |      | 
       |                                    |           |      |
  100  | Send Ifmap Header (6 words)        | Stream 1  | I    | 
       | Header: BRAM range, addresses      | (active)  |      |
       |                                    |           |      |
  200  | Send Ifmap Data (N words)          | Stream 1  | I    | 
       | Assert TLAST on last word          | (active)  |      |
       |                                    |           |      |
  250  | Ifmap load complete                | Stream 1  | I    | ifmap_write_done = 1
       | Parser detects TLAST, signals done | (idle)    |      | ↑ posedge
       |                                    |           |      |
  300  | WAIT (optional, system is ready)   | (both)    | I    | 
       |                                    | (idle)    |      | weight_write_done = 0
       |                                    |           |      |
  350  | Send Weight Header (6 words)       | Stream 0  | W    | 
       | Header: BRAM range, addresses      | (active)  |      |
       |                                    |           |      |
  450  | Send Weight Data (M words)         | Stream 0  | W    | 
       | Assert TLAST on last word          | (active)  |      |
       |                                    |           |      |
  550  | Weight load complete               | Stream 0  | W    | weight_write_done = 1
       | Parser detects TLAST, signals done | (idle)    |      | ↑ posedge
       |                                    |           |      |
  551  | AUTO_SCHEDULER detects BOTH HIGH   |           | W+I  |
       | ├─ ifmap_write_done = 1 (from t250)           |      |
       | ├─ weight_write_done = 1 (NOW)                |      |
       | └─ Generates final_start_signal = 1           |      |
       |                                    |           |      |
  552  | Scheduler_FSM starts processing    |           | W+I  | Processing...
       |                                    |           |      |
```

**Result:** Computation starts only when BOTH are ready ✓

---

## Compatibility Check: Can Current Hardware Support "Input First, Then Weights"?

### **✅ YES - No Hardware Modifications Needed**

| Aspect | Current Hardware | "Input First" Protocol | Compatible? |
|--------|------------------|----------------------|-------------|
| **AXI Streams** | 2 independent streams (weight, ifmap) | Supports sending ifmap first, weight later | ✅ YES |
| **BRAM Writes** | Separate write ports per BRAM block | Ifmap writes to its BRAMs, weight writes to its BRAMs | ✅ YES |
| **Header Parser** | Generic 6-word header parser | Doesn't care about order | ✅ YES |
| **Auto_Scheduler** | Waits for BOTH signals | Works regardless of order | ✅ YES |
| **Data Organization** | Data organized by instruction header | Header specifies destination BRAM range | ✅ YES |

### **What DOES need to change:**

**PS Software ONLY:**
1. Send ifmap packet (header + data) first
2. Wait for `ifmap_write_done` signal (or just wait, hardware doesn't care)
3. Send weight packet (header + data) second
4. Hardware automatically triggers processing when both are loaded

---

## Detailed Example: "Input First, Then Weights" Sequence

```
┌─────────────────────────────────────────────────────────────────────┐
│ PS Software Pseudocode: Load Ifmap, Then Weights                   │
└─────────────────────────────────────────────────────────────────────┘

function load_layer_data(layer_id, input_data[], weight_data[]) {
    
    // STEP 1: Send Input/Ifmap Data FIRST
    // ────────────────────────────────────
    send_axi_packet(
        stream = STREAM_1,           // Stream 1 = Ifmap
        magic = 0xC0DE,
        instruction = LOAD_IFMAP,
        bram_start = 0,
        bram_end = 15,
        addr_start = 0,
        data_count = len(input_data),
        payload = input_data[]
    );
    
    // Check if load is complete (optional, can skip if timing is OK)
    wait_for_status(IFMAP_WRITE_DONE);  // or just wait 100 cycles
    
    // STEP 2: Send Weight Data SECOND
    // ────────────────────────────────
    send_axi_packet(
        stream = STREAM_0,           // Stream 0 = Weight
        magic = 0xC0DE,
        instruction = LOAD_WEIGHT,
        bram_start = 0,
        bram_end = 15,
        addr_start = 0,
        data_count = len(weight_data),
        payload = weight_data[]
    );
    
    // STEP 3: Hardware Automatically Starts
    // ──────────────────────────────────────
    // Auto_Scheduler detects both signals → triggers processing
    // NO SOFTWARE INTERVENTION NEEDED!
}
```

---

## Hardware Signal Flow for "Input First" Scenario

```
                    Ifmap Loaded First          Weight Loaded Second
                    ─────────────────           ───────────────────

Time    ifmap_write_done  weight_write_done     Auto_Scheduler State
 ───    ────────────────  ─────────────────     ────────────────────
  0         0                  0                 IDLE (waiting for both)
            
 250        ▔▔▔▔▔▔▔▔▔▔▔▔▔▔   0                 Ifmap loaded, weight waiting
  ─ ┐       (HIGH)                              IDLE (waiting for weight)
    │
 550        ▔▔▔▔▔▔▔▔▔▔▔▔▔▔   ▔▔▔▔▔▔▔▔▔▔▔▔▔▔    Both signals HIGH!
  ─ ┴       (still HIGH)      (HIGH)             
    
    ┌─ POSEDGE on weight_write_done detected
    │
    └─→ Auto_Scheduler generates final_start_signal = 1
        ↓
        Scheduler_FSM starts processing with:
        - current_layer_id = layer_id_from_header
        - current_batch_id = 0
        - ifmap_addr_base = from ifmap header
        - weight_addr_base = from weight header
```

---

## Multi-Batch Scenario with "Input First" Protocol

### **Layer with 8 Batches (Layer 0 - D1)**

```
Batch 0:
  t=100:  Send Ifmap (all 8 batches in one go)
  t=250:  ifmap_write_done = 1  ──┐
                                  ├─→ Both ready → START
  t=350:  Send Weight Batch 0  ──┤
  t=450:  weight_write_done = 1 ◄┴──→ START Processing
  
  (Processing... Batch 0 complete after N cycles)
  
  Batch 1:
  t=X00:  Send Weight Batch 1 only (Ifmap already loaded)
  t=X50:  weight_write_done = 1 ──→ START Batch 1
  
  Batch 2-7:
  Same pattern as Batch 1 (only weights change)
```

**Key Point:** Ifmap sent ONCE upfront, weight changes per batch ✓

---

## Alternative Protocols Supported

The current hardware can support ANY of these:

| Protocol | Sequence | Current Support |
|----------|----------|-----------------|
| **Weights First** | Send weight → Send ifmap | ✅ YES |
| **Input First** | Send ifmap → Send weight | ✅ YES |
| **Parallel** | Send both simultaneously on different streams | ✅ YES (streams are independent) |
| **Interleaved** | Send weight₁ → ifmap₁ → weight₂ → ifmap₂ | ✅ YES (Auto_Scheduler waits for both) |
| **Bulk** | Send all ifmaps → all weights | ✅ YES |

---

## Code Modification Required

### **Hardware:** ❌ NO CHANGES NEEDED

The current AXI & Auto_Scheduler design is **protocol-agnostic**. It works with any load order.

### **Software (PS):** ✅ MODIFY LOAD SEQUENCE

Currently (hypothetical example):
```c
// Load weights and inputs in parallel or random order
load_weights(STREAM_0, weight_data);
load_ifmaps(STREAM_1, ifmap_data);
```

New (Input First Protocol):
```c
// Load inputs FIRST
load_ifmaps(STREAM_1, ifmap_data);
wait_for_status(IFMAP_WRITE_DONE);  // Optional

// Then load weights
load_weights(STREAM_0, weight_data);
// Hardware auto-triggers when both signals are HIGH
```

---

## Signal Timing Constraints

For "Input First" protocol to work optimally:

```
Requirement 1: Input must fully load before processing starts
  └─ Hardware ensures this automatically (waits for both signals)

Requirement 2: Weight data must arrive before output is needed
  └─ Hardware ensures this (weights are loaded per-batch)

Requirement 3: BRAMs must not overflow
  └─ Set correctly via header (BRAM indices, address ranges)
  └─ Current constraints:
     - Weight BRAM: 2048 entries × 16 banks
     - Ifmap BRAM: 1024 entries × 16 banks
```

---

## Summary & Recommendation

| Question | Answer | Impact |
|----------|--------|--------|
| Can we use "Input First, Then Weights"? | ✅ YES | Improves data locality, reduces context switching |
| Do we need hardware changes? | ❌ NO | Current AXI architecture is protocol-agnostic |
| What changes? | ✅ Software only | Modify PS DMA sequence in application code |
| Is it backward compatible? | ✅ YES | Can still use weights-first or parallel loading |
| Performance benefit? | ✅ POSSIBLE | Depends on DMA timing; could reduce memory contention |

**Recommendation:** 
1. The "Input First, Then Weights" protocol is **fully supported** by current hardware
2. Implement in PS software layer
3. No RTL changes needed
4. Consider testing both orders to find optimal DMA schedule for your use case
