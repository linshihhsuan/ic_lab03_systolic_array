// verilog_lint: waive-start
//////////////////////////////////////////////////////////////////////////////////
// Company: AGILAB
// Engineer: Undergraduate Student
//
// Create Date: 2026/08/21 15:24:51
// Design Type: RTL (Synthesizable Circuit)
// Design Name: ic_lab03_systolic_array
// Module Name: systolic_top
// Project Name:
// Target Devices:
// Tool Versions:
// Description: 建立 Systolic Array 的 top module
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

module systolic_top #(

    parameter integer DATA_WIDTH     = 32,
    parameter integer ACC_WIDTH      = 71,

    parameter integer S_MAX          = 32,

    parameter integer MAX_M          = 256,
    parameter integer MAX_K          = 108,
    parameter integer MAX_N          = 64,

    parameter integer IN_FIFO_DEPTH  = 128,
    // By default the result FIFO can hold one complete maximum-size
    // output matrix.  This allows software to wait for o_done before
    // beginning to read results without deadlocking the drain path.
    parameter integer OUT_FIFO_DEPTH = MAX_M * MAX_N

)(
    input logic i_clk,
    input logic i_rst_n,

    // ============================================================
    // GEMM configuration
    // ============================================================

    input logic i_start,

    input logic [$clog2(MAX_M+1)-1:0] i_m_size,
    input logic [$clog2(MAX_K+1)-1:0] i_k_size,
    input logic [$clog2(MAX_N+1)-1:0] i_n_size,

    // ============================================================
    // A FIFO bank write interface
    // ============================================================

    input logic [S_MAX-1:0] i_a_wren,

    input logic signed [DATA_WIDTH-1:0] i_a_wdata [S_MAX],  // [0:S_MAX-1]

    output logic [S_MAX-1:0] o_a_full,

    // ============================================================
    // B FIFO bank write interface
    // ============================================================

    input logic [S_MAX-1:0] i_b_wren,

    input logic signed [DATA_WIDTH-1:0]
        i_b_wdata [S_MAX],

    output logic [S_MAX-1:0] o_b_full,

    // ============================================================
    // Result FIFO read interface
    // ============================================================

    input  logic i_result_rden,

    output logic signed [ACC_WIDTH-1:0] o_result_data,

    output logic o_result_data_vld,
    output logic o_result_empty,
    output logic o_result_full,

    // ============================================================
    // Status
    // ============================================================

    output logic o_busy,
    output logic o_done,
    output logic o_cfg_error
);

    // ============================================================
    // Width definitions
    // ============================================================

    localparam integer MW =
        $clog2(MAX_M + 1);

    localparam integer KW =
        $clog2(MAX_K + 1);

    localparam integer NW =
        $clog2(MAX_N + 1);

    localparam integer SW =
        $clog2(S_MAX + 1);

    localparam integer PEIDXW =
        (S_MAX <= 1) ? 1 : $clog2(S_MAX);

    // ============================================================
    // Configuration registers
    // ============================================================

    logic [MW-1:0] m_size_r;
    logic [KW-1:0] k_size_r;
    logic [NW-1:0] n_size_r;

    // ============================================================
    // Top FSM
    // ============================================================

    typedef enum logic [2:0] {
        TOP_IDLE,
        TOP_SIZE_START,
        TOP_SIZE_WAIT,
        TOP_TILE_START,
        TOP_RUN,
        TOP_DONE,
        TOP_ERROR
    } top_state_t;

    top_state_t top_state_r;
    top_state_t top_state_n;

    // ============================================================
    // size_selector signals
    // ============================================================

    logic size_start;
    logic size_done;
    logic size_config_valid;

    logic [SW-1:0] s_active;

    // ============================================================
    // tile_controller signals
    // ============================================================

    logic tile_start;

    logic tile_acc_clear;
    logic tile_compute_start;
    logic tile_drain_start;

    logic tile_done;

    logic [MW-1:0] tile_m_base;
    logic [NW-1:0] tile_n_base;

    logic [SW-1:0] active_rows;
    logic [SW-1:0] active_cols;

    logic [KW-1:0] tile_k_size;

    logic compute_done;
    logic drain_done;

    // ============================================================
    // A FIFO bank signals
    // ============================================================

    logic signed [DATA_WIDTH-1:0]
        a_head_data [S_MAX];

    logic [S_MAX-1:0] a_head_valid;
    logic [S_MAX-1:0] a_pop;

    // ============================================================
    // B FIFO bank signals
    // ============================================================

    logic signed [DATA_WIDTH-1:0]
        b_head_data [S_MAX];

    logic [S_MAX-1:0] b_head_valid;
    logic [S_MAX-1:0] b_pop;

    // ============================================================
    // input_skew → systolic_array
    // ============================================================

    logic signed [DATA_WIDTH-1:0]
        skew_a_data [S_MAX];

    logic signed [DATA_WIDTH-1:0]
        skew_b_data [S_MAX];

    logic [S_MAX-1:0] skew_a_valid;
    logic [S_MAX-1:0] skew_b_valid;

    logic skew_step_en;
    logic skew_done;

    // ============================================================
    // result_drain ↔ systolic_array
    // ============================================================

    logic [PEIDXW-1:0] drain_pe_row;
    logic [PEIDXW-1:0] drain_pe_col;

    logic signed [ACC_WIDTH-1:0]
        selected_pe_acc;

    logic signed [ACC_WIDTH-1:0]
        pe_acc_bus [S_MAX][S_MAX];

    // ============================================================
    // Drain output
    // ============================================================

    logic signed [ACC_WIDTH-1:0]
        drain_result_data;

    logic drain_result_valid;
    logic drain_result_ready;

    // ============================================================
    // Output FIFO
    // ============================================================

    logic out_fifo_wren;

    // ============================================================
    // Top FSM next-state
    // ============================================================

    always_comb begin

        top_state_n = top_state_r;

        case (top_state_r)

            // --------------------------------------------------------
            // Wait for a new GEMM command
            // --------------------------------------------------------
            TOP_IDLE: begin

                if (i_start)
                    top_state_n = TOP_SIZE_START;

            end


            // --------------------------------------------------------
            // One-cycle pulse to start size_selector
            // --------------------------------------------------------
            TOP_SIZE_START: begin

                top_state_n = TOP_SIZE_WAIT;

            end


            // --------------------------------------------------------
            // Wait until S_active calculation finishes
            // --------------------------------------------------------
            TOP_SIZE_WAIT: begin

                if (size_done) begin
                    if (!size_config_valid)
                        top_state_n = TOP_ERROR;
                    else
                        top_state_n = TOP_TILE_START;
                end

            end


            // --------------------------------------------------------
            // One-cycle pulse to start tile_controller
            // --------------------------------------------------------
            TOP_TILE_START: begin

                top_state_n = TOP_RUN;

            end


            // --------------------------------------------------------
            // Execute all M/N tiles
            // --------------------------------------------------------
            TOP_RUN: begin

                if (tile_done)
                    top_state_n = TOP_DONE;

            end


            // --------------------------------------------------------
            // One-cycle done state
            // --------------------------------------------------------
            TOP_DONE: begin

                top_state_n = TOP_IDLE;

            end


            // --------------------------------------------------------
            // Configuration error
            // --------------------------------------------------------
            TOP_ERROR: begin

                top_state_n = TOP_IDLE;

            end


            // --------------------------------------------------------
            default: begin

                top_state_n = TOP_IDLE;

            end

        endcase

    end

    // ============================================================
    // Top sequential logic
    // ============================================================

    always_ff @(posedge i_clk) begin

        if (!i_rst_n) begin

            top_state_r <= TOP_IDLE;

            m_size_r <= '0;
            k_size_r <= '0;
            n_size_r <= '0;

        end
        else begin

            top_state_r <= top_state_n;

            // Capture one GEMM configuration.
            if ((top_state_r == TOP_IDLE) &&
                i_start) begin

                m_size_r <= i_m_size;
                k_size_r <= i_k_size;
                n_size_r <= i_n_size;

            end

        end

    end

    // ============================================================
    // Start pulse generation
    // ============================================================

    always_comb begin

        size_start = 1'b0;
        tile_start = 1'b0;

        case (top_state_r)

            TOP_SIZE_START: begin
                size_start = 1'b1;
            end

            TOP_TILE_START: begin
                tile_start = 1'b1;
            end

            default: begin
                size_start = 1'b0;
                tile_start = 1'b0;
            end

        endcase

    end

    // ============================================================
    // Top status
    // ============================================================

    always_comb begin

        o_busy      = 1'b0;
        o_done      = 1'b0;
        o_cfg_error = 1'b0;

        case (top_state_r)

            TOP_IDLE: begin
                o_busy = 1'b0;
            end

            TOP_DONE: begin
                o_busy = 1'b0;
                o_done = 1'b1;
            end

            TOP_ERROR: begin
                o_busy      = 1'b0;
                o_cfg_error = 1'b1;
            end

            default: begin
                o_busy = 1'b1;
            end

        endcase

    end


    // ============================================================
    // Stage13.6
    // size_selector
    // ============================================================

    size_selector #(
        .S_MAX (S_MAX),
        .MAX_M (MAX_M),
        .MAX_K (MAX_K),
        .MAX_N (MAX_N)
    ) u_size_selector (
        .i_clk       (i_clk),
        .i_rst_n     (i_rst_n),

        .i_start     (size_start),

        .i_m    (m_size_r),
        .i_k    (k_size_r),
        .i_n    (n_size_r),

        .o_s_opt  (s_active),
        .o_best_cycles  (),

        .o_busy      (),
        .o_done      (size_done),
        .o_config_valid (size_config_valid)
    );


    // ============================================================
    // Stage13.7
    // tile_controller
    // ============================================================

    tile_controller #(
        .S_MAX (S_MAX),
        .MAX_M (MAX_M),
        .MAX_K (MAX_K),
        .MAX_N (MAX_N)
    ) u_tile_controller (
        .i_clk          (i_clk),
        .i_rst_n        (i_rst_n),

        .i_start        (tile_start),

        .i_m_size       (m_size_r),
        .i_k_size       (k_size_r),
        .i_n_size       (n_size_r),

        .i_s_active     (s_active),

        .i_compute_done (compute_done),
        .i_drain_done   (drain_done),

        .o_acc_clear    (tile_acc_clear),
        .o_compute_start(tile_compute_start),
        .o_drain_start  (tile_drain_start),

        .o_m_base       (tile_m_base),
        .o_n_base       (tile_n_base),

        .o_active_rows  (active_rows),
        .o_active_cols  (active_cols),

        .o_k_size       (tile_k_size),

        .o_busy         (),
        .o_done         (tile_done)
    );


    // ============================================================
    // Stage13.2
    // A FIFO bank
    // ============================================================

    fifo_bank #(
        .NUM_LANES  (S_MAX),
        .DATA_WIDTH (DATA_WIDTH),
        .DEPTH      (IN_FIFO_DEPTH)
    ) u_a_fifo_bank (
        .i_clk        (i_clk),
        .i_rst_n      (i_rst_n),

        .i_wren       (i_a_wren),
        .i_wdata      (i_a_wdata),

        .o_full       (o_a_full),
        .o_empty      (),

        .i_pop        (a_pop),

        .o_head_data  (a_head_data),
        .o_head_valid (a_head_valid)
    );


    // ============================================================
    // Stage13.2
    // B FIFO bank
    // ============================================================

    fifo_bank #(
        .NUM_LANES  (S_MAX),
        .DATA_WIDTH (DATA_WIDTH),
        .DEPTH      (IN_FIFO_DEPTH)
    ) u_b_fifo_bank (
        .i_clk        (i_clk),
        .i_rst_n      (i_rst_n),

        .i_wren       (i_b_wren),
        .i_wdata      (i_b_wdata),

        .o_full       (o_b_full),
        .o_empty      (),

        .i_pop        (b_pop),

        .o_head_data  (b_head_data),
        .o_head_valid (b_head_valid)
    );


    // ============================================================
    // Stage13.5
    // input_skew
    // ============================================================

    input_skew #(
        .DATA_WIDTH (DATA_WIDTH),
        .S_MAX      (S_MAX),
        .MAX_K      (MAX_K)
    ) u_input_skew (
        .i_clk         (i_clk),
        .i_rst_n       (i_rst_n),

        .i_start       (tile_compute_start),

        // Once started, input_skew controls its own lockstep stall.
        .i_run_en      (1'b1),

        .i_active_rows (active_rows),
        .i_active_cols (active_cols),
        .i_k_len       (tile_k_size),

        .i_a_head_data (a_head_data),
        .i_a_head_valid(a_head_valid),

        .i_b_head_data (b_head_data),
        .i_b_head_valid(b_head_valid),

        .o_a_pop       (a_pop),
        .o_b_pop       (b_pop),

        .o_a_data      (skew_a_data),
        .o_a_valid     (skew_a_valid),

        .o_b_data      (skew_b_data),
        .o_b_valid     (skew_b_valid),

        .o_step_en     (skew_step_en),

        .o_busy        (),
        .o_done        (skew_done)
    );


    // ============================================================
    // COMPUTE_DONE CONTRACT
    //
    // IMPORTANT:
    //
    // input_skew.o_done must mean:
    //
    // K + active_rows + active_cols - 2 successful array steps
    // have completed.
    //
    // It must NOT mean simply "last FIFO word was popped".
    // ============================================================

    assign compute_done = skew_done;


    // ============================================================
    // Stage13.4
    // systolic_array
    // ============================================================

    systolic_array #(
        .DATA_WIDTH (DATA_WIDTH),
        .ACC_WIDTH  (ACC_WIDTH),
        .S_MAX      (S_MAX)
    ) u_systolic_array (
        .i_clk        (i_clk),
        .i_rst_n      (i_rst_n),

        // Entire array advances in global lockstep.
        .i_step_en    (skew_step_en),

        // Clear only before starting a new output tile.
        .i_acc_clear  (tile_acc_clear),

        // Left boundary A
        .i_a_data     (skew_a_data),
        .i_a_valid    (skew_a_valid),

        // Top boundary B
        .i_b_data     (skew_b_data),
        .i_b_valid    (skew_b_valid),

        // Runtime active PE region
        .i_active_rows (active_rows),
        .i_active_cols (active_cols),

        .o_acc_bus (pe_acc_bus)
    );

    // result_drain provides a PE coordinate.  Select that element from
    // the full accumulator bus exported by systolic_array.
    always_comb begin
        selected_pe_acc =
            pe_acc_bus[drain_pe_row][drain_pe_col];
    end


    // ============================================================
    // Stage13.8
    // result_drain
    // ============================================================

    result_drain #(
        .S_MAX     (S_MAX),
        .MAX_M     (MAX_M),
        .MAX_N     (MAX_N),
        .ACC_WIDTH (ACC_WIDTH)
    ) u_result_drain (
        .i_clk          (i_clk),
        .i_rst_n        (i_rst_n),

        .i_drain_start  (tile_drain_start),

        .i_m_base       (tile_m_base),
        .i_n_base       (tile_n_base),

        .i_active_rows  (active_rows),
        .i_active_cols  (active_cols),

        .o_pe_row       (drain_pe_row),
        .o_pe_col       (drain_pe_col),

        .i_pe_acc_data  (selected_pe_acc),

        .o_result_data  (drain_result_data),
        .o_result_valid (drain_result_valid),

        .i_result_ready (drain_result_ready),

        .o_c_row        (),
        .o_c_col        (),

        .o_tile_last    (),

        .o_busy         (),
        .o_drain_done   (drain_done)
    );


    // ============================================================
    // Output FIFO write handshake
    //
    // Result ordering is tile-major.  Tiles traverse N first and then
    // M; elements within a tile are emitted in row-major order.
    // ============================================================

    assign drain_result_ready =
        !o_result_full;

    assign out_fifo_wren =
        drain_result_valid &&
        drain_result_ready;


    // ============================================================
    // Stage13.1
    // Output FIFO
    // ============================================================

    sync_fifo #(
        .DATA_WIDTH (ACC_WIDTH),
        .DEPTH      (OUT_FIFO_DEPTH)
    ) u_output_fifo (
        .i_clk      (i_clk),
        .i_rst_n    (i_rst_n),

        .i_wren     (out_fifo_wren),
        .i_data     (drain_result_data),

        .o_full     (o_result_full),

        .i_rden     (i_result_rden),

        .o_data     (o_result_data),
        .o_data_vld (o_result_data_vld),

        .o_empty    (o_result_empty),
        .o_count    ()
    );

endmodule
