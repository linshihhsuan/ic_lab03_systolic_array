// verilog_lint: waive-start
//////////////////////////////////////////////////////////////////////////////////
// Company: AGILAB
// Engineer: Undergraduate Student
//
// Create Date: 2026/08/24 16:54:54
// Design Type: Testbench (Simulation Only)
// Design Name: ic_lab03_systolic_array
// Module Name: tb_sync_fifo
// Project Name:
// Target Devices:
// Tool Versions:
// Description: 建立 sync_fifo.sv 的簡易 Testbench，讀取十筆 input 資料，比對十筆 golden 資料。
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

module tb_sync_fifo;

    parameter int unsigned DATA_WIDTH  = 32;
    parameter int unsigned DEPTH       = 8;
    parameter int unsigned COUNT_WIDTH = 4;
    parameter int NUM_TESTS = 10;

    // DUT signals
    logic i_clk;
    logic i_rst_n;

    // System inputs
    logic                   i_wren;
    logic [DATA_WIDTH-1:0]  i_data;
    logic                   o_full;
    logic                   i_rden;
    logic [DATA_WIDTH-1:0]  o_data;
    logic                   o_data_vld;
    logic                   o_empty;
    logic [COUNT_WIDTH-1:0] o_count;

    // Golden vectors
    logic [33:0] input_vectors  [NUM_TESTS];
    logic [38:0] golden_vectors [NUM_TESTS];

    // 用來比對輸出
    logic                   golden_data_vld;
    logic [DATA_WIDTH-1:0]  golden_data;
    logic [COUNT_WIDTH-1:0] golden_count;
    logic                   golden_empty;
    logic                   golden_full;

    integer test_idx;
    integer error_count;


    // DUT
    sync_fifo #(
        .DATA_WIDTH  (DATA_WIDTH),
        .DEPTH       (DEPTH),
        .COUNT_WIDTH (COUNT_WIDTH)
    ) dut (
        .i_clk      (i_clk),
        .i_rst_n    (i_rst_n),

        .i_wren     (i_wren),
        .i_data     (i_data),
        .o_full     (o_full),

        .i_rden     (i_rden),
        .o_data     (o_data),
        .o_data_vld (o_data_vld),

        .o_empty    (o_empty),
        .o_count    (o_count)
    );


    // Clock
    initial begin
        i_clk = 1'b0;

        forever #4 i_clk = ~i_clk;
    end

    // Main test
    initial begin

        i_rst_n = 1'b0;
        i_wren = 1'b0;
        i_rden = 1'b0;
        i_data = '0;
        error_count = 0;  // integer

        // Read Python-generated vectors
        $readmemh("sync_fifo_input.hex", input_vectors);
        $readmemh("sync_fifo_golden.hex", golden_vectors);

        // 先延遲 2ns，再開始輸入測試值
        repeat (2) @(posedge i_clk);
        @(negedge i_clk);
        i_rst_n = 1'b1;

        $display("");
        $display("=============================================");
        $display("sync_fifo test start");
        $display("=============================================");

        // Apply every Python-generated test vector
        for (test_idx = 0; test_idx < NUM_TESTS; test_idx = test_idx + 1) begin

            // Drive before rising edge
            @(negedge i_clk);
            i_wren = input_vectors[test_idx][33];
            i_rden = input_vectors[test_idx][32];
            i_data = input_vectors[test_idx][31:0];

            // DUT operates on rising edge
            @(posedge i_clk);

            // Wait for nonblocking assignments to settle
            #1;

            // Decode golden
            golden_data_vld = golden_vectors[test_idx][38];
            golden_data     = golden_vectors[test_idx][37:6];
            golden_count    = golden_vectors[test_idx][5:2];
            golden_empty    = golden_vectors[test_idx][1];
            golden_full     = golden_vectors[test_idx][0];

            // Compare
            if (
                (o_data_vld !== golden_data_vld) ||
                (o_data     !== golden_data)     ||
                (o_count    !== golden_count)    ||
                (o_empty    !== golden_empty)    ||
                (o_full     !== golden_full)
            ) begin

                error_count = error_count + 1;

                $display("");
                $display("[ERROR] Test %0d", test_idx);
                $display(
                    "INPUT: WR=%0b RD=%0b DATA=0x%08h",
                    i_wren, i_rden, i_data
                );

                $display(
                    "DUT: VLD=%0b DATA=0x%08h COUNT=%0d EMPTY=%0b FULL=%0b",
                    o_data_vld, o_data, o_count, o_empty, o_full
                );

                $display(
                    "GOLDEN: VLD=%0b DATA=0x%08h COUNT=%0d EMPTY=%0b FULL=%0b",
                    golden_data_vld, golden_data, golden_count,
                    golden_empty, golden_full
                );

            end
            else begin

                $display(
                    "[PASS] %02d | WR=%0b RD=%0b IN=%08h | VLD=%0b OUT=%08h COUNT=%0d",
                    test_idx, i_wren, i_rden, i_data, o_data_vld, o_data, o_count
                );

            end

        end

        // Stop driving
        @(negedge i_clk);

        i_wren = 1'b0;
        i_rden = 1'b0;
        i_data = '0;

        // Final result
        $display("");
        $display("=============================================");

        if (error_count == 0) begin

            $display("ALL SYNC FIFO TESTS PASSED");
            $display("TESTS = %0d", NUM_TESTS);
            $display("PASS RATE = %0d %%", ((NUM_TESTS-error_count)/NUM_TESTS)*100);

        end
        else begin

            $display("SYNC FIFO TEST FAILED");
            $display("ERRORS = %0d", error_count);
            $display("PASS RATE = %0d %%", ((NUM_TESTS-error_count)/NUM_TESTS)*100);

        end

        $display("=============================================");
        $display("");

        $finish;

    end

endmodule
