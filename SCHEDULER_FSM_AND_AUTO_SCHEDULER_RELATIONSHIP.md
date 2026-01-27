# Scheduler_FSM and Auto_Scheduler Relationship

## Overview: Master-Slave Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     HIERARCHICAL CONTROL ARCHITECTURE                    │
└─────────────────────────────────────────────────────────────────────────┘

                        AXI Data Loading (PS)
                               │
                ┌──────────────┴──────────────┐
                │                             │
         weight_write_done            ifmap_write_done
                │                             │
                └──────────────┬──────────────┘
                               ▼
                    ┌──────────────────────┐
                    │  AUTO_SCHEDULER      │  ← MASTER/DECISION MAKER
                    │  (The Brain)         │
                    ├──────────────────────┤
                    │ Logic:               │
                    │ • Monitor AXI        │
                    │ • Detect layer/batch │
                    │ • Decide WHEN to run │
                    │ • Track progress     │
                    └──────┬───────┬───────┘
                           │       │
                  final_start_signal│
                  current_layer_id │
                  current_batch_id │
                           │       │
                           ▼       ▼
                    ┌──────────────────────┐
                    │   SCHEDULER_FSM      │  ← SLAVE/EXECUTOR
                    │   (The Muscles)      │
                    ├──────────────────────┤
                    │ Logic:               │
                    │ • Execute sequence   │
                    │ • Control sub-units  │
                    │ • Generate addresses │
                    │ • Report completion  │
                    └──────┬───────────────┘
                           │
           ┌───────────────┼───────────────┐
           ▼               ▼               ▼
       (Mapper)      (Weight BRAM)    (Ifmap BRAM)
         ...        (Transpose Unit)
                    (Output Manager)
```

---

## Detailed Relationship

### **1. AUTO_SCHEDULER: The Decision Maker**

**Role:** Orchestrates multi-layer, multi-batch execution

**Key Responsibilities:**
- Monitor data arrival from AXI wrappers
- Detect layer changes (both `weight_write_done` AND `ifmap_write_done` posedge)
- Manage batch counting (which batch within a layer)
- Generate `final_start_signal` to trigger Scheduler_FSM
- Track layer and batch context

**Outputs to Scheduler_FSM:**
```verilog
.final_start_signal    → Tells Scheduler_FSM WHEN to start
.current_layer_id      → Tells Scheduler_FSM WHICH layer (D1=0, D2=1)
.current_batch_id      → Tells Scheduler_FSM WHICH batch (0-7 or 0-3)
```

**Inputs from Scheduler_FSM (Feedback):**
```verilog
.batch_complete_signal ← Scheduler_FSM reports when batch is done
```

---

### **2. SCHEDULER_FSM: The Execution Engine**

**Role:** Controls the actual computation sequence for ONE batch

**Key Responsibilities:**
- React to `start` signal from Auto_Scheduler
- Use `current_layer_id` and `current_batch_id` to configure itself
- Generate start signals to sub-modules (Mapper, Weight, Ifmap, Transpose)
- Calculate correct addresses based on layer/batch/row/tile
- Track internal pass counter and tile progression
- Report `batch_complete` when done with current batch

**State Machine (per batch):**
```
IDLE 
  ├─ Wait for start signal from Auto_Scheduler
  │
  ▼
START_ALL (Set up addresses for tile/row)
  ├─ Decode current_batch_id & current_layer_id
  ├─ Calculate IFMAP address range (layer-specific)
  ├─ Calculate weight address (tile-specific)
  ├─ Trigger Mapper, Weight, Ifmap start signals
  │
  ▼
WAIT_BRAM (Wait for BRAM to stabilize)
  ├─ Brief wait (2 cycles)
  │
  ▼
START_TRANS (Trigger transpose unit)
  ├─ Set instruction code
  ├─ Set iteration count
  │
  ▼
