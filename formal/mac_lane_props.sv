module mac_lane_props #(
    parameter OPERAND_WIDTH = 8,
    parameter ACCUM_WIDTH   = 32
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

    logic f_past_valid;
    logic [1:0] idle_cycles;

    initial begin
        f_past_valid = 1'b0;
        idle_cycles = '0;
    end

    always_ff @(posedge clk) begin
        f_past_valid <= 1'b1;

        if (!rst_n) begin
            idle_cycles <= '0;
            assert (accum_out == '0);
        end else begin
            assert ($signed(accum_out) >= -(2**(ACCUM_WIDTH-1)));
            assert ($signed(accum_out) <= (2**(ACCUM_WIDTH-1))-1);

            if (op_valid)
                idle_cycles <= '0;
            else if (idle_cycles != 2'd3)
                idle_cycles <= idle_cycles + 2'd1;

            if (idle_cycles == 2'd3)
                cover (!lane_busy);
        end
    end

endmodule
