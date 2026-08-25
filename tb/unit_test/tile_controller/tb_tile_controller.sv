// verilog_lint: waive-start
//////////////////////////////////////////////////////////////////////////////////
// Company: AGILAB
// Engineer: Undergraduate Student
//
// Create Date: 2026/08/24 19:05:56
// Design Type: Testbench (Simulation Only)
// Design Name: ic_lab03_systolic_array
// Module Name: tb_tile_controller
// Project Name:
// Target Devices:
// Tool Versions:
// Description: 建立 tile_controller.sv 的 Testbench，用來測試功能是否正常
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

module tb_tile_controller;

    parameter integer S_MAX = 32;
    parameter integer MAX_M = 256;
    parameter integer MAX_K = 108;
    parameter integer MAX_N = 64;

    localparam integer MW = $clog2(MAX_M + 1);
    localparam integer KW = $clog2(MAX_K + 1);
    localparam integer NW = $clog2(MAX_N + 1);
    localparam integer SW = $clog2(S_MAX + 1);


    // Clock
    logic i_clk;

    initial begin

        i_clk = 1'b0;

        forever
            #4 i_clk = ~i_clk;  // 125MHz

    end


    // DUT Inputs
    logic i_rst_n;

    logic i_start;

    logic [MW-1:0] i_m_size;
    logic [KW-1:0] i_k_size;
    logic [NW-1:0] i_n_size;

    logic [SW-1:0] i_s_active;

    logic i_compute_done;

    logic i_drain_done;


    // DUT Outputs

    logic o_acc_clear;

    logic o_compute_start;

    logic o_drain_start;


    logic [MW-1:0] o_m_base;

    logic [NW-1:0] o_n_base;


    logic [SW-1:0] o_active_rows;

    logic [SW-1:0] o_active_cols;


    logic [KW-1:0] o_k_size;


    logic o_busy;

    logic o_done;


    // DUT

    tile_controller #(

        .S_MAX (S_MAX),
        .MAX_M (MAX_M),
        .MAX_K (MAX_K),
        .MAX_N (MAX_N)

    ) dut (

        .i_clk (
            i_clk
        ),

        .i_rst_n (
            i_rst_n
        ),


        .i_start (
            i_start
        ),


        .i_m_size (
            i_m_size
        ),

        .i_k_size (
            i_k_size
        ),

        .i_n_size (
            i_n_size
        ),


        .i_s_active (
            i_s_active
        ),


        .i_compute_done (
            i_compute_done
        ),


        .i_drain_done (
            i_drain_done
        ),


        .o_acc_clear (
            o_acc_clear
        ),

        .o_compute_start (
            o_compute_start
        ),

        .o_drain_start (
            o_drain_start
        ),


        .o_m_base (
            o_m_base
        ),

        .o_n_base (
            o_n_base
        ),


        .o_active_rows (
            o_active_rows
        ),

        .o_active_cols (
            o_active_cols
        ),


        .o_k_size (
            o_k_size
        ),


        .o_busy (
            o_busy
        ),

        .o_done (
            o_done
        )

    );


    // File Handling

    integer input_fd;
    integer golden_fd;
    integer input_scan_count;
    integer golden_scan_count;
    string input_file;
    string golden_file;

    // Input File Temporary Variables
    //
    // HEX input format:
    //
    // rst_n
    // start
    // m_size
    // k_size
    // n_size
    // s_active
    // compute_done
    // drain_done
    integer in_rst_n;
    integer in_start;
    integer in_m_size;
    integer in_k_size;
    integer in_n_size;
    integer in_s_active;
    integer in_compute_done;
    integer in_drain_done;

    // Golden File Temporary Variables
    //
    // HEX golden format:
    //
    // acc_clear
    // compute_start
    // drain_start
    // m_base
    // n_base
    // active_rows
    // active_cols
    // k_size
    // busy
    // done
    integer gold_acc_clear;
    integer gold_compute_start;
    integer gold_drain_start;
    integer gold_m_base;
    integer gold_n_base;
    integer gold_active_rows;
    integer gold_active_cols;
    integer gold_k_size;
    integer gold_busy;
    integer gold_done;


    // Statistics
    integer cycle_count;
    integer error_count;

    // Main Test
    initial begin

        // Initial Values

        i_rst_n = 1'b0;
        i_start = 1'b0;
        i_m_size = '0;
        i_k_size = '0;
        i_n_size = '0;
        i_s_active = '0;
        i_compute_done = 1'b0;
        i_drain_done = 1'b0;
        cycle_count = 0;
        error_count = 0;

        // File Name
        //
        // Can be overridden by plusargs:
        //
        // +INPUT_FILE=...
        // +GOLDEN_FILE=...
        if (
            !$value$plusargs(
                "INPUT_FILE=%s",
                input_file
            )
        ) begin

            input_file =
                "tile_controller_input.hex";

        end

        if (
            !$value$plusargs(
                "GOLDEN_FILE=%s",
                golden_file
            )
        ) begin

            golden_file =
                "tile_controller_golden.hex";

        end

        // Open Files
        input_fd = $fopen(
            input_file,
            "r"
        );

        golden_fd = $fopen(
            golden_file,
            "r"
        );

        if (
            input_fd == 0
        ) begin

            $display(
                "[ERROR] Cannot open input file:"
            );

            $display(
                "%s",
                input_file
            );

            $finish;

        end

        if (
            golden_fd == 0
        ) begin

            $display(
                "[ERROR] Cannot open golden file:"
            );

            $display(
                "%s",
                golden_file
            );

            $finish;

        end


        // Test Start

        $display(
            "============================================="
        );

        $display(
            " TILE CONTROLLER TEST START"
        );

        $display(
            "============================================="
        );

        $display(
            "Input File  : %s",
            input_file
        );

        $display(
            "Golden File : %s",
            golden_file
        );

        $display(
            "============================================="
        );

        // Read All Vectors
        while (
            !$feof(input_fd)
            &&
            !$feof(golden_fd)
        ) begin

            // Read Vector Before Falling Edge
            @(negedge i_clk);

            // Read Input HEX
            input_scan_count = $fscanf(

                input_fd,

                "%h %h %h %h %h %h %h %h\n",

                in_rst_n,

                in_start,

                in_m_size,

                in_k_size,

                in_n_size,

                in_s_active,

                in_compute_done,

                in_drain_done

            );


            // Read Golden HEX
            golden_scan_count = $fscanf(

                golden_fd,

                "%h %h %h %h %h %h %h %h %h %h\n",

                gold_acc_clear,

                gold_compute_start,

                gold_drain_start,

                gold_m_base,

                gold_n_base,

                gold_active_rows,

                gold_active_cols,

                gold_k_size,

                gold_busy,

                gold_done

            );


            // fscanf Format Check
            if (
                input_scan_count != 8
            ) begin

                $display(
                    "[ERROR] Input HEX format error."
                );

                $display(
                    "Cycle = %0d",
                    cycle_count
                );

                $finish;

            end

            if (
                golden_scan_count != 10
            ) begin

                $display(
                    "[ERROR] Golden HEX format error."
                );

                $display(
                    "Cycle = %0d",
                    cycle_count
                );

                $finish;

            end

            // Apply DUT Inputs
            i_rst_n =
                in_rst_n[0];

            i_start =
                in_start[0];

            i_m_size =
                in_m_size[MW-1:0];

            i_k_size =
                in_k_size[KW-1:0];

            i_n_size =
                in_n_size[NW-1:0];

            i_s_active =
                in_s_active[SW-1:0];

            i_compute_done =
                in_compute_done[0];

            i_drain_done =
                in_drain_done[0];

            // DUT Updates on Positive Edge
            @(posedge i_clk);

            #1;

            cycle_count =
                cycle_count + 1;

            // Compare o_acc_clear
            if (
                o_acc_clear
                !==
                gold_acc_clear[0]
            ) begin

                $display(
                    "[ERROR][Cycle %0d] o_acc_clear DUT=%0h GOLD=%0h",
                    cycle_count,
                    o_acc_clear,
                    gold_acc_clear
                );

                error_count =
                    error_count + 1;

            end

            // Compare o_compute_start
            if (
                o_compute_start
                !==
                gold_compute_start[0]
            ) begin

                $display(
                    "[ERROR][Cycle %0d] o_compute_start DUT=%0h GOLD=%0h",
                    cycle_count,
                    o_compute_start,
                    gold_compute_start
                );

                error_count =
                    error_count + 1;

            end

            // Compare o_drain_start
            if (
                o_drain_start
                !==
                gold_drain_start[0]
            ) begin

                $display(
                    "[ERROR][Cycle %0d] o_drain_start DUT=%0h GOLD=%0h",
                    cycle_count,
                    o_drain_start,
                    gold_drain_start
                );

                error_count =
                    error_count + 1;

            end

            // Compare o_m_base
            if (
                o_m_base
                !==
                gold_m_base[MW-1:0]
            ) begin

                $display(
                    "[ERROR][Cycle %0d] o_m_base DUT=%0h GOLD=%0h",
                    cycle_count,
                    o_m_base,
                    gold_m_base
                );

                error_count =
                    error_count + 1;

            end

            // Compare o_n_base
            if (
                o_n_base
                !==
                gold_n_base[NW-1:0]
            ) begin

                $display(
                    "[ERROR][Cycle %0d] o_n_base DUT=%0h GOLD=%0h",
                    cycle_count,
                    o_n_base,
                    gold_n_base
                );

                error_count =
                    error_count + 1;

            end

            // Compare o_active_rows
            if (
                o_active_rows
                !==
                gold_active_rows[SW-1:0]
            ) begin

                $display(
                    "[ERROR][Cycle %0d] o_active_rows DUT=%0h GOLD=%0h",
                    cycle_count,
                    o_active_rows,
                    gold_active_rows
                );

                error_count =
                    error_count + 1;

            end

            // Compare o_active_cols
            if (
                o_active_cols
                !==
                gold_active_cols[SW-1:0]
            ) begin

                $display(
                    "[ERROR][Cycle %0d] o_active_cols DUT=%0h GOLD=%0h",
                    cycle_count,
                    o_active_cols,
                    gold_active_cols
                );

                error_count =
                    error_count + 1;

            end

            // Compare o_k_size
            if (
                o_k_size
                !==
                gold_k_size[KW-1:0]
            ) begin

                $display(
                    "[ERROR][Cycle %0d] o_k_size DUT=%0h GOLD=%0h",
                    cycle_count,
                    o_k_size,
                    gold_k_size
                );

                error_count =
                    error_count + 1;

            end

            // Compare o_busy
            if (
                o_busy
                !==
                gold_busy[0]
            ) begin

                $display(
                    "[ERROR][Cycle %0d] o_busy DUT=%0h GOLD=%0h",
                    cycle_count,
                    o_busy,
                    gold_busy
                );

                error_count =
                    error_count + 1;

            end

            // Compare o_done
            if (
                o_done
                !==
                gold_done[0]
            ) begin

                $display(
                    "[ERROR][Cycle %0d] o_done DUT=%0h GOLD=%0h",
                    cycle_count,
                    o_done,
                    gold_done
                );

                error_count =
                    error_count + 1;

            end


        end

        // Close Files
        $fclose(
            input_fd
        );

        $fclose(
            golden_fd
        );


        // Final Result

        $display(
            "============================================="
        );

        $display(
            "Total Cycles = %0d",
            cycle_count
        );

        $display(
            "Total Errors = %0d",
            error_count
        );


        if (
            error_count == 0
        ) begin

            $display("TILE CONTROLLER TEST PASS");
            $display("PASS RATE = %0d%%", ((cycle_count-error_count)/cycle_count)*100);

        end

        else begin

            $display("TILE CONTROLLER TEST FAIL");
            $display("PASS RATE = %0d%%", ((cycle_count-error_count)/cycle_count)*100);

        end


        $display(
            "============================================="
        );


        #20;

        $finish;

    end

endmodule
