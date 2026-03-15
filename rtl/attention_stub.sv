module attention_stub #(
    parameter WIDTH = 32
) (
    input  logic             clk,
    input  logic             reset,
    input  logic             valid_in,
    input  logic [WIDTH-1:0] query_in,
    input  logic [WIDTH-1:0] key_in,
    input  logic [WIDTH-1:0] value_in,
    output logic             valid_out,
    output logic [WIDTH-1:0] score_out,
    output logic [WIDTH-1:0] value_out
);

    logic unused_inputs;
    assign unused_inputs = clk ^ ^key_in;

    // Keep the scaffold physically simple so the OpenLane smoke path stays fast.
    always_comb begin
        if (reset) begin
            valid_out = 1'b0;
            score_out = '0;
            value_out = '0;
        end else begin
            valid_out = valid_in;
            score_out = query_in;
            value_out = value_in;
        end
    end

endmodule
