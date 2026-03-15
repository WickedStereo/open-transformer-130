module mac_lane_formal;
    (* gclk *) logic clk;

    logic rst_n;
    logic f_past_valid;

    (* anyseq *) logic       op_valid;
    (* anyseq *) logic [7:0] op_a;
    (* anyseq *) logic [7:0] op_b;
    (* anyseq *) logic       accum_clear;

    logic [31:0] accum_out;
    logic        lane_busy;

    initial f_past_valid = 1'b0;

    always_ff @(posedge clk) begin
        f_past_valid <= 1'b1;
    end

    assign rst_n = f_past_valid;

    mac_lane dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .op_valid    (op_valid),
        .op_a        (op_a),
        .op_b        (op_b),
        .accum_clear (accum_clear),
        .accum_out   (accum_out),
        .lane_busy   (lane_busy)
    );

    mac_lane_props props (
        .clk         (clk),
        .rst_n       (rst_n),
        .op_valid    (op_valid),
        .op_a        (op_a),
        .op_b        (op_b),
        .accum_clear (accum_clear),
        .accum_out   (accum_out),
        .lane_busy   (lane_busy)
    );
endmodule
