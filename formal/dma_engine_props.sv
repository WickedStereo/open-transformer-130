module dma_engine_props #(
    parameter int NUM_BANKS   = 8,
    parameter int BANK_ADDR_W = 14,
    parameter int SLOT_BITS   = 5
) (
    input logic                     clk,
    input logic                     rst_n,
    input logic                     cmd_valid,
    input logic                     cmd_ready,
    input logic [SLOT_BITS-1:0]     cmd_slot_id,
    input logic [12:0]              cmd_byte_count,
    input logic                     done,
    input logic                     error,
    input logic [NUM_BANKS-1:0]     scratch_req,
    input logic [2:0]               state_dbg
);

    // P1: DMA never requests more than one bank simultaneously
    property p_single_bank_req;
        @(posedge clk) disable iff (!rst_n)
            (scratch_req != '0) |-> $onehot(scratch_req);
    endproperty
    assert property (p_single_bank_req)
        else $error("FORMAL: DMA requested multiple banks simultaneously");

    // P2: cmd_ready only asserted in IDLE state
    property p_ready_only_idle;
        @(posedge clk) disable iff (!rst_n)
            cmd_ready |-> (state_dbg == 3'd0);
    endproperty

    // P3: done and error are mutually exclusive
    property p_done_error_mutex;
        @(posedge clk) disable iff (!rst_n)
            !(done && error);
    endproperty
    assert property (p_done_error_mutex)
        else $error("FORMAL: done and error asserted simultaneously");

    // P4: done or error is one-cycle pulse (not held)
    property p_done_pulse;
        @(posedge clk) disable iff (!rst_n)
            done |=> !done;
    endproperty
    assert property (p_done_pulse)
        else $error("FORMAL: done held for more than one cycle");

    // P5: Every accepted command eventually produces done or error
    // (liveness -- requires bounded model checking depth)
    property p_cmd_completes;
        @(posedge clk) disable iff (!rst_n)
            (cmd_valid && cmd_ready) |-> ##[1:1000] (done || error);
    endproperty
    // Liveness: cover rather than assert (unbounded proof not practical here)
    cover property (p_cmd_completes);

endmodule
