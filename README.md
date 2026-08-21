# [Project Name] - FPGA-Based Accelerator Core

## 1. Introduction
Briefly describe the circuit's function. 
Example: A dynamic quantization unit optimized for Self-Attention, targeting real-time inference on edge FPGA devices.

## 2. System Architecture
![Architecture Diagram](doc/images/arch_diagram.png)
> **Data Flow:** HBM/DDR -> AXI DataMover -> Input Buffer (BRAM) -> Systolic Array -> Output FIFO.

## 3. Key Specifications (FPGA Target)
| Feature | Details |
| :--- | :--- |
| **Target Device** | Xilinx Zynq UltraScale+ (e.g., ZCU102) |
| **Clock Frequency** | 200 MHz / 250 MHz (Target) |
| **Precision** | INT8 / FP16 / Custom Quantization |
| **Control Interface** | AXI4-Lite (Slave) |
| **Data Interface** | AXI4-Stream (Master/Slave) |

## 4. Register Map Summary
For a detailed bit-level definition, see [Full Register Map](doc/register_map.md).

| Address (Offset) | Name | Description |
| :--- | :--- | :--- |
| **0x00** | **CTRL** | AP_START, AP_DONE, AP_IDLE, AP_READY |
| **0x10** | **MODE** | 0: NOP, 1: LOAD_LUT, 2: COMPUTE |
| **0x14** | **DATA_LEN** | Input sequence length (Max: 4096) |

---

## 5. Implementation Results (PPA)
*Updated based on the latest Vivado Implementation Report.*

### Resource Utilization
| Resource | Used | Available | Utilization (%) |
| :--- | :--- | :--- | :--- |
| **CLB LUTs** | 12,450 | 274,080 | 4.5% |
| **BRAM (36Kb)** | 42 | 912 | 4.6% |
| **DSP Slices** | 64 | 2,520 | 2.5% |

### Timing & Power
### 📊 PPA Evaluation Results (Example)

| Metric | Results | Remarks / Constraints |
| :--- | :--- | :--- |
| **Target Clock** | $250$ MHz | Period $T = 4.0$ ns |
| **WNS (Setup)** | $+0.152$ ns | **Met** (with $0.05$ ns Clock Uncertainty) |
| **WHS (Hold)** | $+0.020$ ns | **Met** |
| **Dynamic Power**| $0.98$ W | Based on $FSDB/SAIF$ simulation activity |
| **Total Power** | $1.24$ W | Target Device: **Alveo U55C** |

---

## 6. Verification & Development Status
- [x] **RTL Simulation**: Functional passing (Xsim/Modelsim).
- [x] **Bitstream Generated**: Ready for hardware test.
- [ ] **On-Board Testing**: In progress via Vitis/JTAG.
- [Detailed Test & PPA Report](doc/report.md)

## 7. How to Recreate Project
1. Open Vivado 2023.1.
2. Run `source scripts/recreate_project.tcl` in the Tcl Console.
3. Click "Generate Bitstream".
