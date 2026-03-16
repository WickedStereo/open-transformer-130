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
    input logic        action_load,
    input logic        busy,
    input logic [63:0] slot_state_out,
    input logic        dma_cmd_valid,
    input logic        dma_cmd_load,
    input logic [SLOT_BITS-1:0] dma_cmd_slot_id,
    input logic        compute_cmd_valid,
    input logic [SLOT_BITS-1:0] compute_src_slot,
    input logic [SLOT_BITS-1:0] compute_dst_slot,
    input logic        vector_cmd_valid,
    input logic [SLOT_BITS-1:0] vector_src_slot,
    input logic [SLOT_BITS-1:0] vector_dst_slot,
    input logic        dma_done,
    input logic        compute_done,
    input logic        vector_done
);
    localparam SLOT_FREE     = 2'b00;
    localparam SLOT_LOADING  = 2'b01;
    localparam SLOT_RESIDENT = 2'b10;
    localparam SLOT_STORING  = 2'b11;

    logic f_past_valid;
    logic seen_busy;
    logic dma_inflight;
    logic dma_inflight_load;
    logic [SLOT_BITS-1:0] dma_inflight_slot;
    logic vector_inflight;
    logic [SLOT_BITS-1:0] vector_inflight_dst;

    function automatic [1:0] slot_state_for(input logic [SLOT_BITS-1:0] slot_id);
        begin
            slot_state_for = slot_state_out[slot_id * 2 +: 2];
        end
    endfunction

    initial begin
        f_past_valid = 1'b0;
        seen_busy = 1'b0;
        dma_inflight = 1'b0;
        dma_inflight_load = 1'b0;
        dma_inflight_slot = '0;
        vector_inflight = 1'b0;
        vector_inflight_dst = '0;
    end

    always_ff @(posedge clk) begin
        f_past_valid <= 1'b1;

        if (!rst_n) begin
            seen_busy <= 1'b0;
            dma_inflight <= 1'b0;
            dma_inflight_load <= 1'b0;
            dma_inflight_slot <= '0;
            vector_inflight <= 1'b0;
            vector_inflight_dst <= '0;
        end else begin
            if (busy)
                seen_busy <= 1'b1;

            if (dma_cmd_valid) begin
                dma_inflight <= 1'b1;
                dma_inflight_load <= dma_cmd_load;
                dma_inflight_slot <= dma_cmd_slot_id;
            end else if (dma_done) begin
                dma_inflight <= 1'b0;
            end

            if (vector_cmd_valid) begin
                vector_inflight <= 1'b1;
                vector_inflight_dst <= vector_dst_slot;
            end else if (vector_done) begin
                vector_inflight <= 1'b0;
            end

            assert (!(dma_cmd_valid && compute_cmd_valid));
            assert (!(dma_cmd_valid && vector_cmd_valid));
            assert (!(compute_cmd_valid && vector_cmd_valid));

            if (action_ready)
                assert (!busy && enable);

            if (dma_cmd_valid)
                assert (busy);

            if (compute_cmd_valid) begin
                assert (busy);
                assert (slot_state_for(compute_src_slot) == SLOT_RESIDENT);
                assert (slot_state_for(compute_dst_slot) == SLOT_RESIDENT);
            end

            if (vector_cmd_valid) begin
                assert (busy);
                assert (slot_state_for(vector_src_slot) == SLOT_RESIDENT);
            end

            if (f_past_valid && (dma_done || compute_done || vector_done))
                assert ($past(busy));

            if (f_past_valid && $past(rst_n) && $past(dma_cmd_valid) && $past(dma_cmd_load))
                assert (slot_state_for($past(dma_cmd_slot_id)) == SLOT_LOADING);

            if (f_past_valid && $past(rst_n) && $past(dma_cmd_valid) && !$past(dma_cmd_load))
                assert (slot_state_for($past(dma_cmd_slot_id)) == SLOT_STORING);

            if (f_past_valid && $past(rst_n) && $past(dma_inflight && dma_done)) begin
                if ($past(dma_inflight_load))
                    assert (slot_state_for($past(dma_inflight_slot)) == SLOT_RESIDENT);
                else
                    assert (slot_state_for($past(dma_inflight_slot)) == SLOT_FREE);
            end

            if (f_past_valid && $past(rst_n) && $past(vector_cmd_valid))
                assert (slot_state_for($past(vector_dst_slot)) == SLOT_LOADING);

            if (f_past_valid && $past(rst_n) && $past(vector_inflight && vector_done))
                assert (slot_state_for($past(vector_inflight_dst)) == SLOT_RESIDENT);

            if (seen_busy)
                cover (!busy);
        end
    end

endmodule
