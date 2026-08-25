// verilog_lint: waive-start
//////////////////////////////////////////////////////////////////////////////////
// Company: AGILAB
// Engineer: Undergraduate Student
//
// Create Date: 2026/08/21 13:16:32
// Design Type: RTL (Synthesizable Circuit)
// Design Name: ic_lab_systolic_array
// Module Name: fifo_bank
// Project Name:
// Target Devices:
// Tool Versions:
// Description: 建立由單一 FIFO 串成的 FIFO BANK 模組，作為 PE Array 的 Buffer
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

module fifo_bank #(

    parameter int unsigned NUM_LANES  = 32,
    parameter int unsigned DATA_WIDTH = 32,
    parameter int unsigned DEPTH      = 128

)(

    // 系統輸入
    input logic i_clk,
    input logic i_rst_n,

    // 寫入致能及寫入資料
    input logic [NUM_LANES-1:0] i_wren,
    input logic signed [DATA_WIDTH-1:0] i_wdata [NUM_LANES],

    // Head Buffer 資料及有效訊號
    // i_pop 由 input_skew 傳入
    output logic signed [DATA_WIDTH-1:0] o_head_data [NUM_LANES],
    output logic [NUM_LANES-1:0] o_head_valid,
    input  logic [NUM_LANES-1:0] i_pop,

    // Status
    output logic [NUM_LANES-1:0] o_full,
    output logic [NUM_LANES-1:0] o_empty

);

    // FIFO 內部訊號
    logic [NUM_LANES-1:0] fifo_rden;
    logic signed [DATA_WIDTH-1:0] fifo_rdata [NUM_LANES];
    logic [NUM_LANES-1:0] fifo_rdata_vld;

    // Head buffers 內部訊號
    logic signed [DATA_WIDTH-1:0] head_data_r [NUM_LANES];
    logic [NUM_LANES-1:0] head_valid_r;

    // 防止掏空整個 FIFO
    logic [NUM_LANES-1:0] refill_pending_r;

    // Output assignments
    // 可以直接 assign
    always_comb begin
        o_head_data  = head_data_r;
        o_head_valid = head_valid_r;
    end

    // Generate FIFO lanes
    genvar lane;

    generate
        for (lane=0; lane<NUM_LANES; lane++) begin : gen_FIFO_LANE

            sync_fifo #(
                .DATA_WIDTH (DATA_WIDTH),
                .DEPTH      (DEPTH)
            ) u_sync_fifo (
                .i_clk       (i_clk),
                .i_rst_n     (i_rst_n),

                .i_wren      (i_wren[lane]),
                .i_data      (i_wdata[lane]),
                .o_full      (o_full[lane]),

                .i_rden      (fifo_rden[lane]),
                .o_data      (fifo_rdata[lane]),
                .o_data_vld  (fifo_rdata_vld[lane]),

                .o_empty     (o_empty[lane]),
                .o_count     ()
            );

        end
    endgenerate

    // Read-ahead request
    //
    // Fetch when:
    //   1. head buffer empty
    //   2. FIFO contains data
    //   3. no read already outstanding
    //
    // Or when current head is popped and another FIFO word exists.

    always_comb begin
        fifo_rden = '0;

        for (int j=0; j<NUM_LANES; j++) begin

            if (!refill_pending_r[j]) begin

                if (!head_valid_r[j] && !o_empty[j]) begin
                    fifo_rden[j] = 1'b1;
                end

                else if (
                    head_valid_r[j] &&
                    i_pop[j] &&
                    !o_empty[j]
                ) begin
                    fifo_rden[j] = 1'b1;
                end

            end
        end
    end

    // Head buffer control
    always_ff @(posedge i_clk) begin

        if (!i_rst_n) begin
            head_valid_r      <= '0;
            refill_pending_r  <= '0;

            for (int j=0; j<NUM_LANES; j++) begin
                head_data_r[j] <= '0;
            end
        end
        else begin

            for (int j=0; j<NUM_LANES; j++) begin

                // Consumer pops current head
                // head_valid 要做歸零
                if (i_pop[j] && head_valid_r[j]) begin
                    head_valid_r[j] <= 1'b0;
                end

                // Track synchronous FIFO read request
                if (fifo_rden[j]) begin
                    refill_pending_r[j] <= 1'b1;
                end

                // FIFO returns requested word
                if (fifo_rdata_vld[j]) begin
                    head_data_r[j]      <= fifo_rdata[j];
                    head_valid_r[j]     <= 1'b1;
                    refill_pending_r[j] <= 1'b0;
                end

            end
        end
    end

endmodule
