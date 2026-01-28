# Auto_Scheduler AXI Interaction Analysis

## System Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          PS (Processing System)                              │
│                       (Zynq / Microblaze)                                    │
│                   Sends Weight & Input Data via DMA                          │
└────────────────────┬──────────────────────────────────────────────────────┬──┘
                     │ MM2S (Memory-Mapped to Stream)                │ S2MM
                     │                                               │
        ┌────────────▼──────────────┐            ┌──────────────────▼────────┐
        │  AXI Stream 0 (Weights)   │            │  AXI Stream 1 (Ifmap)     │
        │  s0_axis_tdata/tvalid     │            │  s1_axis_tdata/tvalid     │
        │  s0_axis_tlast            │            │  s1_axis_tlast            │
        └────────────┬──────────────┘            └──────────────┬────────────┘
                     │                                          │
        ┌────────────▼──────────────────────────────────────────▼────────────┐
        │           axis_control_wrapper (Weight)    axis_control_wrapper (Ifmap)    │
        │                                                                       │
        │  • Receives AXI Stream data                                         │
        │  • Parses 6-word header (instruction, BRAM select, addr, count)     │
        │  • Writes payload to Weight/Ifmap BRAMs                             │
        │  • Signals completion via status wires                              │
        └─────────────┬────────────────────────────────────────┬──────────────┘
                      │                                         │
                      │ weight_write_done                       │ ifmap_write_done
                      │ (posedge = data loaded)                 │ (posedge = data loaded)
                      │                                         │
        ┌─────────────▼─────────────────────────────────────────▼──────────┐
        │              AUTO_SCHEDULER (Controller Module)                    │
        │                                                                    │
        │  INPUT:  weight_write_done, ifmap_write_done                      │
        │          ext_scheduler_start (optional manual trigger)             │
        │          external_layer_id (optional layer selection)              │
        │                                                                    │
        │  LOGIC:  Detects posedge on weight & ifmap completion signals    │
        │          Manages multi-batch and multi-layer state machine         │
        │          Generates start pulse when both data is ready             │
        │                                                                    │
        │  OUTPUT: final_start_signal → Scheduler_FSM                        │
        │          current_layer_id → Status output                          │
        │          current_batch_id → Status output                          │
        │          clear_output_bram → Reset accumulator BRAM               │
        │          all_batches_complete → Done signal                        │
        └─────────────┬──────────────────────────────────────────────────────┘
                      │ final_start_signal
                      │ (OR'd with ext_scheduler_start)
                      │
        ┌─────────────▼──────────────────────────────────────────────────┐
        │          Scheduler_FSM (Main State Machine)                    │
        │                                                                 │
        │  Receives: final_start_signal, layer_id, batch_id              │
        │  Controls: Weight & Ifmap address generators & enables         │
        │  Manages: PE pipeline, accumulator, output storage             │
        └─────────────┬──────────────────────────────────────────────────┘
                      │
        ┌─────────────▼────────────────────────────────────────────┐
        │        Weight/Ifmap BRAMs & PE Array / Datapath          │
        │                                                           │
        │  Processes data using generated addresses and enables     │
        └───────────────────────────────────────────────────────────┘
```

---

## **HOW Auto_Scheduler Interacts with AXI**

### **1. INPUTS from AXI Wrappers**

```verilog
input  wire  weight_write_done,    // From axis_control_wrapper (Weight)
input  wire  ifmap_write_done,     // From axis_control_wrapper (Ifmap)
```

**What they do:**
- `weight_write_done`: Goes HIGH when the AXI weight wrapper finishes writing data to the Weight BRAM
- `ifmap_write_done`: Goes HIGH when the AXI ifmap wrapper finishes writing data to the Ifmap BRAM
- These signals transition from LOW → HIGH (posedge) when DMA transfer completes

**Auto_Scheduler detection logic:**
```verilog
wire weight_done_posedge = weight_write_done & ~weight_write_done_prev;
wire ifmap_done_posedge = ifmap_write_done & ~ifmap_write_done_prev;

// Both signals together = NEW LAYER DATA IS READY
wire both_loaded_together = ifmap_done_posedge & weight_done_posedge;
```

---

### **2. State Machine Driven by AXI Signals**

The module contains a **5-state FSM** that responds to AXI completion:

| State | Triggered By | Action |
|-------|--------------|--------|
| **BATCH_IDLE** | Both `ifmap_loaded` AND `weight_loaded` | → BATCH_RUNNING (start computation) |
| **BATCH_RUNNING** | `batch_complete_signal` from Scheduler | Check if more batches needed |
| **BATCH_WAIT_RELOAD** | `weight_done_posedge` (new weight data) | → BATCH_RUNNING (next batch) |
| **BATCH_ALL_DONE** | All batches for layer complete | Await new layer data from AXI |

**Key insight:** The state machine is **data-driven**:
- Waits for AXI wrappers to signal completion
- Only transitions to RUNNING when both weight & ifmap are loaded
- Returns to IDLE/WAIT states when more data is needed

---

### **3. Multi-Batch & Multi-Layer Coordination**

**Layer Detection (AXI-triggered):**
```verilog
// When BOTH signals pulse together = new layer from PS
if (both_loaded_together && batch_state == BATCH_IDLE) begin
    current_layer_id <= current_layer_id + 2'd1;
    layer_changed <= 1'b1;  // Pulse
end
```

**Batch Counting:**
- Layer 0 (D1): 8 batches (requires 1 initial weight + 7 weight reloads from AXI)
- Layer 1 (D2): 4 batches (requires 1 initial weight + 3 weight reloads from AXI)

**Example timeline:**
```
Clock | AXI Action              | Auto_Sched State | Output
------|-------------------------|------------------|------------------
  10  | Weight write completes  | ifmap_loaded=0   | (waiting)
      | weight_write_done=1     |                  |
------|-------------------------|------------------|------------------
  20  | Ifmap write completes   | both loaded      | 
      | ifmap_write_done=1      |                  |
------|-------------------------|------------------|------------------
  21  | (Both signals HIGH)      | BATCH_IDLE →     | final_start_signal=1
      | Both posedges detected   | BATCH_RUNNING    | (triggers Scheduler)
------|-------------------------|------------------|------------------
  50  | Scheduler reports       | (still RUNNING)  |
      | 1st batch done          |                  |
------|-------------------------|------------------|------------------
  60  | PS sends more weight    | BATCH_WAIT_      | (waiting for next)
      | via DMA (next batch)    | RELOAD           |
------|-------------------------|------------------|------------------
  80  | AXI weight done         | weight_done_     | final_start_signal=1
      | weight_write_done=1     | posedge detected | (2nd batch starts)
      |                         | → BATCH_RUNNING  |
```

---

### **4. Output Signal to Control Datapath**

```verilog
assign final_start_signal = ext_scheduler_start | batch_auto_start;
```

**This is sent to Scheduler_FSM:**
- `final_start_signal` tells the main scheduler when to BEGIN processing
- Scheduler can only start when **both** weight and ifmap data are available from AXI

---

### **5. AXI Header Protocol (in axis_control_wrapper)**

The AXI wrappers use a **packet-based protocol**:

```
Word 0: Magic number (validation)
Word 1: Instruction code
Word 2-3: BRAM select & address range
Word 4-5: Data count
Words 6+: Actual data payload
```

When PS wants to load weights:
1. PS sends 6-word header via DMA (MM2S)
2. axis_control_wrapper parses header
3. PS sends N data words
4. When all data written to BRAM, wrapper asserts `write_done`
5. Auto_Scheduler detects this signal
6. Auto_Scheduler generates start pulse

---

## **Data Flow Sequence Diagram**

```
PS (Software)          DMA/AXI            axis_control_wrapper   Auto_Scheduler   Scheduler_FSM
    │                   │                        │                      │              │
    ├─ Start ─ MM2S ───→ │                        │                      │              │
    │  Weight via        │                        │                      │              │
    │  DMA              │──────────────────→ Receive + Parse              │              │
    │                   │                   Write to BRAM                │              │
    │                   │                        │                      │              │
    │                   │                        ├─ weight_write_done ─→ │              │
    │                   │                        │  (signal HIGH)         │              │
    │                   │                        │                      │ (detect)     │
    ├─ Start ─ MM2S ───→ │                        │                      │ posedge      │
    │  Ifmap via        │                        │                      │              │
    │  DMA              │──────────────────→ Receive + Parse              │              │
    │                   │                   Write to BRAM                │              │
    │                   │                        │                      │              │
    │                   │                        ├─ ifmap_write_done ──→ │              │
    │                   │                        │  (signal HIGH)         │              │
    │                   │                        │                      │ Both signals │
    │                   │                        │                      │ detected!    │
    │                   │                        │                      │              │
    │                   │                        │                      ├─ start ─────→ │ Process
    │                   │                        │                      │ + layer/batch│ computation
    │                   │                        │                      │ config       │
    │                   │                        │                      │              │
    │                   │                        │                      │              ├─ Run
    │                   │                        │                      │              │ batches
    │                   │                        │                      │              │
    │                   │                        │                      │← batch_done ─┤
    │                   │                        │                      │              │
    │ (Layer/Batch loop: repeat DMA weight loads for next batches)       │              │
    │                   │                        │                      │              │
```

---

## **Key Design Points**

1. **Decoupled AXI from Computation:**
   - Auto_Scheduler doesn't directly control AXI
   - It only **monitors** completion signals
   - This allows PS software to manage DMA independently

2. **Handshake Mechanism:**
   - AXI wrapper signals: "Data is ready"
   - Auto_Scheduler waits for BOTH signals
   - Then triggers processing via `final_start_signal`

3. **Multi-Layer Support:**
   - Detects when PS sends entirely new layer (both signals posedge together)
   - Automatically increments layer and resets batch counter
   - Handles different batch counts per layer

4. **Optional External Control:**
   - `ext_scheduler_start`: Manual trigger (debug/test)
   - `external_layer_id`: Manual layer override (commented out in current design)

---

## **File Locations**

| Component | File | Role |
|-----------|------|------|
| Auto_Scheduler | `src/Transpose_Convolution/Grouping/Control Unit/Auto_Scheduler.v` | Main FSM that reacts to AXI signals |
| axis_control_wrapper | `src/AXI_CUSTOM/axi_control_wrapper.v` | Parses AXI headers & generates `*_write_done` |
| Top-level | `src/Transpose_Convolution/Grouping/Control Unit/Transpose_Control_Top.v` | Connects everything |
| System Top | `src/Transpose_Convolution/Grouping/Added/Conv_Transconv_System_Top_Level.v` | Full system integration |

---

## **Summary**

**Auto_Scheduler interacts with AXI by:**
1. **Listening** to `weight_write_done` and `ifmap_write_done` signals
2. **Detecting** posedges on these signals (data ready)
3. **Waiting** until BOTH signals indicate completion
4. **Generating** `final_start_signal` to start the Scheduler_FSM
5. **Managing** multi-batch and multi-layer execution based on AXI signal patterns
6. **Providing** status outputs (layer_id, batch_id) for context-aware processing

The AXI interaction is **event-driven** (interrupt-like) rather than polled.
