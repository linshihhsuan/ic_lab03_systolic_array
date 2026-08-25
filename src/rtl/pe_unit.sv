module pe_unit #(

    parameter int DATA_WIDTH    = 32,
    parameter int PRODUCT_WIDTH = 64,
    parameter int ACC_WIDTH     = 71

)(
    // System input
    input logic i_clk,
    input logic i_rst_n,

    // Global control
    // i_step_en 由 input_skew 傳入
    input logic i_step_en,
    input logic i_acc_clear,

    // A stream: left to right
    input logic signed [DATA_WIDTH-1:0]  i_a_data,
    input logic                          i_a_valid,
    output logic signed [DATA_WIDTH-1:0] o_a_data,
    output logic                         o_a_valid,

    // B stream: top to bottom
    input logic signed [DATA_WIDTH-1:0]  i_b_data,
    input logic                          i_b_valid,
    output logic signed [DATA_WIDTH-1:0] o_b_data,
    output logic                         o_b_valid,

    // Output-stationary accumulated result
    output logic signed [ACC_WIDTH-1:0]  o_acc_data
);

    // Internal signals
    logic signed [PRODUCT_WIDTH-1:0] product;
    logic signed [ACC_WIDTH-1:0]     product_ext;

    // 32-bit signed x 32-bit signed -> 64-bit signed
    assign product = $signed(i_a_data) * $signed(i_b_data);

    // Sign extension: 64-bit -> 71-bit
    assign product_ext =
        {{(ACC_WIDTH-PRODUCT_WIDTH){product[PRODUCT_WIDTH-1]}},
         product};

    // A/B registered forwarding
    always_ff @(posedge i_clk) begin
        if (!i_rst_n) begin
            o_a_data  <= '0;
            o_a_valid <= 1'b0;

            o_b_data  <= '0;
            o_b_valid <= 1'b0;
        end
        else if (i_step_en) begin
            o_a_data  <= i_a_data;
            o_a_valid <= i_a_valid;

            o_b_data  <= i_b_data;
            o_b_valid <= i_b_valid;
        end
    end

    // Output-stationary accumulator
    always_ff @(posedge i_clk) begin
        if (!i_rst_n) begin
            o_acc_data <= '0;
        end
        else if (i_acc_clear) begin
            o_acc_data <= '0;
        end
        else if (i_step_en) begin
            if (i_a_valid && i_b_valid) begin
                o_acc_data <= o_acc_data + product_ext;
            end
        end
    end

endmodule