WAIT_TRANS (Wait for transpose to complete)
  ├─ Poll done_transpose signal
  ├─ Increment pass_counter on completion
  ├─ Loop back to START_ALL if more passes in batch
  ├─ Go to DONE_STATE when all passes done
  │
  ▼
DONE_STATE
  ├─ Assert batch_complete pulse
  ├─ Return to IDLE
```

---

## Signal Flow: Complete Example

### **Multi-Batch Execution Timeline**

```
Time    Auto_Scheduler State              Scheduler_FSM State         Action
────    ─────────────────────────────     ───────────────────────     ──────────────

 100    IDLE (waiting for data)           IDLE

 200    Data arrives:
        • weight_write_done = 1
        • ifmap_write_done = 1
        
 201    Detects BOTH signals              ────────────────────────    
        Sets:
        • current_layer_id = 0 (D1)
        • current_batch_id = 0
        • Generates final_start_signal = 1
                                          Start signal received!
                                          ├─ Use layer_id=0, batch_id=0
                                          ├─ START_ALL: decode addresses
                                          ├─ Trigger Mapper, Weight, Ifmap
                                          │
                                          Executes BATCH 0
                                          (128 passes = 32 rows × 4 tiles)

 500    Waits for batch_complete signal   After 128 passes...
        from Scheduler_FSM                DONE_STATE: pulse batch_complete

 501    Receives batch_complete pulse     Returns to IDLE
        ├─ Resets pass counter
        ├─ Increments current_batch_id = 1
        ├─ (still current_layer_id = 0)
        ├─ Generates final_start_signal = 1 again
                                          Start signal received!
                                          ├─ Use layer_id=0, batch_id=1
                                          ├─ START_ALL: decode NEW addresses
                                          ├─ Trigger new batch
                                          │
                                          Executes BATCH 1

 ...    (repeat for batches 2-7)

 900    After batch 7 complete:
        ├─ Detects new data arrival
        │  (weight_write_done posedge AND ifmap_write_done posedge)
        ├─ current_layer_id = 1 (D2)
        ├─ current_batch_id = 0
        ├─ Resets batch counter
        ├─ Generates final_start_signal = 1
                                          Layer transition!
                                          Executes BATCH 0 of LAYER 1
                                          (different row/address counts)
```

---

## Connection Details

### **How They Connect in Transpose_Control_Top.v**

```verilog
// =====================================================
// AUTO_SCHEDULER INSTANTIATION
// =====================================================
Auto_Scheduler u_auto_sched (
    .clk                   (clk),
    .rst_n                 (rst_n),
    
    // INPUTS: From AXI
    .weight_write_done     (weight_write_done),      ← From axis_control_wrapper
    .ifmap_write_done      (ifmap_write_done),       ← From axis_control_wrapper
    
    // INPUTS: Manual override (optional)
    .ext_scheduler_start   (ext_start),              ← From PS
    .external_layer_id     (ext_layer_id),           ← From PS
    
    // INPUTS: Feedback from Scheduler_FSM
    .batch_complete_signal (batch_complete_signal),  ← From Scheduler_FSM.batch_complete
    
    // OUTPUTS: Control to Scheduler_FSM
    .final_start_signal    (final_start_signal),
    .current_batch_id      (auto_batch_id),
    .current_layer_id      (auto_layer_id),
    
    // OUTPUTS: Status
    .all_batches_complete  (all_batches_done),
    .clear_output_bram     (clear_output_bram),
    .auto_start_active     (auto_active),
    .data_load_ready       ()
);

