// verilog_lint: waive-start
//////////////////////////////////////////////////////////////////////////////////
// Company: AGILAB
// Engineer: Undergraduate Student
//
// Create Date: 2026/08/21 15:03:24
// Design Type: RTL (Synthesizable Circuit)
// Design Name: ic_lab03_systolic_array
// Module Name: tile_controller
// Project Name:
// Target Devices:
// Tool Versions:
// Description: 建立 Controller 模組。
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

module tile_controller #(
    parameter integer S_MAX = 32,
    parameter integer MAX_M = 256,
    parameter integer MAX_K = 108,
    parameter integer MAX_N = 64
)(
    input  logic i_clk,
    input  logic i_rst_n,

    // Configuration
    input  logic i_start,

    input  logic [$clog2(MAX_M+1)-1:0] i_m_size,
    input  logic [$clog2(MAX_K+1)-1:0] i_k_size,
    input  logic [$clog2(MAX_N+1)-1:0] i_n_size,

    // From size_selector.sv
    input  logic [$clog2(S_MAX+1)-1:0] i_s_active,

    // Compute handshake
    input  logic i_compute_done,

    // Result drain handshake
    input  logic i_drain_done,

    // Control outputs
    output logic o_acc_clear,
    output logic o_compute_start,
    output logic o_drain_start,

    // Current tile information
    output logic [$clog2(MAX_M+1)-1:0] o_m_base,
    output logic [$clog2(MAX_N+1)-1:0] o_n_base,

    output logic [$clog2(S_MAX+1)-1:0] o_active_rows,
    output logic [$clog2(S_MAX+1)-1:0] o_active_cols,

    // Full K dimension
    output logic [$clog2(MAX_K+1)-1:0] o_k_size,

    // Status
    output logic o_busy,
    output logic o_done
);

    // Width definitions

    localparam integer MW = $clog2(MAX_M + 1);
    localparam integer KW = $clog2(MAX_K + 1);
    localparam integer NW = $clog2(MAX_N + 1);
    localparam integer SW = $clog2(S_MAX + 1);

    // FSM definition

    typedef enum logic [2:0] {
        ST_IDLE,
        ST_PREP_TILE,
        ST_CLEAR_ACC,
        ST_START_COMPUTE,
        ST_WAIT_COMPUTE,
        ST_START_DRAIN,
        ST_WAIT_DRAIN,
        ST_DONE
    } state_t;

    state_t state_r;
    state_t state_n;

    // Configuration registers

    logic [MW-1:0] m_size_r;
    logic [KW-1:0] k_size_r;
    logic [NW-1:0] n_size_r;
    logic [SW-1:0] s_active_r;

    // Tile registers

    logic [MW-1:0] m_base_r;
    logic [NW-1:0] n_base_r;

    logic [SW-1:0] active_rows_r;
    logic [SW-1:0] active_cols_r;

    // Tile boundary detection

    logic last_m_tile;
    logic last_n_tile;

    always_comb begin

        // Current tile is the final M tile when:
        //
        // M - m_base <= S_active

        last_m_tile =
            ((m_size_r - m_base_r) <= MW'(s_active_r));

        // Current tile is the final N tile when:
        //
        // N - n_base <= S_active

        last_n_tile =
            ((n_size_r - n_base_r) <= NW'(s_active_r));

    end

    // FSM next-state logic

    always_comb begin

        state_n = state_r;

        case (state_r)

            ST_IDLE: begin
                if (i_start)
                    state_n = ST_PREP_TILE;
            end

            // Calculate active_rows / active_cols
            ST_PREP_TILE: begin
                state_n = ST_CLEAR_ACC;
            end

            // Clear all PE accumulators for this C tile
            ST_CLEAR_ACC: begin
                state_n = ST_START_COMPUTE;
            end

            // One-cycle compute start pulse
            ST_START_COMPUTE: begin
                state_n = ST_WAIT_COMPUTE;
            end

            // Wait until complete K computation finishes
            ST_WAIT_COMPUTE: begin
                if (i_compute_done)
                    state_n = ST_START_DRAIN;
            end

            // Start draining PE results
            ST_START_DRAIN: begin
                state_n = ST_WAIT_DRAIN;
            end

            // Wait until complete C tile is drained
            ST_WAIT_DRAIN: begin

                if (i_drain_done) begin

                    if (last_m_tile && last_n_tile)
                        state_n = ST_DONE;
                    else
                        state_n = ST_PREP_TILE;

                end

            end

            ST_DONE: begin
                state_n = ST_IDLE;
            end

            default: begin
                state_n = ST_IDLE;
            end

        endcase
    end

    // Sequential logic

    always_ff @(posedge i_clk) begin

        if (!i_rst_n) begin

            state_r       <= ST_IDLE;

            m_size_r      <= '0;
            k_size_r      <= '0;
            n_size_r      <= '0;
            s_active_r    <= '0;

            m_base_r      <= '0;
            n_base_r      <= '0;

            active_rows_r <= '0;
            active_cols_r <= '0;

        end
        else begin

            state_r <= state_n;

            // Capture a new GEMM configuration
            if ((state_r == ST_IDLE) && i_start) begin

                m_size_r   <= i_m_size;
                k_size_r   <= i_k_size;
                n_size_r   <= i_n_size;
                s_active_r <= i_s_active;

                m_base_r   <= '0;
                n_base_r   <= '0;

            end

            // Calculate actual dimensions of current edge tile
            if (state_r == ST_PREP_TILE) begin

                // active_rows = min(S_active, M - m_base)

                if ((m_size_r - m_base_r) <
                    MW'(s_active_r))
                    active_rows_r <=
                        SW'(m_size_r - m_base_r);
                else
                    active_rows_r <= s_active_r;


                // active_cols = min(S_active, N - n_base)

                if ((n_size_r - n_base_r) <
                    NW'(s_active_r))
                    active_cols_r <=
                        SW'(n_size_r - n_base_r);
                else
                    active_cols_r <= s_active_r;

            end

            // Advance tile after drain is completed
            //
            // N dimension = inner loop
            // M dimension = outer loop
            if ((state_r == ST_WAIT_DRAIN) &&
                i_drain_done &&
                !(last_m_tile && last_n_tile)) begin

                if (last_n_tile) begin

                    // Move to next M tile
                    m_base_r <=
                        m_base_r + MW'(s_active_r);

                    // Restart N from zero
                    n_base_r <= '0;

                end
                else begin

                    // Move to next N tile
                    n_base_r <=
                        n_base_r + NW'(s_active_r);

                end

            end

        end
    end

    // Control outputs

    always_comb begin

        o_acc_clear     = 1'b0;
        o_compute_start = 1'b0;
        o_drain_start   = 1'b0;

        o_busy          = 1'b0;
        o_done          = 1'b0;

        case (state_r)

            ST_IDLE: begin
                o_busy = 1'b0;
            end

            ST_CLEAR_ACC: begin
                o_busy      = 1'b1;
                o_acc_clear = 1'b1;
            end

            ST_START_COMPUTE: begin
                o_busy          = 1'b1;
                o_compute_start = 1'b1;
            end

            ST_START_DRAIN: begin
                o_busy        = 1'b1;
                o_drain_start = 1'b1;
            end

            ST_DONE: begin
                o_done = 1'b1;
            end

            default: begin
                o_busy = 1'b1;
            end

        endcase
    end

    // Metadata outputs

    assign o_m_base      = m_base_r;
    assign o_n_base      = n_base_r;

    assign o_active_rows = active_rows_r;
    assign o_active_cols = active_cols_r;

    assign o_k_size      = k_size_r;

endmodule
