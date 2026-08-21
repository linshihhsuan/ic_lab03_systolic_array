# Software Interface & Driver Example

**Path:** `sw/`  
**Description:** This directory contains the C header files and example code required to control the DPQU hardware from a processor (e.g., ARM/RISC-V).

---

## 1. File Inventory

| File Name | Description |
| :--- | :--- |
| `ip_register.h` | **The Single Source of Truth** for all register offsets, bitmask definitions, and base addresses. |
| `example.c` | A complete reference implementation of the software-to-hardware handshake flow. |

---

## 2. Using `ip_register.h`
Always use the macros defined in this file instead of hardcoding addresses. This ensures compatibility if the hardware register map changes.

**Example Usage:**
```c
#include "ip_register.h"

// Set the operation mode to COMPUTE
Xil_Out32(DPQU_BASE_ADDR + REG_MODE_OFFSET, MODE_COMPUTE);

## 3. Execution Flow (Refer to `example.c`)
To properly drive the DPQU accelerator, the software must follow this sequence:

### Step 1: Initialization
* **Address Mapping**: Map the PL (Programmable Logic) address space into your application's memory map.
* **Status Check**: Read `REG_CTRL_OFFSET` and verify that the `IP_IDLE` bit is high before issuing commands.

### Step 2: Configuration
* **Pointer Setup**: Write the Source Physical Address to `REG_SRC_ADDR_OFFSET` and the Destination Physical Address to `REG_DST_ADDR_OFFSET`.
* **Parameter Setup**: Configure operational parameters (e.g., Sequence Length) in `REG_CONFIG_OFFSET`.

### Step 3: Trigger & Wait
1. **Mode Selection**: Set the desired operation mode in `REG_MODE_OFFSET`.
2. **Start**: Write `1` to the `AP_START` bit in `REG_CTRL_OFFSET`.
3. **Synchronization (Polling)**: Loop and read `REG_CTRL_OFFSET` until the `AP_DONE` bit is detected as `1`.
```
---

## 4. Critical Integration Notes
* **Memory Coherency**: If the CPU has a Cache enabled, you **must flush the cache** before starting the DPQU and **invalidate the cache** before reading the results from DDR/HBM.
* **Address Translation**: Ensure that the addresses passed to the hardware are **Physical Addresses (PA)**, not Virtual Addresses (VA) used by the OS.
* **Alignment**: Data buffers in DDR/HBM must be aligned to **16-byte boundaries** for AXI 128-bit bus compatibility.

---

## 5. Build Instructions
If using Xilinx Vitis/SDK:

1. **Include Path**: Add the `sw/` directory to your project's include path.
2. **Header Dependency**: Ensure `ip_register.h` is included in your source.
3. **Driver Library**: Link against the standard Xilinx driver library (e.g., `#include "xil_io.h"`) to use `Xil_Out32` and `Xil_In32` functions.
