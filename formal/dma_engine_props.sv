module dma_engine_props #(
    parameter NUM_BANKS   = 8,
    parameter BANK_ADDR_W = 14,
    parameter SLOT_BITS   = 5
) (
    input logic                     clk,
    input logic                     rst_n,
    input logic                     cmd_valid,
    input logic                     cmd_ready,
    input logic                     cmd_load,
    input logic [SLOT_BITS-1:0]     cmd_slot_id,
    input logic [12:0]              cmd_byte_count,
    input logic                     done,
    input logic                     error,
    input logic [31:0]              bytes_moved,
    input logic [NUM_BANKS-1:0]     scratch_req,
    input logic                     bus_req,
    input logic                     bus_wen
);

    logic f_past_valid;
    logic accepted_cmd;
    logic accepted_load;
    logic accepted_valid_len;
    logic [12:0] accepted_bytes;

    initial begin
        f_past_valid = 1'b0;
        accepted_cmd = 1'b0;
        accepted_load = 1'b0;
        accepted_valid_len = 1'b0;
        accepted_bytes = '0;
    end

    always_ff @(posedge clk) begin
        f_past_valid <= 1'b1;

        if (!rst_n) begin
            accepted_cmd <= 1'b0;
            accepted_load <= 1'b0;
            accepted_valid_len <= 1'b0;
            accepted_bytes <= '0;
        end else begin
            if (cmd_valid && cmd_ready) begin
                accepted_cmd <= 1'b1;
                accepted_load <= cmd_load;
                accepted_valid_len <= (cmd_byte_count != 13'd0 && cmd_byte_count <= 13'd4096);
                accepted_bytes <= cmd_byte_count;
            end
            if (done || error) begin
                accepted_cmd <= 1'b0;
                accepted_valid_len <= 1'b0;
            end

            if (scratch_req != '0)
                assert ((scratch_req & (scratch_req - 1'b1)) == '0);

            if (cmd_ready)
                assert ((scratch_req == '0) && !bus_req);

            if (accepted_cmd)
                assert (!((scratch_req != '0) && bus_req));

            if (accepted_cmd && bus_req)
                assert (bus_wen == !accepted_load);

            if (accepted_cmd && accepted_valid_len) begin
                assert (bytes_moved <= {19'd0, accepted_bytes});
                assert (!error);
            end

            assert (!(done && error));

            if (f_past_valid && $past(rst_n) && $past(done))
                assert (!done);

            if (f_past_valid && $past(rst_n)
                              && $past(cmd_valid && cmd_ready
                                       && (cmd_byte_count == 13'd0 || cmd_byte_count > 13'd4096)))
                assert (error);

            if (done && accepted_valid_len)
                assert (bytes_moved == {19'd0, accepted_bytes});

            if (accepted_cmd && accepted_valid_len)
                cover (done || error);
        end
    end

    logic _unused;
    assign _unused = &{1'b0, cmd_slot_id};

endmodule
