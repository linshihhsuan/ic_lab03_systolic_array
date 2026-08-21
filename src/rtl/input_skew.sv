// verilog_lint: waive-start
//////////////////////////////////////////////////////////////////////////////////
// Company: AGILAB
// Engineer: Undergraduate Student
//
// Create Date: 2026/08/21 14:23:45
// Design Type: RTL (Synthesizable Circuit)
// Design Name: ic_lab03_systolic_array
// Module Name: input_skew
// Project Name:
// Target Devices:
// Tool Versions:
// Description: 建立 input_skew 模組
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

module input_skew #(

    parameter int DATA_WIDTH = 32,
    parameter int S_MAX      = 32,
    parameter int MAX_K      = 108,

    parameter int ACTIVE_WIDTH =
        (S_MAX <= 1) ? 1 : $clog2(S_MAX + 1),

    parameter int K_WIDTH =
        (MAX_K <= 1) ? 1 : $clog2(MAX_K + 1),

    parameter int WAVE_WIDTH =
        (MAX_K + 2*S_MAX <= 1)
        ? 1
        : $clog2(MAX_K + 2*S_MAX + 1)

)(

    // System input
    input logic i_clk,
    input logic i_rst_n,

    // Control
    // Pulse one cycle before starting a new output tile.
    input logic i_start,

    // Controller allows the systolic calculation to advance.
    input logic i_run_en,

    // Runtime configuration

    input logic [ACTIVE_WIDTH-1:0] i_active_rows,
    input logic [ACTIVE_WIDTH-1:0] i_active_cols,

    // Full K dimension of current matrix multiplication.
    input logic [K_WIDTH-1:0] i_k_len,

    // A FIFO bank
    // Lane r contains:
    //
    // A[row=r][0], A[row=r][1], ..., A[row=r][K-1]
    input logic signed [DATA_WIDTH-1:0] i_a_head_data [S_MAX],
    input logic [S_MAX-1:0] i_a_head_valid,

    output logic [S_MAX-1:0] o_a_pop,

    // B FIFO bank
    // Lane c contains:
    //
    // B[0][col=c], B[1][col=c], ..., B[K-1][col=c]
    input logic signed [DATA_WIDTH-1:0] i_b_head_data [S_MAX],
    input logic [S_MAX-1:0] i_b_head_valid,

    output logic [S_MAX-1:0] o_b_pop,

    // Skewed A boundary -> systolic_array
    output logic signed [DATA_WIDTH-1:0] o_a_data [S_MAX],
    output logic [S_MAX-1:0] o_a_valid,

    // Skewed B boundary -> systolic_array
    output logic signed [DATA_WIDTH-1:0] o_b_data [S_MAX],
    output logic [S_MAX-1:0] o_b_valid,

    // Global step control
    // Connect directly to systolic_array.i_step_en
    output logic o_step_en,

    output logic o_busy,
    output logic o_done
);

    // Internal state
    logic [WAVE_WIDTH-1:0] wave_cnt_r;
    logic                  active_r;

    logic a_need [S_MAX];
    logic b_need [S_MAX];

    logic all_required_ready;
    logic config_valid;
    logic last_wave;

    integer r;
    integer c;

    integer wave_i;
    integer k_i;
    integer rows_i;
    integer cols_i;
    integer total_steps_i;


    // Combinational skew / FIFO scheduling
    always_comb begin

        wave_i = wave_cnt_r;
        k_i    = i_k_len;
        rows_i = i_active_rows;
        cols_i = i_active_cols;

        // Runtime configuration validity
        config_valid =
            (k_i > 0) &&
            (rows_i > 0) &&
            (rows_i <= S_MAX) &&
            (cols_i > 0) &&
            (cols_i <= S_MAX);



        // Total systolic execution length
        // Last MAC:
        // wave = K + active_rows + active_cols - 3
        // Therefore total number of step cycles:
        // K + active_rows + active_cols - 2
        total_steps_i =
            k_i +
            rows_i +
            cols_i -
            2;

        last_wave =
            config_valid &&
            (wave_i == (total_steps_i - 1));



        // Check required FIFO data
        all_required_ready = 1'b1;

        // A lanes
        for (r=0; r<S_MAX; r=r+1) begin

            // A row r starts r waves later.
            //
            // k = wave - r
            //
            // valid when:
            //
            // 0 <= wave-r < K
            a_need[r] =
                (r < rows_i) &&
                (wave_i >= r) &&
                ((wave_i - r) < k_i);


            // If this wave needs this FIFO but data is not ready,
            // stall the complete systolic array.
            if (a_need[r] &&
                !i_a_head_valid[r]) begin

                all_required_ready = 1'b0;

            end
        end



        // B lanes
        for (c=0; c<S_MAX; c=c+1) begin

            // B column c starts c waves later.
            //
            // k = wave - c
            b_need[c] =
                (c < cols_i) &&
                (wave_i >= c) &&
                ((wave_i - c) < k_i);

            if (b_need[c] &&
                !i_b_head_valid[c]) begin

                all_required_ready = 1'b0;

            end
        end



        // Global lockstep step enable
        o_step_en =
            active_r &&
            i_run_en &&
            config_valid &&
            all_required_ready;



        // A FIFO -> Array boundary
        for (r = 0; r < S_MAX; r = r + 1) begin

            // Default = bubble / zero padding
            o_a_data[r]  = '0;
            o_a_valid[r] = 1'b0;
            o_a_pop[r]   = 1'b0;

            if (o_step_en &&
                a_need[r]) begin

                o_a_data[r]  =
                    i_a_head_data[r];

                o_a_valid[r] =
                    1'b1;

                o_a_pop[r] =
                    1'b1;

            end
        end

        // B FIFO -> Array boundary
        for (c = 0; c < S_MAX; c = c + 1) begin

            // Default = bubble / zero padding
            o_b_data[c]  = '0;
            o_b_valid[c] = 1'b0;
            o_b_pop[c]   = 1'b0;

            if (o_step_en &&
                b_need[c]) begin

                o_b_data[c] =
                    i_b_head_data[c];

                o_b_valid[c] =
                    1'b1;

                o_b_pop[c] =
                    1'b1;

            end
        end

    end


    // Wave counter
    always_ff @(posedge i_clk) begin

        if (!i_rst_n) begin

            wave_cnt_r <= '0;
            active_r   <= 1'b0;
            o_done     <= 1'b0;

        end else begin

            // o_done is a one-cycle pulse
            o_done <= 1'b0;

            // Start new output tile
            if (i_start) begin

                wave_cnt_r <= '0;

                // Reject an invalid tile instead of entering a busy
                // state that can never assert o_step_en or o_done.
                if (config_valid) begin
                    active_r <= 1'b1;
                end
                else begin
                    active_r <= 1'b0;
                    o_done   <= 1'b1;
                end

            end

            // Advance only when whole array advances
            else if (o_step_en) begin

                if (last_wave) begin

                    wave_cnt_r <= '0;
                    active_r   <= 1'b0;
                    o_done     <= 1'b1;

                end else begin

                    wave_cnt_r <=
                        wave_cnt_r + 1'b1;

                end
            end
        end
    end


    // Status
    assign o_busy = active_r;


endmodule
