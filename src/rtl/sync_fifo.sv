// verilog_lint: waive-start
//////////////////////////////////////////////////////////////////////////////////
// Company: AGILAB
// Engineer: Undergraduate Student
//
// Create Date: 2026/08/20 21:56:53
// Design Type: RTL (Synthesizable Circuit)
// Design Name: ic_lab03_systolic_array
// Module Name: sync_fifo
// Project Name:
// Target Devices:
// Tool Versions:
// Description: 建立一個同步 FIFO 模組。
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

module sync_fifo #(

    parameter int unsigned DATA_WIDTH = 32,
    parameter int unsigned DEPTH      = 8,

    // 必須能表示 0 ~ DEPTH
    parameter int unsigned COUNT_WIDTH = (DEPTH <= 1) ? 1 : $clog2(DEPTH + 1)

)(

    // System input
    input logic i_clk,
    input logic i_rst_n,

    // Write interface
    input logic i_wren,
    input logic [DATA_WIDTH-1:0] i_data,
    output logic o_full,

    // Read interface
    input logic i_rden,
    output logic [DATA_WIDTH-1:0] o_data,
    output logic o_data_vld,

    // Status
    output logic o_empty,
    output logic [COUNT_WIDTH-1:0] o_count

);

    // Local parameters
    localparam int unsigned PtrWidth = (DEPTH <= 1) ? 1 : $clog2(DEPTH);

    // Memory
    logic [DATA_WIDTH-1:0] mem [DEPTH];

    // Internal registers
    logic [PtrWidth-1:0] wr_ptr_r;
    logic [PtrWidth-1:0] rd_ptr_r;
    logic [COUNT_WIDTH-1:0] count_r;

    logic write_accept;
    logic read_accept;


    // Status logic
    always_comb begin
        o_empty = (count_r == 0);
        o_full  = (count_r == DEPTH);
        o_count = count_r;
    end


    // Request acceptance
    // Write request while FULL  -> rejected
    // Read request while EMPTY  -> rejected

    always_comb begin
        write_accept = i_wren && !o_full;
        read_accept  = i_rden && !o_empty;
    end


    // Circular pointer increment
    // 支援非 2^N DEPTH
    function automatic logic [PtrWidth-1:0] ptr_inc(
        input logic [PtrWidth-1:0] ptr
    );
        begin
            if (ptr == DEPTH - 1)
                ptr_inc = '0;
            else
                ptr_inc = ptr + 1'b1;
        end
    endfunction


    // Sequential logic
    always_ff @(posedge i_clk) begin
        // Reset signal
        if (!i_rst_n) begin
            wr_ptr_r   <= '0;
            rd_ptr_r   <= '0;
            count_r    <= '0;

            o_data     <= '0;
            o_data_vld <= 1'b0;
        end
        else begin

            // Default:
            // o_data_vld 是 pulse-like valid
            o_data_vld <= 1'b0;

            // Write
            if (write_accept) begin
                mem[wr_ptr_r] <= i_data;
                wr_ptr_r      <= ptr_inc(wr_ptr_r);
            end

            // Read
            if (read_accept) begin
                o_data       <= mem[rd_ptr_r];
                rd_ptr_r     <= ptr_inc(rd_ptr_r);
                o_data_vld   <= 1'b1;
            end

            // FIFO counter
            unique case ({write_accept, read_accept})

                // Write only
                2'b10: begin
                    count_r <= count_r + 1'b1;
                end

                // Read only
                2'b01: begin
                    count_r <= count_r - 1'b1;
                end

                // Simultaneous read/write OR no operation
                2'b11, 2'b00: begin
                    count_r <= count_r;
                end

                default: begin
                    count_r <= count_r;
                end

            endcase
        end
    end

endmodule
