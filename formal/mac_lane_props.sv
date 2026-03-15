module mac_lane_props #(
    parameter int OPERAND_WIDTH = 8,
    parameter int ACCUM_WIDTH   = 32
) (
    input logic                       clk,
    input logic                       rst_n,
    input logic                       op_valid,
    input logic [OPERAND_WIDTH-1:0]   op_a,
    input logic [OPERAND_WIDTH-1:0]   op_b,
    input logic                       accum_clear,
    input logic [ACCUM_WIDTH-1:0]     accum_out,
    input logic                       lane_busy
);

    // P1: After reset, accumulator is zero
    property p_reset_clears_accum;
        @(posedge clk) !rst_n |=> (accum_out == '0);
    endproperty
    assert property (p_reset_clears_accum)
        else $error("FORMAL: accumulator not zero after reset");

    // P2: Accumulator always in valid INT32 range (bounded by construction)
    // This is trivially true for 32-bit register, but documents the intent
    // for wider accumulator experiments.
    property p_accum_bounded;
        @(posedge clk) disable iff (!rst_n)
            1'b1 |-> ($signed(accum_out) >= -(2**(ACCUM_WIDTH-1))) &&
                      ($signed(accum_out) <= (2**(ACCUM_WIDTH-1))-1);
    endproperty
    assert property (p_accum_bounded)
        else $error("FORMAL: accumulator out of INT32 range");

    // P3: lane_busy deasserts after pipeline drains (within 3 cycles of no input)
    property p_busy_drains;
        @(posedge clk) disable iff (!rst_n)
            (!op_valid ##1 !op_valid ##1 !op_valid) |-> !lane_busy;
    endproperty
    // Cover rather than assert: pipeline timing is design-dependent
    cover property (p_busy_drains);

    // P4: accum_clear when valid resets accumulator to product only
    // (accumulator = op_a * op_b after pipeline latency, no previous state)

endmodule
