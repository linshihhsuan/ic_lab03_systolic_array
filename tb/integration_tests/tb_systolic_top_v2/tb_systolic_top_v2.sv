`timescale 1ns/1ps

module tb_systolic_top_v2;

    // ============================================================
    // DUT 參數設定
    // 必須與目前 systolic_top.sv 的預設參數一致
    // ============================================================

    parameter integer DATA_WIDTH = 32;
    parameter integer ACC_WIDTH  = 71;

    parameter integer S_MAX = 32;

    parameter integer MAX_M = 256;
    parameter integer MAX_K = 108;
    parameter integer MAX_N = 64;

    parameter integer IN_FIFO_DEPTH  = 128;
    parameter integer OUT_FIFO_DEPTH = MAX_M * MAX_N;

    // Matrix dimension port width
    parameter integer MW = $clog2(MAX_M + 1);
    parameter integer KW = $clog2(MAX_K + 1);
    parameter integer NW = $clog2(MAX_N + 1);

    // ============================================================
    // Python input.hex 格式相關參數
    //
    // input.hex 前 7 個 word 為 header：
    //
    // word 0 : MAGIC
    // word 1 : M
    // word 2 : K
    // word 3 : N
    // word 4 : S_ref
    // word 5 : A_words = M*K
    // word 6 : B_words = K*N
    //
    // 後續依序為：
    // A matrix row-major
    // B matrix row-major
    // ============================================================

    parameter integer HEADER_WORDS = 7;

    parameter integer MAX_A_WORDS = MAX_M * MAX_K;
    parameter integer MAX_B_WORDS = MAX_K * MAX_N;
    parameter integer MAX_C_WORDS = MAX_M * MAX_N;

    parameter logic [31:0] MAGIC = 32'h53595341;

    // Simulation timeout
    parameter integer TIMEOUT_CYCLES = 5_000_000;


    // ============================================================
    // Data type
    // ============================================================

    typedef logic signed [DATA_WIDTH-1:0] data_t;
    typedef logic signed [ACC_WIDTH-1:0]  acc_t;


    // ============================================================
    // DUT Interface
    // ============================================================

    logic i_clk;
    logic i_rst_n;

    logic i_start;

    logic [MW-1:0] i_m_size;
    logic [KW-1:0] i_k_size;
    logic [NW-1:0] i_n_size;


    // ------------------------------------------------------------
    // A FIFO Bank write interface
    // ------------------------------------------------------------

    logic [S_MAX-1:0] i_a_wren;

    data_t i_a_wdata [S_MAX];

    logic [S_MAX-1:0] o_a_full;


    // ------------------------------------------------------------
    // B FIFO Bank write interface
    // ------------------------------------------------------------

    logic [S_MAX-1:0] i_b_wren;

    data_t i_b_wdata [S_MAX];

    logic [S_MAX-1:0] o_b_full;


    // ------------------------------------------------------------
    // Result FIFO read interface
    // ------------------------------------------------------------

    logic i_result_rden;

    acc_t o_result_data;

    logic o_result_data_vld;
    logic o_result_empty;
    logic o_result_full;


    // ------------------------------------------------------------
    // DUT status
    // ------------------------------------------------------------

    logic o_busy;
    logic o_done;
    logic o_cfg_error;


    // ============================================================
    // DUT Instance
    // ============================================================

    systolic_top #(
        .DATA_WIDTH     (DATA_WIDTH),
        .ACC_WIDTH      (ACC_WIDTH),
        .S_MAX          (S_MAX),

        .MAX_M          (MAX_M),
        .MAX_K          (MAX_K),
        .MAX_N          (MAX_N),

        .IN_FIFO_DEPTH  (IN_FIFO_DEPTH),
        .OUT_FIFO_DEPTH (OUT_FIFO_DEPTH)
    ) dut (
        .i_clk             (i_clk),
        .i_rst_n           (i_rst_n),

        .i_start           (i_start),

        .i_m_size          (i_m_size),
        .i_k_size          (i_k_size),
        .i_n_size          (i_n_size),

        .i_a_wren          (i_a_wren),
        .i_a_wdata         (i_a_wdata),
        .o_a_full          (o_a_full),

        .i_b_wren          (i_b_wren),
        .i_b_wdata         (i_b_wdata),
        .o_b_full          (o_b_full),

        .i_result_rden     (i_result_rden),

        .o_result_data     (o_result_data),
        .o_result_data_vld (o_result_data_vld),
        .o_result_empty    (o_result_empty),
        .o_result_full     (o_result_full),

        .o_busy            (o_busy),
        .o_done            (o_done),
        .o_cfg_error       (o_cfg_error)
    );


    // ============================================================
    // Vector Memory
    // ============================================================

    // input.hex
    logic [31:0] input_mem [HEADER_WORDS + MAX_A_WORDS + MAX_B_WORDS];

    // golden.hex
    acc_t golden_mem [MAX_C_WORDS];
    // ============================================================
    // Testcase configuration
    // 由 input.hex header 載入
    // ============================================================

    integer case_m;
    integer case_k;
    integer case_n;
    integer case_s;

    integer a_words;
    integer b_words;
    integer c_words;

    // A/B 在 input_mem 中的起始位置
    integer a_base;
    integer b_base;


    // ============================================================
    // Scoreboard / Simulation status
    // ============================================================

    integer result_count;
    integer error_count;
    integer cycle_count;

    logic done_seen;


    // ============================================================
    // Vector file path
    // ============================================================

    string input_hex_path;
    string golden_hex_path;


    // ============================================================
    // Clock Generation
    //
    // Clock period = 10 ns
    // Frequency    = 100 MHz
    // ============================================================

    initial begin
        i_clk = 1'b0;

        forever begin
            #5 i_clk = ~i_clk;
        end
    end


    // ============================================================
    // Task: load_input
    //
    // 功能：
    // 1. 開啟 Python 產生的 input.hex
    // 2. 讀取 header
    // 3. 取得 M/K/N/S_ref
    // 4. 檢查 matrix dimension 是否合法
    // 5. 讀入完整 A/B matrix
    //
    // 若檔案不足，直接 $fatal
    // 避免未初始化資料變成 X 後進入 DUT
    // ============================================================

    task automatic load_input;

        integer fd;
        integer rc;
        integer i;
        integer total;

        begin

            // ----------------------------------------------------
            // 開啟 input.hex
            // ----------------------------------------------------

            fd = $fopen(input_hex_path, "r");

            if (fd == 0) begin
                $fatal(
                    1,
                    "[TB] cannot open %s",
                    input_hex_path
                );
            end


            // ----------------------------------------------------
            // 讀取 Header
            // ----------------------------------------------------

            for (i = 0; i < HEADER_WORDS; i = i + 1) begin

                rc = $fscanf(
                    fd,
                    "%h",
                    input_mem[i]
                );

                if (rc != 1) begin
                    $fatal(
                        1,
                        "[TB] short input header"
                    );
                end
            end


            // ----------------------------------------------------
            // 檢查 MAGIC
            // ----------------------------------------------------

            if (input_mem[0] !== MAGIC) begin
                $fatal(
                    1,
                    "[TB] bad magic"
                );
            end


            // ----------------------------------------------------
            // 解析 Header
            // ----------------------------------------------------

            case_m  = input_mem[1];
            case_k  = input_mem[2];
            case_n  = input_mem[3];
            case_s  = input_mem[4];

            a_words = input_mem[5];
            b_words = input_mem[6];

            c_words = case_m * case_n;


            // ----------------------------------------------------
            // 檢查 M/K/N 是否符合 RTL 支援範圍
            // ----------------------------------------------------

            if (
                (case_m < 1)     ||
                (case_m > MAX_M) ||
                (case_k < 1)     ||
                (case_k > MAX_K) ||
                (case_n < 1)     ||
                (case_n > MAX_N)
            ) begin

                $fatal(
                    1,
                    "[TB] bad dimensions"
                );
            end


            // ----------------------------------------------------
            // 檢查 Python 所算出的 S_ref
            // ----------------------------------------------------

            if (
                (case_s < 1) ||
                (case_s > S_MAX)
            ) begin

                $fatal(
                    1,
                    "[TB] bad S_ref=%0d",
                    case_s
                );
            end


            // ----------------------------------------------------
            // 檢查 A/B matrix word count
            // ----------------------------------------------------

            if (
                (a_words != case_m * case_k) ||
                (b_words != case_k * case_n)
            ) begin

                $fatal(
                    1,
                    "[TB] header word counts mismatch"
                );
            end


            // ----------------------------------------------------
            // 計算 A/B 在 input_mem 中的位置
            // ----------------------------------------------------

            a_base = HEADER_WORDS;
            b_base = HEADER_WORDS + a_words;

            total =
                HEADER_WORDS +
                a_words +
                b_words;


            // ----------------------------------------------------
            // 讀取 A/B Matrix
            // ----------------------------------------------------

            for (
                i = HEADER_WORDS;
                i < total;
                i = i + 1
            ) begin

                rc = $fscanf(
                    fd,
                    "%h",
                    input_mem[i]
                );

                if (rc != 1) begin

                    $fatal(
                        1,
                        "[TB] input ended early at %0d/%0d",
                        i,
                        total
                    );
                end
            end


            // ----------------------------------------------------
            // 關閉檔案
            // ----------------------------------------------------

            $fclose(fd);


            // ----------------------------------------------------
            // 顯示 testcase 資訊
            // ----------------------------------------------------

            $display(
                "[TB] M=%0d K=%0d N=%0d S_ref=%0d",
                case_m,
                case_k,
                case_n,
                case_s
            );

        end

    endtask


    // ============================================================
    // Task: load_golden
    //
    // 功能：
    // 讀取 Python 產生的 golden.hex
    //
    // golden.hex 已經依照 DUT output order 排列：
    //
    // M tile
    //   -> N tile
    //      -> local row
    //         -> local column
    //
    // TB 不自行計算 C = A × B
    // ============================================================

    task automatic load_golden;

        integer fd;
        integer rc;
        integer i;

        begin

            fd = $fopen(
                golden_hex_path,
                "r"
            );

            if (fd == 0) begin

                $fatal(
                    1,
                    "[TB] cannot open %s",
                    golden_hex_path
                );
            end


            // ----------------------------------------------------
            // C matrix 共 M × N 筆
            // ----------------------------------------------------

            for (
                i = 0;
                i < c_words;
                i = i + 1
            ) begin

                rc = $fscanf(
                    fd,
                    "%h",
                    golden_mem[i]
                );

                if (rc != 1) begin

                    $fatal(
                        1,
                        "[TB] golden ended early at %0d/%0d",
                        i,
                        c_words
                    );
                end
            end


            $fclose(fd);


            $display(
                "[TB] golden words=%0d",
                c_words
            );

        end

    endtask


    // ============================================================
    // Task: reset_dut
    //
    // DUT 為 active-low synchronous reset
    // 因此 reset 必須涵蓋數個 posedge
    // ============================================================

    task automatic reset_dut;

        integer l;

        begin

            i_rst_n       = 1'b0;
            i_start       = 1'b0;

            i_m_size      = '0;
            i_k_size      = '0;
            i_n_size      = '0;

            i_a_wren      = '0;
            i_b_wren      = '0;

            i_result_rden = 1'b0;


            // ----------------------------------------------------
            // 初始化 A/B input data
            // ----------------------------------------------------

            for (
                l = 0;
                l < S_MAX;
                l = l + 1
            ) begin

                i_a_wdata[l] = '0;
                i_b_wdata[l] = '0;

            end


            // ----------------------------------------------------
            // Reset 維持 5 個 Clock
            // ----------------------------------------------------

            repeat (5) begin
                @(posedge i_clk);
            end


            // 在 negedge 解除 reset
            // 避免與 DUT posedge sampling race
            @(negedge i_clk);

            i_rst_n = 1'b1;

        end

    endtask


    // ============================================================
    // Task: feed_inputs
    //
    // 功能：
    // 將 Python 產生的 row-major A/B matrix
    // 重新依照 DUT tile / FIFO lane 介面送入
    //
    // Tile traversal：
    //
    // M tile = outer loop
    // N tile = inner loop
    //
    // 每一個 tile：
    //   A lane r -> A[m_base+r][k]
    //   B lane c -> B[k][n_base+c]
    //
    // 注意：
    // TB 只做 input scheduling
    // 不在 SystemVerilog 內計算 golden matrix
    // ============================================================

    task automatic feed_inputs;

        integer mb;
        integer nb;
        integer kk;

        integer r;
        integer c;

        integer ar;
        integer ac;

        logic can_write;

        begin

            // ----------------------------------------------------
            // 初始 tile index
            // ----------------------------------------------------

            mb = 0;
            nb = 0;
            kk = 0;


            // ----------------------------------------------------
            // M dimension 為 outer loop
            // ----------------------------------------------------

            while (mb < case_m) begin

                // ------------------------------------------------
                // Edge tile active row 數量
                // ------------------------------------------------

                ar =
                    ((case_m - mb) < case_s)
                    ? (case_m - mb)
                    : case_s;


                // ------------------------------------------------
                // Edge tile active column 數量
                // ------------------------------------------------

                ac =
                    ((case_n - nb) < case_s)
                    ? (case_n - nb)
                    : case_s;


                // 在 negedge drive input
                @(negedge i_clk);


                // ------------------------------------------------
                // Default：不寫 FIFO
                // ------------------------------------------------

                i_a_wren = '0;
                i_b_wren = '0;


                for (
                    r = 0;
                    r < S_MAX;
                    r = r + 1
                ) begin

                    i_a_wdata[r] = '0;
                    i_b_wdata[r] = '0;

                end


                // ------------------------------------------------
                // 確認所有需要寫入的 lane 都還有空間
                //
                // 若任一 required FIFO full，
                // 本 cycle 全部不送，維持 lockstep
                // ------------------------------------------------

                can_write = 1'b1;


                for (
                    r = 0;
                    r < ar;
                    r = r + 1
                ) begin

                    if (o_a_full[r]) begin
                        can_write = 1'b0;
                    end

                end


                for (
                    c = 0;
                    c < ac;
                    c = c + 1
                ) begin

                    if (o_b_full[c]) begin
                        can_write = 1'b0;
                    end

                end


                // ------------------------------------------------
                // FIFO 可寫時送入一個 K step
                // ------------------------------------------------

                if (can_write) begin

                    // --------------------------------------------
                    // A Matrix
                    //
                    // row-major index:
                    //
                    // A[row][k]
                    // = A[row * K + k]
                    // --------------------------------------------

                    for (
                        r = 0;
                        r < ar;
                        r = r + 1
                    ) begin

                        i_a_wren[r] = 1'b1;

                        i_a_wdata[r] =
                            $signed(
                                input_mem[
                                    a_base +
                                    (mb + r) * case_k +
                                    kk
                                ]
                            );

                    end


                    // --------------------------------------------
                    // B Matrix
                    //
                    // row-major index:
                    //
                    // B[k][col]
                    // = B[k * N + col]
                    // --------------------------------------------

                    for (
                        c = 0;
                        c < ac;
                        c = c + 1
                    ) begin

                        i_b_wren[c] = 1'b1;

                        i_b_wdata[c] =
                            $signed(
                                input_mem[
                                    b_base +
                                    kk * case_n +
                                    (nb + c)
                                ]
                            );

                    end


                    // --------------------------------------------
                    // K dimension 前進
                    // --------------------------------------------

                    if (kk == case_k - 1) begin

                        kk = 0;


                        // ----------------------------------------
                        // 完成目前 N tile
                        // ----------------------------------------

                        if (
                            nb + case_s >= case_n
                        ) begin

                            // 回到 N = 0
                            nb = 0;

                            // 換下一個 M tile
                            mb = mb + case_s;

                        end
                        else begin

                            // 下一個 N tile
                            nb = nb + case_s;

                        end

                    end
                    else begin

                        kk = kk + 1;

                    end

                end

            end


            // ----------------------------------------------------
            // 所有 input 送完
            // ----------------------------------------------------

            @(negedge i_clk);

            i_a_wren = '0;
            i_b_wren = '0;


            $display(
                "[TB] all input tiles queued"
            );

        end

    endtask


    // ============================================================
    // Scoreboard
    //
    // DUT 每當 o_result_data_vld = 1
    // 就把輸出與 Python golden 比較
    //
    // SystemVerilog 不自行計算 expected C
    // ============================================================

    always @(negedge i_clk) begin

        if (!i_rst_n) begin

            result_count <= 0;
            error_count  <= 0;
            done_seen    <= 1'b0;

        end
        else begin

            // ----------------------------------------------------
            // DUT configuration error
            // ----------------------------------------------------

            if (o_cfg_error) begin

                $fatal(
                    1,
                    "[TB] o_cfg_error asserted"
                );

            end


            // ----------------------------------------------------
            // DUT computation complete
            // ----------------------------------------------------

            if (o_done) begin

                done_seen <= 1'b1;

                $display(
                    "[TB] o_done at result_count=%0d",
                    result_count
                );

            end


            // ----------------------------------------------------
            // Result comparison
            // ----------------------------------------------------

            if (o_result_data_vld) begin

                // DUT 輸出超過 M×N 筆
                if (
                    result_count >= c_words
                ) begin

                    $error(
                        "[TB] extra result %0d",
                        $signed(o_result_data)
                    );

                    error_count <=
                        error_count + 1;

                end


                // DUT result != Python golden
                else if (
                    o_result_data !==
                    golden_mem[result_count]
                ) begin

                    $error(
                        "[TB] result[%0d] got %0d expected %0d",
                        result_count,
                        $signed(o_result_data),
                        $signed(
                            golden_mem[result_count]
                        )
                    );

                    error_count <=
                        error_count + 1;

                end


                // 下一筆 expected result
                result_count <=
                    result_count + 1;

            end

        end

    end


    // ============================================================
    // Result FIFO Reader
    //
    // 只要 Output FIFO 非空，
    // Testbench 就送出 read enable
    // ============================================================

    always @(negedge i_clk) begin

        if (
            !i_rst_n ||
            (result_count >= c_words)
        ) begin

            i_result_rden = 1'b0;

        end
        else begin

            i_result_rden =
                !o_result_empty;

        end

    end


    // ============================================================
    // Simulation Timeout
    //
    // 防止 DUT deadlock 或 simulation 無限等待
    // ============================================================

    always @(posedge i_clk) begin

        if (!i_rst_n) begin

            cycle_count <= 0;

        end
        else begin

            cycle_count <=
                cycle_count + 1;


            if (
                cycle_count >
                TIMEOUT_CYCLES
            ) begin

                $fatal(
                    1,
                    "[TB] timeout results=%0d/%0d",
                    result_count,
                    c_words
                );

            end

        end

    end


    // ============================================================
    // Main Test Sequence
    // ============================================================

    initial begin

        // --------------------------------------------------------
        // 初始化 scoreboard
        // --------------------------------------------------------

        result_count = 0;
        error_count  = 0;
        cycle_count  = 0;

        done_seen = 1'b0;


        // --------------------------------------------------------
        // 預設 vector file path
        // --------------------------------------------------------

        input_hex_path  = "input.hex";
        golden_hex_path = "golden.hex";


        // --------------------------------------------------------
        // 支援 XSim PlusArgs
        //
        // 例如：
        //
        // +INPUT_HEX=D:/vectors/input.hex
        // +GOLDEN_HEX=D:/vectors/golden.hex
        // --------------------------------------------------------

        if (
            !$value$plusargs(
                "INPUT_HEX=%s",
                input_hex_path
            )
        ) begin

            input_hex_path =
                "input.hex";

        end


        if (
            !$value$plusargs(
                "GOLDEN_HEX=%s",
                golden_hex_path
            )
        ) begin

            golden_hex_path =
                "golden.hex";

        end


        $display(
            "[TB] input=%s golden=%s",
            input_hex_path,
            golden_hex_path
        );


        // --------------------------------------------------------
        // 載入 Python vectors
        // --------------------------------------------------------

        load_input();
        load_golden();


        // --------------------------------------------------------
        // Reset DUT
        // --------------------------------------------------------

        reset_dut();


        // --------------------------------------------------------
        // 設定 GEMM dimension
        // --------------------------------------------------------

        i_m_size = case_m;
        i_k_size = case_k;
        i_n_size = case_n;


        // --------------------------------------------------------
        // Background thread:
        // 持續將 A/B data 送入 FIFO Bank
        // --------------------------------------------------------

        fork
            feed_inputs();
        join_none


        // --------------------------------------------------------
        // 啟動 DUT
        // --------------------------------------------------------

        @(negedge i_clk);

        i_start = 1'b1;


        @(negedge i_clk);

        i_start = 1'b0;


        // --------------------------------------------------------
        // 等待：
        //
        // 1. DUT o_done
        // 2. 所有 M×N result 都已讀出
        // --------------------------------------------------------

        wait (
            done_seen &&
            (result_count >= c_words)
        );


        // 多等待幾個 clock
        // 確保最後 transaction 完整結束
        repeat (5) begin
            @(posedge i_clk);
        end


        // --------------------------------------------------------
        // Test Summary
        // --------------------------------------------------------

        $display(
            "[TB] checked=%0d errors=%0d",
            result_count,
            error_count
        );


        // --------------------------------------------------------
        // PASS / FAIL
        // --------------------------------------------------------

        if (
            (error_count == 0) &&
            (result_count == c_words)
        ) begin

            $display(
                "[PASS] systolic_top matches Python golden"
            );

        end
        else begin

            $fatal(
                1,
                "[FAIL]"
            );

        end


        $finish;

    end


endmodule