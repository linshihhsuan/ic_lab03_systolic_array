# Verible 使用說明書

本文件提供本專案 Verible 的標準安裝與使用流程，目標是「簡單、可重現、跨電腦可用」。

## 1. 適用情境
1. 在 Windows 本機安裝 Verible。
2. 在 PowerShell、cmd、Git Bash 使用 `verible-verilog-lint`。
3. 在專案中手動執行與 CI 相同的 lint 流程。

## 2. Windows 安裝（推薦）
在專案根目錄執行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install_verible_windows.ps1
```

安裝完成後，Verible 會放在：

`C:\github\vectorAdd_8b\.tools\verible\...`

## 3. Git Bash 安裝（替代）
在專案根目錄執行：

```bash
bash scripts/install_verible_windows_gitbash.sh
```

說明：
1. Git Bash 腳本會呼叫 Windows PowerShell 安裝器。
2. 如果你已經用 PowerShell 安裝過，通常不需要再跑 Git Bash 版本。

## 4. 安裝後驗證
請用你實際要工作的終端機驗證。

PowerShell：

```powershell
verible-verilog-lint --version
```

cmd：

```bat
verible-verilog-lint --version
```

Git Bash：

```bash
verible-verilog-lint --version
```

## 5. 專案常用 lint 指令
### 5.1 Git Bash / Linux

```bash
find src/rtl src/controller -type f \( -name "*.sv" -o -name "*.v" \) -print0 | xargs -0 -r verible-verilog-lint --rules_config=.veriblelintrc
```

### 5.2 PowerShell（Windows）

```powershell
Get-ChildItem src/rtl,src/controller -Recurse -File -Include *.sv,*.v |
ForEach-Object { verible-verilog-lint --rules_config=.veriblelintrc $_.FullName }
```

## 6. 常見問題
### 6.1 PowerShell 可用，但 cmd 顯示找不到指令
原因：cmd 不會即時刷新 PATH。

作法：
1. 關閉目前 cmd 視窗。
2. 開新 cmd 視窗後重試 `verible-verilog-lint --version`。

### 6.2 安裝腳本顯示已成功，但當前終端機仍找不到指令
原因：終端機啟動時載入的 PATH 尚未更新。

作法：
1. 關閉並重開終端機。
2. 再執行 `verible-verilog-lint --version`。

### 6.3 為什麼不直接用 conda 安裝 Verible
目前 `conda-forge` 沒有 `win-64` 的 `verible` 套件，Windows 需改用本專案腳本安裝。
