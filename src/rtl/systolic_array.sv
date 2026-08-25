// verilog_lint: waive-start
//////////////////////////////////////////////////////////////////////////////////
// Company: AGILAB
// Engineer: Undergraduate Student
//
// Create Date: 2026/08/21 13:58:30
// Design Type: RTL (Synthesizable Circuit)
// Design Name: ic_lab03_systolic_array
// Module Name: systolic_array
// Project Name:
// Target Devices:
// Tool Versions:
// Description: 使用 generate 建立實際的 S_MAX × S_MAX PE mesh。
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

module systolic_array #(

    parameter int DATA_WIDTH    = 32,
    parameter int PRODUCT_WIDTH = 64,
    parameter int ACC_WIDTH     = 71,
    parameter int S_MAX         = 32

)(

    // 系統輸入
    input logic i_clk,
    input logic i_rst_n,

    // Global array control
    // i_step_en 由 input_skew 傳入
    input logic i_step_en,
    input logic i_acc_clear,

    // 需要啟動的 PE 範圍 (active)
    // Active PE range:
    //   row = 0 .. i_active_rows-1
    //   col = 0 .. i_active_cols-1
    input logic [$clog2(S_MAX+1)-1:0] i_active_rows,
    input logic [$clog2(S_MAX+1)-1:0] i_active_cols,

    // Left boundary: A stream
    input logic signed [DATA_WIDTH-1:0] i_a_data [S_MAX],
    input logic [S_MAX-1:0] i_a_valid,

    // Top boundary: B stream
    input logic signed [DATA_WIDTH-1:0] i_b_data [S_MAX],
    input logic [S_MAX-1:0] i_b_valid,

    // PE accumulator bus
    // o_acc_bus[row][col]
    //      ↕
    // C[m_base + row][n_base + col]
    output logic signed [ACC_WIDTH-1:0] o_acc_bus [S_MAX][S_MAX]

);


    // Active row / column masks
    logic [S_MAX-1:0] row_active;
    logic [S_MAX-1:0] col_active;

    genvar r;
    genvar c;

    generate
        for (r = 0; r < S_MAX; r++) begin : gen_ROW_ACTIVE
            assign row_active[r] = (i_active_rows > r);
        end

        for (c = 0; c < S_MAX; c++) begin : gen_COL_ACTIVE
            assign col_active[c] = (i_active_cols > c);
        end
    endgenerate


    // Horizontal A interconnect
    //
    // a_data_link[row][0]
    //      = left boundary
    //
    // a_data_link[row][col+1]
    //      = PE[row][col] output
    logic signed [DATA_WIDTH-1:0]
        a_data_link [S_MAX][S_MAX+1];

    logic
        a_valid_link [S_MAX][S_MAX+1];


    // Vertical B interconnect
    //
    // b_data_link[0][col]
    //      = top boundary
    //
    // b_data_link[row+1][col]
    //      = PE[row][col] output
    logic signed [DATA_WIDTH-1:0]
        b_data_link [S_MAX+1][S_MAX];

    logic
        b_valid_link [S_MAX+1][S_MAX];


    // Left boundary input
    //
    // Invalid / inactive rows are zero padded.

    generate
        for (r=0; r<S_MAX; r++) begin : gen_A_BOUNDARY

            assign a_valid_link[r][0] =
                row_active[r]
                    ? i_a_valid[r]
                    : 1'b0;

            assign a_data_link[r][0] =
                (row_active[r] && i_a_valid[r])
                    ? i_a_data[r]
                    : '0;

        end
    endgenerate


    // Top boundary input
    //
    // Invalid / inactive columns are zero padded.

    generate
        for (c=0; c<S_MAX; c++) begin : gen_B_BOUNDARY

            assign b_valid_link[0][c] =
                col_active[c]
                    ? i_b_valid[c]
                    : 1'b0;

            assign b_data_link[0][c] =
                (col_active[c] && i_b_valid[c])
                    ? i_b_data[c]
                    : '0;

        end
    endgenerate


    // PE Mesh

    generate

        for (r=0; r<S_MAX; r++) begin : gen_PE_ROW

            for (c=0; c<S_MAX; c++) begin : gen_PE_COL

                logic pe_active;

                logic signed [DATA_WIDTH-1:0] pe_a_data_in;
                logic signed [DATA_WIDTH-1:0] pe_b_data_in;

                logic pe_a_valid_in;
                logic pe_b_valid_in;


                // Runtime PE activation
                //
                // Only upper-left:
                //
                // [0 : active_rows-1]
                //          ×
                // [0 : active_cols-1]
                //
                // participates in calculation.

                assign pe_active =
                    row_active[r] &&
                    col_active[c];


                // A input masking

                assign pe_a_valid_in =
                    pe_active &&
                    a_valid_link[r][c];

                assign pe_a_data_in =
                    pe_a_valid_in
                        ? a_data_link[r][c]
                        : '0;


                // B input masking

                assign pe_b_valid_in =
                    pe_active &&
                    b_valid_link[r][c];

                assign pe_b_data_in =
                    pe_b_valid_in
                        ? b_data_link[r][c]
                        : '0;


                // Processing Element

                pe_unit #(
                    .DATA_WIDTH    (DATA_WIDTH),
                    .PRODUCT_WIDTH (PRODUCT_WIDTH),
                    .ACC_WIDTH     (ACC_WIDTH)
                ) u_pe_unit (
                    .i_clk       (i_clk),
                    .i_rst_n     (i_rst_n),

                    .i_step_en   (i_step_en),
                    .i_acc_clear (i_acc_clear),

                    // A: left -> right
                    .i_a_data    (pe_a_data_in),
                    .i_a_valid   (pe_a_valid_in),

                    .o_a_data    (a_data_link[r][c+1]),
                    .o_a_valid   (a_valid_link[r][c+1]),

                    // B: top -> bottom
                    .i_b_data    (pe_b_data_in),
                    .i_b_valid   (pe_b_valid_in),

                    .o_b_data    (b_data_link[r+1][c]),
                    .o_b_valid   (b_valid_link[r+1][c]),

                    // Output Stationary ACC
                    .o_acc_data  (o_acc_bus[r][c])
                );

            end

        end

    endgenerate


endmodule
