# 🚀 NTNU EE- AGILAB - 硬體組 Git & Vivado Tcl 協作規範

本文件為實驗室硬體開發的標準作業程序 (SOP)，規範**Vivado Tcl 腳本** 的使用，確保跨裝置開發時不會出現路徑報錯。

---

## 🛠️ 開發環境 (Environment)
* **EDA Tool:** Xilinx Vivado (建議統一使用 2024.x 版本)
* **Target Board:** PYNQ-Z2 / FPGA SoC
* **Version Control:** Git

---

### 第二部分：SOP 指令與 Checklist


---

## ✍️ 導出教學 (Exporter SOP)
在 Commit 提交程式前，請務必更新 Tcl 腳本，以反映最新的電路修改：

1. **移除二進制依賴**：
   在 Sources 視窗中，將 `Utility Sources` -> `utils_1` 內的所有 `.dcp` 檔案按右鍵選擇 **Remove from Project**。
2. **重設合成狀態**：
   在左側 Design Runs 視窗中，對著 synth_1 按右鍵，點選 Reset Runs。(這會清空舊的編譯紀錄，確保 Tcl 導出時是乾淨的)
3. **導出專案腳本 (Project Tcl)**：
   `File` -> `Project` -> `Write Tcl...`
   * **關鍵：** **取消勾選** `Copy sources to project`。
4. **導出 BD 腳本 (Block Design Tcl)**：
   若有使用 AXI DMA或是其他有block diagram的專案，點選 `File` -> `Export` -> `Export Block Design...`。

---

## 🔄 重建與更新教學 (Rebuilder SOP)
當你從 GitHub `git pull` 更新後，請遵循「砍掉重練」原則：

### 1. 刪除本地舊專案
手動刪除由 Tcl 自動產生的專案資料夾（例如 `ProjectName/`）。

### 2. 執行一鍵重建
開啟 Vivado，在下方的 Tcl Console 中輸入：
```tcl
cd [你的專案路徑]
source project_config.tcl
source design_1.tcl
```

📊 硬體 Fit 流程檢查清單 (Hardware Fit Checklist)

Timing (WNS) > 0 ns：時序必須通過，否則硬體無法運作。

Utilization：監控 LUT/DSP 使用率，確保符合晶片資源。

Power Analysis：導出功耗分析報告。

---

## 附錄：Git 工作流程政策與標準流程

# 🌿 Git 工作流程政策

## 🚫 嚴格禁止
* **禁止**提交 `.runs`、`.cache` 或 `.hw` 資料夾。
* **禁止**提交 `.bit` 或 `.msg` 檔案，除非是發版需求且有明確要求。

## ✅ 最佳實務
1. **原子化提交**：一次提交只做一件事（例如：新增 PE 累加邏輯）。
2. **分支管理**：新模組請使用 `feature/` 分支；通過模擬測試後再合併到 `main`。
3. **訊息清楚**：Commit 訊息建議用 `Fix`、`Add`、`Refactor` 作為開頭。

---

# Git 工作流程（實驗室標準作業流程）

此流程可確保儲存庫維持乾淨，並讓 HDL 原始碼成為「唯一真實來源（Single Source of Truth）」。依照此 SOP 執行，你的工作會在 VS Code、Vivado 與 GitHub 之間保持同步。

---

## 1. 初始設定（VS Code）
1. **複製儲存庫（Clone Repository）**
   * 開啟 **VS Code**。
   * 使用 Git 功能把實驗室儲存庫 Clone 到本機。
2. **建立原始碼檔案**
   * 在儲存庫資料夾內，直接於 **VS Code** 建立新的 Verilog/SystemVerilog 檔案（例如：`srcs/rtl/top.v`）。
   * 測試平台（testbench）請放在 `tb/` 資料夾。

## 2. 整合到 Vivado 專案
3. **啟動 Vivado**：開啟既有專案，或建立一個暫時性的專案殼。
4. **加入原始碼（最重要步驟）**
   * 點選 **Add Sources** -> **Add or create design sources**。
   * 選取你剛剛在 VS Code 建立的檔案。
   * ⚠️ **關鍵**：請**取消勾選** `Copy sources into project`。
   * **結果**：Vivado 只會指向 Git 資料夾裡的檔案，不會建立重複副本。

## 3. 同步開發
5. **撰寫與除錯**
   * 請只在 **VS Code** 編輯程式碼。
   * 當你在 VS Code 儲存（Ctrl+S）後，Vivado 會自動偵測變更並跳出提示：
     Files have been modified on disk. Resetting Synthesis...
   * 這樣你可以使用 VS Code 較好的編輯體驗，同時讓 Vivado 專注在硬體實作流程。

## 4. 維護與儲存庫整潔
6. **排除雜訊檔案**
   * 因為你沒有勾選 `Copy sources into project`，Vivado 的大型專案檔（`.xpr`、`.runs`、`.cache`）會與原始碼分離。
   * Git 只追蹤 **HDL 程式碼（`.v`）**、**約束檔（`.xdc`）** 與 **Tcl 腳本**。
7. **模擬檔案管理**
   * 測試平台請放在 `srcs/sim/` 目錄。
   * 不要上傳自動產生的波形檔（`.wdb`）或模擬紀錄檔。

## 5. Commit 前檢查清單
* [ ] **Reset Runs**：在 Vivado 對 `synth_1` 按右鍵 -> **Reset Runs**，避免輸出前夾帶過多二進位垃圾。
* [ ] **更新 Tcl**：若新增 IP 或調整專案設定，請執行 `Write Tcl...`。
* [ ] **Git Push**：使用 VS Code 的 Source Control 分頁進行 stage 並 push 變更。

---

> 💡 **教授提醒**
> 「Vivado 專案只是暫時容器，真正重要的是你的原始碼。照這個流程做，可以避免垃圾檔案進到 GitHub，讓研究專案維持乾淨且專業。」

