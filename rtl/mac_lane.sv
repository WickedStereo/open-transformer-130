module mac_lane #(
    parameter OPERAND_WIDTH = 8,
    parameter ACCUM_WIDTH   = 32
) (
    input  logic                       clk,
    input  logic                       rst_n,
    input  logic                       op_valid,
    input  logic [OPERAND_WIDTH-1:0]   op_a,
    input  logic [OPERAND_WIDTH-1:0]   op_b,
    input  logic                       accum_clear,
    output logic [ACCUM_WIDTH-1:0]     accum_out,
    output logic                       lane_busy
);

    localparam PROD_WIDTH = 2 * OPERAND_WIDTH;

    // ── Stage 1: Operand capture ──
    logic                     s1_valid;
    logic [OPERAND_WIDTH-1:0] s1_a, s1_b;
    logic                     s1_clear;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            s1_valid <= 1'b0;
            s1_a     <= '0;
            s1_b     <= '0;
            s1_clear <= 1'b0;
        end else begin
            s1_valid <= op_valid;
            s1_a     <= op_a;
            s1_b     <= op_b;
            s1_clear <= accum_clear;
        end
    end

    // ── Stage 2: Signed multiply (8×8 → 16-bit product) ──
    logic                    s2_valid;
    logic [PROD_WIDTH-1:0]   s2_product;
    logic                    s2_clear;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            s2_valid   <= 1'b0;
            s2_product <= '0;
            s2_clear   <= 1'b0;
        end else begin
            s2_valid   <= s1_valid;
            s2_product <= $signed(s1_a) * $signed(s1_b);
            s2_clear   <= s1_clear;
        end
    end

    // ── Stage 3: Accumulate with saturation ──
    logic [ACCUM_WIDTH-1:0] accum_r;

    // Wider arithmetic for overflow detection (ACCUM_WIDTH+1 bits).
    // Both operands are manually sign-extended so unsigned addition
    // produces the correct two's-complement bit pattern.
    logic [ACCUM_WIDTH:0] wide_base;
    logic [ACCUM_WIDTH:0] wide_prod;
    logic [ACCUM_WIDTH:0] wide_sum;

    always_comb begin
        if (s2_clear)
            wide_base = '0;
        else
            wide_base = {accum_r[ACCUM_WIDTH-1], accum_r};

        wide_prod = {{(ACCUM_WIDTH - PROD_WIDTH + 1){s2_product[PROD_WIDTH-1]}}, s2_product};
        wide_sum  = wide_base + wide_prod;
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            accum_r <= '0;
        end else if (s2_valid) begin
            if (wide_sum[ACCUM_WIDTH] != wide_sum[ACCUM_WIDTH-1]) begin
                if (wide_sum[ACCUM_WIDTH])
                    accum_r <= {1'b1, {(ACCUM_WIDTH-1){1'b0}}};   // INT32_MIN
                else
                    accum_r <= {1'b0, {(ACCUM_WIDTH-1){1'b1}}};   // INT32_MAX
            end else begin
                accum_r <= wide_sum[ACCUM_WIDTH-1:0];
            end
        end else if (s2_clear) begin
            accum_r <= '0;
        end
    end

    assign accum_out = accum_r;
    assign lane_busy = s1_valid | s2_valid;

endmodule
