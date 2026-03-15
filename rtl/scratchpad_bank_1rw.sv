module scratchpad_bank_1rw #(
    parameter BANK_SIZE   = 16384,
    parameter BANK_ADDR_W = 14,
    parameter DATA_W      = 8
) (
    input  logic                   clk,
    input  logic                   en,
    input  logic                   wen,
    input  logic [BANK_ADDR_W-1:0] addr,
    input  logic [DATA_W-1:0]      wdata,
    output logic [DATA_W-1:0]      rdata
);

    // This wrapper is the intended swap point for an OpenRAM-style 1RW macro.
    logic [DATA_W-1:0] mem [0:BANK_SIZE-1];

    always_ff @(posedge clk) begin
        if (en) begin
            if (wen)
                mem[addr] <= wdata;
            else
                rdata <= mem[addr];
        end
    end

endmodule
