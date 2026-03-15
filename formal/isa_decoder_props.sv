module isa_decoder_props (
    input logic        clk,
    input logic        rst_n,
    input logic        desc_valid,
    input logic [63:0] desc_data,
    input logic        desc_consumed,
    input logic        action_valid,
    input logic        action_ready,
    input logic [2:0]  action_type,
    input logic        fault_valid,
    input logic        fault_active,
    input logic        fault_clear
);

    wire [7:0] opcode  = desc_data[63:56];
    wire [3:0] reserved = desc_data[3:0];
    wire [7:0] dst_raw = desc_data[47:40];
    wire [7:0] src_raw = desc_data[39:32];
    logic f_past_valid;

    initial f_past_valid = 1'b0;

    always_ff @(posedge clk) begin
        f_past_valid <= 1'b1;

        if (!rst_n) begin
            // nothing
        end else begin
            if (f_past_valid && $past(rst_n) && $past(fault_active) && !$past(fault_clear)) begin
                assert (!fault_valid);
                if (desc_consumed)
                    assert ($past(action_valid && action_ready));
            end

            if (f_past_valid && $past(rst_n) && $past(fault_active && fault_clear))
                assert (!fault_active);

            if (desc_consumed)
                assert (fault_valid
                        || (f_past_valid && $past(rst_n) && $past(action_valid && action_ready)));

            if (f_past_valid && $past(rst_n)
                              && $past(desc_valid && !fault_active && !action_valid
                                       && opcode > 8'h07 && reserved == 4'd0))
                assert (fault_active || fault_valid || fault_clear);

            if (f_past_valid && $past(rst_n)
                              && $past(desc_valid && !fault_active && !action_valid && reserved != 4'd0))
                assert (fault_active || fault_valid || fault_clear);

            if (f_past_valid && $past(rst_n)
                              && $past(desc_valid && !fault_active && !action_valid && opcode <= 8'h07
                                      && reserved == 4'd0 && dst_raw < 8'd32 && src_raw < 8'd32))
                assert (action_valid || desc_consumed);
        end
    end

endmodule