// =====================================================
// SCHEDULER_FSM INSTANTIATION
// =====================================================
Scheduler_FSM #(
    .ADDR_WIDTH(ADDR_WIDTH)
) u_scheduler (
    .clk              (clk),
    .rst_n            (rst_n),
    
    // ★★★ KEY CONNECTION: Auto_Scheduler controls start ★★★
    .start            (final_start_signal),        ← FROM Auto_Scheduler
    
    // ★★★ KEY CONNECTION: Context from Auto_Scheduler ★★★
    .current_layer_id (auto_layer_id),             ← FROM Auto_Scheduler
    .current_batch_id (auto_batch_id),             ← FROM Auto_Scheduler
    
    // INPUTS: Feedback from datapath
    .done_mapper      (done_mapper),
    .done_weight      (done_weight),
    .if_done          (if_done),
    .done_transpose   (done_transpose),
    
    // OUTPUTS: Control signals to datapath
    .start_Mapper     (start_Mapper),
    .start_weight     (start_weight),
    .start_ifmap      (start_ifmap),
    .start_transpose  (start_transpose),
    
    // OUTPUTS: Address configuration
    .if_addr_start    (if_addr_start),
    .if_addr_end      (if_addr_end),
    .ifmap_sel_in     (ifmap_sel_in),
    .addr_start       (addr_start),
    .addr_end         (addr_end),
    
    // OUTPUTS: Transpose configuration
    .Instruction_code_transpose (Instruction_code),
    .num_iterations   (num_iterations),
    .row_id           (row_id),
    .tile_id          (tile_id),
    
    // ★★★ KEY CONNECTION: Feedback to Auto_Scheduler ★★★
    .batch_complete   (batch_complete_signal)      ← TO Auto_Scheduler (feedback loop)
);
```

---

## Operational Modes

### **Mode 1: Automatic (Normal Operation)**

```
Auto_Scheduler:     RUNNING (monitoring AXI)
                    ├─ Detects data ready
                    ├─ Sets layer_id, batch_id
                    └─ Pulses final_start_signal

Scheduler_FSM:      IDLE → START_ALL → WAIT_BRAM → START_TRANS → WAIT_TRANS
                    ├─ Reads auto_layer_id, auto_batch_id
                    ├─ Configures itself
                    └─ Executes batch

Auto_Scheduler:     Receives batch_complete
                    ├─ Increments batch counter
                    └─ Generates new final_start_signal
                    
(Loop repeats)
```

### **Mode 2: Manual Override (Debug)**

```
If ext_scheduler_start = 1 (manual trigger):
    Auto_Scheduler: final_start_signal = ext_scheduler_start | batch_auto_start
    
    → Scheduler_FSM can start without waiting for Auto_Scheduler's batch_auto_start
    → But still uses Auto_Scheduler's layer_id and batch_id
```

---

## Key Design Patterns

### **1. Handshake Protocol**

```
Auto_Scheduler                          Scheduler_FSM
    │
    ├─ Sets current_layer_id           (combainational input)
    ├─ Sets current_batch_id           (combinational input)
    │
    └─ Pulses final_start_signal ─────→ Starts FSM
                                        │
                                        ├─ Reads layer/batch context
                                        ├─ Executes sequence
                                        │
                                        └─ Pulses batch_complete ─────→ Signals done
                                        
Auto_Scheduler:
    └─ Detects batch_complete pulse
        ├─ Resets counters
        ├─ Increments batch_id or layer_id
        └─ Waits for next data or generates next start
```

### **2. Layer/Batch Context Passing**

Auto_Scheduler provides context, Scheduler_FSM uses it:

```verilog
// In Scheduler_FSM.v START_ALL state:

case (current_layer_id)
    2'd0: begin  // Layer D1: 32 rows, 8 batches
        max_passes_per_batch = 8'd127;  // 0-127 = 128 passes
        rows_per_batch = 6'd31;
    end
    2'd1: begin  // Layer D2: 64 rows, 4 batches
        max_passes_per_batch = 8'd255;  // 0-255 = 256 passes
        rows_per_batch = 6'd63;
    end
endcase

