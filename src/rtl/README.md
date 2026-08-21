# RTL Source Code Directory

**Path:** `src/rtl/`  
**Description:** This directory contains all synthesizable Verilog/SystemVerilog source files for the DPQU Accelerator.

---

## 1. Module Hierarchy
Below is the structural breakdown of the RTL design:

* **top_dpqu.v** (Top-level Wrapper)
    * **dpqu_ctrl.v** (from `../controller/`) - System FSM & Register Map
    * **datapath_top.v** - Main Computation Wrapper
        * **systolic_array.v** - Processing Element (PE) Grid
            * **pe_unit.v** - Individual Multiply-Accumulate / Distance Engine
        * **pq_engine.v** - Product Quantization Lookup Logic
        * **buffer_manager.v** - Local BRAM / SRAM Controllers
    * **axi_adapter.v** - Bridge between internal signals and AXI Bus

---

## 2. File Descriptions

| File Name | Description |
| :--- | :--- |
| `top_dpqu.v` | The top-level module that integrates the Controller and Datapath. Includes AXI4-Lite and AXI-Stream interfaces. |
| `datapath_top.v` | Orchestrates data flow between the input buffers, PQ engine, and systolic array. |
| `systolic_array.v` | A configurable 2D array of PEs for high-throughput matrix operations. |
| `pe_unit.v` | The fundamental arithmetic unit. Implements the distance calculation for PQ. |
| `pq_engine.v` | Handles the lookup logic for quantized indices against the codebook stored in BRAM. |
| `fifo_sync.v` | Synchronous FIFO used for data buffering between pipeline stages. |

---

## 3. Design Parameters
Most modules utilize parameters defined in `src/include/dpqu_defines.vh`. Key parameters include:

- `DATA_WIDTH`: Default is 8-bit for PQ indices.
- `ARRAY_SIZE`: Defines the N x N dimension of the Systolic Array.
- `LUT_DEPTH`: Number of entries in the Product Quantization Codebook (default 256).

---

## 4. Coding Standards & Guidelines
To maintain code quality and synthesis compatibility:
1. **Naming Convention:** - Use `i_` prefix for inputs (e.g., `i_clk`, `i_data`).
   - Use `o_` prefix for outputs (e.g., `o_valid`, `o_result`).
   - Use `w_` for wires and `r_` for registers within the module.
2. **Clocking:** Only use the global clock `clk_core`. Avoid generated clocks unless approved.
3. **Resets:** Use asynchronous active-low reset `rst_n`, synchronized to the core clock.
4. **Tool Compatibility:** All code must be synthesizable by **Xilinx Vivado** and **Synopsys Design Compiler**.

---

## 5. Dependencies
- **Includes:** Requires `src/include/dpqu_defines.vh` for global constants.
- **IP Cores:** Some modules may instantiate Xilinx IP (e.g., Floating Point IP). Ensure `.xci` files are tracked in `scripts/`.
