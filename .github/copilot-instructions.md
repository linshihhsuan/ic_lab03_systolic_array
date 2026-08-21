# AGILAB Hardware & Software Integration Guidelines

## SystemVerilog Coding Rules
When writing or reviewing SystemVerilog code, follow these strict RTL design conventions:

### Naming Conventions & Ports
- **Ports**: Prefix input ports with `i_*`, output ports with `o_*`, and active-low signals with `*_n` (e.g., `i_clk`, `i_rst_n`, `i_data_vld`, `o_data_rdy`).
- **Registers & Combinational**: Use `*_r` for sequential registers and `*_next` for combinational next-state signals.
- **Data Type**: Always prefer `logic` over traditional `reg`/`wire`.

### Clock, Reset & Sequential Logic
- **Reset**: Active-low synchronous reset (`i_rst_n`).
- **Clocking**: Single positive edge trigger (`posedge i_clk`) only. Do not mix negative edges or asynchronous resets unless explicitly specified.

### FSM & Combinational Logic
- **FSM Style**: Enforce strict 3-block FSM architecture (State Register, Next-State Logic, Output Logic).
- **Latch Prevention**: Prevent latches strictly. Always assign default values to all `*_next` signals at the top of `always_comb` blocks.
- **Case Statements**: Use `unique case` for state decoding.

### Interface & Architecture
- **Handshake Protocol**: Standard valid/ready streaming interface using `*_vld` and `*_rdy`.
- **Systolic Array / PE Naming**: 
  - Instance naming format: `u_PE_R[r]_C[c]`
  - Neighboring inter-PE signals: `pe_data_east`, `pe_data_south`
  - Ping-pong buffer naming: `*_ping`, `*_pong`

### Code Safety & Linting
- **Bit-width Mismatches**: Strictly prohibit implicit bit-width truncation or expansion. Always match bit-widths explicitly or use syntax like `'0` / `'1`.

---

## Git & GitHub Workflow Guidelines

### Git Commit Message Guidelines
When generating Git commit messages, strictly follow these constraints:
- **Language**: Use Traditional Chinese (繁體中文).
- **Format**: `[Type]: Short description` (keep under 50 characters).
- **Allowed Types**: You MUST use exactly one of the following prefix tags for `[Type]`:
  - `feat`
  - `chore`
  - `refactor`
  - `docs`
  - `fix`

### Pull Request (PR) Description Guidelines
When generating Pull Request descriptions, strictly follow these constraints:
- **Language**: Use Traditional Chinese (繁體中文).
- **Title Prefix**: The PR title must start with one of the following `[Type]` tags:
  - `[Feature]`
  - `[Fix]`
  - `[refactor]`
  - `[docs]`
  - `[test]`
- **Required Sections**: The body must include the following structural headers:
  - 【功能摘要】
  - 【主要變更內容 (Bullet points)】
  - 【影響範圍】
  - 【測試方法】
- **Tone & Rationale**: Professional and concise. Focus on explaining **WHY** the changes were made, not just **WHAT** was changed.
- **Special Tags**:
  - If changes involve UI, explicitly tag or mark **『視覺變更』**.
  - If changes involve performance optimization, explicitly tag or mark **『效能影響』**.