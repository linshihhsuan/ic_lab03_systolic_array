# Controller Module Specification

**Module Name:** `dpqu_ctrl`  
**Parent IP:** DPQU Accelerator  
**Description:** This module acts as the "Brain" of the accelerator, handling AXI4-Lite register decoding, FSM transitions, and generating control signals for the Datapath and DMA Interface.

---

## 1. Finite State Machine (FSM) Design
The controller operates based on a central FSM. Below are the state definitions:

| State Name | Description | Next State Criteria |
| :--- | :--- | :--- |
| **ST_IDLE** | Waiting for `ap_start` from register 0x00. | `ap_start == 1` -> ST_LOAD_LUT |
| **ST_LOAD_LUT** | Fetching PQ Codebook from Memory to BRAM. | `dma_done == 1` -> ST_WAIT_CMD |
| **ST_WAIT_CMD** | Ready to compute, waiting for user trigger. | `mode == COMPUTE` -> ST_COMPUTE |
| **ST_COMPUTE** | Controlling Systolic Array & Address Generation. | `last_pixel == 1` -> ST_DONE |
| **ST_DONE** | Setting `ap_done` and clearing internal flags. | `auto_clear` -> ST_IDLE |

---

## 2. Block Diagram (Internal)
*(Insert a diagram showing AXI-Lite Slave -> Decoder -> FSM -> Control Signals)*
![Controller Logic](images/controller_logic.png)

---

## 3. Control Signals (Internal Interface)
These signals are driven by the Controller to manage the Datapath:

| Signal Name | Direction | Width | Description |
| :--- | :--- | :--- | :--- |
| `lut_we` | Output | 1 | Write enable for internal LUT BRAM. |
| `compute_en` | Output | 1 | Enables clock gating/logic for the Systolic Array. |
| `addr_gen_rst` | Output | 1 | Resets the internal Address Generation Unit (AGU). |
| `fifo_clr` | Output | 1 | Clears input/output FIFOs before a new session. |

---

## 4. Key Implementation Details

### 4.1 Register Decoding
* The decoder captures the 32-bit AXI data and maps it to internal wires.
* **Synchronization:** All incoming AXI-Lite signals are synchronized to the core clock domain (`clk_core`).

### 4.2 DMA Handshaking
* The controller asserts `dma_req` to the DMA Interface.
* It waits for `dma_ack` before progressing the FSM to avoid data loss or bus contention.

### 4.3 Pipeline Control
* During the `ST_COMPUTE` state, the controller manages the pipeline stall logic based on the `fifo_full` and `fifo_empty` flags from the Datapath.

---

## 5. Timing Diagram (Example)
*(Describe the timing of ap_start to compute_en)*

## 6. Known Limitations
The controller does not support Out-of-Order AXI transactions.

Maximum outstanding DMA requests is limited to 1 to simplify FSM logic.