// Scheduler configures itself based on layer!
if (current_layer_id == 2'd0) begin
    // Layer 0: 2 ranges (bit 4 determines range)
    if (current_pass_row[4] == 1'b0) begin
        if_addr_start <= 10'd0;
        if_addr_end   <= 10'd255;
    end else begin
        if_addr_start <= 10'd256;
        if_addr_end   <= 10'd511;
    end
end else begin
    // Layer 1: 4 ranges (bits [5:4] determine range)
    case (current_pass_row[5:4])
        2'b00: begin if_addr_start <= 10'd0;   if_addr_end <= 10'd255;  end
        2'b01: begin if_addr_start <= 10'd256; if_addr_end <= 10'd511;  end
        2'b10: begin if_addr_start <= 10'd512; if_addr_end <= 10'd767;  end
        2'b11: begin if_addr_start <= 10'd768; if_addr_end <= 10'd1023; end
    endcase
end
```

---

## Comparison Table

| Aspect | Auto_Scheduler | Scheduler_FSM |
|--------|---|---|
| **Role** | Decision maker | Executor |
| **Scope** | Multi-layer, multi-batch system | Single batch execution |
| **Inputs** | AXI signals, batch_complete feedback | start signal, layer/batch context, done signals |
| **Outputs** | final_start_signal, layer_id, batch_id | Mapper/Weight/Ifmap/Transpose control signals, addresses |
| **State Machine** | 5 states (IDLE, WAIT_INITIAL, RUNNING, WAIT_RELOAD, ALL_DONE) | 6 states (IDLE, START_ALL, WAIT_BRAM, START_TRANS, WAIT_TRANS, DONE) |
| **Frequency** | Activates per batch/layer | Activates per batch (repeatedly) |
| **AXI Awareness** | ✅ YES (monitors write_done signals) | ❌ NO (doesn't see AXI) |
| **Data Ordering** | ✅ Handles layer/batch sequencing | ❌ Just executes current batch |
| **Feedback Loop** | Receives batch_complete | Sends batch_complete |

---

## Complete Information Flow

```
SYSTEM STARTUP:
    PS sends ifmap data via DMA → axis_control_wrapper → ifmap_write_done = 1
    PS sends weight data via DMA → axis_control_wrapper → weight_write_done = 1
    
AUTO_SCHEDULER REACTS:
    1. Detects posedges on both signals
    2. Sets current_layer_id = 0
    3. Sets current_batch_id = 0
    4. Generates final_start_signal pulse
    
SCHEDULER_FSM REACTS:
    1. Receives start signal
    2. Reads current_layer_id = 0 (D1: 32 rows, 8 batches)
    3. Reads current_batch_id = 0
    4. State: IDLE → START_ALL
    5. Calculates addresses based on batch_id and row within batch
    6. Triggers Mapper, Weight, Ifmap starts
    7. State: WAIT_BRAM (stabilize)
    8. State: START_TRANS (trigger transpose)
    9. State: WAIT_TRANS (wait for 128 passes = 32 rows × 4 tiles)
    10. On completion: pulse batch_complete
    
AUTO_SCHEDULER REACTS (FEEDBACK):
    1. Receives batch_complete pulse
    2. Increments current_batch_id to 1
    3. Keeps current_layer_id = 0
    4. Generates next final_start_signal pulse
    
SCHEDULER_FSM REACTS (AGAIN):
    1. Starts with new batch context (batch 1, layer 0)
    2. Repeats execution with new address ranges
    
(Cycle continues for batches 2-7)

AFTER BATCH 7:
    PS sends new ifmap & weight (Layer 1 data)
    Auto_Scheduler detects layer change
    Sets current_layer_id = 1, current_batch_id = 0
    Scheduler_FSM reconfigures for Layer 1 (64 rows instead of 32)
```

---

## Summary

**Auto_Scheduler is the ORCHESTRATOR:**
- Monitors external events (AXI completion)
- Decides global flow (which layer, which batch)
- Triggers Scheduler_FSM at the right time

**Scheduler_FSM is the EXECUTOR:**
- Executes one batch at a time
- Uses context (layer, batch) to self-configure
- Controls detailed datapath operations
- Reports completion back to Auto_Scheduler

**They work in a FEEDBACK LOOP:**
- Auto_Scheduler decides WHAT to do
- Scheduler_FSM does it
- Reports back when done
- Auto_Scheduler makes next decision
