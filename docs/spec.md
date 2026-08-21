# Design Specification: Input/Output Formats

**Project:** DPQU (Dynamic Product Quantization Unit)  
**Version:** 1.0  

## 1. Data Type Definitions
| Data Component | Format | Precision | Range |
| :--- | :--- | :--- | :--- |
| **Query/Key/Value** | Quantized Index | 8-bit Integer | 0 to 255 |
| **Codebook (LUT)** | Floating Point | FP16 / BF16 | - |
| **Attention Score** | Fixed Point | 16-bit Integer | Q8.8 format |

---

## 2. Interface Protocols

### 2.1 AXI-Stream Input (Data Feed)
* **Bus Width:** 128-bit (configured to match DMA burst)
* **TLAST Policy:** Asserted at the end of each Sequence row.
* **Data Packing:**
  * Byte [0]: Index 0
  * Byte [1]: Index 1
  * ...
  * Byte [15]: Index 15

### 2.2 AXI-Stream Output (Results)
* **Bus Width:** 64-bit
* **Content:** Dequantized Attention Output / Intermediate Scores.

---

## 3. Memory Layout in HBM/DDR
To ensure DMA efficiency, data must be stored in the following alignment:

### 3.1 PQ Indices Layout

|Address Offset |  Data (128-bit per Word)
| :--- | :--- |
|0x0000         |  Index[0:15]  (Sequence 0)|
|0x0010         |  Index[16:31] (Sequence 0)|
...

---




### 3.2 Codebook (LUT) Layout
The Codebook must be loaded into the internal BRAM before the COMPUTE mode is activated.

BRAM Depth: 256 entries

BRAM Width: 512-bit (Parallel lookup of multiple sub-vectors)

## 4. Hardware Constraints
Maximum Sequence Length: 4096

Maximum Head Count: 32

Unsupported Features: Variable length padding is not handled by hardware; must be pre-processed by software.
