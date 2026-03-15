module tile_scheduler_props #(
    parameter NUM_SLOTS = 32,
    parameter SLOT_BITS = 5
) (
    input logic        clk,
    input logic        rst_n,
    input logic        enable,
    input logic        action_valid,
    input logic        action_ready,
    input logic [2:0]  action_type,
    input logic        busy,
    input logic [63:0] slot_state_out,
    input logic        dma_cmd_valid,
    input logic        compute_cmd_valid,
    input logic        vector_cmd_valid,
    input logic        dma_done,
    input logic        compute_done,
    input logic        vector_done
);
    logic seen_busy;

    initial seen_busy = 1'b0;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            seen_busy <= 1'b0;
        end else begin
            if (busy)
                seen_busy <= 1'b1;

            assert (!(dma_cmd_valid && compute_cmd_valid));
            assert (!(dma_cmd_valid && vector_cmd_valid));
            assert (!(compute_cmd_valid && vector_cmd_valid));

            if (action_ready)
                assert (!busy && enable);

            if (seen_busy)
                cover (!busy);
        end
    end

    logic _unused;
    assign _unused = &{1'b0, action_valid, action_type, slot_state_out,
                       dma_done, compute_done, vector_done};

endmodule
