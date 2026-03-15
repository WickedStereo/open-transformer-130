module scratchpad #(
    parameter int NUM_BANKS     = 8,
    parameter int BANK_SIZE     = 16384,  // bytes per bank (16 KiB)
    parameter int BANK_ADDR_W   = 14,     // log2(BANK_SIZE)
    parameter int DATA_W        = 8
) (
    input  logic                                    clk,
    input  logic                                    rst_n,

    // Per-bank control (packed for Verilator/cocotb compatibility)
    input  logic [NUM_BANKS-1:0]                    bank_en,
    input  logic [NUM_BANKS-1:0]                    bank_wen,
    input  logic [NUM_BANKS*BANK_ADDR_W-1:0]        bank_addr,
    input  logic [NUM_BANKS*DATA_W-1:0]             bank_wdata,
    output logic [NUM_BANKS*DATA_W-1:0]             bank_rdata
);

    genvar gi;
    generate
        for (gi = 0; gi < NUM_BANKS; gi++) begin : gen_banks
            logic [DATA_W-1:0] mem [0:BANK_SIZE-1];

            wire [BANK_ADDR_W-1:0] addr_i = bank_addr[gi*BANK_ADDR_W +: BANK_ADDR_W];
            wire [DATA_W-1:0]      wd_i   = bank_wdata[gi*DATA_W +: DATA_W];

            always_ff @(posedge clk) begin
                if (bank_en[gi]) begin
                    if (bank_wen[gi])
                        mem[addr_i] <= wd_i;
                    else
                        bank_rdata[gi*DATA_W +: DATA_W] <= mem[addr_i];
                end
            end
        end
    endgenerate

    logic _unused;
    assign _unused = &{1'b0, rst_n};

endmodule
