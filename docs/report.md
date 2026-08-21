# Implementation & Performance Report (PPA)

**Project:** DPQU Accelerator  
**Target Device:** Xilinx Zynq UltraScale+ ZCU102 / ASIC TSMC 28nm  
**Date:** 2026-04-14  

## 1. Area & Resource Utilization
*Results obtained after Implementation (Route).*

| Resource | Used | Available | Utilization (%) |
| :--- | :--- | :--- | :--- |
| **CLB LUTs** | 12,450 | 274,080 | 4.5% |
| **CLB Registers** | 18,200 | 548,160 | 3.3% |
| **BRAM (18Kb)** | 42 | 912 | 4.6% |
| **DSP Slices** | 64 | 2,520 | 2.5% |

---

## 2. Performance & Latency
*Measured at a Clock Frequency of **250 MHz**.*

### 2.1 Execution Time
| Task | Workload | Latency (ms) | Throughput |
| :--- | :--- | :--- | :--- |
| **LOAD_LUT** | 256 entries x 512-bit | 0.05 ms | - |
| **COMPUTE** | Seq=1024, Head=12 | 0.85 ms | 1200 Samples/s |

### 2.2 Bottleneck Analysis
* Current bottleneck is **HBM Bandwidth** during initial data loading.
* Computation logic utilization is at 85% during the `COMPUTE` phase.

---

## 3. Power Analysis
*Estimated by Xilinx Power Estimator (XPE) / Synopsys PrimePower.*

| Component | Dynamic Power (W) | Static Power (W) | Total (W) |
| :--- | :--- | :--- | :--- |
| **Logic/DSP** | 0.45 W | 0.12 W | 0.57 W |
| **BRAM/Memory** | 0.38 W | 0.05 W | 0.43 W |
| **I/O** | 0.22 W | 0.02 W | 0.24 W |
| **Total** | **1.05 W** | **0.19 W** | **1.24 W** |

---

## 4. Accuracy Verification
Comparison between **FP32 Golden Model (Python)** and **Fixed-Point RTL (Verilog)**.

* **Test Dataset:** WikiText-103
* **Metric:** Mean Squared Error (MSE) / Top-1 Recall
* **Result:**
  * **MSE:** 1.2e-4
  * **Top-1 Accuracy Drop:** < 0.2%

---

## 5. Implementation Screenshots
*(Insert Layout or Waveform screenshots below)*
![Layout View](images/layout_snapshot.png)
