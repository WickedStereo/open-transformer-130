module attention_stub #(
    parameter int WIDTH = 32
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

    // Placeholder datapath until a real attention pipeline is implemented.
    always_ff @(posedge clk) begin
        if (reset) begin
            valid_out <= 1'b0;
            score_out <= '0;
            value_out <= '0;
        end else begin
            valid_out <= valid_in;
            score_out <= query_in + key_in;
            value_out <= value_in;
        end
    end

endmodule
