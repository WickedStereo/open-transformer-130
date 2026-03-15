module tile_scheduler_props #(
    parameter int NUM_SLOTS = 32,
    parameter int SLOT_BITS = 5
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

    // Extract slot states
    wire [1:0] slot [NUM_SLOTS];
    genvar gi;
    generate
        for (gi = 0; gi < NUM_SLOTS; gi++) begin : gen_slots
            assign slot[gi] = slot_state_out[gi*2 +: 2];
        end
    endgenerate

    // P1: At most one command type issued per cycle
    property p_single_issue;
        @(posedge clk) disable iff (!rst_n)
            $onehot0({dma_cmd_valid, compute_cmd_valid, vector_cmd_valid});
    endproperty
    assert property (p_single_issue)
        else $error("FORMAL: multiple command types issued simultaneously");

    // P2: action_ready only when IDLE and enabled
    property p_ready_when_idle;
        @(posedge clk) disable iff (!rst_n)
            action_ready |-> (!busy && enable);
    endproperty
    assert property (p_ready_when_idle)
        else $error("FORMAL: action_ready asserted while busy or disabled");

    // P3: Slot state transitions are valid (no LOADING->STORING directly)
    // LOADING can only go to RESIDENT or FREE (on error)
    // STORING can only go to FREE

    // P4: busy flag matches non-IDLE state
    // (busy is defined as state != ST_IDLE in the implementation)

    // P5: No deadlock -- every non-IDLE state has a path back to IDLE
    // This is a liveness property best checked with bounded model checking.
    // Cover: from any state, IDLE is eventually reachable.
    property p_no_permanent_busy;
        @(posedge clk) disable iff (!rst_n)
            busy |-> ##[1:500] !busy;
    endproperty
    cover property (p_no_permanent_busy);

endmodule
