// verilog_lint: waive-start
//////////////////////////////////////////////////////////////////////////////////
// Company: AGILAB
// Engineer: Undergraduate Student
//
// Create Date: 2026/08/21 15:14:24
// Design Type: RTL (Synthesizable Circuit)
// Design Name: ic_lab03_systolic_array
// Module Name: result_drain
// Project Name:
// Target Devices:
// Tool Versions:
// Description: 建立 result_drain 模組。
// Coding Rules:
//   Type       : RTL (Synthesizable Circuit)
//   SV Syntax  : Avoid new SystemVerilog syntax; keep it synthesizable and compatible.RTL (Synthesizable Circuit)
//   Ports      : i_* = inputs, o_* = outputs (e.g. i_clk, i_rst_n, i_a, i_b, o_y)
//   Regs       : *_r = registers, *_next = combinational next-state signals
//   Reset      : active-low synchronous reset (i_rst_n), posedge i_clk only
//   FSM        : strict 3-block style; assign defaults in always_comb; no latches
//   Handshake  : *_vld / *_rdy naming
//   Systolic   : u_PE_R[r]_C[c], pe_data_east/south, *_ping / *_pong
//   Safety     : avoid bit-width mismatches
//
// Dependencies:
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////
// verilog_lint: waive-stop

module result_drain #(
    parameter integer S_MAX     = 32,
    parameter integer MAX_M     = 256,
    parameter integer MAX_N     = 64,
    parameter integer ACC_WIDTH = 71
)(
    input  logic i_clk,
    input  logic i_rst_n,

    // ============================================================
    // Drain control
    // ============================================================

    input  logic i_drain_start,

    // Current tile information from tile_controller
    input  logic [$clog2(MAX_M+1)-1:0] i_m_base,
    input  logic [$clog2(MAX_N+1)-1:0] i_n_base,

    input  logic [$clog2(S_MAX+1)-1:0] i_active_rows,
    input  logic [$clog2(S_MAX+1)-1:0] i_active_cols,

    // ============================================================
    // Systolic array accumulator read interface
    // ============================================================

    // Select which PE accumulator should be read
    output logic [((S_MAX <= 1) ? 1 : $clog2(S_MAX))-1:0] o_pe_row,

    output logic [((S_MAX <= 1) ? 1 : $clog2(S_MAX))-1:0] o_pe_col,

    // Selected PE accumulator.
    //
    // Contract:
    // systolic_array must return the accumulator corresponding
    // to {o_pe_row, o_pe_col}.
    input logic signed [ACC_WIDTH-1:0] i_pe_acc_data,

    // ============================================================
    // Result stream
    // ============================================================

    output logic signed [ACC_WIDTH-1:0] o_result_data,
    output logic                        o_result_valid,

    // Downstream ready.
    //
    // Typically:
    //     i_result_ready = !output_fifo_full
    input  logic i_result_ready,

    // ============================================================
    // Result coordinate metadata
    // ============================================================

    // Global C matrix coordinate
    output logic [$clog2(MAX_M+1)-1:0] o_c_row,
    output logic [$clog2(MAX_N+1)-1:0] o_c_col,

    // Indicates that the current result is the last
    // element of this tile.
    output logic o_tile_last,

    // ============================================================
    // Status
    // ============================================================

    output logic o_busy,
    output logic o_drain_done
);

    // ============================================================
    // Local parameters
    // ============================================================

    localparam integer MW =
        $clog2(MAX_M + 1);

    localparam integer NW =
        $clog2(MAX_N + 1);

    localparam integer SW =
        $clog2(S_MAX + 1);

    localparam integer PEIDXW =
        (S_MAX <= 1) ? 1 : $clog2(S_MAX);

    // ============================================================
    // FSM
    // ============================================================

    typedef enum logic [1:0] {
        ST_IDLE,
        ST_SEND,
        ST_DONE
    } state_t;

    state_t state_r;
    state_t state_n;

    // ============================================================
    // Latched tile configuration
    // ============================================================

    logic [MW-1:0] m_base_r;
    logic [NW-1:0] n_base_r;

    logic [SW-1:0] active_rows_r;
    logic [SW-1:0] active_cols_r;

    // ============================================================
    // Local PE coordinates
    // ============================================================

    logic [SW-1:0] row_idx_r;
    logic [SW-1:0] col_idx_r;

    // ============================================================
    // Handshake / boundary flags
    // ============================================================

    logic result_fire;
    logic last_element;
    logic tile_valid;

    // Tile must contain at least one valid PE
    always_comb begin

        tile_valid =
            (active_rows_r != '0) &&
            (active_cols_r != '0);

    end

    // ------------------------------------------------------------
    // Last valid element of current tile
    // ------------------------------------------------------------

    always_comb begin

        last_element = 1'b0;

        if (tile_valid) begin

            last_element =
                (row_idx_r == (active_rows_r - 1'b1)) &&
                (col_idx_r == (active_cols_r - 1'b1));

        end

    end

    // ------------------------------------------------------------
    // Actual successful transfer
    // ------------------------------------------------------------

    always_comb begin

        result_fire =
            (state_r == ST_SEND) &&
            tile_valid &&
            i_result_ready;

    end

    // ============================================================
    // FSM next-state logic
    // ============================================================

    always_comb begin

        state_n = state_r;

        case (state_r)

            // ----------------------------------------------------
            ST_IDLE: begin

                if (i_drain_start)
                    state_n = ST_SEND;

            end

            // ----------------------------------------------------
            ST_SEND: begin

                // Defensive handling for an empty tile
                if (!tile_valid) begin

                    state_n = ST_DONE;

                end
                else if (result_fire && last_element) begin

                    state_n = ST_DONE;

                end

            end

            // ----------------------------------------------------
            ST_DONE: begin

                state_n = ST_IDLE;

            end

            // ----------------------------------------------------
            default: begin

                state_n = ST_IDLE;

            end

        endcase

    end

    // ============================================================
    // Sequential logic
    // ============================================================

    always_ff @(posedge i_clk) begin

        if (!i_rst_n) begin

            state_r       <= ST_IDLE;

            m_base_r      <= '0;
            n_base_r      <= '0;

            active_rows_r <= '0;
            active_cols_r <= '0;

            row_idx_r     <= '0;
            col_idx_r     <= '0;

        end
        else begin

            state_r <= state_n;

            // ----------------------------------------------------
            // Capture current tile information
            // ----------------------------------------------------

            if ((state_r == ST_IDLE) &&
                i_drain_start) begin

                m_base_r      <= i_m_base;
                n_base_r      <= i_n_base;

                active_rows_r <= i_active_rows;
                active_cols_r <= i_active_cols;

                row_idx_r     <= '0;
                col_idx_r     <= '0;

            end

            // ----------------------------------------------------
            // Move to next PE only after successful handshake
            // ----------------------------------------------------

            if ((state_r == ST_SEND) &&
                result_fire) begin

                if (!last_element) begin

                    // --------------------------------------------
                    // End of current row
                    // --------------------------------------------
                    if (col_idx_r ==
                        (active_cols_r - 1'b1)) begin

                        col_idx_r <= '0;
                        row_idx_r <= row_idx_r + 1'b1;

                    end

                    // --------------------------------------------
                    // Next column
                    // --------------------------------------------
                    else begin

                        col_idx_r <= col_idx_r + 1'b1;

                    end

                end

            end

        end

    end

    // ============================================================
    // PE read address
    // ============================================================

    always_comb begin

        o_pe_row =
            row_idx_r[PEIDXW-1:0];

        o_pe_col =
            col_idx_r[PEIDXW-1:0];

    end

    // ============================================================
    // Result output
    // ============================================================

    always_comb begin

        // Selected accumulator directly becomes stream data
        o_result_data = i_pe_acc_data;

        o_result_valid = 1'b0;
        o_tile_last    = 1'b0;

        if ((state_r == ST_SEND) &&
            tile_valid) begin

            o_result_valid = 1'b1;
            o_tile_last    = last_element;

        end

    end

    // ============================================================
    // Global C coordinates
    //
    // C row = m_base + local PE row
    // C col = n_base + local PE col
    // ============================================================

    always_comb begin

        o_c_row =
            m_base_r + MW'(row_idx_r);

        o_c_col =
            n_base_r + NW'(col_idx_r);

    end

    // ============================================================
    // Status
    // ============================================================

    always_comb begin

        o_busy       = 1'b0;
        o_drain_done = 1'b0;

        case (state_r)

            ST_SEND: begin
                o_busy = 1'b1;
            end

            ST_DONE: begin
                o_busy       = 1'b1;
                o_drain_done = 1'b1;
            end

            default: begin
                o_busy = 1'b0;
            end

        endcase

    end

endmodule
