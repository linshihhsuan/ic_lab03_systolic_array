// verilog_lint: waive-start
//////////////////////////////////////////////////////////////////////////////////
// Company: AGILAB
// Engineer: Undergraduate Student
//
// Create Date: 2026/08/24 18:18:53
// Design Type: Testbench (Simulation Only)
// Design Name: ic_lab03_systolic_array
// Module Name: tb_fifo_bank
// Project Name:
// Target Devices:
// Tool Versions:
// Description: 建立 fifo_bank.sv 的 Testbench，用來測試功能目前是多 lane 的 sync_fifo +
//              每 lane 一個 read-ahead head buffer；外部不是直接下 rd_en，而是透過 i_pop 消費 o_head_data，
//              bank 會自己產生內部 fifo_rden 補下一筆資料。
// Coding Rules:
//   Type       : Testbench (Simulation Only)
//   SV Syntax  : Testbench (Simulation Only)Full SystemVerilog syntax allowed for simulation
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

`timescale 1ns / 1ps

module tb_fifo_bank;

    parameter int unsigned NUM_LANES  = 4;
    parameter int unsigned DATA_WIDTH = 32;
    parameter int unsigned DEPTH      = 4;
    parameter int NUM_TESTS = 15;

    // DUT signals
    // System imput
    logic i_clk;
    logic i_rst_n;

    logic [NUM_LANES-1:0]         i_wren;
    logic signed [DATA_WIDTH-1:0] i_wdata [NUM_LANES];
    logic signed [DATA_WIDTH-1:0] o_head_data [NUM_LANES];
    logic [NUM_LANES-1:0]         o_head_valid;

    logic [NUM_LANES-1:0]         i_pop;

    logic [NUM_LANES-1:0]         o_full;
    logic [NUM_LANES-1:0]         o_empty;

    // Test vector storage
    logic [135:0] input_vectors [NUM_TESTS];
    logic [139:0] golden_vectors [NUM_TESTS];

    // Golden decoded signals
    logic [NUM_LANES-1:0] golden_head_valid;
    logic [NUM_LANES-1:0] golden_full;
    logic [NUM_LANES-1:0] golden_empty;
    logic signed [DATA_WIDTH-1:0] golden_head_data [NUM_LANES];


    integer test_idx;
    integer lane_idx;
    integer error_count;

    logic cycle_error;

    // DUT
    fifo_bank #(
        .NUM_LANES  (NUM_LANES),
        .DATA_WIDTH (DATA_WIDTH),
        .DEPTH      (DEPTH)
    ) dut (
        .i_clk        (i_clk),
        .i_rst_n      (i_rst_n),

        .i_wren       (i_wren),
        .i_wdata      (i_wdata),

        .o_head_data  (o_head_data),
        .o_head_valid (o_head_valid),
        .i_pop        (i_pop),

        .o_full       (o_full),
        .o_empty      (o_empty)
    );

    // Clock
    initial begin

        i_clk = 1'b0;

        forever #4 i_clk = ~i_clk;

    end

    // Main test
    initial begin

        i_rst_n = 1'b0;
        i_wren = '0;
        i_pop  = '0;

        for (lane_idx = 0; lane_idx < NUM_LANES; lane_idx = lane_idx + 1) begin
            i_wdata[lane_idx] = '0;
        end

        error_count = 0;

        // Load Python generated vectors
        $readmemh("fifo_bank_input.hex",  input_vectors );
        $readmemh("fifo_bank_golden.hex", golden_vectors);

        // 重複兩個 clk，再進行測試
        repeat (2) @(posedge i_clk);
        @(negedge i_clk);
        i_rst_n = 1'b1;

        $display("");
        $display("=============================================");
        $display("FIFO BANK TEST START");
        $display("=============================================");

        for (
            test_idx = 0;
            test_idx < NUM_TESTS;
            test_idx = test_idx + 1
        ) begin

            // Drive stimulus at negative edge
            @(negedge i_clk);

            // Control
            i_wren = input_vectors[test_idx][135:132];
            i_pop  = input_vectors[test_idx][131:128];

            // Write data
            i_wdata[3] = input_vectors[test_idx][127:96];
            i_wdata[2] = input_vectors[test_idx][95:64];
            i_wdata[1] = input_vectors[test_idx][63:32];
            i_wdata[0] = input_vectors[test_idx][31:0];

            // DUT operates on positive edge
            @(posedge i_clk);

            #1;

            // Decode Python golden
            golden_head_valid =
                golden_vectors[test_idx][139:136];

            golden_full =
                golden_vectors[test_idx][135:132];

            golden_empty =
                golden_vectors[test_idx][131:128];


            golden_head_data[3] =
                golden_vectors[test_idx][127:96];

            golden_head_data[2] =
                golden_vectors[test_idx][95:64];

            golden_head_data[1] =
                golden_vectors[test_idx][63:32];

            golden_head_data[0] =
                golden_vectors[test_idx][31:0];


            // Compare

            cycle_error = 1'b0;

            // Status comparison
            if (o_head_valid !== golden_head_valid) begin

                cycle_error = 1'b1;

                $display(
                    "[ERROR] Cycle %0d HEAD_VALID DUT=%04b GOLDEN=%04b",
                    test_idx,
                    o_head_valid,
                    golden_head_valid
                );

            end


            if (o_empty !== golden_empty) begin

                cycle_error = 1'b1;

                $display(
                    "[ERROR] Cycle %0d EMPTY DUT=%04b GOLDEN=%04b",
                    test_idx,
                    o_empty,
                    golden_empty
                );

            end


            if (o_full !== golden_full) begin

                cycle_error = 1'b1;

                $display(
                    "[ERROR] Cycle %0d FULL DUT=%04b GOLDEN=%04b",
                    test_idx,
                    o_full,
                    golden_full
                );

            end

            // Head data comparison
            //
            // Only compare data when head is valid.
            // Invalid head contents are don't-care.
            for (
                lane_idx = 0;
                lane_idx < NUM_LANES;
                lane_idx = lane_idx + 1
            ) begin

                if (golden_head_valid[lane_idx]) begin

                    if (
                        o_head_data[lane_idx]
                        !== golden_head_data[lane_idx]
                    ) begin

                        cycle_error = 1'b1;

                        $display(
                            "[ERROR] Cycle %0d Lane %0d HEAD DUT=%08h GOLDEN=%08h",
                            test_idx,
                            lane_idx,
                            o_head_data[lane_idx],
                            golden_head_data[lane_idx]
                        );

                    end

                end

            end

            // Result for this cycle
            if (cycle_error) begin

                error_count = error_count + 1;

                $display(
                    "        WREN=%04b POP=%04b",
                    i_wren,
                    i_pop
                );

            end

            else begin

                $display(
                    "[PASS] C%02d | WREN=%04b POP=%04b | HV=%04b | HEAD: %08h %08h %08h %08h",
                    test_idx,
                    i_wren,
                    i_pop,
                    o_head_valid,
                    o_head_data[3],
                    o_head_data[2],
                    o_head_data[1],
                    o_head_data[0]
                );

            end

        end

        // Stop stimulus
        @(negedge i_clk);

        i_wren = '0;
        i_pop  = '0;

        for (
            lane_idx = 0;
            lane_idx < NUM_LANES;
            lane_idx = lane_idx + 1
        ) begin

            i_wdata[lane_idx] = '0;

        end

        // Final result
        $display("");
        $display("=============================================");

        if (error_count == 0) begin

            $display("ALL FIFO BANK TESTS PASSED");
            $display("TESTS = %0d", NUM_TESTS);
            $display("PASS RATE = %0d%%", ((NUM_TESTS-error_count)/NUM_TESTS)*100);

        end
        else begin

            $display("FIFO BANK TEST FAILED");
            $display("ERRORS = %0d", error_count);
            $display("PASS RATE = %0d%%", ((NUM_TESTS-error_count)/NUM_TESTS)*100);

        end

        $display("=============================================");
        $display("");

        $finish;

    end


endmodule
