# [IP Name] Register Map Specification

**Version:** 1.0  
**Status:** Draft / Released  
**Base Address:** Defined by System Integration (e.g., `0x4000_0000`)

---

## 1. Register Summary Table

| Offset | Name | Access | Default Value | Description |
| :--- | :--- | :--- | :--- | :--- |
| **0x00** | [CTRL](#0x00-ctrl) | R/W | 32'h0000_0004 | Global Control and Status Register |
| **0x04** | [GIER](#0x04-gier) | R/W | 32'h0000_0000 | Global Interrupt Enable Register |
| **0x10** | [MODE](#0x10-mode) | R/W | 32'h0000_0000 | Operation Mode Selection |
| **0x14** | [SRC_ADDR](#0x14-src_addr) | R/W | 32'h0000_0000 | Source Data Base Address (HBM/DDR) |
| **0x18** | [DST_ADDR](#0x18-dst_addr) | R/W | 32'h0000_0000 | Destination Data Base Address (HBM/DDR) |
| **0x1C** | [CONFIG](#0x1c-config) | R/W | 32'h0000_0000 | Operational Parameters (Dim, Seq Len, etc.) |

---

## 2. Detailed Bit Definitions

### 0x00: CTRL
| Bit | Name | Access | Default | Description |
| :--- | :--- | :--- | :--- | :--- |
| 0 | `ap_start` | R/W | 0 | **Start Signal**: Write 1 to trigger operation. Automatically clears to 0 after start. |
| 1 | `ap_done` | RO | 0 | **Done Flag**: Set to 1 by hardware upon completion. Cleared on read. |
| 2 | `ap_idle` | RO | 1 | **Idle State**: 1 indicates the IP is idle and ready for new commands. |
| 3 | `ap_ready` | RO | 0 | **Ready Flag**: 1 indicates the IP is ready to accept new data. |
| 4:31 | Reserved | - | 0 | Reserved for future use. |

### 0x10: MODE
| Bit | Name | Access | Default | Description |
| :--- | :--- | :--- | :--- | :--- |
| 1:0 | `op_mode` | R/W | 00 | **Operation Mode**: <br> `00`: NOP (No Operation) <br> `01`: LOAD_LUT (Move PQ Codebook to internal BRAM) <br> `10`: LOAD_CLUSTER (Load cluster-specific data) <br> `11`: COMPUTE (Execute DPQU Core Logic) |
| 2:31 | Reserved | - | 0 | Reserved. |

### 0x14: SRC_ADDR
* **Description**: Specifies the starting physical address of input data in HBM/DDR.
* **Requirement**: Address must be aligned to the AXI Data Width (e.g., 16-byte aligned for 128-bit bus).

### 0x1C: CONFIG
| Bit | Name | Access | Default | Description |
| :--- | :--- | :--- | :--- | :--- |
| 15:0 | `seq_len` | R/W | 0 | Sequence Length of the input. |
| 31:16 | `head_num` | R/W | 0 | Number of Attention Heads. |

---

## 3. Software Driver Flow (Recommended)

### Step A: Initialization & Check
1. Read `0x00 (CTRL)` to ensure `ap_idle` is 1.
2. Write the memory addresses to `0x14 (SRC_ADDR)` and `0x18 (DST_ADDR)`.
3. Configure matrix dimensions in `0x1C (CONFIG)`.

### Step B: Execution
1. Set `0x10 (MODE)` to `2'b11` (COMPUTE Mode).
2. Write 1 to `0x00 (CTRL)` bit[0] (`ap_start`).

### Step C: Synchronization
1. **Polling Mode**: Continuously read `0x00 (CTRL)` until bit[1] (`ap_done`) becomes 1.
2. **Interrupt Mode**: Wait for the hardware interrupt signal, then enter the ISR for post-processing.

---

## 4. Error Handling
* If `ap_done` hangs, verify if `SRC_ADDR` points to a valid and authorized memory region to avoid DMA stall.
* Ensure all mode transitions follow the prescribed sequence (e.g., LOAD_LUT must occur before COMPUTE).
