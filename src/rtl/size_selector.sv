// verilog_lint: waive-start
//////////////////////////////////////////////////////////////////////////////////
// Company: AGILAB
// Engineer: Undergraduate Student
//
// Create Date: 2026/08/21 14:50:14
// Design Type: RTL (Synthesizable Circuit)
// Design Name: ic_lab03_systolic_array
// Module Name: size_selector
// Project Name:
// Target Devices:
// Tool Versions:
// Description: 建立一個 S 的搜尋器，不合成除法器。
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

module size_selector #(

    parameter int MAX_M = 256,
    parameter int MAX_K = 108,
    parameter int MAX_N = 64,
    parameter int S_MAX = 32,

    parameter int M_WIDTH =
        (MAX_M <= 1) ? 1 : $clog2(MAX_M + 1),

    parameter int K_WIDTH =
        (MAX_K <= 1) ? 1 : $clog2(MAX_K + 1),

    parameter int N_WIDTH =
        (MAX_N <= 1) ? 1 : $clog2(MAX_N + 1),

    parameter int S_WIDTH =
        (S_MAX <= 1) ? 1 : $clog2(S_MAX + 1),

    // Conservative upper bound for ideal, non-stalled execution cost.
    parameter int COST_WIDTH = $clog2( MAX_M * MAX_N * (MAX_K + 2*S_MAX + 7) + 1 )
)(
    // 系統輸入
    input  logic i_clk,
    input  logic i_rst_n,

    // 控制訊號，由 tile_controller 傳入
    input  logic i_start,

    // Runtime matrix dimensions.
    input  logic [M_WIDTH-1:0] i_m,
    input  logic [K_WIDTH-1:0] i_k,
    input  logic [N_WIDTH-1:0] i_n,

    // s_active 的最佳解
    output logic [S_WIDTH-1:0] o_s_opt,

    // Estimated cycle cost corresponding to o_s_opt.
    output logic [COST_WIDTH-1:0] o_best_cycles,

    // Status.
    output logic o_busy,
    output logic o_done,
    output logic o_config_valid
);


    // Internal registers
    logic [M_WIDTH-1:0] m_r;
    logic [K_WIDTH-1:0] k_r;
    logic [N_WIDTH-1:0] n_r;

    logic [S_WIDTH-1:0] search_s_r;
    logic [S_WIDTH-1:0] best_s_r;

    logic [COST_WIDTH-1:0] best_cost_r;

    logic active_r;

    // Current candidate calculation
    logic [COST_WIDTH-1:0] current_cost;

    integer s_i;
    integer tile_m_i;
    integer tile_n_i;
    integer cost_i;


    always_comb begin

        s_i = search_s_r;

        tile_m_i    = 0;
        tile_n_i    = 0;
        cost_i       = 0;

        current_cost = '0;


        if (s_i >= 1) begin

            // ceil(M / S)
            // 為了要取無條件進入
            // 修改成 ceil(a / b) = (a + b - 1) / b
            tile_m_i =
                (m_r + s_i - 1) / s_i;

            // ceil(N / S)
            // 取無條件進入
            tile_n_i =
                (n_r + s_i - 1) / s_i;

            // 公式 Total clock
            cost_i =
                tile_m_i *
                tile_n_i *
                (k_r + 3*s_i - 2);

            current_cost =
                cost_i[COST_WIDTH-1:0];

        end

    end


    // Sequential exhaustive search
    always_ff @(posedge i_clk) begin

        if (!i_rst_n) begin

            m_r            <= '0;
            k_r            <= '0;
            n_r            <= '0;

            search_s_r     <= '0;
            best_s_r       <= '0;

            best_cost_r    <= {COST_WIDTH{1'b1}};

            o_s_opt        <= '0;
            o_best_cycles  <= '0;

            active_r       <= 1'b0;
            o_done         <= 1'b0;
            o_config_valid <= 1'b0;

        end else begin

            // o_done = one-cycle pulse
            o_done <= 1'b0;

            // size_selector 一旦開始工作，就不再直接依賴外面的 i_m/i_k/i_n
            if (i_start && !active_r) begin

                // Latch matrix dimensions.
                m_r <= i_m;
                k_r <= i_k;
                n_r <= i_n;

                if (

                    (i_m >= 1) &&
                    (i_m <= MAX_M) &&
                    (i_k >= 1) &&
                    (i_k <= MAX_K) &&
                    (i_n >= 1) &&
                    (i_n <= MAX_N)

                ) begin

                    // 現在要測的 S = 1
                    search_s_r <=
                        {{(S_WIDTH-1){1'b0}}, 1'b1};

                    // 目前最佳的 S = 1
                    best_s_r <=
                        {{(S_WIDTH-1){1'b0}}, 1'b1};

                    // 目前最佳 cost = ∞，就是 unsigned 最大值
                    best_cost_r <=
                        {COST_WIDTH{1'b1}};

                    active_r       <= 1'b1;
                    o_config_valid <= 1'b1;

                end else begin

                    search_s_r <= '0;
                    best_s_r   <= '0;

                    best_cost_r <=
                        {COST_WIDTH{1'b1}};

                    o_s_opt       <= '0;
                    o_best_cycles <= '0;

                    active_r       <= 1'b0;
                    o_config_valid <= 1'b0;
                    o_done         <= 1'b1;

                end
            end



            // Search S = 1 ... S_MAX
            else if (active_r) begin

                // Strict <
                //
                // Therefore:
                // equal cost -> keep previous smaller S.
                if (current_cost < best_cost_r) begin

                    best_cost_r <= current_cost;
                    best_s_r    <= search_s_r;

                end


                // Last candidate
                if (search_s_r == S_MAX) begin

                    active_r <= 1'b0;
                    o_done   <= 1'b1;


                    // Current S_MAX might itself be the winner,
                    // so final output must include this comparison.
                    if (current_cost < best_cost_r) begin

                        o_s_opt <=
                            search_s_r;

                        o_best_cycles <=
                            current_cost;

                    end else begin

                        o_s_opt <=
                            best_s_r;

                        o_best_cycles <=
                            best_cost_r;

                    end


                    search_s_r <= '0;

                end

                // Next candidate
                else begin

                    search_s_r <=
                        search_s_r + 1'b1;

                end
            end
        end
    end


    // Status

    assign o_busy = active_r;


endmodule
