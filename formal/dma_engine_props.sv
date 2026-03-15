module dma_engine_props #(
    parameter NUM_BANKS   = 8,
    parameter BANK_ADDR_W = 14,
    parameter SLOT_BITS   = 5
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
    input logic                     bus_req
);

    logic f_past_valid;
    logic accepted_cmd;

    initial begin
        f_past_valid = 1'b0;
        accepted_cmd = 1'b0;
    end

    always_ff @(posedge clk) begin
        f_past_valid <= 1'b1;

        if (!rst_n) begin
            accepted_cmd <= 1'b0;
        end else begin
            if (cmd_valid && cmd_ready)
                accepted_cmd <= 1'b1;
            if (done || error)
                accepted_cmd <= 1'b0;

            if (scratch_req != '0)
                assert ((scratch_req & (scratch_req - 1'b1)) == '0);

            if (cmd_ready)
                assert ((scratch_req == '0) && !bus_req);

            assert (!(done && error));

            if (f_past_valid && $past(done))
                assert (!done);

            if (f_past_valid && $past(cmd_valid && cmd_ready
                                      && (cmd_byte_count == 13'd0 || cmd_byte_count > 13'd4096)))
                assert (error);

            if (accepted_cmd)
                cover (done || error);
        end
    end

    logic _unused;
    assign _unused = &{1'b0, cmd_slot_id};

endmodule
